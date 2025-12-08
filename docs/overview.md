# CrossGuardHook Overview

CrossGuardHook is a Uniswap v4 hook that adds privacy-preserving swaps, EigenLayer AVS-backed validation, and cross-chain swap plumbing.

## What it does
- **Commit–reveal swaps**: Users commit swap intent, then reveal after a delay to reduce MEV/front‑running.
- **EigenLayer AVS validation**: Operators register/stake via EigenLayer and validate swap batches; misbehavior can be slashed.
- **Cross-chain support**: Hooks into a bridge interface to initiate and track swaps across chains.

## Core contracts
- `DarkPoolHook` (`src/DarkPoolHook.sol`): Main hook; commit–reveal flow, swap execution, bridge handoff.
- `DarkPoolServiceManager` (`src/DarkPoolServiceManager.sol`): Tracks operators, staking, slashing parameters, and rewards.
- `DarkPoolTaskManager` (`src/DarkPoolTaskManager.sol`): Issues validation tasks to operators, collects quorum responses.
- Interfaces: `IDarkPoolServiceManager`, `IDarkPoolTaskManager`, `ICrossChainBridge`, `ICommitReveal`.

## Key flows
- **Swap lifecycle**: commit → wait commit period → reveal → hook executes swap (after AVS validation).
- **Operator lifecycle**: register & stake via EigenLayer → allocate stake to AVS → register for operator sets/quorums → respond to tasks → can be slashed for faults.
- **Cross-chain**: swap intent is recorded and bridged via `ICrossChainBridge`; hook tracks swap hashes for finalization.

## Defaults and configuration
- Commit period: owner-settable (defaults set in tests; min 1 block, max 100).
- Operator requirements: min stake (e.g., 1 ETH), quorum thresholds, slashing percentage (cap ~10%) configured in `DarkPoolServiceManager`.
- Access control: Ownable + Pausable; ReentrancyGuard on externals.

## Build, test, deploy
- Build: `forge build`
- Test: `forge test`
- Deploy (constructor args):
  - `DarkPoolHook`: poolManager, serviceManager, taskManager, owner
  - `DarkPoolServiceManager`: taskManager, owner, slashingPercentage (bps)
  - `DarkPoolTaskManager`: serviceManager, owner

