// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DoubleTokenLexscrowFactory} from "../src/DoubleTokenLexscrowFactory.sol";
import {DoubleTokenLexscrowRegistry} from "RicardianTriplerDoubleTokenLeXscroW/DoubleTokenLexscrowRegistry.sol";
import {AgreementV1Factory} from "RicardianTriplerDoubleTokenLeXscroW/RicardianTriplerDoubleTokenLexscrow.sol";
import {Create2Transfer} from "../src/Create2Transfer.sol";
import {console} from "forge-std/console.sol";

bytes32 constant DETERMINISTIC_DEPLOY_SALT = keccak256(abi.encodePacked("metalex-coded"));
address constant admin = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

contract Deploy is Script {
    function run() external {
            address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");

        bytes memory bytecode = abi.encodePacked(
            type(DoubleTokenLexscrowRegistry).creationCode,
            abi.encode(deployerAddress) 
        );
        address predictedAddress = vm.computeCreate2Address(
            DETERMINISTIC_DEPLOY_SALT,
            keccak256(bytecode)
        );
        console.log("Predicted address:", predictedAddress);
        vm.startBroadcast(deployerPrivateKey);
        //DoubleTokenLexscrowFactory doubleTokenLexscrowFactory = new DoubleTokenLexscrowFactory{salt: DETERMINISTIC_DEPLOY_SALT}();

        Create2Transfer create2Transfer = new Create2Transfer{salt: DETERMINISTIC_DEPLOY_SALT}();

        //Deploy the factory, set fee and admin to receiver
        address factory = create2Transfer.deployAndTransfer(DETERMINISTIC_DEPLOY_SALT, admin);
        DoubleTokenLexscrowFactory doubleTokenLexscrowFactory = DoubleTokenLexscrowFactory(factory);
        console.log("DoubleTokenLexscrowFactory:", address(doubleTokenLexscrowFactory));

        //Deploy the registry and agreement factory, we must be the admin to enable the factory, then set msig to admin
        DoubleTokenLexscrowRegistry doubleTokenLexscrowRegistry = new DoubleTokenLexscrowRegistry{salt: DETERMINISTIC_DEPLOY_SALT}(deployerAddress);
        console.log("DoubleTokenLexscrowRegistry:", address(doubleTokenLexscrowRegistry));

        //Deploy the agreement factory, set the registry we just deployed
        AgreementV1Factory agreementV1Factory = new AgreementV1Factory{salt: DETERMINISTIC_DEPLOY_SALT}(address(doubleTokenLexscrowRegistry));
        console.log("AgreementV1Factory:", address(agreementV1Factory));  
        doubleTokenLexscrowRegistry.enableFactory(address(agreementV1Factory));
        //set .25% fee
        console.log("Current receiver:", doubleTokenLexscrowFactory.receiver());
        console.log("deployerAddress:", deployerAddress);
       // doubleTokenLexscrowFactory.acceptReceiverRole();
       // doubleTokenLexscrowFactory.updateFee(true, 250000);
      
       //doubleTokenLexscrowFactory.acceptReceiverRole();
        //doubleTokenLexscrowFactory.acceptFeeUpdate();
       // doubleTokenLexscrowFactory.updateReceiver(admin);
        doubleTokenLexscrowRegistry.updateAdmin(admin);

        vm.stopBroadcast();
    }
}   