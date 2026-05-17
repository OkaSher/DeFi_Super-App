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
        // --- Without offset protection (i.e. standard ERC-4626), an attacker does:
        // 1. Attacker (Bob) deposits 1 wei of asset and receives 1 wei of shares.
        // 2. Attacker transfers (donates) 10,000 * 1e18 of assets directly to the vault contract.
        // 3. The price of 1 share is now inflated: 1 share = (10,000 * 1e18 + 1) assets.
        // 4. Victim (Alice) deposits 5,000 * 1e18 assets.
        // 5. Without offset, Alice's shares = 5,000 * 1e18 * 1 / (10,000 * 1e18 + 1) = 0 shares (due to rounding down).
        // 6. Alice gets 0 shares but her 5,000 * 1e18 assets are lost to the vault (shared by existing share holders, i.e. Bob).
        
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
        // Let's make sure Alice can redeem her shares and get her assets back (minus minor precision loss if any, but not stolen).
        vm.prank(alice);
        uint256 aliceAssetsRedeemed = vault.redeem(aliceShares, alice, alice);
        
        // Alice should get almost all of her 5000 * 1e18 assets back.
        // Let's assert that Alice got at least 99.999% of her deposit back.
        assertApproxEqAbs(aliceAssetsRedeemed, 5_000 * 1e18, 1e13);
    }
}
