// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/TokenLexscrowFactory.sol";

/// @notice foundry framework testing of TokenLexscrowFactory.sol
contract TokenLexscrowFactoryTest is Test {
    TokenLexscrowFactory internal factoryTest;
    address internal receiver;
    uint256 internal constant BASIS_POINTS = 1000;
    uint256 internal constant DAY_IN_SECONDS = 86400;
    uint256 public feeBasisPoints;

    function setUp() public {
        factoryTest = new TokenLexscrowFactory();
        //this address deploys 'factoryTest'
        receiver = address(this);
    }

    function testConstructor() public {
        assertEq(factoryTest.receiver(), receiver, "receiver address mismatch");
    }

    ///
    /// @dev use TokenLexscrow.t.sol for test deployments and fuzz inputs as the factory does not have the conditionals
    ///

    function testUpdateReceiver(address _addr, address _addr2) public {
        bool _reverted;
        // address(this) is calling the test contract so it should be the receiver for the call not to revert
        if (address(this) != factoryTest.receiver()) {
            _reverted = true;
            vm.expectRevert();
        }
        factoryTest.updateReceiver(_addr);
        vm.startPrank(_addr2);
        // make sure wrong address causes revert
        if (_addr != _addr2) {
            vm.expectRevert();
            factoryTest.acceptReceiverRole();
        }
        vm.stopPrank();
        vm.startPrank(_addr);
        factoryTest.acceptReceiverRole();
        if (!_reverted) assertEq(factoryTest.receiver(), _addr, "receiver address did not update");
    }

    function testUpdateFee(address _addr2, bool _feeSwitch, uint256 _newFeeBasisPoints, uint256 _timePassed) public {
        vm.assume(_newFeeBasisPoints < 1e50 && _timePassed < 1e20); // reasonable assumptions
        bool _reverted;
        // address(this) is calling the test contract so it should be the receiver for the call not to revert
        if (address(this) != factoryTest.receiver()) {
            _reverted = true;
            vm.expectRevert();
        }
        factoryTest.updateFee(_feeSwitch, _newFeeBasisPoints);
        vm.startPrank(_addr2);
        // make sure wrong address causes revert
        if (_addr2 != factoryTest.receiver()) {
            vm.expectRevert();
            factoryTest.acceptFeeUpdate();
        }
        vm.stopPrank();
        vm.warp(block.timestamp + _timePassed);
        vm.startPrank(factoryTest.receiver());
        if (_timePassed < DAY_IN_SECONDS) {
            _reverted = true;
            vm.expectRevert();
        }
        factoryTest.acceptFeeUpdate();
        if (!_reverted) {
            assertEq(factoryTest.feeBasisPoints(), _newFeeBasisPoints, "feeBasisPoints did not update");
            assertTrue(factoryTest.feeSwitch() == _feeSwitch, "feeSwitch did not update");
        }
    }

    /// @dev fee calculations mocked as they are internal in the contract

    function testFeeCalculation(bool _feeSwitch, uint256 _feeBasisPoints, uint256 _totalAmount) public {
        vm.assume(_feeBasisPoints < 1e10 && _totalAmount < 1e50); // reasonable assumptions as no rational user would accept such fees
        feeBasisPoints = _feeBasisPoints;
        uint256 _fee;
        uint256 _calculated = _calculateFee(_totalAmount);
        if (_feeSwitch) {
            _fee = _calculateFee(_totalAmount);
            assertEq(_calculated, _fee, "fee not properly calculated");
        } else assertEq(_fee, 0, "fee switch is off so fee should be 0");
    }

    /// @notice calculates the fees that should be added to the LeXscrow's `_totalAmount`
    /// @param _totalAmount amount used in this LeXscrow, upon which the fee will be calculated
    function _calculateFee(uint256 _totalAmount) internal view returns (uint256) {
        return _mulDiv(_totalAmount, feeBasisPoints, BASIS_POINTS);
    }

    /// @dev Calculates x * y / denominator with full precision, following the selected rounding direction
    /// uses OpenZeppelin's mulDiv (license: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.5/LICENSE),
    /// see https://github.com/OpenZeppelin/openzeppelin-contracts/blob/bd325d56b4c62c9c5c1aff048c37c6bb18ac0290/contracts/utils/math/Math.sol#L55
    /// Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv), with further edits by Uniswap Labs also under MIT license.
    function _mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1, "Math: mulDiv overflow");

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
            // See https://cs.stackexchange.com/q/138556/92363.

            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }
}
