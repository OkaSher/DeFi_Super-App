// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IAMM} from "../interfaces/IAMM.sol";

/// @title  AMM — Constant-Product Automated Market Maker (x · y = k)
/// @author DeFi Super-App Team
/// @notice Uniswap v2-style pool with a fixed 0.3% swap fee.
///         The contract is itself an ERC-20 token: LP shares represent
///         proportional ownership of the underlying reserves.
contract AMM is IAMM, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice 0.3% swap fee expressed as a fraction: amountIn * 997 / 1000.
    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    /// @notice 1 000 LP wei permanently burned on the first deposit.
    /// @dev    Prevents the first LP from inflating the share price by
    ///         depositing a trivially small amount and then donating tokens.
    uint256 private constant MINIMUM_LIQUIDITY = 1_000;

    // Matches interface naming convention to ensure override compatibility.
    address public immutable override token0;
    address public immutable override token1;

    // Slot-packed: two uint112s share one 32-byte storage slot to save gas.
    uint112 private reserve0;
    uint112 private reserve1;

    /// @notice Deploy a pool for the (_token0, _token1) pair.
    constructor(address _token0, address _token1) ERC20("AMM LP Token", "ALP") {
        if (_token0 == address(0) || _token1 == address(0))
            revert ZeroAddress();
        if (_token0 >= _token1) revert InvalidTokenOrder();

        token0 = _token0;
        token1 = _token1;
    }

    /// @inheritdoc IAMM
    function getReserves()
        external
        view
        override
        returns (uint256 _reserve0, uint256 _reserve1)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    /// @inheritdoc IAMM
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        address to
    ) external override nonReentrant returns (uint256 shares) {
        // Implementation coming next
    }

    /// @inheritdoc IAMM
    function removeLiquidity(
        uint256 shares,
        address to
    )
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        // Implementation coming next
    }

    /// @inheritdoc IAMM
    function swap(
        uint256 amountIn,
        uint256 minAmountOut,
        address tokenIn,
        address to
    ) external override nonReentrant returns (uint256 amountOut) {
        // Implementation coming next
    }

    /// @inheritdoc IAMM
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure override returns (uint256 amountOut) {
        // Implementation coming next
    }

    /// @dev Write new reserve values to storage.
    function _update(uint112 _reserve0, uint112 _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    /// @dev Integer square root via the Babylonian method: floor(sqrt(y)).
    ///      Used to compute initial LP shares as sqrt(amount0 * amount1),
    ///      matching the Uniswap v2 formula.
    /// @param  y Input value
    /// @return z floor(sqrt(y))
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @dev Returns the smaller of two uint256 values.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
