// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Access Control Tests
/// @notice Tests for access control, ownership, and pause functionality
contract DarkPoolTaskManagerAccessControlTest is Test {
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    address public owner;
    address public nonOwner;
    address public operator1;

    bytes32 public constant BATCH_HASH_1 = keccak256("batch1");
    bytes32 public constant RESPONSE_1 = keccak256("response1");
    bytes public constant QUORUM_NUMBERS = hex"00";

    event TaskCompleted(uint32 indexed taskIndex, bytes32 response);

    function setUp() public {
        owner = address(this);
        nonOwner = address(0x999);
        operator1 = address(0x1);

        serviceManager = new MockServiceManager();
        serviceManager.setValidOperator(operator1, true);
        serviceManager.setOperatorStake(operator1, 1e18);

        taskManager = new DarkPoolTaskManager(serviceManager, owner);
    }

    // ============ Ownership Tests ============

    function test_Owner_CanPause() public {
        taskManager.pause();
        assertTrue(taskManager.paused());
    }

    function test_Owner_CanUnpause() public {
        taskManager.pause();
        taskManager.unpause();
        assertFalse(taskManager.paused());
    }

    function test_Owner_CanForceCompleteTask() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.expectEmit(true, true, true, true);
        emit TaskCompleted(0, RESPONSE_1);

        taskManager.forceCompleteTask(0, RESPONSE_1);

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
    }

    function test_NonOwner_CannotPause() public {
        vm.expectRevert();
        vm.prank(nonOwner);
        taskManager.pause();
    }

    function test_NonOwner_CannotUnpause() public {
        taskManager.pause();
        vm.expectRevert();
        vm.prank(nonOwner);
        taskManager.unpause();
    }

    function test_NonOwner_CannotForceCompleteTask() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        vm.expectRevert();
        vm.prank(nonOwner);
        taskManager.forceCompleteTask(0, RESPONSE_1);
    }

    // ============ Pause Functionality Tests ============

    function test_Pause_BlocksTaskCreation() public {
        taskManager.pause();
        vm.expectRevert();
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
    }

    function test_Pause_BlocksTaskResponse() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.pause();

        vm.expectRevert();
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    function test_Unpause_AllowsTaskCreation() public {
        taskManager.pause();
        taskManager.unpause();
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).batchHash, BATCH_HASH_1);
    }

    function test_Unpause_AllowsTaskResponse() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.pause();
        taskManager.unpause();

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
    }

    function test_Pause_DoesNotBlockViewFunctions() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.pause();

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.batchHash, BATCH_HASH_1);
        assertEq(taskManager.latestTaskNum(), 1);
    }

    function test_Pause_DoesNotBlockGetResponseCount() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        taskManager.pause();

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 1);
    }

    function test_Pause_DoesNotBlockIsQuorumReached() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        taskManager.pause();

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    // ============ Force Complete Tests ============

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

    function test_ForceCompleteTask_EmitsEvent() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);

        vm.expectEmit(true, true, true, true);
        emit TaskCompleted(0, RESPONSE_1);

        taskManager.forceCompleteTask(0, RESPONSE_1);
    }

    function test_ForceCompleteTask_CanCompleteBeforeQuorum() public {
        taskManager.createNewTask(BATCH_HASH_1, 5, QUORUM_NUMBERS);

        taskManager.forceCompleteTask(0, RESPONSE_1);

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 0);
    }

    // ============ Operator Validation Tests ============

    function test_OperatorValidation_ValidOperatorCanRespond() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
    }

    function test_OperatorValidation_InvalidOperatorCannotRespond() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        address invalidOperator = address(0x888);
        serviceManager.setValidOperator(invalidOperator, false);

        vm.expectRevert(DarkPoolTaskManager.OperatorNotValid.selector);
        vm.prank(invalidOperator);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    function test_OperatorValidation_OperatorWithLowStakeCannotRespond() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        address lowStakeOperator = address(0x777);
        serviceManager.setValidOperator(lowStakeOperator, true);
        serviceManager.setOperatorStake(lowStakeOperator, 0.5e18); // Below minimum

        vm.expectRevert(DarkPoolTaskManager.OperatorNotValid.selector);
        vm.prank(lowStakeOperator);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }
}

