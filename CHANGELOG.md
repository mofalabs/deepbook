## 0.1.0

**Complete rewrite for DeepBook V3.** Breaking: nothing from 0.0.x survives.

- DeepBook V2 (`0xdee9`) support removed — the V2 on-chain package is
  decommissioned and the JSON-RPC endpoints it relied on are sunset.
- Full port of the official `@mysten/deepbook-v3` TypeScript SDK v1.6.2
  (pinned at MystenLabs/ts-sdks commit `72317198`, 2026-07-28):
  - `DeepBookClient` facade with 94 query methods.
  - 14 transaction contract classes (~230 builder methods): balance manager,
    spot trading, flash loans, governance, admin, and the complete margin
    subsystem (managers, pools, registry, pool proxy, TP/SL, liquidations,
    maintainer).
  - 12 devInspect query classes (~110 methods) over
    `simulateTransaction` + BCS-parsed return values.
  - Pyth integration: Hermes price service client, wormhole VAA
    verification, on-chain price feed updates.
  - Generated Move bindings (`lib/src/contracts/`, 91 modules: 213 structs +
    563 move-call builders) via `tool/codegen/generate.dart`.
- Transport: gRPC(-web) via `sui` ^0.5.0 (JSON-RPC fully removed).
- Verification: builder output byte-compared against the official TS SDK
  (10 fixture suites); live testnet coverage for balance manager write path,
  spot/margin queries and Pyth; full trading and admin write paths executed
  on a self-deployed localnet (`tool/localnet/`).

## 0.0.1

* Initial version, created by Mofa Labs. (DeepBook V2 — obsolete.)
