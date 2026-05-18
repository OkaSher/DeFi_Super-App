// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AMM} from "../../src/core/AMM.sol";
import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {MockERC20} from "./AMM.t.sol";

contract AMMHandler is Test {
    AMM public pool;
    MockERC20 public token0;
    MockERC20 public token1;

    constructor(AMM _pool, MockERC20 _t0, MockERC20 _t1) {
        pool = _pool;
        token0 = _t0;
        token1 = _t1;

        // Approve infinite tokens from this handler
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        pool.approve(address(pool), type(uint256).max);
    }

    function swap(uint256 amountIn, bool isToken0) public {
        amountIn = bound(amountIn, 1, 100_000 * 1e18);
        address tIn = isToken0 ? address(token0) : address(token1);

        // Mint if handler doesn't have enough balance
        MockERC20(tIn).mint(address(this), amountIn);

        // Perform swap
        try pool.swap(amountIn, 0, tIn, address(this)) returns (uint256) {} catch {}
    }

    function addLiquidity(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 1e9, 50_000 * 1e18);
        amount1 = bound(amount1, 1e9, 50_000 * 1e18);

        token0.mint(address(this), amount0);
        token1.mint(address(this), amount1);

        try pool.addLiquidity(amount0, amount1, address(this)) returns (uint256) {} catch {}
    }

    function removeLiquidity(uint256 shares) public {
        uint256 bal = pool.balanceOf(address(this));
        if (bal == 0) return;
        shares = bound(shares, 1, bal);

        try pool.removeLiquidity(shares, address(this)) returns (uint256, uint256) {} catch {}
    }
}

contract AMMInvariantTest is Test {
    AMMFactory public factory;
    AMM public pool;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public t0;
    MockERC20 public t1;

    AMMHandler public handler;

    function setUp() public {
        factory = new AMMFactory();
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");

        address poolAddr = factory.createPool(address(tokenA), address(tokenB));
        pool = AMM(poolAddr);

        t0 = MockERC20(pool.token0());
        t1 = MockERC20(pool.token1());

        // Setup handler
        handler = new AMMHandler(pool, t0, t1);

        // Add initial liquidity so pool always has some active state
        t0.mint(address(handler), 10_000 * 1e18);
        t1.mint(address(handler), 40_000 * 1e18);
        vm.prank(address(handler));
        pool.addLiquidity(10_000 * 1e18, 40_000 * 1e18, address(handler));

        targetContract(address(handler));
    }

    // Invariant 1: Constant-product per share (relative pool value) never decreases
    function invariant_constantProduct() public view {
        (uint256 r0, uint256 r1) = pool.getReserves();
        uint256 supply = pool.totalSupply();

        // Calculate pool value ratio: (r0 * r1 * 1e18) / supply^2
        // Initial ratio is 1e18. Fees from swaps increase this over time.
        // Liquidity actions keep it exactly constant.
        uint256 currentKPerShare = (r0 * r1 * 1e18) / (supply * supply);

        // Assert it never falls below the initial scale (with 1000 wei allowance for rounding precision)
        assertGe(currentKPerShare, 1e18 - 1000, "K per share decreased!");
    }

    // Invariant 2: Total supply conservation of LP tokens
    function invariant_totalSupplyConservation() public view {
        uint256 expectedSupply = pool.totalSupply();
        uint256 actualSum = pool.balanceOf(address(handler)) + pool.balanceOf(address(0xdead));
        assertEq(expectedSupply, actualSum, "LP supply mismatch!");
    }

    // Invariant 3: Treasury asset accounting matches reserves
    function invariant_treasuryAssetAccounting() public view {
        (uint256 r0, uint256 r1) = pool.getReserves();
        assertEq(t0.balanceOf(address(pool)), r0, "Reserve 0 mismatch!");
        assertEq(t1.balanceOf(address(pool)), r1, "Reserve 1 mismatch!");
    }

    // Invariant 4: Token sort order is strictly preserved
    function invariant_tokenOrder() public view {
        assertTrue(address(t0) < address(t1), "Tokens are not sorted!");
    }

    // Invariant 5: Reserves are strictly non-negative
    function invariant_nonNegativityReserves() public view {
        (uint256 r0, uint256 r1) = pool.getReserves();
        assertTrue(r0 > 0, "Reserve 0 is zero!");
        assertTrue(r1 > 0, "Reserve 1 is zero!");
    }
}
