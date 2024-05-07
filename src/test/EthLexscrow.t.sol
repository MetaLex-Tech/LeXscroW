// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/EthLexscrow.sol";
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

/// @dev foundry framework testing of EthLexscrow
contract EthLexscrowTest is Test {
    EthLexscrow internal escrowTest;
    EthLexscrow internal openEscrowTest;
    EthLexscrow internal fuzzEscrowTest;
    EthLexscrow internal conditionEscrowTest;

    address payable internal buyer = payable(address(111111));
    address payable internal receiver = payable(address(222222));
    address payable internal seller = payable(address(333333));
    address escrowTestAddr;
    uint256 internal deposit = 1e14;
    uint256 internal fee = 1e10;
    uint256 internal totalAmount = 1e16;
    uint256 internal totalAmountWithFee = 1e10 + 1e16;
    uint256 internal expirationTime = 5e15;

    function setUp() public {
        EthLexscrow.Amounts memory _amounts = EthLexscrow.Amounts(
            deposit,
            totalAmount,
            fee,
            receiver
        );
        escrowTest = new EthLexscrow(
            true,
            false,
            expirationTime,
            seller,
            buyer,
            address(0), // test without conditions first
            _amounts
        );
        escrowTestAddr = address(escrowTest);
        vm.deal(address(this), _amounts.totalAmount + _amounts.fee);
    }

    function testConstructor() public {
        assertEq(
            escrowTest.totalAmount(),
            totalAmount,
            "totalAmount1 mismatch"
        );
        assertEq(escrowTest.deposit(), deposit, "deposit mismatch");
        assertEq(escrowTest.fee(), fee, "fee mismatch");
        assertEq(
            escrowTest.expirationTime(),
            expirationTime,
            "Expiry time mismatch"
        );
        assertEq(escrowTest.seller(), seller, "Seller mismatch");
        assertEq(escrowTest.buyer(), buyer, "Buyer mismatch");
    }

    function testUpdateSeller(address payable _addr) public {
        vm.startPrank(escrowTest.seller());
        escrowTest.updateSeller(_addr);
        assertEq(escrowTest.seller(), _addr, "seller address did not update");
    }

    function testUpdateBuyer(address payable _addr) public {
        vm.startPrank(escrowTest.buyer());
        uint256 _amtDeposited = escrowTest.amountDeposited(buyer);
        escrowTest.updateBuyer(_addr);
        assertEq(escrowTest.buyer(), _addr, "buyer address did not update");
        assertEq(
            escrowTest.amountDeposited(_addr),
            _amtDeposited,
            "amountDeposited mapping did not update"
        );
    }

    function testReceive(uint256 _amount) public payable {
        uint256 _preBalance = escrowTest.amountDeposited(address(this));
        bool _success;
        //receive() will only be invoked if _amount > 0
        vm.assume(_amount > 0);
        vm.deal(address(this), _amount);

        if (
            _amount > totalAmountWithFee ||
            escrowTest.expirationTime() <= block.timestamp
        ) vm.expectRevert();
        (_success, ) = escrowTestAddr.call{value: _amount}("");
        if (
            _amount > escrowTest.deposit() &&
            _amount <= escrowTest.totalWithFee() &&
            _success
        )
            assertTrue(
                escrowTest.deposited(),
                "deposited variable did not update"
            );
        if (escrowTest.openOffer()) {
            assertTrue(
                escrowTest.buyer() == payable(msg.sender),
                "buyer variable did not update"
            );
        }
        if (_success && _amount <= escrowTest.totalWithFee())
            assertGt(
                escrowTest.amountDeposited(address(this)),
                _preBalance,
                "amountDeposited mapping did not update"
            );
    }

    // fuzz test for different timestamps
    function testCheckIfExpired(uint256 timestamp) external {
        // assume 'totalAmount' is in escrow
        vm.deal(escrowTestAddr, escrowTest.totalAmount());

        uint256 _preBuyerAmtWithdrawable = escrowTest.amountWithdrawable(buyer);
        uint256 _preSellerAmtWithdrawable = escrowTest.amountWithdrawable(
            seller
        );
        bool _preDeposited = escrowTest.deposited();
        vm.warp(timestamp);
        escrowTest.checkIfExpired();
        // ensure, if timestamp is past expiration time and thus escrow is expired, boolean is updated and totalAmount is credited to buyer
        // else, isExpired() should be false and amountWithdrawable mappings should be unchanged
        if (escrowTest.expirationTime() <= timestamp) {
            assertTrue(escrowTest.isExpired());
            if (escrowTest.refundable())
                assertGt(
                    escrowTest.amountWithdrawable(buyer),
                    _preBuyerAmtWithdrawable,
                    "buyer's amountWithdrawable should have been increased by refunded amount"
                );
            else if (!escrowTest.refundable() && _preDeposited) {
                uint256 _remainder = escrowTestAddr.balance -
                    escrowTest.deposit();
                assertEq(
                    escrowTest.amountWithdrawable(seller) -
                        _preSellerAmtWithdrawable,
                    escrowTest.deposit(),
                    "seller's amountWithdrawable should have been increased by non-refundable 'deposit'"
                );
                if (_remainder > 0)
                    assertEq(
                        escrowTest.amountWithdrawable(buyer),
                        _preBuyerAmtWithdrawable + _remainder,
                        "buyer's amountWithdrawable should have been increased by the the remainder (amount over 'deposit')"
                    );
            }
            assertEq(
                escrowTest.amountDeposited(escrowTest.buyer()),
                0,
                "buyer's amountDeposited was not deleted"
            );
        } else {
            assertTrue(!escrowTest.isExpired());
            assertEq(
                escrowTest.amountWithdrawable(seller),
                _preSellerAmtWithdrawable,
                "seller's amountWithdrawable should be unchanged"
            );
            assertEq(
                escrowTest.amountWithdrawable(buyer),
                _preBuyerAmtWithdrawable,
                "buyer's amountWithdrawable should be unchanged"
            );
        }
    }

    function testRejectDepositor(
        address payable _depositor,
        uint256 _deposit
    ) external {
        // '_deposit' must be less than 'totalAmount'
        vm.assume(_deposit <= totalAmount);
        EthLexscrow.Amounts memory _amounts = EthLexscrow.Amounts(
            deposit,
            totalAmount,
            fee,
            receiver
        );
        openEscrowTest = new EthLexscrow(
            true,
            true,
            expirationTime,
            seller,
            buyer,
            address(0),
            _amounts
        );
        address payable _newContract = payable(address(openEscrowTest));
        bool _reverted;
        vm.assume(_newContract != _depositor);
        // give the '_deposit' amount to the '_depositor' so they can accept the open offer
        vm.deal(_depositor, _deposit);
        vm.startPrank(_depositor);
        if (
            _deposit + _newContract.balance > totalAmount ||
            (openEscrowTest.openOffer() && _deposit < totalAmount) ||
            openEscrowTest.amountDeposited(_depositor) == 0
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        (bool _success, ) = _newContract.call{value: _deposit}("");

        bool _wasDeposited = openEscrowTest.deposited();
        uint256 _amountWithdrawableBefore = openEscrowTest.amountWithdrawable(
            _depositor
        );
        vm.stopPrank();
        // reject depositor as 'seller'
        vm.startPrank(seller);
        if (openEscrowTest.amountDeposited(_depositor) == 0 || !_success) {
            _reverted = true;
            vm.expectRevert();
        }
        openEscrowTest.rejectDepositor(_depositor);
        if (!_reverted || _newContract != address(this)) {
            if (_wasDeposited && _success && _depositor != address(0)) {
                if (openEscrowTest.openOffer())
                    assertEq(
                        address(0),
                        openEscrowTest.buyer(),
                        "buyer address did not delete"
                    );
                assertGt(
                    openEscrowTest.amountWithdrawable(_depositor),
                    _amountWithdrawableBefore,
                    "_depositor's amountWithdrawable did not update"
                );
            }
            assertEq(
                0,
                openEscrowTest.amountDeposited(_depositor),
                "amountDeposited did not delete"
            );
        }
    }

    function testWithdraw(address _caller) external {
        // since we're testing only the difference in the amountWithdrawable for '_caller', no need to mock the aggregate 'pendingWithdraw'
        uint256 _preBalance = escrowTestAddr.balance;
        uint256 _preAmtWithdrawable = escrowTest.amountWithdrawable(_caller);
        bool _reverted;

        vm.startPrank(_caller);
        if (escrowTest.amountWithdrawable(_caller) == 0) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.withdraw();

        assertEq(
            escrowTest.amountWithdrawable(_caller),
            0,
            "not all of 'amountWithdrawable' was withdrawn"
        );
        if (!_reverted) {
            assertGt(
                _preBalance,
                escrowTestAddr.balance,
                "balance of escrowTest not affected"
            );
            assertGt(
                _preAmtWithdrawable,
                escrowTest.amountWithdrawable(_caller),
                "amountWithdrawable not affected"
            );
        }
    }

    // fuzz amounts
    function testExecute(
        uint256 _timestamp,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _fee
    ) external {
        // if 'totalAmountwithFee' (accounting for any amounts withdrawable) isn't in escrow, expect revert
        // we just subtract buyer and seller's amountWithdrawable, if any (rather than mocking 'pendingWithdraw')
        vm.assume(
            (_fee < type(uint256).max / 2 &&
                _totalAmount < type(uint256).max / 2) &&
                _deposit <= _totalAmount &&
                _totalAmount != 0 &&
                _timestamp > block.timestamp
        );
        EthLexscrow.Amounts memory _amounts = EthLexscrow.Amounts(
            _deposit,
            _totalAmount,
            _fee,
            receiver
        );
        fuzzEscrowTest = new EthLexscrow(
            true,
            true,
            _timestamp,
            seller,
            buyer,
            address(0),
            _amounts
        );
        // deal 'totalAmountWithFee' in escrow
        address fuzzEscrowTestAddr = address(fuzzEscrowTest);
        vm.deal(fuzzEscrowTestAddr, _totalAmount + _fee);
        uint256 _preBalance = fuzzEscrowTestAddr.balance -
            (fuzzEscrowTest.amountWithdrawable(buyer) +
                fuzzEscrowTest.amountWithdrawable(seller));

        uint256 _preSellerBalance = fuzzEscrowTest.seller().balance;
        bool _approved;

        if (
            _preBalance != fuzzEscrowTest.totalWithFee() ||
            _deposit > _totalAmount ||
            fuzzEscrowTest.expirationTime() <= block.timestamp
        ) vm.expectRevert();
        else _approved = true;

        fuzzEscrowTest.execute();

        // will also revert if already executed once and balance not reloaded
        if (
            _approved ||
            _preBalance != fuzzEscrowTest.totalWithFee() ||
            _deposit > _totalAmount ||
            fuzzEscrowTest.expirationTime() <= block.timestamp
        ) vm.expectRevert();
        else _approved = true;
        fuzzEscrowTest.execute();

        uint256 _postBalance = fuzzEscrowTestAddr.balance -
            (fuzzEscrowTest.amountWithdrawable(buyer) +
                fuzzEscrowTest.amountWithdrawable(seller));

        // if expiry hasn't been reached, seller should be paid the totalAmount
        if (_approved && !fuzzEscrowTest.isExpired()) {
            // seller should have received totalAmount
            assertGt(
                _preBalance,
                _postBalance,
                "escrow's balance should have been reduced by 'totalAmount'"
            );
            assertGt(
                fuzzEscrowTest.seller().balance,
                _preSellerBalance,
                "seller's balance should have been increased by 'totalAmount'"
            );
            assertEq(_postBalance, 0, "escrow balance should be zero");
        } else if (fuzzEscrowTest.isExpired()) {
            //balances should not change if expired
            assertEq(
                _preBalance,
                _postBalance,
                "escrow's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
            assertEq(
                fuzzEscrowTest.seller().balance,
                _preSellerBalance,
                "seller's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
        }
    }

    /// @dev test execution with a valueCondition
    function testConditionedExecute(bool[] calldata _op) external {
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

        // deploy condition manager instance
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

        EthLexscrow.Amounts memory _amounts = EthLexscrow.Amounts(
            deposit,
            totalAmount,
            fee,
            receiver
        );

        conditionEscrowTest = new EthLexscrow(
            true,
            true,
            expirationTime,
            seller,
            buyer,
            address(_manager),
            _amounts
        );

        vm.deal(address(conditionEscrowTest), totalAmountWithFee);

        // we just subtract buyer and seller's amountWithdrawable, if any (rather than mocking 'pendingWithdraw')
        uint256 _preBalance = address(conditionEscrowTest).balance -
            (conditionEscrowTest.amountWithdrawable(buyer) +
                conditionEscrowTest.amountWithdrawable(seller));
        uint256 _preSellerBalance = conditionEscrowTest.seller().balance;
        uint256 _preBuyerBalance = conditionEscrowTest.buyer().balance;
        uint256 _preReceiverBalance = conditionEscrowTest.receiver().balance;
        bool _approved;

        if (_preBalance != conditionEscrowTest.totalWithFee() || !callResult)
            vm.expectRevert();
        else _approved = true;

        conditionEscrowTest.execute();

        // if expiry hasn't been reached, seller should be paid the totalAmount
        if (_approved && !conditionEscrowTest.isExpired()) {
            // seller should have received totalAmount
            assertGt(
                _preBalance,
                address(conditionEscrowTest).balance,
                "escrow's balance should have been reduced by 'totalAmountWithFee'"
            );
            assertEq(
                conditionEscrowTest.seller().balance,
                _preSellerBalance + totalAmount,
                "seller's balance should have been increased by 'totalAmount'"
            );
            assertEq(
                conditionEscrowTest.receiver().balance,
                _preReceiverBalance + fee,
                "receiver's balance should have been increased by 'fee'"
            );
            assertEq(
                address(conditionEscrowTest).balance,
                0,
                "escrow balance should be zero"
            );
        } else if (conditionEscrowTest.isExpired()) {
            //balances should not change if expired
            assertEq(
                _preBalance,
                address(conditionEscrowTest).balance,
                "escrow's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
            assertEq(
                conditionEscrowTest.seller().balance,
                _preSellerBalance,
                "seller's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
            assertGt(
                conditionEscrowTest.amountWithdrawable(buyer),
                _preBuyerBalance,
                "buyer's amountWithdrawable should have increased upon expiry because 'conditionEscrowTest' is refundable"
            );
        }
    }
}
