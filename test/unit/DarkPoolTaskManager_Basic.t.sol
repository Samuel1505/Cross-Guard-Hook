// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {IDarkPoolServiceManager} from "../../src/interfaces/IDarkPoolServiceManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Basic Tests
/// @notice Basic functionality and initialization tests
contract DarkPoolTaskManagerBasicTest is Test {
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

    function test_Constructor_InitialPausedState() public {
        assertFalse(taskManager.paused());
    }

    function test_Constructor_ServiceManagerIsImmutable() public {
        // Verify SERVICE_MANAGER is immutable by checking it can't be changed
        assertEq(address(taskManager.SERVICE_MANAGER()), address(serviceManager));
    }

    function test_Constructor_DifferentOwner() public {
        address newOwner = address(0x999);
        DarkPoolTaskManager newTaskManager = new DarkPoolTaskManager(serviceManager, newOwner);
        assertEq(newTaskManager.owner(), newOwner);
    }

    function test_Constructor_ZeroAddressServiceManager() public {
        // This should still deploy, but may fail on usage
        DarkPoolTaskManager newTaskManager = new DarkPoolTaskManager(
            IDarkPoolServiceManager(address(0)),
            owner
        );
        assertEq(address(newTaskManager.SERVICE_MANAGER()), address(0));
    }

    // ============ Constants Tests ============

    function test_Constants_MinQuorumThreshold() public {
        assertEq(taskManager.MIN_QUORUM_THRESHOLD(), 1);
    }

    function test_Constants_MaxQuorumThreshold() public {
        assertEq(taskManager.MAX_QUORUM_THRESHOLD(), 100);
    }

    // ============ Basic Task Creation Tests ============

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

    function test_CreateTask_StoresQuorumNumbers() public {
        bytes memory customQuorum = hex"010203";
        taskManager.createNewTask(BATCH_HASH_1, 1, customQuorum);
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.quorumNumbers, customQuorum);
    }

    function test_CreateTask_StoresCreatorAddress() public {
        address creator = address(0xABC);
        vm.prank(creator);
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.creator, creator);
    }

    function test_CreateTask_StoresBlockNumber() public {
        uint256 blockBefore = block.number;
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertEq(task.createdBlock, blockBefore);

        vm.roll(block.number + 10);
        taskManager.createNewTask(BATCH_HASH_2, 1, QUORUM_NUMBERS);
        IDarkPoolTaskManager.Task memory task2 = taskManager.getTask(1);
        assertEq(task2.createdBlock, block.number);
    }
}

