/// Take Profit / Stop Loss transaction builders, mirroring the official
/// SDK's `transactions/marginTPSL.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook_margin/margin_manager.dart' as margin_manager;
import '../contracts/deepbook_margin/tpsl.dart' as tpsl;
import '../conversion.dart';
import '../types.dart';

/// MarginTPSLContract class for managing Take Profit / Stop Loss operations.
class MarginTPSLContract {
  final DeepBookConfig _config;

  /// `config` Configuration for MarginTPSLContract.
  MarginTPSLContract(this._config);

  // === Helper Functions ===

  /// Create a new condition for a conditional order.
  /// [poolKey] The key to identify the pool.
  /// [triggerBelowPrice] Whether to trigger when price is below trigger
  /// price.
  /// [triggerPrice] The price at which to trigger the order.
  TransactionResult Function(Transaction) newCondition(
          String poolKey, bool triggerBelowPrice, Object triggerPrice) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputPrice = convertPrice(
            triggerPrice, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        return tpsl.newCondition(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'triggerBelowPrice': triggerBelowPrice,
            'triggerPrice': inputPrice,
          },
        )(tx);
      };

  /// Create a new pending limit order for use in conditional orders.
  /// [poolKey] The key to identify the pool.
  /// [params] Parameters for the pending limit order.
  TransactionResult Function(Transaction) newPendingLimitOrder(
          String poolKey, PendingLimitOrderParams params) =>
      (tx) {
        final clientOrderId = params.clientOrderId;
        final orderType = params.orderType ?? OrderType.noRestriction;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final price = params.price;
        final quantity = params.quantity;
        final isBid = params.isBid;
        final payWithDeep = params.payWithDeep ?? true;
        final expireTimestamp = params.expireTimestamp ?? MAX_TIMESTAMP;
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputPrice = convertPrice(
            price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return tpsl.newPendingLimitOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'clientOrderId': BigInt.parse(clientOrderId),
            'orderType': orderType.index,
            'selfMatchingOption': selfMatchingOption.index,
            'price': inputPrice,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
            'expireTimestamp': expireTimestamp,
          },
        )(tx);
      };

  /// Create a new pending market order for use in conditional orders.
  /// [poolKey] The key to identify the pool.
  /// [params] Parameters for the pending market order.
  TransactionResult Function(Transaction) newPendingMarketOrder(
          String poolKey, PendingMarketOrderParams params) =>
      (tx) {
        final clientOrderId = params.clientOrderId;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final quantity = params.quantity;
        final isBid = params.isBid;
        final payWithDeep = params.payWithDeep ?? true;
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return tpsl.newPendingMarketOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'clientOrderId': BigInt.parse(clientOrderId),
            'selfMatchingOption': selfMatchingOption.index,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
          },
        )(tx);
      };

  // === Public Functions ===

  /// Add a conditional order (take profit or stop loss).
  /// [params] Parameters for adding the conditional order.
  void Function(Transaction) addConditionalOrder(
          AddConditionalOrderParams params) =>
      (tx) {
        final marginManagerKey = params.marginManagerKey;
        final conditionalOrderId = params.conditionalOrderId;
        final triggerBelowPrice = params.triggerBelowPrice;
        final triggerPrice = params.triggerPrice;
        final pendingOrder = params.pendingOrder;
        final manager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        // Create condition
        final condition =
            newCondition(manager.poolKey, triggerBelowPrice, triggerPrice)(tx);

        // Create pending order based on type
        final isLimitOrder = pendingOrder is PendingLimitOrderParams;
        final pending = isLimitOrder
            ? newPendingLimitOrder(manager.poolKey, pendingOrder)(tx)
            : newPendingMarketOrder(
                manager.poolKey, pendingOrder as PendingMarketOrderParams)(tx);

        margin_manager.addConditionalOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'pool': pool.address,
            'basePriceInfoObject': baseCoin.priceInfoObjectId!,
            'quotePriceInfoObject': quoteCoin.priceInfoObjectId!,
            'registry': _config.MARGIN_REGISTRY_ID,
            'conditionalOrderId': BigInt.parse(conditionalOrderId),
            'condition': condition,
            'pendingOrder': pending,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel all conditional orders for a margin manager.
  /// [marginManagerKey] The key to identify the margin manager.
  void Function(Transaction) cancelAllConditionalOrders(
          String marginManagerKey) =>
      (tx) {
        final manager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_manager.cancelAllConditionalOrders(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': manager.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel a specific conditional order.
  /// [marginManagerKey] The key to identify the margin manager.
  /// [conditionalOrderId] The ID of the conditional order to cancel.
  void Function(Transaction) cancelConditionalOrder(
          String marginManagerKey, String conditionalOrderId) =>
      (tx) {
        final manager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(manager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        margin_manager.cancelConditionalOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': manager.address,
            'conditionalOrderId': BigInt.parse(conditionalOrderId),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Execute conditional orders that have been triggered. Permissionless —
  /// anyone can call this. After the inner fill loop, the manager's
  /// post-trade `risk_ratio` is checked against `min_borrow_risk_ratio`; if
  /// any triggered fill breaches that floor, the whole txn aborts (no
  /// partial-state landing).
  /// [managerAddress] The address of the margin manager.
  /// [poolKey] The key to identify the pool (e.g., 'SUI_USDC').
  /// [maxOrdersToExecute] Maximum number of orders to execute in this call.
  TransactionResult Function(Transaction) executeConditionalOrders(
          String managerAddress, String poolKey, int maxOrdersToExecute) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        return margin_manager.executeConditionalOrdersV2(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': managerAddress,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'basePriceInfoObject': baseCoin.priceInfoObjectId!,
            'quotePriceInfoObject': quoteCoin.priceInfoObjectId!,
            'registry': _config.MARGIN_REGISTRY_ID,
            'maxOrdersToExecute': maxOrdersToExecute,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Execute conditional orders, deleveraging on each market-type fill.
  /// Permissionless, with the same trigger and cancellation handling as
  /// [executeConditionalOrders], but the market proceeds are repaid into
  /// the loan before the risk check, and the gate is the *net* post-repay
  /// `risk_ratio` being at least the pre-fill ratio.
  ///
  /// This is what lets a stop-loss fire in the `liquidation..min_borrow`
  /// danger band: a swap alone only lowers the oracle-valued ratio (so the
  /// v2 borrow-floor gate rejects it), while repaying actually improves it.
  /// If a single triggered fill would worsen net solvency the whole txn
  /// aborts — no partial-state landing.
  /// [managerAddress] The address of the margin manager.
  /// [poolKey] The key to identify the pool (e.g., 'SUI_USDC').
  /// [maxOrdersToExecute] Maximum number of orders to execute in this call.
  TransactionResult Function(Transaction) executeConditionalOrdersV3(
          String managerAddress, String poolKey, int maxOrdersToExecute) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        return margin_manager.executeConditionalOrdersV3(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': managerAddress,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'basePriceInfoObject': baseCoin.priceInfoObjectId!,
            'quotePriceInfoObject': quoteCoin.priceInfoObjectId!,
            'registry': _config.MARGIN_REGISTRY_ID,
            'maxOrdersToExecute': maxOrdersToExecute,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  // === Read-Only Functions ===

  /// Get all conditional order IDs for a margin manager.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) conditionalOrderIds(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.conditionalOrderIds(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get a specific conditional order by ID.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  /// [conditionalOrderId] The ID of the conditional order.
  TransactionResult Function(Transaction) conditionalOrder(
          String poolKey, String marginManagerId, String conditionalOrderId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.conditionalOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'self': marginManagerId,
            'conditionalOrderId': BigInt.parse(conditionalOrderId),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the lowest trigger price for trigger_above orders. Returns
  /// `constants::max_u64()` if there are no trigger_above orders.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) lowestTriggerAbovePrice(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.lowestTriggerAbovePrice(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the highest trigger price for trigger_below orders. Returns 0 if
  /// there are no trigger_below orders.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The ID of the margin manager.
  TransactionResult Function(Transaction) highestTriggerBelowPrice(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        return margin_manager.highestTriggerBelowPrice(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {'self': marginManagerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };
}
