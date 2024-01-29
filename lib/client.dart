import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/models/sui_event.dart';
import 'package:sui/sui.dart';
import 'package:sui/types/common.dart';
import 'package:sui/types/sui_bcs.dart';
import 'package:deepbook/types/bcs.dart';

import 'types/index.dart';
import 'utils/constants.dart';

final DUMMY_ADDRESS = normalizeSuiAddress('0x0');

enum AssetType {
  base, quote
}

enum OrderType {
  bid, ask, both
}

typedef TransactionObjectInput = dynamic;

class DeepBookClient {
	final Map<String, List<String>> _poolTypeArgsCache = {};

  late final SuiClient suiClient;
  String? _accountCap;
  late final String currentAddress;
  int clientOrderId = 0;

  DeepBookClient({
    SuiClient? client,
    String? accountCap,
    String? currentAddress
  }) {
    suiClient = client ?? SuiClient(Constants.testnetAPI);
    _accountCap = accountCap;
    this.currentAddress = currentAddress ?? DUMMY_ADDRESS;
  }


	/// [cap] set the account cap for interacting with DeepBook
	void setAccountCap(String cap) {
		_accountCap = cap;
	}

  /// [cap] get the account cap for interacting with DeepBook
  String? get accountCap => _accountCap;

	/// Create pool for trading pair.
  /// 
	/// [baseAssetType] Full coin type of the base asset, eg: "0x3d0d0ce17dcd3b40c2d839d96ce66871ffb40e1154a8dd99af72292b3d10d7fc::wbtc::WBTC"
  /// 
	/// [quoteAssetType] Full coin type of quote asset, eg: "0x3d0d0ce17dcd3b40c2d839d96ce66871ffb40e1154a8dd99af72292b3d10d7fc::usdt::USDT"
  /// 
	/// [tickSize] Minimal Price Change Accuracy of this pool, eg: 10000000. The number must be an integer float scaled by `FLOAT_SCALING_FACTOR`.
  /// 
	/// [lotSize] Minimal Lot Change Accuracy of this pool, eg: 10000.
	TransactionBlock createPool(
		String baseAssetType,
		String quoteAssetType,
		int tickSize,
		int lotSize,
	) {
		final txb = TransactionBlock();
		// create a pool with CREATION_FEE
    final coin = txb.splitCoins(txb.gas, [txb.pureInt(CREATION_FEE)]);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::create_pool",
			typeArguments: [baseAssetType, quoteAssetType],
			arguments: [txb.pureInt(tickSize), txb.pureInt(lotSize), coin],
		);
		return txb;
	}

  /// Create pool for trading pair.
  /// 
  /// [baseAssetType] Full coin type of the base asset, eg: "0x3d0d0ce17dcd3b40c2d839d96ce66871ffb40e1154a8dd99af72292b3d10d7fc::wbtc::WBTC"
  /// 
  /// [quoteAssetType] Full coin type of quote asset, eg: "0x3d0d0ce17dcd3b40c2d839d96ce66871ffb40e1154a8dd99af72292b3d10d7fc::usdt::USDT"
  /// 
  /// [tickSize] Minimal Price Change Accuracy of this pool, eg: 10000000. The number must be an interger float scaled by `FLOAT_SCALING_FACTOR`.
  /// 
  /// [lotSize] Minimal Lot Change Accuracy of this pool, eg: 10000.
  /// 
  /// [takerFeeRate] Customized taker fee rate, float scaled by `FLOAT_SCALING_FACTOR`, Taker_fee_rate of 0.25% should be 2_500_000 for example
  /// 
  /// [makerRebateRate] Customized maker rebate rate, float scaled by `FLOAT_SCALING_FACTOR`,  should be less than or equal to the taker_rebate_rate
	TransactionBlock createCustomizedPool(
		String baseAssetType,
		String quoteAssetType,
		int tickSize,
		int lotSize,
		int takerFeeRate,
		int makerRebateRate,
	) {
		final txb = TransactionBlock();
		// create a pool with CREATION_FEE
    final coin = txb.splitCoins(txb.gas, [txb.pureInt(CREATION_FEE)]);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::create_customized_pool",
			typeArguments: [baseAssetType, quoteAssetType],
			arguments: [
				txb.pureInt(tickSize),
				txb.pureInt(lotSize),
				txb.pureInt(takerFeeRate),
				txb.pureInt(makerRebateRate),
				coin.result,
			],
		);
		return txb;
	}

	/// Create Account Cap
	TransactionResult createAccountCap(TransactionBlock txb) {
		final cap = txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::create_account",
			typeArguments: [],
			arguments: [],
		);
		return cap;
	}

	/// Create and Transfer custodian account to user's [currentAddress]
	TransactionBlock createAccount({
		String? currentAddress,
		TransactionBlock? txb
	}) {
    txb ??= TransactionBlock();
		final cap = createAccountCap(txb);
		txb.transferObjects([cap], txb.pureAddress(_checkAddress(currentAddress ?? this.currentAddress)));
		return txb;
	}

	/// Create and Transfer custodian account to user's [currentAddress].
  /// [accountCap] Object id of Account Capacity under user address, created after invoking createAccount
	TransactionBlock createChildAccountCap({
		String? currentAddress,
		String? accountCap,
	}) {
		final txb = TransactionBlock();
		final childCap = txb.moveCall(
			"$PACKAGE_ID::$MODULE_CUSTODIAN::create_child_account_cap",
			typeArguments: [],
			arguments: [txb.object(_checkAccountCap(accountCap ?? this.accountCap))],
		);
		txb.transferObjects([childCap], txb.pureAddress(_checkAddress(currentAddress ?? this.currentAddress)));
		return txb;
	}

  /// Construct transaction block for depositing asset [coinId] into a pool [poolId].
  /// 
  /// You can omit [coinId] argument if you are depositing SUI, in which case gas coin will be used.
  /// 
	/// The [quantity] to deposit. If omitted, the entire balance of the coin will be deposited
	Future<TransactionBlock> deposit({
		required String poolId,
		String? coinId,
		int? quantity,
	}) async {
		final txb = TransactionBlock();

		final [baseAsset, quoteAsset] = await getPoolTypeArgs(poolId);
		final hasSui =
			baseAsset == NORMALIZED_SUI_COIN_TYPE || quoteAsset == NORMALIZED_SUI_COIN_TYPE;

		if (coinId == null && !hasSui) {
			throw ArgumentError('coinId must be specified if neither baseAsset nor quoteAsset is SUI');
		}

		final inputCoin = coinId != null ? txb.object(coinId) : txb.gas;

    var coin = inputCoin;
    if (quantity != null) {
      coin = txb.splitCoins(inputCoin, [txb.pureInt(quantity)]).result;
    }

		final coinType = coinId != null ? await getCoinType(coinId) : NORMALIZED_SUI_COIN_TYPE;
		if (coinType != baseAsset && coinType != quoteAsset) {
			throw ArgumentError(
				"coin $coinId of $coinType type is not a valid asset for pool $poolId, which supports $baseAsset and $quoteAsset",
			);
		}
		final functionName = coinType == baseAsset ? 'deposit_base' : 'deposit_quote';

		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::$functionName",
			typeArguments: [baseAsset, quoteAsset],
			arguments: [txb.object(poolId), coin, txb.object(_checkAccountCap())],
		);
		return txb;
	}

	/// Construct transaction block for withdrawing the [assetType] (base or quote) of the amount 
  /// of [quantity] asset from a pool [poolId] to [recipientAddress].
  /// 
	/// If omitted [recipientAddress], `this.currentAddress` will be used. The function
	/// will throw if the `recipientAddress === DUMMY_ADDRESS`
	Future<TransactionBlock> withdraw(
		String poolId,
		int quantity,
		AssetType assetType,
		[String? recipientAddress]
	) async {
    recipientAddress ??= currentAddress;
		final txb = TransactionBlock();
		final functionName = assetType == AssetType.base ? 'withdraw_base' : 'withdraw_quote';
    final typeArgs = await getPoolTypeArgs(poolId);
		final withdraw = txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::$functionName",
			typeArguments: typeArgs,
			arguments: [txb.object(poolId), txb.pureInt(quantity), txb.object(_checkAccountCap())],
		);
		txb.transferObjects([withdraw], txb.pureAddress(_checkAddress(recipientAddress)));
		return txb;
	}

	/// Place a limit order
  /// 
  /// [poolId] Object id of pool, created after invoking createPool. 
  /// 
  /// [price] price of the limit order. The number must be an interger float scaled by `FLOAT_SCALING_FACTOR`. 
  /// 
  /// [quantity] quantity of the limit order in BASE ASSET, eg: 100000000. 
  /// 
  /// [orderType] bid for buying base with quote, ask for selling base for quote. ]
  /// 
  /// [expirationTimestamp] expiration timestamp of the limit order in ms. If omitted, the order will expire in 1 day 
	/// from the time this function is called(not the time the transaction is executed). 
  /// 
  /// [restriction] restrictions on limit orders, explain in doc for more details. 
  /// 
  /// [clientOrderId] a client side defined order number for bookkeeping purpose, e.g., "1", "2", etc. If omitted, the sdk will
	/// assign a increasing number starting from 0. But this number might be duplicated if you are using multiple sdk instances. 
  /// 
  /// [selfMatchingPrevention] Options for self-match prevention. Right now only support `CANCEL_OLDEST`.
	Future<TransactionBlock> placeLimitOrder({
		required String poolId,
		required int price,
		required int quantity,
		required OrderType orderType,
		int? expirationTimestamp,
		LimitOrderType restriction = LimitOrderType.NO_RESTRICTION,
		int? clientOrderId,
		SelfMatchingPreventionStyle selfMatchingPrevention = SelfMatchingPreventionStyle.CANCEL_OLDEST,
	}) async {
    expirationTimestamp ??= DateTime.now().millisecondsSinceEpoch + ORDER_DEFAULT_EXPIRATION_IN_MS;
    clientOrderId ??= _nextClientOrderId();

		final txb = TransactionBlock();
		final args = [
			txb.object(poolId),
			txb.pureInt(clientOrderId),
			txb.pureInt(price),
			txb.pureInt(quantity),
			txb.pure(selfMatchingPrevention.index, BCS.U8),
			txb.pure(orderType == OrderType.bid, BCS.BOOL),
			txb.pureInt(expirationTimestamp),
			txb.pure(restriction.index, BCS.U8),
			txb.object(SUI_CLOCK_OBJECT_ID),
			txb.object(_checkAccountCap()),
		];
    final typeArgs = await getPoolTypeArgs(poolId);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::place_limit_order",
			typeArguments: typeArgs,
			arguments: args,
		);
		return txb;
	}

  /// Place a market order.
  /// 
  /// [poolId] Object id of pool, created after invoking createPool.
  /// 
  /// [quantity] Amount of quote asset to swap in base asset.
  /// 
  /// [orderType] bid for buying base with quote, ask for selling base for quote.
  /// 
  /// [baseCoin] the objectId or the coin object of the base coin.
  /// 
  /// [quoteCoin] the objectId or the coin object of the quote coin.
  /// 
  /// [clientOrderId] a client side defined order id for bookkeeping purpose. eg: "1" , "2", ... If omitted, the sdk will
	/// assign an increasing number starting from 0. But this number might be duplicated if you are using multiple sdk instances.
  /// 
  /// [recipientAddress] the address to receive the swapped asset. If omitted, `this.currentAddress` will be used. The function
	Future<TransactionBlock> placeMarketOrder({
		required String accountCap,
		required String poolId,
		required int quantity,
		required OrderType orderType,
		String? baseCoin,
		String? quoteCoin,
		int? clientOrderId,
		String? recipientAddress,
		TransactionBlock? txb
	}) async {
    recipientAddress ??= currentAddress;
    txb ??= TransactionBlock();
		final [baseAssetType, quoteAssetType] = await getPoolTypeArgs(poolId);
		if (baseCoin == null && orderType == OrderType.ask) {
			throw ArgumentError('Must specify a valid base coin for an ask order');
		} else if (quoteCoin == null && orderType == OrderType.bid) {
			throw ArgumentError('Must specify a valid quote coin for a bid order');
		}
		final emptyCoin = txb.moveCall(
			"0x2::coin::zero",
			typeArguments: [baseCoin != null ? quoteAssetType : baseAssetType],
			arguments: [],
		);

		final resp = txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::place_market_order",
			typeArguments: [baseAssetType, quoteAssetType],
			arguments: [
				txb.object(poolId),
        txb.object(_checkAccountCap(accountCap)),
				txb.pureInt(clientOrderId ?? _nextClientOrderId()),
        txb.pureInt(quantity),
				txb.pureBool(orderType == OrderType.bid),
				baseCoin != null ? txb.object(baseCoin) : emptyCoin,
				quoteCoin != null ? txb.object(quoteCoin) : emptyCoin,
				txb.object(SUI_CLOCK_OBJECT_ID),
			],
		);
    final base_coin_ret = resp[0];
    final quote_coin_ret = resp[1];
		final recipient = _checkAddress(recipientAddress);
		txb.transferObjects([base_coin_ret], txb.pureAddress(recipient));
		txb.transferObjects([quote_coin_ret], txb.pureAddress(recipient));

		return txb;
	}

  /// Swap exact quote for base.
  /// 
  /// [poolId] Object id of pool, created after invoking createPool.
  /// 
  /// [tokenObjectIn] Object id of the token to swap.
  /// 
  /// [amountIn] amount of token to buy or sell.
  /// 
  /// [currentAddress] current user address.
  /// 
  /// [clientOrderId] a client side defined order id for bookkeeping purpose, eg: "1" , "2", ... If omitted, the sdk will
	/// assign an increasing number starting from 0. But this number might be duplicated if you are using multiple sdk instances
	Future<TransactionBlock> swapExactQuoteForBase({
		required String poolId,
		required TransactionObjectInput tokenObjectIn,
		required int amountIn, // quantity of USDC
		required String currentAddress,
		int? clientOrderId,
		TransactionBlock? txb
	}) async {
    txb ??= TransactionBlock();
		// in this case, we assume that the tokenIn--tokenOut always exists.
		final resp = txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::swap_exact_quote_for_base",
			typeArguments: await getPoolTypeArgs(poolId),
			arguments: [
				txb.object(poolId),
				txb.pureInt(clientOrderId ?? _nextClientOrderId()),
				txb.object(_checkAccountCap()),
				txb.pureInt(amountIn),
				txb.object(SUI_CLOCK_OBJECT_ID),
				tokenObjectIn is String ? txb.object(tokenObjectIn) : tokenObjectIn,
			],
		);
    final base_coin_ret = resp[0];
    final quote_coin_ret = resp[1];
		txb.transferObjects([base_coin_ret], txb.pureAddress(currentAddress));
		txb.transferObjects([quote_coin_ret], txb.pureAddress(currentAddress));
		return txb;
	}

	/// Swap exact base for quote.
  /// 
  /// [poolId] Object id of pool, created after invoking createPool, eg: "0xcaee8e1c046b58e55196105f1436a2337dcaa0c340a7a8c8baf65e4afb8823a4"
  /// 
  /// [tokenObjectIn] Object id of the token to swap: eg: "0x6e566fec4c388eeb78a7dab832c9f0212eb2ac7e8699500e203def5b41b9c70d"
  /// 
  /// [amountIn] amount of token to buy or sell, eg: 10000000
  /// 
  /// [currentAddress] current user address, eg: "0xbddc9d4961b46a130c2e1f38585bbc6fa8077ce54bcb206b26874ac08d607966"
  /// 
  /// [clientOrderId] a client side defined order number for bookkeeping purpose. eg: "1" , "2", ...
	Future<TransactionBlock> swapExactBaseForQuote({
		required String poolId,
		required TransactionObjectInput tokenObjectIn,
		required int amountIn,
		required String currentAddress,
		int? clientOrderId,
    TransactionBlock? txb
	}) async {
		txb ??= TransactionBlock();
		final [baseAsset, quoteAsset] = await getPoolTypeArgs(poolId);
		// in this case, we assume that the tokenIn--tokenOut always exists.
		final resp = txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::swap_exact_base_for_quote",
			typeArguments: [baseAsset, quoteAsset],
			arguments: [
				txb.object(poolId),
				txb.pureInt(clientOrderId ?? _nextClientOrderId()),
				txb.object(_checkAccountCap()),
				txb.pureInt(amountIn),
        tokenObjectIn is String ? txb.object(tokenObjectIn) : tokenObjectIn,
				txb.moveCall(
					"0x2::coin::zero",
					typeArguments: [quoteAsset],
					arguments: [],
				),
				txb.object(SUI_CLOCK_OBJECT_ID),
			],
		);
    final base_coin_ret = resp[0];
    final quote_coin_ret = resp[1];
		txb.transferObjects([base_coin_ret], txb.pureAddress(currentAddress));
		txb.transferObjects([quote_coin_ret], txb.pureAddress(currentAddress));
		return txb;
	}

  /// Cancel an order.
  /// 
  /// [poolId] Object id of pool, created after invoking createPool, eg: "0xcaee8e1c046b58e55196105f1436a2337dcaa0c340a7a8c8baf65e4afb8823a4"
  /// 
  /// [orderId] orderId of a limit order, you can find them through function query.list_open_orders eg: "0"
	Future<TransactionBlock> cancelOrder({
    required String poolId,
    required int orderId
  }) async {
		final txb = TransactionBlock();
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::cancel_order",
			typeArguments: await getPoolTypeArgs(poolId),
			arguments: [txb.object(poolId), txb.pureInt(orderId), txb.object(_checkAccountCap())],
		);
		return txb;
	}

  /// Cancel all limit orders under a certain account capacity.
  /// 
  /// [poolId] Object id of pool, created after invoking createPool, eg: "0xcaee8e1c046b58e55196105f1436a2337dcaa0c340a7a8c8baf65e4afb8823a4"
	Future<TransactionBlock> cancelAllOrders(String poolId) async {
		final txb = TransactionBlock();
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::cancel_all_orders",
			typeArguments: await getPoolTypeArgs(poolId),
			arguments: [txb.object(poolId), txb.object(_checkAccountCap())],
		);
		return txb;
	}

  /// Batch cancel order.
  /// 
  /// [poolId] Object id of pool, created after invoking createPool.
  /// 
  /// [orderIds] array of order ids you want to cancel, you can find your open orders by query.list_open_orders eg: ["0", "1", "2"]
	Future<TransactionBlock> batchCancelOrder({
    required String poolId, 
    required List<String> orderIds
  }) async {
		final txb = TransactionBlock();
    final typeArgs = await getPoolTypeArgs(poolId);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::batch_cancel_order",
			typeArguments: typeArgs,
			arguments: [
				txb.object(poolId),
        deepbookBCS.ser('vector<u64>', orderIds),
				txb.object(_checkAccountCap()),
			],
		);
		return txb;
	}

  /// [poolId] Object id of pool, created after invoking createPool.
  /// 
  /// [orderIds] array of expired order ids to clean, eg: ["0", "1", "2"]
  /// 
  /// [orderOwners] array of Order owners, should be the owner addresses from the account capacities which placed the orders
	Future<TransactionBlock> cleanUpExpiredOrders({
		required String poolId,
		required List<String> orderIds,
		required List<String> orderOwners
	}) async {
		final txb = TransactionBlock();
    final typeArgs = await getPoolTypeArgs(poolId);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::clean_up_expired_orders",
			typeArguments: typeArgs,
			arguments: [
				txb.object(poolId),
				txb.object(SUI_CLOCK_OBJECT_ID),
        deepbookBCS.ser('vector<u64>', orderIds),
        deepbookBCS.ser('vector<address>', orderOwners)
			],
		);
		return txb;
	}

  /// Returns paginated list of pools created in DeepBook by querying for the `PoolCreated` event.
  /// 
  /// Warning: this method can return incomplete results if the upstream data source is pruned.
	Future<PaginatedPoolSummary> getAllPools({
    String? cursor,
    int? limit,
    bool descendingOrder = false
	}) async {
		final resp = await suiClient.queryEvents(
			{ "MoveEventType": "$PACKAGE_ID::$MODULE_CLOB::PoolCreated" },
			cursor: cursor,
      limit: limit,
      descendingOrder: descendingOrder
		);
		final pools = resp.data.map((event) {
			final rawEvent = event.parsedJson;
      return PoolSummary(
        rawEvent?["pool_id"] ?? "", 
        normalizeStructTagString(rawEvent?["base_asset"]["name"]), 
        normalizeStructTagString(rawEvent?["quote_asset"]["name"])
      );
		}).toList();
    return PaginatedPoolSummary(
      pools,
      resp.hasNextPage,
      EventId.fromJson(resp.nextCursor)
    );
	}

  /// Fetch metadata for a pool [poolId].
	Future<PoolSummary> getPoolInfo(String poolId) async {
		final resp = await suiClient.getObject(
			poolId,
			options: SuiObjectDataOptions(showContent: true),
		);
		if (resp.data?.content?.dataType != 'moveObject') {
			throw ArgumentError("pool $poolId does not exist");
		}

		final list = parseStructTag(resp.data!.content!.type).typeParams.map((t) =>
			normalizeStructTag(t),
		).toList();
    final baseAsset = list[0];
    final quoteAsset = list[1];
		return PoolSummary(
			poolId,
			baseAsset,
			quoteAsset,
    );
	}

	Future<List<String>> getPoolTypeArgs(String poolId) async {
		if (!_poolTypeArgsCache.containsKey(poolId)) {
			final poolInfo = await getPoolInfo(poolId);
			final typeArgs = [poolInfo.baseAsset, poolInfo.quoteAsset];
			_poolTypeArgsCache[poolId] = typeArgs;
		}

		return _poolTypeArgsCache[poolId]!;
	}

  /// Get the order status by pool id [poolId] and order id [orderId]
	Future<Order?> getOrderStatus({
		required String poolId,
		required int orderId,
		String? accountCap
	}) async {
    accountCap ??= this.accountCap;
		final txb = TransactionBlock();
		final cap = _checkAccountCap(accountCap);
    final typeArgs = await getPoolTypeArgs(poolId);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::get_order_status",
			typeArguments: typeArgs,
			arguments: [txb.object(poolId), txb.pureInt(orderId), txb.object(cap)],
		);
		final results = (
			await suiClient.devInspectTransactionBlock(
				currentAddress,
				txb,
			)
		).results;

		if (results == null || results.isEmpty) {
			return null;
		}

    final returnValues = results[0].returnValues![0][0] as List;
		final order = deepbookBCS.de('Order', Uint8List.fromList(returnValues.cast<int>()));
    return Order.fromJson(order);
	}

  /// Get the base and quote token in custodian account by [poolId] and [accountCap].
  /// 
  /// [poolId] eg: 0xcaee8e1c046b58e55196105f1436a2337dcaa0c340a7a8c8baf65e4afb8823a4
  /// 
  /// [accountCap] eg: 0x6f699fef193723277559c8f499ca3706121a65ac96d273151b8e52deb29135d3. If not provided, `this.accountCap` will be used.
	Future<UserPosition> getUserPosition({
		required String poolId,
		String? accountCap
	}) async {
		final txb = TransactionBlock();
		final cap = _checkAccountCap(accountCap);
    final typeArgs = await getPoolTypeArgs(poolId);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::account_balance",
			typeArguments: typeArgs,
			arguments: [txb.object(normalizeSuiObjectId(poolId)), txb.object(cap)],
		);

    final resp = await suiClient.devInspectTransactionBlock(
      currentAddress,
      txb,
    );

    final returnValues = resp.results![0].returnValues as List;
    final values = returnValues.map((item) => int.parse(deepbookBCS.de('u64', Uint8List.fromList((item[0] as List).cast<int>()))));
		final [availableBaseAmount, lockedBaseAmount, availableQuoteAmount, lockedQuoteAmount] = values.toList();
		return UserPosition(
			availableBaseAmount,
			lockedBaseAmount,
			availableQuoteAmount,
			lockedQuoteAmount,
    );
	}

  /// Get the open orders of the current user.
  /// 
  /// [poolId] the pool id. 
  /// 
  /// [accountCap] your accountCap. If not provided, `this.accountCap` will be used.
	Future<List<Order>> listOpenOrders({
		required String poolId,
		String? accountCap
	}) async {
		final txb = TransactionBlock();
		final cap = _checkAccountCap(accountCap);
    final typeArgs = await getPoolTypeArgs(poolId);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::list_open_orders",
			typeArguments: typeArgs,
			arguments: [txb.object(poolId), txb.object(cap)],
		);

		final results = (
			await suiClient.devInspectTransactionBlock(
				currentAddress,
				txb,
			)
		).results;

		if (results == null || results.isEmpty) {
			return [];
		}

    final returnValues = results[0].returnValues![0][0] as List;
		final orders = deepbookBCS.de('vector<Order>', Uint8List.fromList(returnValues.cast<int>()));
    return (orders as List).map((e) => Order.fromJson(e)).toList();
	}

  /// Get the market price {bestBidPrice, bestAskPrice} by pool id [poolId].
	Future<MarketPrice> getMarketPrice(String poolId) async {
		final txb = TransactionBlock();
    final typeArgs = await getPoolTypeArgs(poolId);
		txb.moveCall(
			"$PACKAGE_ID::$MODULE_CLOB::get_market_price",
			typeArguments: typeArgs,
			arguments: [txb.object(poolId)],
		);

    final results = (
			await suiClient.devInspectTransactionBlock(
				currentAddress,
				txb,
			)
		).results;

    final returnValues = results![0].returnValues as List;

    final resp = returnValues.map((val) {
      final opt = deepbookBCS.de('Option<u64>', Uint8List.fromList((val[0] as List).cast<int>()));
      return opt["Some"] != null ? int.tryParse(opt["Some"]) : null;
    }).toList();

    return MarketPrice(
      resp[0],
      resp[1]
    );
	}

  /// Get level2 book status.
  /// 
  /// [poolId] the pool id.
  /// 
  /// [lowerPrice] lower price you want to query in the level2 book, eg: 18000000000. The number must be an integer float scaled by `FLOAT_SCALING_FACTOR`.
  /// 
  /// [higherPrice] higher price you want to query in the level2 book, eg: 20000000000. The number must be an integer float scaled by `FLOAT_SCALING_FACTOR`.
  /// 
  /// [side] { 'bid' | 'ask' | 'both' } bid or ask or both sides.
	Future<dynamic> getLevel2BookStatus({
		required String poolId,
		required int lowerPrice,
		required int higherPrice,
		required OrderType side
	}) async {
		final txb = TransactionBlock();
    final typeArgs = await getPoolTypeArgs(poolId);
		if (side == OrderType.both) {
			txb.moveCall(
				"$PACKAGE_ID::$MODULE_CLOB::get_level2_book_status_bid_side",
				typeArguments: typeArgs,
				arguments: [
					txb.object(poolId),
					txb.pureInt(lowerPrice),
					txb.pureInt(higherPrice),
					txb.object(SUI_CLOCK_OBJECT_ID),
				],
			);
			txb.moveCall(
				"$PACKAGE_ID::$MODULE_CLOB::get_level2_book_status_ask_side",
				typeArguments: typeArgs,
				arguments: [
					txb.object(poolId),
					txb.pureInt(lowerPrice),
					txb.pureInt(higherPrice),
					txb.object(SUI_CLOCK_OBJECT_ID),
				]
			);
		} else {
			txb.moveCall(
				"$PACKAGE_ID::$MODULE_CLOB::get_level2_book_status_${side.name}_side",
				typeArguments: typeArgs,
				arguments: [
					txb.object(poolId),
					txb.pureInt(lowerPrice),
					txb.pureInt(higherPrice),
					txb.object(SUI_CLOCK_OBJECT_ID),
				]
			);
		}

	  final results = await suiClient.devInspectTransactionBlock(
			currentAddress,
			txb,
		);

		if (side == OrderType.both) {
			final bidSide = (results.results![0].returnValues as List).map((vals) =>
				bcs.de('vector<u64>', Uint8List.fromList((vals[0] as List).cast<int>()))
			).toList();
			final askSide = (results.results![1].returnValues as List).map((vals) =>
				bcs.de('vector<u64>', Uint8List.fromList((vals[0] as List).cast<int>()))
			).toList();

      List<Level2BookStatusPoint> bidSideList = [];
      (bidSide[0] as List).asMap().forEach((i, value) {
        bidSideList.add(Level2BookStatusPoint(int.parse(value), int.parse(bidSide[1][i])));
      });

      List<Level2BookStatusPoint> askSideList = [];
      (askSide[0] as List).asMap().forEach((i, value) {
        askSideList.add(Level2BookStatusPoint(int.parse(value), int.parse(askSide[1][i])));
      });

			return [
				bidSideList,
				askSideList,
			];
		} else {
			final result = (results.results![0].returnValues as List).map((vals) =>
				bcs.de('vector<u64>', Uint8List.fromList((vals[0] as List).cast<int>()))
			).toList();

      List<Level2BookStatusPoint> statusPoints = [];
      (result[0] as List).asMap().forEach((i, value) {
        statusPoints.add(Level2BookStatusPoint(int.parse(value), int.parse(result[1][i])));
      });

      return statusPoints;
		}
	}

	String _checkAccountCap([String? accountCap]) {
		final cap = accountCap ?? this.accountCap;
		if (cap == null) {
			throw ArgumentError('accountCap is undefined, please call setAccountCap() first');
		}
		return normalizeSuiObjectId(cap);
	}

	String _checkAddress(String recipientAddress) {
		if (recipientAddress == DUMMY_ADDRESS) {
			throw ArgumentError('Current address cannot be DUMMY_ADDRESS');
		}
		return normalizeSuiAddress(recipientAddress);
	}

	Future<String?> getCoinType(String coinId) async {
		final resp = await suiClient.getObject(
			coinId,
			options: SuiObjectDataOptions(showType: true),
		);

    final type = resp.data?.type;
    if (type == null) {
      return null;
    }

		final parsed = parseStructTag(type);

		// Modification handle case like 0x2::coin::Coin<0xf398b9ecb31aed96c345538fb59ca5a1a2c247c5e60087411ead6c637129f1c4::fish::FISH>
		if (parsed.address == NORMALIZED_SUI_COIN_TYPE.split('::')[0] &&
			parsed.module == 'coin' &&
			parsed.name == 'Coin' &&
			parsed.typeParams.isNotEmpty
		) {
			final firstTypeParam = parsed.typeParams[0];
			return firstTypeParam is StructTag
				? '${firstTypeParam.address}::${firstTypeParam.module}::${firstTypeParam.name}'
				: null;
		} else {
			return null;
		}
	}

	int _nextClientOrderId() {
		final id = clientOrderId;
		clientOrderId += 1;
		return id;
	}
}
