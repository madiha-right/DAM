// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockYbToken is ERC20Permit {
    constructor() ERC20Permit("Mock Yield-bearing token") ERC20("Mock Yield-bearing token", "mockYB") {}

    // Mint mock yb token
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Simulate the increase in yb token value
    function simulateAccrual(address account) public {
        _mint(account, 0.01 ether);
    }
}
