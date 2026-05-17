// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IOracle - Interface for price oracle with staleness validation
/// @notice Defines the contract interface for Chainlink price feed integration
interface IOracle {
    /// @notice Emitted when a token is mapped to a Chainlink aggregator
    event PriceFeedSet(address indexed token, address indexed aggregator);

    /// @notice Emitted when a fresh price is read from a configured feed
    event PriceUpdated(address indexed token, int256 price, uint256 timestamp);

    /// @notice Error raised when a price feed is stale (older than maxAge)
    /// @param age Current age of the price in seconds
    /// @param maxAge Maximum allowed age in seconds
    error PriceStale(uint256 age, uint256 maxAge);

    /// @notice Error raised when an invalid address is provided
    error InvalidFeedAddress();

    /// @notice Error raised when a staleness threshold is zero
    error InvalidStalenessThreshold();

    /// @notice Error raised when no round data is available
    error NoRoundData();

    /// @notice Get the latest price for a token using the configured Chainlink feed
    /// @param token The token address whose price feed should be queried
    /// @return roundId The round ID
    /// @return price The latest price
    /// @return startedAt Timestamp when the round started
    /// @return updatedAt Timestamp when the price was last updated
    /// @return answeredInRound The round ID in which the answer was computed
    /// @dev Reverts if the price is older than `maxStalenessThreshold`
    function getLatestPrice(address token)
        external
        view
        returns (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /// @notice Validate that a price is not stale
    /// @param updatedAt The timestamp when the price was last updated
    /// @param maxAge The maximum acceptable age in seconds
    /// @dev Reverts with PriceStale if (block.timestamp - updatedAt) > maxAge
    function validatePriceFreshness(uint256 updatedAt, uint256 maxAge) external view;
}
