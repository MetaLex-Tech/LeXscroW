//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

// o=o=o=o=o=o=o EthLexscrow Factory o=o=o=o=o=o=o \\

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

import {EthLexscrow} from "./EthLexscrow.sol";
import {ICondition, LexscrowConditionManager} from "./libs/LexscrowConditionManager.sol";

/**
 * @title       EthLexscrowFactory
 *
 *
 * @notice      EthLexscrow factory contract, which enables a caller of 'deployEthLexscrow' to deploy a EthLexscrow with their chosen parameters;
 *              also houses the fee switch, fee denominator, and receiver address controls
 **/
contract EthLexscrowFactory {
    /// gas-saving and best practice to have fixed uint as an internal constant variable, used for fee calculations
    uint256 internal constant ONE = 1;

    /// @notice address which may update the fee parameters and receives any fees in wei if 'feeSwitch' == true
    address payable public receiver;
    address payable private _pendingReceiver;

    /// @notice whether a fee is payable for the EthLexscrow users deployed via 'deployEthLexscrow()'
    bool public feeSwitch;

    /// @notice number by which each user's total amount is divided in order to calculate the fee, if 'feeSwitch' == true
    uint256 public feeDenominator;

    ///
    /// EVENTS
    ///

    event EthLexscrowFactory_Deployment(address deployer, address indexed EthLexscrowAddress);
    event EthLexscrowFactory_FeeUpdate(bool feeSwitch, uint256 newFeeDenominator);
    event EthLexscrowFactory_ReceiverUpdate(address newReceiver);
    event LexscrowConditionManager_Deployment(
        address LexscrowConditionManagerAddress,
        LexscrowConditionManager.Condition[] conditions
    );

    ///
    /// ERRORS
    ///

    error EthLexscrowFactory_OnlyReceiver();
    error EthLexscrowFactory_ZeroAddress();
    error EthLexscrowFactory_ZeroInput();

    ///
    /// FUNCTIONS
    ///

    /** @dev enable optimization with >= 200 runs; 'msg.sender' is the initial 'receiver';
     ** constructor is payable for gas optimization purposes but msg.value should == 0. */
    constructor() payable {
        receiver = payable(msg.sender);
        // initialize to avoid a zero denominator, and there is also such a check in 'updateFee()'
        feeDenominator = ONE;
    }

    /** @notice for a user to deploy their own EthLexscrow, with a communicated fee if 'feeSwitch' == true that adjusts the total amounts (so the fee is paid by the buyer in EthLexscrow rather than here, by its deployer). Note that electing custom conditions may introduce
     ** execution reliance upon the details of the create LexscrowConditionManager, but the deployed EthLexscrow will be entirely immutable save for 'seller' and 'buyer' having the ability to update their own addresses. */
    /** @dev several of the various applicable input validations/condition checks for deployment of a EthLexscrow are in the prospective contracts rather than this factory.
     ** Fee (if 'feeSwitch' == true) is calculated on a percentage basis of raw amount of wei, rather than introducing price oracle dependency here;
     ** '_deposit', '_seller' and '_buyer' nomenclature used for clarity (rather than payee and payor or other alternatives),
     ** though intended purpose of each EthLexscrow is the user's choice; see comments above and in documentation.
     ** The constructor of each deployed EthLexscrow contains more detailed event emissions, rather than emitting duplicative information in this function */
    /// @param _refundable: whether the '_deposit' is refundable to the 'buyer' in the event escrow expires without executing
    /// @param _openOffer whether the EthLexscrow is open to any prospective 'buyer' and 'seller'.
    /// @param _deposit deposit amount in wei, which must be <= '_totalAmount' (< for partial deposit, == for full deposit).
    /// @param _totalAmount total amount (before any applicable fee, which will be calculated using this amount) of wei which will be deposited in the EthLexscrow, ultimately intended for 'seller'. Must be > 0
    /// @param _expirationTime _expirationTime in seconds (Unix time), which will be compared against block.timestamp. Because wei will only be released upon execution or become withdrawable at expiry, submitting a reasonable expirationTime is imperative
    /// @param _seller the seller's address, recipient of the 'totalAmount' if the contract executes. Ignored if 'openOffer'
    /// @param _buyer the buyer's address, depositor of the wei. Ignored if 'openOffer'
    /// @param _conditions array of Condition structs, which for each element contains:
    /// op: LexscrowConditionManager.Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    /// condition: address of the condition contract
    function deployEthLexscrow(
        bool _refundable,
        bool _openOffer,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _expirationTime,
        address payable _seller,
        address payable _buyer,
        LexscrowConditionManager.Condition[] calldata _conditions
    ) external {
        if (_seller == address(0) || (!_openOffer && _buyer == address(0))) revert EthLexscrowFactory_ZeroAddress();
        if (_totalAmount == 0) revert EthLexscrowFactory_ZeroInput();

        // if 'feeSwitch' == true, calculate fee based on '_totalAmount', so total amount + fee amount will be used in the EthLexscrow deployment
        uint256 _fee; // default fee of 0
        if (feeSwitch) {
            unchecked {
                _fee = _totalAmount / feeDenominator;
            }
        }

        LexscrowConditionManager _newConditionManager = new LexscrowConditionManager(_conditions);

        EthLexscrow.Amounts memory _amounts = EthLexscrow.Amounts(_deposit, _totalAmount, _fee, receiver);
        EthLexscrow _newEthLexscrow = new EthLexscrow(
            _refundable,
            _openOffer,
            _expirationTime,
            _seller,
            _buyer,
            address(_newConditionManager),
            _amounts
        );
        emit EthLexscrowFactory_Deployment(msg.sender, address(_newEthLexscrow));
        emit LexscrowConditionManager_Deployment(address(_newConditionManager), _conditions);
    }

    /// @notice allows the receiver to toggle the fee switch, and update the 'feeDenominator'
    /// @param _feeSwitch: boolean fee toggle for 'deployEthLexscrow()' (true == fees on, false == no fees)
    /// @param _newFeeDenominator: nonzero number to update the 'feeDenominator' variable, by which a user's submitted total amounts will be divided in order to calculate the fee; 10e14 corresponds to a 0.1% fee, 10e15 for 1%, etc. (fee calculations in 'deployEthLexscrow()' are 18 decimals)
    function updateFee(bool _feeSwitch, uint256 _newFeeDenominator) external {
        if (msg.sender != receiver) revert EthLexscrowFactory_OnlyReceiver();
        if (_newFeeDenominator == 0) revert EthLexscrowFactory_ZeroInput();
        feeSwitch = _feeSwitch;
        feeDenominator = _newFeeDenominator;

        emit EthLexscrowFactory_FeeUpdate(_feeSwitch, _newFeeDenominator);
    }

    /// @notice allows the 'receiver' to propose a replacement to their address. First step in two-step address change, as '_newReceiver' will subsequently need to call 'acceptReceiverRole()'
    /// @dev use care in updating 'receiver' as it must have the ability to call 'acceptReceiverRole()', or once it needs to be replaced, 'updateReceiver()'
    /// @param _newReceiver: new address for pending 'receiver', who must accept the role by calling 'acceptReceiverRole'
    function updateReceiver(address payable _newReceiver) external {
        if (msg.sender != receiver) revert EthLexscrowFactory_OnlyReceiver();
        _pendingReceiver = _newReceiver;
    }

    /// @notice allows the pending new receiver to accept the role transfer, and receive fees
    /// @dev access restricted to the address stored as '_pendingReceiver' to accept the two-step change. Transfers 'receiver' role to the caller and deletes '_pendingReceiver' to reset.
    function acceptReceiverRole() external {
        address payable _sender = payable(msg.sender);
        if (_sender != _pendingReceiver) revert EthLexscrowFactory_OnlyReceiver();
        delete _pendingReceiver;
        receiver = _sender;
        emit EthLexscrowFactory_ReceiverUpdate(_sender);
    }
}