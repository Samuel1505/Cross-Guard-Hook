// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IDarkPoolServiceManager} from "./interfaces/IDarkPoolServiceManager.sol";
import {IDarkPoolTaskManager} from "./interfaces/IDarkPoolTaskManager.sol";

/// @title DarkPoolServiceManager
/// @notice Manages EigenLayer AVS operators, staking, slashing, and rewards
/// @dev Implements the service manager interface for EigenLayer integration
contract DarkPoolServiceManager is IDarkPoolServiceManager, ReentrancyGuard, Ownable, Pausable {
    /// @notice Minimum stake required to become an operator
    uint256 public constant MIN_STAKE = 1 ether;
    
    /// @notice Maximum slashing percentage (basis points, 10000 = 100%)
    uint256 public constant MAX_SLASH_BPS = 1000; // 10%
    
    /// @notice Task manager contract
    IDarkPoolTaskManager public immutable TASK_MANAGER;

    /// @notice Mapping of operator address to their stake
    mapping(address => uint256) public operatorStake;
    
    /// @notice Mapping of operator address to whether they are registered
    mapping(address => bool) public isOperator;
    
    /// @notice Mapping of task index to reward amount
    mapping(uint32 => uint256) public taskRewards;
    
    /// @notice Mapping of task index to operator to whether they validated correctly
    mapping(uint32 => mapping(address => bool)) public taskValidations;
    
    /// @notice Total staked amount across all operators
    uint256 public totalStaked;
    
    /// @notice Total slashed amount
    uint256 public totalSlashed;
    
    /// @notice Slashing percentage (basis points)
    uint256 public slashingPercentage;

    /// @notice Errors
    error InsufficientStake();
    error NotAnOperator();
    error AlreadyRegistered();
    error InvalidSlashPercentage();
    error TaskRewardNotSet();
    error AlreadyValidated();
    error InvalidOperator();

    /// @notice Constructor
    /// @param _taskManager The task manager contract
    /// @param _owner The owner of the contract
    /// @param _slashingPercentage Initial slashing percentage in basis points
    constructor(
        IDarkPoolTaskManager _taskManager,
        address _owner,
        uint256 _slashingPercentage
    ) Ownable(_owner) {
        TASK_MANAGER = _taskManager;
        if (_slashingPercentage > MAX_SLASH_BPS) {
            revert InvalidSlashPercentage();
        }
        slashingPercentage = _slashingPercentage;
    }

    /// @notice Register as an operator with minimum stake
    function registerOperator() external payable whenNotPaused {
        if (isOperator[msg.sender]) {
            revert AlreadyRegistered();
        }
        
        if (msg.value < MIN_STAKE) {
            revert InsufficientStake();
        }

        isOperator[msg.sender] = true;
        operatorStake[msg.sender] = msg.value;
        totalStaked += msg.value;

        emit OperatorRegistered(msg.sender, msg.value);
    }

    /// @notice Deregister operator and return stake
    function deregisterOperator() external nonReentrant whenNotPaused {
        if (!isOperator[msg.sender]) {
            revert NotAnOperator();
        }

        uint256 stake = operatorStake[msg.sender];
        operatorStake[msg.sender] = 0;
        isOperator[msg.sender] = false;
        totalStaked -= stake;

        // Return stake to operator
        (bool success, ) = payable(msg.sender).call{value: stake}("");
        require(success, "Transfer failed");

        emit OperatorDeregistered(msg.sender);
    }

    /// @notice Add more stake to existing registration
    function addStake() external payable whenNotPaused {
        if (!isOperator[msg.sender]) {
            revert NotAnOperator();
        }

        operatorStake[msg.sender] += msg.value;
        totalStaked += msg.value;

        emit StakeUpdated(msg.sender, operatorStake[msg.sender]);
    }

    /// @notice Check if an address is a valid operator
    /// @param operator The operator address to check
    /// @return Whether the address is a valid operator
    function isValidOperator(address operator) external view override returns (bool) {
        return isOperator[operator] && operatorStake[operator] >= MIN_STAKE;
    }

    /// @notice Get operator stake amount
    /// @param operator The operator address
    /// @return The stake amount
    function getOperatorStake(address operator) external view override returns (uint256) {
        return operatorStake[operator];
    }

    /// @notice Record task validation by operator
    /// @param taskIndex The task index
    /// @param operator The operator address
    function recordTaskValidation(uint32 taskIndex, address operator) external override {
        if (msg.sender != address(TASK_MANAGER)) {
            revert InvalidOperator();
        }
        
        if (!isOperator[operator]) {
            revert NotAnOperator();
        }
        
        if (taskValidations[taskIndex][operator]) {
            revert AlreadyValidated();
        }

        taskValidations[taskIndex][operator] = true;
    }

    /// @notice Set reward amount for a task
    /// @param taskIndex The task index
    /// @param rewardAmount The reward amount
    function setTaskReward(uint32 taskIndex, uint256 rewardAmount) external payable override onlyOwner {
        if (msg.value != rewardAmount) {
            revert("Value mismatch");
        }
        
        taskRewards[taskIndex] = rewardAmount;
    }

    /// @notice Distribute rewards to operators who validated tasks correctly
    /// @param taskIndex The task index
    /// @param validOperators Array of operators who validated correctly
    function distributeTaskReward(
        uint32 taskIndex,
        address[] calldata validOperators
    ) external override nonReentrant onlyOwner {
        uint256 reward = taskRewards[taskIndex];
        
        if (reward == 0) {
            revert TaskRewardNotSet();
        }

        if (validOperators.length == 0) {
            return;
        }

        uint256 rewardPerOperator = reward / validOperators.length;
        uint256 remainder = reward % validOperators.length;

        for (uint256 i = 0; i < validOperators.length; i++) {
            address operator = validOperators[i];
            
            if (!taskValidations[taskIndex][operator]) {
                continue;
            }

            uint256 operatorReward = rewardPerOperator;
            if (i == 0) {
                operatorReward += remainder; // Give remainder to first operator
            }

            (bool success, ) = payable(operator).call{value: operatorReward}("");
            require(success, "Reward transfer failed");

            emit TaskValidationRewarded(taskIndex, operator, operatorReward);
        }

        // Clear the reward
        taskRewards[taskIndex] = 0;
    }

    /// @notice Slash an operator for misbehavior
    /// @param operator The operator to slash
    /// @param amount The amount to slash
    function slashOperator(address operator, uint256 amount) external onlyOwner {
        if (!isOperator[operator]) {
            revert NotAnOperator();
        }

        uint256 stake = operatorStake[operator];
        uint256 slashAmount = amount > stake ? stake : amount;
        
        // Calculate slashing based on percentage
        uint256 slashByPercentage = (stake * slashingPercentage) / 10000;
        uint256 finalSlash = slashAmount > slashByPercentage ? slashByPercentage : slashAmount;

        operatorStake[operator] -= finalSlash;
        totalStaked -= finalSlash;
        totalSlashed += finalSlash;

        // If stake falls below minimum, deregister
        if (operatorStake[operator] < MIN_STAKE) {
            isOperator[operator] = false;
            emit OperatorDeregistered(operator);
        }

        emit OperatorSlashed(operator, finalSlash);
    }

    /// @notice Set the slashing percentage
    /// @param newPercentage The new slashing percentage in basis points
    function setSlashingPercentage(uint256 newPercentage) external onlyOwner {
        if (newPercentage > MAX_SLASH_BPS) {
            revert InvalidSlashPercentage();
        }
        slashingPercentage = newPercentage;
    }

    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Withdraw contract balance (only slashed funds)
    /// @param to The address to withdraw to
    /// @param amount The amount to withdraw
    function withdrawSlashedFunds(address to, uint256 amount) external onlyOwner {
        require(amount <= totalSlashed, "Insufficient slashed funds");
        totalSlashed -= amount;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Withdraw failed");
    }

    /// @notice Receive function to accept ETH
    receive() external payable {}
}

