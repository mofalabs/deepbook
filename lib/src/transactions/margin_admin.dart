/// Margin admin transaction builders, mirroring the official SDK's
/// `transactions/marginAdmin.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook_margin/margin_pool.dart' as margin_pool;
import '../contracts/deepbook_margin/margin_registry.dart' as margin_registry;
import '../contracts/deepbook_margin/oracle.dart' as oracle;
import '../conversion.dart';
import '../errors.dart';
import '../types.dart';

/// A coin plus its oracle config, used when building a new Pyth config.
typedef CoinOracleSetup = ({
  String coinKey,
  int maxConfBps,
  int maxEwmaDifferenceBps,
});

/// MarginAdminContract class for managing admin actions.
class MarginAdminContract {
  final DeepBookConfig _config;

  /// `config` — configuration for MarginAdminContract.
  MarginAdminContract(this._config);

  /// The admin capability required for admin operations.
  /// Throws if the admin capability is not set.
  String _marginAdminCap() {
    final marginAdminCap = _config.marginAdminCap;
    if (marginAdminCap == null) {
      throw ConfigurationError(ErrorMessages.marginAdminCapNotSet);
    }
    return marginAdminCap;
  }

  /// Mint a maintainer cap.
  TransactionResult Function(Transaction) mintMaintainerCap() =>
      (tx) => margin_registry.mintMaintainerCap(
            package: _config.MARGIN_PACKAGE_ID,
            arguments: {
              'self': _config.MARGIN_REGISTRY_ID,
              'AdminCap': _marginAdminCap(),
            },
          )(tx);

  /// Revoke a maintainer cap.
  void Function(Transaction) revokeMaintainerCap(String maintainerCapId) =>
      (tx) {
        // NOTE: left as a positional moveCall (not codegen), matching the
        // official SDK. The original passes `maintainerCapId` as an object
        // reference (`tx.object`), whereas the generated binding encodes it
        // as a pure `ID` value — kept verbatim to stay byte-identical.
        tx.moveCall(
          '${_config.MARGIN_PACKAGE_ID}::margin_registry::revoke_maintainer_cap',
          arguments: [
            tx.object(_config.MARGIN_REGISTRY_ID),
            tx.object(_marginAdminCap()),
            tx.object(maintainerCapId),
            tx.object('0x6'),
          ],
        );
      };

  /// Register a deepbook pool.
  /// [poolKey] The key of the pool to be registered.
  /// [poolConfig] The configuration of the pool.
  void Function(Transaction) registerDeepbookPool(
          String poolKey, dynamic poolConfig) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.registerDeepbookPool(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pool': pool.address,
            'poolConfig': poolConfig,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Enable a deepbook pool for margin trading.
  /// [poolKey] The key of the pool to be enabled.
  void Function(Transaction) enableDeepbookPool(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.enableDeepbookPool(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pool': pool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Disable a deepbook pool from margin trading.
  /// [poolKey] The key of the pool to be disabled.
  void Function(Transaction) disableDeepbookPool(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.disableDeepbookPool(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pool': pool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Update the risk parameters for a margin pool.
  /// [poolKey] The key of the pool to be updated.
  /// [poolConfig] The configuration of the pool.
  void Function(Transaction) updateRiskParams(
          String poolKey, dynamic poolConfig) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.updateRiskParams(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pool': pool.address,
            'poolConfig': poolConfig,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Set the price deviation tolerance for a pool. [tolerance] is in
  /// 9-decimal float scaling (1.0 = `FLOAT_SCALAR`); the SDK applies the
  /// scaling, so callers pass a human-readable fraction (e.g. `0.1` for
  /// 10%). Requires the pool's current price to have been initialized via
  /// `PoolProxyContract.updateCurrentPrice` first.
  /// [poolKey] The key of the pool to update.
  /// [tolerance] Tolerance as a fraction (e.g. 0.1 for 10%).
  void Function(Transaction) setPriceTolerance(
          String poolKey, Object tolerance) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.setPriceTolerance(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pool': pool.address,
            'tolerance': convertRate(tolerance, FLOAT_SCALAR),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Set the maximum acceptable Pyth price age (in milliseconds) for a
  /// pool. Requires the pool's current price to have been initialized via
  /// `PoolProxyContract.updateCurrentPrice` first.
  /// [poolKey] The key of the pool to update.
  /// [maxAgeMs] Max age in milliseconds (raw u64).
  void Function(Transaction) setMaxPriceAge(String poolKey, Object maxAgeMs) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.setMaxPriceAge(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pool': pool.address,
            'maxAgeMs': maxAgeMs,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Set the maximum lifetime (in milliseconds) of margin limit orders for
  /// a pool. `pool_proxy::place_limit_order_v2` and
  /// `place_reduce_only_limit_order_v2` clamp the user-supplied
  /// `expire_timestamp` to at most `now + max_order_ttl_ms`, bounding
  /// margin orders' exposure to stale-price exploitation.
  /// [poolKey] The key of the pool to update.
  /// [maxOrderTtlMs] Max order TTL in milliseconds (raw u64).
  void Function(Transaction) setMaxOrderTtl(
          String poolKey, Object maxOrderTtlMs) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.setMaxOrderTtl(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pool': pool.address,
            'maxOrderTtlMs': maxOrderTtlMs,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Set the minimum risk ratio required to open a new position on a pool.
  /// Distinct from the borrow floor: this gates position opening, not
  /// borrowing. Stored in 9-decimal float scaling (1.0 = `FLOAT_SCALAR`);
  /// the SDK applies the scaling, so callers pass a human-readable ratio
  /// (e.g. `1.25`).
  /// [poolKey] The key of the pool to update.
  /// [minOpenRiskRatio] Minimum open risk ratio (e.g. 1.25).
  void Function(Transaction) setMinOpenRiskRatio(
          String poolKey, Object minOpenRiskRatio) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.setMinOpenRiskRatio(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pool': pool.address,
            'minOpenRiskRatio': convertRate(minOpenRiskRatio, FLOAT_SCALAR),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Add the PythConfig to the margin registry.
  /// [config] The config to be added.
  void Function(Transaction) addConfig(dynamic config) => (tx) {
        margin_registry.addConfig(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'config': config,
          },
          typeArguments: ['${_config.MARGIN_PACKAGE_ID}::oracle::PythConfig'],
        )(tx);
      };

  /// Remove the PythConfig from the margin registry.
  void Function(Transaction) removeConfig() => (tx) {
        margin_registry.removeConfig(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
          },
          typeArguments: ['${_config.MARGIN_PACKAGE_ID}::oracle::PythConfig'],
        )(tx);
      };

  /// Enable a specific version.
  /// [version] The version to be enabled.
  void Function(Transaction) enableVersion(int version) => (tx) {
        margin_registry.enableVersion(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'version': version,
            'AdminCap': _marginAdminCap(),
          },
        )(tx);
      };

  /// Disable a specific version.
  /// [version] The version to be disabled.
  void Function(Transaction) disableVersion(int version) => (tx) {
        margin_registry.disableVersion(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'version': version,
            'AdminCap': _marginAdminCap(),
          },
        )(tx);
      };

  /// Create a new pool config.
  /// [poolKey] The key to identify the pool.
  /// [poolConfigParams] The parameters for the pool config.
  TransactionResult Function(Transaction) newPoolConfig(
          String poolKey, PoolConfigParams poolConfigParams) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_registry.newPoolConfig(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'minWithdrawRiskRatio': convertRate(
                poolConfigParams.minWithdrawRiskRatio, FLOAT_SCALAR),
            'minBorrowRiskRatio':
                convertRate(poolConfigParams.minBorrowRiskRatio, FLOAT_SCALAR),
            'liquidationRiskRatio': convertRate(
                poolConfigParams.liquidationRiskRatio, FLOAT_SCALAR),
            'targetLiquidationRiskRatio': convertRate(
                poolConfigParams.targetLiquidationRiskRatio, FLOAT_SCALAR),
            'userLiquidationReward': convertRate(
                poolConfigParams.userLiquidationReward, FLOAT_SCALAR),
            'poolLiquidationReward': convertRate(
                poolConfigParams.poolLiquidationReward, FLOAT_SCALAR),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Create a new pool config with leverage.
  /// [poolKey] The key to identify the pool.
  /// [leverage] The leverage for the pool.
  void Function(Transaction) newPoolConfigWithLeverage(
          String poolKey, Object leverage) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_registry.newPoolConfigWithLeverage(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'leverage': convertRate(leverage, FLOAT_SCALAR),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Create a new coin type data.
  /// [coinKey] The key to identify the coin.
  /// [maxConfBps] The maximum confidence interval in basis points.
  /// [maxEwmaDifferenceBps] The maximum EWMA difference in basis points.
  TransactionResult Function(Transaction) newCoinTypeData(
          String coinKey, int maxConfBps, int maxEwmaDifferenceBps) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        final feed = coin.feed;
        if (feed == null) {
          throw DeepBookError('Coin feed not found');
        }
        final priceFeedInput =
            _hexToBytes(feed.startsWith('0x') ? feed.substring(2) : feed);
        return oracle.newCoinTypeDataFromCurrency(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'currency': coin.currencyId!,
            'priceFeedId': priceFeedInput,
            'maxConfBps': maxConfBps,
            'maxEwmaDifferenceBps': maxEwmaDifferenceBps,
          },
          typeArguments: [coin.type],
        )(tx);
      };

  /// Create a new Pyth config.
  /// [coinSetups] The coins with their oracle config to be added to the
  /// Pyth config.
  /// [maxAgeSeconds] The max age in seconds for the Pyth config.
  TransactionResult Function(Transaction) newPythConfig(
          List<CoinOracleSetup> coinSetups, int maxAgeSeconds) =>
      (tx) {
        final coinTypeDataList = <dynamic>[];
        for (final setup in coinSetups) {
          coinTypeDataList.add(newCoinTypeData(
              setup.coinKey, setup.maxConfBps, setup.maxEwmaDifferenceBps)(tx));
        }
        return oracle.newPythConfig(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'setups': tx.makeMoveVec(
              objects: coinTypeDataList,
              type: '${_config.MARGIN_PACKAGE_ID}::oracle::CoinTypeData',
            ),
            'maxAgeSecs': maxAgeSeconds,
          },
        )(tx);
      };

  /// Mint a pause cap.
  TransactionResult Function(Transaction) mintPauseCap() =>
      (tx) => margin_registry.mintPauseCap(
            package: _config.MARGIN_PACKAGE_ID,
            arguments: {
              'self': _config.MARGIN_REGISTRY_ID,
              'AdminCap': _marginAdminCap(),
            },
          )(tx);

  /// Revoke a pause cap.
  /// [pauseCapId] The ID of the pause cap to revoke.
  void Function(Transaction) revokePauseCap(String pauseCapId) => (tx) {
        margin_registry.revokePauseCap(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
            'pauseCapId': pauseCapId,
          },
        )(tx);
      };

  /// Disable a version using pause cap.
  /// [version] The version to disable.
  /// [pauseCapId] The ID of the pause cap.
  void Function(Transaction) disableVersionPauseCap(
          int version, String pauseCapId) =>
      (tx) {
        margin_registry.disableVersionPauseCap(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'version': version,
            'pauseCap': pauseCapId,
          },
        )(tx);
      };

  /// Withdraw the default referral fees (admin only). The default referral
  /// at 0x0 doesn't have a SupplyReferral object.
  /// [coinKey] The key to identify the margin pool.
  /// Returns a `Coin<Asset>` transaction result.
  TransactionResult Function(Transaction) adminWithdrawDefaultReferralFees(
          String coinKey) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.adminWithdrawDefaultReferralFees(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'AdminCap': _marginAdminCap(),
          },
          typeArguments: [coin.type],
        )(tx);
      };
}

List<int> _hexToBytes(String hex) {
  if (hex.length.isOdd) {
    throw ArgumentError.value(hex, 'hex', 'expected an even-length hex string');
  }
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
