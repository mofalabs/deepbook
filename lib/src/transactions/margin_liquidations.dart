/// LiquidationVault transaction builders, mirroring the official SDK's
/// `transactions/marginLiquidations.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/margin_liquidation/liquidation_vault.dart'
    as liquidation_vault;
import '../conversion.dart';

/// MarginLiquidationsContract class for managing LiquidationVault
/// operations.
class MarginLiquidationsContract {
  final DeepBookConfig _config;

  /// `config` Configuration for MarginLiquidationsContract.
  MarginLiquidationsContract(this._config);

  /// Create a new liquidation vault.
  /// [liquidationAdminCap] The liquidation admin cap object ID.
  void Function(Transaction) createLiquidationVault(
          String liquidationAdminCap) =>
      (tx) {
        liquidation_vault.createLiquidationVault(
          package: _config.LIQUIDATION_PACKAGE_ID,
          arguments: {'LiquidationCap': liquidationAdminCap},
        )(tx);
      };

  /// Deposit coins into a liquidation vault.
  /// [vaultId] The liquidation vault object ID.
  /// [liquidationAdminCap] The liquidation admin cap object ID.
  /// [coinKey] The key to identify the coin type.
  /// [amount] The amount to deposit.
  void Function(Transaction) deposit(String vaultId, String liquidationAdminCap,
          String coinKey, Object amount) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        final depositCoin =
            tx.coin(coin.type, convertQuantity(amount, coin.scalar));
        liquidation_vault.deposit(
          package: _config.LIQUIDATION_PACKAGE_ID,
          arguments: {
            'self': vaultId,
            'LiquidationCap': liquidationAdminCap,
            'coin': depositCoin,
          },
          typeArguments: [coin.type],
        )(tx);
      };

  /// Withdraw coins from a liquidation vault; returns the withdrawn coin.
  /// [vaultId] The liquidation vault object ID.
  /// [liquidationAdminCap] The liquidation admin cap object ID.
  /// [coinKey] The key to identify the coin type.
  /// [amount] The amount to withdraw.
  TransactionResult Function(Transaction) withdraw(String vaultId,
          String liquidationAdminCap, String coinKey, Object amount) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        return liquidation_vault.withdraw(
          package: _config.LIQUIDATION_PACKAGE_ID,
          arguments: {
            'self': vaultId,
            'LiquidationCap': liquidationAdminCap,
            'amount': convertQuantity(amount, coin.scalar),
          },
          typeArguments: [coin.type],
        )(tx);
      };

  /// Liquidate a margin manager by repaying base debt.
  /// [vaultId] The liquidation vault object ID.
  /// [managerAddress] The margin manager address to liquidate.
  /// [poolKey] The key to identify the pool.
  /// [repayAmount] The amount to repay (in base asset units), or omit for
  /// full liquidation.
  void Function(Transaction) liquidateBase(
          String vaultId, String managerAddress, String poolKey,
          [Object? repayAmount]) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);

        // Build the Option arg first so its pure input registers ahead of
        // the object inputs (matches the original positional ordering —
        // byte-identical).
        final repayAmountArg = repayAmount != null
            ? tx.pure
                .option('u64', convertQuantity(repayAmount, baseCoin.scalar))
            : tx.pure.option('u64', null);

        liquidation_vault.liquidateBase(
          package: _config.LIQUIDATION_PACKAGE_ID,
          arguments: {
            'self': vaultId,
            'marginManager': managerAddress,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'pool': pool.address,
            'repayAmount': repayAmountArg,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Liquidate a margin manager by repaying quote debt.
  /// [vaultId] The liquidation vault object ID.
  /// [managerAddress] The margin manager address to liquidate.
  /// [poolKey] The key to identify the pool.
  /// [repayAmount] The amount to repay (in quote asset units), or omit for
  /// full liquidation.
  void Function(Transaction) liquidateQuote(
          String vaultId, String managerAddress, String poolKey,
          [Object? repayAmount]) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);

        // Build the Option arg first so its pure input registers ahead of
        // the object inputs (matches the original positional ordering —
        // byte-identical).
        final repayAmountArg = repayAmount != null
            ? tx.pure
                .option('u64', convertQuantity(repayAmount, quoteCoin.scalar))
            : tx.pure.option('u64', null);

        liquidation_vault.liquidateQuote(
          package: _config.LIQUIDATION_PACKAGE_ID,
          arguments: {
            'self': vaultId,
            'marginManager': managerAddress,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'pool': pool.address,
            'repayAmount': repayAmountArg,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  // === Read-Only Functions ===

  /// Get the balance of a specific coin type in the liquidation vault.
  /// [vaultId] The liquidation vault object ID.
  /// [coinKey] The key to identify the coin type.
  TransactionResult Function(Transaction) balance(
          String vaultId, String coinKey) =>
      (tx) {
        final coin = _config.getCoin(coinKey);
        return liquidation_vault.balance(
          package: _config.LIQUIDATION_PACKAGE_ID,
          arguments: {'self': vaultId},
          typeArguments: [coin.type],
        )(tx);
      };
}
