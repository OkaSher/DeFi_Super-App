// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracle {
    error StalePrice();
    error ZeroAddress();
    error InvalidPrice();

    function getAssetPrice(address asset) external view returns (uint256);
}
