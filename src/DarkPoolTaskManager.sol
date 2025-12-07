// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IDarkPoolTaskManager} from "./interfaces/IDarkPoolTaskManager.sol";
import {IDarkPoolServiceManager} from "./interfaces/IDarkPoolServiceManager.sol";

/// @title DarkPoolTaskManager
/// @notice Manages validation tasks for EigenLayer AVS operators
/// @dev Handles task creation, responses, and quorum validation
contract DarkPoolTaskManager is IDarkPoolTaskManager, ReentrancyGuard, Ownable, Pausable {
    /// @notice Service manager contract
    IDarkPoolServiceManager public immutable SERVICE_MANAGER;

    /// @notice Latest task number
    uint32 private _latestTaskNum;

    /// @notice Mapping of task index to task data
    mapping(uint32 => Task) public tasks;

    /// @notice Mapping of task index to operator to response
    mapping(uint32 => mapping(address => bytes32)) public taskResponses;

    /// @notice Mapping of task index to response hash to count
    mapping(uint32 => mapping(bytes32 => uint256)) public responseCounts;

    /// @notice Mapping of task index to operator to whether they have responded
    mapping(uint32 => mapping(address => bool)) private _hasResponded;

    /// @notice Mapping of task index to whether it was force-completed
    mapping(uint32 => bool) private _isForceCompleted;

    /// @notice Minimum quorum threshold
    uint32 public constant MIN_QUORUM_THRESHOLD = 1;

    /// @notice Maximum quorum threshold
    uint32 public constant MAX_QUORUM_THRESHOLD = 100;

    /// @notice Errors
    error InvalidQuorumThreshold();
    error TaskNotFound();
    error TaskAlreadyCompleted();
    error InvalidSignature();
    error OperatorNotValid();
    error DuplicateResponse();
    error QuorumNotReached();

    /// @notice Constructor
    /// @param _serviceManager The service manager contract
    /// @param _owner The owner of the contract
    constructor(IDarkPoolServiceManager _serviceManager, address _owner) Ownable(_owner) {
        SERVICE_MANAGER = _serviceManager;
    }

    /// @notice Create a new task for batch validation
    /// @param batchHash The hash of the batch to validate
    /// @param quorumThreshold The minimum number of responses needed
    /// @param quorumNumbers The quorum numbers (for EigenLayer compatibility)
    function createNewTask(bytes32 batchHash, uint32 quorumThreshold, bytes calldata quorumNumbers)
        external
        override
        whenNotPaused
    {
        if (quorumThreshold < MIN_QUORUM_THRESHOLD || quorumThreshold > MAX_QUORUM_THRESHOLD) {
            revert InvalidQuorumThreshold();
        }

        uint32 taskIndex = _latestTaskNum++;

        tasks[taskIndex] = Task({
            batchHash: batchHash,
            quorumThreshold: quorumThreshold,
            quorumNumbers: quorumNumbers,
            createdBlock: uint256(block.number),
            creator: msg.sender,
            isCompleted: false
        });

        emit TaskCreated(taskIndex, batchHash, msg.sender);
    }

    /// @notice Respond to a task with signature
    /// @param batchHash The batch hash (for verification)
    /// @param response The response hash
    function respondToTask(
        bytes32 batchHash,
        bytes32 response,
        bytes calldata /* signature - reserved for future EIP-712 implementation */
    )
        external
        override
        nonReentrant
        whenNotPaused
    {
        // First, try to find any task with this batch hash (including completed ones)
        uint32 taskIndex = _findTaskByBatchHash(batchHash, false);

        if (taskIndex == type(uint32).max) {
            revert TaskNotFound();
        }

        Task storage task = tasks[taskIndex];

        // Check if task was force-completed (block responses for force-completed tasks)
        if (_isForceCompleted[taskIndex]) {
            revert TaskAlreadyCompleted();
        }

        // Verify operator is valid through EigenLayer (check quorum 0 by default)
        if (!SERVICE_MANAGER.isValidOperator(msg.sender, 0)) {
            revert OperatorNotValid();
        }

        // Check if operator already responded (works even if response is bytes32(0))
        if (_hasResponded[taskIndex][msg.sender]) {
            revert DuplicateResponse();
        }

        // Verify signature (simplified - in production, use EIP-712)
        // For now, we'll just record the response
        // In production, you'd verify: keccak256(abi.encodePacked(batchHash, response)) signed by operator

        // Record response
        taskResponses[taskIndex][msg.sender] = response;
        _hasResponded[taskIndex][msg.sender] = true;
        responseCounts[taskIndex][response]++;

        // Notify service manager
        SERVICE_MANAGER.recordTaskValidation(taskIndex, msg.sender);

        emit TaskResponded(taskIndex, msg.sender, response);

        // Check if quorum is reached
        if (responseCounts[taskIndex][response] >= task.quorumThreshold) {
            task.isCompleted = true;
            emit TaskCompleted(taskIndex, response);
        }
    }

    /// @notice Get the latest task number
    /// @return The latest task number
    function latestTaskNum() external view override returns (uint32) {
        return _latestTaskNum;
    }

    /// @notice Get task details by index
    /// @param taskIndex The task index
    /// @return The task data
    function getTask(uint32 taskIndex) external view override returns (Task memory) {
        return tasks[taskIndex];
    }

    /// @notice Get task response count for a specific response
    /// @param taskIndex The task index
    /// @param response The response hash
    /// @return The count of operators who provided this response
    function getResponseCount(uint32 taskIndex, bytes32 response) external view returns (uint256) {
        return responseCounts[taskIndex][response];
    }

    /// @notice Check if quorum is reached for a task
    /// @param taskIndex The task index
    /// @param response The response to check
    /// @return Whether quorum is reached
    function isQuorumReached(uint32 taskIndex, bytes32 response) external view returns (bool) {
        Task memory task = tasks[taskIndex];
        if (task.creator == address(0)) {
            return false;
        }
        return responseCounts[taskIndex][response] >= task.quorumThreshold;
    }

    /// @notice Find task index by batch hash
    /// @param batchHash The batch hash to search for
    /// @param requireIncomplete If true, only return incomplete tasks
    /// @return The task index, or type(uint32).max if not found
    function _findTaskByBatchHash(bytes32 batchHash, bool requireIncomplete) internal view returns (uint32) {
        // Linear search through recent tasks (in production, use a mapping)
        // For efficiency, we'll search backwards from _latestTaskNum
        for (uint32 i = _latestTaskNum; i > 0; i--) {
            uint32 taskIndex = i - 1;
            if (tasks[taskIndex].batchHash == batchHash) {
                if (requireIncomplete && tasks[taskIndex].isCompleted) {
                    continue; // Skip completed tasks if we require incomplete
                }
                return taskIndex;
            }
        }
        return type(uint32).max;
    }

    /// @notice Force complete a task (admin function)
    /// @param taskIndex The task index
    /// @param response The response to mark as complete
    function forceCompleteTask(uint32 taskIndex, bytes32 response) external onlyOwner {
        Task storage task = tasks[taskIndex];
        if (task.creator == address(0)) {
            revert TaskNotFound();
        }
        if (task.isCompleted) {
            revert TaskAlreadyCompleted();
        }

        task.isCompleted = true;
        _isForceCompleted[taskIndex] = true;
        emit TaskCompleted(taskIndex, response);
    }

    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }
}
