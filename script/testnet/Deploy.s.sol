// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Embankment} from "src/Embankment.sol";
import {Dam} from "src/Dam.sol";
import {MockYbToken} from "src/mocks/MockYbToken.sol";

contract Deploy is Script {
    MockYbToken public mockYbToken;
    Embankment public embankment;
    Dam public dam;

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);

        mockYbToken = new MockYbToken();
        embankment = new Embankment(mockYbToken, 'dam mETH', 'damMETH');
        dam = new Dam(mockYbToken, embankment);

        dam.setOracle(msg.sender);
        embankment.transferOwnership(address(dam));
        mockYbToken.mint(0xB7DAF364C11Ec537356Ce0997f750ba17236906c, 1000 * 1e18);

        console2.log("MockYbToken address: ", address(mockYbToken));
        console2.log("Embankment address: ", address(embankment));
        console2.log("Dam address: ", address(dam));

        console2.log("Embankment owner: ", address(embankment.owner()));

        vm.stopBroadcast();
    }
}
