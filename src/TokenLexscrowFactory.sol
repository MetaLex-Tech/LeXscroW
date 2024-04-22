//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

// o=o=o=o=o=o=o TokenLexscrow Factory o=o=o=o=o=o=o \\

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

import {TokenLexscrow} from "./TokenLexscrow.sol";
import {ICondition, LexscrowConditionManager} from "./libs/LexscrowConditionManager.sol";

interface IERC20 {
    function decimals() external view returns (uint256);
}

/**
 * @title       TokenLexscrowFactory
 *
 *
 * @notice      TokenLexscrow factory contract, which enables a caller of 'deployTokenLexscrow' to deploy a TokenLexscrow with their chosen parameters;
 *              also houses the fee switch, fee denominator, and receiver address controls
 **/
contract TokenLexscrowFactory {
    /// gas-saving and best practice to have fixed uint as an internal constant variable, used for fee calculations
    uint256 internal constant EIGHTEEN = 18;
    uint256 internal constant ONE = 1;
    uint256 internal constant TEN = 10;

    /// @notice address which may update the fee parameters and receives any token fees if 'feeSwitch' == true. Only accepts token fees, so 'payable' is not necessary
    address public receiver;
    address private _pendingReceiver;

    /// @notice whether a fee is payable for the TokenLexscrow users deployed via 'deployTokenLexscrow()'
    bool public feeSwitch;

    /// @notice number by which each user's total amount is divided in order to calculate the fee, if 'feeSwitch' == true
    uint256 public feeDenominator;

    ///
    /// EVENTS
    ///

    event TokenLexscrowFactory_Deployment(address deployer, address indexed TokenLexscrowAddress);
    event TokenLexscrowFactory_FeeUpdate(bool feeSwitch, uint256 newFeeDenominator);
    event TokenLexscrowFactory_ReceiverUpdate(address newReceiver);
    event LexscrowConditionManager_Deployment(
        address LexscrowConditionManagerAddress,
        LexscrowConditionManager.Condition[] conditions
    );

    ///
    /// ERRORS
    ///

    error TokenLexscrowFactory_OnlyReceiver();
    error TokenLexscrowFactory_ZeroAddress();
    error TokenLexscrowFactory_ZeroInput();

    ///
    /// FUNCTIONS
    ///

    /** @dev enable optimization with >= 200 runs; 'msg.sender' is the initial 'receiver';
     ** constructor is payable for gas optimization purposes but msg.value should == 0. */
    constructor() payable {
        receiver = msg.sender;
        // initialize to avoid a zero denominator, and there is also such a check in 'updateFee()'
        feeDenominator = ONE;
    }

    /** @notice for a user to deploy their own TokenLexscrow, with a communicated fee if 'feeSwitch' == true that adjusts the total amounts (so the fee is paid by the buyer in TokenLexscrow rather than here, by its deployer). Note that electing custom conditions may introduce
     ** execution reliance upon the details of the create LexscrowConditionManager, but the deployed TokenLexscrow will be entirely immutable save for 'seller' and 'buyer' having the ability to update their own addresses. */
    /** @dev several of the various applicable input validations/condition checks for deployment of a TokenLexscrow are in the prospective contracts rather than this factory.
     ** Fee (if 'feeSwitch' == true) is calculated on a percentage basis of (decimal-accounted) raw amount, rather than introducing price oracle dependency here;
     ** fee-on-transfer and rebasing tokens are NOT SUPPORTED as the applicable deposit & fee amounts are immutable.
     ** '_deposit', '_seller' and '_buyer' nomenclature used for clarity (rather than payee and payor or other alternatives),
     ** though intended purpose of each TokenLexscrow is the user's choice; see comments above and in documentation.
     ** The constructor of each deployed TokenLexscrow contains more detailed event emissions, rather than emitting duplicative information in this function */
    /// @param _refundable: whether the '_deposit' is refundable to the 'buyer' in the event escrow expires without executing
    /// @param _openOffer whether the TokenLexscrow is open to any prospective 'buyer' and 'seller'.
    /// @param _deposit deposit amount in tokens, which must be <= '_totalAmount' (< for partial deposit, == for full deposit).
    /// @param _totalAmount total amount (before any applicable fee, which will be calculated using this amount) of 'tokenContract' which will be deposited in the TokenLexscrow, ultimately intended for 'seller'. Must be > 0
    /// @param _expirationTime _expirationTime in seconds (Unix time), which will be compared against block.timestamp. Because tokens will only be released upon execution or become withdrawable at expiry, submitting a reasonable expirationTime is imperative
    /// @param _seller the seller's address, recipient of the tokens if the contract executes. Ignored if 'openOffer'
    /// @param _buyer the buyer's address, depositor of the tokens. Ignored if 'openOffer'
    /// @param _tokenContract contract address for the ERC20 token used in the TokenLexscrow; fee-on-transfer and rebasing tokens are NOT SUPPORTED as the applicable deposit & fee amounts are immutable
    /// @param _conditions array of Condition structs, which for each element contains:
    /// op: LexscrowConditionManager.Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    /// condition: address of the condition contract
    function deployTokenLexscrow(
        bool _refundable,
        bool _openOffer,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _expirationTime,
        address _seller,
        address _buyer,
        address _tokenContract,
        LexscrowConditionManager.Condition[] calldata _conditions
    ) external {
        if (_seller == address(0) || _tokenContract == address(0) || (!_openOffer && _buyer == address(0)))
            revert TokenLexscrowFactory_ZeroAddress();
        if (_totalAmount == 0) revert TokenLexscrowFactory_ZeroInput();

        // if 'feeSwitch' == true, calculate fee based on '_totalAmount', so total amount + fee amount will be used in the TokenLexscrow deployment
        uint256 _fee; // default fee of 0
        if (feeSwitch) {
            uint256 _decimals = IERC20(_tokenContract).decimals();
            if (_decimals == 0) _decimals = EIGHTEEN; // 'decimals()' is technically optional for ERC20s, so if not present, assume 18 (see https://eips.ethereum.org/EIPS/eip-20)
            // Normalize feeDenominator to the token's decimals to maintain proportionality
            uint256 _feeDenominatorAdjusted = feeDenominator;
            if (_decimals != EIGHTEEN) {
                unchecked {
                    // 'feeDenominator' and '_decimals' both have condition checks against == 0
                    _feeDenominatorAdjusted = (_feeDenominatorAdjusted * TEN ** _decimals) / TEN ** EIGHTEEN;
                }
            }
            // avoid division by zero error
            _feeDenominatorAdjusted = _feeDenominatorAdjusted != 0 ? _feeDenominatorAdjusted : ONE;
            unchecked {
                _fee = _totalAmount / _feeDenominatorAdjusted;
            }
        }

        LexscrowConditionManager _newConditionManager = new LexscrowConditionManager(_conditions);

        TokenLexscrow.Amounts memory _amounts = TokenLexscrow.Amounts(_deposit, _totalAmount, _fee, receiver);
        TokenLexscrow _newTokenLexscrow = new TokenLexscrow(
            _refundable,
            _openOffer,
            _expirationTime,
            _seller,
            _buyer,
            _tokenContract,
            address(_newConditionManager),
            _amounts
        );
        emit TokenLexscrowFactory_Deployment(msg.sender, address(_newTokenLexscrow));
        emit LexscrowConditionManager_Deployment(address(_newConditionManager), _conditions);
    }

    /// @notice allows the receiver to toggle the fee switch, and update the 'feeDenominator'
    /// @param _feeSwitch: boolean fee toggle for 'deployTokenLexscrow()' (true == fees on, false == no fees)
    /// @param _newFeeDenominator: nonzero number to update the 'feeDenominator' variable, by which a user's submitted total amounts will be divided in order to calculate the fee; 10e14 corresponds to a 0.1% fee, 10e15 for 1%, etc. (fee calculations in 'deployTokenLexscrow()' are 18 decimals)
    function updateFee(bool _feeSwitch, uint256 _newFeeDenominator) external {
        if (msg.sender != receiver) revert TokenLexscrowFactory_OnlyReceiver();
        if (_newFeeDenominator == 0) revert TokenLexscrowFactory_ZeroInput();
        feeSwitch = _feeSwitch;
        feeDenominator = _newFeeDenominator;

        emit TokenLexscrowFactory_FeeUpdate(_feeSwitch, _newFeeDenominator);
    }

    /// @notice allows the 'receiver' to propose a replacement to their address. First step in two-step address change, as '_newReceiver' will subsequently need to call 'acceptReceiverRole()'
    /// @dev use care in updating 'receiver' as it must have the ability to call 'acceptReceiverRole()', or once it needs to be replaced, 'updateReceiver()'
    /// @param _newReceiver: new address for pending 'receiver', who must accept the role by calling 'acceptReceiverRole'
    function updateReceiver(address _newReceiver) external {
        if (msg.sender != receiver) revert TokenLexscrowFactory_OnlyReceiver();
        _pendingReceiver = _newReceiver;
    }

    /// @notice allows the pending new receiver to accept the role transfer, and receive fees
    /// @dev access restricted to the address stored as '_pendingReceiver' to accept the two-step change. Transfers 'receiver' role to the caller and deletes '_pendingReceiver' to reset.
    function acceptReceiverRole() external {
        address _sender = msg.sender;
        if (_sender != _pendingReceiver) revert TokenLexscrowFactory_OnlyReceiver();
        delete _pendingReceiver;
        receiver = _sender;
        emit TokenLexscrowFactory_ReceiverUpdate(_sender);
    }
}
