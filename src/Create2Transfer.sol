//SPDX-License-Identifier: AGPL-3.0-only
import {DoubleTokenLexscrowFactory} from "./DoubleTokenLexscrowFactory.sol";
import {Create2} from "lib/openzeppelin-contracts/contracts/utils/Create2.sol";

pragma solidity ^0.8.18;

contract Create2Transfer {
    
    function deployAndTransfer(bytes32 salt, address admin) external returns (address) {
        address doubleTokenLexscrowFactory = Create2.deploy(0, salt, type(DoubleTokenLexscrowFactory).creationCode);
        DoubleTokenLexscrowFactory(doubleTokenLexscrowFactory).updateFee(true, 250000);
        DoubleTokenLexscrowFactory(doubleTokenLexscrowFactory).updateReceiver(admin);
        return doubleTokenLexscrowFactory;
    }
}


