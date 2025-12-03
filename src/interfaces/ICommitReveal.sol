// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @title ICommitReveal
/// @notice Interface for commit-reveal scheme implementation
interface ICommitReveal {
    /// @notice Commit data structure
    struct CommitData {
        address user;
        PoolId poolId;
        uint256 amountIn;
        Currency currencyIn;
        Currency currencyOut;
        uint256 deadline;
        uint256 commitBlock;
        bool revealed;
        bool executed;
    }

    /// @notice Commit a swap order
    /// @param poolKey The pool key
    /// @param amountIn The input amount
    /// @param currencyIn The input currency
    /// @param currencyOut The output currency
    /// @param deadline The deadline
    /// @param secret The secret for commit-reveal
    /// @return commitHash The hash of the committed swap
    function commitSwap(
        PoolKey calldata poolKey,
        uint256 amountIn,
        Currency currencyIn,
        Currency currencyOut,
        uint256 deadline,
        bytes32 secret
    ) external returns (bytes32 commitHash);

    /// @notice Get commit data
    /// @param commitHash The commit hash
    /// @return The commit data
    function getCommit(bytes32 commitHash) external view returns (CommitData memory);

    /// @notice Check if commit period has elapsed
    /// @param commitHash The commit hash
    /// @return Whether the commit period has elapsed
    function isCommitPeriodElapsed(bytes32 commitHash) external view returns (bool);
}

