// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Core} from "./Core.t.sol";

contract TestEmbankment is Core {
    function test_deposit_UnauthorizedAccount() public {
        uint256 amount = 100 ether;
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        embankment.deposit(amount, alice);
    }

    function test_mint_UnauthorizedAccount() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        embankment.mint(amount, alice);
    }

    function test_withdraw_UnauthorizedAccount() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        embankment.withdraw(amount, alice, alice);
    }

    function test_redeem_UnauthorizedAccount() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        embankment.redeem(amount, alice, alice);
    }
}
