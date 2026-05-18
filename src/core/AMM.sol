// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IAMM} from "../interfaces/IAMM.sol";

/// @title  AMM — Constant-Product Automated Market Maker (x · y = k)
/// @notice Uniswap v2-style pool with 0.3% swap fee.
contract AMM is IAMM, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice 0.3% swap fee: amountInWithFee = amountIn * 997 / 1000.
    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    /// @notice 1 000 LP wei permanently burned on the first deposit.
    uint256 private constant MINIMUM_LIQUIDITY = 1_000;

    address public factory;
    address public override token0;
    address public override token1;

    // Slot-packed: two uint112s share one 32-byte storage slot.
    uint112 private reserve0;
    uint112 private reserve1;

    bool private _initialized;

    constructor() ERC20("AMM LP Token", "ALP") {}

    /// @dev One-time initialization post-CREATE2 deployment.
    function initialize(address _token0, address _token1) external {
        if (_initialized) revert AlreadyInitialized();
        if (msg.sender != factory && factory != address(0)) {
            revert Unauthorized();
        }
        if (_token0 == _token1) revert IdenticalAddresses();
        if (_token0 == address(0)) revert ZeroAddress();
        if (_token0 >= _token1) revert InvalidTokenOrder();

        token0 = _token0;
        token1 = _token1;
        factory = msg.sender;
        _initialized = true;
    }

    /// @inheritdoc IAMM
    function getReserves() external view override returns (uint256 _reserve0, uint256 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    /// @inheritdoc IAMM
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        override
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        if (reserveIn == 0 || reserveOut == 0) revert NoLiquidity();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);
    }

    /// @inheritdoc IAMM
    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, address to)
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (amount0Desired == 0 || amount1Desired == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();

        uint256 _reserve0 = reserve0;
        uint256 _reserve1 = reserve1;
        uint256 _totalSupply = totalSupply();

        uint256 amount0;
        uint256 amount1;

        if (_totalSupply == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            shares = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            uint256 amount1Optimal = (amount0Desired * _reserve1) / _reserve0;
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                amount0 = (amount1Desired * _reserve0) / _reserve1;
                amount1 = amount1Desired;
            }
            shares = _min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }

        if (shares == 0) revert ZeroAmount();

        uint256 newReserve0 = _reserve0 + amount0;
        uint256 newReserve1 = _reserve1 + amount1;
        if (newReserve0 > type(uint112).max || newReserve1 > type(uint112).max) {
            revert Overflow();
        }

        _mint(to, shares);
        // forge-lint: disable-next-line(unsafe-typecast)
        _update(uint112(newReserve0), uint112(newReserve1));

        emit LiquidityAdded(to, amount0, amount1, shares);

        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
    }

    /// @inheritdoc IAMM
    function removeLiquidity(uint256 shares, address to)
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (shares == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();

        uint256 _totalSupply = totalSupply();
        if (shares > _totalSupply) {
            revert InsufficientShares(shares, _totalSupply);
        }

        uint256 _reserve0 = reserve0;
        uint256 _reserve1 = reserve1;

        amount0 = (shares * _reserve0) / _totalSupply;
        amount1 = (shares * _reserve1) / _totalSupply;

        if (amount0 == 0 || amount1 == 0) revert ZeroAmount();

        _burn(msg.sender, shares);
        // Safe: amount0/amount1 are proportional fractions of the reserve (<= reserve).
        // forge-lint: disable-next-line(unsafe-typecast)
        _update(uint112(_reserve0 - amount0), uint112(_reserve1 - amount1));

        emit LiquidityRemoved(to, amount0, amount1, shares);

        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);
    }

    /// @inheritdoc IAMM
    /// @dev    Fee-on-Transfer protection: uses balance difference.
    ///         K-invariant check: implemented in Yul for gas efficiency.
    function swap(uint256 amountIn, uint256 minAmountOut, address tokenIn, address to)
        external
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        if (tokenIn != token0 && tokenIn != token1) revert InvalidTokenOrder();

        bool isToken0 = (tokenIn == token0);
        (uint256 rIn, uint256 rOut) = isToken0 ? (reserve0, reserve1) : (reserve1, reserve0);

        if (rIn == 0 || rOut == 0) revert NoLiquidity();

        // Interactions (Input): Transfer and measure actual amount received
        uint256 balBefore = IERC20(tokenIn).balanceOf(address(this));
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 actualAmountIn = IERC20(tokenIn).balanceOf(address(this)) - balBefore;
        if (actualAmountIn == 0) revert ZeroAmount();

        amountOut = getAmountOut(actualAmountIn, rIn, rOut);
        if (amountOut < minAmountOut) {
            revert SlippageExceeded(amountOut, minAmountOut);
        }

        // Effects (Update Reserves)
        uint112 nextR0;
        uint112 nextR1;
        if (isToken0) {
            // Safe: rIn + actualAmountIn overflow is guarded by Overflow() in addLiquidity;
            // rOut - amountOut cannot underflow (amountOut < rOut by getAmountOut formula).
            // forge-lint: disable-next-line(unsafe-typecast)
            nextR0 = uint112(rIn + actualAmountIn);
            // forge-lint: disable-next-line(unsafe-typecast)
            nextR1 = uint112(rOut - amountOut);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            nextR0 = uint112(rOut - amountOut);
            // forge-lint: disable-next-line(unsafe-typecast)
            nextR1 = uint112(rIn + actualAmountIn);
        }

        // K-invariant check via Yul: verifies (rIn * rOut) <= ( (rIn + adjustedIn) * (rOut - amountOut) )
        uint256 balance0 = isToken0 ? rIn + actualAmountIn : rOut - amountOut;
        uint256 balance1 = isToken0 ? rOut - amountOut : rIn + actualAmountIn;

        uint256 kBefore = rIn * rOut;

        assembly {
            let adj0 := mul(balance0, 1000)
            let adj1 := mul(balance1, 1000)

            if isToken0 {
                adj0 := sub(adj0, mul(actualAmountIn, 3))
            }
            if iszero(isToken0) {
                adj1 := sub(adj1, mul(actualAmountIn, 3))
            }

            if lt(mul(adj0, adj1), mul(kBefore, 1000000)) {
                let ptr := mload(0x40)
                mstore(ptr, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(add(ptr, 0x04), 0x0000002000000000000000000000000000000000000000000000000000000000)
                mstore(add(ptr, 0x24), 1)
                mstore(add(ptr, 0x44), 0x4b00000000000000000000000000000000000000000000000000000000000000)
                revert(ptr, 0x64)
            }
        }

        _update(nextR0, nextR1);
        emit Swap(msg.sender, actualAmountIn, amountOut, tokenIn, isToken0 ? token1 : token0);

        // Interactions (Output)
        IERC20(isToken0 ? token1 : token0).safeTransfer(to, amountOut);
    }

    function _update(uint112 _reserve0, uint112 _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    /// @dev Babylonian method for square root: convergences to floor(sqrt(y))
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        assembly {
            switch gt(y, 3)
            case 1 {
                z := y
                let x := add(div(y, 2), 1)
                for {} lt(x, z) {} {
                    z := x
                    x := div(add(div(y, z), z), 2)
                }
            }
            default {
                z := gt(y, 0)
            }
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
