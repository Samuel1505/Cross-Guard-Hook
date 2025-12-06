// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICrossChainBridge} from "../../src/interfaces/ICrossChainBridge.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title MockBridge
/// @notice Mock implementation of ICrossChainBridge for testing
contract MockBridge is ICrossChainBridge {
    mapping(bytes32 => bool) public pendingTransfers;
    mapping(uint256 => uint256) public bridgeFees; // chainId => fee

    function initiateCrossChainTransfer(
        uint256 targetChainId,
        address recipient,
        Currency currency,
        uint256 amount,
        bytes32 swapHash
    ) external payable {
        pendingTransfers[swapHash] = true;
    }

    function completeCrossChainTransfer(bytes32 swapHash, address recipient, Currency currency, uint256 amount)
        external
    {
        pendingTransfers[swapHash] = false;
    }

    function isTransferPending(bytes32 swapHash) external view returns (bool) {
        return pendingTransfers[swapHash];
    }

    function getBridgeFee(uint256 targetChainId, uint256 amount) external view returns (uint256) {
        return bridgeFees[targetChainId];
    }

    function setBridgeFee(uint256 chainId, uint256 fee) external {
        bridgeFees[chainId] = fee;
    }
}

