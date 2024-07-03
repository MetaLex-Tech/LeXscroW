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

/// @notice interface to LexscrowConditionManager or MetaLeX's regular ConditionManager
interface ILexscrowConditionManager {
    function checkConditions() external returns (bool);
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
/// @author Solady (https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
/// Licenses copied below
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
    /// 9 bytes is large enough to avoid collisions with lower slots, but not too large to result in excessive bytecode bloat.
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
 * @title       TokenLexscrow
 *
 * @notice non-custodial smart escrow contract using ERC20 tokens on Ethereum Mainnet, supporting:
 * partial or full deposit amount
 * refundable or non-refundable deposit upon expiry
 * deposit via transfer or EIP2612 permit signature
 * seller-identified buyer or open offer
 * escrow expiration denominated in seconds
 * optional conditions for execution (contingent execution based on oracle-fed external data value, or any conditions within the LexscrowConditionManager spec)
 * buyer and seller addresses replaceable by applicable party
 *
 * @dev adapted from TokenLocker (https://github.com/ChainLockerLLC/smart-contracts/blob/main/src/TokenLocker.sol). Contract executes and releases 'totalAmount' to 'seller' iff:
 * (1) erc20.balanceOf(address(this)) - 'pendingWithdraw' >= 'totalWithFee'
 * (2) 'expirationTime' > block.timestamp
 * (3) any condition(s) are satisfied
 *
 * otherwise, amount held in address(this) will be treated according to the code in 'checkIfExpired()' when called following expiry
 *
 * variables are public for interface friendliness and enabling getters.
 * 'seller', 'buyer', 'deposit', 'refundable', 'openOffer' and other terminology, naming, and descriptors herein are used only for simplicity and convenience of reference, and
 * should not be interpreted to ascribe nor imply any agreement or relationship between or among any author, modifier, deployer, user, contract, asset, or other relevant participant hereto
 **/
contract TokenLexscrow is ReentrancyGuard, SafeTransferLib {
    struct Amounts {
        uint256 deposit;
        uint256 totalAmount;
        uint256 fee;
        address receiver;
    }

    // Receipt.sol contract address, ETH mainnet
    IReceipt internal constant RECEIPT =
        IReceipt(0xf838D6829fcCBedCB0B4D8aD58cb99814F935BA8);

    // internal visibility for gas savings, as 'tokenContract' is public and bears the same contract address
    IERC20Permit internal immutable erc20;
    ILexscrowConditionManager public immutable conditionManager;
    address public immutable receiver;
    address public immutable tokenContract;
    bool public immutable openOffer;
    bool public immutable refundable;
    uint256 public immutable deposit;
    uint256 public immutable expirationTime;
    uint256 public immutable fee;
    uint256 public immutable totalAmount;
    uint256 public immutable totalWithFee;

    address public buyer;
    address public seller;
    bool public deposited;
    bool public isExpired;
    /// @notice aggregate pending withdrawable amount, so address(this) balance checks subtract withdrawable, but not yet withdrawn, amounts
    uint256 public pendingWithdraw;

    mapping(address => uint256) public amountDeposited;
    mapping(address => uint256) public amountWithdrawable;

    ///
    /// EVENTS
    ///

    event TokenLexscrow_AmountReceived(uint256 tokenAmount);
    event TokenLexscrow_BuyerUpdated(address newBuyer);
    event TokenLexscrow_DepositedAmountTransferred(
        address recipient,
        uint256 amount
    );
    event TokenLexscrow_DepositInEscrow(address depositor);
    event TokenLexscrow_Deployed(
        bool refundable,
        bool openOffer,
        uint256 expirationTime,
        address seller,
        address buyer,
        address tokenContract,
        address conditionManager,
        Amounts amounts
    );
    event TokenLexscrow_Executed(uint256 indexed effectiveTime);
    event TokenLexscrow_Expired();
    event TokenLexscrow_TotalAmountInEscrow();
    event TokenLexscrow_SellerUpdated(address newSeller);

    ///
    /// ERRORS
    ///

    error TokenLexscrow_AmountNotApprovedForTransferFrom();
    error TokenLexscrow_BalanceExceedsTotalAmount();
    error TokenLexscrow_DepositGreaterThanTotalAmount();
    error TokenLexscrow_IsExpired();
    error TokenLexscrow_MustDepositTotalAmount();
    error TokenLexscrow_NotBuyer();
    error TokenLexscrow_NotSeller();
    error TokenLexscrow_NonERC20Contract();
    error TokenLexscrow_NotReadyToExecute();
    error TokenLexscrow_OnlyOpenOffer();
    error TokenLexscrow_ZeroAmount();

    ///
    /// FUNCTIONS
    ///

    /// @notice constructs the TokenLexscrow smart escrow contract. Arranger MUST verify that _tokenContract is both ERC20- and EIP2612- standard compliant and that '_conditionManager' is accurate if not relying upon the factory contract to deploy it
    /// @param _refundable: whether the '_deposit' is refundable to the 'buyer' in the event escrow expires without executing
    /// @param _openOffer: whether this escrow is open to any prospective 'buyer' (revocable at seller's option). A 'buyer' assents by sending 'deposit' to address(this) after deployment
    /// @param _expirationTime: _expirationTime in seconds (Unix time), which will be compared against block.timestamp. input type(uint256).max for no expiry (not recommended, as funds will only be released upon execution or if seller rejects depositor -- refunds only process at expiry)
    /// @param _seller: the seller's address, recipient of the 'totalAmount' if the contract executes
    /// @param _buyer: the buyer's address, who will cause the 'totalWithFee' to be paid to this address. Ignored if 'openOffer'
    /// @param _tokenContract: contract address for the ERC20 token used in this TokenLexscrow
    /// @param _conditionManager contract address for LexscrowConditionManager.sol or ConditionManager.sol, or address(0) for no conditions
    /// @param _amounts: Amounts struct containing:
    /// deposit: deposit amount in tokens, which must be <= '_totalAmount' (< for partial deposit, == for full deposit). If 'openOffer', msg.sender must deposit entire 'totalAmount', but if '_refundable', this amount will be refundable to the accepting address of the open offer (buyer) at expiry if not yet executed
    /// totalAmount: total amount of tokens ultimately intended for 'seller', not including fees. Must be > 0
    /// fee: amount of tokens that also must be deposited, if any, which will be paid to the fee receiver
    /// receiver: address payable to receive 'fee'
    constructor(
        bool _refundable,
        bool _openOffer,
        uint256 _expirationTime,
        address _seller,
        address _buyer,
        address _tokenContract,
        address _conditionManager,
        Amounts memory _amounts
    ) payable {
        if (_amounts.deposit > _amounts.totalAmount)
            revert TokenLexscrow_DepositGreaterThanTotalAmount();
        if (_amounts.totalAmount == 0) revert TokenLexscrow_ZeroAmount();
        if (_expirationTime <= block.timestamp)
            revert TokenLexscrow_IsExpired();

        // quick staticcall condition check that '_tokenContract' is at least partially ERC-20 compliant by checking if both totalSupply and balanceOf functions exist
        (bool successTotalSupply, ) = _tokenContract.staticcall(
            abi.encodeWithSignature("totalSupply()")
        );

        (bool successBalanceOf, ) = _tokenContract.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        if (!successTotalSupply || !successBalanceOf)
            revert TokenLexscrow_NonERC20Contract();

        refundable = _refundable;
        openOffer = _openOffer;
        seller = _seller;
        buyer = _buyer;
        tokenContract = _tokenContract;
        expirationTime = _expirationTime;
        deposit = _amounts.deposit;
        totalAmount = _amounts.totalAmount;
        fee = _amounts.fee;
        totalWithFee = _amounts.totalAmount + _amounts.fee; // revert if overflow
        receiver = _amounts.receiver;
        conditionManager = ILexscrowConditionManager(_conditionManager);
        erc20 = IERC20Permit(_tokenContract);

        emit TokenLexscrow_Deployed(
            _refundable,
            _openOffer,
            _expirationTime,
            _seller,
            _buyer,
            _tokenContract,
            _conditionManager,
            _amounts
        );
    }

    /// @notice deposit value to 'address(this)' by permitting address(this) to safeTransferFrom '_amount' of tokens from '_depositor'
    /** @dev max '_amount limit of 'totalWithFee', and if 'totalWithFee' is already held or escrow has expired, revert. Updates boolean and emits event when 'deposit' reached
     ** also updates 'buyer' to msg.sender if true 'openOffer' and false 'deposited', and
     ** records amount deposited by msg.sender in case of refundability or where 'seller' rejects a 'buyer' and buyer's deposited amount is to be returned  */
    /// @param _depositor: depositor of the '_amount' of tokens, often msg.sender/originating EOA, but must == 'buyer' if this is not an open offer (!openOffer)
    /// @param _amount: amount of tokens deposited. If 'openOffer', '_amount' must == 'totalWithFee'
    /// @param _deadline: deadline for usage of the permit approval signature
    /// @param v: ECDSA sig parameter
    /// @param r: ECDSA sig parameter
    /// @param s: ECDSA sig parameter
    function depositTokensWithPermit(
        address _depositor,
        uint256 _amount,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        uint256 _balance = erc20.balanceOf(address(this)) +
            _amount -
            pendingWithdraw;
        if (_balance > totalWithFee)
            revert TokenLexscrow_BalanceExceedsTotalAmount();
        if (!openOffer && _depositor != buyer) revert TokenLexscrow_NotBuyer();
        if (_deadline < block.timestamp || expirationTime <= block.timestamp)
            revert TokenLexscrow_IsExpired();
        if (openOffer && _balance < totalWithFee)
            revert TokenLexscrow_MustDepositTotalAmount();

        if (_balance >= deposit && !deposited) {
            // if this TokenLexscrow is an open offer and was not yet accepted (thus '!deposited'), make depositing address the 'buyer' and update 'deposited' to true
            if (openOffer) {
                buyer = _depositor;
                emit TokenLexscrow_BuyerUpdated(_depositor);
            }
            deposited = true;
            emit TokenLexscrow_DepositInEscrow(_depositor);
        }
        if (_balance == totalWithFee) emit TokenLexscrow_TotalAmountInEscrow();

        emit TokenLexscrow_AmountReceived(_amount);
        amountDeposited[_depositor] += _amount;
        erc20.permit(_depositor, address(this), _amount, _deadline, v, r, s);
        safeTransferFrom(tokenContract, _depositor, address(this), _amount);
    }

    /// @notice deposit value to 'address(this)' via safeTransferFrom '_amount' of tokens from msg.sender; provided msg.sender has approved address(this) to transferFrom such 'amount'
    /** @dev msg.sender must have erc20.approve(address(this), _amount) prior to calling this function
     ** max '_amount limit of 'totalWithFee', and if 'totalWithFee' is already held or this TokenLexscrow has expired, revert. Updates boolean and emits event when 'deposit' reached
     ** also updates 'buyer' to msg.sender if true 'openOffer' and false 'deposited', and
     ** records amount deposited by msg.sender in case of refundability or where 'seller' rejects a 'buyer' and buyer's deposited amount is to be returned  */
    /// @param _amount: amount of tokens deposited. If 'openOffer', '_amount' must == 'totalWithFee'
    function depositTokens(uint256 _amount) external nonReentrant {
        uint256 _balance = erc20.balanceOf(address(this)) +
            _amount -
            pendingWithdraw;
        if (_balance > totalWithFee)
            revert TokenLexscrow_BalanceExceedsTotalAmount();
        if (!openOffer && msg.sender != buyer) revert TokenLexscrow_NotBuyer();
        if (erc20.allowance(msg.sender, address(this)) < _amount)
            revert TokenLexscrow_AmountNotApprovedForTransferFrom();
        if (expirationTime <= block.timestamp) revert TokenLexscrow_IsExpired();
        if (openOffer && _balance < totalWithFee)
            revert TokenLexscrow_MustDepositTotalAmount();

        if (_balance >= deposit && !deposited) {
            // if this TokenLexscrow is an open offer and was not yet accepted (thus '!deposited'), make depositing address the 'buyer' and update 'deposited' to true
            if (openOffer) {
                buyer = msg.sender;
                emit TokenLexscrow_BuyerUpdated(msg.sender);
            }
            deposited = true;
            emit TokenLexscrow_DepositInEscrow(msg.sender);
        }
        if (_balance == totalWithFee) emit TokenLexscrow_TotalAmountInEscrow();

        emit TokenLexscrow_AmountReceived(_amount);
        amountDeposited[msg.sender] += _amount;
        safeTransferFrom(tokenContract, msg.sender, address(this), _amount);
    }

    /// @notice for the current seller to designate a new recipient address
    /// @param _seller: new recipient address of seller
    function updateSeller(address _seller) external {
        if (msg.sender != seller) revert TokenLexscrow_NotSeller();

        seller = _seller;
        emit TokenLexscrow_SellerUpdated(_seller);
    }

    /// @notice for the current 'buyer' to designate a new buyer address
    /// @param _buyer: new address of buyer
    function updateBuyer(address _buyer) external {
        if (msg.sender != buyer) revert TokenLexscrow_NotBuyer();

        // transfer 'amountDeposited[buyer]' to the new '_buyer', delete the existing buyer's 'amountDeposited', and update the 'buyer' state variable
        amountDeposited[_buyer] += amountDeposited[buyer];
        delete amountDeposited[buyer];

        buyer = _buyer;
        emit TokenLexscrow_BuyerUpdated(_buyer);
    }

    /** @notice callable by any external address: checks if both buyer and seller are ready to execute, and that any applicable condition(s) is/are met, and expiration has not been met;
     *** if so, this contract executes and transfers 'totalAmount' to 'seller' and 'fee' to 'receiver' **/
    /** @dev requires entire 'totalWithFee' be held by address(this). If properly executes, pays seller and emits event with effective time of execution.
     *** Does not require amountDeposited[buyer] == erc20.balanceOf(address(this)) - pendingWithdraw to allow buyer to deposit from multiple addresses if desired; */
    function execute() external {
        if (
            erc20.balanceOf(address(this)) - pendingWithdraw < totalWithFee ||
            (address(conditionManager) != address(0) &&
                !conditionManager.checkConditions())
        ) revert TokenLexscrow_NotReadyToExecute();

        if (!checkIfExpired()) {
            delete deposited;
            delete amountDeposited[buyer];

            // safeTransfer 'totalAmount' to 'seller' and 'fee' to 'receiver'; note the deposit functions perform checks against depositing more than the 'totalWithFee',
            // and further safeguarded by any excess balance being withdrawable by buyer after expiry in 'checkIfExpired()'
            safeTransfer(tokenContract, seller, totalAmount);
            safeTransfer(tokenContract, receiver, fee);

            // effective time of execution is block.timestamp upon payment to seller
            emit TokenLexscrow_Executed(block.timestamp);
        }
    }

    /// @notice convenience function to get a USD value receipt if a dAPI / data feed proxy exists for 'tokenContract', for example for 'seller' to submit 'totalAmount' immediately after execution/release of TokenLexscrow
    /// @dev external call will revert if price quote is too stale or if token is not supported; event containing '_paymentId' and '_usdValue' emitted by Receipt.sol
    /// @param _tokenAmount: amount of tokens (corresponding to this TokenLexscrow's 'tokenContract') for which caller is seeking the total USD value receipt
    function getReceipt(
        uint256 _tokenAmount
    ) external returns (uint256 _paymentId, uint256 _usdValue) {
        return
            RECEIPT.printReceipt(tokenContract, _tokenAmount, erc20.decimals());
    }

    /// @notice for a 'seller' to reject any depositing address (including 'buyer') and cause the return of their deposited amount
    /// @param _depositor: address being rejected by 'seller' which will subsequently be able to withdraw their 'amountDeposited'
    /// @dev if !openOffer and 'seller' passes 'buyer' to this function, 'buyer' will need to call 'updateBuyer' to choose another address and re-deposit tokens.
    function rejectDepositor(address _depositor) external nonReentrant {
        if (msg.sender != seller) revert TokenLexscrow_NotSeller();

        uint256 _amtDeposited = amountDeposited[_depositor];
        if (_amtDeposited == 0) revert TokenLexscrow_ZeroAmount();

        delete amountDeposited[_depositor];
        // regardless of whether '_depositor' is 'buyer', permit them to withdraw their 'amountWithdrawable' balance
        amountWithdrawable[_depositor] += _amtDeposited;
        // update the aggregate withdrawable balance counter
        pendingWithdraw += _amtDeposited;

        // if this depositor rejection causes the non-pendingWithdraw amount held in this contract to fall below the 'deposit', delete 'deposited'
        if (erc20.balanceOf(address(this)) - pendingWithdraw < deposit) delete deposited;

        if (_depositor == buyer && openOffer) {
            // if 'openOffer', delete the 'buyer' variable so the next valid depositor will become 'buyer'
            // we do not delete 'buyer' if !openOffer, to allow the 'buyer' to choose another address via 'updateBuyer', rather than irreversibly deleting the variable
            delete buyer;
            // the '_depositor' must have deposited at least 'deposit' since this is an open offer, so reset the 'deposited' variable as the deposit is now pending withdrawal
            delete deposited;
            emit TokenLexscrow_BuyerUpdated(address(0));
        }
    }

    /// @notice allows an address to withdraw 'amountWithdrawable' of tokens, such as a refundable amount post-expiry or if seller has called 'rejectDepositor' for such an address, etc.
    /// @dev used by a depositing address which 'seller' passed to 'rejectDepositor()', or if 'isExpired', used by 'buyer' and/or 'seller' (as applicable)
    function withdraw() external {
        uint256 _amt = amountWithdrawable[msg.sender];
        if (_amt == 0) revert TokenLexscrow_ZeroAmount();

        delete amountWithdrawable[msg.sender];
        // update the aggregate withdrawable balance counter
        pendingWithdraw -= _amt;

        safeTransfer(tokenContract, msg.sender, _amt);
        emit TokenLexscrow_DepositedAmountTransferred(msg.sender, _amt);
    }

    /// @notice check if expired, and if so, handle refundability by updating the 'amountWithdrawable' mapping as applicable
    /** @dev if expired, update isExpired boolean. If non-refundable, update seller's 'amountWithdrawable' to be the non-refundable deposit amount before updating buyer's mapping for the remainder.
     *** If refundable, update buyer's 'amountWithdrawable' to the entire balance. */
    /// @return isExpired
    function checkIfExpired() public nonReentrant returns (bool) {
        if (expirationTime <= block.timestamp) {
            isExpired = true;
            uint256 _balance = erc20.balanceOf(address(this)) - pendingWithdraw;
            bool _isDeposited = deposited;

            emit TokenLexscrow_Expired();

            delete deposited;
            delete amountDeposited[buyer];
            // update the aggregate withdrawable balance counter. Cannot overflow even if erc20.balanceOf(address(this)) == type(uint256).max because 'pendingWithdraw' is subtracted in the calculation of '_balance' above
            unchecked {
                pendingWithdraw += _balance;
            }

            if (_balance != 0) {
                // if non-refundable deposit and 'deposit' hasn't been reset to 'false' by
                // a successful 'execute()', enable 'seller' to withdraw the 'deposit' amount before enabling the remainder amount (if any) to be withdrawn by buyer
                // update mappings in order to allow 'buyer' to withdraw all of remaining '_balance' as fees are only paid upon successful execution
                if (!refundable && _isDeposited) {
                    amountWithdrawable[seller] = deposit;
                    amountWithdrawable[buyer] = _balance - deposit;
                } else amountWithdrawable[buyer] += _balance;
            }
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
