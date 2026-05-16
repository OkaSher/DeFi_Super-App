// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IOracle - Interface for price oracle with staleness validation
/// @notice Defines the contract interface for Chainlink price feed integration
interface IOracle {
    /// @notice Emitted when a price feed is updated for a token
    event PriceUpdated(address indexed feed, int256 price, uint256 timestamp);

    /// @notice Error raised when a price feed is stale (older than maxAge)
    /// @param age Current age of the price in seconds
    /// @param maxAge Maximum allowed age in seconds
    error PriceStale(uint256 age, uint256 maxAge);

    /// @notice Error raised when an invalid feed address is provided
    error InvalidFeedAddress();

    /// @notice Error raised when no round data is available
    error NoRoundData();

    /// @notice Get the latest price from a Chainlink aggregator
    /// @param feed The address of the Chainlink price feed aggregator
    /// @return roundId The round ID
    /// @return price The latest price
    /// @return startedAt Timestamp when the round started
    /// @return updatedAt Timestamp when the price was last updated
    /// @return answeredInRound The round ID in which the answer was computed
    function getLatestPrice(address feed)
        external
        view
        returns (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Validate that a price is not stale
    /// @param updatedAt The timestamp when the price was last updated
    /// @param maxAge The maximum acceptable age of the price in seconds
    /// @dev Reverts with PriceStale if (block.timestamp - updatedAt) > maxAge
    function validatePriceFreshness(uint256 updatedAt, uint256 maxAge) external pure;
}
