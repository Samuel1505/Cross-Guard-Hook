// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @title MockPoolManager
/// @notice Mock implementation of IPoolManager for testing
contract MockPoolManager is IPoolManager {
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => bool) public pools;
    mapping(PoolId => uint256) public poolLiquidity;

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        PoolId poolId = key.toId();
        pools[poolId] = true;
        return 0;
    }

    function lock(bytes calldata data) external returns (bytes memory) {
        return data;
    }

    function unlock(bytes calldata data) external returns (bytes memory) {
        return data;
    }

    // Stub implementations for required functions
    function modifyLiquidity(PoolKey memory, ModifyLiquidityParams memory, bytes calldata)
        external
        returns (BalanceDelta, BalanceDelta)
    {
        return (toBalanceDelta(0, 0), toBalanceDelta(0, 0));
    }

    function swap(PoolKey memory, SwapParams memory, bytes calldata) external returns (BalanceDelta) {
        return toBalanceDelta(0, 0);
    }

    function donate(PoolKey calldata, uint256, uint256, bytes calldata) external returns (BalanceDelta) {
        return toBalanceDelta(0, 0);
    }

    function take(Currency, address, uint256) external {}

    function settle() external payable returns (uint256 paid) {
        return 0;
    }

    function settleFor(address recipient) external payable returns (uint256 paid) {
        return 0;
    }

    function mint(address, uint256, uint256) external {}

    function burn(address, uint256, uint256) external {}

    function collectProtocolFees(address, Currency, uint256) external returns (uint256) {
        return 0;
    }

    function clear(Currency, uint256) external {}

    function sync(Currency) external {}

    function setProtocolFee(PoolKey memory, uint24) external {}

    function setProtocolFeeController(address) external {}

    function protocolFeeController() external view returns (address) {
        return address(0);
    }

    function protocolFeesAccrued(Currency) external view returns (uint256) {
        return 0;
    }

    function updateDynamicLPFee(PoolKey memory, uint24) external {}

    // ERC6909 functions
    function balanceOf(address, uint256) external view returns (uint256) {
        return 0;
    }

    function allowance(address, address, uint256) external view returns (uint256) {
        return 0;
    }

    function isOperator(address, address) external view returns (bool) {
        return false;
    }

    function approve(address, uint256, uint256) external returns (bool) {
        return true;
    }

    function setOperator(address, bool) external returns (bool) {
        return true;
    }

    function transfer(address, uint256, uint256) external returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256, uint256) external returns (bool) {
        return true;
    }

    // Extsload functions
    function extsload(bytes32) external view returns (bytes32) {
        return bytes32(0);
    }

    function extsload(bytes32, uint256) external view returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function extsload(bytes32[] calldata) external view returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    // Exttload functions
    function exttload(bytes32) external view returns (bytes32) {
        return bytes32(0);
    }

    function exttload(bytes32[] calldata) external view returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function setPool(PoolId poolId, bool exists) external {
        pools[poolId] = exists;
    }

    function setPoolLiquidity(PoolId poolId, uint256 liquidity) external {
        poolLiquidity[poolId] = liquidity;
    }
}

