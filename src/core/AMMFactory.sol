// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IAMMFactory} from "../interfaces/IAMMFactory.sol";
import {AMM} from "./AMM.sol";


contract AMMFactory is IAMMFactory {
    /// @inheritdoc IAMMFactory
    mapping(address => mapping(address => address)) public override getPool;

    /// @dev Ordered list of all pools for off-chain enumeration.
    address[] private _allPools;

    /// @inheritdoc IAMMFactory
    function allPoolsLength() external view override returns (uint256) {
        return _allPools.length;
    }

    /// @inheritdoc IAMMFactory
    function allPools(uint256 index) external view override returns (address) {
        return _allPools[index];
    }

    /// @inheritdoc IAMMFactory
    /// @dev    Normalises token order before salt generation.
    function createPool(
        address tokenA,
        address tokenB
    ) external override returns (address pool) {
        // CHECKS
        if (tokenA == tokenB) revert IdenticalAddresses();
        if (tokenA == address(0)) revert ZeroAddress();

        // Normalise order: token0 is always the lower address.
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        if (getPool[token0][token1] != address(0))
            revert PoolAlreadyExists(getPool[token0][token1]);

        // EFFECTS + INTERACTIONS (deploy)
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        // Deploy with no constructor args so creationCode hash is constant.
        pool = address(new AMM{salt: salt}());

        // Initialize immediately — protected against double-call by _initialized flag.
        AMM(pool).initialize(token0, token1);

        // Store bilaterally so callers don't need to sort before calling getPool.
        getPool[token0][token1] = pool;
        getPool[token1][token0] = pool;

        _allPools.push(pool);

        emit PoolCreated(token0, token1, pool, _allPools.length);
    }

    /// @inheritdoc IAMMFactory
    /// @dev    Implements the standard CREATE2 address prediction formula.
    function computePoolAddress(
        address tokenA,
        address tokenB
    ) external view override returns (address pool) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 initCodeHash = keccak256(type(AMM).creationCode);

        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            initCodeHash
                        )
                    )
                )
            )
        );
    }
}
