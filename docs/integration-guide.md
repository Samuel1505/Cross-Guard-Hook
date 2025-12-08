# Integration Guide: CrossGuardHook + EigenLayer AVS

This guide explains how to integrate, deploy, and operate CrossGuardHook with EigenLayer middleware.

## Prerequisites
- Foundry toolchain installed.
- Access to Uniswap v4 `PoolManager`.
- Deployed EigenLayer core contracts (DelegationManager, AllocationManager, AVSDirectory) on your target network.
- Bridge implementation that satisfies `ICrossChainBridge`.

## Contract roles and responsibilities
- `DarkPoolHook`: Uniswap v4 hook with commit–reveal and cross-chain handoff.
- `DarkPoolServiceManager`: AVS-facing contract that owns slashing params, rewards, and operator registry linkage.
- `DarkPoolTaskManager`: Issues validation tasks, verifies quorum responses, and signals hook readiness.
- EigenLayer middleware (from `lib/eigenlayer-middleware`):
  - `ServiceManagerBase`: AVS address to EigenLayer core.
  - `RegistryCoordinator` / `SlashingRegistryCoordinator`: create operator sets, handle operator (de)registration.
  - Registries (`StakeRegistry`, `BLSApkRegistry`, `IndexRegistry`): track stake weights, BLS keys, indices.
  - `BLSSignatureChecker`, `OperatorStateRetriever`: verify aggregate signatures; expose operator/quorum state.

## Deployment sequence
1) Deploy EigenLayer middleware stack (or reuse existing):
   - `ServiceManagerBase`, `RegistryCoordinator`/`SlashingRegistryCoordinator`, registries, slasher (`InstantSlasher` or `VetoableSlasher`), signature checker.
2) Deploy CrossGuardHook stack:
   - `DarkPoolTaskManager` (args: serviceManager addr, owner).
   - `DarkPoolServiceManager` (args: taskManager addr, owner, slashingPercentage bps).
   - `DarkPoolHook` (args: poolManager, serviceManager, taskManager, owner).
3) Wire permissions and config:
   - Set commit period on `DarkPoolHook`.
   - Configure slashing %, quorum thresholds, min stake on `DarkPoolServiceManager`.
   - Point task/service managers to EigenLayer middleware as needed (registrar/slasher/checker endpoints).

## Operator onboarding (EigenLayer flow)
1) Operator registers with EigenLayer core: `DelegationManager.registerAsOperator(...)`.
2) Stakers delegate to operator.
3) Operator allocates stake to AVS operator sets: `AllocationManager.modifyAllocations(...)` with operator set IDs and strategy weights.
4) After allocation delay, operator registers to AVS: `registerForOperatorSets(...)` on `SlashingRegistryCoordinator` (implements `IAVSRegistrar`).
5) AVS (or AVS-Sync) pushes stake updates: `StakeRegistry.updateOperatorsForQuorum(...)` so weights are current for rewards/slashing.

## Validation + swap flow
1) User commits swap via `DarkPoolHook.commitSwap(...)` with secret hash.
2) After commit period, user calls `revealAndSwap(...)` with secret + params.
3) Hook triggers task emission via `DarkPoolTaskManager`; operators respond with signatures.
4) Task manager verifies quorum via `BLSSignatureChecker`; on success, hook executes swap.
5) For cross-chain swaps, hook invokes `ICrossChainBridge` implementation to relay swap data/hash; settlement tracked via stored swap hashes.

## Slashing and security
- Slashing contract: choose `VetoableSlasher` (recommended) or `InstantSlasher`.
- Only objectively attributable faults should be slashable (e.g., invalid signatures, double execution).
- Keep `updateOperatorsForQuorum` calls regular to avoid stale stake weights.
- Use UAM/PermissionsController (EigenLayer) to delegate roles for slashing, registry ops, and metadata.
- All externals are ReentrancyGuard-protected; emergency pause via Ownable.

## Testing and ops
- Unit/integration tests: `forge test` (see `test/unit/` for hook and service/task manager coverage).
- Gas/safety checks: run Foundry fuzz tests where available; consider adding integration tests for your bridge adapter.
- Monitoring: watch operator set events from registries, task responses, and slashing events.

## Quick command cheatsheet
- Build: `forge build`
- Tests: `forge test`
- Format (if used): `forge fmt`

