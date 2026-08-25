/// DeepBook SDK configuration, mirroring the official SDK's
/// `utils/config.ts`.
library;

// Constant and field names deliberately mirror the official TS SDK verbatim
// (FLOAT_SCALAR, DEEPBOOK_PACKAGE_ID, …).
// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'package:sui/types/common.dart' show normalizeSuiAddress;

import 'constants.dart';
import 'errors.dart';
import 'types.dart';

// Numerical precision and scaling.
/// On-chain fixed-point scalar (10^9).
const int FLOAT_SCALAR = 1000000000; // 10^9 — on-chain fixed point

/// DEEP token decimal scalar (10^6).
const int DEEP_SCALAR = 1000000; // 10^6 — DEEP token decimals

// Time-related.
/// Timestamp used for orders without an explicit expiration.
final BigInt MAX_TIMESTAMP = BigInt.parse('1844674407370955161');

/// Maximum age (ms) before an on-chain PriceInfoObject is considered stale.
const int PRICE_INFO_OBJECT_MAX_AGE_MS = 30000; // 30 seconds

// Transaction and fee.
/// Default gas budget in MIST (0.25 SUI).
const int GAS_BUDGET = 250000000; // 0.25 SUI

/// Permissionless pool creation fee in raw DEEP units (500 DEEP).
const int POOL_CREATION_FEE_DEEP = 500000000; // 500 DEEP (500 * 10^6)

/// Supported network identifiers for the built-in constants.
enum DeepBookNetwork { mainnet, testnet }

/// Holds per-network addresses, coin/pool registries, the sender address and
/// optional admin capabilities. All transaction/query classes read from this.
class DeepBookConfig {
  final CoinMap _coins;
  final PoolMap _pools;
  final MarginPoolMap _marginPools;

  /// The network identifier (`'mainnet'`, `'testnet'`, or custom).
  final String network;

  /// Configured balance managers, keyed by a user-chosen manager key.
  final Map<String, BalanceManager> balanceManagers;

  /// Configured margin managers, keyed by a user-chosen manager key.
  final Map<String, MarginManager> marginManagers;

  /// The normalized sender address used by transaction builders.
  final String address;

  /// Pyth and Wormhole state ids used for price feed operations.
  final PythConfig pyth;

  /// The DeepBook package id.
  final String DEEPBOOK_PACKAGE_ID;

  /// The DeepBook registry shared object id.
  final String REGISTRY_ID;

  /// The DEEP treasury shared object id.
  final String DEEP_TREASURY_ID;

  /// The margin trading package id.
  final String MARGIN_PACKAGE_ID;

  /// The original (v1) margin package id.
  final String MARGIN_V1;

  /// The margin registry shared object id.
  final String MARGIN_REGISTRY_ID;

  /// The liquidation package id.
  final String LIQUIDATION_PACKAGE_ID;

  /// The DeepBook admin capability id, when held by the user.
  final String? adminCap;

  /// The margin admin capability id, when held by the user.
  final String? marginAdminCap;

  /// The margin maintainer capability id, when held by the user.
  final String? marginMaintainerCap;

  /// Creates a config for [network], resolving the built-in constants for
  /// mainnet/testnet or using the provided [packageIds] for custom networks.
  factory DeepBookConfig({
    required String network,
    required String address,
    String? adminCap,
    String? marginAdminCap,
    String? marginMaintainerCap,
    Map<String, BalanceManager>? balanceManagers,
    Map<String, MarginManager>? marginManagers,
    CoinMap? coins,
    PoolMap? pools,
    MarginPoolMap? marginPools,
    DeepbookPackageIds? packageIds,
    PythConfig? pyth,
  }) {
    final CoinMap resolvedCoins;
    final PoolMap resolvedPools;
    final MarginPoolMap resolvedMarginPools;
    final DeepbookPackageIds ids;
    final PythConfig resolvedPyth;

    if (packageIds != null) {
      ids = packageIds;
      resolvedCoins = coins ?? const {};
      resolvedPools = pools ?? const {};
      resolvedMarginPools = marginPools ?? const {};
      resolvedPyth =
          pyth ?? const PythConfig(pythStateId: '', wormholeStateId: '');
    } else if (network == 'mainnet') {
      ids = mainnetPackageIds;
      resolvedCoins = coins ?? mainnetCoins;
      resolvedPools = pools ?? mainnetPools;
      resolvedMarginPools = marginPools ?? mainnetMarginPools;
      resolvedPyth = pyth ?? mainnetPythConfigs;
    } else if (network == 'testnet') {
      ids = testnetPackageIds;
      resolvedCoins = coins ?? testnetCoins;
      resolvedPools = pools ?? testnetPools;
      resolvedMarginPools = marginPools ?? testnetMarginPools;
      resolvedPyth = pyth ?? testnetPythConfigs;
    } else {
      throw ConfigurationError(
          "Network '$network' is not supported by default. Provide custom "
          "'packageIds' for non-standard networks.");
    }

    return DeepBookConfig._(
      network: network,
      address: normalizeSuiAddress(address),
      adminCap: adminCap,
      marginAdminCap: marginAdminCap,
      marginMaintainerCap: marginMaintainerCap,
      balanceManagers: balanceManagers ?? {},
      marginManagers: marginManagers ?? {},
      coins: resolvedCoins,
      pools: resolvedPools,
      marginPools: resolvedMarginPools,
      ids: ids,
      pyth: resolvedPyth,
    );
  }

  DeepBookConfig._({
    required this.network,
    required this.address,
    required this.adminCap,
    required this.marginAdminCap,
    required this.marginMaintainerCap,
    required this.balanceManagers,
    required this.marginManagers,
    required CoinMap coins,
    required PoolMap pools,
    required MarginPoolMap marginPools,
    required DeepbookPackageIds ids,
    required this.pyth,
  })  : _coins = coins,
        _pools = pools,
        _marginPools = marginPools,
        DEEPBOOK_PACKAGE_ID = ids.deepbookPackageId,
        REGISTRY_ID = ids.registryId,
        DEEP_TREASURY_ID = ids.deepTreasuryId,
        MARGIN_PACKAGE_ID = ids.marginPackageId,
        MARGIN_V1 = ids.marginV1,
        MARGIN_REGISTRY_ID = ids.marginRegistryId,
        LIQUIDATION_PACKAGE_ID = ids.liquidationPackageId;

  /// Throws unless Pyth state ids are configured (needed for price feeds).
  void requirePyth() {
    if (pyth.pythStateId.isEmpty || pyth.wormholeStateId.isEmpty) {
      throw ConfigurationError(
          "Pyth configuration is required for price feed operations. "
          "Provide 'pyth' when using custom packageIds.");
    }
  }

  /// Returns the configured [Coin] for [key]; throws [ResourceNotFoundError]
  /// when unknown.
  Coin getCoin(String key) {
    final coin = _coins[key];
    if (coin == null) throw ResourceNotFoundError('Coin', key);
    return coin;
  }

  /// Returns the configured [Pool] for [key]; throws [ResourceNotFoundError]
  /// when unknown.
  Pool getPool(String key) {
    final pool = _pools[key];
    if (pool == null) throw ResourceNotFoundError('Pool', key);
    return pool;
  }

  /// Returns the configured [MarginPool] for [key]; throws
  /// [ResourceNotFoundError] when unknown.
  MarginPool getMarginPool(String key) {
    final pool = _marginPools[key];
    if (pool == null) throw ResourceNotFoundError('Margin pool', key);
    return pool;
  }

  /// Gets a configured balance manager by key.
  BalanceManager getBalanceManager(String managerKey) {
    final manager = balanceManagers[managerKey];
    if (manager == null) {
      throw DeepBookError(ErrorMessages.balanceManagerNotFound(managerKey));
    }
    return manager;
  }

  /// Gets a configured margin manager by key.
  MarginManager getMarginManager(String managerKey) {
    final manager = marginManagers[managerKey];
    if (manager == null) {
      throw DeepBookError(ErrorMessages.marginManagerNotFound(managerKey));
    }
    return manager;
  }
}
