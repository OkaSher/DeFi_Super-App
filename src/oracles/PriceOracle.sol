// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IOracle.sol";

/// @title PriceOracle - Chainlink price feed oracle with UUPS upgradeable pattern
/// @notice Provides safe access to Chainlink price feeds with staleness validation
/// @dev Implements UUPSUpgradeable for future upgrades without re-deployment
contract PriceOracle is IOracle, UUPSUpgradeable, OwnableUpgradeable {
    // ============ Storage ============
    /// @notice Maps token address to its Chainlink price feed aggregator
    mapping(address => address) public priceFeeds;

    /// @notice Maximum allowed age (staleness) for prices in seconds
    uint256 public maxStalenessThreshold;

    // Storage gap for future upgrades (as per OpenZeppelin upgradeability patterns)
    uint256[48] private __gap;

    // ============ Events ============
    /// @notice Emitted when a price feed is set or updated
    event PriceFeedSet(address indexed token, address indexed feed);

    /// @notice Emitted when max staleness threshold is updated
    event MaxStalenessThresholdUpdated(uint256 newThreshold);

    // ============ Initialization ============

    /// @notice Initialize the contract (replaces constructor for upgradeable contracts)
    /// @param _owner Address that will own this contract and have admin privileges
    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert InvalidFeedAddress();
        __Ownable_init(_owner);
        // Default: 1 day staleness threshold
        maxStalenessThreshold = 1 days;
    }

    // ============ Price Feed Access ============

    /// @notice Get the latest price from a Chainlink aggregator with staleness check
    /// @param feed The address of the Chainlink price feed (token to get price for)
    /// @return roundId The round ID
    /// @return price The latest price answer
    /// @return startedAt Timestamp when the round started
    /// @return updatedAt Timestamp when the price was last updated
    /// @return answeredInRound The round ID when the answer was computed
    function getLatestPrice(address feed)
        external
        view
        returns (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (feed == address(0)) revert InvalidFeedAddress();

        address aggregatorAddress = priceFeeds[feed];
        if (aggregatorAddress == address(0)) revert InvalidFeedAddress();

        AggregatorV3Interface aggregator = AggregatorV3Interface(aggregatorAddress);
        (roundId, price, startedAt, updatedAt, answeredInRound) = aggregator.latestRoundData();

        if (updatedAt == 0) revert NoRoundData();
    }

    /// @notice Get the latest price with mandatory staleness check
    /// @param feed The address of the token to fetch price for
    /// @param stalenessThreshold Maximum acceptable age of the price in seconds
    /// @return price The latest price (int256 from Chainlink)
    /// @dev Reverts if price is older than stalenessThreshold
    function getPriceWithStalenessCheck(address feed, uint256 stalenessThreshold)
        external
        view
        returns (int256 price)
    {
        if (feed == address(0)) revert InvalidFeedAddress();

        address aggregatorAddress = priceFeeds[feed];
        if (aggregatorAddress == address(0)) revert InvalidFeedAddress();

        AggregatorV3Interface aggregator = AggregatorV3Interface(aggregatorAddress);
        (, int256 answer, , uint256 updatedAt, ) = aggregator.latestRoundData();

        if (updatedAt == 0) revert NoRoundData();

        // Validate staleness
        validatePriceFreshness(updatedAt, stalenessThreshold);

        return answer;
    }

    // ============ Staleness Validation ============

    /// @notice Validate that a price is not stale
    /// @param updatedAt The timestamp when the price was last updated
    /// @param maxAge The maximum acceptable age of the price in seconds
    /// @dev Reverts with PriceStale if (block.timestamp - updatedAt) > maxAge
    function validatePriceFreshness(uint256 updatedAt, uint256 maxAge) public view {
        if (updatedAt == 0) revert NoRoundData();

        uint256 age = block.timestamp - updatedAt;
        if (age > maxAge) revert PriceStale(age, maxAge);
    }

    // ============ Admin Functions ============

    /// @notice Set or update the Chainlink price feed for a token
    /// @param token The token address to set the feed for
    /// @param feed The Chainlink aggregator contract address
    function setPriceFeed(address token, address feed) external onlyOwner {
        if (token == address(0)) revert InvalidFeedAddress();
        if (feed == address(0)) revert InvalidFeedAddress();

        priceFeeds[token] = feed;
        emit PriceFeedSet(token, feed);
    }

    /// @notice Update the maximum staleness threshold for all prices
    /// @param _threshold The new max staleness threshold in seconds
    function setMaxStalenessThreshold(uint256 _threshold) external onlyOwner {
        if (_threshold == 0) revert InvalidFeedAddress();
        maxStalenessThreshold = _threshold;
        emit MaxStalenessThresholdUpdated(_threshold);
    }

    // ============ UUPS Upgrade Authorization ============

    /// @notice Authorize an upgrade to a new implementation
    /// @param newImplementation The address of the new implementation contract
    /// @dev This function is called by the proxy when executing an upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

/// @dev Interface for Chainlink AggregatorV3
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
