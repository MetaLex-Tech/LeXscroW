// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/EthLexscrowFactory.sol";

/// @notice foundry framework testing of EthLexscrowFactory.sol
contract EthLexscrowFactoryTest is Test {
    EthLexscrowFactory internal factoryTest;
    address internal receiver;

    function setUp() public {
        factoryTest = new EthLexscrowFactory();
        //this address deploys 'factoryTest'
        receiver = address(this);
    }

    function testConstructor() public {
        assertGt(factoryTest.feeDenominator(), 0, "feeDenominator not > 0");
        assertEq(factoryTest.receiver(), receiver, "receiver address mismatch");
    }

    // test EthLexscrow deployment and fuzz inputs
    function testDeploy(
        bool _refundable,
        bool _openOffer,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _expirationTime,
        address payable _seller,
        address payable _buyer,
        address[] calldata _conditionAddr
    ) public {
        // expressly define op enum as foundry cannot ascertain enum bounds (leading to too many vm.assume rejections), see https://github.com/foundry-rs/foundry/issues/871
        uint256 _len = _conditionAddr.length;
        LexscrowConditionManager.Logic[] memory _logic = new LexscrowConditionManager.Logic[](_len);
        LexscrowConditionManager.Condition[] memory _conditions = new LexscrowConditionManager.Condition[](_len);
        for (uint256 x = 0; x < _len; x++) {
            //vm.assume(_ops[x] < 2);
            _logic[x] = LexscrowConditionManager.Logic(uint8(1));
            _conditions[x] = (LexscrowConditionManager.Condition(_conditionAddr[x], _logic[x]));
        }

        if (
            _totalAmount == 0 ||
            _deposit > _totalAmount ||
            _expirationTime <= block.timestamp ||
            _seller == address(0) ||
            (!_openOffer && _buyer == address(0))
        ) vm.expectRevert();
        // condition checks in EthLexscrowFactory.deployEthLexscrow() and EthLexscrow's constructor
        // post-deployment contract tests undertaken in EthLexscrow.t.sol
        factoryTest.deployEthLexscrow(
            _refundable,
            _openOffer,
            _deposit,
            _totalAmount,
            _expirationTime,
            _seller,
            _buyer,
            _conditions
        );
    }

    function testUpdateReceiver(address payable _addr, address payable _addr2) public {
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

    function testUpdateFee(address _caller, bool _feeSwitch, uint256 _newFeeDenominator) public {
        vm.startPrank(_caller);
        bool _updated;
        if (_caller != factoryTest.receiver() || _newFeeDenominator == 0) vm.expectRevert();
        else _updated = true;
        factoryTest.updateFee(_feeSwitch, _newFeeDenominator);

        if (_updated) {
            assertEq(factoryTest.feeDenominator(), _newFeeDenominator, "feeDenominator did not update");
            if (_feeSwitch) assertTrue(factoryTest.feeSwitch(), "feeSwitch did not update");
        }
    }
}
