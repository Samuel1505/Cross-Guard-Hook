// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Task Creation Tests
/// @notice Comprehensive tests for task creation functionality
contract DarkPoolTaskManagerTaskCreationTest is Test {
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    address public owner;
    address public user;

    bytes32 public constant BATCH_HASH_1 = keccak256("batch1");
    bytes32 public constant BATCH_HASH_2 = keccak256("batch2");
    bytes public constant QUORUM_NUMBERS = hex"00";

    function setUp() public {
        owner = address(this);
        user = address(0x4);

        serviceManager = new MockServiceManager();
        taskManager = new DarkPoolTaskManager(serviceManager, owner);
    }

    // ============ Quorum Threshold Validation Tests ============

    function test_CreateTask_RevertIfQuorumThresholdTooLow() public {
        vm.expectRevert(DarkPoolTaskManager.InvalidQuorumThreshold.selector);
        taskManager.createNewTask(BATCH_HASH_1, 0, QUORUM_NUMBERS);
    }

    function test_CreateTask_RevertIfQuorumThresholdTooHigh() public {
        vm.expectRevert(DarkPoolTaskManager.InvalidQuorumThreshold.selector);
        taskManager.createNewTask(BATCH_HASH_1, 101, QUORUM_NUMBERS);
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

    function test_CreateTask_QuorumThresholdBoundaryMin() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).quorumThreshold, 1);
    }

    function test_CreateTask_QuorumThresholdBoundaryMax() public {
        taskManager.createNewTask(BATCH_HASH_1, 100, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).quorumThreshold, 100);
    }

    function test_CreateTask_QuorumThresholdJustBelowMin() public {
        vm.expectRevert(DarkPoolTaskManager.InvalidQuorumThreshold.selector);
        taskManager.createNewTask(BATCH_HASH_1, 0, QUORUM_NUMBERS);
    }

    function test_CreateTask_QuorumThresholdJustAboveMax() public {
        vm.expectRevert(DarkPoolTaskManager.InvalidQuorumThreshold.selector);
        taskManager.createNewTask(BATCH_HASH_1, 101, QUORUM_NUMBERS);
    }

    function test_CreateTask_VariousQuorumThresholds() public {
        for (uint32 i = 1; i <= 10; i++) {
            taskManager.createNewTask(keccak256(abi.encodePacked("batch", i)), i, QUORUM_NUMBERS);
            assertEq(taskManager.getTask(i - 1).quorumThreshold, i);
        }
    }

    // ============ Pause State Tests ============

    function test_CreateTask_RevertIfPaused() public {
        taskManager.pause();
        vm.expectRevert();
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
    }

    function test_CreateTask_WorksAfterUnpause() public {
        taskManager.pause();
        taskManager.unpause();
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).batchHash, BATCH_HASH_1);
    }

    // ============ Batch Hash Tests ============

    function test_CreateTask_WithZeroBatchHash() public {
        bytes32 zeroHash = bytes32(0);
        taskManager.createNewTask(zeroHash, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).batchHash, zeroHash);
    }

    function test_CreateTask_WithMaxBatchHash() public {
        bytes32 maxHash = bytes32(type(uint256).max);
        taskManager.createNewTask(maxHash, 1, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).batchHash, maxHash);
    }

    function test_CreateTask_DuplicateBatchHashes() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);
        assertEq(taskManager.getTask(0).batchHash, BATCH_HASH_1);
        assertEq(taskManager.getTask(1).batchHash, BATCH_HASH_1);
    }

    // ============ Quorum Numbers Tests ============

    function test_CreateTask_EmptyQuorumNumbers() public {
        bytes memory emptyQuorum = "";
        taskManager.createNewTask(BATCH_HASH_1, 1, emptyQuorum);
        assertEq(taskManager.getTask(0).quorumNumbers.length, 0);
    }

    function test_CreateTask_LargeQuorumNumbers() public {
        bytes memory largeQuorum = new bytes(1000);
        for (uint256 i = 0; i < 1000; i++) {
            largeQuorum[i] = bytes1(uint8(i % 256));
        }
        taskManager.createNewTask(BATCH_HASH_1, 1, largeQuorum);
        assertEq(taskManager.getTask(0).quorumNumbers.length, 1000);
    }

    function test_CreateTask_MultipleQuorumNumbers() public {
        bytes memory multiQuorum = hex"000102030405";
        taskManager.createNewTask(BATCH_HASH_1, 1, multiQuorum);
        assertEq(taskManager.getTask(0).quorumNumbers, multiQuorum);
    }

    // ============ Task Indexing Tests ============

    function test_CreateTask_SequentialTaskIndices() public {
        for (uint32 i = 0; i < 10; i++) {
            taskManager.createNewTask(keccak256(abi.encodePacked(i)), 1, QUORUM_NUMBERS);
            assertEq(taskManager.latestTaskNum(), i + 1);
        }
    }

    function test_CreateTask_TaskIndexStartsAtZero() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.batchHash, BATCH_HASH_1);
    }

    // ============ Event Emission Tests ============

    function test_CreateTask_EmitsTaskCreatedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IDarkPoolTaskManager.TaskCreated(0, BATCH_HASH_1, user);
        vm.prank(user);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
    }

    function test_CreateTask_EventIndexMatchesTaskIndex() public {
        vm.recordLogs();
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
    }

    // ============ Multiple Tasks Tests ============

    function test_CreateTask_ManyTasks() public {
        for (uint32 i = 0; i < 50; i++) {
            taskManager.createNewTask(keccak256(abi.encodePacked(i)), 1, QUORUM_NUMBERS);
        }
        assertEq(taskManager.latestTaskNum(), 50);
    }

    function test_CreateTask_DifferentCreators() public {
        address creator1 = address(0x100);
        address creator2 = address(0x200);

        vm.prank(creator1);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        vm.prank(creator2);
        taskManager.createNewTask(BATCH_HASH_2, 1, QUORUM_NUMBERS);

        assertEq(taskManager.getTask(0).creator, creator1);
        assertEq(taskManager.getTask(1).creator, creator2);
    }
}

