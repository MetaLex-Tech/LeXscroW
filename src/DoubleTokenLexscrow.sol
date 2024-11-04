//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

/*
*********************************
██╗     ███████╗██╗   ██╗███████╗███████╗██████╗ ███████╗██╗    ██╗
██║     ██╔════╝ ██║ ██╔╝██╔════╝██╔════╝██╔══██╗██╔══██║██║    ██║
██║     █████╗    ╚██╔╝  ███████╗██║     ██████╔╝██║  ██║██║ █╗ ██║
██║     ██╔══╝   ██╔╝██╗ ╚════██║██║     ██╔══██╗██║  ██║██║███╗██║
███████╗███████╗██║   ██╗███████║███████╗██║  ██║███████║╚███╔███╔╝
╚══════╝╚══════╝╚═╝   ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝ 
                                 ***********************************
                                                                  */

/// @notice interface to `LexscrowConditionManager.sol` for condition checks
interface ILexscrowConditionManager {
    function checkConditions(bytes memory data) external view returns (bool result);
}

/// @notice interface for ERC-20 standard token contract, including EIP2612 permit function
interface IERC20Permit {
    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function totalSupply() external view returns (uint256);
}

/// @notice interface to Receipt.sol, which returns USD-value receipts for a provided token amount for supported tokens
interface IReceipt {
    function printReceipt(address token, uint256 tokenAmount, uint256 decimals) external returns (uint256, uint256);
}

/// @notice gas-efficient ERC20 safe transfers that revert on failure, `SafeTransfer()` and `SafeTransferFrom()`
abstract contract SafeTransferLib {
    /// @dev The ERC20 `transfer` has failed.
    error TransferFailed();
    /// @dev The ERC20 `transferFrom` has failed.
    error TransferFromFailed();

    /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`. Reverts upon failure.
    function safeTransfer(address token, address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and(
                    // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`. Reverts upon failure.
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x60, amount) // Store the `amount` argument.
            mstore(0x40, to) // Store the `to` argument.
            mstore(0x2c, shl(96, from)) // Store the `from` argument.
            mstore(0x0c, 0x23b872dd000000000000000000000000) // `transferFrom(address,address,uint256)`.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and(
                    // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x7939f424) // `TransferFromFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }
}

/// @notice Gas-optimized reentrancy protection
abstract contract ReentrancyGuard {
    /// @dev Equivalent to: `uint72(bytes9(keccak256("_REENTRANCY_GUARD_SLOT")))`.
    /// 9 bytes is large enough to avoid collisions with lower slots,
    /// but not too large to result in excessive bytecode bloat.
    uint256 private constant _REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;
    error Reentrancy();

    /// @dev Guards a function from reentrancy.
    modifier nonReentrant() virtual {
        /// @solidity memory-safe-assembly
        assembly {
            if eq(sload(_REENTRANCY_GUARD_SLOT), address()) {
                mstore(0x00, 0xab143c06) // `Reentrancy()`.
                revert(0x1c, 0x04)
            }
            sstore(_REENTRANCY_GUARD_SLOT, address())
        }
        _;
        /// @solidity memory-safe-assembly
        assembly {
            sstore(_REENTRANCY_GUARD_SLOT, codesize())
        }
    }
}

/**
 * @title       DoubleTokenLexscrow
 *
 * @author      MetaLeX Labs, Inc.
 *
 * @notice      Non-custodial bilateral smart escrow contract for non-rebasing ERC20 tokens, supporting:
 *      deposit tokens via approve+transfer or EIP2612 permit signature
 *      identified parties or open offer (party that deposits totalAmount1 of token1 becomes `buyer`, and vice versa)
 *      escrow expiration denominated in seconds
 *      optional conditions for execution (contingent execution based on oracle-fed external data value, signatures, etc.)
 *      buyer and seller addresses replaceable by applicable party
 *      no separate approval is necessary as both sides must deposit value (which serves as signalled approval to execute)
 *      mutual termination option, which returns deposited tokens to applicable parties
 *      automatically refunded to buyer and seller, as applicable, at expiry if not executed
 *      if executed, re-usable by parties until expiration time
 *
 * @dev         Contract executes and simultaneously releases `totalAmount1` to `seller` and `totalAmount2` to `buyer` iff:
 *      (1) `buyer` and `seller` have respectively deposited `totalAmount1` + `fee1` of `token1` and `totalAmount2` + `fee2` of `token2`
 *      (2) token1.balanceOf(address(this)) >= `totalAmount1` + `fee1` && token2.balanceOf(address(this)) >= `totalAmount2` + `fee2`
 *      (3) `expirationTime` > block.timestamp
 *      (4) if there is/are condition(s), such condition(s) is/are satisfied
 *
 *      Otherwise, deposited amounts are returned to the respective parties if this contract expires, or if both parties elect to terminate early.
 *
 *      Variables are public for interface friendliness and enabling getters.
 **/
contract DoubleTokenLexscrow is ReentrancyGuard, SafeTransferLib {
    struct Amounts {
        uint256 totalAmount1;
        uint256 fee1;
        uint256 totalAmount2;
        uint256 fee2;
        address receiver;
    }

    // internal visibility for gas savings, as each tokenContract is public and bears the same contract address as its respective interface
    IERC20Permit internal immutable token1; // tokenContract1
    IERC20Permit internal immutable token2; // tokenContract2

    IReceipt internal immutable receipt;
    ILexscrowConditionManager public immutable conditionManager;
    address public immutable tokenContract1;
    address public immutable tokenContract2;
    address public immutable receiver;
    bool public immutable openOffer;
    uint256 public immutable expirationTime;
    uint256 public immutable totalAmount1;
    uint256 public immutable totalAmount2;
    uint256 public immutable fee1;
    uint256 public immutable fee2;

    address public buyer;
    address public seller;
    bool public isExpired;

    /// @notice address mapped to whether they have consented to early termination and return of deposited tokens
    mapping(address => bool) public terminationConsent;

    ///
    /// EVENTS
    ///

    event DoubleTokenLexscrow_AmountReceived(address token, uint256 tokenAmount);
    event DoubleTokenLexscrow_BuyerUpdated(address newBuyer);
    event DoubleTokenLexscrow_Deployed(
        bool openOffer,
        uint256 expirationTime,
        address seller,
        address buyer,
        address tokenContract1,
        address tokenContract2,
        address conditionManager,
        Amounts amounts
    );
    event DoubleTokenLexscrow_Executed(uint256 indexed effectiveTime, address seller, address buyer, address receiver);
    event DoubleTokenLexscrow_Expired();
    event DoubleTokenLexscrow_Terminated();
    event DoubleTokenLexscrow_TotalAmountInEscrow(address depositor, address token);
    event DoubleTokenLexscrow_SellerUpdated(address newSeller);

    ///
    /// ERRORS
    ///

    error DoubleTokenLexscrow_AmountNotApprovedForTransferFrom();
    error DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
    error DoubleTokenLexscrow_IsExpired();
    error DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
    error DoubleTokenLexscrow_NotBuyer();
    error DoubleTokenLexscrow_NotParty();
    error DoubleTokenLexscrow_NotSeller();
    error DoubleTokenLexscrow_NonERC20Contract();
    error DoubleTokenLexscrow_NotReadyToExecute();
    error DoubleTokenLexscrow_PartiesHaveSameAddress();
    error DoubleTokenLexscrow_SameTokenContracts();
    error DoubleTokenLexscrow_ZeroAmount();
    error DoubleTokenLexscrow_ZeroAddress();

    ///
    /// FUNCTIONS
    ///

    /// @notice constructs the DoubleTokenLexscrow smart escrow contract. Arranger MUST verify that _tokenContract is both ERC20- and EIP2612- standard compliant and that the conditions are proper, as neither address(this) nor the LeXscrow Factory contract fully perform such checks.
    /// @param _openOffer whether this escrow is open to any prospective `buyer` or `seller`. A `buyer` assents by depositing `totalAmount1` + `fee1` of `token1` to address(this), and a `seller` assents by depositing `totalAmount2` + `fee2` of `token2` to address(this) via the applicable function
    /// @param _expirationTime _expirationTime in seconds (Unix time), which will be compared against block.timestamp. Because tokens will only be released upon execution or returned after expiry, submitting a reasonable expirationTime is imperative
    /// @param _seller the seller's address, depositor of the `totalAmount2` + `fee2` (in token2) and recipient of the `totalAmount1` (in token1) if the contract executes. Automatically updated by successful `depositTokensWithPermit()` or `depositTokens()` if `openOffer`
    /// @param _buyer the buyer's address, depositor of the `totalAmount1` + `fee1` (in token1) and recipient of the `totalAmount2` (in token2) if the contract executes. Automatically updated by successful `depositTokensWithPermit()` or `depositTokens()` if `openOffer`
    /// @param _tokenContract1 contract address for the ERC20 token used in this DoubleTokenLexscrow as `token1`
    /// @param _tokenContract2 contract address for the ERC20 token used in this DoubleTokenLexscrow as `token2`; must be different than `_tokenContract1`
    /// @param _conditionManager contract address for LexscrowConditionManager.sol, or address(0) if none
    /// @param _receipt contract address for Receipt.sol contract
    /// @param _amounts struct containing the total amounts and fees as follows:
    /// _totalAmount1: total amount of `tokenContract1` ultimately intended for `seller`, not including fees
    /// _fee1: amount of `tokenContract1` that also must be deposited, which will be paid to the fee receiver
    /// _totalAmount2: total amount of `tokenContract2` ultimately intended for `buyer`, not including fees
    /// _fee2: amount of `tokenContract2` that also must be deposited, which will be paid to the fee receiver
    /// _receiver: address to receive `_fee1` and `_fee2`
    constructor(
        bool _openOffer,
        uint256 _expirationTime,
        address _seller,
        address _buyer,
        address _tokenContract1,
        address _tokenContract2,
        address _conditionManager,
        address _receipt,
        Amounts memory _amounts
    ) {
        if (_amounts.totalAmount1 == 0 || _amounts.totalAmount2 == 0) revert DoubleTokenLexscrow_ZeroAmount();
        if (
            _tokenContract1 == address(0) ||
            _tokenContract2 == address(0) ||
            ((!_openOffer && _buyer == address(0)) || (!_openOffer && _seller == address(0)))
        ) revert DoubleTokenLexscrow_ZeroAddress();
        if (_seller == _buyer) revert DoubleTokenLexscrow_PartiesHaveSameAddress();
        if (_expirationTime <= block.timestamp) revert DoubleTokenLexscrow_IsExpired();
        if (_tokenContract1 == _tokenContract2) revert DoubleTokenLexscrow_SameTokenContracts();

        openOffer = _openOffer;
        expirationTime = _expirationTime;
        if (!openOffer) {
            seller = _seller;
            buyer = _buyer;
        }
        totalAmount1 = _amounts.totalAmount1;
        totalAmount2 = _amounts.totalAmount2;
        fee1 = _amounts.fee1;
        fee2 = _amounts.fee2;
        receiver = _amounts.receiver;
        tokenContract1 = _tokenContract1;
        tokenContract2 = _tokenContract2;

        conditionManager = ILexscrowConditionManager(_conditionManager);
        receipt = IReceipt(_receipt);
        token1 = IERC20Permit(_tokenContract1);
        token2 = IERC20Permit(_tokenContract2);

        // check ERC20 compliance, calls will revert if not compliant with interface
        if (
            token1.totalSupply() == 0 ||
            token1.balanceOf(address(this)) < 0 ||
            token2.totalSupply() == 0 ||
            token2.balanceOf(address(this)) < 0
        ) revert DoubleTokenLexscrow_NonERC20Contract();

        emit DoubleTokenLexscrow_Deployed(
            _openOffer,
            _expirationTime,
            _seller,
            _buyer,
            _tokenContract1,
            _tokenContract2,
            _conditionManager,
            _amounts
        );
    }

    /// @notice deposit value to `address(this)` by permitting address(this) to safeTransferFrom `_amount` of tokens from `_depositor`
    /** @dev if `_depositor` == `sender`, deposit token2; otherwise, deposit token1; this enables open offers for any prospective buyer to deposit
     ** max `_amount` limit of `totalAmount1` + `fee1` or `totalAmount2` + `fee2` as applicable, and if such amount is already held or escrow has expired, revert.
     ** also updates `seller` or `buyer` to `_depositor` (depending on token used) if true `openOffer`, and
     ** records amount deposited by `_depositor` for refundability at expiry  */
    /// @param _token1Deposit if true, depositing `token1`; if false, depositing `token2`
    /// @param _depositor depositor of the `_amount` of tokens, often msg.sender/originating EOA, but if !`openOffer`, must == `buyer` if `token1Deposit` or == `seller` if `token2Deposit`
    /// @param _amount amount of tokens deposited. If `openOffer`, `_amount` must == `totalAmount1` + `fee1` or `totalAmount2` + `fee2` as applicable
    /// @param _deadline deadline for usage of the permit approval signature
    /// @param v ECDSA sig parameter
    /// @param r ECDSA sig parameter
    /// @param s ECDSA sig parameter
    function depositTokensWithPermit(
        bool _token1Deposit,
        address _depositor,
        uint256 _amount,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        if (expirationTime <= block.timestamp) revert DoubleTokenLexscrow_IsExpired();
        if (_amount == 0) revert DoubleTokenLexscrow_ZeroAmount();
        uint256 _permitAmount = _amount;
        bool _openOffer = openOffer;

        if (!_token1Deposit) {
            if (!_openOffer && _depositor != seller) revert DoubleTokenLexscrow_NotSeller();
            uint256 _totalWithFee2 = totalAmount2 + fee2;
            uint256 _balance2 = token2.balanceOf(address(this)) + _amount;

            if (_balance2 > _totalWithFee2) {
                uint256 _surplus = _balance2 - _totalWithFee2;
                // either reduce `_amount` by the surplus, or revert if `_amount` is less than the surplus
                if (_amount - _surplus > 0) _amount -= _surplus;
                else revert DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
            }
            if (_openOffer && _balance2 < _totalWithFee2) revert DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
            address _tokenContract2 = tokenContract2;

            // whether exact amount deposited or adjusted for surplus, total amount will be in escrow
            if (_balance2 >= _totalWithFee2) {
                // if this DoubleTokenLexscrow is an open offer and was not yet accepted by tendering full amount, make depositing address the `seller`
                if (_openOffer) {
                    seller = _depositor;
                    emit DoubleTokenLexscrow_SellerUpdated(_depositor);
                }
                emit DoubleTokenLexscrow_TotalAmountInEscrow(_depositor, _tokenContract2);
            }
            emit DoubleTokenLexscrow_AmountReceived(_tokenContract2, _amount);

            token2.permit(_depositor, address(this), _permitAmount, _deadline, v, r, s);
            safeTransferFrom(_tokenContract2, _depositor, address(this), _amount);
        } else {
            if (!_openOffer && _depositor != buyer) revert DoubleTokenLexscrow_NotBuyer();
            uint256 _totalWithFee1 = totalAmount1 + fee1;
            uint256 _balance1 = token1.balanceOf(address(this)) + _amount;

            if (_balance1 > _totalWithFee1) {
                uint256 _surplus = _balance1 - _totalWithFee1;
                // either reduce `_amount` by the surplus, or revert if `_amount` is less than the surplus
                if (_amount - _surplus > 0) _amount -= _surplus;
                else revert DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
            }
            if (_openOffer && _balance1 < _totalWithFee1) revert DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
            address _tokenContract1 = tokenContract1;

            // whether exact amount deposited or adjusted for surplus, total amount will be in escrow
            if (_balance1 >= _totalWithFee1) {
                // if this DoubleTokenLexscrow is an open offer and was not yet accepted by tendering full amount, make depositing address the `buyer`
                if (_openOffer) {
                    buyer = _depositor;
                    emit DoubleTokenLexscrow_BuyerUpdated(_depositor);
                }
                emit DoubleTokenLexscrow_TotalAmountInEscrow(_depositor, _tokenContract1);
            }
            emit DoubleTokenLexscrow_AmountReceived(_tokenContract1, _amount);

            token1.permit(_depositor, address(this), _permitAmount, _deadline, v, r, s);
            safeTransferFrom(_tokenContract1, _depositor, address(this), _amount);
        }
    }

    /// @notice deposit value to `address(this)` via safeTransferFrom `_amount` of tokens from msg.sender; provided msg.sender has approved address(this) to transferFrom such `amount`
    /** @dev msg.sender must have called approve(address(this), _amount) on the proper token contract prior to calling this function
     ** max `_amount` limit of `totalAmount1` + `fee1` or `totalAmount2` + `fee2` as applicable, and if such amount is already held or escrow has expired, revert.
     ** updates `seller` or `buyer` to msg.sender (depending on token used) if true `openOffer`, and
     ** records amount deposited by msg.sender for refundability at expiry  */
    /// @param _token1Deposit if true, depositing `token1`; if false, depositing `token2`
    /// @param _amount amount of tokens deposited (tokenContract2 if seller, otherwise tokenContract1). If `openOffer`, `_amount` must == `totalAmount1` + `fee1` or `totalAmount2` + `fee2` as applicable
    function depositTokens(bool _token1Deposit, uint256 _amount) external nonReentrant {
        if (expirationTime <= block.timestamp) revert DoubleTokenLexscrow_IsExpired();
        if (_amount == 0) revert DoubleTokenLexscrow_ZeroAmount();
        bool _openOffer = openOffer;

        if (!_token1Deposit) {
            if (!_openOffer && msg.sender != seller) revert DoubleTokenLexscrow_NotSeller();
            if (token2.allowance(msg.sender, address(this)) < _amount)
                revert DoubleTokenLexscrow_AmountNotApprovedForTransferFrom();
            uint256 _totalWithFee2 = totalAmount2 + fee2;
            uint256 _balance2 = token2.balanceOf(address(this)) + _amount;

            if (_balance2 > _totalWithFee2) {
                uint256 _surplus = _balance2 - _totalWithFee2;
                // either reduce `_amount` by the surplus, or revert if `_amount` is less than the surplus
                if (_amount - _surplus > 0) _amount -= _surplus;
                else revert DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
            }
            if (_openOffer && _balance2 < _totalWithFee2) revert DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
            address _tokenContract2 = tokenContract2;

            // whether exact amount deposited or adjusted for surplus, total amount will be in escrow
            if (_balance2 >= _totalWithFee2) {
                // if this DoubleTokenLexscrow is an open offer and was not yet accepted by tendering full amount, make depositing address the `seller`
                if (_openOffer) {
                    seller = msg.sender;
                    emit DoubleTokenLexscrow_SellerUpdated(msg.sender);
                }
                emit DoubleTokenLexscrow_TotalAmountInEscrow(msg.sender, _tokenContract2);
            }
            emit DoubleTokenLexscrow_AmountReceived(_tokenContract2, _amount);

            safeTransferFrom(_tokenContract2, msg.sender, address(this), _amount);
        } else {
            if (!_openOffer && msg.sender != buyer) revert DoubleTokenLexscrow_NotBuyer();
            if (token1.allowance(msg.sender, address(this)) < _amount)
                revert DoubleTokenLexscrow_AmountNotApprovedForTransferFrom();
            uint256 _totalWithFee1 = totalAmount1 + fee1;
            uint256 _balance1 = token1.balanceOf(address(this)) + _amount;

            if (_balance1 > _totalWithFee1) {
                uint256 _surplus = _balance1 - _totalWithFee1;
                // either reduce `_amount` by the surplus, or revert if `_amount` is less than the surplus
                if (_amount - _surplus > 0) _amount -= _surplus;
                else revert DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
            }
            if (_openOffer && _balance1 < _totalWithFee1) revert DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
            address _tokenContract1 = tokenContract1;

            // whether exact amount deposited or adjusted for surplus, total amount will be in escrow
            if (_balance1 >= _totalWithFee1) {
                // if this DoubleTokenLexscrow is an open offer and was not yet accepted by tendering full amount, make depositing address the `buyer`
                if (_openOffer) {
                    buyer = msg.sender;
                    emit DoubleTokenLexscrow_BuyerUpdated(msg.sender);
                }
                emit DoubleTokenLexscrow_TotalAmountInEscrow(msg.sender, _tokenContract1);
            }
            emit DoubleTokenLexscrow_AmountReceived(_tokenContract1, _amount);

            safeTransferFrom(_tokenContract1, msg.sender, address(this), _amount);
        }
    }

    /// @notice for the current `seller` to designate a new seller address
    /// @param _seller new address of seller; conditional protects against passing address (0)
    function updateSeller(address _seller) external {
        if (msg.sender != seller || _seller == seller) revert DoubleTokenLexscrow_NotSeller();
        if (_seller == buyer) revert DoubleTokenLexscrow_PartiesHaveSameAddress();
        if (_seller == address(0)) revert DoubleTokenLexscrow_ZeroAddress();

        seller = _seller;
        emit DoubleTokenLexscrow_SellerUpdated(_seller);
    }

    /// @notice for the current `buyer` to designate a new buyer address
    /// @param _buyer new address of buyer; conditional protects against passing address (0)
    function updateBuyer(address _buyer) external {
        if (msg.sender != buyer || _buyer == buyer) revert DoubleTokenLexscrow_NotBuyer();
        if (_buyer == seller) revert DoubleTokenLexscrow_PartiesHaveSameAddress();
        if (_buyer == address(0)) revert DoubleTokenLexscrow_ZeroAddress();

        buyer = _buyer;
        emit DoubleTokenLexscrow_BuyerUpdated(_buyer);
    }

    /** @notice checks if both total amounts are in address(this), satisfaction of any applicable condition(s), and expiration has not been met;
     *** if so, this contract executes and transfers `totalAmount1` of `token1` to `seller` and `totalAmount2` of `token2` to `buyer`;
     *** if expired, `checkIfExpired()` logic fires; callable by any external address **/
    /** @dev requires entire `totalAmount1` + `fee1` and `totalAmount2` + `fee2` be held by address(this). If properly executes, emits event with effective time of execution.
     *** allows execution even if parties mistaken directly send tokens to address(this) rather than properly calling the applicable functions */
    function execute() external {
        address _tokenContract1 = tokenContract1;
        address _tokenContract2 = tokenContract2;
        uint256 _totalAmount1 = totalAmount1;
        uint256 _totalAmount2 = totalAmount2;
        uint256 _fee1 = fee1;
        uint256 _fee2 = fee2;
        uint256 _totalWithFee1 = _totalAmount1 + _fee1;
        uint256 _totalWithFee2 = _totalAmount2 + _fee2;
        if (
            token1.balanceOf(address(this)) < _totalWithFee1 ||
            token2.balanceOf(address(this)) < _totalWithFee2 ||
            (address(conditionManager) != address(0) && !conditionManager.checkConditions(""))
        ) revert DoubleTokenLexscrow_NotReadyToExecute();

        if (!checkIfExpired()) {
            address _receiver = receiver;

            // safeTransfer `totalAmount1` to `seller`, `totalAmount2` to `buyer`, and each fee to `_receiver`; note the deposit functions perform checks against depositing more than the totalAmounts plus fees,
            // and further safeguarded by any excess balance being returned to the respective party after expiry in `checkIfExpired()`
            // if any fails, function will revert
            if (_fee1 != 0) safeTransfer(_tokenContract1, _receiver, _fee1);
            safeTransfer(_tokenContract1, seller, _totalAmount1);
            if (_fee2 != 0) safeTransfer(_tokenContract2, _receiver, _fee2);
            safeTransfer(_tokenContract2, buyer, _totalAmount2);

            // effective time of execution is block.timestamp, no need to emit token contracts, condition manager details, or amounts as these are immutable variables
            // and if the latter is desired to be logged, can use the ERC20 Transfer event; `DoubleTokenLexscrow_Executed` emission implies emitted Transfer events
            emit DoubleTokenLexscrow_Executed(block.timestamp, seller, buyer, _receiver);
        }
    }

    /// @notice convenience function to get a USD value receipt if a dAPI / data feed proxy exists for a tokenContract, for example for `seller` to submit `totalAmount1` and `_token1` == true immediately after execution/release of DoubleTokenLexscrow
    /// @dev external call will revert if price quote is too stale or if token is not supported; event containing `_paymentId` and `_usdValue` emitted by Receipt.sol; irrelevant to execution of this contract
    /// @param _token1 whether caller is seeking a receipt for `token1`; if true, yes, if false, seeking receipt for `token2`
    /// @param _tokenAmount amount of tokens for which caller is seeking the total USD value receipt
    /// @return _paymentId uint256 ID number for this call
    /// @return _usdValue uint256 printed receipt value in $US for this `_tokenAmount` of the applicable token
    function getReceipt(bool _token1, uint256 _tokenAmount) external returns (uint256 _paymentId, uint256 _usdValue) {
        if (_token1) return receipt.printReceipt(tokenContract1, _tokenAmount, token1.decimals());
        else return receipt.printReceipt(tokenContract2, _tokenAmount, token2.decimals());
    }

    /// @notice enables mutual early termination and return of deposited tokens, if both `buyer` and `seller` pass `true` to this function
    /// @dev if both `buyer` and `seller` pass `true` to this function, the `isExpired` boolean will be set to true, and this function will call `checkIfExpired`, returning any deposited tokens
    /// if the parties effectively terminate early, this contract will not be reusable.
    /// @param _electToTerminate whether the caller elects to terminate this LeXscrow early (`true`); this election is revocable by such caller passing `false`
    function electToTerminate(bool _electToTerminate) external {
        if (msg.sender != buyer && msg.sender != seller) revert DoubleTokenLexscrow_NotParty();
        if (isExpired) revert DoubleTokenLexscrow_IsExpired();

        terminationConsent[msg.sender] = _electToTerminate;

        // if both parties have elected to terminate early, update `isExpired` to true and mimics the logic in `checkIfExpired` to enable deposit returns, effectively accelerating the expiration
        if (terminationConsent[buyer] && terminationConsent[seller]) {
            isExpired = true;
            uint256 _balance1 = token1.balanceOf(address(this));
            uint256 _balance2 = token2.balanceOf(address(this));

            if (_balance1 != 0) safeTransfer(address(token1), buyer, _balance1);
            if (_balance2 != 0) safeTransfer(address(token2), seller, _balance2);

            emit DoubleTokenLexscrow_Terminated();
        }
    }

    /// @notice check if expired, and if so, handle refundability to the identified `buyer` and `seller` at such time by returning their applicable tokens
    /// @dev if expired, update `isExpired` boolean and safeTransfer `buyer` all of `token1` and `seller` all of `token2`, as fees are only paid upon successful execution;
    /// while the `buyer` and `seller` may not have been the depositors, they are the best options for deposit return at the time of calling, especially considering
    /// either may replace their own addresses at any time for any reason via `updateBuyer()` and `updateSeller()`
    /// @return isExpired boolean of whether this LeXscroW has expired
    function checkIfExpired() public nonReentrant returns (bool) {
        if (expirationTime <= block.timestamp && !isExpired) {
            isExpired = true;
            uint256 _balance1 = token1.balanceOf(address(this));
            uint256 _balance2 = token2.balanceOf(address(this));

            if (_balance1 != 0) safeTransfer(address(token1), buyer, _balance1);
            if (_balance2 != 0) safeTransfer(address(token2), seller, _balance2);

            emit DoubleTokenLexscrow_Expired();
        }
        return isExpired;
    }
}
