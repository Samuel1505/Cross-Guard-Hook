# CrossGuardHook Pitch

## Overview
CrossGuardHook is a sophisticated Uniswap v4 hook that extends `BaseHook`, integrates EigenLayer’s Actively Validated Services (AVS) for staking-backed validation and slashing hooks, and layers in privacy-focused order execution plus simplified cross-chain swap functionality.

## Problem
- Public swap intent leaks MEV and invites front-running.
- Execution needs to be conditioned on stake-backed operator validation with accountability (slashing).
- Cross-chain handoff should happen through a clean adapter to contain bridge risk.

## Solution
Lock swap intent behind commit–reveal, gate execution on EigenLayer AVS operator validation (with slashing pathways), and isolate cross-chain delivery behind an explicit bridge interface so the hook stays minimal, auditable, and chain-agnostic.

## Technical Components & Integration
- Core contracts
  - `DarkPoolHook` (`BaseHook`): commit/reveal swaps (`commitSwap`, `revealAndSwap`), enforces `commitPeriod` bounds and pool allowlists, and inspects `hookData` in `beforeSwap`/`afterSwap`. Derives batch hashes for AVS tasks and triggers cross-chain signaling via `CrossChainSwapInitiated`; bridge target settable via `setCrossChainBridge`.
  - `DarkPoolTaskManager`: creates validation tasks (`createNewTask`), records operator responses, enforces quorum, and calls `SERVICE_MANAGER.recordTaskValidation`. Responses are gated by `SERVICE_MANAGER.isValidOperator`; pausable with force-complete controls.
  - `DarkPoolServiceManager`: extends EigenLayer `ServiceManagerBase`, wiring AVS directory, registry/stake, allocation, permission, and rewards coordinators. Exposes operator stake checks, records validations, and provides hooks for slashing/reward flows.
- EigenLayer touchpoints
  - Operator validity via `RegistryCoordinator` + `StakeRegistry` stake/quorum data.
  - AVS registration, permissions, allocations, and rewards routed through EigenLayer middleware; slashing hook available via the base service manager stack.
- Cross-chain
  - `_handleCrossChainSwap` decodes target chain/recipient/amount from `hookData`, computes a `swapHash`, and emits `CrossChainSwapInitiated`; bridging is abstracted behind `ICrossChainBridge`.

## Why It Matters
- Mitigates MEV by hiding swap intent until reveal.
- Adds stake- and slash-backed operator validation before accepting batch results.
- Keeps bridge risk contained with an adapter boundary and minimal hook surface.

## Core Features
- Commit–reveal with nonce-bound commits, deadline checks, and bounded block-based `commitPeriod`.
- Pool gating via `setPoolEnabled`; owner control of commit period and bridge target.
- Hook permissions limited to `beforeSwap`/`afterSwap`; commits marked executed after hook run.
- Cross-chain hook path emits `CrossChainSwapInitiated` from encoded `hookData`.
- Task lifecycle: `createNewTask`, operator `respondToTask` with quorum counting, force-complete admin path, pause/unpause.
- EigenLayer operator gating through `isValidOperator` stake checks; validations recorded; reward/slashing hooks exposed via `ServiceManagerBase`.

## System Architecture
```
          Users                    EigenLayer Core (AVS)
            |                                  ^
     commit/reveal                              |
            v                                  |
   +----------------+      responses   +------------------+
   |  DarkPoolHook  |<-----------------| TaskManager      |
   | (Uniswap v4)   |                  | (quorum/checks)  |
   +-------+--------+                  +---------+--------+
           |                                     |
   afterSwap w/ bridge data                      |
           v                                     |
   +----------------+                    +-------v-------+
   | Bridge Adapter |                    | ServiceMgr    |
   | (ICrossChain)  |---- optional ----->| (EigenLayer   |
   +----------------+                    |  stake/slash  |
                                         +---------------+
```
