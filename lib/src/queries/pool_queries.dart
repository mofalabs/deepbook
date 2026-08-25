/// Pool queries, mirroring the official SDK's `queries/poolQueries.ts`.
library;

import 'dart:typed_data';

import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;
import 'package:sui/types/common.dart' show normalizeSuiAddress;

import '../config.dart';
import '../transactions/deepbook.dart';
import '../types.dart';
import 'query_context.dart';

class PoolQueries {
  final QueryContext _ctx;
  final DeepBookContract _deepBook;

  PoolQueries(this._ctx) : _deepBook = DeepBookContract(_ctx.config);

  /// Whether the pool identified by [poolKey] is whitelisted.
  Future<bool> whitelisted(String poolKey) async {
    final tx = Transaction();
    _deepBook.whitelisted(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// The base/quote/DEEP balances held in the pool vault, in human units.
  Future<VaultBalances> vaultBalances(String poolKey) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.vaultBalances(poolKey)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseInVault =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteInVault =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepInVault =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return VaultBalances(
      base: double.parse((baseInVault / baseScalar).toStringAsFixed(9)),
      quote: double.parse((quoteInVault / quoteScalar).toStringAsFixed(9)),
      deep: double.parse((deepInVault / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// The pool id for the pair ([baseType], [quoteType]).
  Future<String> getPoolIdByAssets(String baseType, String quoteType) async {
    final tx = Transaction();
    _deepBook.getPoolIdByAssets(baseType, quoteType)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.Address.parse(bytes);
  }

  /// The mid price of the pool, in human units.
  Future<double> midPrice(String poolKey) async {
    final pool = _ctx.config.getPool(poolKey);
    final tx = Transaction();
    _deepBook.midPrice(poolKey)(tx);

    final baseCoin = _ctx.config.getCoin(pool.baseCoin);
    final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);

    final bytes = await _ctx.simulateReturn(tx);
    final parsedMidPrice = SuiBcs.U64.parse(bytes).toDouble();
    final adjustedMidPrice =
        parsedMidPrice * baseCoin.scalar / quoteCoin.scalar / FLOAT_SCALAR;

    return double.parse(adjustedMidPrice.toStringAsFixed(9));
  }

  /// The current trade params (taker fee, maker fee, stake required).
  Future<PoolTradeParams> poolTradeParams(String poolKey) async {
    final tx = Transaction();
    _deepBook.poolTradeParams(poolKey)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final takerFee =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final makerFee =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final stakeRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return PoolTradeParams(
      takerFee: takerFee / FLOAT_SCALAR,
      makerFee: makerFee / FLOAT_SCALAR,
      stakeRequired: stakeRequired / DEEP_SCALAR,
    );
  }

  /// The book params (tick size, lot size, min size), in human units.
  Future<PoolBookParams> poolBookParams(String poolKey) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.poolBookParams(poolKey)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final tickSize =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final lotSize =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final minSize =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return PoolBookParams(
      tickSize: tickSize * baseScalar / quoteScalar / FLOAT_SCALAR,
      lotSize: lotSize / baseScalar,
      minSize: minSize / baseScalar,
    );
  }

  /// Whether the pool is a stable pool.
  Future<bool> stablePool(String poolKey) async {
    final tx = Transaction();
    _deepBook.stablePool(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// Whether the pool is registered.
  Future<bool> registeredPool(String poolKey) async {
    final tx = Transaction();
    _deepBook.registeredPool(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// The trade params that will apply next epoch.
  Future<PoolTradeParams> poolTradeParamsNext(String poolKey) async {
    final tx = Transaction();
    _deepBook.poolTradeParamsNext(poolKey)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final takerFee =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final makerFee =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final stakeRequired =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return PoolTradeParams(
      takerFee: takerFee / FLOAT_SCALAR,
      makerFee: makerFee / FLOAT_SCALAR,
      stakeRequired: stakeRequired / DEEP_SCALAR,
    );
  }

  /// The governance quorum of the pool, in DEEP units.
  Future<double> quorum(String poolKey) async {
    final tx = Transaction();
    _deepBook.quorum(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final quorum = SuiBcs.U64.parse(bytes).toDouble();
    return quorum / DEEP_SCALAR;
  }

  /// The pool object id.
  Future<String> poolId(String poolKey) async {
    final tx = Transaction();
    _deepBook.poolId(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return normalizeSuiAddress(SuiBcs.Address.parse(bytes));
  }

  /// Whether a limit order with [params] could be placed.
  Future<bool> canPlaceLimitOrder(CanPlaceLimitOrderParams params) async {
    final tx = Transaction();
    _deepBook.canPlaceLimitOrder(params)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// Whether a market order with [params] could be placed.
  Future<bool> canPlaceMarketOrder(CanPlaceMarketOrderParams params) async {
    final tx = Transaction();
    _deepBook.canPlaceMarketOrder(params)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// Whether market order params ([quantity]) are valid for the pool.
  Future<bool> checkMarketOrderParams(String poolKey, Object quantity) async {
    final tx = Transaction();
    _deepBook.checkMarketOrderParams(poolKey, quantity)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// Whether limit order params are valid for the pool.
  Future<bool> checkLimitOrderParams(String poolKey, Object price,
      Object quantity, int expireTimestamp) async {
    final tx = Transaction();
    _deepBook.checkLimitOrderParams(
        poolKey, price, quantity, expireTimestamp)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }
}
