// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



interface IAMMFactory {

    event PoolCreated(
        address indexed token0,
        address indexed token1,
        address pool,
        uint256 totalPools
    );

    error IdenticalAddresses();
    error ZeroAddress();
    error PoolAlreadyExists(address pool);

    function getPool(
        address tokenA,
        address tokenB
    ) external view returns (address pool);

    function allPoolsLength() external view returns (uint256);

    function allPools(uint256 index) external view returns (address pool);
    function createPool(
        address tokenA,
        address tokenB
    ) external returns (address pool);

    function computePoolAddress(
        address tokenA,
        address tokenB
    ) external view returns (address pool);
}
