// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/TokenLexscrowFactory.sol";

// minimal ERC20 for this test, extraneous functionalities like mint removed as unnecessary here
contract ERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        return true;
    }
}

/// @notice foundry framework testing of TokenLexscrowFactory.sol
contract TokenLexscrowFactoryTest is Test {
    TokenLexscrowFactory internal factoryTest;
    ERC20 public token;
    address internal receiver;

    function setUp() public {
        factoryTest = new TokenLexscrowFactory();
        //this address deploys 'factoryTest'
        receiver = address(this);
    }

    function testConstructor() public {
        assertGt(factoryTest.feeDenominator(), 0, "feeDenominator not > 0");
        assertEq(factoryTest.receiver(), receiver, "receiver address mismatch");
    }

    // test TokenLexscrow deployment and fuzz inputs, including decimals in the ERC20
    function testDeploy(
        bool _refundable,
        bool _openOffer,
        uint8 _decimals,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _expirationTime,
        address _seller,
        address _buyer,
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
        vm.assume(_decimals > 0);
        token = new ERC20("token 1", "ONE", _decimals);

        if (
            _totalAmount == 0 ||
            _deposit > _totalAmount ||
            _expirationTime <= block.timestamp ||
            _seller == address(0) ||
            address(token) == address(0) ||
            (!_openOffer && _buyer == address(0))
        ) vm.expectRevert();
        // condition checks in TokenLexscrowFactory.deployTokenLexscrow() and TokenLexscrow's constructor
        // post-deployment contract tests undertaken in TokenLexscrow.t.sol
        factoryTest.deployTokenLexscrow(
            _refundable,
            _openOffer,
            _deposit,
            _totalAmount,
            _expirationTime,
            _seller,
            _buyer,
            address(token),
            _conditions
        );
    }

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