// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IOracle} from "../interfaces/IOracle.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title PriceOracle
 * @notice UUPS Upgradeable Price Oracle with Chainlink integration and staleness checks.
 */
contract PriceOracle is Initializable, UUPSUpgradeable, OwnableUpgradeable, IOracle {
    // Mapping from asset address (e.g. USDT, WETH) to Chainlink feed address
    mapping(address => address) public priceFeeds;

    // Staleness threshold in seconds (e.g. 3600 seconds = 1 hour)
    uint256 public stalenessThreshold;

    event PriceFeedUpdated(address indexed asset, address indexed feed);
    event StalenessThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializer replacing constructor for UUPS proxy
     */
    function initialize(uint256 _stalenessThreshold, address _owner) external initializer {
        __Ownable_init(_owner);

        if (_stalenessThreshold == 0) revert InvalidPrice();
        stalenessThreshold = _stalenessThreshold;
    }

    /**
     * @notice Sets the Chainlink price feed for a given asset
     * @param asset The address of the asset
     * @param feed The address of the Chainlink AggregatorV3 feed
     */
    function setPriceFeed(address asset, address feed) external onlyOwner {
        if (asset == address(0)) revert ZeroAddress();
        if (feed == address(0)) revert ZeroAddress();
        priceFeeds[asset] = feed;
        emit PriceFeedUpdated(asset, feed);
    }

    /**
     * @notice Updates the staleness threshold
     * @param _stalenessThreshold The new staleness threshold in seconds
     */
    function setStalenessThreshold(uint256 _stalenessThreshold) external onlyOwner {
        if (_stalenessThreshold == 0) revert InvalidPrice();
        emit StalenessThresholdUpdated(stalenessThreshold, _stalenessThreshold);
        stalenessThreshold = _stalenessThreshold;
    }

    /**
     * @notice Fetches the latest price of an asset, with validation and staleness check.
     * @dev Price is scaled to 18 decimals.
     * @param asset The address of the asset
     * @return The latest price, scaled to 18 decimals.
     */
    function getAssetPrice(address asset) external view override returns (uint256) {
        address feed = priceFeeds[asset];
        if (feed == address(0)) revert ZeroAddress();

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0 || answeredInRound < roundId) revert StalePrice();
        if (block.timestamp - updatedAt > stalenessThreshold) revert StalePrice();

        uint8 decimals = priceFeed.decimals();
        uint256 price = uint256(answer);

        // Standardise all prices to 18 decimals
        if (decimals < 18) {
            price = price * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            price = price / (10 ** (decimals - 18));
        }

        return price;
    }

    /**
     * @notice Authorizes upgrades, restricted to owner
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
