/// Order queries, mirroring the official SDK's `queries/orderQueries.ts`.
library;

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;

import '../config.dart';
import '../contracts/deepbook/deps/sui/vec_set.dart' as vec_set;
import '../contracts/deepbook/order.dart' as order;
import '../errors.dart';
import '../transactions/deepbook.dart';
import '../types.dart';
import 'query_context.dart';

/// Read-only order and order-book queries, executed by simulating
/// transactions.
class OrderQueries {
  final QueryContext _ctx;
  final DeepBookContract _deepBook;

  /// Creates order queries that execute through the given query context.
  OrderQueries(this._ctx) : _deepBook = DeepBookContract(_ctx.config);

  /// The open order ids of [managerKey] in [poolKey], as decimal u128 strings.
  Future<List<String>> accountOpenOrders(
      String poolKey, String managerKey) async {
    final tx = Transaction();
    _deepBook.accountOpenOrders(poolKey, managerKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final orderIds = vec_set.VecSet(Bcs.u128()).parse(bytes);
    return [for (final id in orderIds['contents'] as List) id.toString()];
  }

  /// The raw on-chain order for [orderId], as the parsed `Order` struct
  /// (snake_case fields, u64/u128 as BigInt), or null when not found.
  Future<Map<String, dynamic>?> getOrder(String poolKey, String orderId) async {
    final tx = Transaction();
    _deepBook.getOrder(poolKey, orderId)(tx);

    try {
      final bytes = await _ctx.simulateReturn(tx);
      return order.Order.parse(bytes);
    } on DeepBookError {
      return null;
    }
  }

  /// Like [getOrder], with quantities/prices normalized to human units
  /// (added keys: `isBid`, `normalized_price`), or null when not found.
  Future<Map<String, dynamic>?> getOrderNormalized(
      String poolKey, String orderId) async {
    final tx = Transaction();
    _deepBook.getOrder(poolKey, orderId)(tx);

    try {
      final bytes = await _ctx.simulateReturn(tx);
      final orderInfo = order.Order.parse(bytes);

      final baseCoin =
          _ctx.config.getCoin(_ctx.config.getPool(poolKey).baseCoin);
      final quoteCoin =
          _ctx.config.getCoin(_ctx.config.getPool(poolKey).quoteCoin);

      final encodedOrderId = orderInfo['order_id'] as BigInt;
      final isBid = encodedOrderId >> 127 == BigInt.zero;
      final rawPrice =
          ((encodedOrderId >> 64) & ((BigInt.one << 63) - BigInt.one))
              .toDouble();
      final normalizedPrice =
          rawPrice * baseCoin.scalar / quoteCoin.scalar / FLOAT_SCALAR;

      final orderDeepPrice =
          Map<String, dynamic>.from(orderInfo['order_deep_price'] as Map);
      orderDeepPrice['deep_per_asset'] =
          ((orderDeepPrice['deep_per_asset'] as BigInt).toDouble() /
                  DEEP_SCALAR)
              .toStringAsFixed(9);

      return {
        ...orderInfo,
        'quantity':
            ((orderInfo['quantity'] as BigInt).toDouble() / baseCoin.scalar)
                .toStringAsFixed(9),
        'filled_quantity':
            ((orderInfo['filled_quantity'] as BigInt).toDouble() /
                    baseCoin.scalar)
                .toStringAsFixed(9),
        'order_deep_price': orderDeepPrice,
        'isBid': isBid,
        'normalized_price': normalizedPrice.toStringAsFixed(9),
      };
    } on DeepBookError {
      return null;
    }
  }

  /// The raw on-chain orders for [orderIds], or null on failure.
  Future<List<Map<String, dynamic>>?> getOrders(
      String poolKey, List<String> orderIds) async {
    final tx = Transaction();
    _deepBook.getOrders(poolKey, orderIds)(tx);

    try {
      final bytes = await _ctx.simulateReturn(tx);
      return Bcs.vector(order.Order).parse(bytes);
    } on DeepBookError {
      return null;
    }
  }

  /// Level 2 order book in the price range [priceLow]..[priceHigh]
  /// ([isBid] selects the side), in human units.
  Future<Level2Range> getLevel2Range(
      String poolKey, Object priceLow, Object priceHigh, bool isBid) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseCoin = _ctx.config.getCoin(pool.baseCoin);
    final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);

    final tx = Transaction();
    _deepBook.getLevel2Range(poolKey, priceLow, priceHigh, isBid)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final parsedPrices =
        Bcs.vector(SuiBcs.U64).parse(Uint8List.fromList(rv[0].value.value));
    final parsedQuantities =
        Bcs.vector(SuiBcs.U64).parse(Uint8List.fromList(rv[1].value.value));

    return Level2Range(
      prices: [
        for (final price in parsedPrices)
          double.parse((price.toDouble() /
                  FLOAT_SCALAR /
                  quoteCoin.scalar *
                  baseCoin.scalar)
              .toStringAsFixed(9)),
      ],
      quantities: [
        for (final quantity in parsedQuantities)
          double.parse(
              (quantity.toDouble() / baseCoin.scalar).toStringAsFixed(9)),
      ],
    );
  }

  /// Level 2 order book [ticks] ticks away from the mid price on both sides,
  /// in human units.
  Future<Level2TicksFromMid> getLevel2TicksFromMid(
      String poolKey, int ticks) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseCoin = _ctx.config.getCoin(pool.baseCoin);
    final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);

    final tx = Transaction();
    _deepBook.getLevel2TicksFromMid(poolKey, ticks)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final bidParsedPrices =
        Bcs.vector(SuiBcs.U64).parse(Uint8List.fromList(rv[0].value.value));
    final bidParsedQuantities =
        Bcs.vector(SuiBcs.U64).parse(Uint8List.fromList(rv[1].value.value));
    final askParsedPrices =
        Bcs.vector(SuiBcs.U64).parse(Uint8List.fromList(rv[2].value.value));
    final askParsedQuantities =
        Bcs.vector(SuiBcs.U64).parse(Uint8List.fromList(rv[3].value.value));

    double toPrice(BigInt price) => double.parse(
        (price.toDouble() / FLOAT_SCALAR / quoteCoin.scalar * baseCoin.scalar)
            .toStringAsFixed(9));
    double toQuantity(BigInt quantity) => double.parse(
        (quantity.toDouble() / baseCoin.scalar).toStringAsFixed(9));

    return Level2TicksFromMid(
      bidPrices: [for (final p in bidParsedPrices) toPrice(p)],
      bidQuantities: [for (final q in bidParsedQuantities) toQuantity(q)],
      askPrices: [for (final p in askParsedPrices) toPrice(p)],
      askQuantities: [for (final q in askParsedQuantities) toQuantity(q)],
    );
  }

  /// The raw on-chain order details of every open order [managerKey] has in
  /// [poolKey] (empty list on failure).
  Future<List<Map<String, dynamic>>> getAccountOrderDetails(
      String poolKey, String managerKey) async {
    final tx = Transaction();
    _deepBook.getAccountOrderDetails(poolKey, managerKey)(tx);

    try {
      final bytes = await _ctx.simulateReturn(tx);
      return Bcs.vector(order.Order).parse(bytes);
    } on DeepBookError {
      return [];
    }
  }

  /// Decodes an encoded u128 order id into side, raw price and order id.
  /// Mirrors the official client's `decodeOrderId`.
  static DecodedOrderId decodeOrderId(BigInt encodedOrderId) {
    final isBid = encodedOrderId >> 127 == BigInt.zero;
    final price =
        ((encodedOrderId >> 64) & ((BigInt.one << 63) - BigInt.one)).toDouble();
    final orderId = encodedOrderId & ((BigInt.one << 64) - BigInt.one);
    return DecodedOrderId(isBid: isBid, price: price, orderId: orderId);
  }
}
