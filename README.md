# CrossGuardHook - Uniswap V4 Hook with EigenLayer AVS Integration

A sophisticated Uniswap V4 hook contract that extends the base BaseHook from V4 periphery, integrating EigenLayer's Actively Validated Services (AVS) for staking and slashing, while adding privacy-focused order execution (to mitigate MEV attacks) and simplified cross-chain swap functionality.

## Features

### 🔒 Privacy-Focused Order Execution (Commit-Reveal Scheme)
- **MEV Protection**: Implements a commit-reveal scheme to prevent front-running and MEV attacks
- Users commit their swap intentions with a secret hash
- After a configurable commit period, users reveal and execute their swaps
- This prevents MEV bots from seeing and front-running trades

### ⛓️ EigenLayer AVS Integration
- **Operator Staking**: Operators can register with minimum stake requirements
- **Task Validation**: Operators validate swap batches through quorum-based consensus
- **Slashing Mechanism**: Misbehaving operators can be slashed
- **Reward Distribution**: Operators receive rewards for correct validations

### 🌐 Cross-Chain Swap Functionality
- Simplified cross-chain swap execution
- Bridge integration interface for seamless cross-chain transfers
- Swap hash tracking for cross-chain operations

### 🛡️ Security Features
- Reentrancy guards on all external functions
- Access control with Ownable pattern
- Pausable contracts for emergency situations
- Input validation and bounds checking

## Contract Architecture

### Core Contracts

1. **DarkPoolHook** (`src/DarkPoolHook.sol`)
   - Main hook contract extending BaseHook
   - Implements commit-reveal scheme for privacy
   - Handles cross-chain swap initiation
   - Integrates with service and task managers

2. **DarkPoolServiceManager** (`src/DarkPoolServiceManager.sol`)
   - Manages EigenLayer AVS operators
   - Handles staking, slashing, and rewards
   - Tracks operator registrations and validations

3. **DarkPoolTaskManager** (`src/DarkPoolTakManager.sol`)
   - Manages validation tasks for operators
   - Implements quorum-based validation
   - Tracks task responses and completion

### Interfaces

- **IDarkPoolServiceManager** - Service manager interface
- **IDarkPoolTaskManager** - Task manager interface
- **ICrossChainBridge** - Cross-chain bridge interface
- **ICommitReveal** - Commit-reveal scheme interface

## Usage

### 1. Commit a Swap

```solidity
bytes32 secret = keccak256(abi.encodePacked("my-secret", block.timestamp));
bytes32 commitHash = darkPoolHook.commitSwap(
    poolKey,
    amountIn,
    currencyIn,
    currencyOut,
    deadline,
    secret
);
```

### 2. Reveal and Execute Swap

```solidity
darkPoolHook.revealAndSwap(
    commitHash,
    secret,
    poolKey,
    swapParams,
    hookData
);
```

### 3. Register as Operator

```solidity
serviceManager.registerOperator{value: minStake}();
```

### 4. Respond to Validation Task

```solidity
taskManager.respondToTask(
    batchHash,
    response,
    signature
);
```

## Configuration

### Commit Period
- Default: 5 blocks
- Minimum: 1 block
- Maximum: 100 blocks
- Configurable by owner via `setCommitPeriod()`

### Operator Requirements
- Minimum stake: 1 ETH
- Slashing percentage: Configurable (max 10%)
- Quorum threshold: 1-100 operators

## Security Considerations

1. **Reentrancy Protection**: All external functions use ReentrancyGuard
2. **Access Control**: Critical functions are protected with Ownable
3. **Input Validation**: All inputs are validated before processing
4. **Commit Period**: Prevents immediate execution to protect against MEV
5. **Quorum Validation**: Requires multiple operators to validate tasks

## Development

### Prerequisites
- Foundry
- Solidity 0.8.24+

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

The contracts require the following constructor parameters:

**DarkPoolHook:**
- `_poolManager`: IPoolManager address
- `_serviceManager`: IDarkPoolServiceManager address
- `_taskManager`: IDarkPoolTaskManager address
- `_owner`: Owner address

**DarkPoolServiceManager:**
- `_taskManager`: IDarkPoolTaskManager address
- `_owner`: Owner address
- `_slashingPercentage`: Initial slashing percentage (basis points)

**DarkPoolTaskManager:**
- `_serviceManager`: IDarkPoolServiceManager address
- `_owner`: Owner address

## License

MIT
