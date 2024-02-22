//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * this solidity file is provided as-is; no guarantee, representation or warranty is being made, express or implied,
 * as to the safety or correctness of the code or any smart contracts or other software deployed from these files.
 * this solidity file is currently NOT AUDITED; there can be no assurance it will work as intended,
 * and users may experience delays, failures, errors, omissions or loss of transmitted information or value.
 *
 * Any users, developers, or adapters of these files should proceed with caution and use at their own risk.
 **/

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

/////// o=o=o=o=o DoubleTokenLexscrow o=o=o=o=o \\\\\\\

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

interface ILexscrowConditionManager {
    function checkConditions() external returns (bool);
}

/// @notice interface for ERC-20 standard token contract, including EIP2612 permit function
interface IERC20Permit {
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

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
}

/// @notice interface to Receipt.sol, which returns USD-value receipts for a provided token amount
interface IReceipt {
    function printReceipt(
        address token,
        uint256 tokenAmount,
        uint256 decimals
    ) external returns (uint256, uint256);
}

/// @notice Solady's SafeTransferLib 'SafeTransfer()' and 'SafeTransferFrom()'.  Extracted from library and pasted for convenience, transparency, and size minimization.
/// @author Solady (https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol), license copied below
/// @dev implemented as abstract contract rather than library for size/gas reasons
abstract contract SafeTransferLib {
    /// @dev The ERC20 `transfer` has failed.
    error TransferFailed();
    /// @dev The ERC20 `transferFrom` has failed.
    error TransferFromFailed();

    /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
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

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
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

/// @notice Gas-optimized reentrancy protection for smart contracts.
/// @author Solbase (https://github.com/Sol-DAO/solbase/blob/main/src/utils/ReentrancyGuard.sol), license copied below
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
 **/
/** @notice non-custodial bilateral smart escrow contract using ERC20 tokens, supporting:
 * deposit tokens via approve+transfer or EIP2612 permit signature
 * identified parties or open offer (party that deposits totalAmount1 of token1 becomes 'buyer', and vice versa)
 * escrow expiration denominated in seconds
 * optional conditions for execution (contingent execution based on oracle-fed external data value, signatures, etc.)
 * buyer and seller addresses replaceable by applicable party
 * no separate approval is necessary as both sides must deposit value (which serves as signalled approval to execute)
 * automatically refundable (withdrawable) to buyer and seller at expiry if not executed
 * if executed, re-usable by parties until expiration time
 **/
/** @dev contract executes and simultaneously releases 'totalAmount1' to 'seller' and 'totalAmount2' to 'buyer' iff:
 * (1) 'buyer' and 'seller' have respectively deposited 'totalAmount1' + 'fee1' of 'token1' and 'totalAmount2' + 'fee2' of 'token2'
 * (2) token1.balanceOf(address(this)) >= 'totalAmount1' + 'fee1' && token2.balanceOf(address(this)) >= 'totalAmount2' + 'fee2'
 * (3) 'expirationTime' > block.timestamp
 * (4) if there is/are condition(s), such condition(s) is/are satisfied
 *
 * otherwise, amounts held in address(this) will be treated according to the code in 'checkIfExpired()' when called following expiry. Deposited fees are returned (by becoming withdrawable) if this contract expires.
 *
 * variables are public for interface friendliness and enabling getters.
 * 'seller', 'buyer', 'deposit', 'openOffer' and other terminology, naming, and descriptors herein are used only for simplicity and convenience of reference, and
 * should not be interpreted to ascribe nor imply any agreement or relationship between or among any author, modifier, deployer, user, contract, asset, or other relevant participant hereto
 **/
contract DoubleTokenLexscrow is ReentrancyGuard, SafeTransferLib {
    struct Amounts {
        uint256 totalAmount1;
        uint256 fee1;
        uint256 totalAmount2;
        uint256 fee2;
        address receiver;
    }

    // 60 seconds * 60 minutes * 24 hours
    uint256 internal constant ONE_DAY = 86400;

    // internal visibility for gas savings, as each tokenContract is public and bears the same contract address as its respective interface
    IERC20Permit internal immutable token1; // tokenContract1
    IERC20Permit internal immutable token2; // tokenContract2

    // Receipt.sol contract address
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

    mapping(address => uint256) public amountWithdrawable1; // token1
    mapping(address => uint256) public amountWithdrawable2; // token2

    ///
    /// EVENTS
    ///

    event DoubleTokenLexscrow_AmountReceived(
        address token,
        uint256 tokenAmount
    );
    event DoubleTokenLexscrow_BuyerUpdated(address newBuyer);
    event DoubleTokenLexscrow_DepositedAmountWithdrawn(
        address recipient,
        address token,
        uint256 amount
    );
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
    event DoubleTokenLexscrow_Executed(
        uint256 indexed effectiveTime,
        address seller,
        address buyer,
        address receiver
    );
    event DoubleTokenLexscrow_Expired();
    event DoubleTokenLexscrow_TotalAmountInEscrow(
        address depositor,
        address token
    );
    event DoubleTokenLexscrow_SellerUpdated(address newSeller);

    ///
    /// ERRORS
    ///

    error DoubleTokenLexscrow_AmountNotApprovedForTransferFrom();
    error DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
    error DoubleTokenLexscrow_IsExpired();
    error DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
    error DoubleTokenLexscrow_NotBuyer();
    error DoubleTokenLexscrow_NotSeller();
    error DoubleTokenLexscrow_NonERC20Contract();
    error DoubleTokenLexscrow_NotReadyToExecute();
    error DoubleTokenLexscrow_ZeroAmount();

    ///
    /// FUNCTIONS
    ///

    /// @notice constructs the DoubleTokenLexscrow smart escrow contract. Arranger MUST verify that _tokenContract is both ERC20- and EIP2612- standard compliant and that the conditions are proper, as neither address(this) nor the LeXscrow Factory contract fully perform such checks.
    /// @param _openOffer: whether this escrow is open to any prospective 'buyer' or 'seller'. A 'buyer' assents by depositing 'totalAmount1' + 'fee1' of 'token1' to address(this), and a 'seller' assents by depositing 'totalAmount2' + 'fee2' of 'token2' to address(this) via the applicable function
    /// @param _expirationTime: _expirationTime in seconds (Unix time), which will be compared against block.timestamp. Because tokens will only be released upon execution or become withdrawable at expiry, submitting a reasonable expirationTime is imperative
    /// @param _seller: the seller's address, depositor of the 'totalAmount2' + 'fee2' (in token2) and recipient of the 'totalAmount1' (in token1) if the contract executes. Automatically updated by successful 'depositTokensWithPermit()' or 'depositTokens()' if 'openOffer'
    /// @param _buyer: the buyer's address, depositor of the 'totalAmount1' + 'fee1' (in token1) and recipient of the 'totalAmount2' (in token2) if the contract executes. Automatically updated by successful 'depositTokensWithPermit()' or 'depositTokens()' if 'openOffer'
    /// @param _tokenContract1: contract address for the ERC20 token used in this DoubleTokenLexscrow as 'token1'
    /// @param _tokenContract2: contract address for the ERC20 token used in this DoubleTokenLexscrow as 'token2'
    /// @param _conditionManager contract address for ConditionManager.sol
    /// @param _receipt contract address for Receipt.sol contract
    /// @param _amounts: struct containing the total amounts and fees as follows:
    /// _totalAmount1: total amount of 'tokenContract1' ultimately intended for 'seller', not including fees
    /// _fee1: amount of 'tokenContract1' that also must be deposited, which will be paid to the fee receiver
    /// _totalAmount2: total amount of 'tokenContract2' ultimately intended for 'buyer', not including fees
    /// _fee2: amount of 'tokenContract2' that also must be deposited, which will be paid to the fee receiver
    /// _receiver: address to receive '_fee1' and '_fee2'
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
    ) payable {
        if (_amounts.totalAmount1 == 0 || _amounts.totalAmount2 == 0)
            revert DoubleTokenLexscrow_ZeroAmount();
        if (_expirationTime <= block.timestamp)
            revert DoubleTokenLexscrow_IsExpired();

        // quick staticcall condition check that each of '_tokenContract1' and '_tokenContract2' is at least partially ERC-20 compliant by checking if balanceOf function exists
        (bool successBalanceOf1, bytes memory dataBalanceOf1) = _tokenContract1
            .staticcall(
                abi.encodeWithSignature("balanceOf(address)", address(this))
            );
        (bool successBalanceOf2, bytes memory dataBalanceOf2) = _tokenContract2
            .staticcall(
                abi.encodeWithSignature("balanceOf(address)", address(this))
            );

        if (
            !successBalanceOf1 ||
            dataBalanceOf1.length == 0 ||
            !successBalanceOf2 ||
            dataBalanceOf2.length == 0
        ) revert DoubleTokenLexscrow_NonERC20Contract();

        openOffer = _openOffer;
        expirationTime = _expirationTime;
        seller = _seller;
        buyer = _buyer;
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

    /// @notice deposit value to 'address(this)' by permitting address(this) to safeTransferFrom '_amount' of tokens from '_depositor'
    /** @dev if '_depositor' == 'sender', deposit token2; otherwise, deposit token1; this enables open offers for any prospective buyer to deposit
     ** max '_amount' limit of 'totalAmount1' + 'fee1' or 'totalAmount2' + 'fee2' as applicable, and if such amount is already held or escrow has expired, revert.
     ** also updates 'seller' or 'buyer' to '_depositor' (depending on token used) if true 'openOffer', and
     ** records amount deposited by '_depositor' for refundability at expiry  */
    /// @param _token1Deposit: if true, depositing 'token1'; if false, depositing 'token2'
    /// @param _depositor: depositor of the '_amount' of tokens, often msg.sender/originating EOA, but if !'openOffer', must == 'buyer' if 'token1Deposit' or == 'seller' if 'token2Deposit'
    /// @param _amount: amount of tokens deposited. If 'openOffer', '_amount' must == 'totalAmount1' + 'fee1' or 'totalAmount2' + 'fee2' as applicable
    /// @param _deadline: deadline for usage of the permit approval signature
    /// @param v: ECDSA sig parameter
    /// @param r: ECDSA sig parameter
    /// @param s: ECDSA sig parameter
    function depositTokensWithPermit(
        bool _token1Deposit,
        address _depositor,
        uint256 _amount,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        if (_deadline < block.timestamp || expirationTime <= block.timestamp)
            revert DoubleTokenLexscrow_IsExpired();
        if (_amount == 0) revert DoubleTokenLexscrow_ZeroAmount();
        bool _openOffer = openOffer;

        if (!_token1Deposit) {
            if (!_openOffer && _depositor != seller)
                revert DoubleTokenLexscrow_NotSeller();
            uint256 _totalWithFee2 = totalAmount2 + fee2;
            uint256 _balance2 = token2.balanceOf(address(this)) + _amount;
            if (_balance2 > _totalWithFee2)
                revert DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
            if (_openOffer && _balance2 < _totalWithFee2)
                revert DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
            address _tokenContract2 = tokenContract2;

            if (_balance2 == _totalWithFee2) {
                // if this DoubleTokenLexscrow is an open offer and was not yet accepted by tendering full amount, make depositing address the 'seller'
                if (_openOffer) {
                    seller = _depositor;
                    emit DoubleTokenLexscrow_SellerUpdated(_depositor);
                }
                emit DoubleTokenLexscrow_TotalAmountInEscrow(
                    _depositor,
                    _tokenContract2
                );
            }
            emit DoubleTokenLexscrow_AmountReceived(_tokenContract2, _amount);

            token2.permit(
                _depositor,
                address(this),
                _amount,
                _deadline,
                v,
                r,
                s
            );
            safeTransferFrom(
                _tokenContract2,
                _depositor,
                address(this),
                _amount
            );
        } else {
            if (!_openOffer && _depositor != buyer)
                revert DoubleTokenLexscrow_NotBuyer();
            uint256 _totalWithFee1 = totalAmount1 + fee1;
            uint256 _balance1 = token1.balanceOf(address(this)) + _amount;
            if (_balance1 > _totalWithFee1)
                revert DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
            if (_openOffer && _balance1 < _totalWithFee1)
                revert DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
            address _tokenContract1 = tokenContract1;

            if (_balance1 == _totalWithFee1) {
                // if this DoubleTokenLexscrow is an open offer and was not yet accepted by tendering full amount, make depositing address the 'buyer'
                if (_openOffer) {
                    buyer = _depositor;
                    emit DoubleTokenLexscrow_BuyerUpdated(_depositor);
                }
                emit DoubleTokenLexscrow_TotalAmountInEscrow(
                    _depositor,
                    _tokenContract1
                );
            }
            emit DoubleTokenLexscrow_AmountReceived(_tokenContract1, _amount);

            token1.permit(
                _depositor,
                address(this),
                _amount,
                _deadline,
                v,
                r,
                s
            );
            safeTransferFrom(
                _tokenContract1,
                _depositor,
                address(this),
                _amount
            );
        }
    }

    /// @notice deposit value to 'address(this)' via safeTransferFrom '_amount' of tokens from msg.sender; provided msg.sender has approved address(this) to transferFrom such 'amount'
    /** @dev msg.sender must have called approve(address(this), _amount) on the proper token contract prior to calling this function
     ** max '_amount' limit of 'totalAmount1' + 'fee1' or 'totalAmount2' + 'fee2' as applicable, and if such amount is already held or escrow has expired, revert.
     ** updates 'seller' or 'buyer' to msg.sender (depending on token used) if true 'openOffer', and
     ** records amount deposited by msg.sender for refundability at expiry  */
    /// @param _token1Deposit: if true, depositing 'token1'; if false, depositing 'token2'
    /// @param _amount: amount of tokens deposited (tokenContract2 if seller, otherwise tokenContract1). If 'openOffer', '_amount' must == 'totalAmount1' + 'fee1' or 'totalAmount2' + 'fee2' as applicable
    function depositTokens(
        bool _token1Deposit,
        uint256 _amount
    ) external nonReentrant {
        if (expirationTime <= block.timestamp)
            revert DoubleTokenLexscrow_IsExpired();
        if (_amount == 0) revert DoubleTokenLexscrow_ZeroAmount();
        bool _openOffer = openOffer;

        if (!_token1Deposit) {
            if (!_openOffer && msg.sender != seller)
                revert DoubleTokenLexscrow_NotSeller();
            if (token2.allowance(msg.sender, address(this)) < _amount)
                revert DoubleTokenLexscrow_AmountNotApprovedForTransferFrom();
            uint256 _totalWithFee2 = totalAmount2 + fee2;
            uint256 _balance2 = token2.balanceOf(address(this)) + _amount;
            if (_balance2 > _totalWithFee2)
                revert DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
            if (_openOffer && _balance2 < _totalWithFee2)
                revert DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
            address _tokenContract2 = tokenContract2;

            if (_balance2 == _totalWithFee2) {
                // if this DoubleTokenLexscrow is an open offer and was not yet accepted by tendering full amount, make depositing address the 'seller'
                if (_openOffer) {
                    seller = msg.sender;
                    emit DoubleTokenLexscrow_SellerUpdated(msg.sender);
                }
                emit DoubleTokenLexscrow_TotalAmountInEscrow(
                    msg.sender,
                    _tokenContract2
                );
            }
            emit DoubleTokenLexscrow_AmountReceived(_tokenContract2, _amount);

            safeTransferFrom(
                _tokenContract2,
                msg.sender,
                address(this),
                _amount
            );
        } else {
            if (!_openOffer && msg.sender != buyer)
                revert DoubleTokenLexscrow_NotBuyer();
            if (token1.allowance(msg.sender, address(this)) < _amount)
                revert DoubleTokenLexscrow_AmountNotApprovedForTransferFrom();
            uint256 _totalWithFee1 = totalAmount1 + fee1;
            uint256 _balance1 = token1.balanceOf(address(this)) + _amount;
            if (_balance1 > _totalWithFee1)
                revert DoubleTokenLexscrow_BalanceExceedsTotalAmountWithFee();
            if (_openOffer && _balance1 < _totalWithFee1)
                revert DoubleTokenLexscrow_MustDepositTotalAmountWithFee();
            address _tokenContract1 = tokenContract1;

            if (_balance1 == _totalWithFee1) {
                // if this DoubleTokenLexscrow is an open offer and was not yet accepted by tendering full amount, make depositing address the 'buyer'
                if (_openOffer) {
                    buyer = msg.sender;
                    emit DoubleTokenLexscrow_BuyerUpdated(msg.sender);
                }
                emit DoubleTokenLexscrow_TotalAmountInEscrow(
                    msg.sender,
                    _tokenContract1
                );
            }
            emit DoubleTokenLexscrow_AmountReceived(_tokenContract1, _amount);

            safeTransferFrom(
                _tokenContract1,
                msg.sender,
                address(this),
                _amount
            );
        }
    }

    /// @notice for the current 'seller' to designate a new seller address
    /// @param _seller: new address of seller
    function updateSeller(address _seller) external {
        if (msg.sender != seller) revert DoubleTokenLexscrow_NotSeller();
        seller = _seller;
        emit DoubleTokenLexscrow_SellerUpdated(_seller);
    }

    /// @notice for the current 'buyer' to designate a new buyer address
    /// @param _buyer: new address of buyer
    function updateBuyer(address _buyer) external {
        if (msg.sender != buyer) revert DoubleTokenLexscrow_NotBuyer();
        buyer = _buyer;
        emit DoubleTokenLexscrow_BuyerUpdated(_buyer);
    }

    /** @notice checks if both total amounts are in address(this), satisfaction of any applicable condition(s), and expiration has not been met;
     *** if so, this contract executes and transfers 'totalAmount1' of 'token1' to 'seller' and 'totalAmount2' of 'token2' to 'buyer';
     *** if expired, 'checkIfExpired()' logic fires; callable by any external address **/
    /** @dev requires entire 'totalAmount1' + 'fee1' and 'totalAmount2' + 'fee2' be held by address(this). If properly executes, emits event with effective time of execution.
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
            token2.balanceOf(address(this)) < _totalWithFee2
        ) revert DoubleTokenLexscrow_NotReadyToExecute();

        // only perform these checks if execution is contingent upon specified external condition(s)
        bool _conditionsSatisfied = true;
        if (address(conditionManager) != address(0))
            _conditionsSatisfied = conditionManager.checkConditions();

        if (_conditionsSatisfied && !checkIfExpired()) {
            address _receiver = receiver;

            // safeTransfer 'totalAmount1' to 'seller', 'totalAmount2' to 'buyer', and each fee to '_receiver'; note the deposit functions perform checks against depositing more than the totalAmounts plus fees,
            // and further safeguarded by any excess balance being withdrawable by each respective depositing party side after expiry in 'checkIfExpired()'
            // if any fails, function will revert
            safeTransfer(_tokenContract1, _receiver, _fee1);
            safeTransfer(_tokenContract1, seller, _totalAmount1);
            safeTransfer(_tokenContract2, _receiver, _fee2);
            safeTransfer(_tokenContract2, buyer, _totalAmount2);

            // effective time of execution is block.timestamp, no need to emit token contracts, condition manager details, or amounts as these are immutable variables
            // and if the latter is desired to be logged, can use the ERC20 Transfer event
            emit DoubleTokenLexscrow_Executed(
                block.timestamp,
                seller,
                buyer,
                _receiver
            );
        }
    }

    /// @notice convenience function to get a USD value receipt if a dAPI / data feed proxy exists for a tokenContract, for example for 'seller' to submit 'totalAmount1' and '_token1' == true immediately after execution/release of DoubleTokenLexscrow
    /// @dev external call will revert if price quote is too stale or if token is not supported; event containing '_paymentId' and '_usdValue' emitted by Receipt.sol
    /// @param _token1: whether caller is seeking a receipt for 'token1'; if true, yes, if false, seeking receipt for 'token2'
    /// @param _tokenAmount: amount of tokens for which caller is seeking the total USD value receipt
    function getReceipt(
        bool _token1,
        uint256 _tokenAmount
    ) external returns (uint256 _paymentId, uint256 _usdValue) {
        if (_token1)
            return
                receipt.printReceipt(
                    tokenContract1,
                    _tokenAmount,
                    token1.decimals()
                );
        else
            return
                receipt.printReceipt(
                    tokenContract2,
                    _tokenAmount,
                    token2.decimals()
                );
    }

    /// @notice allows an address to withdraw tokens according to their applicable mapped value (refundable amount post-expiry)
    /// @dev if 'isExpired', used by 'buyer' and/or 'seller' (as applicable)
    function withdraw() external {
        address _tokenContract1 = tokenContract1;
        address _tokenContract2 = tokenContract2;
        uint256 _amt1 = amountWithdrawable1[msg.sender];
        uint256 _amt2 = amountWithdrawable2[msg.sender];
        if (_amt1 == 0 && _amt2 == 0) revert DoubleTokenLexscrow_ZeroAmount();
        else if (_amt1 != 0 && _amt2 == 0) {
            delete amountWithdrawable1[msg.sender];
            safeTransfer(_tokenContract1, msg.sender, _amt1);
            emit DoubleTokenLexscrow_DepositedAmountWithdrawn(
                msg.sender,
                _tokenContract1,
                _amt1
            );
        } else if (_amt1 == 0 && _amt2 != 0) {
            delete amountWithdrawable2[msg.sender];
            safeTransfer(_tokenContract2, msg.sender, _amt2);
            emit DoubleTokenLexscrow_DepositedAmountWithdrawn(
                msg.sender,
                _tokenContract2,
                _amt2
            );
        } else {
            delete amountWithdrawable1[msg.sender];
            delete amountWithdrawable2[msg.sender];
            safeTransfer(_tokenContract1, msg.sender, _amt1);
            safeTransfer(_tokenContract2, msg.sender, _amt2);
            emit DoubleTokenLexscrow_DepositedAmountWithdrawn(
                msg.sender,
                _tokenContract1,
                _amt1
            );
            emit DoubleTokenLexscrow_DepositedAmountWithdrawn(
                msg.sender,
                _tokenContract2,
                _amt2
            );
        }
    }

    /// @notice check if expired, and if so, handle refundability to the identified 'buyer' and 'seller' at such time by updating the 'amountWithdrawable1' and 'amountWithdrawable2' mappings as applicable
    /// @dev if expired, update isExpired boolean and allow 'buyer' to withdraw all of 'amountWithdrawable1' and allow 'seller' to withdraw all of 'amountWithdrawable2'
    /// @return isExpired
    function checkIfExpired() public nonReentrant returns (bool) {
        if (expirationTime <= block.timestamp) {
            isExpired = true;
            uint256 _balance1 = token1.balanceOf(address(this));
            uint256 _balance2 = token2.balanceOf(address(this));

            emit DoubleTokenLexscrow_Expired();

            // update mappings in order to allow 'buyer' to withdraw all of '_balance1' and 'seller' to withdraw all of '_balance2', as fees are only paid upon successful execution
            if (_balance1 != 0) amountWithdrawable1[buyer] = _balance1;
            if (_balance2 != 0) amountWithdrawable2[seller] = _balance2;
        }
        return isExpired;
    }
}

/** 
Solady License:
MIT License

Copyright (c) 2022 Solady.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */
