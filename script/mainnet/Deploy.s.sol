// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Embankment} from "src/Embankment.sol";
import {Dam} from "src/Dam.sol";

contract Deploy is Script {
    Embankment public embankment;
    Dam public dam;

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address mETH = vm.envAddress("MANTLE_ETH_ADDRESS");

        vm.startBroadcast(pk);

        embankment = new Embankment(IERC20(mETH), 'DAM Mantle Staked Ether', 'damMETH');
        dam = new Dam(IERC20(mETH), embankment);

        dam.setOracle(msg.sender);
        embankment.transferOwnership(address(dam));

        console2.log("Embankment address: ", address(embankment));
        console2.log("Dam address: ", address(dam));

        vm.stopBroadcast();
    }
}
