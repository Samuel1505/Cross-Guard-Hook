// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDarkPoolServiceManager} from "../../src/interfaces/IDarkPoolServiceManager.sol";

/// @title MockServiceManager
/// @notice Mock implementation of IDarkPoolServiceManager for testing
contract MockServiceManager is IDarkPoolServiceManager {
    mapping(address => bool) public validOperators;
    mapping(address => uint96) public operatorStakes;
    mapping(uint32 => mapping(address => bool)) public taskValidations;
    mapping(uint32 => uint256) public taskRewards;
    uint96 public constant MIN_STAKE = 1e18;

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function registerOperator() external payable {
        validOperators[msg.sender] = true;
        operatorStakes[msg.sender] = uint96(msg.value);
        emit OperatorRegistered(msg.sender, msg.value);
    }

    function deregisterOperator() external {
        validOperators[msg.sender] = false;
        uint96 stake = operatorStakes[msg.sender];
        operatorStakes[msg.sender] = 0;
        payable(msg.sender).transfer(stake);
        emit OperatorDeregistered(msg.sender);
    }

    function addStake() external payable {
        operatorStakes[msg.sender] += uint96(msg.value);
        emit StakeUpdated(msg.sender, operatorStakes[msg.sender]);
    }

    function isValidOperator(address operator, uint8) external view returns (bool) {
        return validOperators[operator] && operatorStakes[operator] >= MIN_STAKE;
    }

    function getOperatorStake(address operator, uint8) external view returns (uint96) {
        return operatorStakes[operator];
    }

    function recordTaskValidation(uint32 taskIndex, address operator) external {
        taskValidations[taskIndex][operator] = true;
    }

    function setTaskReward(uint32 taskIndex, uint256 rewardAmount) external payable {
        require(msg.sender == owner, "Not owner");
        taskRewards[taskIndex] = rewardAmount;
    }

    function distributeTaskReward(uint32 taskIndex, address[] calldata operators) external {
        // Mock implementation
    }

    function setValidOperator(address operator, bool valid) external {
        validOperators[operator] = valid;
    }

    function setOperatorStake(address operator, uint96 stake) external {
        operatorStakes[operator] = stake;
    }
}

