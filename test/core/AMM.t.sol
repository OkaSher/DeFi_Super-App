// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AMM} from "../../src/core/AMM.sol";
import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AMMTest is Test {
    AMMFactory public factory;
    AMM public pool;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INIT_A = 10_000 * 1e18;
    uint256 constant INIT_B = 40_000 * 1e18;

    function setUp() public {
        factory = new AMMFactory();

        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");

        tokenA.mint(alice, 1_000_000 * 1e18);
        tokenB.mint(alice, 1_000_000 * 1e18);
        tokenA.mint(bob, 1_000_000 * 1e18);
        tokenB.mint(bob, 1_000_000 * 1e18);

        address poolAddr = factory.createPool(address(tokenA), address(tokenB));
        pool = AMM(poolAddr);

        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function _addStandardLiquidity() internal returns (uint256 shares) {
        (address t0, address t1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        uint256 amount0 = address(tokenA) == t0 ? INIT_A : INIT_B;
        uint256 amount1 = address(tokenA) == t0 ? INIT_B : INIT_A;

        vm.prank(alice);
        shares = pool.addLiquidity(amount0, amount1, alice);
    }

    function test_InitialLiquidityMint() public {
        uint256 shares = _addStandardLiquidity();

        uint256 expectedShares = 20_000 * 1e18 - 1000;
        assertEq(shares, expectedShares);
        assertEq(pool.balanceOf(alice), expectedShares);
        assertEq(pool.balanceOf(address(0xdead)), 1000);
        assertEq(pool.totalSupply(), 20_000 * 1e18);
    }

    function test_GetAmountOut() public {
        _addStandardLiquidity();

        (uint256 res0, uint256 res1) = pool.getReserves();

        uint256 expectedOut = pool.getAmountOut(100 * 1e18, res0, res1);

        uint256 inWithFee = 100 * 1e18 * 997;
        uint256 calcOut = (inWithFee * res1) / (res0 * 1000 + inWithFee);
        assertEq(expectedOut, calcOut);
    }

    function test_RemoveLiquidity() public {
        uint256 shares = _addStandardLiquidity();

        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(
            shares,
            alice
        );

        assertTrue(amount0 > 0 && amount1 > 0);
        assertEq(pool.balanceOf(alice), 0);
    }

    function test_Swap() public {
        _addStandardLiquidity();

        uint256 amountIn = 100 * 1e18;
        address tokenIn = address(tokenA) < address(tokenB)
            ? address(tokenA)
            : address(tokenB); // swap token0 for token1
        address tokenOut = tokenIn == address(tokenA)
            ? address(tokenB)
            : address(tokenA);

        uint256 balOutBefore = MockERC20(tokenOut).balanceOf(bob);

        vm.prank(bob);
        uint256 amountOut = pool.swap(amountIn, 0, tokenIn, bob);

        uint256 balOutAfter = MockERC20(tokenOut).balanceOf(bob);
        assertEq(balOutAfter - balOutBefore, amountOut);
        assertTrue(amountOut > 0);
    }

    function _solidity_sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function testGas_Yul_Benchmark() public {
        uint256 val = 1000000000000000000 ether * 4000 ether;
        uint256 z = _solidity_sqrt(val);
        assertTrue(z > 0);
    }

    function testFuzz_Swap(uint256 amountIn) public {
        _addStandardLiquidity();
        amountIn = bound(amountIn, 1, 100_000 * 1e18);

        address tokenIn = address(tokenA) < address(tokenB)
            ? address(tokenA)
            : address(tokenB); // swap token0 for token1
        address tokenOut = tokenIn == address(tokenA)
            ? address(tokenB)
            : address(tokenA);

        uint256 balOutBefore = MockERC20(tokenOut).balanceOf(bob);

        vm.prank(bob);
        uint256 amountOut = pool.swap(amountIn, 0, tokenIn, bob);

        uint256 balOutAfter = MockERC20(tokenOut).balanceOf(bob);
        assertEq(balOutAfter - balOutBefore, amountOut);
        assertTrue(amountOut > 0);
    }

    function testFuzz_Invariant_K_NeverDecreases(
        uint256 amountIn,
        bool isToken0
    ) public {
        _addStandardLiquidity();
        (uint256 r0Before, uint256 r1Before) = pool.getReserves();

        amountIn = bound(amountIn, 1, 100_000 * 1e18);
        address tokenIn = isToken0 ? pool.token0() : pool.token1();

        vm.prank(bob);
        pool.swap(amountIn, 0, tokenIn, bob);

        (uint256 r0After, uint256 r1After) = pool.getReserves();

        uint256 kBefore = r0Before * r1Before;
        uint256 kAfter = r0After * r1After;

        assertGe(kAfter, kBefore, "Invariant broken: K decreased!");
    }
}
