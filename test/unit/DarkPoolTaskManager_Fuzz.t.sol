// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Fuzz Tests
/// @notice Property-based fuzz tests for the task manager
contract DarkPoolTaskManagerFuzzTest is Test {
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    address public owner;
    address[] public operators;

    bytes public constant QUORUM_NUMBERS = hex"00";

    function setUp() public {
        owner = address(this);
        serviceManager = new MockServiceManager();
        taskManager = new DarkPoolTaskManager(serviceManager, owner);

        // Create 20 operators for fuzzing
        for (uint256 i = 0; i < 20; i++) {
            address operator = address(uint160(0x1000 + i));
            operators.push(operator);
            serviceManager.setValidOperator(operator, true);
            serviceManager.setOperatorStake(operator, 1e18);
        }
    }

    // ============ Fuzz Tests ============

    function testFuzz_CreateTask_ValidQuorumThreshold(uint32 quorumThreshold) public {
        vm.assume(quorumThreshold >= 1 && quorumThreshold <= 100);

        bytes32 batchHash = keccak256(abi.encodePacked(quorumThreshold));
        taskManager.createNewTask(batchHash, quorumThreshold, QUORUM_NUMBERS);

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.quorumThreshold, quorumThreshold);
    }

    function testFuzz_CreateTask_InvalidQuorumThreshold(uint32 quorumThreshold) public {
        vm.assume(quorumThreshold == 0 || quorumThreshold > 100);

        bytes32 batchHash = keccak256(abi.encodePacked(quorumThreshold));
        vm.expectRevert(DarkPoolTaskManager.InvalidQuorumThreshold.selector);
        taskManager.createNewTask(batchHash, quorumThreshold, QUORUM_NUMBERS);
    }

    function testFuzz_RespondToTask_ValidOperator(bytes32 batchHash, bytes32 response) public {
        taskManager.createNewTask(batchHash, 1, QUORUM_NUMBERS);

        vm.prank(operators[0]);
        taskManager.respondToTask(batchHash, response, "");

        assertEq(taskManager.taskResponses(0, operators[0]), response);
        assertEq(taskManager.getResponseCount(0, response), 1);
    }

    function testFuzz_QuorumReached_ExactMatch(uint32 quorumThreshold, bytes32 batchHash, bytes32 response) public {
        vm.assume(quorumThreshold >= 1 && quorumThreshold <= 20);

        taskManager.createNewTask(batchHash, quorumThreshold, QUORUM_NUMBERS);

        // Respond with exact quorum threshold
        for (uint256 i = 0; i < quorumThreshold; i++) {
            vm.prank(operators[i]);
            taskManager.respondToTask(batchHash, response, "");
        }

        assertTrue(taskManager.isQuorumReached(0, response));
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
    }

    function testFuzz_QuorumReached_OneBelow(uint32 quorumThreshold, bytes32 batchHash, bytes32 response) public {
        vm.assume(quorumThreshold >= 2 && quorumThreshold <= 20);

        taskManager.createNewTask(batchHash, quorumThreshold, QUORUM_NUMBERS);

        // Respond with one less than quorum
        for (uint256 i = 0; i < quorumThreshold - 1; i++) {
            vm.prank(operators[i]);
            taskManager.respondToTask(batchHash, response, "");
        }

        assertFalse(taskManager.isQuorumReached(0, response));
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertFalse(task.isCompleted);
    }

    function testFuzz_ResponseCounts_Accurate(uint8 numResponses, bytes32 batchHash, bytes32 response) public {
        vm.assume(numResponses >= 1 && numResponses <= 20);

        taskManager.createNewTask(batchHash, 100, QUORUM_NUMBERS);

        for (uint256 i = 0; i < numResponses; i++) {
            vm.prank(operators[i]);
            taskManager.respondToTask(batchHash, response, "");
        }

        assertEq(taskManager.getResponseCount(0, response), numResponses);
    }

    function testFuzz_MultipleTasks_DifferentBatchHashes(uint8 numTasks, bytes32 seed) public {
        vm.assume(numTasks >= 1 && numTasks <= 10);

        for (uint256 i = 0; i < numTasks; i++) {
            bytes32 batchHash = keccak256(abi.encodePacked(seed, i));
            taskManager.createNewTask(batchHash, 1, QUORUM_NUMBERS);
        }

        assertEq(taskManager.latestTaskNum(), numTasks);
    }

    function testFuzz_DuplicateResponse_Reverts(bytes32 batchHash, bytes32 response1, bytes32 response2) public {
        vm.assume(response1 != response2);

        taskManager.createNewTask(batchHash, 2, QUORUM_NUMBERS);

        vm.prank(operators[0]);
        taskManager.respondToTask(batchHash, response1, "");

        vm.expectRevert(DarkPoolTaskManager.DuplicateResponse.selector);
        vm.prank(operators[0]);
        taskManager.respondToTask(batchHash, response2, "");
    }

    function testFuzz_TaskNotFound_Reverts(bytes32 batchHash, bytes32 response) public {
        vm.expectRevert(DarkPoolTaskManager.TaskNotFound.selector);
        vm.prank(operators[0]);
        taskManager.respondToTask(batchHash, response, "");
    }

    function testFuzz_ForceComplete_OnlyOwner(bytes32 batchHash, bytes32 response, address nonOwner) public {
        vm.assume(nonOwner != owner && nonOwner != address(0));

        taskManager.createNewTask(batchHash, 100, QUORUM_NUMBERS);

        vm.expectRevert();
        vm.prank(nonOwner);
        taskManager.forceCompleteTask(0, response);
    }

    function testFuzz_Pause_BlocksOperations(bytes32 batchHash, bytes32 response, uint32 quorumThreshold) public {
        vm.assume(quorumThreshold >= 1 && quorumThreshold <= 100);

        taskManager.pause();

        // Cannot create task
        vm.expectRevert();
        taskManager.createNewTask(batchHash, quorumThreshold, QUORUM_NUMBERS);

        // Create task before pause, then try to respond
        taskManager.unpause();
        taskManager.createNewTask(batchHash, quorumThreshold, QUORUM_NUMBERS);
        taskManager.pause();

        // Cannot respond
        vm.expectRevert();
        vm.prank(operators[0]);
        taskManager.respondToTask(batchHash, response, "");
    }
}

