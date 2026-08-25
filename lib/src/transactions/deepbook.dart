/// DeepBook pool transaction builders, mirroring the official SDK's
/// `transactions/deepbook.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook/pool.dart' as pool_calls;
import '../contracts/deepbook/registry.dart' as registry_calls;
import '../conversion.dart';
import '../errors.dart';
import '../types.dart';
import 'balance_manager.dart';

/// DeepBookContract class for managing DeepBook operations.
class DeepBookContract {
  final DeepBookConfig _config;
  final BalanceManagerContract _balanceManager;

  /// `config` — configuration for DeepBookContract.
  DeepBookContract(DeepBookConfig config)
      : _config = config,
        _balanceManager = BalanceManagerContract(config);

  /// Mirrors the official `tx.setGasBudgetIfNotSet(GAS_BUDGET)`.
  void _setGasBudgetIfNotSet(Transaction tx) {
    if (tx.getData().gasData.budget == null) {
      tx.setGasBudget(BigInt.from(GAS_BUDGET));
    }
  }

  /// Place a limit order.
  ///
  /// [params] Parameters for placing a limit order.
  void Function(Transaction) placeLimitOrder(PlaceLimitOrderParams params) =>
      (tx) {
        final expiration = params.expiration ?? MAX_TIMESTAMP;
        final orderType = params.orderType ?? OrderType.noRestriction;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final payWithDeep = params.payWithDeep ?? true;

        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(params.poolKey);
        final balanceManager =
            _config.getBalanceManager(params.balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputPrice = convertPrice(
            params.price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(params.quantity, baseCoin.scalar);

        final tradeProof =
            _balanceManager.generateProof(params.balanceManagerKey)(tx);

        pool_calls.placeLimitOrder(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'clientOrderId': BigInt.parse(params.clientOrderId),
            'orderType': orderType.index,
            'selfMatchingOption': selfMatchingOption.index,
            'price': inputPrice,
            'quantity': inputQuantity,
            'isBid': params.isBid,
            'payWithDeep': payWithDeep,
            'expireTimestamp': expiration,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Place a market order.
  ///
  /// [params] Parameters for placing a market order.
  void Function(Transaction) placeMarketOrder(PlaceMarketOrderParams params) =>
      (tx) {
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final payWithDeep = params.payWithDeep ?? true;

        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(params.poolKey);
        final balanceManager =
            _config.getBalanceManager(params.balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof =
            _balanceManager.generateProof(params.balanceManagerKey)(tx);
        final inputQuantity = convertQuantity(params.quantity, baseCoin.scalar);

        pool_calls.placeMarketOrder(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'clientOrderId': BigInt.parse(params.clientOrderId),
            'selfMatchingOption': selfMatchingOption.index,
            'quantity': inputQuantity,
            'isBid': params.isBid,
            'payWithDeep': payWithDeep,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Modify an existing order.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  /// [orderId] Order ID to modify.
  /// [newQuantity] New quantity for the order.
  void Function(Transaction) modifyOrder(String poolKey,
          String balanceManagerKey, String orderId, Object newQuantity) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);
        final inputQuantity = convertQuantity(newQuantity, baseCoin.scalar);

        pool_calls.modifyOrder(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'orderId': BigInt.parse(orderId),
            'newQuantity': inputQuantity,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel an existing order.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  /// [orderId] Order ID to cancel.
  void Function(Transaction) cancelOrder(
          String poolKey, String balanceManagerKey, String orderId) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);

        pool_calls.cancelOrder(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'orderId': BigInt.parse(orderId),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel multiple orders.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  /// [orderIds] Array of order IDs to cancel.
  void Function(Transaction) cancelOrders(
          String poolKey, String balanceManagerKey, List<String> orderIds) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);

        pool_calls.cancelOrders(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'orderIds': orderIds.map(BigInt.parse).toList(),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel an existing order, no-op if the order is not currently in the
  /// balance manager's open orders (e.g. already filled, cancelled,
  /// expired-and-swept, or not owned by this balance manager). Unlike
  /// [cancelOrder], this will not abort on unknown order ids.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  /// [orderId] Order ID to cancel.
  void Function(Transaction) cancelLiveOrder(
          String poolKey, String balanceManagerKey, String orderId) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);

        pool_calls.cancelLiveOrder(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'orderId': BigInt.parse(orderId),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel multiple orders, skipping any order_id that is not currently in
  /// the balance manager's open orders (e.g. already filled, cancelled,
  /// expired-and-swept, or not owned by this balance manager). Duplicate ids
  /// in the input vector are handled gracefully. Unlike [cancelOrders], this
  /// will not abort on unknown order ids.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  /// [orderIds] Array of order IDs to cancel.
  void Function(Transaction) cancelLiveOrders(
          String poolKey, String balanceManagerKey, List<String> orderIds) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);

        pool_calls.cancelLiveOrders(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'orderIds': orderIds.map(BigInt.parse).toList(),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel all open orders for a balance manager.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  void Function(Transaction) cancelAllOrders(
          String poolKey, String balanceManagerKey) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);

        pool_calls.cancelAllOrders(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Withdraw settled amounts for a balance manager.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  void Function(Transaction) withdrawSettledAmounts(
          String poolKey, String balanceManagerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);

        pool_calls.withdrawSettledAmounts(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Withdraw settled amounts permissionlessly for a balance manager.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  void Function(Transaction) withdrawSettledAmountsPermissionless(
          String poolKey, String balanceManagerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.withdrawSettledAmountsPermissionless(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Withdraw settled amounts permissionlessly for a balance manager by ID.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerId] The object ID of the BalanceManager.
  void Function(Transaction) withdrawSettledAmountsManagerID(
          String poolKey, String balanceManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.withdrawSettledAmountsPermissionless(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManagerId,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Add a deep price point for a target pool using a reference pool.
  ///
  /// [targetPoolKey] The key to identify the target pool.
  /// [referencePoolKey] The key to identify the reference pool.
  void Function(Transaction) addDeepPricePoint(
          String targetPoolKey, String referencePoolKey) =>
      (tx) {
        final targetPool = _config.getPool(targetPoolKey);
        final referencePool = _config.getPool(referencePoolKey);
        final targetBaseCoin = _config.getCoin(targetPool.baseCoin);
        final targetQuoteCoin = _config.getCoin(targetPool.quoteCoin);
        final referenceBaseCoin = _config.getCoin(referencePool.baseCoin);
        final referenceQuoteCoin = _config.getCoin(referencePool.quoteCoin);

        pool_calls.addDeepPricePoint(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'targetPool': targetPool.address,
            'referencePool': referencePool.address,
          },
          typeArguments: [
            targetBaseCoin.type,
            targetQuoteCoin.type,
            referenceBaseCoin.type,
            referenceQuoteCoin.type,
          ],
        )(tx);
      };

  /// Claim rebates for a balance manager.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  void Function(Transaction) claimRebates(
          String poolKey, String balanceManagerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);

        pool_calls.claimRebates(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Mint a referral for a pool.
  ///
  /// [poolKey] The key to identify the pool.
  /// [multiplier] The multiplier for the referral.
  void Function(Transaction) mintReferral(String poolKey, Object multiplier) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final adjustedNumber = convertRate(multiplier, FLOAT_SCALAR);

        pool_calls.mintReferral(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'multiplier': adjustedNumber},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Update the referral multiplier for a pool (DeepBookPoolReferral).
  ///
  /// [poolKey] The key to identify the pool.
  /// [referral] The referral (DeepBookPoolReferral) to update.
  /// [multiplier] The multiplier for the referral.
  void Function(Transaction) updatePoolReferralMultiplier(
          String poolKey, String referral, Object multiplier) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final adjustedNumber = convertRate(multiplier, FLOAT_SCALAR);

        pool_calls.updatePoolReferralMultiplier(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'referral': referral,
            'multiplier': adjustedNumber,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Claim the rewards for a referral (DeepBookPoolReferral).
  ///
  /// Returns a map with the `baseRewards`, `quoteRewards` and `deepRewards`
  /// coin results (nested results of the underlying move call).
  ///
  /// [poolKey] The key to identify the pool.
  /// [referral] The referral (DeepBookPoolReferral) to claim the rewards for.
  Map<String, dynamic> Function(Transaction) claimPoolReferralRewards(
          String poolKey, String referral) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        final rewards = pool_calls.claimPoolReferralRewards(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'referral': referral},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);

        return {
          'baseRewards': rewards[0],
          'quoteRewards': rewards[1],
          'deepRewards': rewards[2],
        };
      };

  /// Update the allowed versions for a pool.
  ///
  /// [poolKey] The key of the pool to be updated.
  void Function(Transaction) updatePoolAllowedVersions(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.updatePoolAllowedVersions(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'registry': _config.REGISTRY_ID},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Gets an order.
  ///
  /// [poolKey] The key to identify the pool.
  /// [orderId] Order ID to get.
  void Function(Transaction) getOrder(String poolKey, String orderId) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.getOrder(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'orderId': BigInt.parse(orderId)},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Prepares a transaction to retrieve multiple orders from a specified pool.
  ///
  /// [poolKey] The identifier key for the pool to retrieve orders from.
  /// [orderIds] Array of order IDs to retrieve.
  void Function(Transaction) getOrders(String poolKey, List<String> orderIds) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.getOrders(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'orderIds': orderIds.map(BigInt.parse).toList(),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Burn DEEP tokens from the pool.
  ///
  /// [poolKey] The key to identify the pool.
  void Function(Transaction) burnDeep(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.burnDeep(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'treasuryCap': _config.DEEP_TREASURY_ID,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the mid price for a pool.
  ///
  /// [poolKey] The key to identify the pool.
  void Function(Transaction) midPrice(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.midPrice(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if a pool is whitelisted.
  ///
  /// [poolKey] The key to identify the pool.
  void Function(Transaction) whitelisted(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.whitelisted(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the quote quantity out for a given base quantity in.
  ///
  /// [poolKey] The key to identify the pool.
  /// [baseQuantity] Base quantity to convert.
  void Function(Transaction) getQuoteQuantityOut(
          String poolKey, Object baseQuantity) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.getQuoteQuantityOut(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'baseQuantity': convertQuantity(baseQuantity, baseCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the base quantity out for a given quote quantity in.
  ///
  /// [poolKey] The key to identify the pool.
  /// [quoteQuantity] Quote quantity to convert.
  void Function(Transaction) getBaseQuantityOut(
          String poolKey, Object quoteQuantity) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final quoteScalar = quoteCoin.scalar;

        pool_calls.getBaseQuantityOut(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'quoteQuantity': convertQuantity(quoteQuantity, quoteScalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the quantity out for a given base or quote quantity.
  ///
  /// [poolKey] The key to identify the pool.
  /// [baseQuantity] Base quantity to convert.
  /// [quoteQuantity] Quote quantity to convert.
  void Function(Transaction) getQuantityOut(
          String poolKey, Object baseQuantity, Object quoteQuantity) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final quoteScalar = quoteCoin.scalar;

        pool_calls.getQuantityOut(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'baseQuantity': convertQuantity(baseQuantity, baseCoin.scalar),
            'quoteQuantity': convertQuantity(quoteQuantity, quoteScalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get open orders for a balance manager in a pool.
  ///
  /// [poolKey] The key to identify the pool.
  /// [managerKey] Key of the balance manager.
  void Function(Transaction) accountOpenOrders(
          String poolKey, String managerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final manager = _config.getBalanceManager(managerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.accountOpenOrders(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'balanceManager': manager.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get level 2 order book specifying range of price.
  ///
  /// [poolKey] The key to identify the pool.
  /// [priceLow] Lower bound of the price range.
  /// [priceHigh] Upper bound of the price range.
  /// [isBid] Whether to get bid or ask orders.
  void Function(Transaction) getLevel2Range(
          String poolKey, Object priceLow, Object priceHigh, bool isBid) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.getLevel2Range(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'priceLow': convertPrice(
                priceLow, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar),
            'priceHigh': convertPrice(
                priceHigh, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar),
            'isBid': isBid,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get level 2 order book ticks from mid-price for a pool.
  ///
  /// [poolKey] The key to identify the pool.
  /// [tickFromMid] Number of ticks from mid-price.
  void Function(Transaction) getLevel2TicksFromMid(
          String poolKey, int tickFromMid) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.getLevel2TicksFromMid(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'ticks': tickFromMid},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the vault balances for a pool.
  ///
  /// [poolKey] The key to identify the pool.
  void Function(Transaction) vaultBalances(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.vaultBalances(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the pool ID by asset types.
  ///
  /// [baseType] Type of the base asset.
  /// [quoteType] Type of the quote asset.
  void Function(Transaction) getPoolIdByAssets(
          String baseType, String quoteType) =>
      (tx) {
        pool_calls.getPoolIdByAsset(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'registry': _config.REGISTRY_ID},
          typeArguments: [baseType, quoteType],
        )(tx);
      };

  /// Swap exact base amount for quote amount.
  ///
  /// The result supports `[0]` (base coin), `[1]` (quote coin) and
  /// `[2]` (deep coin).
  ///
  /// [params] Parameters for the swap.
  TransactionResult Function(Transaction) swapExactBaseForQuote(
          SwapParams params) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        tx.setSenderIfNotSet(_config.address);

        if (params.quoteCoin != null) {
          throw DeepBookError(
              'quoteCoin is not accepted for swapping base asset');
        }

        final pool = _config.getPool(params.poolKey);
        final deepCoinType = _config.getCoin('DEEP').type;
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        final baseCoinInput = params.baseCoin ??
            tx.coin(
                baseCoin.type, convertQuantity(params.amount, baseCoin.scalar));

        final deepCoin = params.deepCoin ??
            tx.coin(
                deepCoinType, convertQuantity(params.deepAmount, DEEP_SCALAR));

        final minQuoteInput = convertQuantity(params.minOut, quoteCoin.scalar);

        return pool_calls.swapExactBaseForQuote(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'baseIn': baseCoinInput,
            'deepIn': deepCoin,
            'minQuoteOut': minQuoteInput,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Swap exact quote amount for base amount.
  ///
  /// The result supports `[0]` (base coin), `[1]` (quote coin) and
  /// `[2]` (deep coin).
  ///
  /// [params] Parameters for the swap.
  TransactionResult Function(Transaction) swapExactQuoteForBase(
          SwapParams params) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        tx.setSenderIfNotSet(_config.address);

        if (params.baseCoin != null) {
          throw DeepBookError(
              'baseCoin is not accepted for swapping quote asset');
        }

        final pool = _config.getPool(params.poolKey);
        final deepCoinType = _config.getCoin('DEEP').type;
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        final quoteCoinInput = params.quoteCoin ??
            tx.coin(quoteCoin.type,
                convertQuantity(params.amount, quoteCoin.scalar));

        final deepCoin = params.deepCoin ??
            tx.coin(
                deepCoinType, convertQuantity(params.deepAmount, DEEP_SCALAR));

        final minBaseInput = convertQuantity(params.minOut, baseCoin.scalar);

        return pool_calls.swapExactQuoteForBase(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'quoteIn': quoteCoinInput,
            'deepIn': deepCoin,
            'minBaseOut': minBaseInput,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Swap exact quantity without a balance manager.
  ///
  /// The result supports `[0]` (base coin), `[1]` (quote coin) and
  /// `[2]` (deep coin).
  ///
  /// [params] Parameters for the swap; [isBaseToCoin] chooses the direction
  /// (mirrors the official `SwapParams & {isBaseToCoin: boolean}`).
  TransactionResult Function(Transaction) swapExactQuantity(SwapParams params,
          {required bool isBaseToCoin}) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        tx.setSenderIfNotSet(_config.address);

        final pool = _config.getPool(params.poolKey);
        final deepCoinType = _config.getCoin('DEEP').type;
        final baseCoinType = _config.getCoin(pool.baseCoin);
        final quoteCoinType = _config.getCoin(pool.quoteCoin);

        final baseCoinInput = isBaseToCoin
            ? (params.baseCoin ??
                tx.coin(baseCoinType.type,
                    convertQuantity(params.amount, baseCoinType.scalar)))
            : tx.coin(baseCoinType.type, BigInt.zero);

        final quoteCoinInput = isBaseToCoin
            ? tx.coin(quoteCoinType.type, BigInt.zero)
            : (params.quoteCoin ??
                tx.coin(quoteCoinType.type,
                    convertQuantity(params.amount, quoteCoinType.scalar)));

        final deepCoinInput = params.deepCoin ??
            tx.coin(
                deepCoinType, convertQuantity(params.deepAmount, DEEP_SCALAR));

        final minOutInput = convertQuantity(params.minOut,
            isBaseToCoin ? quoteCoinType.scalar : baseCoinType.scalar);

        return pool_calls.swapExactQuantity(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'baseIn': baseCoinInput,
            'quoteIn': quoteCoinInput,
            'deepIn': deepCoinInput,
            'minOut': minOutInput,
          },
          typeArguments: [baseCoinType.type, quoteCoinType.type],
        )(tx);
      };

  /// Swap exact base for quote with a balance manager.
  ///
  /// The result supports `[0]` (base coin) and `[1]` (quote coin).
  ///
  /// [params] Parameters for the swap.
  TransactionResult Function(Transaction) swapExactBaseForQuoteWithManager(
          SwapWithManagerParams params) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(params.poolKey);
        final balanceManager =
            _config.getBalanceManager(params.balanceManagerKey);
        final baseCoinType = _config.getCoin(pool.baseCoin);
        final quoteCoinType = _config.getCoin(pool.quoteCoin);

        final baseCoinInput = params.baseCoin ??
            tx.coin(baseCoinType.type,
                convertQuantity(params.amount, baseCoinType.scalar));
        final minQuoteInput =
            convertQuantity(params.minOut, quoteCoinType.scalar);

        return pool_calls.swapExactBaseForQuoteWithManager(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeCap': params.tradeCap,
            'depositCap': params.depositCap,
            'withdrawCap': params.withdrawCap,
            'baseIn': baseCoinInput,
            'minQuoteOut': minQuoteInput,
          },
          typeArguments: [baseCoinType.type, quoteCoinType.type],
        )(tx);
      };

  /// Swap exact quote for base with a balance manager.
  ///
  /// The result supports `[0]` (base coin) and `[1]` (quote coin).
  ///
  /// [params] Parameters for the swap.
  TransactionResult Function(Transaction) swapExactQuoteForBaseWithManager(
          SwapWithManagerParams params) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(params.poolKey);
        final balanceManager =
            _config.getBalanceManager(params.balanceManagerKey);
        final baseCoinType = _config.getCoin(pool.baseCoin);
        final quoteCoinType = _config.getCoin(pool.quoteCoin);

        final quoteCoinInput = params.quoteCoin ??
            tx.coin(quoteCoinType.type,
                convertQuantity(params.amount, quoteCoinType.scalar));
        final minBaseInput =
            convertQuantity(params.minOut, baseCoinType.scalar);

        return pool_calls.swapExactQuoteForBaseWithManager(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeCap': params.tradeCap,
            'depositCap': params.depositCap,
            'withdrawCap': params.withdrawCap,
            'quoteIn': quoteCoinInput,
            'minBaseOut': minBaseInput,
          },
          typeArguments: [baseCoinType.type, quoteCoinType.type],
        )(tx);
      };

  /// Swap exact quantity (base or quote) with a balance manager.
  ///
  /// The result supports `[0]` (base coin) and `[1]` (quote coin).
  ///
  /// [params] Parameters for the swap; [isBaseToCoin] chooses the direction
  /// (mirrors the official `SwapWithManagerParams & {isBaseToCoin: boolean}`).
  TransactionResult Function(Transaction) swapExactQuantityWithManager(
          SwapWithManagerParams params,
          {required bool isBaseToCoin}) =>
      (tx) {
        _setGasBudgetIfNotSet(tx);
        final pool = _config.getPool(params.poolKey);
        final balanceManager =
            _config.getBalanceManager(params.balanceManagerKey);
        final baseCoinType = _config.getCoin(pool.baseCoin);
        final quoteCoinType = _config.getCoin(pool.quoteCoin);

        final baseCoinInput = isBaseToCoin
            ? (params.baseCoin ??
                tx.coin(baseCoinType.type,
                    convertQuantity(params.amount, baseCoinType.scalar)))
            : tx.coin(baseCoinType.type, BigInt.zero);

        final quoteCoinInput = isBaseToCoin
            ? tx.coin(quoteCoinType.type, BigInt.zero)
            : (params.quoteCoin ??
                tx.coin(quoteCoinType.type,
                    convertQuantity(params.amount, quoteCoinType.scalar)));

        final minOutInput = convertQuantity(params.minOut,
            isBaseToCoin ? quoteCoinType.scalar : baseCoinType.scalar);

        return pool_calls.swapExactQuantityWithManager(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeCap': params.tradeCap,
            'depositCap': params.depositCap,
            'withdrawCap': params.withdrawCap,
            'baseIn': baseCoinInput,
            'quoteIn': quoteCoinInput,
            'minOut': minOutInput,
          },
          typeArguments: [baseCoinType.type, quoteCoinType.type],
        )(tx);
      };

  /// Create a new pool permissionlessly.
  ///
  /// [params] Parameters for creating permissionless pool.
  void Function(Transaction) createPermissionlessPool(
          CreatePermissionlessPoolParams params) =>
      (tx) {
        tx.setSenderIfNotSet(_config.address);
        final baseCoin = _config.getCoin(params.baseCoinKey);
        final quoteCoin = _config.getCoin(params.quoteCoinKey);
        final deepCoinType = _config.getCoin('DEEP').type;

        final baseScalar = baseCoin.scalar;
        final quoteScalar = quoteCoin.scalar;

        final adjustedTickSize = convertPrice(
            params.tickSize, FLOAT_SCALAR, quoteScalar, baseScalar);
        final adjustedLotSize = convertQuantity(params.lotSize, baseScalar);
        final adjustedMinSize = convertQuantity(params.minSize, baseScalar);

        final deepCoinInput = params.deepCoin ??
            tx.coin(deepCoinType, BigInt.from(POOL_CREATION_FEE_DEEP));

        pool_calls.createPermissionlessPool(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'registry': _config.REGISTRY_ID,
            'tickSize': adjustedTickSize,
            'lotSize': adjustedLotSize,
            'minSize': adjustedMinSize,
            'creationFee': deepCoinInput,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the trade parameters for a given pool, including taker fee,
  /// maker fee, and stake required.
  ///
  /// [poolKey] Key of the pool.
  void Function(Transaction) poolTradeParams(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.poolTradeParams(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the book parameters for a given pool, including tick size,
  /// lot size, and min size.
  ///
  /// [poolKey] Key of the pool.
  void Function(Transaction) poolBookParams(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.poolBookParams(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the account information for a given pool and balance manager.
  ///
  /// [poolKey] Key of the pool.
  /// [managerKey] The key of the BalanceManager.
  void Function(Transaction) account(String poolKey, String managerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final managerId = _config.getBalanceManager(managerKey).address;

        pool_calls.account(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'balanceManager': managerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the locked balance for a given pool and balance manager.
  ///
  /// [poolKey] Key of the pool.
  /// [managerKey] The key of the BalanceManager.
  void Function(Transaction) lockedBalance(String poolKey, String managerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final managerId = _config.getBalanceManager(managerKey).address;

        pool_calls.lockedBalance(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'balanceManager': managerId},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the DEEP price conversion for a pool.
  ///
  /// [poolKey] The key to identify the pool.
  void Function(Transaction) getPoolDeepPrice(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.getOrderDeepPrice(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the balance manager IDs for a given owner.
  ///
  /// [owner] The owner address to get balance manager IDs for.
  void Function(Transaction) getBalanceManagerIds(String owner) => (tx) {
        registry_calls.getBalanceManagerIds(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': _config.REGISTRY_ID, 'owner': owner},
        )(tx);
      };

  /// Get the balances for a referral (DeepBookPoolReferral).
  ///
  /// [poolKey] The key to identify the pool.
  /// [referral] The referral (DeepBookPoolReferral) to get the balances for.
  TransactionResult Function(Transaction) getPoolReferralBalances(
          String poolKey, String referral) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.getPoolReferralBalances(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'referral': referral},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the multiplier for a referral (DeepBookPoolReferral).
  ///
  /// [poolKey] The key to identify the pool.
  /// [referral] The referral (DeepBookPoolReferral) to get the multiplier for.
  TransactionResult Function(Transaction) poolReferralMultiplier(
          String poolKey, String referral) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.poolReferralMultiplier(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'referral': referral},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if a pool is a stable pool.
  ///
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) stablePool(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.stablePool(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if a pool is registered.
  ///
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) registeredPool(String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.registeredPool(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the quote quantity out for a given base quantity using input token
  /// as fee.
  ///
  /// [poolKey] The key to identify the pool.
  /// [baseQuantity] Base quantity to convert.
  TransactionResult Function(Transaction) getQuoteQuantityOutInputFee(
          String poolKey, Object baseQuantity) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.getQuoteQuantityOutInputFee(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'baseQuantity': convertQuantity(baseQuantity, baseCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the base quantity out for a given quote quantity using input token
  /// as fee.
  ///
  /// [poolKey] The key to identify the pool.
  /// [quoteQuantity] Quote quantity to convert.
  TransactionResult Function(Transaction) getBaseQuantityOutInputFee(
          String poolKey, Object quoteQuantity) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.getBaseQuantityOutInputFee(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'quoteQuantity': convertQuantity(quoteQuantity, quoteCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the quantity out for a given base or quote quantity using input
  /// token as fee.
  ///
  /// [poolKey] The key to identify the pool.
  /// [baseQuantity] Base quantity to convert.
  /// [quoteQuantity] Quote quantity to convert.
  TransactionResult Function(Transaction) getQuantityOutInputFee(
          String poolKey, Object baseQuantity, Object quoteQuantity) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.getQuantityOutInputFee(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'baseQuantity': convertQuantity(baseQuantity, baseCoin.scalar),
            'quoteQuantity': convertQuantity(quoteQuantity, quoteCoin.scalar),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the base quantity needed to receive a target quote quantity.
  ///
  /// [poolKey] The key to identify the pool.
  /// [targetQuoteQuantity] Target quote quantity.
  /// [payWithDeep] Whether to pay fees with DEEP.
  TransactionResult Function(Transaction) getBaseQuantityIn(
          String poolKey, Object targetQuoteQuantity, bool payWithDeep) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.getBaseQuantityIn(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'targetQuoteQuantity':
                convertQuantity(targetQuoteQuantity, quoteCoin.scalar),
            'payWithDeep': payWithDeep,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the quote quantity needed to receive a target base quantity.
  ///
  /// [poolKey] The key to identify the pool.
  /// [targetBaseQuantity] Target base quantity.
  /// [payWithDeep] Whether to pay fees with DEEP.
  TransactionResult Function(Transaction) getQuoteQuantityIn(
          String poolKey, Object targetBaseQuantity, bool payWithDeep) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.getQuoteQuantityIn(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'targetBaseQuantity':
                convertQuantity(targetBaseQuantity, baseCoin.scalar),
            'payWithDeep': payWithDeep,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get account order details for a balance manager.
  ///
  /// [poolKey] The key to identify the pool.
  /// [managerKey] Key of the balance manager.
  TransactionResult Function(Transaction) getAccountOrderDetails(
          String poolKey, String managerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final manager = _config.getBalanceManager(managerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.getAccountOrderDetails(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'balanceManager': manager.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the DEEP required for an order.
  ///
  /// [poolKey] The key to identify the pool.
  /// [baseQuantity] Base quantity.
  /// [price] Price.
  TransactionResult Function(Transaction) getOrderDeepRequired(
          String poolKey, Object baseQuantity, Object price) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputPrice = convertPrice(
            price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(baseQuantity, baseCoin.scalar);

        return pool_calls.getOrderDeepRequired(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'baseQuantity': inputQuantity,
            'price': inputPrice,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if account exists for a balance manager.
  ///
  /// [poolKey] The key to identify the pool.
  /// [managerKey] Key of the balance manager.
  TransactionResult Function(Transaction) accountExists(
          String poolKey, String managerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final manager = _config.getBalanceManager(managerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.accountExists(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'balanceManager': manager.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the next epoch trade parameters for a pool.
  ///
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) poolTradeParamsNext(String poolKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.poolTradeParamsNext(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the quorum for a pool.
  ///
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) quorum(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.quorum(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Get the pool ID.
  ///
  /// [poolKey] The key to identify the pool.
  TransactionResult Function(Transaction) poolId(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        return pool_calls.id(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if a limit order can be placed.
  ///
  /// [params] Parameters for checking limit order validity.
  TransactionResult Function(Transaction) canPlaceLimitOrder(
          CanPlaceLimitOrderParams params) =>
      (tx) {
        final pool = _config.getPool(params.poolKey);
        final manager = _config.getBalanceManager(params.balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputPrice = convertPrice(
            params.price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(params.quantity, baseCoin.scalar);

        return pool_calls.canPlaceLimitOrder(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': manager.address,
            'price': inputPrice,
            'quantity': inputQuantity,
            'isBid': params.isBid,
            'payWithDeep': params.payWithDeep,
            'expireTimestamp': params.expireTimestamp,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if a market order can be placed.
  ///
  /// [params] Parameters for checking market order validity.
  TransactionResult Function(Transaction) canPlaceMarketOrder(
          CanPlaceMarketOrderParams params) =>
      (tx) {
        final pool = _config.getPool(params.poolKey);
        final manager = _config.getBalanceManager(params.balanceManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputQuantity = convertQuantity(params.quantity, baseCoin.scalar);

        return pool_calls.canPlaceMarketOrder(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': manager.address,
            'quantity': inputQuantity,
            'isBid': params.isBid,
            'payWithDeep': params.payWithDeep,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if market order params are valid.
  ///
  /// [poolKey] The key to identify the pool.
  /// [quantity] Quantity.
  TransactionResult Function(Transaction) checkMarketOrderParams(
          String poolKey, Object quantity) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);

        return pool_calls.checkMarketOrderParams(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'quantity': inputQuantity},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Check if limit order params are valid.
  ///
  /// [poolKey] The key to identify the pool.
  /// [price] Price.
  /// [quantity] Quantity.
  /// [expireTimestamp] Expiration timestamp.
  TransactionResult Function(Transaction) checkLimitOrderParams(
          String poolKey, Object price, Object quantity, int expireTimestamp) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputPrice = convertPrice(
            price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);

        return pool_calls.checkLimitOrderParams(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'price': inputPrice,
            'quantity': inputQuantity,
            'expireTimestamp': expireTimestamp,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };
}
