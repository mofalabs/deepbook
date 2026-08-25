/// Quantity (quote/estimate) queries, mirroring the official SDK's
/// `queries/quantityQueries.ts`.
library;

import 'dart:typed_data';

import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;

import '../config.dart';
import '../transactions/deepbook.dart';
import '../types.dart';
import 'query_context.dart';

/// Read-only quantity (quote/estimate) queries, executed by simulating
/// transactions.
class QuantityQueries {
  final QueryContext _ctx;
  final DeepBookContract _deepBook;

  /// Creates quantity queries that execute through the given query context.
  QuantityQueries(this._ctx) : _deepBook = DeepBookContract(_ctx.config);

  double _asDouble(Object value) =>
      value is BigInt ? value.toDouble() : (value as num).toDouble();

  /// The quote quantity received for selling [baseQuantity] (DEEP fees).
  Future<QuoteQuantityOut> getQuoteQuantityOut(
      String poolKey, Object baseQuantity) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getQuoteQuantityOut(poolKey, baseQuantity)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return QuoteQuantityOut(
      baseQuantity: _asDouble(baseQuantity),
      baseOut: double.parse((baseOut / baseScalar).toStringAsFixed(9)),
      quoteOut: double.parse((quoteOut / quoteScalar).toStringAsFixed(9)),
      deepRequired:
          double.parse((deepRequired / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// The base quantity received for spending [quoteQuantity] (DEEP fees).
  Future<BaseQuantityOut> getBaseQuantityOut(
      String poolKey, Object quoteQuantity) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getBaseQuantityOut(poolKey, quoteQuantity)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return BaseQuantityOut(
      quoteQuantity: _asDouble(quoteQuantity),
      baseOut: double.parse((baseOut / baseScalar).toStringAsFixed(9)),
      quoteOut: double.parse((quoteOut / quoteScalar).toStringAsFixed(9)),
      deepRequired:
          double.parse((deepRequired / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// The output quantities for [baseQuantity] or [quoteQuantity] (DEEP fees).
  Future<QuantityOut> getQuantityOut(
      String poolKey, Object baseQuantity, Object quoteQuantity) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getQuantityOut(poolKey, baseQuantity, quoteQuantity)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return QuantityOut(
      baseQuantity: _asDouble(baseQuantity),
      quoteQuantity: _asDouble(quoteQuantity),
      baseOut: double.parse((baseOut / baseScalar).toStringAsFixed(9)),
      quoteOut: double.parse((quoteOut / quoteScalar).toStringAsFixed(9)),
      deepRequired:
          double.parse((deepRequired / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// Like [getQuoteQuantityOut], with fees paid in the input token.
  Future<QuoteQuantityOut> getQuoteQuantityOutInputFee(
      String poolKey, Object baseQuantity) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getQuoteQuantityOutInputFee(poolKey, baseQuantity)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return QuoteQuantityOut(
      baseQuantity: _asDouble(baseQuantity),
      baseOut: double.parse((baseOut / baseScalar).toStringAsFixed(9)),
      quoteOut: double.parse((quoteOut / quoteScalar).toStringAsFixed(9)),
      deepRequired:
          double.parse((deepRequired / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// Like [getBaseQuantityOut], with fees paid in the input token.
  Future<BaseQuantityOut> getBaseQuantityOutInputFee(
      String poolKey, Object quoteQuantity) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getBaseQuantityOutInputFee(poolKey, quoteQuantity)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return BaseQuantityOut(
      quoteQuantity: _asDouble(quoteQuantity),
      baseOut: double.parse((baseOut / baseScalar).toStringAsFixed(9)),
      quoteOut: double.parse((quoteOut / quoteScalar).toStringAsFixed(9)),
      deepRequired:
          double.parse((deepRequired / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// Like [getQuantityOut], with fees paid in the input token.
  Future<QuantityOut> getQuantityOutInputFee(
      String poolKey, Object baseQuantity, Object quoteQuantity) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getQuantityOutInputFee(poolKey, baseQuantity, quoteQuantity)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return QuantityOut(
      baseQuantity: _asDouble(baseQuantity),
      quoteQuantity: _asDouble(quoteQuantity),
      baseOut: double.parse((baseOut / baseScalar).toStringAsFixed(9)),
      quoteOut: double.parse((quoteOut / quoteScalar).toStringAsFixed(9)),
      deepRequired:
          double.parse((deepRequired / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// The base quantity needed to receive [targetQuoteQuantity].
  Future<BaseQuantityIn> getBaseQuantityIn(
      String poolKey, Object targetQuoteQuantity, bool payWithDeep) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getBaseQuantityIn(poolKey, targetQuoteQuantity, payWithDeep)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseIn =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return BaseQuantityIn(
      baseIn: double.parse((baseIn / baseScalar).toStringAsFixed(9)),
      quoteOut: double.parse((quoteOut / quoteScalar).toStringAsFixed(9)),
      deepRequired:
          double.parse((deepRequired / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// The quote quantity needed to receive [targetBaseQuantity].
  Future<QuoteQuantityIn> getQuoteQuantityIn(
      String poolKey, Object targetBaseQuantity, bool payWithDeep) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getQuoteQuantityIn(poolKey, targetBaseQuantity, payWithDeep)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseOut =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteIn =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return QuoteQuantityIn(
      baseOut: double.parse((baseOut / baseScalar).toStringAsFixed(9)),
      quoteIn: double.parse((quoteIn / quoteScalar).toStringAsFixed(9)),
      deepRequired:
          double.parse((deepRequired / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// The DEEP required as taker/maker for an order of [baseQuantity] at
  /// [price].
  Future<OrderDeepRequiredResult> getOrderDeepRequired(
      String poolKey, Object baseQuantity, Object price) async {
    final tx = Transaction();
    _deepBook.getOrderDeepRequired(poolKey, baseQuantity, price)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final deepRequiredTaker =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final deepRequiredMaker =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();

    return OrderDeepRequiredResult(
      deepRequiredTaker:
          double.parse((deepRequiredTaker / DEEP_SCALAR).toStringAsFixed(9)),
      deepRequiredMaker:
          double.parse((deepRequiredMaker / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }
}
