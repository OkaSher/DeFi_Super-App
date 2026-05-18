// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../../src/tokens/YieldVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract YieldVaultTest is Test {
    // Standard ERC-6093 and ERC-4626 custom errors declared for expectRevert
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

    MockERC20 public asset;
    YieldVault public vault;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        asset = new MockERC20("Underlying Asset", "USDT");
        vault = new YieldVault(asset, "YieldVault USDT", "yvUSDT");

        // Mint initial assets
        asset.mint(alice, 1_000_000 * 1e18);
        asset.mint(bob, 1_000_000 * 1e18);

        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    /* ==================== EXISTING TESTS ==================== */

    function test_Initialization() public {
        assertEq(vault.name(), "YieldVault USDT");
        assertEq(vault.symbol(), "yvUSDT");
        assertEq(vault.asset(), address(asset));
        // Decimals of asset = 18. Offset = 9. Total decimals = 27.
        assertEq(vault.decimals(), 27);
    }

    function test_DepositAndWithdraw() public {
        uint256 depositAmount = 1000 * 1e18;

        // Alice deposits 1000 assets
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Shares minted should account for the decimals offset of 9
        // convertToShares: assets * (totalSupply + 10**9) / (totalAssets + 1)
        // With 1000 * 1e18 assets, first deposit:
        // shares = 1000 * 1e18 * (0 + 1e9) / (0 + 1) = 1000 * 1e27 shares
        assertEq(shares, depositAmount * 1e9);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), depositAmount);

        // Alice withdraws her shares
        vm.prank(alice);
        uint256 assetsReceived = vault.redeem(shares, alice, alice);

        assertEq(assetsReceived, depositAmount);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_InflationAttackProtection() public {
        // --- With 9 decimals offset protection:
        // 1. Bob (attacker) deposits 1 wei of asset
        vm.prank(bob);
        uint256 bobShares = vault.deposit(1, bob);
        assertEq(bobShares, 1e9); // 1 * 10**9 / 1 = 1e9 shares.

        // 2. Bob directly transfers 10,000 * 1e18 USDT to the vault as a donation
        deal(address(asset), address(vault), asset.balanceOf(address(vault)) + 10_000 * 1e18);

        // 3. Alice deposits 5,000 * 1e18 USDT
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(5_000 * 1e18, alice);

        // Alice's shares must be greater than 0
        assertTrue(aliceShares > 0, "Alice must receive non-zero shares");

        // Check conversion and share ratios
        vm.prank(alice);
        uint256 aliceAssetsRedeemed = vault.redeem(aliceShares, alice, alice);

        // Alice should get almost all of her 5000 * 1e18 assets back.
        // Assert that Alice got at least 99.999% of her deposit back.
        assertApproxEqAbs(aliceAssetsRedeemed, 5_000 * 1e18, 1e13);
    }

    /* ==================== EXPANDED UNIT TESTS ==================== */

    function test_MaxDeposit() public view {
        assertEq(vault.maxDeposit(alice), type(uint256).max);
    }

    function test_MaxMint() public view {
        assertEq(vault.maxMint(alice), type(uint256).max);
    }

    function test_MaxWithdraw() public {
        uint256 amount = 500 * 1e18;
        vm.prank(alice);
        vault.deposit(amount, alice);

        // Max withdraw should equal Alice's converted assets
        uint256 expectedMax = vault.convertToAssets(vault.balanceOf(alice));
        assertEq(vault.maxWithdraw(alice), expectedMax);
        assertEq(vault.maxWithdraw(bob), 0);
    }

    function test_MaxRedeem() public {
        uint256 amount = 500 * 1e18;
        vm.prank(alice);
        vault.deposit(amount, alice);

        assertEq(vault.maxRedeem(alice), vault.balanceOf(alice));
        assertEq(vault.maxRedeem(bob), 0);
    }

    function test_PreviewDeposit() public view {
        uint256 depositAmount = 250 * 1e18;
        uint256 expectedShares = vault.convertToShares(depositAmount);
        assertEq(vault.previewDeposit(depositAmount), expectedShares);
    }

    function test_PreviewMint() public view {
        uint256 sharesAmount = 250 * 1e27;
        uint256 expectedAssets = vault.convertToAssets(sharesAmount);
        assertEq(vault.previewMint(sharesAmount), expectedAssets);
    }

    function test_PreviewWithdraw() public {
        uint256 depositAmount = 1000 * 1e18;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 withdrawAmount = 400 * 1e18;
        // Preview withdraw calculates shares needed to withdraw assets
        // Under standard ERC-4626 implementation, it rounds up
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        assertTrue(expectedShares > 0);
    }

    function test_PreviewRedeem() public {
        uint256 depositAmount = 1000 * 1e18;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 sharesToRedeem = vault.balanceOf(alice) / 2;
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);
        assertTrue(expectedAssets > 0);
    }

    function test_ConvertToShares() public view {
        // assets * 10**9 for empty vault
        assertEq(vault.convertToShares(1e18), 1e27);
        assertEq(vault.convertToShares(0), 0);
    }

    function test_ConvertToAssets() public view {
        // shares / 10**9 for empty vault
        assertEq(vault.convertToAssets(1e27), 1e18);
        assertEq(vault.convertToAssets(0), 0);
    }

    function test_RevertWithdrawExceedsMax() public {
        uint256 depositAmount = 500 * 1e18;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 max = vault.maxWithdraw(alice);
        uint256 overLimit = max + 1;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC4626ExceededMaxWithdraw.selector, alice, overLimit, max));
        vault.withdraw(overLimit, alice, alice);
        vm.stopPrank();
    }

    function test_RevertRedeemExceedsMax() public {
        uint256 depositAmount = 500 * 1e18;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 max = vault.maxRedeem(alice);
        uint256 overLimit = max + 1;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC4626ExceededMaxRedeem.selector, alice, overLimit, max));
        vault.redeem(overLimit, alice, alice);
        vm.stopPrank();
    }

    function test_RevertTransferInsufficientBalance() public {
        uint256 depositAmount = 500 * 1e18;
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, alice, shares, shares + 1));
        vault.transfer(bob, shares + 1);
        vm.stopPrank();
    }

    function test_RevertTransferFromInsufficientAllowance() public {
        uint256 depositAmount = 500 * 1e18;
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Bob tries to transfer alice's shares without approval
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, bob, 0, shares));
        vault.transferFrom(alice, bob, shares);
        vm.stopPrank();
    }

    function test_DepositAndRedeemAll() public {
        uint256 amount = 10_000 * 1e18;

        vm.startPrank(alice);
        uint256 shares = vault.deposit(amount, alice);
        assertEq(vault.balanceOf(alice), shares);

        vault.redeem(shares, alice, alice);
        assertEq(vault.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function test_MintAndWithdrawAll() public {
        uint256 shares = 10_000 * 1e27;
        uint256 assetEquivalent = vault.previewMint(shares);

        vm.startPrank(alice);
        vault.mint(shares, alice);
        assertEq(vault.balanceOf(alice), shares);

        vault.withdraw(assetEquivalent, alice, alice);
        assertEq(vault.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function test_MultipleDepositors() public {
        uint256 aliceDeposit = 1000 * 1e18;
        uint256 bobDeposit = 2000 * 1e18;

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(aliceDeposit, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(bobDeposit, bob);

        assertEq(vault.totalAssets(), aliceDeposit + bobDeposit);
        assertEq(vault.balanceOf(alice), aliceShares);
        assertEq(vault.balanceOf(bob), bobShares);

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);

        assertEq(vault.totalAssets(), 0);
    }

    function test_SharePriceIncreaseOnDonation() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000 * 1e18, alice);

        // Donate assets to the vault directly
        asset.mint(address(vault), 1000 * 1e18);

        // Assets per share has doubled. Alice's 1000 shares are now worth 2000 assets.
        // Minor rounding down of 1 wei due to the 9-decimal offset formula is expected, so we assert approximate equality
        assertEq(vault.totalAssets(), 2000 * 1e18);
        assertApproxEqAbs(vault.convertToAssets(shares), 2000 * 1e18, 10);
    }

    function test_DecimalsOffsetSafety() public view {
        // Vault uses offset of 9
        // Initial conversion should scale assets by 10**9
        uint256 assetAmt = 12345;
        uint256 sharesAmt = vault.convertToShares(assetAmt);
        assertEq(sharesAmt, assetAmt * 1e9);
    }

    function test_AllowanceTracking() public {
        vm.prank(alice);
        vault.approve(bob, 1000);
        assertEq(vault.allowance(alice, bob), 1000);
    }

    function test_VaultApproveAndTransferFrom() public {
        uint256 depositAmount = 500 * 1e18;
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.prank(alice);
        vault.approve(bob, shares);

        vm.prank(bob);
        vault.transferFrom(alice, bob, shares);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), shares);
        assertEq(vault.allowance(alice, bob), 0);
    }

    /* ==================== EXPANDED FUZZ TESTS ==================== */

    function testFuzz_DepositBounds(uint256 amount) public {
        // Bound deposit amount from 1 wei to 10M USDT (1e18 scale)
        amount = bound(amount, 1, 10_000_000 * 1e18);

        // Ensure Alice has enough mock assets to perform the fuzzed deposit
        deal(address(asset), alice, amount);

        vm.startPrank(alice);
        uint256 shares = vault.deposit(amount, alice);
        assertEq(shares, amount * 1e9);
        assertEq(vault.balanceOf(alice), shares);

        uint256 redeemed = vault.redeem(shares, alice, alice);
        assertEq(redeemed, amount);
        vm.stopPrank();
    }

    function testFuzz_WithdrawBounds(uint256 amount) public {
        amount = bound(amount, 1e9, 1_000_000 * 1e18);

        deal(address(asset), alice, amount);

        // Pre-deposit so vault has enough liquidity
        vm.prank(alice);
        vault.deposit(amount, alice);

        uint256 max = vault.maxWithdraw(alice);
        uint256 withdrawAmt = bound(amount / 2, 1, max);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAmt, alice, alice);
        assertTrue(sharesBurned > 0);
    }

    function testFuzz_MintBounds(uint256 shares) public {
        // Bound shares from 1e9 (1 asset) to 10M * 1e27
        shares = bound(shares, 1e9, 10_000_000 * 1e27);

        uint256 assetsNeeded = vault.previewMint(shares);
        deal(address(asset), alice, assetsNeeded);

        vm.startPrank(alice);
        vault.mint(shares, alice);
        assertEq(vault.balanceOf(alice), shares);

        // Use redeem instead of withdraw to respect the standard ERC-4626 rounding-down maxWithdraw limits
        vault.redeem(shares, alice, alice);
        assertEq(vault.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function testFuzz_RedeemBounds(uint256 shares) public {
        // Bound shares to be at least 1e10 so redeemAmt / 2 is >= 5e9 (to prevent rounding to 0 assets)
        shares = bound(shares, 1e10, 1_000_000 * 1e27);

        uint256 assetsNeeded = vault.previewMint(shares);
        deal(address(asset), alice, assetsNeeded);

        vm.startPrank(alice);
        vault.mint(shares, alice);

        uint256 max = vault.maxRedeem(alice);
        uint256 redeemAmt = bound(shares / 2, 1e9, max);

        uint256 assetsReceived = vault.redeem(redeemAmt, alice, alice);
        assertTrue(assetsReceived > 0);
        vm.stopPrank();
    }

    function testFuzz_RoundingDownConvertToShares(uint256 amount) public view {
        amount = bound(amount, 0, 10_000_000 * 1e18);
        uint256 expected = amount * 1e9;
        assertEq(vault.convertToShares(amount), expected);
    }

    function testFuzz_RoundingUpConvertToAssets(uint256 shares) public view {
        shares = bound(shares, 0, 10_000_000 * 1e27);
        uint256 expected = shares / 1e9;
        assertEq(vault.convertToAssets(shares), expected);
    }

    function testFuzz_PreviewDepositEqualsConvertToShares(uint256 amount) public view {
        amount = bound(amount, 1, 10_000_000 * 1e18);
        assertEq(vault.previewDeposit(amount), vault.convertToShares(amount));
    }

    function testFuzz_PreviewMintEqualsConvertToShares(uint256 shares) public view {
        shares = bound(shares, 1e9, 10_000_000 * 1e27);
        uint256 assetsNeeded = vault.previewMint(shares);
        // The difference can be at most 1e9 shares (scale factor) due to rounding in previewMint
        assertApproxEqAbs(vault.convertToShares(assetsNeeded), shares, 1e9);
    }

    function testFuzz_PreviewRedeemEqualsConvertToAssets(uint256 shares) public view {
        shares = bound(shares, 1e9, 10_000_000 * 1e27);
        assertEq(vault.previewRedeem(shares), vault.convertToAssets(shares));
    }
}
