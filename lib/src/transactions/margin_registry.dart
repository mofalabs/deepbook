/// MarginRegistry read-only transaction builders, mirroring the official
/// SDK's `transactions/marginRegistry.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook_margin/margin_registry.dart' as margin_registry;

/// MarginRegistryContract class for managing MarginRegistry read-only
/// operations.
class MarginRegistryContract {
  final DeepBookConfig _config;

  /// `config` Configuration for MarginRegistryContract.
  MarginRegistryContract(this._config);

  /// Check if a deepbook pool is enabled for margin trading.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) poolEnabled(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_registry.poolEnabled(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'pool': pool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the margin pool ID for a given asset.
  /// [coinKey] The key to identify the coin.
  TransactionResult Function(Transaction) getMarginPoolId(String coinKey) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        return margin_registry.getMarginPoolId(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': _config.MARGIN_REGISTRY_ID},
          typeArguments: [coin.type],
        )(tx);
      };

  /// Get the margin pool IDs (base and quote) for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) getDeepbookPoolMarginPoolIds(
          String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.getDeepbookPoolMarginPoolIds(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the margin manager IDs for a given owner.
  /// [owner] The owner address.
  TransactionResult Function(Transaction) getMarginManagerIds(String owner) =>
      (tx) => margin_registry.getMarginManagerIds(
            package: _config.MARGIN_PACKAGE_ID,
            arguments: {
              'self': _config.MARGIN_REGISTRY_ID,
              'owner': owner,
            },
          )(tx);

  /// Get the base margin pool ID for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) baseMarginPoolId(String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.baseMarginPoolId(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the quote margin pool ID for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) quoteMarginPoolId(String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.quoteMarginPoolId(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the minimum withdraw risk ratio for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) minWithdrawRiskRatio(
          String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.minWithdrawRiskRatio(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the minimum borrow risk ratio for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) minBorrowRiskRatio(String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.minBorrowRiskRatio(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the minimum risk ratio required to open a new position on a
  /// deepbook pool. Distinct from [minBorrowRiskRatio], which gates
  /// borrowing.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) minOpenRiskRatio(String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.minOpenRiskRatio(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the liquidation risk ratio for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) liquidationRiskRatio(
          String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.liquidationRiskRatio(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the target liquidation risk ratio for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) targetLiquidationRiskRatio(
          String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.targetLiquidationRiskRatio(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the user liquidation reward for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) userLiquidationReward(
          String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.userLiquidationReward(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get the pool liquidation reward for a deepbook pool.
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) poolLiquidationReward(
          String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        return margin_registry.poolLiquidationReward(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': _config.MARGIN_REGISTRY_ID,
            'deepbookPoolId': pool.address,
          },
        )(tx);
      };

  /// Get all allowed maintainer cap IDs.
  TransactionResult Function(Transaction) allowedMaintainers() =>
      (tx) => margin_registry.allowedMaintainers(
            package: _config.MARGIN_PACKAGE_ID,
            arguments: {'self': _config.MARGIN_REGISTRY_ID},
          )(tx);

  /// Get all allowed pause cap IDs.
  TransactionResult Function(Transaction) allowedPauseCaps() =>
      (tx) => margin_registry.allowedPauseCaps(
            package: _config.MARGIN_PACKAGE_ID,
            arguments: {'self': _config.MARGIN_REGISTRY_ID},
          )(tx);
}
