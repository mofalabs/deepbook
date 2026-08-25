/// Dart SDK for DeepBook V3 — the decentralized central limit order book on
/// Sui. Aligned with the official `@mysten/deepbook-v3` TypeScript SDK
/// (v1.6.2). Transport is the gRPC(-web) stack from `package:sui` 0.5.0.
library;

export 'src/client.dart';
export 'src/config.dart';
export 'src/constants.dart';
export 'src/errors.dart';
export 'src/types.dart';
export 'src/validation.dart';

// On-chain BCS schemas for parsing raw DeepBook data, matching the official
// SDK's `types/bcs` exports.
export 'src/contracts/deepbook/account.dart' show Account;
export 'src/contracts/deepbook/balances.dart' show Balances;
export 'src/contracts/deepbook/deep_price.dart' show OrderDeepPrice;
export 'src/contracts/deepbook/order.dart' show Order;
export 'src/contracts/deepbook/deps/sui/vec_set.dart' show VecSet;

// Pyth price feed helpers.
export 'src/pyth/price_service_connection.dart';
export 'src/pyth/pyth_helpers.dart';
export 'src/pyth/sui_pyth_client.dart';

// Query classes (devInspect-style read queries).
export 'src/queries/account_queries.dart';
export 'src/queries/balance_manager_queries.dart';
export 'src/queries/margin_manager_queries.dart';
export 'src/queries/margin_pool_queries.dart';
export 'src/queries/order_queries.dart';
export 'src/queries/pool_queries.dart';
export 'src/queries/price_feed_queries.dart';
export 'src/queries/quantity_queries.dart';
export 'src/queries/query_context.dart';
export 'src/queries/referral_queries.dart';
export 'src/queries/registry_queries.dart';
export 'src/queries/tpsl_queries.dart';

// Transaction contract classes.
export 'src/transactions/balance_manager.dart';
export 'src/transactions/deepbook.dart';
export 'src/transactions/deepbook_admin.dart';
export 'src/transactions/flash_loans.dart';
export 'src/transactions/governance.dart';
export 'src/transactions/margin_admin.dart';
export 'src/transactions/margin_liquidations.dart';
export 'src/transactions/margin_maintainer.dart';
export 'src/transactions/margin_manager.dart';
export 'src/transactions/margin_pool.dart';
export 'src/transactions/margin_registry.dart';
export 'src/transactions/margin_tpsl.dart';
export 'src/transactions/pool_proxy.dart';
