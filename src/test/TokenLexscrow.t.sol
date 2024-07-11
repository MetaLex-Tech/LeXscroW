//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/TokenLexscrow.sol";
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

abstract contract ERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

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

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}

/// ERC20 + EIP-2612 implementation, including EIP712 logic.
abstract contract ERC20Permit is ERC20 {
    /// @dev `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
    bytes32 internal constant DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    bytes32 internal hashedDomainName;
    bytes32 internal hashedDomainVersion;
    bytes32 internal initialDomainSeparator;
    uint256 internal initialChainId;

    /// @dev `keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")`.
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    mapping(address => uint256) public nonces;

    error PermitExpired();
    error InvalidSigner();

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _version,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        hashedDomainName = keccak256(bytes(_name));
        hashedDomainVersion = keccak256(bytes(_version));
        initialDomainSeparator = _computeDomainSeparator();
        initialChainId = block.chainid;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > deadline) revert PermitExpired();

        // Unchecked because the only math done is incrementing the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                _computeDigest(
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
                ),
                v,
                r,
                s
            );

            if (recoveredAddress == address(0)) revert InvalidSigner();
            if (recoveredAddress != owner) revert InvalidSigner();
            allowance[recoveredAddress][spender] = value;
        }
    }

    function domainSeparator() public view virtual returns (bytes32) {
        return block.chainid == initialChainId ? initialDomainSeparator : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(abi.encode(DOMAIN_TYPEHASH, hashedDomainName, hashedDomainVersion, block.chainid, address(this)));
    }

    function _computeDigest(bytes32 hashStruct) internal view virtual returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), hashStruct));
    }
}

/// @notice ERC20 token contract
/// @dev not burnable or mintable; ERC20Permit implemented
contract TestToken is ERC20Permit {
    string public constant TESTTOKEN_NAME = "Test Token";
    string public constant TESTTOKEN_SYMBOL = "TEST";
    string public constant TESTTOKEN_VERSION = "1";
    uint8 public constant TESTTOKEN_DECIMALS = 18;

    constructor(address _user) ERC20Permit(TESTTOKEN_NAME, TESTTOKEN_SYMBOL, TESTTOKEN_VERSION, TESTTOKEN_DECIMALS) {
        _mint(_user, 1e24);
    }

    //allow anyone to mint the token for testing
    function mintToken(address to, uint256 amt) public {
        _mint(to, amt);
    }
}

/// @dev to test EIP-712 operations
contract SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    // mockToken.domainSeparator()
    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMITTYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    // computes the hash of a permit
    function getStructHash(Permit memory _permit) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PERMITTYPEHASH,
                    _permit.owner,
                    _permit.spender,
                    _permit.value,
                    _permit.nonce,
                    _permit.deadline
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(Permit memory _permit) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getStructHash(_permit)));
    }
}

/// @dev foundry framework testing of TokenLexscrow
contract TokenLexscrowTest is Test {
    TokenLexscrow internal escrowTest;
    TokenLexscrow internal openEscrowTest;
    TokenLexscrow internal fuzzEscrowTest;
    TokenLexscrow internal conditionEscrowTest;
    TestToken internal testToken;
    SigUtils internal sigUtils;

    address internal buyer;
    address internal receiver = address(222222);
    address internal seller = address(333333);
    address testTokenAddr;
    address escrowTestAddr;
    uint256 internal deposit = 1e14;
    uint256 internal fee = 1e10;
    uint256 internal totalAmount = 1e16;
    uint256 internal totalWithFee = 1e10 + 1e16;
    uint256 internal expirationTime = 5e15;
    uint256 internal ownerPrivateKey;

    function setUp() public {
        TokenLexscrow.Amounts memory _amounts = TokenLexscrow.Amounts(deposit, totalAmount, fee, receiver);
        testToken = new TestToken(buyer);
        testTokenAddr = address(testToken);
        // initialize EIP712 variables
        sigUtils = new SigUtils(testToken.domainSeparator());
        ownerPrivateKey = 0xA11CE;
        buyer = vm.addr(ownerPrivateKey);
        escrowTest = new TokenLexscrow(
            true,
            false,
            expirationTime,
            seller,
            buyer,
            testTokenAddr,
            address(0), // test without conditions first
            _amounts
        );
        escrowTestAddr = address(escrowTest);
        testToken.mintToken(buyer, totalWithFee);
    }

    function testConstructor() public {
        assertEq(escrowTest.totalAmount(), totalAmount, "totalAmount mismatch");
        assertEq(escrowTest.deposit(), deposit, "deposit mismatch");
        assertEq(escrowTest.fee(), fee, "fee mismatch");
        assertEq(escrowTest.expirationTime(), expirationTime, "Expiry time mismatch");
        assertEq(escrowTest.seller(), seller, "Seller mismatch");
        if (!escrowTest.openOffer()) assertEq(escrowTest.buyer(), buyer, "Buyer mismatch");
        else assertEq(escrowTest.buyer(), address(0), "openOffer buyer should be zero address");
    }

    function testUpdateSeller(address _addr) public {
        vm.startPrank(escrowTest.seller());
        bool _reverted;
        if (_addr == escrowTest.buyer() || _addr == escrowTest.seller()) {
            vm.expectRevert();
            _reverted = true;
        }
        escrowTest.updateSeller(_addr);
        if (!_reverted) assertEq(escrowTest.seller(), _addr, "seller address did not update");
    }

    function testUpdateBuyer(address _addr) public {
        vm.startPrank(escrowTest.buyer());
        uint256 _amtDeposited = escrowTest.amountDeposited(buyer);
        bool _reverted;
        if (_addr == escrowTest.buyer() || _addr == escrowTest.seller() || escrowTest.rejected(buyer)) {
            vm.expectRevert();
            _reverted = true;
        }
        escrowTest.updateBuyer(_addr);
        if (!_reverted) {
            assertEq(escrowTest.buyer(), _addr, "buyer address did not update");
            assertEq(escrowTest.amountDeposited(_addr), _amtDeposited, "amountDeposited mapping did not update");
        }
    }

    function testDepositTokensWithPermit(uint256 _amount, uint256 _deadline) public {
        bool _reverted;
        vm.assume(_amount <= totalWithFee);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: buyer,
            spender: escrowTestAddr,
            value: _amount,
            nonce: 0,
            deadline: _deadline
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        // check amountDeposited mapping pre-call
        uint256 _beforeAmountDeposited = escrowTest.amountDeposited(buyer);
        uint256 _beforeBalance = testToken.balanceOf(escrowTestAddr);

        vm.prank(buyer);
        if (
            _amount > totalWithFee ||
            _amount == 0 ||
            (escrowTest.openOffer() && _amount < totalWithFee) ||
            escrowTest.expirationTime() <= block.timestamp ||
            _deadline < block.timestamp ||
            escrowTest.rejected(buyer)
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.depositTokensWithPermit(permit.owner, permit.value, permit.deadline, v, r, s);
        uint256 _afterBalance = testToken.balanceOf(escrowTestAddr);
        if (permit.value > 0 && !_reverted) {
            uint256 _afterAmountDeposited = escrowTest.amountDeposited(buyer);
            assertGt(_afterAmountDeposited, _beforeAmountDeposited, "amountDeposited mapping did not update for owner");
            assertGt(_afterBalance, _beforeBalance, "balanceOf escrow did not increase");
            if (_amount > escrowTest.deposit() && _amount <= escrowTest.totalWithFee())
                assertTrue(escrowTest.deposited(), "deposited variable did not update");
            if (escrowTest.openOffer()) assertTrue(escrowTest.buyer() == msg.sender, "buyer variable did not update");
        }
    }

    function testDepositTokens(uint256 _amount) public {
        bool _reverted;
        vm.assume(_amount <= totalWithFee);

        uint256 _beforeAmountDeposited = escrowTest.amountDeposited(buyer);
        uint256 _beforeBalance = testToken.balanceOf(escrowTestAddr);

        vm.startPrank(buyer);
        testToken.approve(escrowTestAddr, _amount);
        if (
            _amount == 0 ||
            _amount + testToken.balanceOf(address(this)) > totalWithFee ||
            (escrowTest.openOffer() && _amount < totalWithFee) ||
            escrowTest.expirationTime() <= block.timestamp ||
            escrowTest.rejected(buyer)
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.depositTokens(_amount);
        uint256 _afterBalance = testToken.balanceOf(escrowTestAddr);
        if (_amount > 0 && !_reverted) {
            uint256 _afterAmountDeposited = escrowTest.amountDeposited(buyer);
            assertGt(_afterAmountDeposited, _beforeAmountDeposited, "amountDeposited mapping did not update for owner");
            assertGt(_afterBalance, _beforeBalance, "balanceOf escrow did not increase");
            if (_amount > escrowTest.deposit() && _amount <= escrowTest.totalWithFee())
                assertTrue(escrowTest.deposited(), "deposited variable did not update");
            if (escrowTest.openOffer()) assertTrue(escrowTest.buyer() == msg.sender, "buyer variable did not update");
        }
    }

    // fuzz test for different timestamps
    function testCheckIfExpired(uint256 timestamp) external {
        // assume 'totalWithFee' is in escrow
        testToken.mintToken(escrowTestAddr, escrowTest.totalWithFee());

        uint256 _preBuyerAmtWithdrawable = escrowTest.amountWithdrawable(buyer);
        uint256 _preSellerAmtWithdrawable = escrowTest.amountWithdrawable(seller);
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
                uint256 _remainder = testToken.balanceOf(escrowTestAddr) - escrowTest.deposit();
                assertEq(
                    escrowTest.amountWithdrawable(seller) - _preSellerAmtWithdrawable,
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
            assertEq(escrowTest.amountDeposited(escrowTest.buyer()), 0, "buyer's amountDeposited was not deleted");
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

    function testRejectDepositor(uint256 _deposit) external {
        // '_deposit' must be less than 'totalWithFee'
        vm.assume(_deposit <= totalWithFee);
        TokenLexscrow.Amounts memory _amounts = TokenLexscrow.Amounts(deposit, totalAmount, fee, receiver);
        openEscrowTest = new TokenLexscrow(
            true,
            true,
            expirationTime,
            seller,
            buyer,
            testTokenAddr,
            address(0),
            _amounts
        );
        address _newContract = address(openEscrowTest);
        bool _reverted;
        vm.assume(_newContract != buyer);
        // give the '_deposit' amount to the 'buyer' so they can accept the open offer
        testToken.mintToken(buyer, _deposit);
        vm.startPrank(buyer);
        if (
            _deposit + testToken.balanceOf(_newContract) > totalWithFee ||
            (openEscrowTest.openOffer() && _deposit < totalWithFee) ||
            openEscrowTest.amountDeposited(buyer) == 0
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        (bool _success, ) = _newContract.call{value: _deposit}("");

        bool _wasDeposited = openEscrowTest.deposited();
        uint256 _amountWithdrawableBefore = openEscrowTest.amountWithdrawable(buyer);
        vm.stopPrank();
        // reject depositor as 'seller'
        vm.startPrank(seller);
        if (openEscrowTest.amountDeposited(buyer) == 0 || !_success) {
            _reverted = true;
            vm.expectRevert();
        }
        openEscrowTest.rejectDepositor();
        if (!_reverted) {
            if (_wasDeposited && _success && buyer != address(0)) {
                if (openEscrowTest.openOffer())
                    assertEq(address(0), openEscrowTest.buyer(), "buyer address did not delete");
                assertTrue(!openEscrowTest.deposited(), "deposited variable did not delete");
                assertGt(
                    openEscrowTest.amountWithdrawable(buyer),
                    _amountWithdrawableBefore,
                    "buyer's amountWithdrawable did not update"
                );
            }
            assertEq(0, openEscrowTest.amountDeposited(buyer), "amountDeposited did not delete");
            assertTrue(openEscrowTest.rejected(buyer), "rejected mapping not updated");
        }
    }

    function testWithdraw(address _caller) external {
        // since we're testing only the difference in the amountWithdrawable for '_caller', no need to mock the aggregate 'pendingWithdraw'
        uint256 _preBalance = testToken.balanceOf(escrowTestAddr);
        uint256 _preAmtWithdrawable = escrowTest.amountWithdrawable(_caller);
        bool _reverted;

        vm.startPrank(_caller);
        if (escrowTest.amountWithdrawable(_caller) == 0) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.withdraw();

        assertEq(escrowTest.amountWithdrawable(_caller), 0, "not all of 'amountWithdrawable' was withdrawn");
        if (!_reverted) {
            assertGt(_preBalance, testToken.balanceOf(escrowTestAddr), "balance of escrowTest not affected");
            assertGt(_preAmtWithdrawable, escrowTest.amountWithdrawable(_caller), "amountWithdrawable not affected");
        }
    }

    // fuzz amounts
    function testExecute(uint256 _timestamp, uint256 _deposit, uint256 _totalAmount, uint256 _fee) external {
        // if 'totalWithFee' (accounting for any amounts withdrawable) isn't in escrow, expect revert
        // we just subtract buyer and seller's amountWithdrawable, if any (rather than mocking 'pendingWithdraw')
        vm.assume(
            (_fee < type(uint256).max / 2 && _totalAmount < type(uint256).max / 2) &&
                _deposit <= _totalAmount &&
                _totalAmount != 0 &&
                _timestamp > block.timestamp
        );
        TokenLexscrow.Amounts memory _amounts = TokenLexscrow.Amounts(_deposit, _totalAmount, _fee, receiver);
        fuzzEscrowTest = new TokenLexscrow(true, true, _timestamp, seller, buyer, testTokenAddr, address(0), _amounts);
        // deal 'totalWithFee' in escrow, otherwise sellerApproval() will be false (which is captured by this test anyway)
        address fuzzEscrowTestAddr = address(fuzzEscrowTest);
        testToken.mintToken(fuzzEscrowTestAddr, _totalAmount + _fee);
        uint256 _preBalance = testToken.balanceOf(fuzzEscrowTestAddr) -
            (fuzzEscrowTest.amountWithdrawable(buyer) + fuzzEscrowTest.amountWithdrawable(seller));

        uint256 _preSellerBalance = testToken.balanceOf(fuzzEscrowTest.seller());
        bool _approved;

        if (
            _preBalance != fuzzEscrowTest.totalWithFee() ||
            _deposit > _totalAmount ||
            fuzzEscrowTest.expirationTime() <= block.timestamp
        ) vm.expectRevert();
        else _approved = true;

        fuzzEscrowTest.execute();

        // will also revert if already _approved (already executed once and balance not reloaded)
        if (
            _approved ||
            _preBalance != fuzzEscrowTest.totalWithFee() ||
            _deposit > _totalAmount ||
            fuzzEscrowTest.expirationTime() <= block.timestamp
        ) vm.expectRevert();
        else _approved = true;
        fuzzEscrowTest.execute();

        uint256 _postBalance = testToken.balanceOf(fuzzEscrowTestAddr) -
            (fuzzEscrowTest.amountWithdrawable(buyer) + fuzzEscrowTest.amountWithdrawable(seller));

        // if expiry hasn't been reached, seller should be paid the totalAmount
        if (_approved && !fuzzEscrowTest.isExpired()) {
            // seller should have received totalAmount
            assertGt(_preBalance, _postBalance, "escrow's balance should have been reduced by 'totalAmount'");
            assertGt(
                testToken.balanceOf(fuzzEscrowTest.seller()),
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
                testToken.balanceOf(fuzzEscrowTest.seller()),
                _preSellerBalance,
                "seller's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
        }
    }

    /// @dev test execution with a valueCondition
    function testConditionedExecute(bool[] calldata _op) external {
        uint256 _len = _op.length;
        vm.assume(_len < 10); // reasonable array length assumption as contract will fail creation otherwise anyway
        LexscrowConditionManager.Condition[] memory _conditions = new LexscrowConditionManager.Condition[](_len);
        LexscrowConditionManager.Logic[] memory _logic = new LexscrowConditionManager.Logic[](_len);
        // load array to feed to constructor
        for (uint256 i = 0; i < _len; i++) {
            if (_op[i]) _logic[i] = LexscrowConditionManager.Logic.AND;
            else _logic[i] = LexscrowConditionManager.Logic.OR;
            BaseCondition _bC = new BaseCondition();
            _conditions[i] = LexscrowConditionManager.Condition(address(_bC), _logic[i]);
        }

        // deploy condition manager instance
        LexscrowConditionManager _manager = new LexscrowConditionManager(_conditions);

        // check conditions
        bool result;
        for (uint256 x = 0; x < _conditions.length; ) {
            if (_conditions[x].op == LexscrowConditionManager.Logic.AND) {
                result = IBaseCondition(_conditions[x].condition).checkCondition();
                if (!result) {
                    result = false;
                    break;
                }
            } else {
                result = IBaseCondition(_conditions[x].condition).checkCondition();
                if (result) break;
            }
            unchecked {
                ++x; // cannot overflow without hitting gaslimit
            }
        }
        bool callResult = _manager.checkConditions();
        if (_len == 0) assertTrue(callResult, "empty conditions should return true");
        else assertTrue(result == callResult, "condition calls do not match");

        TokenLexscrow.Amounts memory _amounts = TokenLexscrow.Amounts(deposit, totalAmount, fee, receiver);

        conditionEscrowTest = new TokenLexscrow(
            true,
            true,
            expirationTime,
            seller,
            buyer,
            testTokenAddr,
            address(_manager),
            _amounts
        );

        testToken.mintToken(address(conditionEscrowTest), totalWithFee);

        // we just subtract buyer and seller's amountWithdrawable, if any (rather than mocking 'pendingWithdraw')
        uint256 _preBalance = testToken.balanceOf(address(conditionEscrowTest)) -
            (conditionEscrowTest.amountWithdrawable(buyer) + conditionEscrowTest.amountWithdrawable(seller));
        uint256 _preSellerBalance = testToken.balanceOf(conditionEscrowTest.seller());
        uint256 _preBuyerBalance = testToken.balanceOf(conditionEscrowTest.buyer());
        uint256 _preReceiverBalance = testToken.balanceOf(conditionEscrowTest.receiver());
        bool _approved;

        if (_preBalance != conditionEscrowTest.totalWithFee() || !callResult) vm.expectRevert();
        else _approved = true;

        conditionEscrowTest.execute();

        // if expiry hasn't been reached, seller should be paid the totalAmount
        if (_approved && !conditionEscrowTest.isExpired()) {
            // seller should have received totalAmount
            assertGt(
                _preBalance,
                testToken.balanceOf(address(conditionEscrowTest)),
                "escrow's balance should have been reduced by 'totalWithFee'"
            );
            assertEq(
                testToken.balanceOf(conditionEscrowTest.seller()),
                _preSellerBalance + totalAmount,
                "seller's balance should have been increased by 'totalAmount'"
            );
            assertEq(
                testToken.balanceOf(conditionEscrowTest.receiver()),
                _preReceiverBalance + fee,
                "receiver's balance should have been increased by 'fee'"
            );
            assertEq(testToken.balanceOf(address(conditionEscrowTest)), 0, "escrow balance should be zero");
        } else if (conditionEscrowTest.isExpired()) {
            //balances should not change if expired
            assertEq(
                _preBalance,
                testToken.balanceOf(address(conditionEscrowTest)),
                "escrow's balance should not change yet if expired ('amountWithdrawable' mappings will update)"
            );
            assertEq(
                testToken.balanceOf(conditionEscrowTest.seller()),
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
