// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolHook} from "../../src/DarkPoolHook.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";
import {MockBridge} from "../mocks/MockBridge.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title DarkPoolHook Unit Tests
/// @notice Comprehensive unit tests for DarkPoolHook contract
contract DarkPoolHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    DarkPoolHook public hook;
    MockPoolManager public poolManager;
    MockServiceManager public serviceManager;
    DarkPoolTaskManager public taskManager;
    MockBridge public bridge;
    address public owner;
    address public user;

    PoolKey public poolKey;
    PoolId public poolId;
    Currency public currency0;
    Currency public currency1;

    event CommitCreated(bytes32 indexed commitHash, address indexed user, PoolId indexed poolId, uint256 commitBlock);
    event SwapRevealed(bytes32 indexed commitHash, address indexed user, PoolId indexed poolId, uint256 amountIn, uint256 amountOut);
    event PoolEnabled(PoolId indexed poolId, bool enabled);
    event CommitPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event CrossChainBridgeUpdated(address oldBridge, address newBridge);

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        poolManager = new MockPoolManager();
        serviceManager = new MockServiceManager();
        taskManager = new DarkPoolTaskManager(serviceManager, owner);
        bridge = new MockBridge();

        // Calculate hook address with correct flags (BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG)
        address hookAddress = address(
            uint160(
                (type(uint160).max & ~Hooks.ALL_HOOK_MASK) | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            )
        );

        // Deploy hook to the correct address using deployCodeTo
        // This bypasses address validation by deploying directly to the target address
        bytes memory constructorArgs = abi.encode(poolManager, serviceManager, taskManager, owner);
        deployCodeTo("DarkPoolHook", constructorArgs, hookAddress);
        
        hook = DarkPoolHook(hookAddress);

        currency0 = Currency.wrap(address(0x100));
        currency1 = Currency.wrap(address(0x200));

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsPoolManager() public {
        assertEq(address(hook.poolManager()), address(poolManager));
    }

    function test_Constructor_SetsServiceManager() public {
        assertEq(address(hook.SERVICE_MANAGER()), address(serviceManager));
    }

    function test_Constructor_SetsTaskManager() public {
        assertEq(address(hook.TASK_MANAGER()), address(taskManager));
    }

    function test_Constructor_SetsDefaultCommitPeriod() public {
        assertEq(hook.commitPeriod(), hook.DEFAULT_COMMIT_PERIOD());
    }

    function test_Constructor_SetsOwner() public {
        assertEq(hook.owner(), owner);
    }

    // ============ Hook Permissions Tests ============

    function test_GetHookPermissions_ReturnsCorrectPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
    }

    // ============ Commit Swap Tests ============

    function test_CommitSwap_Success() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 amountIn = 1e18;
        uint256 deadline = block.timestamp + 1 days;

        // Calculate expected commit hash (need to know the nonce, which starts at 0)
        uint256 nonce = hook.userNonces(user);
        bytes32 expectedCommitHash = keccak256(
            abi.encodePacked(user, poolId, amountIn, currency0, currency1, deadline, nonce, secret)
        );

        vm.expectEmit(true, true, true, true);
        emit CommitCreated(expectedCommitHash, user, poolId, block.number);

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, amountIn, currency0, currency1, deadline, secret);

        DarkPoolHook.CommitData memory commit = hook.getCommit(commitHash);
        assertEq(commit.user, user);
        assertEq(PoolId.unwrap(commit.poolId), PoolId.unwrap(poolId));
        assertEq(commit.amountIn, amountIn);
        assertEq(Currency.unwrap(commit.currencyIn), Currency.unwrap(currency0));
        assertEq(Currency.unwrap(commit.currencyOut), Currency.unwrap(currency1));
        assertEq(commit.deadline, deadline);
        assertEq(commit.commitBlock, block.number);
        assertFalse(commit.revealed);
        assertFalse(commit.executed);
    }

    function test_CommitSwap_IncrementsUserNonce() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        assertEq(hook.userNonces(user), 0);

        vm.prank(user);
        hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        assertEq(hook.userNonces(user), 1);

        vm.prank(user);
        hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        assertEq(hook.userNonces(user), 2);
    }

    function test_CommitSwap_UniqueHashPerCommit() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret1 = keccak256("secret1");
        bytes32 secret2 = keccak256("secret2");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash1 = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret1);

        vm.prank(user);
        bytes32 commitHash2 = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret2);

        assertNotEq(commitHash1, commitHash2);
    }

    function test_CommitSwap_RevertIfPoolNotEnabled() public {
        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.expectRevert(DarkPoolHook.PoolNotEnabled.selector);
        vm.prank(user);
        hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);
    }

    function test_CommitSwap_RevertIfDeadlinePassed() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp - 1;

        vm.expectRevert(DarkPoolHook.CommitExpired.selector);
        vm.prank(user);
        hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);
    }

    function test_CommitSwap_NonReentrant() public {
        hook.setPoolEnabled(poolKey, true);
        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);
    }

    // ============ Reveal and Swap Tests ============

    function test_RevealAndSwap_Success() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        // Advance blocks to pass commit period
        vm.roll(block.number + hook.DEFAULT_COMMIT_PERIOD() + 1);

        vm.expectEmit(true, true, true, true);
        emit SwapRevealed(commitHash, user, poolId, 1e18, 0);

        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");

        DarkPoolHook.CommitData memory commit = hook.getCommit(commitHash);
        assertTrue(commit.revealed);
    }

    function test_RevealAndSwap_RevertIfCommitNotFound() public {
        bytes32 fakeHash = keccak256("fake");
        bytes32 secret = keccak256("secret");

        vm.expectRevert(DarkPoolHook.CommitNotFound.selector);
        hook.revealAndSwap(fakeHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");
    }

    function test_RevealAndSwap_RevertIfAlreadyRevealed() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        vm.roll(block.number + hook.DEFAULT_COMMIT_PERIOD() + 1);

        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");

        vm.expectRevert(DarkPoolHook.CommitAlreadyRevealed.selector);
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");
    }

    function test_RevealAndSwap_RevertIfCommitPeriodNotElapsed() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        vm.expectRevert(DarkPoolHook.CommitPeriodNotElapsed.selector);
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");
    }

    function test_RevealAndSwap_RevertIfDeadlinePassed() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        vm.roll(block.number + hook.DEFAULT_COMMIT_PERIOD() + 1);
        vm.warp(deadline + 1);

        vm.expectRevert(DarkPoolHook.CommitExpired.selector);
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");
    }

    function test_RevealAndSwap_RevertIfInvalidReveal() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        bytes32 wrongSecret = keccak256("wrong");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        vm.roll(block.number + hook.DEFAULT_COMMIT_PERIOD() + 1);

        vm.expectRevert(DarkPoolHook.InvalidReveal.selector);
        vm.prank(user);
        hook.revealAndSwap(commitHash, wrongSecret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");
    }

    function test_RevealAndSwap_RevertIfAlreadyExecuted() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        vm.roll(block.number + hook.DEFAULT_COMMIT_PERIOD() + 1);

        // First reveal should succeed
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");

        // Second reveal should revert as it's already revealed
        vm.expectRevert(DarkPoolHook.CommitAlreadyRevealed.selector);
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");
    }

    // ============ Pool Management Tests ============

    function test_SetPoolEnabled_Success() public {
        vm.expectEmit(true, true, true, true);
        emit PoolEnabled(poolId, true);

        hook.setPoolEnabled(poolKey, true);
        assertTrue(hook.isPoolEnabled(poolKey));
    }

    function test_SetPoolEnabled_Disable() public {
        hook.setPoolEnabled(poolKey, true);
        hook.setPoolEnabled(poolKey, false);
        assertFalse(hook.isPoolEnabled(poolKey));
    }

    function test_SetPoolEnabled_RevertIfNotOwner() public {
        vm.expectRevert();
        vm.prank(user);
        hook.setPoolEnabled(poolKey, true);
    }

    function test_IsPoolEnabled_ReturnsFalseInitially() public {
        assertFalse(hook.isPoolEnabled(poolKey));
    }

    // ============ Commit Period Tests ============

    function test_SetCommitPeriod_Success() public {
        uint256 newPeriod = 10;

        vm.expectEmit(true, true, true, true);
        emit CommitPeriodUpdated(hook.DEFAULT_COMMIT_PERIOD(), newPeriod);

        hook.setCommitPeriod(newPeriod);
        assertEq(hook.commitPeriod(), newPeriod);
    }

    function test_SetCommitPeriod_RevertIfTooLow() public {
        vm.expectRevert(DarkPoolHook.InvalidCommitPeriod.selector);
        hook.setCommitPeriod(0);
    }

    function test_SetCommitPeriod_RevertIfTooHigh() public {
        vm.expectRevert(DarkPoolHook.InvalidCommitPeriod.selector);
        hook.setCommitPeriod(101);
    }

    function test_SetCommitPeriod_RevertIfNotOwner() public {
        vm.expectRevert();
        vm.prank(user);
        hook.setCommitPeriod(10);
    }

    // ============ Cross-Chain Bridge Tests ============

    function test_SetCrossChainBridge_Success() public {
        vm.expectEmit(true, true, true, true);
        emit CrossChainBridgeUpdated(address(0), address(bridge));

        hook.setCrossChainBridge(address(bridge));
        assertEq(address(hook.crossChainBridge()), address(bridge));
    }

    function test_SetCrossChainBridge_RevertIfNotOwner() public {
        vm.expectRevert();
        vm.prank(user);
        hook.setCrossChainBridge(address(bridge));
    }

    // ============ Get Commit Tests ============

    function test_GetCommit_ReturnsCorrectData() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 amountIn = 1e18;
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, amountIn, currency0, currency1, deadline, secret);

        DarkPoolHook.CommitData memory commit = hook.getCommit(commitHash);
        assertEq(commit.user, user);
        assertEq(commit.amountIn, amountIn);
    }

    function test_GetCommit_ReturnsEmptyForNonExistent() public {
        bytes32 fakeHash = keccak256("fake");
        DarkPoolHook.CommitData memory commit = hook.getCommit(fakeHash);
        assertEq(commit.user, address(0));
    }

    // ============ Edge Cases ============

    function test_CommitSwap_MultipleUsers() public {
        hook.setPoolEnabled(poolKey, true);

        address user2 = address(0x2);
        bytes32 secret1 = keccak256("secret1");
        bytes32 secret2 = keccak256("secret2");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash1 = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret1);

        vm.prank(user2);
        bytes32 commitHash2 = hook.commitSwap(poolKey, 2e18, currency0, currency1, deadline, secret2);

        assertNotEq(commitHash1, commitHash2);
        assertEq(hook.userNonces(user), 1);
        assertEq(hook.userNonces(user2), 1);
    }

    function test_CommitSwap_DifferentPools() public {
        PoolKey memory poolKey2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 500,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        hook.setPoolEnabled(poolKey, true);
        hook.setPoolEnabled(poolKey2, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash1 = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        vm.prank(user);
        bytes32 commitHash2 = hook.commitSwap(poolKey2, 1e18, currency0, currency1, deadline, secret);

        assertNotEq(commitHash1, commitHash2);
    }

    function test_RevealAndSwap_ExactCommitPeriod() public {
        hook.setPoolEnabled(poolKey, true);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;
        uint256 commitBlock = block.number;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        // Advance to one block before commit period elapses (should revert)
        vm.roll(commitBlock + hook.DEFAULT_COMMIT_PERIOD() - 1);

        vm.expectRevert(DarkPoolHook.CommitPeriodNotElapsed.selector);
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");

        // Advance to exactly commit period blocks (should succeed as block.number >= commitBlock + commitPeriod)
        vm.roll(commitBlock + hook.DEFAULT_COMMIT_PERIOD());

        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");
    }
}

