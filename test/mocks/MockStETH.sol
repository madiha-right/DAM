// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockStETH is ERC20 {
    constructor() ERC20("Mock Staked ETH", "stETH") {}

    // Mint mock stETH
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Simulate the increase in stETH value
    function simulateAccrual(address account) public {
        _mint(account, 0.01 ether);
    }
}
