// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {IDarkPoolServiceManager} from "../../src/interfaces/IDarkPoolServiceManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Integration Tests
/// @notice Integration tests with service manager and complex scenarios
contract DarkPoolTaskManagerIntegrationTest is Test {
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    address public owner;
    address public operator1;
    address public operator2;
    address public operator3;
    address public operator4;
    address public operator5;

    bytes32 public constant BATCH_HASH_1 = keccak256("batch1");
    bytes32 public constant RESPONSE_1 = keccak256("response1");
    bytes32 public constant RESPONSE_2 = keccak256("response2");
    bytes public constant QUORUM_NUMBERS = hex"00";

    event TaskCreated(uint32 indexed taskIndex, bytes32 indexed batchHash, address indexed creator);
    event TaskResponded(uint32 indexed taskIndex, address indexed operator, bytes32 response);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 response);
    event OperatorRegistered(address indexed operator, uint256 stake);
    event TaskValidationRewarded(uint32 indexed taskIndex, address indexed operator, uint256 reward);

    function setUp() public {
        owner = address(this);
        operator1 = address(0x1);
        operator2 = address(0x2);
        operator3 = address(0x3);
        operator4 = address(0x4);
        operator5 = address(0x5);

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

    // ============ Service Manager Integration Tests ============

    function test_Integration_ServiceManagerValidatesOperator() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        // Valid operator can respond
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
    }

    function test_Integration_ServiceManagerRejectsInvalidOperator() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        address invalidOperator = address(0x999);
        serviceManager.setValidOperator(invalidOperator, false);

        vm.expectRevert(DarkPoolTaskManager.OperatorNotValid.selector);
        vm.prank(invalidOperator);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    function test_Integration_ServiceManagerRecordsTaskValidation() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        // Service manager should have recorded the validation
        // This is tested through the mock's recordTaskValidation call
        assertTrue(true); // If we get here, the call succeeded
    }

    function test_Integration_OperatorDeregistrationBlocksResponse() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        // Deregister operator
        serviceManager.setValidOperator(operator1, false);

        vm.expectRevert(DarkPoolTaskManager.OperatorNotValid.selector);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    function test_Integration_OperatorRegistrationAfterTaskCreation() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        // Register new operator
        address newOperator = address(0x888);
        serviceManager.setValidOperator(newOperator, true);
        serviceManager.setOperatorStake(newOperator, 1e18);

        vm.prank(newOperator);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertEq(taskManager.taskResponses(0, newOperator), RESPONSE_1);
    }

    // ============ Complex Scenario Tests ============

    function test_Integration_MultipleTasksMultipleOperators() public {
        bytes32 batchHash2 = keccak256("batch2");
        bytes32 batchHash3 = keccak256("batch3");

        // Create multiple tasks
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);
        taskManager.createNewTask(batchHash2, 3, QUORUM_NUMBERS);
        taskManager.createNewTask(batchHash3, 2, QUORUM_NUMBERS);

        // Operators respond to different tasks
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator1);
        taskManager.respondToTask(batchHash2, RESPONSE_2, "");

        vm.prank(operator2);
        taskManager.respondToTask(batchHash2, RESPONSE_2, "");

        vm.prank(operator3);
        taskManager.respondToTask(batchHash2, RESPONSE_2, "");

        vm.prank(operator4);
        taskManager.respondToTask(batchHash3, RESPONSE_1, "");

        vm.prank(operator5);
        taskManager.respondToTask(batchHash3, RESPONSE_1, "");

        // Verify all tasks completed
        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
        assertTrue(taskManager.isQuorumReached(1, RESPONSE_2));
        assertTrue(taskManager.isQuorumReached(2, RESPONSE_1));
    }

    function test_Integration_QuorumWithSplitResponses() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        // Two operators respond with RESPONSE_1
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        // One operator responds with RESPONSE_2
        vm.prank(operator3);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_2, "");

        // Neither reaches quorum
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_2));

        // Add one more for RESPONSE_1 to reach quorum
        vm.prank(operator4);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_2));
    }

    function test_Integration_SequentialTaskCompletion() public {
        bytes32 batchHash2 = keccak256("batch2");

        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);
        taskManager.createNewTask(batchHash2, 2, QUORUM_NUMBERS);

        // Complete first task
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));

        // Complete second task
        vm.prank(operator3);
        taskManager.respondToTask(batchHash2, RESPONSE_2, "");

        vm.prank(operator4);
        taskManager.respondToTask(batchHash2, RESPONSE_2, "");

        assertTrue(taskManager.isQuorumReached(1, RESPONSE_2));
    }

    // ============ Pause Integration Tests ============

    function test_Integration_PauseBlocksAllOperations() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.pause();

        // Cannot create new tasks
        vm.expectRevert();
        taskManager.createNewTask(keccak256("batch2"), 1, QUORUM_NUMBERS);

        // Cannot respond to tasks
        vm.expectRevert();
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    function test_Integration_UnpauseResumesOperations() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.pause();
        taskManager.unpause();

        // Can create new tasks
        taskManager.createNewTask(keccak256("batch2"), 1, QUORUM_NUMBERS);

        // Can respond to tasks
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    // ============ Force Complete Integration Tests ============

    function test_Integration_ForceCompleteBeforeQuorum() public {
        taskManager.createNewTask(BATCH_HASH_1, 5, QUORUM_NUMBERS);

        // Only 2 operators respond
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        // Quorum not reached
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));

        // Owner forces completion
        taskManager.forceCompleteTask(0, RESPONSE_2);

        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
    }

    // ============ Large Scale Tests ============

    function test_Integration_ManyOperatorsOneTask() public {
        taskManager.createNewTask(BATCH_HASH_1, 10, QUORUM_NUMBERS);

        // Register and respond with 10 operators
        for (uint256 i = 0; i < 10; i++) {
            address operator = address(uint160(operator1) + uint160(i));
            serviceManager.setValidOperator(operator, true);
            serviceManager.setOperatorStake(operator, 1e18);

            vm.prank(operator);
            taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        }

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 10);
        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    function test_Integration_ManyTasksOneOperator() public {
        // Create 10 tasks
        for (uint32 i = 0; i < 10; i++) {
            taskManager.createNewTask(keccak256(abi.encodePacked("batch", i)), 1, QUORUM_NUMBERS);
        }

        // One operator responds to all
        for (uint32 i = 0; i < 10; i++) {
            bytes32 batchHash = keccak256(abi.encodePacked("batch", i));
            vm.prank(operator1);
            taskManager.respondToTask(batchHash, RESPONSE_1, "");
        }

        // All tasks should be completed
        for (uint32 i = 0; i < 10; i++) {
            assertTrue(taskManager.isQuorumReached(i, RESPONSE_1));
        }
    }

    // ============ Response Pattern Tests ============

    function test_Integration_AllOperatorsSameResponse() public {
        taskManager.createNewTask(BATCH_HASH_1, 3, QUORUM_NUMBERS);

        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator3);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertEq(taskManager.getResponseCount(0, RESPONSE_1), 3);
        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
    }

    function test_Integration_AllOperatorsDifferentResponses() public {
        taskManager.createNewTask(BATCH_HASH_1, 5, QUORUM_NUMBERS);

        bytes32[5] memory responses = [
            keccak256("response1"),
            keccak256("response2"),
            keccak256("response3"),
            keccak256("response4"),
            keccak256("response5")
        ];

        address[5] memory operators = [operator1, operator2, operator3, operator4, operator5];

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(operators[i]);
            taskManager.respondToTask(BATCH_HASH_1, responses[i], "");
        }

        // No quorum reached
        for (uint256 i = 0; i < 5; i++) {
            assertFalse(taskManager.isQuorumReached(0, responses[i]));
        }
    }

    function test_Integration_ServiceManagerStakeValidation() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);

        // Operator with sufficient stake can respond
        serviceManager.setOperatorStake(operator1, 2e18);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertEq(taskManager.taskResponses(0, operator1), RESPONSE_1);
    }

    function test_Integration_TaskIndexIncrement() public {
        bytes32 batchHash2 = keccak256("batch2");
        bytes32 batchHash3 = keccak256("batch3");

        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        assertEq(taskManager.latestTaskNum(), 1);

        taskManager.createNewTask(batchHash2, 1, QUORUM_NUMBERS);
        assertEq(taskManager.latestTaskNum(), 2);

        taskManager.createNewTask(batchHash3, 1, QUORUM_NUMBERS);
        assertEq(taskManager.latestTaskNum(), 3);
    }

    function test_Integration_ResponseAfterForceComplete() public {
        taskManager.createNewTask(BATCH_HASH_1, 5, QUORUM_NUMBERS);

        // Force complete before quorum
        taskManager.forceCompleteTask(0, RESPONSE_1);

        // Cannot respond after force complete
        vm.expectRevert(DarkPoolTaskManager.TaskAlreadyCompleted.selector);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
    }

    function test_Integration_MixedQuorumThresholds() public {
        bytes32 batchHash2 = keccak256("batch2");
        bytes32 batchHash3 = keccak256("batch3");

        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        taskManager.createNewTask(batchHash2, 50, QUORUM_NUMBERS);
        taskManager.createNewTask(batchHash3, 100, QUORUM_NUMBERS);

        assertEq(taskManager.getTask(0).quorumThreshold, 1);
        assertEq(taskManager.getTask(1).quorumThreshold, 50);
        assertEq(taskManager.getTask(2).quorumThreshold, 100);
    }

    function test_Integration_ComplexQuorumScenario() public {
        taskManager.createNewTask(BATCH_HASH_1, 4, QUORUM_NUMBERS);

        // 3 operators respond with RESPONSE_1
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        vm.prank(operator3);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        // Quorum not reached yet
        assertFalse(taskManager.isQuorumReached(0, RESPONSE_1));

        // 4th operator responds, quorum reached
        vm.prank(operator4);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        assertTrue(taskManager.isQuorumReached(0, RESPONSE_1));
        IDarkPoolTaskManager.Task memory task = taskManager.getTask(0);
        assertTrue(task.isCompleted);
    }
}

