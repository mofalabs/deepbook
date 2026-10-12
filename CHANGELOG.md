## 0.2.0

**Margin moves to Pyth's upgraded Core; Predict, sessions and the account
primitive arrive.** Aligned with the official `@mysten/deepbook-v3` v2.6.8
(pinned at MystenLabs/ts-sdks commit `045187f2`). Method names and signatures
are unchanged from 0.1.0; what changes is which on-chain modules the margin
surface targets.

- **Margin / Pyth upgraded Core** (official 2.0.0): every oracle-taking margin
  entrypoint now targets the parallel `_upgraded` Move modules
  (`margin_manager_upgraded`, `pool_proxy_upgraded`,
  `liquidate_base_upgraded` / `liquidate_quote_upgraded`). Requires the
  upgraded `deepbook_margin` publication, enabled on the network's
  `MarginRegistry` — package ids move to testnet v16 / mainnet v7. Entrypoints
  that take no oracle stay on the base modules.
- **Hermes v2**: price updates fetch from `/v2/updates/price/latest` (v1
  `/api/latest_vaas` is deprecated upstream). New `pythAccessToken` client
  option (`Authorization: Bearer`) — the endpoint serving the upgraded Core
  answers 401 without one. 4xx responses are not retried, and error messages
  never carry the token.
- **New: `package:deepbook/predict.dart`** — DeepBook Predict (prediction
  markets): market discovery, quotes, mint/redeem/claim, PLP with price
  floors, typed receipts, and an exact-integer port of the on-chain fee path
  (`cost.*`: all-in mint cost, budget sizing, live-redeem proceeds) plus the
  client-side board pricer. Mainnet settles in Circle native USDC; read
  `quoteCoinType` from the config rather than assuming a symbol.
- **New: `package:deepbook/account.dart`** — the shared on-chain account
  primitive (`AccountContract`, `generateAuth`, `Account`/`AccountWrapper`
  BCS) that DeepBook's core wrapper and Predict both build on.
- **New: `package:deepbook/sessions.dart`** — time-limited trading sessions
  over a canonical Account: authorize/revoke/expiry, Predict session wrappers,
  and grant enumeration helpers.
- Generated bindings regenerated against the new baseline: 143 files,
  331 structs + 859 move-call builders (was 213/563), including the Predict,
  sessions, account and propbook (Block-Scholes) packages and the shared
  deployment records (`getDeployment` / `getUnits`).
- Fixed: the 93 `contracts/pyth/*` builders shipped in 0.1.0 could not accept
  arguments (a code-generator defect) — callable now.
- Verification: 44 fixture suites generated from the official TS SDK —
  transaction byte-compare (spot output is byte-identical to 0.1.0), a
  bit-exact parity matrix for the Predict fee engine, and derivation /
  event-decode parity — plus mainnet smoke of every pinned id, live testnet
  reads, real testnet execution of the margin write path (manager creation
  on the v16 package and a deposit through `margin_manager_upgraded`), the
  web (Chrome) suite, and an on-device acceptance run inside a real Flutter
  app on the iOS simulator.
- Known gap: the margin localnet real-execution suite needs a re-vendored
  Move deployment with the upgraded modules and is skipped until then.

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
