// SPDX-License-Identifier: MIT

/**
 * this solidity file is provided as-is; no guarantee, representation or warranty is being made, express or implied,
 * as to the safety or correctness of the code or any smart contracts or other software deployed from these files.
 * this solidity file is NOT AUDITED; there can be no assurance it will work as intended,
 * and users may experience delays, failures, errors, omissions or loss of transmitted information or value.
 *
 * Any users, developers, or adapters of these files should proceed with caution and use at their own risk.
 **/

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/libs/LexscrowConditionManager.sol";

interface IBaseCondition {
    function checkCondition() external pure returns (bool);
}

contract BaseCondition {
    constructor() {}

    //weak bool fuzzer (will be same within each test run)
    function checkCondition() public view returns (bool) {
        return ((block.number) % 2 == 0);
    }
}

/// @dev foundry framework testing of LexscrowConditionManager
contract LexscrowConditionManagerTest is Test {
    function setUp() public {}

    function testConstructor(bool[] calldata _op) public {
        uint256 _len = _op.length;
        vm.assume(_len < 20); // reasonable array length assumption as contract will fail creation otherwise
        LexscrowConditionManager.Condition[]
            memory _conditions = new LexscrowConditionManager.Condition[](_len);
        LexscrowConditionManager.Logic[]
            memory _logic = new LexscrowConditionManager.Logic[](_len);
        // load array to feed to constructor
        for (uint256 i = 0; i < _len; i++) {
            if (_op[i]) _logic[i] = LexscrowConditionManager.Logic.AND;
            else _logic[i] = LexscrowConditionManager.Logic.OR;
            BaseCondition _bC = new BaseCondition();
            _conditions[i] = LexscrowConditionManager.Condition(
                address(_bC),
                _logic[i]
            );
        }

        // deploy instance
        LexscrowConditionManager _manager = new LexscrowConditionManager(
            _conditions
        );
        // ensure everything was properly pushed in the '_manager' contract
        for (uint256 x = 0; x < _len; x++) {
            // Use low-level call to retrieve the condition address and Logic, since can't use getter for an array in another contract
            (bool success, bytes memory result) = address(_manager).call(
                abi.encodeWithSignature("conditions(uint256)", x)
            );
            require(success, "External call failed");
            address _conditionRetrieved = abi.decode(result, (address));
            (bool success2, bytes memory result2) = address(_manager).call(
                abi.encodeWithSignature("conditions(uint256)", x)
            );
            require(success2, "External call failed");
            bool _logRet;
            (, uint256 _logicValue) = abi.decode(result2, (address, uint256)); // Use low-level call to retrieve the Logic enum value encoded as uint256
            if (_logicValue == 0) _logRet = true;

            assertEq(
                _conditionRetrieved,
                _conditions[x].condition,
                "address was not pushed to array"
            );
            if (_op[x]) assertTrue(_logRet, "Logic was not pushed to array");
        }
    }

    function testCheckConditions(bool[] calldata _op) public {
        uint256 _len = _op.length;
        vm.assume(_len < 10); // reasonable array length assumption as contract will fail creation otherwise anyway
        LexscrowConditionManager.Condition[]
            memory _conditions = new LexscrowConditionManager.Condition[](_len);
        LexscrowConditionManager.Logic[]
            memory _logic = new LexscrowConditionManager.Logic[](_len);
        // load array to feed to constructor
        for (uint256 i = 0; i < _len; i++) {
            if (_op[i]) _logic[i] = LexscrowConditionManager.Logic.AND;
            else _logic[i] = LexscrowConditionManager.Logic.OR;
            BaseCondition _bC = new BaseCondition();
            _conditions[i] = LexscrowConditionManager.Condition(
                address(_bC),
                _logic[i]
            );
        }

        // deploy instance
        LexscrowConditionManager _manager = new LexscrowConditionManager(
            _conditions
        );

        // check conditions
        bool result;
        for (uint256 x = 0; x < _conditions.length; ) {
            if (_conditions[x].op == LexscrowConditionManager.Logic.AND) {
                result = IBaseCondition(_conditions[x].condition)
                    .checkCondition();
                if (!result) {
                    result = false;
                    break;
                }
            } else {
                result = IBaseCondition(_conditions[x].condition)
                    .checkCondition();
                if (result) break;
            }
            unchecked {
                ++x; // cannot overflow without hitting gaslimit
            }
        }
        bool callResult = _manager.checkConditions();
        if (_len == 0)
            assertTrue(callResult, "empty conditions should return true");
        else assertTrue(result == callResult, "condition calls do not match");
    }
}
