// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";

/// @title DarkPoolTaskManager Gas Tests
/// @notice Tests focused on gas optimization and performance
contract DarkPoolTaskManagerGasTest is Test {
    DarkPoolTaskManager public taskManager;
    MockServiceManager public serviceManager;
    address public owner;
    address public operator1;
    address public operator2;
    address public operator3;

    bytes32 public constant BATCH_HASH_1 = keccak256("batch1");
    bytes32 public constant RESPONSE_1 = keccak256("response1");
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

    // ============ Gas Measurement Tests ============

    function test_Gas_CreateTask() public {
        uint256 gasBefore = gasleft();
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_RespondToTask() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        uint256 gasBefore = gasleft();
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_RespondToTaskWithQuorumReached() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        uint256 gasBefore = gasleft();
        vm.prank(operator2);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_GetTask() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        uint256 gasBefore = gasleft();
        taskManager.getTask(0);
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_GetResponseCount() public {
        taskManager.createNewTask(BATCH_HASH_1, 1, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        uint256 gasBefore = gasleft();
        taskManager.getResponseCount(0, RESPONSE_1);
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_IsQuorumReached() public {
        taskManager.createNewTask(BATCH_HASH_1, 2, QUORUM_NUMBERS);
        vm.prank(operator1);
        taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");

        uint256 gasBefore = gasleft();
        taskManager.isQuorumReached(0, RESPONSE_1);
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_ForceCompleteTask() public {
        taskManager.createNewTask(BATCH_HASH_1, 100, QUORUM_NUMBERS);
        uint256 gasBefore = gasleft();
        taskManager.forceCompleteTask(0, RESPONSE_1);
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_Pause() public {
        uint256 gasBefore = gasleft();
        taskManager.pause();
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_Unpause() public {
        taskManager.pause();
        uint256 gasBefore = gasleft();
        taskManager.unpause();
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    // ============ Batch Operation Gas Tests ============

    function test_Gas_MultipleTaskCreations() public {
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < 10; i++) {
            taskManager.createNewTask(keccak256(abi.encodePacked(i)), 1, QUORUM_NUMBERS);
        }
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }

    function test_Gas_MultipleResponses() public {
        taskManager.createNewTask(BATCH_HASH_1, 10, QUORUM_NUMBERS);
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < 10; i++) {
            address operator = address(uint160(operator1) + uint160(i));
            serviceManager.setValidOperator(operator, true);
            serviceManager.setOperatorStake(operator, 1e18);
            vm.prank(operator);
            taskManager.respondToTask(BATCH_HASH_1, RESPONSE_1, "");
        }
        uint256 gasUsed = gasBefore - gasleft();
        assertGt(gasUsed, 0);
    }
}

