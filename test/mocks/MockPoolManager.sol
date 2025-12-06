// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @title MockPoolManager
/// @notice Mock implementation of IPoolManager for testing
contract MockPoolManager is IPoolManager {
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => bool) public pools;
    mapping(PoolId => uint256) public poolLiquidity;

    function initialize(PoolKey calldata key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        override
        returns (int24 tick)
    {
        PoolId poolId = key.toId();
        pools[poolId] = true;
        return 0;
    }

    function lock(bytes calldata data) external override returns (bytes memory) {
        return data;
    }

    function setPool(PoolId poolId, bool exists) external {
        pools[poolId] = exists;
    }

    function setPoolLiquidity(PoolId poolId, uint256 liquidity) external {
        poolLiquidity[poolId] = liquidity;
    }
}

