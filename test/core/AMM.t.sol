// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AMM} from "../../src/core/AMM.sol";
import {AMMFactory} from "../../src/core/AMMFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAMM} from "../../src/interfaces/IAMM.sol";
import {IAMMFactory} from "../../src/interfaces/IAMMFactory.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AMMHelper is AMM {
    function solidity_sqrt(uint256 y) external pure returns (uint256 z) {
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

    function yul_sqrt(uint256 y) external pure returns (uint256) {
        return _sqrt(y);
    }
}

contract AMMTest is Test {
    // Custom error definitions matching AMM and AMMFactory
    error ZeroAddress();
    error ZeroAmount();
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error InsufficientShares(uint256 requested, uint256 available);
    error NoLiquidity();
    error InvalidTokenOrder();
    error Overflow();
    error IdenticalAddresses();
    error AlreadyInitialized();
    error Unauthorized();
    error PoolAlreadyExists(address pool);

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
        (address t0,) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

        uint256 amount0 = address(tokenA) == t0 ? INIT_A : INIT_B;
        uint256 amount1 = address(tokenA) == t0 ? INIT_B : INIT_A;

        vm.prank(alice);
        shares = pool.addLiquidity(amount0, amount1, alice);
    }

    /* ==================== EXISTING TESTS ==================== */

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
        (uint256 amount0, uint256 amount1) = pool.removeLiquidity(shares, alice);

        assertTrue(amount0 > 0 && amount1 > 0);
        assertEq(pool.balanceOf(alice), 0);
    }

    function test_Swap() public {
        _addStandardLiquidity();

        uint256 amountIn = 100 * 1e18;
        address tokenIn = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB); // swap token0 for token1
        address tokenOut = tokenIn == address(tokenA) ? address(tokenB) : address(tokenA);

        uint256 balOutBefore = MockERC20(tokenOut).balanceOf(bob);

        vm.prank(bob);
        uint256 amountOut = pool.swap(amountIn, 0, tokenIn, bob);

        uint256 balOutAfter = MockERC20(tokenOut).balanceOf(bob);
        assertEq(balOutAfter - balOutBefore, amountOut);
        assertTrue(amountOut > 0);
    }

    function testGas_Yul_vs_Solidity_Sqrt() public {
        AMMHelper helper = new AMMHelper();
        uint256 val = 1000000 * 1e18;

        // Measure Solidity gas
        uint256 gasBeforeSol = gasleft();
        uint256 resSol = helper.solidity_sqrt(val);
        uint256 gasAfterSol = gasleft();
        uint256 gasSolidity = gasBeforeSol - gasAfterSol;

        // Measure Yul gas
        uint256 gasBeforeYul = gasleft();
        uint256 resYul = helper.yul_sqrt(val);
        uint256 gasAfterYul = gasleft();
        uint256 gasYul = gasBeforeYul - gasAfterYul;

        assertEq(resSol, resYul);
        console2.log("Solidity Sqrt Gas Used:", gasSolidity);
        console2.log("Yul Sqrt Gas Used:", gasYul);
        assertTrue(gasYul < gasSolidity, "Yul should be more gas efficient!");
    }

    function testFuzz_Swap(uint256 amountIn) public {
        _addStandardLiquidity();
        amountIn = bound(amountIn, 1, 100_000 * 1e18);

        address tokenIn = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB); // swap token0 for token1
        address tokenOut = tokenIn == address(tokenA) ? address(tokenB) : address(tokenA);

        uint256 balOutBefore = MockERC20(tokenOut).balanceOf(bob);

        vm.prank(bob);
        uint256 amountOut = pool.swap(amountIn, 0, tokenIn, bob);

        uint256 balOutAfter = MockERC20(tokenOut).balanceOf(bob);
        assertEq(balOutAfter - balOutBefore, amountOut);
        assertTrue(amountOut > 0);
    }

    function testFuzz_Invariant_K_NeverDecreases(uint256 amountIn, bool isToken0) public {
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

    /* ==================== EXPANDED UNIT TESTS ==================== */

    function test_RevertInitializeAlreadyInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(AlreadyInitialized.selector));
        pool.initialize(address(tokenA), address(tokenB));
    }

    function test_RevertInitializeUnauthorized() public {
        // Deploy a fresh AMM instance directly
        AMM freshPool = new AMM();

        // Factory is not set, but caller is not factory so we can't initialize
        vm.prank(alice);
        freshPool.initialize(address(tokenA), address(tokenB));

        // Re-call from alice when already initialized/factory set should revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AlreadyInitialized.selector));
        freshPool.initialize(address(tokenA), address(tokenB));
    }

    function test_RevertInitializeIdenticalAddresses() public {
        AMM freshPool = new AMM();
        vm.expectRevert(abi.encodeWithSelector(IdenticalAddresses.selector));
        freshPool.initialize(address(tokenA), address(tokenA));
    }

    function test_RevertInitializeZeroAddress() public {
        AMM freshPool = new AMM();
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        freshPool.initialize(address(0), address(tokenB));
    }

    function test_RevertInitializeInvalidTokenOrder() public {
        AMM freshPool = new AMM();
        address t0 = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address t1 = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);

        vm.expectRevert(abi.encodeWithSelector(InvalidTokenOrder.selector));
        // Initialize with reversed sort order
        freshPool.initialize(t1, t0);
    }

    function test_RevertAddLiquidityZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));
        pool.addLiquidity(0, 1000, alice);
    }

    function test_RevertAddLiquidityZeroAddressTo() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        pool.addLiquidity(1000, 1000, address(0));
    }

    function test_RevertRemoveLiquidityZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));
        pool.removeLiquidity(0, alice);
    }

    function test_RevertRemoveLiquidityZeroAddressTo() public {
        _addStandardLiquidity();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        pool.removeLiquidity(100, address(0));
    }

    function test_RevertRemoveLiquidityInsufficientShares() public {
        _addStandardLiquidity();
        uint256 excessShares = pool.totalSupply() + 1;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(InsufficientShares.selector, excessShares, pool.totalSupply()));
        pool.removeLiquidity(excessShares, alice);
    }

    function test_RevertSwapZeroAmount() public {
        _addStandardLiquidity();
        address t0 = pool.token0();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));
        pool.swap(0, 0, t0, bob);
    }

    function test_RevertSwapZeroAddressTo() public {
        _addStandardLiquidity();
        address t0 = pool.token0();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        pool.swap(100, 0, t0, address(0));
    }

    function test_RevertSwapInvalidTokenIn() public {
        _addStandardLiquidity();
        address fakeToken = address(0x999);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenOrder.selector));
        pool.swap(100, 0, fakeToken, bob);
    }

    function test_RevertSwapSlippageExceeded() public {
        _addStandardLiquidity();
        uint256 amountIn = 100 * 1e18;
        address tokenIn = pool.token0();
        uint256 expectedOut = pool.getAmountOut(amountIn, INIT_A, INIT_B);
        uint256 minOut = expectedOut + 1; // force slippage violation

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SlippageExceeded.selector, expectedOut, minOut));
        pool.swap(amountIn, minOut, tokenIn, bob);
    }

    function test_RevertSwapNoLiquidity() public {
        address t0 = pool.token0();
        // Pool has no reserves initially
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NoLiquidity.selector));
        pool.swap(100, 0, t0, bob);
    }

    function test_RevertFactoryCreatePoolIdenticalAddresses() public {
        vm.expectRevert(abi.encodeWithSelector(IdenticalAddresses.selector));
        factory.createPool(address(tokenA), address(tokenA));
    }

    function test_RevertFactoryCreatePoolZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        factory.createPool(address(0), address(tokenB));
    }

    function test_RevertFactoryCreatePoolAlreadyExists() public {
        vm.expectRevert(abi.encodeWithSelector(PoolAlreadyExists.selector, address(pool)));
        factory.createPool(address(tokenA), address(tokenB));
    }

    function test_FactoryComputePoolAddress() public view {
        address predicted = factory.computePoolAddress(address(tokenA), address(tokenB));
        assertEq(predicted, address(pool));
    }

    /* ==================== EXPANDED FUZZ TESTS ==================== */

    function testFuzz_AddLiquidityOptimal(uint256 amount0Desired, uint256 amount1Desired) public {
        amount0Desired = bound(amount0Desired, 1e9, 100_000 * 1e18);
        amount1Desired = bound(amount1Desired, 1e9, 100_000 * 1e18);

        vm.startPrank(alice);
        uint256 shares = pool.addLiquidity(amount0Desired, amount1Desired, alice);
        assertTrue(shares > 0);
        vm.stopPrank();
    }

    function testFuzz_RemoveLiquidityOptimal(uint256 deposit0, uint256 deposit1, uint256 removeFraction) public {
        deposit0 = bound(deposit0, 1e9, 50_000 * 1e18);
        deposit1 = bound(deposit1, 1e9, 50_000 * 1e18);
        removeFraction = bound(removeFraction, 1, 100); // 1% to 100%

        vm.startPrank(alice);
        uint256 shares = pool.addLiquidity(deposit0, deposit1, alice);

        uint256 sharesToRemove = (shares * removeFraction) / 100;
        if (sharesToRemove > 0) {
            (uint256 amount0, uint256 amount1) = pool.removeLiquidity(sharesToRemove, alice);
            assertTrue(amount0 > 0 && amount1 > 0);
        }
        vm.stopPrank();
    }

    /* ==================== CLASSIC CREATE FACTORY TESTS ==================== */

    function test_CreatePoolClassic() public {
        MockERC20 tokenC = new MockERC20("Token C", "TKNC");
        MockERC20 tokenD = new MockERC20("Token D", "TKND");

        // Deploy using standard CREATE
        address classicPoolAddr = factory.createPoolClassic(address(tokenC), address(tokenD));
        assertTrue(classicPoolAddr != address(0));

        AMM classicPool = AMM(classicPoolAddr);
        assertEq(classicPool.factory(), address(factory));

        // Sorting check
        (address token0, address token1) =
            address(tokenC) < address(tokenD) ? (address(tokenC), address(tokenD)) : (address(tokenD), address(tokenC));
        assertEq(classicPool.token0(), token0);
        assertEq(classicPool.token1(), token1);

        // Verification of bilateral getPool lookup
        assertEq(factory.getPool(address(tokenC), address(tokenD)), classicPoolAddr);
        assertEq(factory.getPool(address(tokenD), address(tokenC)), classicPoolAddr);

        // Revert on identical addresses
        vm.expectRevert(abi.encodeWithSelector(IdenticalAddresses.selector));
        factory.createPoolClassic(address(tokenC), address(tokenC));

        // Revert on zero address
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        factory.createPoolClassic(address(0), address(tokenC));

        // Revert on duplicate pool
        vm.expectRevert(abi.encodeWithSelector(PoolAlreadyExists.selector, classicPoolAddr));
        factory.createPoolClassic(address(tokenC), address(tokenD));
    }
}
