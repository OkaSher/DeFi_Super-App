// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {MockAggregatorV3} from "../mocks/MockAggregatorV3.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PriceOracleTest is Test {
    PriceOracle oracle;
    MockAggregatorV3 feed;
    address owner = makeAddr("owner");
    address token = makeAddr("token");

    function setUp() public {
        vm.warp(1_700_000_000);

        PriceOracle impl = new PriceOracle();
        bytes memory initData = abi.encodeCall(PriceOracle.initialize, (owner));
        oracle = PriceOracle(address(new ERC1967Proxy(address(impl), initData)));

        feed = new MockAggregatorV3(2_000e8);

        vm.prank(owner);
        oracle.setPriceFeed(token, address(feed));
    }

    function test_GetLatestPriceReturnsFreshData() public view {
        (,,, uint256 updatedAt,) = oracle.getLatestPrice(token);
        assertGt(updatedAt, 0);
    }

    function test_GetLatestPriceRevertsWhenStale() public {
        feed.setRound(2_100e8, block.timestamp - 2 days);

        vm.expectRevert(
            abi.encodeWithSelector(IOracle.PriceStale.selector, 2 days, 1 days)
        );
        oracle.getLatestPrice(token);
    }

    function test_GetPriceWithStalenessCheckUsesCustomThreshold() public {
        feed.setRound(2_100e8, block.timestamp - 2 hours);

        int256 price = oracle.getPriceWithStalenessCheck(token, 3 hours);
        assertEq(price, 2_100e8);
    }

    function test_SetMaxStalenessThresholdUpdatesDefaultCheck() public {
        vm.prank(owner);
        oracle.setMaxStalenessThreshold(30 minutes);

        feed.setRound(2_200e8, block.timestamp - 45 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(IOracle.PriceStale.selector, 45 minutes, 30 minutes)
        );
        oracle.getLatestPrice(token);
    }

    function test_NonOwnerCannotSetFeed() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        oracle.setPriceFeed(makeAddr("other"), address(feed));
    }

    function test_UpgradeRequiresOwner() public {
        PriceOracle newImpl = new PriceOracle();

        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        oracle.upgradeToAndCall(address(newImpl), "");
    }
}
