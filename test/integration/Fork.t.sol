// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Router {
    function factory() external view returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract ForkTest is Test {
    string public constant MAINNET_RPC_URL = "https://ethereum-rpc.publicnode.com";
    uint256 public mainnetFork;

    // Mainnet addresses
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function setUp() public {
        // Create and select fork of Ethereum Mainnet
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL);
    }

    /**
     * @notice Test 1: Query and interact with real Mainnet USDC contract
     */
    function testFork_RealUSDCToken() public view {
        IERC20 usdcToken = IERC20(USDC);

        // Query symbol & decimals
        uint8 decimals = 6;
        string memory expectedSymbol = "USDC";

        // Read real USDC decimals from mainnet
        // USDC uses custom decimals of 6
        (bool success, bytes memory data) = USDC.staticcall(abi.encodeWithSignature("decimals()"));
        assertTrue(success, "decimals call failed");
        uint8 usdcDecimals = abi.decode(data, (uint8));
        assertEq(usdcDecimals, decimals, "USDC decimals mismatch");

        (bool success2, bytes memory data2) = USDC.staticcall(abi.encodeWithSignature("symbol()"));
        assertTrue(success2, "symbol call failed");
        string memory usdcSymbol = abi.decode(data2, (string));
        assertEq(usdcSymbol, expectedSymbol, "USDC symbol mismatch");

        // Verify total supply is positive
        uint256 totalSupply = usdcToken.totalSupply();
        assertTrue(totalSupply > 0, "USDC total supply is zero");
    }

    /**
     * @notice Test 2: Interact with Uniswap V2 Router on Mainnet
     */
    function testFork_UniswapV2Router() public view {
        IUniswapV2Router router = IUniswapV2Router(UNISWAP_V2_ROUTER);

        // Verify factory address matches Uniswap V2 standard factory
        address expectedFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        assertEq(router.factory(), expectedFactory, "Router factory mismatch");

        // Simulate swap path from USDC to WETH
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        // Query price for 1000 USDC ($1000) in WETH
        uint256 amountIn = 1000 * 1e6; // 1000 USDC (6 decimals)

        uint256[] memory amountsOut = router.getAmountsOut(amountIn, path);

        assertTrue(amountsOut.length == 2, "Amounts length mismatch");
        assertTrue(amountsOut[0] == amountIn, "Input amount mismatch");
        assertTrue(amountsOut[1] > 0, "Quote amount is zero");
    }

    /**
     * @notice Test 3: Query real Chainlink price feed on Mainnet
     */
    function testFork_RealChainlinkPriceFeed() public view {
        IChainlinkFeed ethUsdFeed = IChainlinkFeed(CHAINLINK_ETH_USD);

        // Chainlink ETH/USD uses 8 decimals
        assertEq(ethUsdFeed.decimals(), 8, "ETH/USD feed decimals mismatch");

        // Get latest price
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = ethUsdFeed.latestRoundData();

        // Verify validity of Chainlink data
        assertTrue(answer > 0, "Price must be positive");
        assertTrue(roundId > 0, "Round ID is zero");
        assertTrue(updatedAt > 0, "Updated timestamp is zero");
        assertTrue(answeredInRound >= roundId, "Round validation failure");
    }
}
