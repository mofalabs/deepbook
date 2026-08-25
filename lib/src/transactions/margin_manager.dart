/// MarginManager transaction builders, mirroring the official SDK's
/// `transactions/marginManager.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook_margin/margin_manager.dart' as margin_manager;
import '../conversion.dart';
import '../types.dart';

/// MarginManagerContract class for managing MarginManager operations.
class MarginManagerContract {
  final DeepBookConfig _config;

  /// `config` Configuration for MarginManagerContract.
  MarginManagerContract(this._config);

  /// Create a new margin manager.
  /// [poolKey] The key to identify the pool.
  void Function(Transaction) newMarginManager(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_manager.new_(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'pool': pool.address,
            'deepbookRegistry': _config.REGISTRY_ID,
            'marginRegistry': _config.MARGIN_REGISTRY_ID,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Create a new margin manager with an initializer; returns the manager
  /// and the initializer.
  /// [poolKey] The key to identify the pool.
  ({dynamic manager, dynamic initializer}) Function(Transaction)
      newMarginManagerWithInitializer(String poolKey) => (tx) {
            final pool = _config.getPool(poolKey);
            final baseCoin = _config.getCoin(pool.baseCoin);
            final quoteCoin = _config.getCoin(pool.quoteCoin);
            final result = margin_manager.newWithInitializer(
              package: _config.MARGIN_PACKAGE_ID,
              arguments: {
                'pool': pool.address,
                'deepbookRegistry': _config.REGISTRY_ID,
                'marginRegistry': _config.MARGIN_REGISTRY_ID,
              },
              typeArguments: [baseCoin.type, quoteCoin.type],
            )(tx);
            return (manager: result[0], initializer: result[1]);
          };

  /// Share a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [manager] The margin manager to share.
  /// [initializer] The initializer for the manager.
  void Function(Transaction) shareMarginManager(
          String poolKey, dynamic manager, dynamic initializer) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_manager.share(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'manager': manager, 'initializer': initializer},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Register a margin manager back to the margin registry. Lets owners
  /// restore visibility of a manager that was unregistered by another
  /// platform.
  /// [managerKey] The key to identify the margin manager.
  void Function(Transaction) registerMarginManager(String managerKey) => (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_manager.registerMarginManager(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'marginRegistry': _config.MARGIN_REGISTRY_ID,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Unregister a margin manager from the margin registry. Aborts if the
  /// manager holds any outstanding debt or base/quote/DEEP balance.
  /// [managerKey] The key to identify the margin manager.
  void Function(Transaction) unregisterMarginManager(String managerKey) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_manager.unregisterMarginManager(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'marginRegistry': _config.MARGIN_REGISTRY_ID,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Deposit into a margin manager during initialization (before sharing).
  /// Use this when you need to deposit funds into a newly created manager in
  /// the same transaction.
  /// [params] The deposit parameters.
  void Function(Transaction) depositDuringInitialization(
          DepositDuringInitParams params) =>
      (tx) {
        final manager = params.manager;
        final poolKey = params.poolKey;
        final coinType = params.coinType;
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        // Get the deposit coin from config using the coinType key
        // (e.g., 'SUI', 'DBUSDC', 'DEEP').
        final depositCoin = _config.getCoin(coinType);

        // If amount is provided, create a coin with balance; otherwise use
        // the provided coin.
        final coin = params.amount != null
            ? tx.coin(depositCoin.type,
                convertQuantity(params.amount!, depositCoin.scalar))
            : params.coin;

        margin_manager.deposit(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'coin': coin,
          },
          typeArguments: [baseCoin.type, quoteCoin.type, depositCoin.type],
        )(tx);
      };

  /// Deposit base into a margin manager.
  /// [params] The deposit parameters.
  void Function(Transaction) depositBase(DepositParams params) => (tx) {
        final managerKey = params.managerKey;
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final coin = params.amount != null
            ? tx.coin(
                baseCoin.type, convertQuantity(params.amount!, baseCoin.scalar))
            : params.coin;
        margin_manager.deposit(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'coin': coin,
          },
          typeArguments: [baseCoin.type, quoteCoin.type, baseCoin.type],
        )(tx);
      };

  /// Deposit quote into a margin manager.
  /// [params] The deposit parameters.
  void Function(Transaction) depositQuote(DepositParams params) => (tx) {
        final managerKey = params.managerKey;
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final coin = params.amount != null
            ? tx.coin(quoteCoin.type,
                convertQuantity(params.amount!, quoteCoin.scalar))
            : params.coin;
        margin_manager.deposit(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'coin': coin,
          },
          typeArguments: [baseCoin.type, quoteCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Deposit deep into a margin manager.
  /// [params] The deposit parameters.
  void Function(Transaction) depositDeep(DepositParams params) => (tx) {
        final managerKey = params.managerKey;
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final deepCoin = _config.getCoin('DEEP');
        final coin = params.amount != null
            ? tx.coin(
                deepCoin.type, convertQuantity(params.amount!, deepCoin.scalar))
            : params.coin;
        margin_manager.deposit(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'coin': coin,
          },
          typeArguments: [baseCoin.type, quoteCoin.type, deepCoin.type],
        )(tx);
      };

  /// Withdraw base from a margin manager.
  /// [managerKey] The key to identify the manager.
  /// [amount] The amount to withdraw.
  TransactionResult Function(Transaction) withdrawBase(
          String managerKey, Object amount) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        return margin_manager.withdraw(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'pool': pool.address,
            'withdrawAmount': convertQuantity(amount, baseCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type, baseCoin.type],
        )(tx);
      };

  /// Withdraw quote from a margin manager.
  /// [managerKey] The key to identify the manager.
  /// [amount] The amount to withdraw.
  TransactionResult Function(Transaction) withdrawQuote(
          String managerKey, Object amount) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        return margin_manager.withdraw(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'pool': pool.address,
            'withdrawAmount': convertQuantity(amount, quoteCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Withdraw deep from a margin manager.
  /// [managerKey] The key to identify the manager.
  /// [amount] The amount to withdraw.
  TransactionResult Function(Transaction) withdrawDeep(
          String managerKey, Object amount) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final deepCoin = _config.getCoin('DEEP');
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        return margin_manager.withdraw(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'pool': pool.address,
            'withdrawAmount': convertQuantity(amount, deepCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type, deepCoin.type],
        )(tx);
      };

  /// Borrow base from a margin manager.
  /// [managerKey] The key to identify the manager.
  /// [amount] The amount to borrow.
  TransactionResult Function(Transaction) borrowBase(
          String managerKey, Object amount) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        return margin_manager.borrowBase(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseMarginPool': baseMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'pool': pool.address,
            'loanAmount': convertQuantity(amount, baseCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Borrow quote from a margin manager.
  /// [managerKey] The key to identify the manager.
  /// [amount] The amount to borrow.
  TransactionResult Function(Transaction) borrowQuote(
          String managerKey, Object amount) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        return margin_manager.borrowQuote(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'pool': pool.address,
            'loanAmount': convertQuantity(amount, quoteCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Repay base from a margin manager.
  /// [managerKey] The key to identify the manager.
  /// [amount] The amount to repay; omit to repay in full.
  TransactionResult Function(Transaction) repayBase(String managerKey,
          [Object? amount]) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        return margin_manager.repayBase(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginPool': baseMarginPool.address,
            'amount': amount != null
                ? convertQuantity(amount, baseCoin.scalar)
                : null,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Repay quote from a margin manager.
  /// [managerKey] The key to identify the manager.
  /// [amount] The amount to repay; omit to repay in full.
  TransactionResult Function(Transaction) repayQuote(String managerKey,
          [Object? amount]) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        return margin_manager.repayQuote(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginPool': quoteMarginPool.address,
            'amount': amount != null
                ? convertQuantity(amount, quoteCoin.scalar)
                : null,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Liquidate a margin manager.
  /// [managerAddress] The address of the manager to liquidate.
  /// [poolKey] The key to identify the pool.
  /// [debtIsBase] Whether the debt is in base.
  /// [repayCoin] The coin to repay.
  TransactionResult Function(Transaction) liquidate(String managerAddress,
          String poolKey, bool debtIsBase, dynamic repayCoin) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        final marginPool = debtIsBase ? baseMarginPool : quoteMarginPool;
        return margin_manager.liquidate(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': managerAddress,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'marginPool': marginPool.address,
            'pool': pool.address,
            'repayCoin': repayCoin,
          },
          typeArguments: [
            baseCoin.type,
            quoteCoin.type,
            debtIsBase ? baseCoin.type : quoteCoin.type,
          ],
        )(tx);
      };

  /// Set the referral for a margin manager (DeepBookPoolReferral).
  /// [managerKey] The key to identify the margin manager.
  /// [referral] The referral (DeepBookPoolReferral) to set.
  void Function(Transaction) setMarginManagerReferral(
          String managerKey, String referral) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        margin_manager.setMarginManagerReferral(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': manager.address, 'referralCap': referral},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Unset the referral for a margin manager.
  /// [managerKey] The key to identify the margin manager.
  /// [poolKey] The key of the pool to unset the referral for.
  void Function(Transaction) unsetMarginManagerReferral(
          String managerKey, String poolKey) =>
      (tx) {
        final manager = _config.getMarginManager(managerKey);
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        margin_manager.unsetMarginManagerReferral(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': manager.address, 'poolId': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  // === Read-Only Functions ===

  /// Get the owner address of a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) ownerByPoolKey(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.owner(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the DeepBook pool ID associated with a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) deepbookPool(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.deepbookPool(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the margin pool ID (if any) associated with a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) marginPoolId(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.marginPoolId(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get borrowed shares for both base and quote assets.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) borrowedShares(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.borrowedShares(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get borrowed base shares.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) borrowedBaseShares(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.borrowedBaseShares(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get borrowed quote shares.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) borrowedQuoteShares(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.borrowedQuoteShares(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if margin manager has base asset debt.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) hasBaseDebt(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.hasBaseDebt(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the balance manager ID for a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) balanceManager(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.balanceManager(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Calculate assets (base and quote) for a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) calculateAssets(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.calculateAssets(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId, 'pool': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Calculate debts (base and quote) for a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [coinKey] The key to identify the debt coin (base or quote).
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) calculateDebts(
          String poolKey, String coinKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final debtCoin = _config.getCoin(coinKey);
        final marginPool = _config.getMarginPool(coinKey);
        return margin_manager.calculateDebts(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginManagerId,
            'marginPool': marginPool.address
          },
          typeArguments: [baseCoin.type, quoteCoin.type, debtCoin.type],
        )(tx);
      };

  /// Get comprehensive state information for a margin manager.
  ///
  /// Returns (manager_id, deepbook_pool_id, risk_ratio, base_asset,
  /// quote_asset, base_debt, quote_debt, base_pyth_price, base_pyth_decimals,
  /// quote_pyth_price, quote_pyth_decimals).
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) managerState(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        return margin_manager.managerState(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginManagerId,
            'registry': _config.MARGIN_REGISTRY_ID,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the base asset balance of a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) baseBalance(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.baseBalance(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the quote asset balance of a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) quoteBalance(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.quoteBalance(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the DEEP token balance of a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) deepBalance(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.deepBalance(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the underlying BalanceManager ID for a margin manager. Returns an
  /// ID (not a `&BalanceManager`), so it composes in PTBs unlike
  /// [balanceManager].
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) balanceManagerId(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.balanceManagerId(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the BalanceManager referral ID for a pool (`Option<ID>`).
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) getBalanceManagerReferralId(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.getBalanceManagerReferralId(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId, 'poolId': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if the margin manager's account exists in the pool.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) accountExists(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.accountExists(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId, 'pool': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the pool account data for the margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) account(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.account(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId, 'pool': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the open order IDs for the margin manager's account in the pool.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) accountOpenOrders(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.accountOpenOrders(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId, 'pool': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get full order details for the margin manager's account in the pool.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) getAccountOrderDetails(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.getAccountOrderDetails(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId, 'pool': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get locked balances (base, quote, deep) for the margin manager's
  /// account in the pool.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) lockedBalance(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.lockedBalance(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId, 'pool': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check whether a limit order can be placed given the manager's current
  /// state.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  /// [price] Limit price.
  /// [quantity] Order quantity (base units).
  /// [isBid] True for bid, false for ask.
  /// [payWithDeep] Whether to pay fees in DEEP.
  /// [expireTimestamp] Order expiration timestamp (ms).
  TransactionResult Function(Transaction) canPlaceLimitOrder(
          String poolKey,
          String marginManagerId,
          Object price,
          Object quantity,
          bool isBid,
          bool payWithDeep,
          Object expireTimestamp) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputPrice = convertPrice(
            price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return margin_manager.canPlaceLimitOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginManagerId,
            'pool': pool.address,
            'price': inputPrice,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
            'expireTimestamp': expireTimestamp,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check whether a market order can be placed given the manager's current
  /// state.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  /// [quantity] Order quantity (base units).
  /// [isBid] True for bid, false for ask.
  /// [payWithDeep] Whether to pay fees in DEEP.
  TransactionResult Function(Transaction) canPlaceMarketOrder(
          String poolKey,
          String marginManagerId,
          Object quantity,
          bool isBid,
          bool payWithDeep) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return margin_manager.canPlaceMarketOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginManagerId,
            'pool': pool.address,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };
}
