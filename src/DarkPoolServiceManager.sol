// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {ServiceManagerBase} from "eigenlayer-middleware/ServiceManagerBase.sol";
import {IServiceManager} from "eigenlayer-middleware/interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "eigenlayer-middleware/interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {ISlashingRegistryCoordinator} from "eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IDarkPoolTaskManager} from "./interfaces/IDarkPoolTaskManager.sol";

/// @title DarkPoolServiceManager
/// @notice EigenLayer AVS Service Manager for DarkPool Hook
/// @dev Extends EigenLayer's ServiceManagerBase for direct integration
contract DarkPoolServiceManager is ServiceManagerBase {
    /// @notice Task manager contract
    IDarkPoolTaskManager public immutable TASK_MANAGER;

    /// @notice Mapping of task index to reward amount
    mapping(uint32 => uint256) public taskRewards;

    /// @notice Mapping of task index to operator to whether they validated correctly
    mapping(uint32 => mapping(address => bool)) public taskValidations;

    /// @notice Events
    event TaskValidationRewarded(uint32 indexed taskIndex, address indexed operator, uint256 reward);
    event TaskRewardSet(uint32 indexed taskIndex, uint256 rewardAmount);

    /// @notice Errors
    error TaskRewardNotSet();
    error InvalidOperator();
    error AlreadyValidated();
    error OnlyTaskManager();

    /// @notice Constructor
    /// @param _avsDirectory EigenLayer AVS Directory contract
    /// @param _rewardsCoordinator EigenLayer Rewards Coordinator contract
    /// @param _registryCoordinator EigenLayer Registry Coordinator contract
    /// @param _stakeRegistry EigenLayer Stake Registry contract
    /// @param _permissionController EigenLayer Permission Controller contract
    /// @param _allocationManager EigenLayer Allocation Manager contract
    /// @param _taskManager The task manager contract
    constructor(
        IAVSDirectory _avsDirectory,
        IRewardsCoordinator _rewardsCoordinator,
        ISlashingRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        IPermissionController _permissionController,
        IAllocationManager _allocationManager,
        IDarkPoolTaskManager _taskManager
    )
        ServiceManagerBase(
            _avsDirectory,
            _rewardsCoordinator,
            _registryCoordinator,
            _stakeRegistry,
            _permissionController,
            _allocationManager
        )
    {
        TASK_MANAGER = _taskManager;
    }

    /// @notice Initialize the contract
    /// @param initialOwner The initial owner of the contract
    /// @param _rewardsInitiator The address that can initiate rewards
    function initialize(address initialOwner, address _rewardsInitiator) external initializer {
        __ServiceManagerBase_init(initialOwner, _rewardsInitiator);
    }

    /// @notice Check if an address is a valid operator registered with EigenLayer
    /// @param operator The operator address to check
    /// @param quorumNumber The quorum number to check (0 for first quorum)
    /// @return Whether the address is a valid operator
    function isValidOperator(address operator, uint8 quorumNumber) external view returns (bool) {
        IRegistryCoordinator regCoordinator = IRegistryCoordinator(address(_registryCoordinator));

        // Get operator ID from registry coordinator
        bytes32 operatorId = regCoordinator.getOperatorId(operator);

        // Check if operator has stake in the quorum
        uint96 stake = _stakeRegistry.getCurrentStake(operatorId, quorumNumber);
        uint96 minimumStake = _stakeRegistry.minimumStakeForQuorum(quorumNumber);

        return stake >= minimumStake;
    }

    /// @notice Get operator stake amount from EigenLayer
    /// @param operator The operator address
    /// @param quorumNumber The quorum number
    /// @return The stake amount
    function getOperatorStake(address operator, uint8 quorumNumber) external view returns (uint96) {
        IRegistryCoordinator regCoordinator = IRegistryCoordinator(address(_registryCoordinator));
        bytes32 operatorId = regCoordinator.getOperatorId(operator);
        return _stakeRegistry.getCurrentStake(operatorId, quorumNumber);
    }

    /// @notice Record task validation by operator
    /// @param taskIndex The task index
    /// @param operator The operator address
    function recordTaskValidation(uint32 taskIndex, address operator) external {
        if (msg.sender != address(TASK_MANAGER)) {
            revert OnlyTaskManager();
        }

        // Verify operator is registered with EigenLayer
        IRegistryCoordinator regCoordinator = IRegistryCoordinator(address(_registryCoordinator));
        bytes32 operatorId = regCoordinator.getOperatorId(operator);

        // Check if operator is registered (has non-zero operatorId)
        if (operatorId == bytes32(0)) {
            revert InvalidOperator();
        }

        if (taskValidations[taskIndex][operator]) {
            revert AlreadyValidated();
        }

        taskValidations[taskIndex][operator] = true;
    }

    /// @notice Set reward amount for a task
    /// @param taskIndex The task index
    /// @param rewardAmount The reward amount
    function setTaskReward(uint32 taskIndex, uint256 rewardAmount) external onlyOwner {
        taskRewards[taskIndex] = rewardAmount;
        emit TaskRewardSet(taskIndex, rewardAmount);
    }

    /// @notice Distribute rewards to operators who validated tasks correctly
    /// @param taskIndex The task index
    /// @param validOperators Array of operators who validated correctly
    /// @param quorumNumber The quorum number for stake checking
    function distributeTaskReward(uint32 taskIndex, address[] calldata validOperators, uint8 quorumNumber)
        external
        onlyOwner
    {
        uint256 reward = taskRewards[taskIndex];

        if (reward == 0) {
            revert TaskRewardNotSet();
        }

        if (validOperators.length == 0) {
            return;
        }

        // Prepare operator-directed rewards submission for EigenLayer
        // This will be distributed through EigenLayer's rewards coordinator
        // For now, we'll use a simplified approach - in production, you'd use createOperatorDirectedAVSRewardsSubmission

        uint256 rewardPerOperator = reward / validOperators.length;
        uint256 remainder = reward % validOperators.length;

        // Verify each operator and record validation
        for (uint256 i = 0; i < validOperators.length; i++) {
            address operator = validOperators[i];

            if (!taskValidations[taskIndex][operator]) {
                continue;
            }

            // Verify operator is still valid
            if (!this.isValidOperator(operator, quorumNumber)) {
                continue;
            }

            uint256 operatorReward = rewardPerOperator;
            if (i == 0) {
                operatorReward += remainder; // Give remainder to first operator
            }

            emit TaskValidationRewarded(taskIndex, operator, operatorReward);
        }

        // Clear the reward
        taskRewards[taskIndex] = 0;
    }

    /// @notice Get the registry coordinator address
    /// @return The registry coordinator contract
    function registryCoordinator() external view returns (address) {
        return address(_registryCoordinator);
    }

    /// @notice Get the stake registry address
    /// @return The stake registry contract
    function stakeRegistry() external view returns (address) {
        return address(_stakeRegistry);
    }
}
