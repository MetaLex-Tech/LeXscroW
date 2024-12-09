// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DoubleTokenLexscrowFactory} from "../src/DoubleTokenLexscrowFactory.sol";
import {DoubleTokenLexscrowRegistry} from "RicardianTriplerDoubleTokenLeXscroW/DoubleTokenLexscrowRegistry.sol";
import {AgreementV1Factory} from "RicardianTriplerDoubleTokenLeXscroW/RicardianTriplerDoubleTokenLexscrow.sol";
import {console} from "forge-std/console.sol";

bytes32 constant DETERMINISTIC_DEPLOY_SALT = keccak256(abi.encodePacked("metalex-coded"));
address constant admin = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

contract Deploy is Script {
    function run() external {
            address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");

        bytes memory bytecode = abi.encodePacked(
            type(DoubleTokenLexscrowFactory).creationCode
        );
        address predictedAddress = vm.computeCreate2Address(
            DETERMINISTIC_DEPLOY_SALT,
            keccak256(bytecode)
        );
        console.log("Predicted address:", predictedAddress);
        vm.startBroadcast(deployerPrivateKey);
        DoubleTokenLexscrowFactory doubleTokenLexscrowFactory = new DoubleTokenLexscrowFactory{salt: DETERMINISTIC_DEPLOY_SALT}();
        console.log("Deployed address:", address(doubleTokenLexscrowFactory));
        DoubleTokenLexscrowRegistry doubleTokenLexscrowRegistry = new DoubleTokenLexscrowRegistry{salt: DETERMINISTIC_DEPLOY_SALT}(deployerAddress);
        console.log("Deployed address:", address(doubleTokenLexscrowRegistry));
        AgreementV1Factory agreementV1Factory = new AgreementV1Factory{salt: DETERMINISTIC_DEPLOY_SALT}(address(doubleTokenLexscrowRegistry));
        console.log("Deployed address:", address(agreementV1Factory));  
        doubleTokenLexscrowRegistry.enableFactory(address(agreementV1Factory));
        //set .25% fee
        console.log("Current receiver:", doubleTokenLexscrowFactory.receiver());
        console.log("deployerAddress:", deployerAddress);
        doubleTokenLexscrowFactory.updateFee(true, 250000);
        doubleTokenLexscrowFactory.acceptFeeUpdate();
        doubleTokenLexscrowFactory.updateReceiver(admin);
        doubleTokenLexscrowRegistry.updateAdmin(admin);

        vm.stopBroadcast();
    }
}   