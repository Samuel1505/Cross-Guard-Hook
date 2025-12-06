// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolHook} from "../../src/DarkPoolHook.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {DarkPoolServiceManager} from "../../src/DarkPoolServiceManager.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";
import {MockBridge} from "../mocks/MockBridge.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// @title DarkPool Integration Tests
/// @notice Integration tests for the complete DarkPool system
contract DarkPoolIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    DarkPoolHook public hook;
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    MockPoolManager public poolManager;
    MockBridge public bridge;
    address public owner;
    address public operator1;
    address public operator2;
    address public operator3;
    address public user;

    PoolKey public poolKey;
    PoolId public poolId;
    Currency public currency0;
    Currency public currency1;

    function setUp() public {
        owner = address(this);
        operator1 = address(0x1);
        operator2 = address(0x2);
        operator3 = address(0x3);
        user = address(0x4);

        serviceManager = new MockServiceManager();
        serviceManager.setValidOperator(operator1, true);
        serviceManager.setOperatorStake(operator1, 1e18);
        serviceManager.setValidOperator(operator2, true);
        serviceManager.setOperatorStake(operator2, 1e18);
        serviceManager.setValidOperator(operator3, true);
        serviceManager.setOperatorStake(operator3, 1e18);

        taskManager = new DarkPoolTaskManager(serviceManager, owner);
        poolManager = new MockPoolManager();
        bridge = new MockBridge();

        hook = new DarkPoolHook(poolManager, serviceManager, taskManager, owner);
        hook.setCrossChainBridge(address(bridge));

        currency0 = Currency.wrap(address(0x100));
        currency1 = Currency.wrap(address(0x200));

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: Hooks(address(hook))
        });
        poolId = poolKey.toId();

        hook.setPoolEnabled(poolKey, true);
    }

    // ============ Full Flow Tests ============

    function test_FullFlow_CommitRevealSwap() public {
        bytes32 secret = keccak256("secret");
        uint256 amountIn = 1e18;
        uint256 deadline = block.timestamp + 1 days;

        // Step 1: Commit swap
        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, amountIn, currency0, currency1, deadline, secret);

        // Step 2: Wait for commit period
        vm.roll(block.number + hook.DEFAULT_COMMIT_PERIOD() + 1);

        // Step 3: Reveal and swap
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: amountIn, sqrtPriceLimitX96: 0}), "");

        DarkPoolHook.CommitData memory commit = hook.getCommit(commitHash);
        assertTrue(commit.revealed);
    }

    function test_FullFlow_TaskCreationAndResponse() public {
        bytes32 batchHash = keccak256("batch1");
        bytes32 response = keccak256("response1");
        bytes memory quorumNumbers = hex"00";

        // Step 1: Create task
        taskManager.createNewTask(batchHash, 2, quorumNumbers);

        // Step 2: Operators respond
        vm.prank(operator1);
        taskManager.respondToTask(batchHash, response, "");

        vm.prank(operator2);
        taskManager.respondToTask(batchHash, response, "");

        // Step 3: Verify quorum reached
        assertTrue(taskManager.isQuorumReached(0, response));
    }

    function test_FullFlow_CommitSwapWithTaskValidation() public {
        bytes32 secret = keccak256("secret");
        uint256 amountIn = 1e18;
        uint256 deadline = block.timestamp + 1 days;

        // Commit swap
        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, amountIn, currency0, currency1, deadline, secret);

        // Create validation task
        bytes32 batchHash = keccak256(abi.encodePacked(commitHash, block.number, user));
        taskManager.createNewTask(batchHash, 2, hex"00");

        // Operators validate
        bytes32 response = keccak256("valid");
        vm.prank(operator1);
        taskManager.respondToTask(batchHash, response, "");

        vm.prank(operator2);
        taskManager.respondToTask(batchHash, response, "");

        // Verify task completed
        assertTrue(taskManager.isQuorumReached(0, response));
    }

    function test_FullFlow_MultipleCommitsSameUser() public {
        bytes32 secret1 = keccak256("secret1");
        bytes32 secret2 = keccak256("secret2");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash1 = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret1);

        vm.prank(user);
        bytes32 commitHash2 = hook.commitSwap(poolKey, 2e18, currency0, currency1, deadline, secret2);

        assertNotEq(commitHash1, commitHash2);
        assertEq(hook.userNonces(user), 2);
    }

    function test_FullFlow_MultipleTasksMultipleOperators() public {
        bytes32 batchHash1 = keccak256("batch1");
        bytes32 batchHash2 = keccak256("batch2");
        bytes32 response1 = keccak256("response1");
        bytes32 response2 = keccak256("response2");

        // Create two tasks
        taskManager.createNewTask(batchHash1, 2, hex"00");
        taskManager.createNewTask(batchHash2, 2, hex"00");

        // Operators respond to task 1
        vm.prank(operator1);
        taskManager.respondToTask(batchHash1, response1, "");

        vm.prank(operator2);
        taskManager.respondToTask(batchHash1, response1, "");

        // Operators respond to task 2
        vm.prank(operator1);
        taskManager.respondToTask(batchHash2, response2, "");

        vm.prank(operator3);
        taskManager.respondToTask(batchHash2, response2, "");

        assertTrue(taskManager.isQuorumReached(0, response1));
        assertTrue(taskManager.isQuorumReached(1, response2));
    }

    // ============ Cross-Chain Integration Tests ============

    function test_CrossChainSwap_InitiateTransfer() public {
        bytes32 secret = keccak256("secret");
        uint256 amountIn = 1e18;
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, amountIn, currency0, currency1, deadline, secret);

        vm.roll(block.number + hook.DEFAULT_COMMIT_PERIOD() + 1);

        // This would test cross-chain swap initiation
        // In a full implementation, this would call the bridge
    }

    // ============ Pause/Unpause Integration Tests ============

    function test_Pause_BlocksAllOperations() public {
        taskManager.pause();
        hook.pause();

        bytes32 batchHash = keccak256("batch1");
        vm.expectRevert();
        taskManager.createNewTask(batchHash, 1, hex"00");

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;
        vm.expectRevert();
        vm.prank(user);
        hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);
    }

    function test_Unpause_ResumesOperations() public {
        taskManager.pause();
        hook.pause();

        taskManager.unpause();
        hook.unpause();

        bytes32 batchHash = keccak256("batch1");
        taskManager.createNewTask(batchHash, 1, hex"00");

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;
        vm.prank(user);
        hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);
    }

    // ============ Quorum Threshold Tests ============

    function test_QuorumThreshold_ExactMatch() public {
        bytes32 batchHash = keccak256("batch1");
        bytes32 response = keccak256("response1");

        taskManager.createNewTask(batchHash, 3, hex"00");

        vm.prank(operator1);
        taskManager.respondToTask(batchHash, response, "");

        assertFalse(taskManager.isQuorumReached(0, response));

        vm.prank(operator2);
        taskManager.respondToTask(batchHash, response, "");

        assertFalse(taskManager.isQuorumReached(0, response));

        vm.prank(operator3);
        taskManager.respondToTask(batchHash, response, "");

        assertTrue(taskManager.isQuorumReached(0, response));
    }

    function test_QuorumThreshold_ExceedsThreshold() public {
        bytes32 batchHash = keccak256("batch1");
        bytes32 response = keccak256("response1");

        taskManager.createNewTask(batchHash, 2, hex"00");

        vm.prank(operator1);
        taskManager.respondToTask(batchHash, response, "");

        vm.prank(operator2);
        taskManager.respondToTask(batchHash, response, "");

        vm.prank(operator3);
        taskManager.respondToTask(batchHash, response, "");

        assertEq(taskManager.getResponseCount(0, response), 3);
        assertTrue(taskManager.isQuorumReached(0, response));
    }

    // ============ Response Counting Tests ============

    function test_ResponseCounts_TrackMultipleResponses() public {
        bytes32 batchHash = keccak256("batch1");
        bytes32 response1 = keccak256("response1");
        bytes32 response2 = keccak256("response2");

        taskManager.createNewTask(batchHash, 3, hex"00");

        vm.prank(operator1);
        taskManager.respondToTask(batchHash, response1, "");

        vm.prank(operator2);
        taskManager.respondToTask(batchHash, response1, "");

        vm.prank(operator3);
        taskManager.respondToTask(batchHash, response2, "");

        assertEq(taskManager.getResponseCount(0, response1), 2);
        assertEq(taskManager.getResponseCount(0, response2), 1);
    }

    // ============ Commit Period Tests ============

    function test_CommitPeriod_CustomPeriod() public {
        uint256 customPeriod = 10;
        hook.setCommitPeriod(customPeriod);

        bytes32 secret = keccak256("secret");
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(user);
        bytes32 commitHash = hook.commitSwap(poolKey, 1e18, currency0, currency1, deadline, secret);

        vm.roll(block.number + customPeriod);
        vm.expectRevert(DarkPoolHook.CommitPeriodNotElapsed.selector);
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");

        vm.roll(block.number + 1);
        vm.prank(user);
        hook.revealAndSwap(commitHash, secret, poolKey, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), "");
    }

    // ============ Pool Management Integration Tests ============

    function test_PoolManagement_EnableDisable() public {
        PoolKey memory newPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 500,
            tickSpacing: 60,
            hooks: Hooks(address(hook))
        });

        assertFalse(hook.isPoolEnabled(newPoolKey));

        hook.setPoolEnabled(newPoolKey, true);
        assertTrue(hook.isPoolEnabled(newPoolKey));

        hook.setPoolEnabled(newPoolKey, false);
        assertFalse(hook.isPoolEnabled(newPoolKey));
    }

    // ============ Edge Case Integration Tests ============

    function test_EdgeCase_CommitExpiresBeforeReveal() public {
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

    function test_EdgeCase_TaskNotFoundAfterCompletion() public {
        bytes32 batchHash = keccak256("batch1");
        bytes32 response = keccak256("response1");

        taskManager.createNewTask(batchHash, 1, hex"00");

        vm.prank(operator1);
        taskManager.respondToTask(batchHash, response, "");

        // Task is now completed, should not find it
        bytes32 fakeBatchHash = keccak256("fake");
        vm.expectRevert(DarkPoolTaskManager.TaskNotFound.selector);
        vm.prank(operator2);
        taskManager.respondToTask(fakeBatchHash, response, "");
    }

    function test_EdgeCase_MaxQuorumThreshold() public {
        bytes32 batchHash = keccak256("batch1");
        taskManager.createNewTask(batchHash, 100, hex"00");

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.quorumThreshold, 100);
    }

    function test_EdgeCase_MinQuorumThreshold() public {
        bytes32 batchHash = keccak256("batch1");
        taskManager.createNewTask(batchHash, 1, hex"00");

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.quorumThreshold, 1);
    }
}

