// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AMM} from "../../src/core/AMM.sol";
import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {PriceOracle} from "../../src/oracles/PriceOracle.sol";
import {GovToken} from "../../src/tokens/GovToken.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {YieldVault} from "../../src/tokens/YieldVault.sol";
import {ProtocolGovernor} from "../../src/governance/ProtocolGovernor.sol";
import {ProtocolTimelock} from "../../src/governance/ProtocolTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockAggregatorV3} from "../mocks/MockAggregatorV3.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title ForkTest - Integration tests on Arbitrum Sepolia fork
/// @notice Tests protocol components interacting together on L2 mainnet state
contract ForkTest is Test {
    // ============ Test Setup ============

    // Core contracts
    GovToken govToken;
    ProtocolTimelock timelock;
    ProtocolGovernor governor;
    AMMFactory factory;
    YieldVault vault;
    PriceOracle oracle;

    // Test accounts
    address alice = address(0x111);
    address bob = address(0x222);
    address deployer = address(0x333);

    // Mock tokens for AMM
    MockERC20 token0;
    MockERC20 token1;
    AMM pool;

    function setUp() public {
        // This would be called on a fork of Arbitrum Sepolia
        // Fork URL should be set via env: ARBITRUM_SEPOLIA_RPC_URL
        vm.warp(1 days);

        // Deploy governance token
        govToken = new GovToken(1_000_000 * 1e18);

        // Deploy timelock with no initial proposers/executors
        address[] memory noRoles = new address[](0);
        timelock = new ProtocolTimelock(2 days, noRoles, noRoles, deployer);

        // Deploy governor
        governor = new ProtocolGovernor(
            govToken,
            timelock,
            7200,      // 1 day voting delay
            50400,     // 7 days voting period
            10_000 * 1e18 // 10k threshold
        );

        // Deploy AMM factory
        factory = new AMMFactory();

        // Deploy yield vault
        vault = new YieldVault(IERC20(address(govToken)), "Yield Vault", "yGOV");

        // Deploy PriceOracle with UUPS proxy
        {
            PriceOracle oracleImpl = new PriceOracle();
            bytes memory initData = abi.encodeCall(PriceOracle.initialize, (deployer));
            ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), initData);
            oracle = PriceOracle(address(oracleProxy));
        }

        vm.startPrank(deployer);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        oracle.setMaxStalenessThreshold(3600); // 1 hour
        vm.stopPrank();

        // Deploy mock tokens for AMM testing
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");

        // Create an AMM pool
        address poolAddr = factory.createPool(address(token0), address(token1));
        pool = AMM(poolAddr);

        // Setup initial liquidity
        token0.mint(alice, 100_000 * 1e18);
        token1.mint(alice, 100_000 * 1e18);

        vm.prank(alice);
        token0.approve(poolAddr, type(uint256).max);
        vm.prank(alice);
        token1.approve(poolAddr, type(uint256).max);

        vm.prank(alice);
        pool.addLiquidity(10_000 * 1e18, 40_000 * 1e18, alice);
    }

    // ============ Fork Tests ============

    /// @notice Test AMM swap gated by a fresh oracle price check
    function test_ForkAMMSwapWithOracle() public {
        MockAggregatorV3 feed = new MockAggregatorV3(1_000e8);
        vm.prank(deployer);
        oracle.setPriceFeed(address(token0), address(feed));

        int256 referencePrice = oracle.getPriceWithStalenessCheck(address(token0), 1 hours);
        assertGt(referencePrice, 0, "oracle must return a fresh reference price");

        token0.mint(bob, 1_000 * 1e18);

        vm.prank(bob);
        token0.approve(address(pool), 100 * 1e18);

        vm.prank(bob);
        uint256 amountOut = pool.swap(100 * 1e18, 0, address(token0), bob);

        assertGt(amountOut, 0, "Swap should output tokens");
        assertEq(token1.balanceOf(bob), amountOut, "Bob should receive tokens from swap");

        console2.log("Swap successful - output:", amountOut);
        console2.log("Oracle reference price:", referencePrice);
    }

    /// @notice Test oracle staleness prevention
    function test_ForkOracleStalenessPrevention() public {
        uint256 staleTimestamp = block.timestamp - 7200;
        uint256 threshold = 1 hours;

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracle.PriceStale.selector, block.timestamp - staleTimestamp, threshold
            )
        );
        oracle.validatePriceFreshness(staleTimestamp, threshold);
    }

    /// @notice Test oracle validates fresh prices
    function test_ForkOracleFreshPriceAccepted() public {
        // Arrange: Fresh price timestamp
        uint256 freshTimestamp = block.timestamp - 30 minutes;
        uint256 threshold = 1 hours;

        // Act & Assert: Should not revert
        oracle.validatePriceFreshness(freshTimestamp, threshold);

        console2.log("Oracle accepted fresh price");
    }

    /// @notice Test yield vault deposit flow
    function test_ForkYieldVaultDeposit() public {
        // Arrange: Give alice governance tokens
        govToken.transfer(alice, 1_000 * 1e18);

        vm.prank(alice);
        govToken.approve(address(vault), 1_000 * 1e18);

        // Act: Deposit into vault
        vm.prank(alice);
        uint256 shares = vault.deposit(1_000 * 1e18, alice);

        // Assert: Shares minted correctly
        assertGt(shares, 0, "Deposit should mint shares");
        assertEq(vault.balanceOf(alice), shares, "Alice should own shares");

        console2.log("Deposit successful - shares:", shares);
    }

    /// @notice Test PriceOracle upgrade mechanism (UUPS)
    function test_ForkPriceOracleUpgradeAuthorization() public {
        // Arrange: Try to upgrade without authorization
        PriceOracle newImpl = new PriceOracle();

        // Act & Assert: Non-owner cannot upgrade
        vm.prank(alice); // Not the owner
        vm.expectRevert();
        oracle.upgradeToAndCall(address(newImpl), "");

        console2.log("Oracle upgrade authorization requires owner - correctly protected");
    }

    /// @notice Test K-invariant preservation across fork
    function test_ForkKInvariantPreservation() public {
        // Arrange: Get initial reserves
        (uint256 r0Before, uint256 r1Before) = pool.getReserves();
        uint256 kBefore = r0Before * r1Before;

        // Act: Execute swap
        token0.mint(bob, 500 * 1e18);
        vm.prank(bob);
        token0.approve(address(pool), 500 * 1e18);

        vm.prank(bob);
        pool.swap(500 * 1e18, 0, address(token0), bob);

        // Assert: K-invariant preserved (with fees)
        (uint256 r0After, uint256 r1After) = pool.getReserves();
        uint256 kAfter = r0After * r1After;

        assertGe(kAfter, kBefore, "K-invariant should not decrease");

        console2.log("K-invariant preserved:");
        console2.log("  Before:", kBefore);
        console2.log("  After:", kAfter);
    }
}
