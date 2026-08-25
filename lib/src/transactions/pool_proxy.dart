/// PoolProxy transaction builders, mirroring the official SDK's
/// `transactions/poolProxy.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook_margin/pool_proxy.dart' as pool_proxy;
import '../conversion.dart';
import '../errors.dart';
import '../types.dart';

/// PoolProxyContract class for managing PoolProxy operations.
class PoolProxyContract {
  final DeepBookConfig _config;

  /// `config` Configuration for PoolProxyContract.
  PoolProxyContract(this._config);

  /// Place a limit order. Enforces a post-trade `risk_ratio >=
  /// min_borrow_risk_ratio` invariant on the manager (skipped when the
  /// manager has no debt).
  /// [params] Parameters for placing a limit order.
  TransactionResult Function(Transaction) placeLimitOrder(
          PlaceMarginLimitOrderParams params) =>
      (tx) {
        final poolKey = params.poolKey;
        final marginManagerKey = params.marginManagerKey;
        final clientOrderId = params.clientOrderId;
        final price = params.price;
        final quantity = params.quantity;
        final isBid = params.isBid;
        final expiration = params.expiration ?? MAX_TIMESTAMP;
        final orderType = params.orderType ?? OrderType.noRestriction;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final payWithDeep = params.payWithDeep ?? true;
        final pool = _config.getPool(poolKey);
        final manager = _config.getMarginManager(marginManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        final inputPrice = convertPrice(
            price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return pool_proxy.placeLimitOrderV2(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': manager.address,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'clientOrderId': BigInt.parse(clientOrderId),
            'orderType': orderType.index,
            'selfMatchingOption': selfMatchingOption.index,
            'price': inputPrice,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
            'expireTimestamp': expiration,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Place a market order. Enforces a post-trade `risk_ratio >=
  /// min_borrow_risk_ratio` invariant on the manager (skipped when the
  /// manager has no debt).
  /// [params] Parameters for placing a market order.
  TransactionResult Function(Transaction) placeMarketOrder(
          PlaceMarginMarketOrderParams params) =>
      (tx) {
        final poolKey = params.poolKey;
        final marginManagerKey = params.marginManagerKey;
        final clientOrderId = params.clientOrderId;
        final quantity = params.quantity;
        final isBid = params.isBid;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final payWithDeep = params.payWithDeep ?? true;
        final pool = _config.getPool(poolKey);
        final manager = _config.getMarginManager(marginManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return pool_proxy.placeMarketOrderV2(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': manager.address,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'clientOrderId': BigInt.parse(clientOrderId),
            'selfMatchingOption': selfMatchingOption.index,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Place a reduce only limit order. Requires the manager to have debt on
  /// the relevant side; enforces a monotonic `risk_ratio_after >=
  /// risk_ratio_before` invariant so the fill cannot leak value to the
  /// counterparty.
  /// [params] Parameters for placing a reduce only limit order.
  TransactionResult Function(Transaction) placeReduceOnlyLimitOrder(
          PlaceMarginLimitOrderParams params) =>
      (tx) {
        final poolKey = params.poolKey;
        final marginManagerKey = params.marginManagerKey;
        final clientOrderId = params.clientOrderId;
        final price = params.price;
        final quantity = params.quantity;
        final isBid = params.isBid;
        final expiration = params.expiration ?? MAX_TIMESTAMP;
        final orderType = params.orderType ?? OrderType.noRestriction;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final payWithDeep = params.payWithDeep ?? true;
        final pool = _config.getPool(poolKey);
        final manager = _config.getMarginManager(marginManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        final inputPrice = convertPrice(
            price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return pool_proxy.placeReduceOnlyLimitOrderV2(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': manager.address,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'clientOrderId': BigInt.parse(clientOrderId),
            'orderType': orderType.index,
            'selfMatchingOption': selfMatchingOption.index,
            'price': inputPrice,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
            'expireTimestamp': expiration,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Place a reduce only market order. Requires the manager to have debt on
  /// the relevant side; enforces a monotonic `risk_ratio_after >=
  /// risk_ratio_before` invariant so the fill cannot leak value to the
  /// counterparty.
  /// [params] Parameters for placing a reduce only market order.
  TransactionResult Function(Transaction) placeReduceOnlyMarketOrder(
          PlaceMarginMarketOrderParams params) =>
      (tx) {
        final poolKey = params.poolKey;
        final marginManagerKey = params.marginManagerKey;
        final clientOrderId = params.clientOrderId;
        final quantity = params.quantity;
        final isBid = params.isBid;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final payWithDeep = params.payWithDeep ?? true;
        final pool = _config.getPool(poolKey);
        final manager = _config.getMarginManager(marginManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return pool_proxy.placeReduceOnlyMarketOrderV2(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': manager.address,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'clientOrderId': BigInt.parse(clientOrderId),
            'selfMatchingOption': selfMatchingOption.index,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Place a market order and repay the loan from the fill proceeds. The
  /// taker fill settles into the manager's balance, so the proceeds (plus
  /// any idle balance) are repaid into the debt side before the risk check;
  /// the gate is then the *net* post-repay `risk_ratio` being at least the
  /// pre-fill ratio. Unlike [placeMarketOrder], which checks the post-trade
  /// ratio against `min_borrow_risk_ratio`, this lets a deleveraging fill
  /// go through in the `liquidation..min_borrow` band, where a swap alone
  /// would be rejected.
  /// [params] Parameters for placing a market order.
  TransactionResult Function(Transaction) placeMarketOrderAndRepayLoan(
          PlaceMarginMarketOrderParams params) =>
      (tx) {
        final poolKey = params.poolKey;
        final marginManagerKey = params.marginManagerKey;
        final clientOrderId = params.clientOrderId;
        final quantity = params.quantity;
        final isBid = params.isBid;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final payWithDeep = params.payWithDeep ?? true;
        final pool = _config.getPool(poolKey);
        final manager = _config.getMarginManager(marginManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return pool_proxy.placeMarketOrderAndRepayLoan(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': manager.address,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'clientOrderId': BigInt.parse(clientOrderId),
            'selfMatchingOption': selfMatchingOption.index,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Place a reduce only limit order and repay the loan from the fill
  /// proceeds. Requires debt on the relevant side (a bid needs base debt;
  /// an ask needs quote debt and sells at most the gross base held); the
  /// repay happens before the monotonic `risk_ratio` gate, so the check is
  /// on the net post-repay ratio.
  /// [params] Parameters for placing a reduce only limit order.
  TransactionResult Function(Transaction) placeReduceOnlyLimitOrderAndRepayLoan(
          PlaceMarginLimitOrderParams params) =>
      (tx) {
        final poolKey = params.poolKey;
        final marginManagerKey = params.marginManagerKey;
        final clientOrderId = params.clientOrderId;
        final price = params.price;
        final quantity = params.quantity;
        final isBid = params.isBid;
        final expiration = params.expiration ?? MAX_TIMESTAMP;
        final orderType = params.orderType ?? OrderType.noRestriction;
        final selfMatchingOption = params.selfMatchingOption ??
            SelfMatchingOptions.selfMatchingAllowed;
        final payWithDeep = params.payWithDeep ?? true;
        final pool = _config.getPool(poolKey);
        final manager = _config.getMarginManager(marginManagerKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final baseMarginPool = _config.getMarginPool(pool.baseCoin);
        final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
        final inputPrice = convertPrice(
            price, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
        return pool_proxy.placeReduceOnlyLimitOrderAndRepayLoan(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': manager.address,
            'pool': pool.address,
            'baseMarginPool': baseMarginPool.address,
            'quoteMarginPool': quoteMarginPool.address,
            'baseOracle': baseCoin.priceInfoObjectId!,
            'quoteOracle': quoteCoin.priceInfoObjectId!,
            'clientOrderId': BigInt.parse(clientOrderId),
            'orderType': orderType.index,
            'selfMatchingOption': selfMatchingOption.index,
            'price': inputPrice,
            'quantity': inputQuantity,
            'isBid': isBid,
            'payWithDeep': payWithDeep,
            'expireTimestamp': expiration,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Place a reduce only market order and repay the loan from the fill
  /// proceeds. Same reduce-only direction guard as
  /// [placeReduceOnlyMarketOrder], but the settled proceeds are repaid into
  /// the debt side before the monotonic `risk_ratio` gate, so the check is
  /// on the net post-repay ratio.
  /// [params] Parameters for placing a reduce only market order.
  TransactionResult Function(Transaction)
      placeReduceOnlyMarketOrderAndRepayLoan(
              PlaceMarginMarketOrderParams params) =>
          (tx) {
            final poolKey = params.poolKey;
            final marginManagerKey = params.marginManagerKey;
            final clientOrderId = params.clientOrderId;
            final quantity = params.quantity;
            final isBid = params.isBid;
            final selfMatchingOption = params.selfMatchingOption ??
                SelfMatchingOptions.selfMatchingAllowed;
            final payWithDeep = params.payWithDeep ?? true;
            final pool = _config.getPool(poolKey);
            final manager = _config.getMarginManager(marginManagerKey);
            final baseCoin = _config.getCoin(pool.baseCoin);
            final quoteCoin = _config.getCoin(pool.quoteCoin);
            final baseMarginPool = _config.getMarginPool(pool.baseCoin);
            final quoteMarginPool = _config.getMarginPool(pool.quoteCoin);
            final inputQuantity = convertQuantity(quantity, baseCoin.scalar);
            return pool_proxy.placeReduceOnlyMarketOrderAndRepayLoan(
              package: _config.MARGIN_PACKAGE_ID,
              arguments: {
                'registry': _config.MARGIN_REGISTRY_ID,
                'marginManager': manager.address,
                'pool': pool.address,
                'baseMarginPool': baseMarginPool.address,
                'quoteMarginPool': quoteMarginPool.address,
                'baseOracle': baseCoin.priceInfoObjectId!,
                'quoteOracle': quoteCoin.priceInfoObjectId!,
                'clientOrderId': BigInt.parse(clientOrderId),
                'selfMatchingOption': selfMatchingOption.index,
                'quantity': inputQuantity,
                'isBid': isBid,
                'payWithDeep': payWithDeep,
              },
              typeArguments: [baseCoin.type, quoteCoin.type],
            )(tx);
          };

  /// Modify an existing order.
  /// [marginManagerKey] The key to identify the MarginManager.
  /// [orderId] Order ID to modify.
  /// [newQuantity] New quantity for the order.
  void Function(Transaction) modifyOrder(
          String marginManagerKey, String orderId, Object newQuantity) =>
      (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputQuantity = convertQuantity(newQuantity, baseCoin.scalar);

        pool_proxy.modifyOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
            'orderId': BigInt.parse(orderId),
            'newQuantity': inputQuantity,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel an existing order.
  /// [marginManagerKey] The key to identify the MarginManager.
  /// [orderId] Order ID to cancel.
  void Function(Transaction) cancelOrder(
          String marginManagerKey, String orderId) =>
      (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_proxy.cancelOrder(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
            'orderId': BigInt.parse(orderId),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel multiple existing orders.
  /// [marginManagerKey] The key to identify the MarginManager.
  /// [orderIds] Order IDs to cancel.
  void Function(Transaction) cancelOrders(
          String marginManagerKey, List<String> orderIds) =>
      (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_proxy.cancelOrders(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
            'orderIds': orderIds.map(BigInt.parse).toList(),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Cancel all existing orders.
  /// [marginManagerKey] The key to identify the MarginManager.
  void Function(Transaction) cancelAllOrders(String marginManagerKey) => (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_proxy.cancelAllOrders(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Withdraw settled amounts.
  /// [marginManagerKey] The key to identify the MarginManager.
  void Function(Transaction) withdrawSettledAmounts(String marginManagerKey) =>
      (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_proxy.withdrawSettledAmounts(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Stake in the pool.
  /// [marginManagerKey] The key to identify the MarginManager.
  /// [stakeAmount] The amount to stake.
  void Function(Transaction) stake(
          String marginManagerKey, Object stakeAmount) =>
      (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final deepCoin = _config.getCoin('DEEP');
        final stakeInput = convertQuantity(stakeAmount, deepCoin.scalar);
        pool_proxy.stake(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
            'amount': stakeInput,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Unstake from the pool.
  /// [marginManagerKey] The key to identify the MarginManager.
  void Function(Transaction) unstake(String marginManagerKey) => (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_proxy.unstake(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Submit a proposal.
  /// [marginManagerKey] The key to identify the MarginManager.
  /// [params] Parameters for the proposal.
  void Function(Transaction) submitProposal(
          String marginManagerKey, MarginProposalParams params) =>
      (tx) {
        final takerFee = params.takerFee;
        final makerFee = params.makerFee;
        final stakeRequired = params.stakeRequired;
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final stakeInput = convertRate(stakeRequired, FLOAT_SCALAR);
        final takerFeeInput = convertRate(takerFee, FLOAT_SCALAR);
        final makerFeeInput = convertRate(makerFee, FLOAT_SCALAR);
        pool_proxy.submitProposal(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
            'takerFee': takerFeeInput,
            'makerFee': makerFeeInput,
            'stakeRequired': stakeInput,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Vote on a proposal.
  /// [marginManagerKey] The key to identify the MarginManager.
  /// [proposalId] The ID of the proposal to vote on.
  void Function(Transaction) vote(String marginManagerKey, String proposalId) =>
      (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_proxy.vote(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
            'proposalId': proposalId,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Claim a rebate from a pool.
  /// [marginManagerKey] The key to identify the MarginManager.
  void Function(Transaction) claimRebate(String marginManagerKey) => (tx) {
        final marginManager = _config.getMarginManager(marginManagerKey);
        final pool = _config.getPool(marginManager.poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_proxy.claimRebates(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManager.address,
            'pool': pool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Withdraw settled amounts permissionlessly for a margin manager by ID.
  /// [poolKey] The key to identify the pool.
  /// [marginManagerId] The object ID of the MarginManager.
  void Function(Transaction) withdrawMarginSettledAmounts(
          String poolKey, String marginManagerId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_proxy.withdrawSettledAmountsPermissionless(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'marginManager': marginManagerId,
            'pool': pool.address,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Update the current price for a pool using Pyth oracle.
  /// [poolKey] The key to identify the pool.
  void Function(Transaction) updateCurrentPrice(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        if (baseCoin.priceInfoObjectId == null) {
          throw DeepBookError('Missing priceInfoObjectId for ${pool.baseCoin}');
        }
        if (quoteCoin.priceInfoObjectId == null) {
          throw DeepBookError(
              'Missing priceInfoObjectId for ${pool.quoteCoin}');
        }
        pool_proxy.updateCurrentPrice(
          package: _config.MARGIN_PACKAGE_ID,
          arguments: {
            'registry': _config.MARGIN_REGISTRY_ID,
            'pool': pool.address,
            'basePriceInfoObject': baseCoin.priceInfoObjectId,
            'quotePriceInfoObject': quoteCoin.priceInfoObjectId,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };
}
