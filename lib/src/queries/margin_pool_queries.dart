/// MarginPool queries, mirroring the official SDK's
/// `queries/marginPoolQueries.ts`.
library;

import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;

import '../config.dart';
import '../transactions/margin_pool.dart';
import 'query_context.dart';

class MarginPoolQueries {
  final QueryContext _ctx;
  final MarginPoolContract _marginPool;

  MarginPoolQueries(this._ctx) : _marginPool = MarginPoolContract(_ctx.config);

  /// The margin pool id for [coinKey].
  Future<String> getMarginPoolId(String coinKey) async {
    final tx = Transaction();
    _marginPool.getId(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.Address.parse(bytes);
  }

  /// Whether DeepBook pool [deepbookPoolId] is allowed to borrow from the
  /// [coinKey] margin pool.
  Future<bool> isDeepbookPoolAllowed(
      String coinKey, String deepbookPoolId) async {
    final tx = Transaction();
    _marginPool.deepbookPoolAllowed(coinKey, deepbookPoolId)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// Total supply of the [coinKey] margin pool, formatted with [decimals]
  /// fractional digits.
  Future<String> getMarginPoolTotalSupply(String coinKey,
      [int decimals = 6]) async {
    final tx = Transaction();
    _marginPool.totalSupply(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final rawAmount = SuiBcs.U64.parse(bytes);
    final coin = _ctx.config.getCoin(coinKey);
    return formatTokenAmount(rawAmount, coin.scalar, decimals);
  }

  /// Total supply shares of the [coinKey] margin pool, formatted with
  /// [decimals] fractional digits.
  Future<String> getMarginPoolSupplyShares(String coinKey,
      [int decimals = 6]) async {
    final tx = Transaction();
    _marginPool.supplyShares(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final rawShares = SuiBcs.U64.parse(bytes);
    final coin = _ctx.config.getCoin(coinKey);
    return formatTokenAmount(rawShares, coin.scalar, decimals);
  }

  /// Total borrow of the [coinKey] margin pool, formatted with [decimals]
  /// fractional digits.
  Future<String> getMarginPoolTotalBorrow(String coinKey,
      [int decimals = 6]) async {
    final tx = Transaction();
    _marginPool.totalBorrow(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final rawAmount = SuiBcs.U64.parse(bytes);
    final coin = _ctx.config.getCoin(coinKey);
    return formatTokenAmount(rawAmount, coin.scalar, decimals);
  }

  /// Total borrow shares of the [coinKey] margin pool, formatted with
  /// [decimals] fractional digits.
  Future<String> getMarginPoolBorrowShares(String coinKey,
      [int decimals = 6]) async {
    final tx = Transaction();
    _marginPool.borrowShares(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final rawShares = SuiBcs.U64.parse(bytes);
    final coin = _ctx.config.getCoin(coinKey);
    return formatTokenAmount(rawShares, coin.scalar, decimals);
  }

  /// The last update timestamp (ms) of the [coinKey] margin pool.
  Future<int> getMarginPoolLastUpdateTimestamp(String coinKey) async {
    final tx = Transaction();
    _marginPool.lastUpdateTimestamp(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toInt();
  }

  /// The supply cap of the [coinKey] margin pool, formatted with [decimals]
  /// fractional digits.
  Future<String> getMarginPoolSupplyCap(String coinKey,
      [int decimals = 6]) async {
    final tx = Transaction();
    _marginPool.supplyCap(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final rawAmount = SuiBcs.U64.parse(bytes);
    final coin = _ctx.config.getCoin(coinKey);
    return formatTokenAmount(rawAmount, coin.scalar, decimals);
  }

  /// The max utilization rate of the [coinKey] margin pool (fraction).
  Future<double> getMarginPoolMaxUtilizationRate(String coinKey) async {
    final tx = Transaction();
    _marginPool.maxUtilizationRate(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The protocol spread of the [coinKey] margin pool (fraction).
  Future<double> getMarginPoolProtocolSpread(String coinKey) async {
    final tx = Transaction();
    _marginPool.protocolSpread(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The minimum borrow amount of the [coinKey] margin pool, formatted with
  /// [decimals] fractional digits.
  Future<String> getMarginPoolMinBorrow(String coinKey,
      [int decimals = 6]) async {
    final tx = Transaction();
    _marginPool.minBorrow(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final rawAmount = SuiBcs.U64.parse(bytes);
    final coin = _ctx.config.getCoin(coinKey);
    return formatTokenAmount(rawAmount, coin.scalar, decimals);
  }

  /// The current interest rate of the [coinKey] margin pool (fraction).
  Future<double> getMarginPoolInterestRate(String coinKey) async {
    final tx = Transaction();
    _marginPool.interestRate(coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// Supply shares held by supplier cap [supplierCapId] in the [coinKey]
  /// margin pool, formatted with [decimals] fractional digits.
  Future<String> getUserSupplyShares(String coinKey, String supplierCapId,
      [int decimals = 6]) async {
    final tx = Transaction();
    _marginPool.userSupplyShares(coinKey, supplierCapId)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final rawShares = SuiBcs.U64.parse(bytes);
    final coin = _ctx.config.getCoin(coinKey);
    return formatTokenAmount(rawShares, coin.scalar, decimals);
  }

  /// Supply amount held by supplier cap [supplierCapId] in the [coinKey]
  /// margin pool, formatted with [decimals] fractional digits.
  Future<String> getUserSupplyAmount(String coinKey, String supplierCapId,
      [int decimals = 6]) async {
    final tx = Transaction();
    _marginPool.userSupplyAmount(coinKey, supplierCapId)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final rawAmount = SuiBcs.U64.parse(bytes);
    final coin = _ctx.config.getCoin(coinKey);
    return formatTokenAmount(rawAmount, coin.scalar, decimals);
  }
}
