// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {PriceOracleV2} from "../../src/oracles/PriceOracleV2.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PriceOracleTest is Test {
    // Custom error definitions matching contract
    error StalePrice();
    error ZeroAddress();
    error InvalidPrice();
    error OwnableUnauthorizedAccount(address account);

    PriceOracle public oracleImpl;
    PriceOracle public oracle;
    MockV3Aggregator public wethFeed;
    MockV3Aggregator public usdtFeed;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public weth = makeAddr("weth");
    address public usdt = makeAddr("usdt");

    uint256 public constant STALENESS_THRESHOLD = 3600; // 1 hour

    function setUp() public {
        // Deploy implementation
        oracleImpl = new PriceOracle();

        // Encode initialisation data
        bytes memory initData = abi.encodeWithSelector(PriceOracle.initialize.selector, STALENESS_THRESHOLD, owner);

        // Deploy UUPS proxy pointing to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(address(oracleImpl), initData);
        oracle = PriceOracle(address(proxy));

        // Deploy Mock Chainlink Aggregators
        // WETH feed has 8 decimals (standard Chainlink ETH/USD), WETH is $3000
        wethFeed = new MockV3Aggregator(8, 3000 * 1e8);
        // USDT feed has 18 decimals, USDT is $1
        usdtFeed = new MockV3Aggregator(18, 1 * 1e18);

        // Configure feeds in Oracle
        vm.startPrank(owner);
        oracle.setPriceFeed(weth, address(wethFeed));
        oracle.setPriceFeed(usdt, address(usdtFeed));
        vm.stopPrank();
    }

    function test_Initialization() public view {
        assertEq(oracle.owner(), owner);
        assertEq(oracle.stalenessThreshold(), STALENESS_THRESHOLD);
    }

    function test_DoubleInitializationReverts() public {
        vm.expectRevert();
        oracle.initialize(1800, alice);
    }

    function test_GetPriceNormalizationWeth() public view {
        // Price should be scaled from 8 decimals to 18 decimals
        uint256 price = oracle.getAssetPrice(weth);
        assertEq(price, 3000 * 1e18);
    }

    function test_GetPriceNormalizationUsdt() public view {
        // Price should remain 18 decimals
        uint256 price = oracle.getAssetPrice(usdt);
        assertEq(price, 1 * 1e18);
    }

    function test_RevertGetPriceUnconfiguredAsset() public {
        address unconfigured = makeAddr("fake");
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        oracle.getAssetPrice(unconfigured);
    }

    function test_SetPriceFeedOwnerOnly() public {
        address token = makeAddr("token");
        address feed = makeAddr("feed");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        oracle.setPriceFeed(token, feed);
    }

    function test_SetStalenessThresholdOwnerOnly() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        oracle.setStalenessThreshold(1800);
    }

    function test_UpdateStalenessThreshold() public {
        vm.prank(owner);
        oracle.setStalenessThreshold(1800);
        assertEq(oracle.stalenessThreshold(), 1800);
    }

    function test_RevertStalePrice() public {
        // Warp block time past the threshold
        vm.warp(block.timestamp + STALENESS_THRESHOLD + 10);

        vm.expectRevert(abi.encodeWithSelector(StalePrice.selector));
        oracle.getAssetPrice(weth);
    }

    function test_RevertInvalidAnswer() public {
        // Update price to 0
        wethFeed.updateAnswer(0);

        vm.expectRevert(abi.encodeWithSelector(InvalidPrice.selector));
        oracle.getAssetPrice(weth);
    }

    function test_RevertNegativeAnswer() public {
        // Update price to negative
        wethFeed.updateAnswer(-100);

        vm.expectRevert(abi.encodeWithSelector(InvalidPrice.selector));
        oracle.getAssetPrice(weth);
    }

    function test_UUPSUpgradeLifecycle() public {
        // Deploy new V2 implementation
        PriceOracleV2 v2Impl = new PriceOracleV2();

        // Non-owner should not be able to upgrade
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice));
        oracle.upgradeToAndCall(address(v2Impl), "");

        // Owner upgrades the proxy to V2
        vm.prank(owner);
        oracle.upgradeToAndCall(address(v2Impl), "");

        // Cast proxy address to V2 type
        PriceOracleV2 oracleV2 = PriceOracleV2(address(oracle));

        // Verify version function is available
        assertEq(oracleV2.version(), "V2");

        // Verify state is preserved
        assertEq(oracleV2.owner(), owner);
        assertEq(oracleV2.stalenessThreshold(), STALENESS_THRESHOLD);
        assertEq(oracleV2.getAssetPrice(weth), 3000 * 1e18);
    }
}
