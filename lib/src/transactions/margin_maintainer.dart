/// Maintainer (MaintainerCap-gated) margin-pool builders, mirroring the
/// official SDK's `transactions/marginMaintainer.ts`.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook_margin/margin_pool.dart' as margin_pool_calls;
import '../contracts/deepbook_margin/protocol_config.dart'
    as protocol_config_calls;
import '../conversion.dart';
import '../errors.dart';
import '../types.dart';

/// DeepBookMaintainerContract class for managing maintainer actions.
class MarginMaintainerContract {
  final DeepBookConfig _config;

  MarginMaintainerContract(this._config);

  String get _marginMaintainerCap {
    final cap = _config.marginMaintainerCap;
    if (cap == null) {
      throw ConfigurationError('MARGIN_ADMIN_CAP environment variable not set');
    }
    return cap;
  }

  /// Create a new margin pool.
  void Function(Transaction) createMarginPool(
          String coinKey, dynamic poolConfig) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        margin_pool_calls.createMarginPool(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'config': poolConfig,
            'maintainerCap': _marginMaintainerCap,
          },
          typeArguments: [coin.type],
        )(tx);
      };

  /// Create a new protocol config (margin pool config + interest config).
  TransactionResult Function(Transaction) newProtocolConfig(
          String coinKey,
          MarginPoolConfigParams marginPoolConfig,
          InterestConfigParams interestConfig) =>
      (tx) {
        final hasRateLimit = marginPoolConfig.rateLimitCapacity != null &&
            marginPoolConfig.rateLimitRefillRatePerMs != null &&
            marginPoolConfig.rateLimitEnabled != null;
        final marginPoolConfigObject = hasRateLimit
            ? newMarginPoolConfigWithRateLimit(coinKey, marginPoolConfig)(tx)
            : newMarginPoolConfig(coinKey, marginPoolConfig)(tx);
        final interestConfigObject = newInterestConfig(interestConfig)(tx);
        return protocol_config_calls.newProtocolConfig(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'marginPoolConfig': marginPoolConfigObject,
            'interestConfig': interestConfigObject,
          },
        )(tx);
      };

  /// Create a new margin pool config.
  TransactionResult Function(Transaction) newMarginPoolConfig(
          String coinKey, MarginPoolConfigParams marginPoolConfig) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        return protocol_config_calls.newMarginPoolConfig(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'supplyCap':
                convertQuantity(marginPoolConfig.supplyCap, coin.scalar),
            'maxUtilizationRate':
                convertRate(marginPoolConfig.maxUtilizationRate, FLOAT_SCALAR),
            'protocolSpread':
                convertRate(marginPoolConfig.protocolSpread, FLOAT_SCALAR),
            'minBorrow':
                convertQuantity(marginPoolConfig.minBorrow, coin.scalar),
          },
        )(tx);
      };

  /// Create a new margin pool config with a rate limit. The rate-limit
  /// fields of [marginPoolConfig] must all be set.
  TransactionResult Function(Transaction) newMarginPoolConfigWithRateLimit(
          String coinKey, MarginPoolConfigParams marginPoolConfig) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        return protocol_config_calls.newMarginPoolConfigWithRateLimit(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'supplyCap':
                convertQuantity(marginPoolConfig.supplyCap, coin.scalar),
            'maxUtilizationRate':
                convertRate(marginPoolConfig.maxUtilizationRate, FLOAT_SCALAR),
            'protocolSpread':
                convertRate(marginPoolConfig.protocolSpread, FLOAT_SCALAR),
            'minBorrow':
                convertQuantity(marginPoolConfig.minBorrow, coin.scalar),
            'rateLimitCapacity': convertQuantity(
                marginPoolConfig.rateLimitCapacity!, coin.scalar),
            'rateLimitRefillRatePerMs': convertQuantity(
                marginPoolConfig.rateLimitRefillRatePerMs!, coin.scalar),
            'rateLimitEnabled': marginPoolConfig.rateLimitEnabled!,
          },
        )(tx);
      };

  /// Create a new interest config.
  TransactionResult Function(Transaction) newInterestConfig(
          InterestConfigParams interestConfig) =>
      (tx) => protocol_config_calls.newInterestConfig(
            package: _config.MARGIN_PACKAGE_ID,
            arguments: {
              'baseRate': convertRate(interestConfig.baseRate, FLOAT_SCALAR),
              'baseSlope': convertRate(interestConfig.baseSlope, FLOAT_SCALAR),
              'optimalUtilization':
                  convertRate(interestConfig.optimalUtilization, FLOAT_SCALAR),
              'excessSlope':
                  convertRate(interestConfig.excessSlope, FLOAT_SCALAR),
            },
          )(tx);

  /// Enable a deepbook pool for loan.
  void Function(Transaction) enableDeepbookPoolForLoan(
          String deepbookPoolKey, String coinKey, dynamic marginPoolCap) =>
      (tx) {
        final deepbookPool = _config.getPool(deepbookPoolKey);
        final marginPool = _config.getMarginPool(coinKey);
        margin_pool_calls.enableDeepbookPoolForLoan(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': deepbookPool.address,
            'marginPoolCap': marginPoolCap,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Disable a deepbook pool for loan.
  void Function(Transaction) disableDeepbookPoolForLoan(
          String deepbookPoolKey, String coinKey, dynamic marginPoolCap) =>
      (tx) {
        final deepbookPool = _config.getPool(deepbookPoolKey);
        final marginPool = _config.getMarginPool(coinKey);
        margin_pool_calls.disableDeepbookPoolForLoan(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': deepbookPool.address,
            'marginPoolCap': marginPoolCap,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Update the interest params.
  void Function(Transaction) updateInterestParams(String coinKey,
          dynamic marginPoolCap, InterestConfigParams interestConfig) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        final interestConfigObject = newInterestConfig(interestConfig)(tx);
        margin_pool_calls.updateInterestParams(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'interestConfig': interestConfigObject,
            'marginPoolCap': marginPoolCap,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Update the margin pool config.
  void Function(Transaction) updateMarginPoolConfig(String coinKey,
          dynamic marginPoolCap, MarginPoolConfigParams marginPoolConfig) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        final hasRateLimit = marginPoolConfig.rateLimitCapacity != null &&
            marginPoolConfig.rateLimitRefillRatePerMs != null &&
            marginPoolConfig.rateLimitEnabled != null;
        final marginPoolConfigObject = hasRateLimit
            ? newMarginPoolConfigWithRateLimit(coinKey, marginPoolConfig)(tx)
            : newMarginPoolConfig(coinKey, marginPoolConfig)(tx);
        margin_pool_calls.updateMarginPoolConfig(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginPoolConfig': marginPoolConfigObject,
            'marginPoolCap': marginPoolCap,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };
}
