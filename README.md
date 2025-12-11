# CrossGuardHook

Uniswap v4 hook that adds privacy-preserving swaps, EigenLayer AVS validation, and cross-chain swap plumbing. This README gives a deep overview, flows, deployment, and operational guidance.

## Motivation
- **MEV mitigation for swaps:** Commit–reveal hides intent until execution.
- **Economic security via EigenLayer:** AVS operators validate batches; slashable stake backs correctness.
- **Interoperability:** Hooks into bridges for cross-chain swap finality and tracking.

## High-level architecture
- **Uniswap v4 Hook:** Extends BaseHook to intercept swaps and enforce commit–reveal plus AVS checks.
- **EigenLayer AVS middleware:** Service/task managers interface with EigenLayer operator sets, registries, and slashing.
- **Bridge adapter:** Pluggable `ICrossChainBridge` to send/track swap data across chains.

## Core contracts
- `DarkPoolHook` (`src/DarkPoolHook.sol`): Main hook; commit–reveal, swap execution, bridge initiation, references service/task managers.
- `DarkPoolServiceManager` (`src/DarkPoolServiceManager.sol`): Tracks operators, staking, slashing %, reward logic; interfaces to EigenLayer middleware.
- `DarkPoolTaskManager` (`src/DarkPoolTaskManager.sol`): Emits validation tasks, enforces quorum responses, integrates with signature verification.
- Interfaces: `IDarkPoolServiceManager`, `IDarkPoolTaskManager`, `ICrossChainBridge`, `ICommitReveal`.

## Key flows
### Swap lifecycle (MEV-resistant)
1) **Commit:** User submits secret hash with pool params and deadline via `commitSwap`.
2) **Waiting period:** Enforced commit period prevents instant reveal/front‑run.
3) **Reveal:** User calls `revealAndSwap` with secret and swap params.
4) **Validation:** Task manager requests operator signatures; quorum verified.
5) **Execution:** Hook performs swap; may trigger bridge if cross-chain.

### Operator lifecycle (EigenLayer-backed)
1) Operator registers in EigenLayer core (`DelegationManager.registerAsOperator`); stakers delegate.
2) Operator allocates stake to AVS operator sets (`modifyAllocations` on AllocationManager).
3) After allocation delay, operator registers to sets (`registerForOperatorSets` on SlashingRegistryCoordinator).
4) Task responses are signed; incorrect behavior can be slashed via slasher contract.

### Cross-chain swap flow
- Hook records swap hash and calls `ICrossChainBridge` to relay payload.
- Remote domain can verify/replay with stored hash; finalization is tracked in hook state.

## Configuration
- **Commit period:** Owner-set; suggested 1–100 blocks. Function: `setCommitPeriod`.
- **Slashing percentage:** Set in `DarkPoolServiceManager`; cap typically <=10% (bps).
- **Quorum size/thresholds:** Managed in task/service managers + EigenLayer registries.
- **Min stake:** Enforced via service manager when registering operators.
- **Access control:** Ownable + Pausable; ReentrancyGuard on external entrypoints.

## Deployment guide
1) **Prereqs:** Foundry installed; Solidity 0.8.24+; access to Uniswap v4 `PoolManager`; deployed EigenLayer core (DelegationManager, AllocationManager, AVSDirectory) on target network; chosen bridge adapter implementing `ICrossChainBridge`.
2) **Deploy middleware (if not reusing):** `ServiceManagerBase`, `RegistryCoordinator`/`SlashingRegistryCoordinator`, registries (`StakeRegistry`, `BLSApkRegistry`, `IndexRegistry`), signature checker (`BLSSignatureChecker`), slasher (`VetoableSlasher` recommended).
3) **Deploy CrossGuardHook stack:**
   - `DarkPoolTaskManager` (args: serviceManager, owner).
   - `DarkPoolServiceManager` (args: taskManager, owner, slashingPercentage bps).
   - `DarkPoolHook` (args: poolManager, serviceManager, taskManager, owner).
4) **Wire permissions/config:**
   - Set commit period on hook.
   - Configure slashing %, quorum thresholds, min stake on service manager.
   - Point service/task managers to EigenLayer middleware addresses (registrar, slasher, signature checker).
5) **Dry run:** `forge script ...` or local anvil fork to validate constructor wiring.

## Operator onboarding (EigenLayer)
1) Register to EigenLayer core: `DelegationManager.registerAsOperator(...)`.
2) Stakers delegate stake to operator.
3) Allocate stake to AVS sets: `AllocationManager.modifyAllocations(...)` (operator set IDs + strategy weights).
4) After allocation delay, register to AVS: `registerForOperatorSets(...)` on `SlashingRegistryCoordinator` (IAVSRegistrar).
5) Keep stake data fresh: AVS (or AVS-Sync) calls `StakeRegistry.updateOperatorsForQuorum(...)`.

## Cross-chain integration
- Implement `ICrossChainBridge` to emit/relay swap payloads.
- Store and verify swap hashes on both domains to prevent replays.
- Ensure reveal timing on source chain aligns with bridge finality on destination.

## Security model
- **Reentrancy protection:** All externals use ReentrancyGuard.
- **Ownable + pause:** Owner can pause in emergencies.
- **Objective slashing:** Faults must be objectively attributable (invalid sigs, double execution).
- **Commit–reveal:** Prevents pre-trade visibility to MEV bots; enforce non-zero commit period.
- **Stake freshness:** Regular `updateOperatorsForQuorum` calls avoid stale weights for rewards/slashing.
- **Bridge risk:** Bridge adapter must be audited; cross-chain assumptions kept explicit.

## Testing
- Unit/integration: `forge test` (see `test/unit` for coverage of hook/service/task managers).
- Fuzzing: Foundry fuzz targets included; extend for bridge adapter edge cases.
- Gas: Use `forge test --gas-report` for hot paths (commit/reveal, task responses).

## Repository layout
- `src/`: Core contracts (`DarkPoolHook`, `DarkPoolServiceManager`, `DarkPoolTaskManager`, interfaces).
- `test/`: Unit and integration tests; mocks for pool manager, bridge, operators.
- `docs/`: Project docs (`overview.md`, `integration-guide.md`).
- `lib/`: Dependencies (EigenLayer middleware, Uniswap v4 core/periphery, OZ, forge-std).
- `script/`: Deployment/testing scripts (if present).

## Frequently asked questions
- **Why EigenLayer?** Reuses staked security for operator validation and slashing, reducing bootstrapping costs.
- **Can I change the bridge?** Yes; supply any contract implementing `ICrossChainBridge`.
- **What stops instant reveal?** Enforced commit period in `DarkPoolHook`; reveals before period should revert.
- **How are operators paid?** Service manager can distribute rewards based on verified task responses and stake weights.
- **What happens if stake data is stale?** Rewards/slashing may be inaccurate; keep `updateOperatorsForQuorum` current (consider AVS-Sync).

## Quick commands
- Build: `forge build`
- Test: `forge test`
- Format (if enabled): `forge fmt`

## License
MIT
