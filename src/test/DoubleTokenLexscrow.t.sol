// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/DoubleTokenLexscrow.sol";
import "src/libs/LexscrowConditionManager.sol";

/// @dev foundry framework testing of DoubleTokenLexscrow.sol including a mock ERC20Permit
/// forge t --via-ir

/// @notice Modern, minimalist, and gas-optimized ERC20 implementation for testing
/// @author Solbase (https://github.com/Sol-DAO/solbase/blob/main/src/tokens/ERC20/ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
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

    /// -----------------------------------------------------------------------
    /// ERC20 Logic
    /// -----------------------------------------------------------------------

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
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

/// @notice ERC20 + EIP-2612 implementation, including EIP712 logic.
/** @dev modified Solbase ERC20Permit implementation (https://github.com/Sol-DAO/solbase/blob/main/src/tokens/ERC20/extensions/ERC20Permit.sol)
 ** plus Solbase EIP712 implementation (https://github.com/Sol-DAO/solbase/blob/main/src/utils/EIP712.sol)*/
abstract contract ERC20Permit is ERC20 {
    /// @dev `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
    bytes32 internal constant DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 internal hashedDomainName;
    bytes32 internal hashedDomainVersion;
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
        initialChainId = block.chainid;
        DOMAIN_SEPARATOR = _computeDomainSeparator();
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
        if (block.chainid == initialChainId) {
            return DOMAIN_SEPARATOR;
        } else {
            return _computeDomainSeparator();
        }
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
    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMITTYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    bytes32 internal DOMAIN_SEPARATOR;

    // mockToken.domainSeparator()
    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
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

/// @notice Second ERC20 token contract with 6 decimals
/// @dev not burnable or mintable; ERC20Permit implemented
contract TestToken2 is ERC20Permit {
    string public constant TESTTOKEN_NAME = "Test Token 2";
    string public constant TESTTOKEN_SYMBOL = "TEST2";
    string public constant TESTTOKEN_VERSION = "1";
    uint8 public constant TESTTOKEN_DECIMALS = 6; //test difference decimals amount

    constructor(address _user) ERC20Permit(TESTTOKEN_NAME, TESTTOKEN_SYMBOL, TESTTOKEN_VERSION, TESTTOKEN_DECIMALS) {
        _mint(_user, 1e24);
    }

    //allow anyone to mint the token for testing
    function mintToken(address to, uint256 amt) public {
        _mint(to, amt);
    }
}

/// @notice test contract for DoubleTokenLexscrow using Foundry
contract DoubleTokenLexscrowTest is Test {
    struct PreBalances {
        uint256 _preBalance;
        uint256 _preBalance2;
        uint256 _preBuyerBalance;
        uint256 _preSellerBalance;
        uint256 _preReceiverBalance2;
        uint256 _preReceiverBalance;
    }

    TestToken internal testToken;
    TestToken2 internal testToken2;
    DoubleTokenLexscrow internal escrowTest;
    SigUtils internal sigUtils;

    uint256 internal constant totalAmount = 1e16;
    uint256 internal constant fee = 1e12;
    uint256 internal constant expirationTime = 5e25;
    uint256 internal constant buyerPrivateKey = 0xA11CE;
    uint256 internal constant sellerPrivateKey = 0xb000E;

    bool internal baseCondition;
    address internal buyer = vm.addr(buyerPrivateKey);
    address internal seller = vm.addr(sellerPrivateKey);
    // using zero address because 'receiver' is retrieved at 'execute()' via an internal 'DoubleTokenLexscrowFactory()' call;
    // it has a fallback to address(0). Since the fallback will occur every time with this test and receiver functionality is tested in DoubleTokenLexscrowFactoryTest, hardcode address(0)
    address internal receiver = address(0);
    address escrowTestAddr;
    address testTokenAddr;
    address testToken2Addr;
    uint256 internal deployTime = block.timestamp;

    // testing basic functionalities: refund, no condition, identified parties, known ERC20 compliance
    function setUp() public {
        testToken = new TestToken(buyer);
        testToken2 = new TestToken2(seller);
        testTokenAddr = address(testToken);
        testToken2Addr = address(testToken2);
        // initialize EIP712 variables
        sigUtils = new SigUtils(testToken.domainSeparator());
        DoubleTokenLexscrow.Amounts memory _amounts = DoubleTokenLexscrow.Amounts(
            totalAmount,
            fee,
            totalAmount,
            fee,
            receiver
        );
        escrowTest = new DoubleTokenLexscrow(
            true,
            expirationTime,
            seller,
            buyer,
            testTokenAddr,
            testToken2Addr,
            address(0), // test without conditions first
            address(0), // receipt's tests are separate, and receipt.sol does not affect LeXscrow execution
            _amounts
        );
        escrowTestAddr = address(escrowTest);
        //give parties tokens
        testToken.mintToken(buyer, totalAmount + fee);
        testToken2.mintToken(seller, totalAmount + fee);
    }

    function testConstructor() public {
        (bool successBalanceOf1, bytes memory dataBalanceOf1) = testTokenAddr.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        (bool successBalanceOf2, bytes memory dataBalanceOf2) = testToken2Addr.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        assertTrue(successBalanceOf1, "ERC20 check failed");
        assertGt(dataBalanceOf1.length, 0, "ERC20 check failed");
        assertGt(testTokenAddr.code.length, 0, "ERC20 check failed");
        assertTrue(successBalanceOf2, "Second ERC20 check failed");
        assertGt(dataBalanceOf2.length, 0, "Second ERC20 check failed");
        assertGt(testToken2Addr.code.length, 0, "Second ERC20 check failed");
        assertEq(escrowTest.totalAmount1(), totalAmount, "totalAmount1 mismatch");
        assertEq(escrowTest.totalAmount2(), totalAmount, "totalAmount2 mismatch");
        assertEq(escrowTest.fee1(), fee, "fee1 mismatch");
        assertEq(escrowTest.fee2(), fee, "fee2 mismatch");
        assertEq(escrowTest.expirationTime(), expirationTime, "Expiry time mismatch");
    }

    function testUpdateSeller(address _addr) public {
        vm.startPrank(escrowTest.seller());
        bool _reverted;
        if (_addr == address(0) || _addr == escrowTest.seller() || _addr == escrowTest.buyer()) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.updateSeller(_addr);
        if (!_reverted) assertEq(escrowTest.seller(), _addr, "seller address did not update");
    }

    function testUpdateBuyer(address _addr) public {
        vm.startPrank(escrowTest.buyer());
        bool _reverted;
        if (_addr == address(0) || _addr == escrowTest.seller() || _addr == escrowTest.buyer()) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.updateBuyer(_addr);
        if (!_reverted) assertEq(escrowTest.buyer(), _addr, "buyer address did not update");
    }

    function testBuyerDepositTokensWithPermit(bool _token1Deposit, uint256 _amount, uint256 _deadline) public {
        bool _reverted;
        vm.assume(_amount <= totalAmount + fee);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: buyer,
            spender: escrowTestAddr,
            value: _amount,
            nonce: 0,
            deadline: _deadline
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, digest);
        uint256 _beforeBalance = testToken.balanceOf(escrowTestAddr);

        vm.prank(buyer);
        if (
            !_token1Deposit ||
            _amount > totalAmount + fee ||
            _amount > testToken.balanceOf(buyer) ||
            (escrowTest.openOffer() && _amount < totalAmount + fee) ||
            escrowTest.expirationTime() <= block.timestamp ||
            _deadline < block.timestamp
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.depositTokensWithPermit(_token1Deposit, permit.owner, permit.value, permit.deadline, v, r, s);
        uint256 _afterBalance = testToken.balanceOf(escrowTestAddr);
        if (permit.value > 0 && !_reverted) {
            assertGt(_afterBalance, _beforeBalance, "balanceOf escrow did not increase");
            if (_amount == escrowTest.totalAmount1() + escrowTest.fee1() && escrowTest.openOffer())
                assertTrue(escrowTest.buyer() == buyer, "buyer variable did not update");
        }
    }

    function testSellerDepositTokensWithPermit(bool _token1Deposit, uint256 _amount, uint256 _deadline) public {
        bool _reverted;
        vm.assume(_amount <= totalAmount + fee);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: seller,
            spender: escrowTestAddr,
            value: _amount,
            nonce: 0,
            deadline: _deadline
        });
        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, digest);
        uint256 _beforeBalance = testToken2.balanceOf(escrowTestAddr);

        vm.prank(seller);
        if (
            _token1Deposit ||
            _amount > totalAmount + fee ||
            _amount > testToken2.balanceOf(seller) ||
            (escrowTest.openOffer() && _amount < totalAmount + fee) ||
            escrowTest.expirationTime() <= block.timestamp ||
            _deadline < block.timestamp
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.depositTokensWithPermit(_token1Deposit, permit.owner, permit.value, permit.deadline, v, r, s);
        uint256 _afterBalance = testToken2.balanceOf(escrowTestAddr);
        if (permit.value > 0 && !_reverted) {
            assertGt(_afterBalance, _beforeBalance, "balanceOf escrow did not increase");
            if (_amount == escrowTest.totalAmount2() + escrowTest.fee2() && escrowTest.openOffer())
                assertTrue(escrowTest.seller() == seller, "seller variable did not update");
        }
    }

    function testBuyerDepositTokens(bool _token1Deposit, uint256 _amount) public {
        bool _reverted;
        vm.assume(_amount <= totalAmount + fee);
        uint256 _beforeBalance = testToken.balanceOf(escrowTestAddr);

        vm.startPrank(buyer);
        testToken.approve(escrowTestAddr, _amount);
        if (
            !_token1Deposit ||
            _amount + testToken.balanceOf(address(this)) > totalAmount + fee ||
            (escrowTest.openOffer() && _amount < totalAmount + fee) ||
            escrowTest.expirationTime() <= block.timestamp
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.depositTokens(_token1Deposit, _amount);
        uint256 _afterBalance = testToken.balanceOf(escrowTestAddr);
        if (_amount > 0 && !_reverted && _token1Deposit) {
            assertGt(_afterBalance, _beforeBalance, "balanceOf escrow did not increase");
            if (_afterBalance == escrowTest.totalAmount1() + escrowTest.fee1() && escrowTest.openOffer())
                assertTrue(escrowTest.buyer() == msg.sender, "buyer variable did not update");
        }
    }

    function testSellerDepositTokens(bool _token1Deposit, uint256 _amount) public {
        bool _reverted;
        vm.assume(_amount <= totalAmount + fee);
        uint256 _beforeBalance = testToken2.balanceOf(escrowTestAddr);

        vm.startPrank(seller);
        testToken2.approve(escrowTestAddr, _amount);
        if (
            _token1Deposit || // seller will deposit token2, so _token1Deposit should be false for this
            _amount + testToken2.balanceOf(address(this)) > totalAmount + fee ||
            (escrowTest.openOffer() && _amount < totalAmount + fee) ||
            escrowTest.expirationTime() <= block.timestamp
        ) {
            _reverted = true;
            vm.expectRevert();
        }
        escrowTest.depositTokens(_token1Deposit, _amount);
        uint256 _afterBalance = testToken2.balanceOf(escrowTestAddr);
        if (_amount > 0 && !_reverted && !_token1Deposit) {
            assertGt(_afterBalance, _beforeBalance, "balanceOf escrow did not increase");
            if (_afterBalance == escrowTest.totalAmount2() + escrowTest.fee2() && escrowTest.openOffer())
                assertTrue(escrowTest.seller() == msg.sender, "seller variable did not update");
        }
    }

    // fuzz test for different timestamps
    function testCheckIfExpired(uint256 timestamp) external {
        // assume total amounts are in escrow
        testToken.mintToken(address(escrowTest), escrowTest.totalAmount1());
        testToken2.mintToken(address(escrowTest), escrowTest.totalAmount2());
        uint256 _preBalance = testToken.balanceOf(escrowTestAddr);
        uint256 _preBalance2 = testToken2.balanceOf(escrowTestAddr);
        uint256 _preBuyerBalance = testToken.balanceOf(buyer);
        uint256 _preSellerBalance = testToken2.balanceOf(seller);
        bool _isAlreadyExpired = escrowTest.isExpired();

        vm.warp(timestamp);
        escrowTest.checkIfExpired();
        // ensure, if timestamp is past expiration time and thus escrow is expired, boolean is updated and tokens are returned to the applicable parties
        // else, isExpired() should be false and balances should be unchanged
        if (escrowTest.expirationTime() <= timestamp && !_isAlreadyExpired) {
            assertTrue(escrowTest.isExpired());

            if (_preBalance != 0) {
                assertGt(_preBalance, testToken.balanceOf(escrowTestAddr), "balance of escrowTest not affected");
                assertGt(testToken.balanceOf(buyer), _preBuyerBalance, "buyer's tokens not returned");
            }
            if (_preBalance2 != 0) {
                assertGt(_preBalance2, testToken2.balanceOf(escrowTestAddr), "balance2 of escrowTest not affected");
                assertGt(testToken2.balanceOf(seller), _preSellerBalance, "seller's tokens not returned");
            }
        } else {
            assertTrue(!escrowTest.isExpired());
            assertEq(testToken2.balanceOf(seller), _preSellerBalance, "seller's token2 balance should be unchanged");
            assertEq(testToken.balanceOf(buyer), _preBuyerBalance, "buyer's token1 balance should be unchanged");
        }
    }

    function testExecute() external {
        // deal each total amount and fee in escrow
        testToken.mintToken(escrowTestAddr, escrowTest.totalAmount1() + escrowTest.fee1());
        testToken2.mintToken(escrowTestAddr, escrowTest.totalAmount2() + escrowTest.fee2());

        PreBalances memory preBalances = PreBalances(
            testToken.balanceOf(escrowTestAddr),
            testToken2.balanceOf(escrowTestAddr),
            testToken2.balanceOf(buyer),
            testToken.balanceOf(seller),
            testToken2.balanceOf(receiver),
            testToken.balanceOf(receiver)
        );
        bool _executed;
        if (
            escrowTest.isExpired() ||
            testToken.balanceOf(escrowTestAddr) != escrowTest.totalAmount1() + escrowTest.fee1() ||
            testToken2.balanceOf(escrowTestAddr) != escrowTest.totalAmount2() + escrowTest.fee2()
        ) vm.expectRevert();
        else _executed = true;
        escrowTest.execute();
        if (_executed) {
            assertGt(
                preBalances._preBalance,
                testToken.balanceOf(escrowTestAddr),
                "escrow's balance should have been reduced"
            );
            assertGt(
                preBalances._preBalance2,
                testToken2.balanceOf(escrowTestAddr),
                "escrow's balance2 should have been reduced"
            );
            assertGt(
                testToken2.balanceOf(buyer),
                preBalances._preBuyerBalance,
                "buyer's balance of token2 should have been increased"
            );
            assertGt(
                testToken.balanceOf(seller),
                preBalances._preSellerBalance,
                "seller's balance of token should have been increased"
            );
            assertGt(
                testToken2.balanceOf(receiver),
                preBalances._preReceiverBalance2,
                "receiver's balance of token2 should have been increased"
            );
            assertGt(
                testToken.balanceOf(receiver),
                preBalances._preReceiverBalance,
                "receiver's balance of token1 should have been increased"
            );
            assertEq(
                testToken2.balanceOf(receiver) - preBalances._preReceiverBalance2,
                escrowTest.fee2(),
                "receiver's balance of token2 should have increased by fee2"
            );
            assertEq(
                testToken.balanceOf(receiver) - preBalances._preReceiverBalance,
                escrowTest.fee1(),
                "receiver's balance of token should have increased by fee1"
            );
            assertEq(testToken.balanceOf(escrowTestAddr), 0, "escrow balance should be zero");
            assertEq(testToken2.balanceOf(escrowTestAddr), 0, "escrow balance2 should be zero");
        }
    }

    /// @dev test execution with a condition
    function testConditionedExecute(bool _baseCondition, bool _operator) external {
        // use bool _operator input to fuzz the Logic enum
        LexscrowConditionManager.Logic _log;
        if (_operator) _log = LexscrowConditionManager.Logic.AND;
        else _log = LexscrowConditionManager.Logic.OR;

        DoubleTokenLexscrow.Amounts memory _amounts = DoubleTokenLexscrow.Amounts(
            totalAmount,
            fee,
            totalAmount,
            fee,
            receiver
        );
        baseCondition = _baseCondition; // update to fuzzed bool for checkCondition call
        LexscrowConditionManager.Condition[] memory _cond = new LexscrowConditionManager.Condition[](1);
        _cond[0] = LexscrowConditionManager.Condition(address(this), _log);
        LexscrowConditionManager _manager = new LexscrowConditionManager(_cond); // conditionManager fuzz testing done in LexscrowConditionManagerTest
        /// feed 'address(this)' as the condition to return the fuzzed bool value from 'checkCondition()'
        DoubleTokenLexscrow conditionEscrowTest = new DoubleTokenLexscrow(
            true,
            expirationTime,
            seller,
            buyer,
            testTokenAddr,
            testToken2Addr,
            address(_manager),
            address(0),
            _amounts
        );
        address conditionEscrowTestAddr = address(conditionEscrowTest);
        testToken.mintToken(conditionEscrowTestAddr, conditionEscrowTest.totalAmount1() + conditionEscrowTest.fee1());
        testToken2.mintToken(conditionEscrowTestAddr, conditionEscrowTest.totalAmount2() + conditionEscrowTest.fee2());

        PreBalances memory preBalances = PreBalances(
            testToken.balanceOf(conditionEscrowTestAddr),
            testToken2.balanceOf(conditionEscrowTestAddr),
            testToken2.balanceOf(buyer),
            testToken.balanceOf(seller),
            testToken2.balanceOf(receiver),
            testToken.balanceOf(receiver)
        );
        bool _executed;
        if (
            !_baseCondition ||
            conditionEscrowTest.isExpired() ||
            testToken.balanceOf(conditionEscrowTestAddr) !=
            conditionEscrowTest.totalAmount1() + conditionEscrowTest.fee1() ||
            testToken2.balanceOf(conditionEscrowTestAddr) !=
            conditionEscrowTest.totalAmount2() + conditionEscrowTest.fee2()
        ) vm.expectRevert();
        else _executed = true;
        conditionEscrowTest.execute();
        if (_executed) {
            assertGt(
                preBalances._preBalance,
                testToken.balanceOf(conditionEscrowTestAddr),
                "escrow's balance should have been reduced"
            );
            assertGt(
                preBalances._preBalance2,
                testToken2.balanceOf(conditionEscrowTestAddr),
                "escrow's balance2 should have been reduced"
            );
            assertGt(
                testToken2.balanceOf(buyer),
                preBalances._preBuyerBalance,
                "buyer's balance of token2 should have been increased"
            );
            assertGt(
                testToken.balanceOf(seller),
                preBalances._preSellerBalance,
                "seller's balance of token should have been increased"
            );
            assertGt(
                testToken2.balanceOf(receiver),
                preBalances._preReceiverBalance2,
                "receiver's balance of token2 should have been increased"
            );
            assertGt(
                testToken.balanceOf(receiver),
                preBalances._preReceiverBalance,
                "receiver's balance of token should have been increased"
            );
            assertEq(
                testToken2.balanceOf(receiver) - preBalances._preReceiverBalance2,
                conditionEscrowTest.fee2(),
                "receiver's balance of token2 should have increased by fee2"
            );
            assertEq(
                testToken.balanceOf(receiver) - preBalances._preReceiverBalance,
                conditionEscrowTest.fee1(),
                "receiver's balance of token should have increased by fee1"
            );
            assertEq(testToken.balanceOf(conditionEscrowTestAddr), 0, "escrow balance should be zero");
            assertEq(testToken2.balanceOf(conditionEscrowTestAddr), 0, "escrow balance2 should be zero");
        }
    }

    function testElectToTerminate() external {
        vm.assume(escrowTest.isExpired() == false);
        // deal each total amount and fee in escrow
        testToken.mintToken(escrowTestAddr, escrowTest.totalAmount1() + escrowTest.fee1());
        testToken2.mintToken(escrowTestAddr, escrowTest.totalAmount2() + escrowTest.fee2());

        PreBalances memory preBalances = PreBalances(
            testToken.balanceOf(escrowTestAddr),
            testToken2.balanceOf(escrowTestAddr),
            testToken.balanceOf(buyer),
            testToken2.balanceOf(seller),
            testToken2.balanceOf(receiver),
            testToken.balanceOf(receiver)
        );
        if (escrowTest.isExpired()) vm.expectRevert();
        vm.prank(seller);
        escrowTest.electToTerminate(true);
        if (escrowTest.isExpired()) vm.expectRevert();
        vm.prank(buyer);
        escrowTest.electToTerminate(true);
        if (escrowTest.isExpired()) {
            assertGt(
                preBalances._preBalance,
                testToken.balanceOf(escrowTestAddr),
                "escrow's balance should have been reduced"
            );
            assertGt(
                preBalances._preBalance2,
                testToken2.balanceOf(escrowTestAddr),
                "escrow's balance2 should have been reduced"
            );
            assertGt(
                testToken.balanceOf(buyer),
                preBalances._preBuyerBalance,
                "buyer's balance of token1 should have been increased"
            );
            assertGt(
                testToken2.balanceOf(seller),
                preBalances._preSellerBalance,
                "seller's balance of token2 should have been increased"
            );
            assertEq(
                testToken2.balanceOf(receiver),
                preBalances._preReceiverBalance2,
                "receiver's balance of token2 should not change"
            );
            assertEq(
                testToken.balanceOf(receiver),
                preBalances._preReceiverBalance,
                "receiver's balance of token1 should not change"
            );
            assertEq(testToken.balanceOf(escrowTestAddr), 0, "escrow balance should be zero");
            assertEq(testToken2.balanceOf(escrowTestAddr), 0, "escrow balance2 should be zero");
        }
    }

    /// @dev mock a BaseCondition call
    function checkCondition() public view returns (bool) {
        return (baseCondition);
    }
}
