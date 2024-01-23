// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IDam} from "./interfaces/IDam.sol";
import {PercentageMath} from "./libraries/PercentageMath.sol";

/**
 * @title Dam
 * @dev Implements a performance and growth-based program designed to reward projects within the ecosystem.
 *      This contract manages yield generation and distribution, aligning with the strategic goals
 *      of fostering ecosystem development and project growth. It handles deposits, withdrawal,
 *      and yield distribution, operating in defined rounds with specific configurations.
 */
contract Dam is IDam, Ownable {
    using SafeERC20 for IERC20;
    using PercentageMath for uint256;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /* ============ Structs ============ */

    struct Upstream {
        uint256 period; // period of the round
        /**
         * @dev ratio of the yield that goes to the treasury, expressed in BP(basis points).
         * 10000 - reinvestmentRatio = ratio of the yield that goes to the Embankment
         */
        uint16 reinvestmentRatio;
        /**
         * @dev ratio of the generated yield in Embankment that goes to the projects who registered for the auto stream, expressed in BP(basis points).
         * 10000 - autoStreamRatio = communityStreamRatio(voting)
         */
        uint16 autoStreamRatio;
        bool flowing; // if false, next round will not be started
    }

    struct Round {
        uint16 id;
        bool ongoing;
        uint256 startTime;
        uint256 endTime;
    }

    struct Withdrawal {
        uint256 amount;
        address receiver;
    }

    /* ============ Constants ============ */

    uint16 constant PERCENTAGE_FACTOR = 1e4;

    /* ============ Immutables ============ */

    IERC20 public immutable ybToken; // Yield Bearing Token
    IERC4626 public immutable embankment; // where the principal and generated yield will be stored

    /* ============ State Variables ============ */

    Upstream public upstream; // configs
    Round public round;
    Withdrawal public withdrawal; // scheduled withdrawal

    address public oracle; // address of oracle which provides the result data for the round
    uint256 public fund; // principal amount of the deposited ybToken

    /* ============ Modifiers ============ */

    /// @dev only the owner and oracle can call this function
    modifier onlyOwnerAndOracle() {
        address sender = _msgSender();
        if (sender != owner() && sender != oracle) revert OwnableUnauthorizedAccount(sender);
        _;
    }

    /* ============ Constructor ============ */

    constructor(IERC20 ybToken_, IERC4626 embankment_) Ownable(_msgSender()) {
        ybToken = ybToken_;
        embankment = embankment_;
    }

    /* ============ External Functions ============ */

    /**
     * @dev Starts the DAM operation with specified parameters.
     * @param amount The amount of funds that will be the source of yield.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested back into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     */
    function operateDam(uint256 amount, uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio)
        external
        onlyOwner
    {
        _operateDam(amount, period, reinvestmentRatio, autoStreamRatio);
    }

    /**
     * @dev Starts the DAM operation with specified parameters via permit function.
     * see: https://eips.ethereum.org/EIPS/eip-2612 and https://eips.ethereum.org/EIPS/eip-713
     * @param amount The amount of funds that will be the source of yield.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested back into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     * @param deadline The deadline timestamp that the permit is valid.
     * @param v Part of the signature (v value).
     * @param r Part of the signature (r value).
     * @param s Part of the signature (s value).
     */
    function operateDamWithPermit(
        uint256 amount,
        uint256 period,
        uint16 reinvestmentRatio,
        uint16 autoStreamRatio,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyOwner {
        IERC20Permit(address(ybToken)).permit(_msgSender(), address(this), amount, deadline, v, r, s);
        _operateDam(amount, period, reinvestmentRatio, autoStreamRatio);
    }

    /**
     * @dev Decommissions the DAM and schedules a withdrawal to the specified receiver.
     * 			All remaining funds in the DAM will be sent to the receiver.
     * @param receiver The address to receive the remaining funds in the DAM.
     */
    function decommissionDam(address receiver) external onlyOwner {
        if (!upstream.flowing) revert DamNotOperating();
        _scheduleWithdrawal(type(uint256).max, receiver);
        upstream.flowing = false;

        emit DecommissionDam();
    }

    /**
     * @dev Ends the current round, verifies data integrity, and processes withdrawal if any.
     * @param data Data required to finalize the round.
     * 				It includes the following:
     * 				- List of addresses to receive grants
     * 				- List of grant proportions
     * @param v Part of the signature (v value).
     * @param r Part of the signature (r value).
     * @param s Part of the signature (s value).
     */
    function endRound(bytes calldata data, uint8 v, bytes32 r, bytes32 s) external onlyOwnerAndOracle {
        Round storage _round = round;

        if (block.timestamp < _round.endTime) revert RoundNotEnded();
        if (keccak256(data).toEthSignedMessageHash().recover(v, r, s) != oracle) revert InvalidSignature();

        _round.ongoing = false;
        _dischargeYield(data);

        Withdrawal memory _withdrawal = withdrawal;

        if (_withdrawal.amount > 0) {
            _withdraw(_withdrawal.amount, _withdrawal.receiver);
            withdrawal = Withdrawal(0, address(0));
        }

        emit EndRound(_round.id, data);

        if (upstream.flowing) {
            _startRound();
        }
    }

    /**
     * @dev Deposits the specified amount into the DAM, applying it to the ongoing round.
     * @param amount The amount of funds to deposit.
     */
    function deposit(uint256 amount) external onlyOwner {
        _deposit(amount);
    }

    /**
     * @dev deposits the specified amount into the dam, applying it to the ongoing round via permit function.
     * @param amount the amount of funds to deposit.
     * @param deadline the deadline timestamp that the permit is valid.
     * @param v part of the signature (v value).
     * @param r part of the signature (r value).
     * @param s part of the signature (s value).
     */
    function depositWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external onlyOwner {
        IERC20Permit(address(ybToken)).permit(_msgSender(), address(this), amount, deadline, v, r, s);
        _deposit(amount);
    }

    /**
     * @dev Withdraws all remaining funds from embankment and transfers to the specified receiver.
     * 			It can only be called when the DAM is not operating. (i.e. when the DAM is decommissioned, and the last round has ended)
     * 			Use this function when scheduled withdrawal of decommissionDam has failed.
     * @param receiver The address to receive the withdrawn ybTokens.
     */
    function withdrawAll(address receiver) external onlyOwner {
        if (upstream.flowing) revert DamOperating();
        if (block.timestamp < round.endTime || round.ongoing) revert RoundNotEnded();
        _withdraw(type(uint256).max, receiver);
    }

    /**
     * @dev Schedules a withdrawal of the specified amount to the given receiver.
     * @param amount The amount of funds to withdraw.
     * @param receiver The address to receive the withdrawn funds.
     */
    function scheduleWithdrawal(uint256 amount, address receiver) external onlyOwner {
        if (!upstream.flowing) revert DamNotOperating();
        if (amount > fund) revert InsufficientBalance();
        if (amount == fund) revert InvalidAmountRequest(); // to withdraw all, use decommissionDam()

        _scheduleWithdrawal(amount, receiver);
    }

    /**
     * @dev Sets the parameters for upcoming rounds in the DAM.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested back into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     */
    function setUpstream(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) external onlyOwner {
        _setUpsteram(period, reinvestmentRatio, autoStreamRatio);
    }

    /**
     * @dev Updates the oracle address for data verification in endRound.
     * @param newOracle The new oracle address.
     */
    function setOracle(address newOracle) external onlyOwnerAndOracle {
        if (newOracle == address(0)) revert InvalidAddress();
        address oldOracle = oracle;
        oracle = newOracle;
        emit SetOracle(oldOracle, newOracle);
    }

    /**
     * @dev returns the interest generated in the current round.
     * @return totalincentive the total amount of incentive that goes to the projects.
     * @return reinvestmentamount the amount of interest reinvested into the next round.
     */
    function getTotalIncentive() public view returns (uint256, uint256) {
        uint256 amount = embankment.maxWithdraw(address(this));
        uint256 interest = amount - fund;
        uint256 totalIncentive = interest;
        uint256 reinvestmentAmount;
        uint16 reinvestmentRatio = upstream.reinvestmentRatio;

        if (reinvestmentRatio > 0) {
            totalIncentive = interest.mulTo(PERCENTAGE_FACTOR - reinvestmentRatio);
            reinvestmentAmount = interest - totalIncentive;
        }

        return (totalIncentive, reinvestmentAmount);
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev Starts the DAM operation by setting up the upstream parameters and depositing the specified amount.
     * @param amount The amount of funds that will be the source of yield.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested back into the treasury.
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution.
     */
    function _operateDam(uint256 amount, uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) internal {
        if (upstream.flowing) revert DamOperating();
        upstream.flowing = true;

        _setUpsteram(period, reinvestmentRatio, autoStreamRatio);
        _deposit(amount);
        _startRound();

        emit OperateDam();
    }

    /**
     * @dev Starts a new round for yield generation and distribution. Sets up the round parameters.
     *      Can only be called when the previous round has ended and if the DAM is in an operating state.
     */
    function _startRound() internal {
        Round storage _round = round;
        Upstream memory _upstream = upstream;
        uint256 timestamp = block.timestamp;

        if (!_upstream.flowing) revert DamNotOperating();
        if (timestamp < round.endTime || round.ongoing) revert RoundNotEnded();

        _round.id += 1;
        _round.ongoing = true;
        _round.startTime = timestamp;
        _round.endTime = timestamp + _upstream.period;

        emit StartRound(_round.id, timestamp, round.endTime);
    }

    /**
     * @dev Sets the upstream parameters for the DAM.
     * @param period The duration of each round in seconds.
     * @param reinvestmentRatio The percentage of yield reinvested to the treasury. Expressed in BP(basis points).
     * @param autoStreamRatio The percentage of yield allocated to automatic grant distribution. Expressed in BP(basis points).
     */
    function _setUpsteram(uint256 period, uint16 reinvestmentRatio, uint16 autoStreamRatio) internal {
        if (period == 0) revert InvalidPeriod();
        if (reinvestmentRatio > PERCENTAGE_FACTOR || autoStreamRatio > PERCENTAGE_FACTOR) {
            revert InvalidRatio();
        }

        Upstream storage _upstream = upstream;
        _upstream.period = period;
        _upstream.reinvestmentRatio = reinvestmentRatio;
        _upstream.autoStreamRatio = autoStreamRatio;

        emit SetUpstream(period, reinvestmentRatio, autoStreamRatio);
    }

    /**
     * @dev Deposits ybTokens into the embankment for yield generation.
     * @param amount The amount of ybTokens to deposit.
     */
    function _deposit(uint256 amount) internal {
        if (!upstream.flowing) revert DamNotOperating();

        fund += amount;

        address sender = _msgSender();
        ybToken.safeTransferFrom(sender, address(this), amount);
        ybToken.forceApprove(address(embankment), amount);
        embankment.deposit(amount, address(this));

        emit Deposit(sender, amount);
    }

    /**
     * @dev Schedules a withdrawal from the DAM. The scheduled withdrawal will be processed when the round ends.
     * @param amount The amount of ybTokens to withdraw.
     * @param receiver The address to receive the ybTokens.
     */
    function _scheduleWithdrawal(uint256 amount, address receiver) internal {
        if (receiver == address(0)) revert InvalidReceiver();
        withdrawal = Withdrawal(amount, receiver);

        emit ScheduleWithdrawal(receiver, amount);
    }

    /**
     * @dev Withdraws ybTokens from embankment and transfers to the specified receiver.
     * 			try-catch to prevent contract being stuck
     * @param amount The amount of ybTokens to withdraw. If set to max uint256, it withdraws the entire balance.
     * @param receiver The address to receive the withdrawn ybTokens.
     */
    function _withdraw(uint256 amount, address receiver) internal {
        if (amount == type(uint256).max) {
            amount = embankment.maxWithdraw(address(this));
        }

        fund -= amount;

        try embankment.withdraw(amount, address(this), address(this)) {
            try ybToken.transfer(receiver, amount) {
                emit Withdraw(receiver, amount);
            } catch {}
        } catch {}
    }

    /**
     * @dev Distributes the generated yield to the specified receivers and reinvest part of genertaed yield to the next round
     * 			if the reinvestment ratio is greater than 0.
     * @param data Encoded data containing arrays of receivers' addresses and their corresponding proportions.
     */
    function _dischargeYield(bytes calldata data) internal {
        (uint256 totalIncentive, uint256 reinvestmentAmount) = getTotalIncentive();

        fund += reinvestmentAmount;
        embankment.withdraw(totalIncentive, address(this), address(this));

        (address[] memory receivers, uint16[] memory proportions) = abi.decode(data, (address[], uint16[]));

        uint256 len = receivers.length;
        uint256 leftIncentive = totalIncentive;
        uint16 totalProportion;

        for (uint256 i = 0; i < len;) {
            address receiver = receivers[i];
            uint16 proportion = proportions[i];
            uint256 amount = i == len - 1 ? leftIncentive : totalIncentive.mulTo(uint256(proportion));

            totalProportion += proportion;
            leftIncentive -= amount;
            ybToken.safeTransfer(receiver, amount);

            emit DistributeIncentive(receiver, proportion, amount);

            unchecked {
                ++i;
            }
        }

        if (totalProportion != PERCENTAGE_FACTOR) revert InvalidProportion(totalProportion);
    }
}
