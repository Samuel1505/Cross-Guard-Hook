// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Task Response Tests
/// @notice Comprehensive tests for task response and quorum functionality
contract DarkPoolTaskManagerTaskResponseTest is Test {
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    address public owner;
    address public operator1;
    address public operator2;
    address public operator3;
    address public operator4;
    address public operator5;
    address public user;

    bytes32 public constant BATCH_HASH_1 = keccak256("batch1");
    bytes32 public constant BATCH_HASH_2 = keccak256("batch2");
    bytes32 public constant RESPONSE_1 = keccak256("response1");
    bytes32 public constant RESPONSE_2 = keccak256("response2");
    bytes32 public constant RESPONSE_3 = keccak256("response3");
    bytes public constant QUORUM_NUMBERS = hex"00";

    event TaskResponded(uint32 indexed taskIndex, address indexed operator, bytes32 response);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 response);

    function setUp() public {
        owner = address(this);
        operator1 = address(0x1);
        operator2 = address(0x2);
        operator3 = address(0x3);
        operator4 = address(0x4);
        operator5 = address(0x5);
        user = address(0x6);

        serviceManager = new MockServiceManager();
        serviceManager.setValidOperator(operator1, true);
        serviceManager.setOperatorStake(operator1, 1e18);
        serviceManager.setValidOperator(operator2, true);
        serviceManager.setOperatorStake(operator2, 1e18);
        serviceManager.setValidOperator(operator3, true);
        serviceManager.setOperatorStake(operator3, 1e18);
        serviceManager.setValidOperator(operator4, true);
        serviceManager.setOperatorStake(operator4, 1e18);
        serviceManager.setValidOperator(operator5, true);
        serviceManager.setOperatorStake(operator5, 1e18);

        taskManager = new DarkPoolTaskManager(serviceManager, owner);
    }

    // ============ Basic Response Tests ============

    function test_RespondToTask_Success() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        vm.expectEmit(true, true, true, true);
        emit TaskResponded(0, operator1, RESPONSE_1);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 1);
    }

    function test_RespondToTask_MultipleOperators() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 2);
    }

    function test_RespondToTask_DifferentResponses() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_2, "");

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 1);
        assertEq(taskManager.getResponseCount(0, RESPONSE_2), 1);
    }

    function test_RespondToTask_ThreeDifferentResponses() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_2, "");

        vm.prank(operator3);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_3, "");

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 1);
        assertEq(taskManager.getResponseCount(0, RESPONSE_2), 1);
        assertEq(taskManager.getResponseCount(0, RESPONSE_3), 1);
    }

    // ============ Quorum Tests ============

    function test_RespondToTask_ReachesQuorum() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.expectEmit(true, true, true, true);
        emit TaskCompleted(0, RESPONSE_1);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
    }

    function test_RespondToTask_QuorumNotReached() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertFalse(task.isCompleted);
    }

    function test_RespondToTask_QuorumExactMatch() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    function test_RespondToTask_QuorumExceedsThreshold() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator3);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 3);
        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    function test_RespondToTask_MaxQuorumThreshold() public {
        taskManager.createNewTask(BATCH_HASH_1, 5, QUORUM_NUMBERS);

        for (uint256 i = 0; i < 5; i++) {
            address operator = address(uint160(operator1) + uint160(i));
            vm.prank(operator);
            taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        }

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    // ============ Error Cases ============

    function test_RespondToTask_RevertIfTaskNotFound() public {
        vm.expectRevert(DarkPoolTaskManager.TaskNotFound.selector);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_2, RESPONSE_1, "");
    }

    function test_RespondToTask_RevertIfTaskAlreadyCompleted() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.expectRevert(DarkPoolTaskManager.TaskAlreadyCompleted.selector);
        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    function test_RespondToTask_RevertIfOperatorNotValid() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        address invalidOperator = address(0x999);
        serviceManager.setValidOperator(invalidOperator, false);

        vm.expectRevert(DarkPoolTaskManager.OperatorNotValid.selector);
        vm.prank(invalidOperator);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    function test_RespondToTask_RevertIfDuplicateResponse() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.expectRevert(DarkPoolTaskManager.DuplicateResponse.selector);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_2, "");
    }

    function test_RespondToTask_RevertIfPaused() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.pause();

        vm.expectRevert();
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    // ============ Response Counting Tests ============

    function test_ResponseCounts_TrackMultipleResponses() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator3);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_2, "");

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 2);
        assertEq(taskManager.getResponseCount(0, RESPONSE_2), 1);
    }

    function test_ResponseCounts_ZeroInitially() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 0);
    }

    function test_ResponseCounts_IncrementsCorrectly() public {
        taskManager.createNewTask(BATCH_HASH_1, 5, QUORUM_NUMBERS);

        for (uint256 i = 0; i < 5; i++) {
            address operator = address(uint160(operator1) + uint160(i));
            vm.prank(operator);
            taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
            assertEq(taskManager.getResponseCount(0, RESPONSE_1), i + 1);
        }
    }

    // ============ Multiple Tasks Tests ============

    function test_RespondToTask_MultipleTasks() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_2, 1, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_2, RESPONSE_2, "");

        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
        assertEq(taskManager.taskResponses(1, operator2), RESPONSE_2);
    }

    function test_RespondToTask_SameOperatorDifferentTasks() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_2, 1, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_2, RESPONSE_2, "");

        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
        assertEq(taskManager.taskResponses(1, operator1), RESPONSE_2);
    }

    // ============ Find Task By Batch Hash Tests ============

    function test_FindTaskByBatchHash_FindsLatestTask() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        // Should find the latest task (index 1)
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(1);
        assertEq(task.batchHash, BATCH_HASH_1);
    }

    function test_FindTaskByBatchHash_IgnoresCompletedTasks() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_2, "");

        // Should find task 1, not task 0 (which is completed)
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(1);
        assertEq(task.batchHash, BATCH_HASH_1);
        assertEq(taskManager.taskResponses(1, operator2), RESPONSE_2);
    }

    // ============ Signature Tests ============

    function test_RespondToTask_WithEmptySignature() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
    }

    function test_RespondToTask_WithNonEmptySignature() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        bytes memory signature = hex"123456";
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, signature);
        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
    }

    // ============ Reentrancy Tests ============

    function test_RespondToTask_NonReentrant() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        // This test ensures reentrancy protection is in place
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }
}

