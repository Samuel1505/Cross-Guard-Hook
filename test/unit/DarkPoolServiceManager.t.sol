// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DarkPoolServiceManager} from "../../src/DarkPoolServiceManager.sol";
import {DarkPoolTaskManager} from "../../src/DarkPoolTaskManager.sol";
import {IDarkPoolTaskManager} from "../../src/interfaces/IDarkPoolTaskManager.sol";
import {MockServiceManager} from "../mocks/MockServiceManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IStakeRegistry} from "eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IRegistryCoordinator} from "eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISlashingRegistryCoordinator} from "eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Minimal task manager that can call back into the service manager
contract MockTaskManager is IDarkPoolTaskManager {
    function createNewTask(bytes32, uint32, bytes calldata) external pure override {}

    function respondToTask(bytes32, bytes32, bytes calldata) external pure override {}

    function latestTaskNum() external pure override returns (uint32) {
        return 0;
    }

    function getTask(uint32) external pure override returns (Task memory) {
        return
            Task({
                batchHash: bytes32(0),
                quorumThreshold: 0,
                quorumNumbers: "",
                createdBlock: 0,
                creator: address(0),
                isCompleted: false
            });
    }

    function callRecordValidation(DarkPoolServiceManager manager, uint32 taskIndex, address operator) external {
        manager.recordTaskValidation(taskIndex, operator);
    }
}

/// @title DarkPoolServiceManager Unit Tests
/// @notice Comprehensive unit tests for DarkPoolServiceManager contract
contract DarkPoolServiceManagerTest is Test {
    DarkPoolServiceManager public serviceManager;
    DarkPoolTaskManager public taskManager;
    address public owner;
    address public operator1;
    address public operator2;
    address public operator3;
    address public rewardsInitiator;

    // Mock EigenLayer contracts (simplified for testing)
    address public mockAVSDirectory;
    address public mockRewardsCoordinator;
    address public mockRegistryCoordinator;
    address public mockStakeRegistry;
    address public mockPermissionController;
    address public mockAllocationManager;

    event TaskValidationRewarded(uint32 indexed taskIndex, address indexed operator, uint256 reward);
    event TaskRewardSet(uint32 indexed taskIndex, uint256 rewardAmount);

    function _deployServiceManager() internal returns (DarkPoolServiceManager, MockTaskManager) {
        MockTaskManager mockTaskManager = new MockTaskManager();
        DarkPoolServiceManager implementation = new DarkPoolServiceManager(
            IAVSDirectory(mockAVSDirectory),
            IRewardsCoordinator(mockRewardsCoordinator),
            ISlashingRegistryCoordinator(mockRegistryCoordinator),
            IStakeRegistry(mockStakeRegistry),
            IPermissionController(mockPermissionController),
            IAllocationManager(mockAllocationManager),
            mockTaskManager
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(DarkPoolServiceManager.initialize.selector, owner, rewardsInitiator)
        );
        DarkPoolServiceManager manager = DarkPoolServiceManager(address(proxy));
        return (manager, mockTaskManager);
    }

    function _deployAndInit() internal returns (DarkPoolServiceManager, MockTaskManager) {
        return _deployServiceManager();
    }

    function _mockOperator(
        address operator,
        bytes32 operatorId,
        uint8 quorum,
        uint96 stake,
        uint96 minimumStake
    ) internal {
        vm.mockCall(
            mockRegistryCoordinator,
            abi.encodeWithSelector(ISlashingRegistryCoordinator.getOperatorId.selector, operator),
            abi.encode(operatorId)
        );
        vm.mockCall(
            mockStakeRegistry,
            abi.encodeWithSelector(IStakeRegistry.getCurrentStake.selector, operatorId, quorum),
            abi.encode(stake)
        );
        vm.mockCall(
            mockStakeRegistry,
            abi.encodeWithSelector(IStakeRegistry.minimumStakeForQuorum.selector, quorum),
            abi.encode(minimumStake)
        );
    }

    function setUp() public {
        owner = address(this);
        operator1 = address(0x1);
        operator2 = address(0x2);
        operator3 = address(0x3);
        rewardsInitiator = address(0x4);

        // Deploy mock EigenLayer contracts
        mockAVSDirectory = address(0x100);
        mockRewardsCoordinator = address(0x200);
        mockRegistryCoordinator = address(0x300);
        mockStakeRegistry = address(0x400);
        mockPermissionController = address(0x500);
        mockAllocationManager = address(0x600);

        // Note: In a real test, you would deploy actual EigenLayer contracts or use proper mocks
        // For this test, we'll use a simplified approach with a mock that implements the interface
        // This requires the actual ServiceManagerBase to work with EigenLayer contracts
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsTaskManager() public {
        MockTaskManager mockTaskManager = new MockTaskManager();
        DarkPoolServiceManager manager = new DarkPoolServiceManager(
            IAVSDirectory(mockAVSDirectory),
            IRewardsCoordinator(mockRewardsCoordinator),
            ISlashingRegistryCoordinator(mockRegistryCoordinator),
            IStakeRegistry(mockStakeRegistry),
            IPermissionController(mockPermissionController),
            IAllocationManager(mockAllocationManager),
            mockTaskManager
        );

        assertEq(address(manager.TASK_MANAGER()), address(mockTaskManager));
    }

    // ============ Initialize Tests ============

    function test_Initialize_Success() public {
        MockTaskManager mockTaskManager = new MockTaskManager();
        DarkPoolServiceManager implementation = new DarkPoolServiceManager(
            IAVSDirectory(mockAVSDirectory),
            IRewardsCoordinator(mockRewardsCoordinator),
            ISlashingRegistryCoordinator(mockRegistryCoordinator),
            IStakeRegistry(mockStakeRegistry),
            IPermissionController(mockPermissionController),
            IAllocationManager(mockAllocationManager),
            mockTaskManager
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(DarkPoolServiceManager.initialize.selector, owner, rewardsInitiator)
        );
        DarkPoolServiceManager manager = DarkPoolServiceManager(address(proxy));

        assertEq(manager.owner(), owner);
        assertEq(manager.rewardsInitiator(), rewardsInitiator);
    }

    function test_Initialize_RevertIfAlreadyInitialized() public {
        (DarkPoolServiceManager manager,) = _deployServiceManager();

        vm.expectRevert("Initializable: contract is already initialized");
        manager.initialize(owner, rewardsInitiator);
    }

    // ============ IsValidOperator Tests ============

    function test_IsValidOperator_ReturnsTrueForValidOperator() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint8 quorum = 0;
        _mockOperator(operator1, bytes32("op1"), quorum, 2e18, 1e18);

        bool isValid = manager.isValidOperator(operator1, quorum);

        assertTrue(isValid);
    }

    function test_IsValidOperator_ReturnsFalseForInvalidOperator() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint8 quorum = 1;
        _mockOperator(operator1, bytes32("op1"), quorum, 5e17, 1e18);

        bool isValid = manager.isValidOperator(operator1, quorum);

        assertFalse(isValid);
    }

    function test_IsValidOperator_ChecksQuorumStake() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint8 quorum = 2;
        bytes32 operatorId = bytes32("op1");

        vm.expectCall(
            mockRegistryCoordinator,
            abi.encodeWithSelector(ISlashingRegistryCoordinator.getOperatorId.selector, operator1)
        );
        vm.expectCall(
            mockStakeRegistry,
            abi.encodeWithSelector(IStakeRegistry.getCurrentStake.selector, operatorId, quorum)
        );
        vm.expectCall(
            mockStakeRegistry,
            abi.encodeWithSelector(IStakeRegistry.minimumStakeForQuorum.selector, quorum)
        );

        _mockOperator(operator1, operatorId, quorum, 2e18, 1e18);

        manager.isValidOperator(operator1, quorum);
    }

    // ============ GetOperatorStake Tests ============

    function test_GetOperatorStake_ReturnsCorrectStake() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint8 quorum = 1;
        _mockOperator(operator1, bytes32("op1"), quorum, 7, 1);

        uint96 stake = manager.getOperatorStake(operator1, quorum);

        assertEq(stake, 7);
    }

    function test_GetOperatorStake_ReturnsZeroForNonExistentOperator() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint8 quorum = 0;

        vm.mockCall(
            mockRegistryCoordinator,
            abi.encodeWithSelector(ISlashingRegistryCoordinator.getOperatorId.selector, operator1),
            abi.encode(bytes32(0))
        );
        vm.mockCall(
            mockStakeRegistry,
            abi.encodeWithSelector(IStakeRegistry.getCurrentStake.selector, bytes32(0), quorum),
            abi.encode(uint96(0))
        );

        uint96 stake = manager.getOperatorStake(operator1, quorum);

        assertEq(stake, 0);
    }

    // ============ RecordTaskValidation Tests ============

    function test_RecordTaskValidation_Success() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 0;
        _mockOperator(operator1, bytes32("op1"), 0, 1, 1);

        mockTaskManager.callRecordValidation(manager, taskIndex, operator1);

        assertTrue(manager.taskValidations(taskIndex, operator1));
    }

    function test_RecordTaskValidation_RevertIfNotTaskManager() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();

        vm.expectRevert(DarkPoolServiceManager.OnlyTaskManager.selector);
        manager.recordTaskValidation(0, operator1);
    }

    function test_RecordTaskValidation_RevertIfInvalidOperator() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 1;

        vm.mockCall(
            mockRegistryCoordinator,
            abi.encodeWithSelector(ISlashingRegistryCoordinator.getOperatorId.selector, operator1),
            abi.encode(bytes32(0))
        );

        vm.expectRevert(DarkPoolServiceManager.InvalidOperator.selector);
        mockTaskManager.callRecordValidation(manager, taskIndex, operator1);
    }

    function test_RecordTaskValidation_RevertIfAlreadyValidated() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 2;
        _mockOperator(operator1, bytes32("op1"), 0, 1, 1);

        mockTaskManager.callRecordValidation(manager, taskIndex, operator1);

        vm.expectRevert(DarkPoolServiceManager.AlreadyValidated.selector);
        mockTaskManager.callRecordValidation(manager, taskIndex, operator1);
    }

    // ============ SetTaskReward Tests ============

    function test_SetTaskReward_Success() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint32 taskIndex = 10;

        manager.setTaskReward(taskIndex, 1 ether);

        assertEq(manager.taskRewards(taskIndex), 1 ether);
    }

    function test_SetTaskReward_EmitsEvent() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint32 taskIndex = 11;
        uint256 rewardAmount = 123;

        vm.expectEmit(true, true, false, true);
        emit TaskRewardSet(taskIndex, rewardAmount);

        manager.setTaskReward(taskIndex, rewardAmount);
    }

    function test_SetTaskReward_RevertIfNotOwner() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint32 taskIndex = 12;

        vm.prank(operator1);
        vm.expectRevert("Ownable: caller is not the owner");
        manager.setTaskReward(taskIndex, 50);
    }

    // ============ DistributeTaskReward Tests ============

    function test_DistributeTaskReward_Success() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 20;
        uint8 quorum = 0;
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        manager.setTaskReward(taskIndex, 100);
        _mockOperator(operator1, bytes32("op1"), quorum, 2e18, 1e18);
        _mockOperator(operator2, bytes32("op2"), quorum, 2e18, 1e18);

        mockTaskManager.callRecordValidation(manager, taskIndex, operator1);
        mockTaskManager.callRecordValidation(manager, taskIndex, operator2);

        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator1, 50);
        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator2, 50);

        manager.distributeTaskReward(taskIndex, operators, quorum);

        assertEq(manager.taskRewards(taskIndex), 0);
    }

    function test_DistributeTaskReward_RevertIfRewardNotSet() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint32 taskIndex = 21;
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        vm.expectRevert(DarkPoolServiceManager.TaskRewardNotSet.selector);
        manager.distributeTaskReward(taskIndex, operators, 0);
    }

    function test_DistributeTaskReward_OnlyValidatesValidOperators() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 22;
        uint8 quorum = 0;
        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        manager.setTaskReward(taskIndex, 80);
        _mockOperator(operator1, bytes32("op1"), quorum, 2e18, 1e18);
        // operator2 has stake below minimum, will be treated as invalid
        _mockOperator(operator2, bytes32("op2"), quorum, 5e17, 1e18);

        mockTaskManager.callRecordValidation(manager, taskIndex, operator1);
        mockTaskManager.callRecordValidation(manager, taskIndex, operator2);

        vm.recordLogs();
        manager.distributeTaskReward(taskIndex, operators, quorum);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Only one TaskValidationRewarded event should be emitted
        uint256 rewardedEvents;
        bytes32 expectedTopic = keccak256("TaskValidationRewarded(uint32,address,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == expectedTopic) {
                rewardedEvents++;
            }
        }
        assertEq(rewardedEvents, 1);
    }

    function test_DistributeTaskReward_DistributesEqually() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 23;
        uint8 quorum = 1;
        address[] memory operators = new address[](4);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;
        operators[3] = rewardsInitiator;

        manager.setTaskReward(taskIndex, 400);
        _mockOperator(operator1, bytes32("op1"), quorum, 2e18, 1e18);
        _mockOperator(operator2, bytes32("op2"), quorum, 2e18, 1e18);
        _mockOperator(operator3, bytes32("op3"), quorum, 2e18, 1e18);
        _mockOperator(rewardsInitiator, bytes32("op4"), quorum, 2e18, 1e18);

        for (uint256 i = 0; i < operators.length; i++) {
            mockTaskManager.callRecordValidation(manager, taskIndex, operators[i]);
        }

        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator1, 100);
        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator2, 100);
        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator3, 100);
        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, rewardsInitiator, 100);

        manager.distributeTaskReward(taskIndex, operators, quorum);
    }

    function test_DistributeTaskReward_HandlesRemainder() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 24;
        uint8 quorum = 0;
        address[] memory operators = new address[](3);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;

        manager.setTaskReward(taskIndex, 100);
        _mockOperator(operator1, bytes32("op1"), quorum, 2e18, 1e18);
        _mockOperator(operator2, bytes32("op2"), quorum, 2e18, 1e18);
        _mockOperator(operator3, bytes32("op3"), quorum, 2e18, 1e18);

        for (uint256 i = 0; i < operators.length; i++) {
            mockTaskManager.callRecordValidation(manager, taskIndex, operators[i]);
        }

        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator1, 34);
        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator2, 33);
        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator3, 33);

        manager.distributeTaskReward(taskIndex, operators, quorum);
    }

    function test_DistributeTaskReward_RevertIfNotOwner() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        address[] memory operators = new address[](1);
        operators[0] = operator1;
        manager.setTaskReward(25, 10);

        vm.prank(operator1);
        vm.expectRevert("Ownable: caller is not the owner");
        manager.distributeTaskReward(25, operators, 0);
    }

    // ============ View Function Tests ============

    function test_RegistryCoordinator_ReturnsCorrectAddress() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();

        assertEq(manager.registryCoordinator(), mockRegistryCoordinator);
    }

    function test_StakeRegistry_ReturnsCorrectAddress() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();

        assertEq(manager.stakeRegistry(), mockStakeRegistry);
    }

    // ============ Edge Cases ============

    function test_DistributeTaskReward_EmptyOperatorsArray() public {
        (DarkPoolServiceManager manager,) = _deployAndInit();
        uint32 taskIndex = 30;
        manager.setTaskReward(taskIndex, 55);

        address[] memory operators = new address[](0);

        manager.distributeTaskReward(taskIndex, operators, 0);

        // reward should remain unchanged because nothing was distributed
        assertEq(manager.taskRewards(taskIndex), 55);
    }

    function test_DistributeTaskReward_SingleOperator() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 31;
        uint8 quorum = 0;
        address[] memory operators = new address[](1);
        operators[0] = operator1;

        manager.setTaskReward(taskIndex, 90);
        _mockOperator(operator1, bytes32("op1"), quorum, 2e18, 1e18);
        mockTaskManager.callRecordValidation(manager, taskIndex, operator1);

        vm.expectEmit(true, true, false, true);
        emit TaskValidationRewarded(taskIndex, operator1, 90);

        manager.distributeTaskReward(taskIndex, operators, quorum);

        assertEq(manager.taskRewards(taskIndex), 0);
    }

    function test_DistributeTaskReward_ManyOperators() public {
        (DarkPoolServiceManager manager, MockTaskManager mockTaskManager) = _deployAndInit();
        uint32 taskIndex = 32;
        uint8 quorum = 0;

        address[] memory operators = new address[](5);
        operators[0] = operator1;
        operators[1] = operator2;
        operators[2] = operator3;
        operators[3] = rewardsInitiator;
        operators[4] = owner;

        manager.setTaskReward(taskIndex, 500);
        _mockOperator(operator1, bytes32("op1"), quorum, 2e18, 1e18);
        _mockOperator(operator2, bytes32("op2"), quorum, 2e18, 1e18);
        _mockOperator(operator3, bytes32("op3"), quorum, 2e18, 1e18);
        _mockOperator(rewardsInitiator, bytes32("op4"), quorum, 2e18, 1e18);
        _mockOperator(owner, bytes32("op5"), quorum, 2e18, 1e18);

        for (uint256 i = 0; i < operators.length; i++) {
            mockTaskManager.callRecordValidation(manager, taskIndex, operators[i]);
        }

        manager.distributeTaskReward(taskIndex, operators, quorum);

        assertEq(manager.taskRewards(taskIndex), 0);
    }
}

