# CrossGuardHook

Uniswap v4 hook stack that adds privacy-preserving swaps, EigenLayer AVS-backed validation, and cross-chain swap plumbing. This README explains what the project does, how EigenLayer is integrated (with exact contract touchpoints), and how to deploy and operate it.

## Overview
CrossGuardHook is a Uniswap v4 hook stack designed to make swaps more private and verifiable while remaining chain-agnostic. It adds a commit–reveal flow to hide intent (reducing MEV), leans on EigenLayer AVS operators for batch validation and security, and provides scaffolding to hand off swap payloads across chains via a bridge adapter. The core hook (`DarkPoolHook`) intercepts swaps, enforces timing/validity, and coordinates with AVS/task managers. Companion managers (`DarkPoolServiceManager`, `DarkPoolTaskManager`) plug directly into EigenLayer middleware (AVSDirectory, Registry/Stake/Allocation managers, Rewards, PermissionController) to gate operator participation, tally responses, and emit reward events. Cross-chain support is abstracted behind `ICrossChainBridge`, keeping bridge risk isolated.

## What this project does
- **Commit–reveal swaps (MEV mitigation):** Users commit swap intent, wait a minimum block delay, then reveal to execute; the hook enforces timing and authenticity.
- **EigenLayer-secured validation:** AVS operators validate swap batches; stake-backed security and potential slashing provide economic assurances.
- **Cross-chain swap scaffolding:** The hook can emit cross-domain swap payloads via a pluggable bridge interface.

## Component map (where things live)
- `src/DarkPoolHook.sol`: Uniswap v4 `BaseHook`. Owns commit–reveal state, before/after swap hooks, and cross-chain handoff. References EigenLayer managers for validation.
- `src/DarkPoolServiceManager.sol`: Extends EigenLayer `ServiceManagerBase`. Connects to AVSDirectory, Registry/Stake/Allocation managers, Rewards, and PermissionController. Tracks task rewards and records operator validations.
- `src/DarkPoolTaskManager.sol`: Issues validation tasks, enforces quorum, and checks operator validity through `SERVICE_MANAGER.isValidOperator`.
- Interfaces: `src/interfaces/IDarkPoolServiceManager.sol`, `IDarkPoolTaskManager.sol`, `ICrossChainBridge.sol`.
- Docs: `docs/overview.md` (high-level) plus any additional integration notes.

## Where and how EigenLayer is integrated (exact touchpoints)
- **Hook references AVS managers:** `DarkPoolHook` constructor takes `IDarkPoolServiceManager` and `IDarkPoolTaskManager` and stores them as immutables. In `_beforeSwap`, it can derive a batch hash and (stub) create a validation task when AVS is configured.
- **Operator validity checks:** `DarkPoolTaskManager.respondToTask` calls `SERVICE_MANAGER.isValidOperator(msg.sender, 0)` to ensure responders are active EigenLayer operators for the quorum.
- **Service manager ↔ EigenLayer middleware:** `DarkPoolServiceManager` inherits `ServiceManagerBase` from EigenLayer middleware and wires these contracts:
  - `IAVSDirectory` for AVS registration
  - `IRegistryCoordinator` + `IStakeRegistry` for operator IDs and stake weights
  - `IAllocationManager` for stake allocations to operator sets
  - `IRewardsCoordinator` for reward distribution plumbing
  - `IPermissionController` for access control to AVS actions
  - `ISlashingRegistryCoordinator` (via base) for slashing integration
- **Stake and quorum checks:** `isValidOperator` uses `RegistryCoordinator.getOperatorId` and `StakeRegistry.getCurrentStake` vs `minimumStakeForQuorum` to gate operator participation.
- **Task validation flow:** `recordTaskValidation` is called by the task manager to log operator participation; rewards can later be computed/distributed through EigenLayer reward submission flows.
- **Reward path (simplified):** `distributeTaskReward` emits `TaskValidationRewarded` per operator; comments note where to plug into `createOperatorDirectedAVSRewardsSubmission`.
- **Slashing posture:** While on-chain slashing logic is not fully implemented here, the design expects objective faults to be enforced through EigenLayer’s slashing/coordinator stack.

## Flows
### Swap lifecycle (commit–reveal)
1) **Commit:** User calls `commitSwap` with pool params, amount, deadline, and secret. Hook stores `CommitData` keyed by hash.
2) **Wait:** Enforced `commitPeriod` (owner-set, bounded by `MIN_COMMIT_PERIOD`/`MAX_COMMIT_PERIOD`).
3) **Reveal:** User calls `revealAndSwap` with the secret; hook recomputes the hash, checks deadline and period, then marks revealed.
4) **Before-swap validation:** `_beforeSwap` ensures commit period elapsed and (optionally) derives a batch hash for AVS validation.
5) **Execute swap:** In production this would call `poolManager.swap`; the current code is a scaffold for integration.
6) **After-swap:** `_afterSwap` can initiate cross-chain handling and marks the commit as executed.

### AVS validation path
- Task creation (stubbed in hook): batch hash can be derived per committed swap set.
- Task responses: Operators call `DarkPoolTaskManager.respondToTask`, which:
  - Verifies operator via EigenLayer stake/quorum (`SERVICE_MANAGER.isValidOperator`).
  - Records response and tallies counts; when quorum is hit, emits `TaskCompleted`.
  - Notifies `SERVICE_MANAGER.recordTaskValidation` to persist operator participation.
- Rewards: Owner can set `taskRewards`; `distributeTaskReward` emits reward events (integration point for EigenLayer rewards coordinator).

### Cross-chain swap handoff
- `_afterSwap` detects encoded cross-chain payload in `hookData` and delegates to `_handleCrossChainSwap`.
- `_handleCrossChainSwap` decodes target chain, recipient, amount, computes a `swapHash`, and emits `CrossChainSwapInitiated`.
- Actual bridge call is intentionally abstracted behind `ICrossChainBridge`.

## Configuration knobs
- `commitPeriod`: set via `setCommitPeriod` (bounded 1–100 blocks).
- Pool gating: `setPoolEnabled` to allow dark-pool swaps per pool ID.
- Bridge target: `setCrossChainBridge`.
- AVS rewards: `setTaskReward` and `distributeTaskReward` on the service manager.
- Quorum thresholds: `createNewTask` takes `quorumThreshold`; operator validity tied to EigenLayer stake data.

## Deployment guide
1) **Prereqs:** Foundry, Solidity 0.8.24+, deployed Uniswap v4 `PoolManager`, EigenLayer core (DelegationManager, AVSDirectory, AllocationManager, Stake/Registry coordinators, RewardsCoordinator, PermissionController, Slasher), and a bridge implementing `ICrossChainBridge`.
2) **Deploy AVS middleware (if not reusing existing):** EigenLayer registry/ stake/ allocation infra plus slashing + rewards components.
3) **Deploy this stack:**
   - `DarkPoolTaskManager` (args: serviceManager, owner).
   - `DarkPoolServiceManager` (args: EigenLayer middleware addresses, taskManager).
   - `DarkPoolHook` (args: poolManager, serviceManager, taskManager, owner).
4) **Wire + configure:**
   - Register the AVS in `AVSDirectory`.
   - Set commit period, enable desired pools, set bridge.
   - Configure task reward amounts and quorum policy.
   - Ensure operators register/allocate stake to the AVS quorums.
5) **Dry-run:** `forge build && forge test` (optionally with `--gas-report`), then `forge script` against an Anvil fork.

## Operator onboarding (EigenLayer)
1) Register as operator: `DelegationManager.registerAsOperator(...)`.
2) Receive delegations from stakers.
3) Allocate stake to AVS operator sets: `AllocationManager.modifyAllocations(...)`.
4) After delay, register to sets: `registerForOperatorSets(...)` on `SlashingRegistryCoordinator`.
5) Keep stake fresh: call `StakeRegistry.updateOperatorsForQuorum(...)` (or use AVS-Sync if available).
6) Respond to tasks: call `respondToTask` on `DarkPoolTaskManager` with batch hash + response; meet quorum.

## Security posture
- ReentrancyGuard on externals; Ownable + Pausable for emergency control.
- Commit–reveal enforced by block-based delays to mitigate pre-trade MEV.
- Operator gating via EigenLayer stake/quorum checks; rewards/slashing rely on accurate stake updates.
- Bridge abstraction keeps chain assumptions explicit; bridge contract must be audited.

## Testing
- Unit/integration: `forge test` (covers hook/service/task managers and mocks).
- Gas: `forge test --gas-report`.
- Extend with bridge adapter edge cases and AVS signature verification once integrated.

## Repository layout
- `src/`: Core contracts (`DarkPoolHook`, `DarkPoolServiceManager`, `DarkPoolTaskManager`, interfaces).
- `test/`: Unit and integration tests; mocks for pool manager, bridge, operators.
- `docs/`: Additional docs (`overview.md`, integration guides).
- `lib/`: Dependencies (EigenLayer middleware, Uniswap v4 core/periphery, OZ, forge-std).
- `script/`: Deployment or simulation scripts (if present).

## Quick commands
- Build: `forge build`
- Test: `forge test`
- Format (if enabled): `forge fmt`

## License
MIT
