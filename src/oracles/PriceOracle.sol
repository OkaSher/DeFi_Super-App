// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IOracle} from "../interfaces/IOracle.sol";

/// @title PriceOracle - Chainlink price feed oracle with UUPS upgradeable pattern
/// @notice Provides safe access to Chainlink price feeds with staleness validation
/// @dev Implements UUPSUpgradeable for future upgrades without re-deployment
contract PriceOracle is IOracle, UUPSUpgradeable, OwnableUpgradeable {
    /// @notice Maps token address to its Chainlink price feed aggregator
    mapping(address => address) public priceFeeds;

    /// @notice Maximum allowed age (staleness) for prices in seconds
    uint256 public maxStalenessThreshold;

    uint256[48] private __gap;

    /// @notice Initialize the contract (replaces constructor for upgradeable contracts)
    /// @param owner Address that will own this contract and have admin privileges
    function initialize(address owner) external initializer {
        if (owner == address(0)) revert InvalidFeedAddress();
        __Ownable_init(owner);
        maxStalenessThreshold = 1 days;
    }

    /// @inheritdoc IOracle
    function getLatestPrice(address token)
        external
        view
        returns (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        address aggregatorAddress = _aggregatorFor(token);
        AggregatorV3Interface aggregator = AggregatorV3Interface(aggregatorAddress);

        (roundId, price, startedAt, updatedAt, answeredInRound) = aggregator.latestRoundData();

        if (updatedAt == 0 || startedAt > updatedAt || answeredInRound < roundId) {
            revert NoRoundData();
        }

        validatePriceFreshness(updatedAt, maxStalenessThreshold);
    }

    /// @notice Get the latest price with a custom staleness threshold
    /// @param token The token address to fetch a price for
    /// @param stalenessThreshold Maximum acceptable age of the price in seconds
    /// @return price The latest price (int256 from Chainlink)
    function getPriceWithStalenessCheck(address token, uint256 stalenessThreshold)
        external
        view
        returns (int256 price)
    {
        if (stalenessThreshold == 0) revert InvalidStalenessThreshold();

        address aggregatorAddress = _aggregatorFor(token);
        AggregatorV3Interface aggregator = AggregatorV3Interface(aggregatorAddress);

        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        (roundId, answer, startedAt, updatedAt, answeredInRound) = aggregator.latestRoundData();

        if (updatedAt == 0 || startedAt > updatedAt || answeredInRound < roundId) {
            revert NoRoundData();
        }

        validatePriceFreshness(updatedAt, stalenessThreshold);

        return answer;
    }

    /// @inheritdoc IOracle
    function validatePriceFreshness(uint256 updatedAt, uint256 maxAge) public view {
        if (maxAge == 0) revert InvalidStalenessThreshold();
        if (updatedAt == 0) revert NoRoundData();

        uint256 age = block.timestamp - updatedAt;
        if (age > maxAge) revert PriceStale(age, maxAge);
    }

    /// @notice Set or update the Chainlink price feed for a token
    /// @param token The token address to set the feed for
    /// @param feed The Chainlink aggregator contract address
    function setPriceFeed(address token, address feed) external onlyOwner {
        if (token == address(0) || feed == address(0)) revert InvalidFeedAddress();

        priceFeeds[token] = feed;

        uint80 roundId;
        int256 price;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        (roundId, price, startedAt, updatedAt, answeredInRound) =
            AggregatorV3Interface(feed).latestRoundData();

        if (updatedAt == 0 || startedAt > updatedAt || answeredInRound < roundId) {
            revert NoRoundData();
        }

        emit PriceFeedSet(token, feed);
        emit PriceUpdated(token, price, updatedAt);
    }

    /// @notice Update the maximum staleness threshold used by `getLatestPrice`
    /// @param threshold The new max staleness threshold in seconds
    function setMaxStalenessThreshold(uint256 threshold) external onlyOwner {
        if (threshold == 0) revert InvalidStalenessThreshold();
        maxStalenessThreshold = threshold;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _aggregatorFor(address token) internal view returns (address aggregatorAddress) {
        if (token == address(0)) revert InvalidFeedAddress();
        aggregatorAddress = priceFeeds[token];
        if (aggregatorAddress == address(0)) revert InvalidFeedAddress();
    }
}

/// @dev Interface for Chainlink AggregatorV3
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
