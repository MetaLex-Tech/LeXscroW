// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {DoubleTokenLexscrow} from "../src/DoubleTokenLexscrow.sol";
import {console} from "forge-std/console.sol";

bytes32 constant DETERMINISTIC_DEPLOY_SALT = keccak256(abi.encodePacked("metalex-coded"));

contract Deploy is Script {
    function run() external {
            deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");

             // Create bytecode with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(DoubleTokenLexscrow).creationCode
        );

        address predictedAddress = vm.computeCreate2Address(
            salt,
            keccak256(bytecode)
        );
        
        console.log("Predicted address:", predictedAddress);

        vm.startBroadcast(deployerPrivateKey);
                // Calculate the address before deployment

        // Deploy the contract
        address deployedAddress = vm.create2(
            0, // value to send
            salt,
            bytecode
        );

        console.log("Deployed address:", deployedAddress);
            vm.stopBroadcast();
    }
}   