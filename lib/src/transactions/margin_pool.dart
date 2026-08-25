/// MarginPool transaction builders, mirroring the official SDK's
/// `transactions/marginPool.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook_margin/margin_pool.dart' as margin_pool;
import '../conversion.dart';

/// MarginPoolContract class for managing MarginPool operations.
class MarginPoolContract {
  final DeepBookConfig _config;

  /// `config` Configuration for MarginPoolContract.
  MarginPoolContract(this._config);

  /// Mint a supplier cap for margin pool.
  TransactionResult Function(Transaction) mintSupplierCap() =>
      (tx) => margin_pool.mintSupplierCap(
            package: _config.MARGIN_PACKAGE_ID,
            arguments: {'registry': _config.MARGIN_REGISTRY_ID},
          )(tx);

  /// Supply to a margin pool.
  /// [coinKey] The key to identify the pool.
  /// [supplierCap] The supplier cap object.
  /// [amountToDeposit] The amount to deposit.
  /// [referralId] The ID of the referral.
  void Function(Transaction) supplyToMarginPool(
          String coinKey, dynamic supplierCap, Object amountToDeposit,
          [String? referralId]) =>
      (tx) {
        tx.setSenderIfNotSet(_config.address);
        final marginPool = _config.getMarginPool(coinKey);
        final coin = _config.getCoin(coinKey);
        final depositInput = convertQuantity(amountToDeposit, coin.scalar);
        final supply = tx.coin(coin.type, depositInput);

        // NOTE: left as a positional moveCall (not codegen), matching the
        // official SDK. The referral is an on-chain `option::some/none`
        // MoveCall (the TS `tx.object.option`), which a generated named-arg
        // call would encode as a pure Option<ID> instead — kept verbatim to
        // stay byte-identical.
        final referralOption = referralId != null
            ? tx.moveCall(
                '0x1::option::some',
                arguments: [tx.pure.id(referralId)],
                typeArguments: ['0x2::object::ID'],
              )
            : tx.moveCall(
                '0x1::option::none',
                arguments: [],
                typeArguments: ['0x2::object::ID'],
              );
        tx.moveCall(
          '${_config.MARGIN_PACKAGE_ID}::margin_pool::supply',
          arguments: [
            tx.object(marginPool.address),
            tx.object(_config.MARGIN_REGISTRY_ID),
            supplierCap is String ? tx.object(supplierCap) : supplierCap,
            supply,
            referralOption,
            tx.object('0x6'),
          ],
          typeArguments: [marginPool.type],
        );
      };

  /// Withdraw from a margin pool. If [amountToWithdraw] is not provided,
  /// withdraws all.
  /// [coinKey] The key to identify the pool.
  /// [supplierCap] The supplier cap object.
  /// [amountToWithdraw] The amount to withdraw. If omitted, withdraws all.
  TransactionResult Function(Transaction) withdrawFromMarginPool(
          String coinKey, dynamic supplierCap,
          [Object? amountToWithdraw]) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        final coin = _config.getCoin(coinKey);
        final withdrawInput = amountToWithdraw != null
            ? convertQuantity(amountToWithdraw, coin.scalar)
            : null;
        return margin_pool.withdraw(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'supplierCap': supplierCap,
            'amount': withdrawInput,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Mint a referral for a margin pool.
  /// [coinKey] The key to identify the pool.
  void Function(Transaction) mintSupplyReferral(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        margin_pool.mintSupplyReferral(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'registry': _config.MARGIN_REGISTRY_ID,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Withdraw referral fees from a margin pool.
  /// [coinKey] The key to identify the pool.
  /// [referralId] The ID of the referral.
  TransactionResult Function(Transaction) withdrawReferralFees(
          String coinKey, String referralId) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.withdrawReferralFees(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'referral': referralId,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };

  // === Read-only/View Functions ===

  /// Get the margin pool ID.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) getId(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.id(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Check if a deepbook pool is allowed for borrowing.
  /// [coinKey] The key to identify the margin pool.
  /// [deepbookPoolId] The ID of the deepbook pool.
  TransactionResult Function(Transaction) deepbookPoolAllowed(
          String coinKey, String deepbookPoolId) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.deepbookPoolAllowed(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'deepbookPoolId': deepbookPoolId,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the total supply amount.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) totalSupply(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.totalSupply(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the total supply shares.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) supplyShares(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.supplyShares(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the total borrow amount.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) totalBorrow(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.totalBorrow(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the total borrow shares.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) borrowShares(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.borrowShares(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the last update timestamp.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) lastUpdateTimestamp(String coinKey) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.lastUpdateTimestamp(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the supply cap.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) supplyCap(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.supplyCap(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the max utilization rate.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) maxUtilizationRate(String coinKey) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.maxUtilizationRate(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the protocol spread.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) protocolSpread(String coinKey) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.protocolSpread(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the minimum borrow amount.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) minBorrow(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.minBorrow(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get the current interest rate.
  /// [coinKey] The key to identify the pool.
  TransactionResult Function(Transaction) interestRate(String coinKey) => (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.interestRate(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginPool.address},
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get user supply shares for a supplier cap.
  /// [coinKey] The key to identify the pool.
  /// [supplierCapId] The ID of the supplier cap.
  TransactionResult Function(Transaction) userSupplyShares(
          String coinKey, String supplierCapId) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.userSupplyShares(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'supplierCapId': supplierCapId,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };

  /// Get user supply amount for a supplier cap.
  /// [coinKey] The key to identify the pool.
  /// [supplierCapId] The ID of the supplier cap.
  TransactionResult Function(Transaction) userSupplyAmount(
          String coinKey, String supplierCapId) =>
      (tx) {
        final marginPool = _config.getMarginPool(coinKey);
        return margin_pool.userSupplyAmount(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginPool.address,
            'supplierCapId': supplierCapId,
          },
          typeArguments: [marginPool.type],
        )(tx);
      };
}
