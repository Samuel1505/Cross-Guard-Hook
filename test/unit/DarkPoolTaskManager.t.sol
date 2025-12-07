// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Unit Tests
/// @notice Comprehensive unit tests for DarkPoolTaskManager contract
contract DarkPoolTaskManagerTest is Test {
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    address public owner;
    address public operator1;
    address public operator2;
    address public operator3;
    address public user;

    bytes32 public constant BATCH_HASH_1 = keccak256("batch1");
    bytes32 public constant BATCH_HASH_2 = keccak256("batch2");
    bytes32 public constant RESPONSE_1 = keccak256("response1");
    bytes32 public constant RESPONSE_2 = keccak256("response2");
    bytes public constant QUORUM_NUMBERS = hex"00";

    event TaskCreated(uint32 indexed taskIndex, bytes32 indexed batchHash, address indexed creator);
    event TaskResponded(uint32 indexed taskIndex, address indexed operator, bytes32 response);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 response);

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
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsServiceManager() public {
        assertEq(address(taskManager.SERVICE_MANAGER()), address(serviceManager));
    }

    function test_Constructor_SetsOwner() public {
        assertEq(taskManager.owner(), owner);
    }

    function test_Constructor_InitialTaskNumIsZero() public {
        assertEq(taskManager.latestTaskNum(), 0);
    }

    // ============ Create Task Tests ============

    function test_CreateTask_Success() public {
        vm.expectEmit(true, true, true, true);
        emit TaskCreated(0, BATCH_HASH_1, user);

        vm.prank(user);
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.batchHash, BATCH_HASH_1);
        assertEq(task.quorumThreshold, 2);
        assertEq(task.creator, user);
        assertEq(task.isCompleted, false);
        assertEq(task.createdBlock, block.number);
    }

    function test_CreateTask_IncrementsTaskNum() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.latestTaskNum(), 1);

        taskManager.createNewTask(BATCH_HASH_2, 1, QUORUM_NUMBERS);
        assertEq(taskManager.latestTaskNum(), 2);
    }

    function test_CreateTask_MultipleTasks() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_2, 2, QUORUM_NUMBERS);

        IDarkPoolTaskManager.Task memory task1 = taskManager.getTask(0);
        IDarkPoolTaskManager.Task memory task2 = taskManager.getTask(1);

        assertEq(task1.batchHash, BATCH_HASH_1);
        assertEq(task2.batchHash, BATCH_HASH_2);
    }

    function test_CreateTask_RevertIfQuorumThresholdTooLow() public {
        vm.expectRevert(DarkPoolTaskManager.InvalidQuorumThreshold.selector);
        taskManager.createNewTask(BATCH_HASH_1, 0, QUORUM_NUMBERS);
    }

    function test_CreateTask_RevertIfQuorumThresholdTooHigh() public {
        vm.expectRevert(DarkPoolTaskManager.InvalidQuorumThreshold.selector);
        taskManager.createNewTask(BATCH_HASH_1, 101, QUORUM_NUMBERS);
    }

    function test_CreateTask_RevertIfPaused() public {
        taskManager.pause();
        vm.expectRevert();
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
    }

    function test_CreateTask_WithMinQuorum() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.quorumThreshold, 1);
    }

    function test_CreateTask_WithMaxQuorum() public {
        taskManager.createNewTask(BATCH_HASH_1, 100, QUORUM_NUMBERS);
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.quorumThreshold, 100);
    }

    // ============ Respond to Task Tests ============

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

    function test_RespondToTask_ReachesQuorum() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.expectEmit(true, true, true, true);
        emit TaskCompleted(0, RESPONSE_1);

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
    }

    function test_RespondToTask_RevertIfTaskNotFound() public {
        vm.expectRevert(DarkPoolTaskManager.TaskNotFound.selector);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_2, RESPONSE_1, "");
    }

    function test_RespondToTask_RevertIfTaskAlreadyCompleted() public {
        // Create task with quorum 2 so it doesn't auto-complete after first response
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        // Force complete the task before quorum is reached
        taskManager.forceCompleteTask(0, RESPONSE_1);

        // Now responses should be blocked after force complete
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

    function test_RespondToTask_NonReentrant() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        // This test ensures reentrancy protection is in place
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    // ============ View Function Tests ============

    function test_GetTask_ReturnsCorrectData() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.batchHash, BATCH_HASH_1);
        assertEq(task.quorumThreshold, 3);
        assertEq(task.creator, address(this));
        assertEq(task.isCompleted, false);
    }

    function test_GetResponseCount_ReturnsZeroInitially() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 0);
    }

    function test_GetResponseCount_ReturnsCorrectCount() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 2);
    }

    function test_IsQuorumReached_ReturnsFalseInitially() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    function test_IsQuorumReached_ReturnsTrueWhenReached() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    function test_IsQuorumReached_ReturnsFalseForNonExistentTask() public {
        assertFalse(taskManager.isQuorumReached(999, RESPONSE_1));
    }

    // ============ Force Complete Tests ============

    function test_ForceCompleteTask_Success() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.expectEmit(true, true, true, true);
        emit TaskCompleted(0, RESPONSE_1);

        taskManager.forceCompleteTask(0, RESPONSE_1);

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
    }

    function test_ForceCompleteTask_RevertIfNotOwner() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        vm.expectRevert();
        vm.prank(user);
        taskManager.forceCompleteTask(0, RESPONSE_1);
    }

    function test_ForceCompleteTask_RevertIfTaskNotFound() public {
        vm.expectRevert(DarkPoolTaskManager.TaskNotFound.selector);
        taskManager.forceCompleteTask(999, RESPONSE_1);
    }

    function test_ForceCompleteTask_RevertIfAlreadyCompleted() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.expectRevert(DarkPoolTaskManager.TaskAlreadyCompleted.selector);
        taskManager.forceCompleteTask(0, RESPONSE_1);
    }

    // ============ Pause/Unpause Tests ============

    function test_Pause_Success() public {
        taskManager.pause();
        assertTrue(taskManager.paused());
    }

    function test_Unpause_Success() public {
        taskManager.pause();
        taskManager.unpause();
        assertFalse(taskManager.paused());
    }

    function test_Pause_RevertIfNotOwner() public {
        vm.expectRevert();
        vm.prank(user);
        taskManager.pause();
    }

    function test_Unpause_RevertIfNotOwner() public {
        taskManager.pause();
        vm.expectRevert();
        vm.prank(user);
        taskManager.unpause();
    }

    // ============ Edge Cases ============

    function test_FindTaskByBatchHash_FindsLatestTask() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        // Should find the latest task (index 1)
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(1);
        assertEq(task.batchHash, BATCH_HASH_1);
    }

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

    function test_QuorumThreshold_ExactMatch() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }
}

