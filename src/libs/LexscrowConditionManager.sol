//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

///// o=o=o=o=o LexscrowConditionManager o=o=o=o=o \\\\\

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

/// @dev see: https://github.com/MetaLex-Tech/BORG-CORE/blob/main/src/interfaces/ICondition.sol
interface ICondition {
    function checkCondition() external returns (bool);
}

/// @dev a stripped-down version of the BORG-CORE ConditionManager (https://github.com/MetaLex-Tech/BORG-CORE/blob/main/src/libs/conditions/conditionManager.sol),
/// removing auth/access control (and thus also the ability to add or remove conditions post-deployment) in favor of immutability
contract LexscrowConditionManager {
    enum Logic {
        AND,
        OR
    }

    struct Condition {
        address condition;
        Logic op;
    }

    Condition[] public conditions;

    /// @param _conditions array of Condition structs, which for each element contains:
    /// op: Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    /// condition: address of the condition contract
    constructor(Condition[] memory _conditions) payable {
        for (uint256 i = 0; i < _conditions.length; ) {
            conditions.push(_conditions[i]);
            unchecked {
                ++i; // cannot overflow without hitting gaslimit
            }
        }
    }

    /// @notice iterates through the 'conditions' array, calling each 'condition' contract's 'checkCondition()' function
    /// @return result boolean of whether all conditions (accounting for each Condition's 'Logic' operator) have been satisfied
    function checkConditions() public returns (bool result) {
        if (conditions.length == 0) return true;
        else {
            for (uint256 i = 0; i < conditions.length; ) {
                if (conditions[i].op == Logic.AND) {
                    result = ICondition(conditions[i].condition)
                        .checkCondition();
                    if (!result) {
                        return false;
                    }
                } else {
                    result = ICondition(conditions[i].condition)
                        .checkCondition();
                    if (result) {
                        return true;
                    }
                }
                unchecked {
                    ++i; // cannot overflow without hitting gaslimit
                }
            }
            return result;
        }
    }
}
