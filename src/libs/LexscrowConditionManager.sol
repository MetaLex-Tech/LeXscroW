//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

///// o=o=o=o=o LexscrowConditionManager o=o=o=o=o \\\\\

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 * OpenZeppelin's implementation at https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/introspection/IERC165.sol; license: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/LICENSE
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @dev see: https://github.com/MetaLex-Tech/borg-core/blob/main/src/interfaces/ICondition.sol
interface ICondition {
    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) external view returns (bool);
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

    /// @dev "checkCondition(address,bytes4,bytes)"
    bytes4 private constant _INTERFACE_ID_BASE_CONDITION = 0x8b94fce4;

    mapping(address => bool) internal conditionContract;

    error LexscrowConditionManager_DuplicateCondition();
    error LexscrowConditionManager_InvalidCondition();

    /// @param _conditions array of Condition structs, which for each element contains:
    /// op: Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    /// condition: address of the condition contract
    /// @dev reverts if a supplied condition does not properly implement the `checkCondition` interface or if duplicate conditions are passed;
    /// IF A LEXSCROW WITH CONDITIONS IS RE-USED, THE RETURNS FROM THE APPLICABLE CONDITIONS MAY CHANGE IN SUBSEQUENT EXECUTES -- this
    /// is by design as, for example, a dynamic condition such as an oracle-fed value or time condition is likely to be different for
    /// subsequent executes
    constructor(Condition[] memory _conditions) payable {
        for (uint256 i = 0; i < _conditions.length; ) {
            address _currentCondition = _conditions[i].condition;

            if (!IERC165(_currentCondition).supportsInterface(_INTERFACE_ID_BASE_CONDITION))
                revert LexscrowConditionManager_InvalidCondition();
            if (conditionContract[_currentCondition]) revert LexscrowConditionManager_DuplicateCondition();

            conditionContract[_currentCondition] = true;
            conditions.push(_conditions[i]);
            unchecked {
                ++i; // cannot overflow without hitting gaslimit
            }
        }
    }

    /// @notice iterates through the 'conditions' array, calling each 'condition' contract's 'checkCondition()' function
    /// @param data any data passed to the condition contract
    /// @return result boolean of whether all conditions (accounting for each Condition's 'Logic' operator) have been satisfied
    function checkConditions(bytes memory data) public view returns (bool result) {
        if (conditions.length == 0) return true;
        else {
            for (uint256 i = 0; i < conditions.length; ) {
                if (conditions[i].op == Logic.AND) {
                    result = ICondition(conditions[i].condition).checkCondition(msg.sender, msg.sig, data);
                    if (!result) {
                        return false;
                    }
                } else {
                    result = ICondition(conditions[i].condition).checkCondition(msg.sender, msg.sig, data);
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
