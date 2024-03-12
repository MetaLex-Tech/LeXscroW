//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * this solidity file is provided as-is; no guarantee, representation or warranty is being made, express or implied,
 * as to the safety or correctness of the code or any smart contracts or other software deployed from these files.
 **/

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

/////////// o=o=o=o=o EthLexscrow o=o=o=o=o \\\\\\\\\\\

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

/// @notice interface to Receipt.sol, which optionally returns USD-value receipts for a provided token amount
interface IReceipt {
    function printReceipt(
        address token,
        uint256 tokenAmount,
        uint256 decimals
    ) external returns (uint256, uint256);
}

/// @notice interface to LexscrowConditionManager or MetaLeX's regular ConditionManager
interface ILexscrowConditionManager {
    function checkConditions() external returns (bool);
}

/// @notice Solady's SafeTransferLib 'SafeTransferETH()'.  Extracted from library and pasted for convenience, transparency, and size minimization.
/// @author Solady (https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol), license copied below
abstract contract SafeTransferLib {
    /// @dev The ETH transfer has failed.
    error ETHTransferFailed();

    /// @dev Sends `amount` (in wei) ETH to `to`; reverts upon failure.
    function safeTransferETH(address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(
                call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)
            ) {
                // Store the function selector of `ETHTransferFailed()`.
                mstore(0x00, 0xb12d13eb)
                revert(0x1c, 0x04)
            }
        }
    }
}

/// @notice Gas-optimized reentrancy protection for smart contracts.
abstract contract ReentrancyGuard {
    uint256 private _locked = 1;
    error Reentrancy();

    modifier nonReentrant() virtual {
        if (_locked == 2) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }
}

/**
 * @title       o=o=o=o=o EthLexscrow o=o=o=o=o
 *
 * @notice non-custodial smart escrow contract for ETH-denominated transaction on Ethereum Mainnet, supporting:
 * partial or full deposit amount
 * refundable or non-refundable deposit upon expiry
 * seller-identified buyer or open offer
 * escrow expiration denominated in seconds
 * optional conditions for execution (contingent execution based on oracle-fed external data value)
 * buyer and seller addresses replaceable by applicable party
 *
 * @dev adapted from EthLocker (https://github.com/ChainLockerLLC/smart-contracts/blob/main/src/EthLocker.sol)
 * executes and releases 'totalAmount' to 'seller' iff:
 * (1) 'buyer' and 'seller' have both called 'readyToExecute()'
 * (2) address(this).balance - 'pendingWithdraw' >= 'totalAmount'
 * (3) 'expirationTime' > block.timestamp
 * (4) any condition(s) are satisfied
 *
 * otherwise, amount held in address(this) will be treated according to the code in 'checkIfExpired()' when called following expiry
 *
 * variables are public for interface friendliness and enabling getters.
 * 'seller', 'buyer', 'deposit', 'refundable', 'open offer' and other terminology, naming, and descriptors herein are used only for simplicity and convenience of reference, and
 * should not be interpreted to ascribe nor imply any agreement or relationship between or among any author, modifier, deployer, user, contract, asset, or other relevant participant hereto
 **/
contract EthLexscrow is ReentrancyGuard, SafeTransferLib {
    struct Amounts {
        uint256 deposit;
        uint256 totalAmount;
        uint256 fee;
        address payable receiver;
    }

    // Receipt.sol contract address, ETH mainnet
    IReceipt internal constant RECEIPT =
        IReceipt(0xf838D6829fcCBedCB0B4D8aD58cb99814F935BA8);
    // 18 decimals for wei
    uint256 internal constant DECIMALS = 18;

    ILexscrowConditionManager public immutable conditionManager;
    address payable public immutable receiver;
    bool public immutable openOffer;
    bool public immutable refundable;
    uint256 public immutable deposit;
    uint256 public immutable expirationTime;
    uint256 public immutable fee;
    uint256 public immutable totalAmount;
    uint256 public immutable totalWithFee;

    bool public deposited;
    bool public isExpired;
    bool public buyerApproved;
    bool public sellerApproved;
    address payable public buyer;
    address payable public seller;
    /// @notice aggregate pending withdrawable amount, so address(this) balance checks subtract withdrawable, but not yet withdrawn, amounts
    uint256 public pendingWithdraw;

    mapping(address => uint256) public amountDeposited;
    mapping(address => uint256) public amountWithdrawable;

    ///
    /// EVENTS
    ///

    event EthLexscrow_AmountReceived(uint256 weiAmount);
    event EthLexscrow_BuyerReady();
    event EthLexscrow_BuyerUpdated(address newBuyer);
    event EthLexscrow_DepositedAmountTransferred(
        address recipient,
        uint256 amount
    );
    event EthLexscrow_DepositInEscrow(address depositor);
    event EthLexscrow_Deployed(
        bool refundable,
        bool openOffer,
        uint256 expirationTime,
        address seller,
        address buyer,
        address conditionManager,
        Amounts amounts
    );
    event EthLexscrow_Expired();
    event EthLexscrow_Executed(uint256 indexed effectiveTime);
    event EthLexscrow_TotalAmountInEscrow();
    event EthLexscrow_SellerReady();
    event EthLexscrow_SellerUpdated(address newSeller);

    ///
    /// ERRORS
    ///

    error EthLexscrow_BalanceExceedsTotalAmount();
    error EthLexscrow_DepositGreaterThanTotalAmount();
    error EthLexscrow_IsExpired();
    error EthLexscrow_MustDepositTotalAmount();
    error EthLexscrow_NotReadyToExecute();
    error EthLexscrow_NotBuyer();
    error EthLexscrow_NotSeller();
    error EthLexscrow_OnlyOpenOffer();
    error EthLexscrow_ZeroAmount();

    ///
    /// FUNCTIONS
    ///

    /// @notice constructs the EthLexscrow smart escrow contract. Arranger MUST verify that '_conditionManager' is accurate if not relying upon the factory contract to deploy it
    /// @param _refundable: whether the '_deposit' is refundable to the 'buyer' in the event escrow expires without executing
    /// @param _openOffer: whether this escrow is open to any prospective 'buyer' (revocable at seller's option). A 'buyer' assents by sending 'deposit' to address(this) after deployment
    /// @param _expirationTime: _expirationTime in seconds (Unix time), which will be compared against block.timestamp. input type(uint256).max for no expiry (not recommended, as funds will only be released upon execution or if seller rejects depositor -- refunds only process at expiry)
    /// @param _seller: the seller's address, recipient of the '_totalAmount' if the contract executes
    /// @param _buyer: the buyer's address, who will cause the '_totalAmount' to be transferred to this address. Ignored if 'openOffer'
    /// @param _conditionManager contract address for LexscrowConditionManager.sol or ConditionManager.sol, or address(0) for no conditions
    /// @param _amounts: Amounts struct containing:
    /// deposit: deposit amount in wei, which must be <= '_totalAmount' (< for partial deposit, == for full deposit). If 'openOffer', msg.sender must deposit entire 'totalAmount', but if '_refundable', this amount will be refundable to the accepting address of the open offer (buyer) at expiry if not yet executed
    /// totalAmount: total amount of wei ultimately intended for 'seller', not including fees. Must be > 0
    /// fee: amount of wei that also must be deposited, if any, which will be paid to the fee receiver
    /// receiver: address payable to receive 'fee'
    constructor(
        bool _refundable,
        bool _openOffer,
        uint256 _expirationTime,
        address payable _seller,
        address payable _buyer,
        address _conditionManager,
        Amounts memory _amounts
    ) payable {
        if (_amounts.deposit > _amounts.totalAmount)
            revert EthLexscrow_DepositGreaterThanTotalAmount();
        if (_amounts.totalAmount == 0) revert EthLexscrow_ZeroAmount();
        if (_expirationTime <= block.timestamp) revert EthLexscrow_IsExpired();

        refundable = _refundable;
        openOffer = _openOffer;
        expirationTime = _expirationTime;
        seller = _seller;
        buyer = _buyer;
        deposit = _amounts.deposit;
        totalAmount = _amounts.totalAmount;
        fee = _amounts.fee;
        totalWithFee = _amounts.totalAmount + _amounts.fee; // revert if overflow
        receiver = _amounts.receiver;
        conditionManager = ILexscrowConditionManager(_conditionManager);

        emit EthLexscrow_Deployed(
            _refundable,
            _openOffer,
            _expirationTime,
            _seller,
            _buyer,
            _conditionManager,
            _amounts
        );
    }

    /// @notice deposit value simply by sending 'msg.value' to 'address(this)'; if openOffer, msg.sender must deposit 'totalWithFee'
    /** @dev max msg.value limit of 'totalWithFee', and if 'totalWithFee' is already held or escrow has expired, revert. Updates boolean and emits event when 'deposit' reached
     ** also updates 'buyer' to msg.sender if true 'openOffer' and false 'deposited' (msg.sender must send 'totalWithFee' to accept an openOffer), and
     ** records amount deposited by msg.sender in case of refundability or where 'seller' rejects a 'buyer' and buyer's deposited amount is to be returned  */
    receive() external payable {
        uint256 _lockedBalance = address(this).balance - pendingWithdraw;
        if (_lockedBalance > totalWithFee)
            revert EthLexscrow_BalanceExceedsTotalAmount();
        if (expirationTime <= block.timestamp) revert EthLexscrow_IsExpired();
        if (openOffer && _lockedBalance < totalWithFee)
            revert EthLexscrow_MustDepositTotalAmount();
        if (_lockedBalance >= deposit && !deposited) {
            // if this EthLexscrow is an open offer and was not yet accepted (thus '!deposited'), make depositing address the 'buyer' and update 'deposited' to true
            if (openOffer) {
                buyer = payable(msg.sender);
                emit EthLexscrow_BuyerUpdated(msg.sender);
            }
            deposited = true;
            emit EthLexscrow_DepositInEscrow(msg.sender);
        }
        if (_lockedBalance == totalWithFee)
            emit EthLexscrow_TotalAmountInEscrow();

        amountDeposited[msg.sender] += msg.value;
        emit EthLexscrow_AmountReceived(msg.value);
    }

    /// @notice for the current seller to designate a new recipient address
    /// @param _seller: new recipient address of seller
    function updateSeller(address payable _seller) external {
        if (msg.sender != seller) revert EthLexscrow_NotSeller();

        seller = _seller;
        emit EthLexscrow_SellerUpdated(_seller);
    }

    /// @notice for the current 'buyer' to designate a new buyer address
    /// @param _buyer: new address of buyer
    function updateBuyer(address payable _buyer) external {
        if (msg.sender != buyer) revert EthLexscrow_NotBuyer();

        // transfer 'amountDeposited[buyer]' to the new '_buyer', delete the existing buyer's 'amountDeposited', and update the 'buyer' state variable
        amountDeposited[_buyer] += amountDeposited[buyer];
        delete amountDeposited[buyer];

        buyer = _buyer;
        emit EthLexscrow_BuyerUpdated(_buyer);
    }

    /// @notice seller and buyer each call this when ready to execute; other address callers will have no effect
    /// @dev no need for an address(this).balance check because (1) a reasonable seller will only pass 'true'
    /// if 'totalWithFee' is in place, and (2) 'execute()' requires the locked balance >= 'totalWithFee'
    /// separate conditionals in case 'buyer' == 'seller'
    function readyToExecute() external {
        if (msg.sender == seller) {
            sellerApproved = true;
            emit EthLexscrow_SellerReady();
        }
        if (msg.sender == buyer) {
            buyerApproved = true;
            emit EthLexscrow_BuyerReady();
        }
    }

    /** @notice callable by any external address: checks if both buyer and seller are ready to execute and expiration has not been met;
     *** if so, this contract executes and transfers 'totalAmount' to 'seller' and 'fee' to 'receiver' **/
    /** @dev requires entire 'totalWithFee' be held by address(this). If properly executes, pays seller and receiver and emits event with effective time of execution.
     *** Does not require amountDeposited[buyer] == address(this).balance to allow buyer to deposit from multiple addresses if desired */
    function execute() external {
        uint256 _lockedBalance = address(this).balance - pendingWithdraw;
        if (
            !sellerApproved ||
            !buyerApproved ||
            _lockedBalance < totalWithFee ||
            (address(conditionManager) != address(0) &&
                !conditionManager.checkConditions())
        ) revert EthLexscrow_NotReadyToExecute();

        // delete approvals
        delete sellerApproved;
        delete buyerApproved;

        if (!checkIfExpired()) {
            delete deposited;
            delete amountDeposited[buyer];
            // safeTransfer 'totalAmount' to 'seller' and 'fee' to 'receiver', since 'receive()' prevents depositing more than the totalWithFee, and safeguarded by any excess balance being withdrawable by buyer after expiry in 'checkIfExpired()'
            safeTransferETH(seller, totalAmount);
            safeTransferETH(receiver, fee);

            // effective time of execution is block.timestamp upon payment to seller
            emit EthLexscrow_Executed(block.timestamp);
        }
    }

    /// @notice convenience function to get a USD value receipt if a dAPI / data feed proxy exists for ETH, for example for 'seller' to submit 'totalAmount' immediately after execution/release of this EthLexscrow
    /// @dev external call will revert if price quote is too stale or if token is not supported; event containing '_paymentId' and '_usdValue' emitted by Receipt.sol. address(0) hard-coded for tokenContract, as native gas token price is sought
    /// @param _weiAmount: amount of wei for which caller is seeking the total USD value receipt (for example, 'totalAmount' or 'deposit')
    function getReceipt(
        uint256 _weiAmount
    ) external returns (uint256 _paymentId, uint256 _usdValue) {
        return RECEIPT.printReceipt(address(0), _weiAmount, DECIMALS);
    }

    /// @notice for a 'seller' to reject any depositing address (including 'buyer') and enable their withdrawal of their deposited amount in 'withdraw()'
    /// @param _depositor: address being rejected by 'seller' which will subsequently be able to withdraw their 'amountDeposited' in 'withdraw()'
    /// @dev if !openOffer and 'seller' passes 'buyer' to this function, 'buyer' will need to call 'updateBuyer' to choose another address and re-deposit tokens.
    function rejectDepositor(address payable _depositor) external nonReentrant {
        if (msg.sender != seller) revert EthLexscrow_NotSeller();

        uint256 _amtDeposited = amountDeposited[_depositor];
        if (_amtDeposited == 0) revert EthLexscrow_ZeroAmount();

        delete amountDeposited[_depositor];
        // regardless of whether '_depositor' is 'buyer', permit them to withdraw their 'amountWithdrawable' balance
        amountWithdrawable[_depositor] += _amtDeposited;
        // update the aggregate withdrawable balance counter
        pendingWithdraw += _amtDeposited;

        // reset 'deposited' and 'buyerApproved' variables if 'seller' passed 'buyer' as '_depositor'
        if (_depositor == buyer) {
            delete deposited;
            delete buyerApproved;
            // if 'openOffer', delete the 'buyer' variable so the next valid depositor will become 'buyer'
            // we do not delete 'buyer' if !openOffer, to allow the 'buyer' to choose another address via 'updateBuyer', rather than irreversibly deleting the variable
            if (openOffer) {
                delete buyer;
                emit EthLexscrow_BuyerUpdated(address(0));
            }
        }
    }

    /// @notice allows an address to withdraw 'amountWithdrawable' of wei, such as a refundable amount post-expiry or if seller has called 'rejectDepositor' for such an address, etc.
    /// @dev used by a depositing address which 'seller' passed to 'rejectDepositor()', or if 'isExpired', used by 'buyer' and/or 'seller' (as applicable)
    function withdraw() external {
        uint256 _amt = amountWithdrawable[msg.sender];
        if (_amt == 0) revert EthLexscrow_ZeroAmount();

        delete amountWithdrawable[msg.sender];
        // update the aggregate withdrawable balance counter
        pendingWithdraw -= _amt;

        safeTransferETH(payable(msg.sender), _amt);
        emit EthLexscrow_DepositedAmountTransferred(msg.sender, _amt);
    }

    /// @notice check if expired, and if so, handle refundability by updating the 'amountWithdrawable' mapping as applicable
    /** @dev if expired, update isExpired boolean. If non-refundable, update seller's 'amountWithdrawable' to be the non-refundable deposit amount before updating buyer's mapping for the remainder.
     *** If refundable, update buyer's 'amountWithdrawable' to the entire balance. */
    /// @return isExpired
    function checkIfExpired() public nonReentrant returns (bool) {
        if (expirationTime <= block.timestamp) {
            isExpired = true;
            uint256 _balance = address(this).balance - pendingWithdraw;
            bool _isDeposited = deposited;

            emit EthLexscrow_Expired();

            delete deposited;
            delete amountDeposited[buyer];
            // update the aggregate withdrawable balance counter. Cannot overflow even if address(this).balance == type(uint256).max because 'pendingWithdraw' is subtracted in the calculation of '_balance' above
            unchecked {
                pendingWithdraw += _balance;
            }

            if (_balance > 0) {
                // if non-refundable deposit and 'deposit' hasn't been reset to 'false' by a successful 'execute()', enable 'seller' to withdraw the 'deposit' amount
                // before enabling the remainder amount (if any) to be withdrawn by buyer, as fee is only paid upon successful execution
                if (!refundable && _isDeposited) {
                    amountWithdrawable[seller] = deposit;
                    amountWithdrawable[buyer] = _balance - deposit;
                } else amountWithdrawable[buyer] = _balance;
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
