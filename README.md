# DeepBook V3 Dart SDK

Dart/Flutter SDK for [DeepBook V3](https://deepbook.tech) — the decentralized
central limit order book (CLOB) on [Sui](https://sui.io). A faithful port of
the official [`@mysten/deepbook-v3`](https://www.npmjs.com/package/@mysten/deepbook-v3)
TypeScript SDK (v2.6.8), running on the gRPC(-web) transport of
[`package:sui`](https://pub.dev/packages/sui) ≥ 0.5.0.

> **History:** 0.1.0 was a complete rewrite — the 0.0.x releases targeted
> DeepBook **V2** (`0xdee9`), decommissioned on-chain, over the now-sunset
> JSON-RPC API, and nothing from them survives. 0.2.0 moves margin onto
> Pyth's upgraded Core and adds Predict, sessions and the account primitive.
> See CHANGELOG.

## Coverage

Full parity with the official TS SDK surface:

- **Spot CLOB** — BalanceManager (deposits/withdrawals/trade caps/proofs),
  order placement & cancellation, swaps, flash loans, governance
  (stake/vote/proposals), referrals.
- **Queries** — all devInspect-style reads: order book (level2), pool
  parameters, account state, quantity quotes, registry, margin state.
- **Margin trading** — margin managers, margin pools, leveraged orders via
  pool proxy, TP/SL conditional orders, liquidations, maintainer/admin ops.
  Targets Pyth's upgraded Core (the only deployment the official SDK
  supports); price updates need a Hermes credential via `pythAccessToken`.
- **Pyth** — Hermes (v2) price service client, wormhole VAA verification and
  on-chain price feed updates.
- **Predict** (`package:deepbook/predict.dart`) — prediction markets: market
  discovery, quotes, mint/redeem/claim, PLP, typed receipts, and client-side
  all-in cost previews that are an exact integer port of the on-chain fee
  path.
- **Account & sessions** (`package:deepbook/account.dart`,
  `package:deepbook/sessions.dart`) — the shared on-chain account primitive
  and time-limited trading sessions over it, mirroring the official SDK's
  `/account` and `/sessions` subpaths. Like the official package root,
  `package:deepbook/deepbook.dart` is unchanged — the new surfaces are
  separate entry points.
- **Admin** — pool creation/tuning, version management, stablecoin whitelist
  (requires the `DeepbookAdminCap`).

## Install

```yaml
dependencies:
  deepbook: ^0.2.0
  sui: ^0.5.0
```

## Quick start

```dart
import 'package:sui/sui.dart' hide Coin; // `Coin` also exists in deepbook
import 'package:deepbook/deepbook.dart';

final grpc = SuiGrpcClient(network: SuiNetwork.mainnet);
final client = DeepBookClient(
  client: grpc.core as GrpcCoreClient,
  network: 'mainnet',
  address: '0x...your address',
  balanceManagers: {
    'MAIN': BalanceManager(address: '0x...your balance manager'),
  },
);

// Read the book.
final mid = await client.midPrice('SUI_USDC');
final book = await client.getLevel2TicksFromMid('SUI_USDC', 10);

// Trade: compose a transaction with the contract builders, then sign+execute
// with the sui package.
final tx = Transaction();
client.deepBook.placeLimitOrder(PlaceLimitOrderParams(
  poolKey: 'SUI_USDC',
  balanceManagerKey: 'MAIN',
  clientOrderId: '1',
  price: 3.05,
  quantity: 10,
  isBid: true,
))(tx);

final account = SuiAccount.fromPrivateKey('suiprivkey...');
final executed = await (grpc.core as GrpcCoreClient)
    .signAndExecuteTransaction(account, tx);
```

Every transaction-builder method returns a closure to apply to a
`Transaction` — `contract.method(...)(tx)` — mirroring the official SDK's
`tx.add(contract.method(...))` composition, so multiple calls compose into
one programmable transaction block.

Quantity/price inputs accept either a `num` (human units, scaled by the coin
scalar) or a `BigInt` (raw on-chain u64).

## Networks

Built-in constants cover `mainnet` and `testnet` (package ids, coins, pools,
margin pools, Pyth state). For localnet or custom deployments pass
`packageIds:`/`coins:`/`pools:` explicitly (see
`tool/localnet/setup.sh` for a self-deployed localnet used by the tests).

## Regenerating the contract bindings

`lib/src/contracts/` is generated from the official SDK's codegen output:

```sh
dart tool/codegen/generate.dart <ts-sdks>/packages/deepbook-v3/src/contracts
dart format lib/src/contracts
```

## Testing

- `flutter test test/config_test.dart test/byte_compare_test.dart
  test/account_sessions_byte_compare_test.dart
  test/predict_byte_compare_test.dart test/predict_cost_test.dart
  test/pyth_offline_test.dart` — offline. The byte-compare suites verify
  builder output against fixtures produced by the official TS SDK
  (`tool/byte_compare/gen_fixtures*.mjs` regenerates them), and the Predict
  cost suite asserts bit-exact parity with the official fee engine. The
  fixtures live in the repository but are not shipped in the published
  package; the suites skip themselves when they are absent.
- `flutter test test/balance_manager_live_test.dart test/queries_live_test.dart
  test/predict_live_test.dart test/pyth_live_test.dart` — live against
  public testnet.
- `test/*_localnet_test.dart` — full REAL-EXECUTION integration against a
  self-deployed localnet: matched trades, market/IOC/FOK/post-only orders,
  swaps in both directions, flash loans, cap-based permissions, governance,
  and the complete margin stack (borrow/repay, leveraged orders via pool
  proxy, TP/SL conditional orders, and liquidation driven by a crashed
  oracle price). Prepare the chain once with `tool/localnet/vendor.sh`, then
  `tool/localnet/setup.sh` per regenesis. These skip automatically when no
  localnet is configured. The margin suite currently requires a re-vendored
  deployment carrying the `_upgraded` modules (the SDK's oracle entrypoints
  target Pyth's upgraded Core since 0.2.0); until then the margin write path
  is covered by the byte-compare suites.

### Web platform

`flutter test test/web_transport_test.dart test/config_test.dart --platform
chrome` covers the browser path: the gRPC-web transport, dio, config /
constants / conversion, and BCS (including the u128 BigInt path).

The network layer is verified end-to-end in a real browser:
`tool/webcheck/run.sh` builds a minimal Flutter Web app against this
package, serves it, and loads it in headless Chrome, asserting that live
gRPC-web reads against a mainnet fullnode succeed (chain id, mid price,
pool params). `flutter build web --release` takes ~25s.

Note: `flutter test --platform chrome` cannot compile a suite that
constructs `GrpcCoreClient` — the test runner's compiler stalls on the
generated `sui.rpc.v2` protobuf set (124 files, ~18k lines). That is a
test-runner limitation only; release web builds are unaffected, which is
why browser coverage of the network layer lives in `tool/webcheck/`
rather than in a `--platform chrome` test.

The byte-compare suite is VM-only (`@TestOn('vm')`) because it reads
fixtures from disk.
