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

/// o=o=o=o=o DoubleTokenLexscrow Factory o=o=o=o=o \\\

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

import {DoubleTokenLexscrow} from "./DoubleTokenLexscrow.sol";
import {ICondition, LexscrowConditionManager} from "./libs/LexscrowConditionManager.sol";

interface IERC20 {
    function decimals() external view returns (uint256);
}

/**
 * @title       o=o=o=o=o DoubleTokenLexscrowFactory o=o=o=o=o
 **/
/**
 * @notice DoubleTokenLexscrow factory contract, which enables a caller of 'deployDoubleTokenLexscrow' to deploy a DoubleTokenLexscrow with their chosen parameters;
 * also houses the fee switch, fee denominator, and receiver address controls
 **/
contract DoubleTokenLexscrowFactory {
    /// gas-saving and best practice to have fixed uint as an internal constant variable, used for fee calculations
    uint256 internal constant EIGHTEEN = 18;
    uint256 internal constant ONE = 1;
    uint256 internal constant TEN = 10;

    /// @notice address which may update the fee parameters and receives any token fees if 'feeSwitch' == true. Only accepts token fees, so 'payable' is not necessary
    address public receiver;
    address private _pendingReceiver;

    /// @notice whether a fee is payable for the DoubleTokenLexscrow users deployed via 'deployDoubleTokenLexscrow()'
    bool public feeSwitch;

    /// @notice number by which each user's total amount is divided in order to calculate the fee, if 'feeSwitch' == true
    uint256 public feeDenominator;

    ///
    /// EVENTS
    ///

    event DoubleTokenLexscrowFactory_Deployment(
        address deployer,
        address indexed DoubleTokenLexscrowAddress
    );
    event DoubleTokenLexscrowFactory_FeeUpdate(
        bool feeSwitch,
        uint256 newFeeDenominator
    );
    event DoubleTokenLexscrowFactory_ReceiverUpdate(address newReceiver);
    event LexscrowConditionManager_Deployment(
        address LexscrowConditionManagerAddress,
        LexscrowConditionManager.Condition[] conditions
    );

    ///
    /// ERRORS
    ///

    error DoubleTokenLexscrowFactory_OnlyReceiver();
    error DoubleTokenLexscrowFactory_ZeroInput();

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

    /** @notice for a user to deploy their own DoubleTokenLexscrow, with a communicated fee if 'feeSwitch' == true that adjusts the total amounts (so the fee is paid by the DoubleTokenLexscrow parties rather than its deployer). Note that electing custom conditions may introduce
     ** execution reliance upon the details of the create LexscrowConditionManager, but the deployed DoubleTokenLexscrow will be entirely immutable save for 'seller' and 'buyer' having the ability to update their own addresses. */
    /** @dev the various applicable input validations/condition checks for deployment of a DoubleTokenLexscrow are in the prospective contracts rather than this factory.
     ** Fee (if 'feeSwitch' == true) is calculated on a percentage basis of (decimal-accounted) raw amount, rather than introducing price oracle dependency here;
     ** fee-on-transfer and rebasing tokens are NOT SUPPORTED as the applicable deposit & fee amounts are immutable.
     ** '_deposit', '_seller' and '_buyer' nomenclature used for clarity (rather than payee and payor or other alternatives),
     ** though intended purpose of each DoubleTokenLexscrow is the user's choice; see comments above and in documentation.
     ** The constructor of each deployed DoubleTokenLexscrow contains more detailed event emissions, rather than emitting duplicative information in this function */
    /// @param _openOffer whether the DoubleTokenLexscrow is open to any prospective 'buyer' and 'seller'.
    /// @param _totalAmount1 total amount (before any applicable fee, which will be calculated using this amount) of 'tokenContract1' which will be deposited in the DoubleTokenLexscrow, ultimately intended for 'seller'
    /// @param _totalAmount2 total amount (before any applicable fee, which will be calculated using this amount) of 'tokenContract2' which will be deposited in the DoubleTokenLexscrow, ultimately intended for 'buyer'
    /// @param _expirationTime _expirationTime in seconds (Unix time), which will be compared against block.timestamp. Because tokens will only be released upon execution or become withdrawable at expiry, submitting a reasonable expirationTime is imperative
    /// @param _seller the seller's address, depositor of token2 and recipient of token1 if the contract executes. Ignored if 'openOffer'
    /// @param _buyer the buyer's address, depositor of token1 and recipient of token2 if the contract executes. Ignored if 'openOffer'
    /// @param _tokenContract1 contract address for the ERC20 token used in the DoubleTokenLexscrow as 'token1'; fee-on-transfer and rebasing tokens are NOT SUPPORTED as the applicable deposit & fee amounts are immutable
    /// @param _tokenContract2 contract address for the ERC20 token used in the DoubleTokenLexscrow as 'token2'; fee-on-transfer and rebasing tokens are NOT SUPPORTED as the applicable deposit & fee amounts are immutable
    /// @param _receipt contract address for Receipt.sol contract
    /// @param _conditions array of Condition structs, which for each element contains:
    /// op: LexscrowConditionManager.Logic enum, either 'AND' (all conditions must be true) or 'OR' (only one of the conditions must be true)
    /// condition: address of the condition contract
    function deployDoubleTokenLexscrow(
        bool _openOffer,
        uint256 _totalAmount1,
        uint256 _totalAmount2,
        uint256 _expirationTime,
        address _seller,
        address _buyer,
        address _tokenContract1,
        address _tokenContract2,
        address _receipt,
        LexscrowConditionManager.Condition[] memory _conditions
    ) external {
        // if 'feeSwitch' == true, calculate fees based on applicable '_totalAmount', so each total amount + fee amount will be used in the DoubleTokenLexscrow deployment
        uint256 _fee1; // default fees of 0
        uint256 _fee2;
        if (feeSwitch) {
            uint256 _decimals1 = IERC20(_tokenContract1).decimals();
            if (_decimals1 == 0) _decimals1 = EIGHTEEN; // 'decimals()' is technically optional for ERC20s, so if not present, assume 18 (see https://eips.ethereum.org/EIPS/eip-20)
            // Normalize feeDenominator to the token's decimals to maintain proportionality
            uint256 _feeDenominatorAdjusted1 = feeDenominator;
            if (_decimals1 != EIGHTEEN) {
                unchecked {
                    // 'feeDenominator' and '_decimals1' both have condition checks against == 0
                    _feeDenominatorAdjusted1 =
                        (_feeDenominatorAdjusted1 * TEN ** _decimals1) /
                        TEN ** EIGHTEEN;
                }
            }
            // avoid division by zero error
            _feeDenominatorAdjusted1 = _feeDenominatorAdjusted1 != 0
                ? _feeDenominatorAdjusted1
                : ONE;
            unchecked {
                _fee1 = _totalAmount1 / _feeDenominatorAdjusted1;
            }

            // repeat for the second token
            uint256 _decimals2 = IERC20(_tokenContract2).decimals();
            if (_decimals2 == 0) _decimals2 = EIGHTEEN;
            uint256 _feeDenominatorAdjusted2 = feeDenominator;
            if (_decimals2 != EIGHTEEN) {
                unchecked {
                    _feeDenominatorAdjusted2 =
                        (_feeDenominatorAdjusted2 * TEN ** _decimals2) /
                        TEN ** EIGHTEEN;
                }
            }
            _feeDenominatorAdjusted2 = _feeDenominatorAdjusted2 != 0
                ? _feeDenominatorAdjusted2
                : ONE;
            unchecked {
                _fee2 = _totalAmount2 / _feeDenominatorAdjusted2;
            }
        }

        LexscrowConditionManager _newConditionManager = new LexscrowConditionManager(
                _conditions
            );

        DoubleTokenLexscrow.Amounts memory _amounts = DoubleTokenLexscrow
            .Amounts(_totalAmount1, _fee1, _totalAmount2, _fee2, receiver);
        DoubleTokenLexscrow _newDoubleTokenLexscrow = new DoubleTokenLexscrow(
            _openOffer,
            _expirationTime,
            _seller,
            _buyer,
            _tokenContract1,
            _tokenContract2,
            address(_newConditionManager),
            _receipt,
            _amounts
        );
        emit DoubleTokenLexscrowFactory_Deployment(
            msg.sender,
            address(_newDoubleTokenLexscrow)
        );
        emit LexscrowConditionManager_Deployment(
            address(_newConditionManager),
            _conditions
        );
    }

    /// @notice allows the receiver to toggle the fee switch, and update the 'feeDenominator'
    /// @param _feeSwitch: boolean fee toggle for 'deployDoubleTokenLexscrow()' (true == fees on, false == no fees)
    /// @param _newFeeDenominator: nonzero number to update the 'feeDenominator' variable, by which a user's submitted total amounts will be divided in order to calculate the fee; 10e14 corresponds to a 0.1% fee, 10e15 for 1%, etc. (fee calculations in 'deployDoubleTokenLexscrow()' are 18 decimals)
    function updateFee(bool _feeSwitch, uint256 _newFeeDenominator) external {
        if (msg.sender != receiver)
            revert DoubleTokenLexscrowFactory_OnlyReceiver();
        if (_newFeeDenominator == 0)
            revert DoubleTokenLexscrowFactory_ZeroInput();
        feeSwitch = _feeSwitch;
        feeDenominator = _newFeeDenominator;

        emit DoubleTokenLexscrowFactory_FeeUpdate(
            _feeSwitch,
            _newFeeDenominator
        );
    }

    /// @notice allows the 'receiver' to propose a replacement to their address. First step in two-step address change, as '_newReceiver' will subsequently need to call 'acceptReceiverRole()'
    /// @dev use care in updating 'receiver' as it must have the ability to call 'acceptReceiverRole()', or once it needs to be replaced, 'updateReceiver()'
    /// @param _newReceiver: new address for pending 'receiver', who must accept the role by calling 'acceptReceiverRole'
    function updateReceiver(address _newReceiver) external {
        if (msg.sender != receiver)
            revert DoubleTokenLexscrowFactory_OnlyReceiver();
        _pendingReceiver = _newReceiver;
    }

    /// @notice allows the pending new receiver to accept the role transfer, and receive fees
    /// @dev access restricted to the address stored as '_pendingReceiver' to accept the two-step change. Transfers 'receiver' role to the caller and deletes '_pendingReceiver' to reset.
    function acceptReceiverRole() external {
        address _sender = msg.sender;
        if (_sender != _pendingReceiver)
            revert DoubleTokenLexscrowFactory_OnlyReceiver();
        delete _pendingReceiver;
        receiver = _sender;
        emit DoubleTokenLexscrowFactory_ReceiverUpdate(_sender);
    }
}
