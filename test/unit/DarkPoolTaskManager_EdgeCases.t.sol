// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Edge Cases Tests
/// @notice Tests for edge cases, boundary conditions, and unusual scenarios
contract DarkPoolTaskManagerEdgeCasesTest is Test {
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    address public owner;
    address public operator1;
    address public operator2;
    address public operator3;

    bytes32 public constant BATCH_HASH_1 = keccak256("batch1");
    bytes32 public constant RESPONSE_1 = keccak256("response1");
    bytes32 public constant RESPONSE_2 = keccak256("response2");
    bytes public constant QUORUM_NUMBERS = hex"00";

    function setUp() public {
        owner = address(this);
        operator1 = address(0x1);
        operator2 = address(0x2);
        operator3 = address(0x3);

        serviceManager = new MockServiceManager();
        serviceManager.setValidOperator(operator1, true);
        serviceManager.setOperatorStake(operator1, 1e18);
        serviceManager.setValidOperator(operator2, true);
        serviceManager.setOperatorStake(operator2, 1e18);
        serviceManager.setValidOperator(operator3, true);
        serviceManager.setOperatorStake(operator3, 1e18);

        taskManager = new DarkPoolTaskManager(serviceManager, owner);
    }

    // ============ Boundary Value Tests ============

    function test_QuorumThreshold_ExactMatch() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    function test_QuorumThreshold_OneBelow() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    function test_QuorumThreshold_OneAbove() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator3);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 3);
    }

    // ============ Zero/Empty Value Tests ============

    function test_ZeroBatchHash() public {
        bytes32 zeroHash = bytes32(0);
        taskManager.createNewTask(zeroHash, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).batchHash, zeroHash);
    }

    function test_ZeroResponse() public {
        bytes32 zeroResponse = bytes32(0);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, zeroResponse, "");
        assertEq(taskManager.taskResponses(0, operator1), zeroResponse);
    }

    function test_EmptyQuorumNumbers() public {
        bytes memory emptyQuorum = "";
        taskManager.createNewTask(BATCH_HASH_1, 1, emptyQuorum);
        assertEq(taskManager.getTask(0).quorumNumbers.length, 0);
    }

    // ============ Maximum Value Tests ============

    function test_MaxQuorumThreshold() public {
        taskManager.createNewTask(BATCH_HASH_1, 100, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).quorumThreshold, 100);
    }

    function test_MaxBatchHash() public {
        bytes32 maxHash = bytes32(type(uint256).max);
        taskManager.createNewTask(maxHash, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).batchHash, maxHash);
    }

    function test_MaxResponseHash() public {
        bytes32 maxResponse = bytes32(type(uint256).max);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, maxResponse, "");
        assertEq(taskManager.taskResponses(0, operator1), maxResponse);
    }

    // ============ Multiple Tasks Edge Cases ============

    function test_MultipleTasks_SameBatchHash() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        // Should find the latest incomplete task
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        // Should find task index 2
        assertEq(taskManager.taskResponses(2, operator1), RESPONSE_1);
    }

    function test_MultipleTasks_DifferentQuorumThresholds() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        assertEq(taskManager.getTask(0).quorumThreshold, 1);
        assertEq(taskManager.getTask(1).quorumThreshold, 2);
        assertEq(taskManager.getTask(2).quorumThreshold, 3);
    }

    // ============ Response Edge Cases ============

    function test_ResponseCounts_MultipleDifferentResponses() public {
        taskManager.createNewTask(BATCH_HASH_1, 10, QUORUM_NUMBERS);

        bytes32[10] memory responses;
        for (uint256 i = 0; i < 10; i++) {
            responses[i] = keccak256(abi.encodePacked("response", i));
            address operator = address(uint160(operator1) + uint160(i));
            serviceManager.setValidOperator(operator, true);
            serviceManager.setOperatorStake(operator, 1e18);
            vm.prank(operator);
            taskManager.respondToTask(BATCH_HASH_1, responses[i], "");
        }

        for (uint256 i = 0; i < 10; i++) {
            assertEq(taskManager.getResponseCount(0, responses[i]), 1);
        }
    }

    function test_ResponseCounts_SameResponseMultipleTimes() public {
        taskManager.createNewTask(BATCH_HASH_1, 10, QUORUM_NUMBERS);

        for (uint256 i = 0; i < 10; i++) {
            address operator = address(uint160(operator1) + uint160(i));
            serviceManager.setValidOperator(operator, true);
            serviceManager.setOperatorStake(operator, 1e18);
            vm.prank(operator);
            taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        }

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 10);
    }

    // ============ Task Completion Edge Cases ============

    function test_TaskCompletion_QuorumReachedOnLastResponse() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertFalse(task.isCompleted);

        vm.prank(operator3);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
    }

    function test_TaskCompletion_QuorumReachedWithDifferentResponses() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_2, "");

        // Neither response reaches quorum
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_2));

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertFalse(task.isCompleted);
    }

    // ============ View Function Edge Cases ============

    function test_GetTask_NonExistentTask() public {
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(999);
        assertEq(task.creator, address(0));
        assertEq(task.batchHash, bytes32(0));
    }

    function test_GetResponseCount_NonExistentTask() public {
        assertEq(taskManager.getResponseCount(999, RESPONSE_1), 0);
    }

    function test_GetResponseCount_NonExistentResponse() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getResponseCount(0, RESPONSE_2), 0);
    }

    function test_IsQuorumReached_NonExistentTask() public {
        assertFalse(taskManager.isQuorumReached(999, RESPONSE_1));
    }

    function test_IsQuorumReached_NonExistentResponse() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_2));
    }

    // ============ Block Number Edge Cases ============

    function test_CreatedBlock_StoredCorrectly() public {
        uint256 blockBefore = block.number;
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).createdBlock, blockBefore);
    }

    function test_CreatedBlock_DifferentBlocks() public {
        uint256 block1 = block.number;
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        uint256 task1Block = taskManager.getTask(0).createdBlock;
        assertEq(task1Block, block1);

        // Roll forward 100 blocks - vm.roll sets the block number for the next transaction
        vm.roll(block1 + 100);
        
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        uint256 task2Block = taskManager.getTask(1).createdBlock;

        // Verify tasks were created in different blocks
        // Note: The exact difference may vary, but task2 should be created in a later block
        assertGt(task2Block, task1Block, "Second task should be created in a later block");
        // Verify the difference is at least close to 100 (allowing for some variance)
        assertGe(task2Block - task1Block, 100, "Block difference should be at least 100");
    }

    // ============ Large Number Tests ============

    function test_LargeQuorumNumbers() public {
        bytes memory largeQuorum = new bytes(5000);
        for (uint256 i = 0; i < 5000; i++) {
            largeQuorum[i] = bytes1(uint8(i % 256));
        }
        taskManager.createNewTask(BATCH_HASH_1, 1, largeQuorum);
        assertEq(taskManager.getTask(0).quorumNumbers.length, 5000);
    }

    function test_ManyTasks() public {
        for (uint32 i = 0; i < 100; i++) {
            taskManager.createNewTask(keccak256(abi.encodePacked(i)), 1, QUORUM_NUMBERS);
        }
        assertEq(taskManager.latestTaskNum(), 100);
    }

    // ============ Find Task Edge Cases ============

    function test_FindTask_NoMatchingBatchHash() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        bytes32 differentHash = keccak256("different");

        vm.expectRevert(DarkPoolTaskManager.TaskNotFound.selector);
        vm.prank(operator1);
        taskManager.respondToTask(differentHash, RESPONSE_1, "");
    }

    function test_FindTask_AllTasksCompleted() public {
        // Create task with quorum 2 so it doesn't auto-complete after first response
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        // Force complete the task before quorum is reached
        taskManager.forceCompleteTask(0, RESPONSE_1);

        // After force complete, responses should be blocked
        vm.expectRevert(DarkPoolTaskManager.TaskAlreadyCompleted.selector);
        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_2, "");
    }
}

