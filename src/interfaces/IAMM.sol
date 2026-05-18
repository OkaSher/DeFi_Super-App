// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  IAMM — Interface for the constant-product AMM pool
interface IAMM {
    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 shares);

    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 shares);

    event Swap(
        address indexed sender, uint256 amountIn, uint256 amountOut, address indexed tokenIn, address indexed tokenOut
    );

    error ZeroAddress();
    error ZeroAmount();
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error InsufficientShares(uint256 requested, uint256 available);
    error NoLiquidity();
    error InvalidTokenOrder();
    error Overflow();
    error IdenticalAddresses();
    error AlreadyInitialized();
    error Unauthorized();

    function initialize(address _token0, address _token1) external;

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1);

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, address to) external returns (uint256 shares);

    function removeLiquidity(uint256 shares, address to) external returns (uint256 amount0, uint256 amount1);

    function swap(uint256 amountIn, uint256 minAmountOut, address tokenIn, address to)
        external
        returns (uint256 amountOut);

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut);
}
