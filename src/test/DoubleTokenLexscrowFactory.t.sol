// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/DoubleTokenLexscrowFactory.sol";

/// @notice foundry framework testing of DoubleTokenLexscrowFactory.sol
contract DoubleTokenLexscrowFactoryTest is Test {
    DoubleTokenLexscrowFactory internal factoryTest;
    address internal receiver;

    // match internal constants in DoubleTokenLexscrowFactory.sol
    uint256 internal constant BASIS_POINTS = 1000;
    uint256 internal constant DAY_IN_SECONDS = 86400;

    uint256 public feeBasisPoints;

    function setUp() public {
        factoryTest = new DoubleTokenLexscrowFactory();
        //this address deploys 'factoryTest'
        receiver = address(this);
    }

    function testConstructor() public {
        assertEq(factoryTest.receiver(), receiver, "receiver address mismatch");
    }

    ///
    /// @dev use DoubleTokenLexscrow.t.sol for test deployments and fuzz inputs as the factory does not have the conditionals
    ///

    function testUpdateReceiver(address _addr, address _addr2) public {
        bool _reverted;
        // address(this) is calling the test contract so it should be the receiver for the call not to revert
        if (address(this) != factoryTest.receiver()) {
            _reverted = true;
            vm.expectRevert();
        }
        factoryTest.updateReceiver(_addr);
        vm.startPrank(_addr2);
        // make sure wrong address causes revert
        if (_addr != _addr2) {
            vm.expectRevert();
            factoryTest.acceptReceiverRole();
        }
        vm.stopPrank();
        vm.startPrank(_addr);
        factoryTest.acceptReceiverRole();
        if (!_reverted) assertEq(factoryTest.receiver(), _addr, "receiver address did not update");
    }

    function testUpdateFee(address _addr2, bool _feeSwitch, uint256 _newFeeBasisPoints, uint256 _timePassed) public {
        vm.assume(_newFeeBasisPoints < 1e50 && _timePassed < 1e20); // reasonable assumptions
        bool _reverted;
        // address(this) is calling the test contract so it should be the receiver for the call not to revert
        if (address(this) != factoryTest.receiver()) {
            _reverted = true;
            vm.expectRevert();
        }
        factoryTest.updateFee(_feeSwitch, _newFeeBasisPoints);
        vm.startPrank(_addr2);
        // make sure wrong address causes revert
        if (_addr2 != factoryTest.receiver()) {
            vm.expectRevert();
            factoryTest.acceptFeeUpdate();
        }
        vm.stopPrank();
        vm.warp(block.timestamp + _timePassed);
        vm.startPrank(factoryTest.receiver());
        if (_timePassed < DAY_IN_SECONDS) {
            _reverted = true;
            vm.expectRevert();
        }
        factoryTest.acceptFeeUpdate();
        if (!_reverted) {
            assertEq(factoryTest.feeBasisPoints(), _newFeeBasisPoints, "feeBasisPoints did not update");
            assertTrue(factoryTest.feeSwitch() == _feeSwitch, "feeSwitch did not update");
        }
    }
}
