// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title ICrossChainBridge
/// @notice Interface for cross-chain bridge functionality
interface ICrossChainBridge {
    /// @notice Initiate a cross-chain transfer
    /// @param targetChainId The target chain ID
    /// @param recipient The recipient address on the target chain
    /// @param currency The currency to transfer
    /// @param amount The amount to transfer
    /// @param swapHash The swap hash for tracking
    function initiateCrossChainTransfer(
        uint256 targetChainId,
        address recipient,
        Currency currency,
        uint256 amount,
        bytes32 swapHash
    ) external payable;

    /// @notice Complete a cross-chain transfer (called on target chain)
    /// @param swapHash The swap hash from the source chain
    /// @param recipient The recipient address
    /// @param currency The currency to receive
    /// @param amount The amount to receive
    function completeCrossChainTransfer(
        bytes32 swapHash,
        address recipient,
        Currency currency,
        uint256 amount
    ) external;

    /// @notice Check if a cross-chain transfer is pending
    /// @param swapHash The swap hash
    /// @return Whether the transfer is pending
    function isTransferPending(bytes32 swapHash) external view returns (bool);

    /// @notice Get the bridge fee for a cross-chain transfer
    /// @param targetChainId The target chain ID
    /// @param amount The transfer amount
    /// @return The bridge fee
    function getBridgeFee(uint256 targetChainId, uint256 amount) external view returns (uint256);
}

