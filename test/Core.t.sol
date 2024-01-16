// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Embankment} from "src/Embankment.sol";
import {Dam} from "src/Dam.sol";
import {PercentageMath} from "src/libraries/PercentageMath.sol";
import {MockStETH} from "./mocks/MockStETH.sol";
import {Helper} from "./Helper.t.sol";

contract Core is Helper {
    using SafeERC20 for IERC20;
    using PercentageMath for uint256;
    using MessageHashUtils for bytes32;

    /* ============ State Variables ============ */

    MockStETH public ybToken;
    Embankment public embankment;
    Dam public dam;

    /* ============ setUp Function ============ */

    function setUp() public {
        ybToken = new MockStETH();
        embankment = new Embankment(IERC20(address(ybToken)), "dam mETH", "damMETH");
        dam = new Dam(ybToken, embankment);

        embankment.transferOwnership(address(dam));
    }

    /* ============ Internal Functions ============ */

    function _operateDam(
        uint256 amount,
        uint256 period,
        uint16 reinvestmentRatio,
        uint16 autoStreamRatio,
        uint16 roundId
    ) internal {
        ybToken.mint(address(this), amount);
        IERC20(ybToken).forceApprove(address(dam), amount);

        uint256 timestamp = block.timestamp;

        vm.expectEmit(false, false, false, false);
        emit OperateDam();
        dam.operateDam(amount, period, reinvestmentRatio, autoStreamRatio);

        // _setUpstream()
        (uint256 _period, uint16 _reinvestmentRatio, uint16 _autoStreamRatio, bool _flowing) = dam.upstream();
        assertEq(_period, period, "period should equal to _period");
        assertEq(_reinvestmentRatio, reinvestmentRatio, "reinvestmentRatio should equal to _reinvestmentRatio");
        assertEq(_autoStreamRatio, autoStreamRatio, "autoStreamRatio should equal to _autoStreamRatio");
        assertTrue(_flowing, "flowing should be true");

        // _deposit()
        assertEq(ybToken.balanceOf(address(this)), 0, "balance should be 0");
        assertEq(embankment.maxWithdraw(address(dam)), amount, "maxWithdraw should equal to amount");

        // _startRound()
        (uint16 id, uint256 startTime, uint256 endTime) = dam.round();
        assertEq(id, roundId, "id should equal to roundId");
        assertEq(startTime, timestamp, "startTime should equal to timestamp");
        assertEq(endTime, timestamp + period, "endTime should equal to timestamp + period");
    }

    function _endRound(bytes memory data, uint16 roundId) internal {
        (address oracle, uint256 oraclePk) = makeAddrAndKey("oracle");
        bytes32 digest = keccak256(data).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePk, digest);

        dam.setOracle(oracle);

        (uint256 _amount, address _receiver) = dam.withdrawal();
        (, uint256 startTime, uint256 endTime) = dam.round();

        _mintYbToken(100 * 1e18, address(embankment)); // mock total incentive
        (uint256 totalIncentive,) = dam.getTotalIncentive();

        vm.warp(endTime);
        vm.expectEmit(true, false, false, true);
        emit EndRound(roundId, data);
        dam.endRound(data, v, r, s);

        _testDischargeYield(data, totalIncentive);
        _testProcessWithdrawal(_amount, _receiver);
        _testStartRound(roundId, startTime, endTime);
    }

    function _testDischargeYield(bytes memory data, uint256 totalIncentive) internal {
        assertEq(ybToken.balanceOf(address(dam)), 0, "Dam should not have any ybToken");

        (address[] memory recipients, uint16[] memory proportions) = abi.decode(data, (address[], uint16[]));
        uint256 leftIncentive = totalIncentive;

        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 incentive =
                i == recipients.length - 1 ? leftIncentive : totalIncentive.mulTo(uint256(proportions[i]));
            assertEq(IERC20(address(ybToken)).balanceOf(recipients[i]), incentive, "Incorrect incentive");
            leftIncentive -= incentive;
        }
    }

    function _testProcessWithdrawal(uint256 _amount, address _receiver) internal {
        if (_amount > 0) {
            if (_amount == type(uint256).max) {
                assertEq(embankment.balanceOf(address(dam)), 0, "Dam should not have any shares");
                assertEq(ybToken.balanceOf(address(dam)), 0, "Dam should not have any ybToken");
            } else {
                assertEq(ybToken.balanceOf(_receiver), _amount, "Receiver should have the _amount of ybToken");
            }
        }

        (uint256 amount, address receiver) = dam.withdrawal();
        assertEq(amount, 0, "amount should equal to 0");
        assertEq(receiver, address(0), "receiver should equal to address(0)");
    }

    function _testStartRound(uint16 roundId, uint256 startTime, uint256 endTime) internal {
        (uint256 period,,, bool flowing) = dam.upstream();
        (uint16 _id, uint256 _startTime, uint256 _endTime) = dam.round();

        if (flowing) {
            assertEq(_id, roundId + 1, "id should equal to roundId + 1");
            assertEq(_startTime, block.timestamp, "startTime should equal to block.timestamp");
            assertEq(_endTime, block.timestamp + period, "endTime should equal to block.timestamp + period");
        } else {
            assertEq(_id, roundId, "id should not increase");
            assertEq(_startTime, startTime, "startTime should not change");
            assertEq(_endTime, endTime, "endTime should not change");
        }
    }

    function _mintYbToken(uint256 amount, address receiver) internal {
        ybToken.mint(receiver, amount);
    }
}
