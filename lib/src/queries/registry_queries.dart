/// Margin registry queries, mirroring the official SDK's
/// `queries/registryQueries.ts`.
library;

import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;
import 'package:sui/types/common.dart' show normalizeSuiAddress;

import '../config.dart';
import '../contracts/deepbook/deps/sui/vec_set.dart' as vec_set;
import '../transactions/margin_registry.dart';
import 'query_context.dart';

class RegistryQueries {
  final QueryContext _ctx;
  final MarginRegistryContract _marginRegistry;

  RegistryQueries(this._ctx)
      : _marginRegistry = MarginRegistryContract(_ctx.config);

  /// Whether the deepbook pool [poolKey] is enabled for margin trading.
  Future<bool> isPoolEnabledForMargin(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.poolEnabled(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// The MarginManager ids registered by [owner].
  Future<List<String>> getMarginManagerIdsForOwner(String owner) async {
    final tx = Transaction();
    _marginRegistry.getMarginManagerIds(owner)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final vecSet = vec_set.VecSet(SuiBcs.Address).parse(bytes);
    return [
      for (final id in vecSet['contents'] as List)
        normalizeSuiAddress(id as String),
    ];
  }

  /// The base margin pool id for [poolKey].
  Future<String> getBaseMarginPoolId(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.baseMarginPoolId(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.Address.parse(bytes);
  }

  /// The quote margin pool id for [poolKey].
  Future<String> getQuoteMarginPoolId(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.quoteMarginPoolId(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.Address.parse(bytes);
  }

  /// The minimum withdraw risk ratio for [poolKey].
  Future<double> getMinWithdrawRiskRatio(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.minWithdrawRiskRatio(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The minimum borrow risk ratio for [poolKey].
  Future<double> getMinBorrowRiskRatio(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.minBorrowRiskRatio(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The minimum open risk ratio for [poolKey].
  Future<double> getMinOpenRiskRatio(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.minOpenRiskRatio(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The liquidation risk ratio for [poolKey].
  Future<double> getLiquidationRiskRatio(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.liquidationRiskRatio(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The target liquidation risk ratio for [poolKey].
  Future<double> getTargetLiquidationRiskRatio(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.targetLiquidationRiskRatio(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The user liquidation reward for [poolKey].
  Future<double> getUserLiquidationReward(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.userLiquidationReward(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The pool liquidation reward for [poolKey].
  Future<double> getPoolLiquidationReward(String poolKey) async {
    final tx = Transaction();
    _marginRegistry.poolLiquidationReward(poolKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The addresses allowed as margin maintainers.
  Future<List<String>> getAllowedMaintainers() async {
    final tx = Transaction();
    _marginRegistry.allowedMaintainers()(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final vecSet = vec_set.VecSet(SuiBcs.Address).parse(bytes);
    return [
      for (final id in vecSet['contents'] as List)
        normalizeSuiAddress(id as String),
    ];
  }

  /// The ids of the allowed pause caps.
  Future<List<String>> getAllowedPauseCaps() async {
    final tx = Transaction();
    _marginRegistry.allowedPauseCaps()(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final vecSet = vec_set.VecSet(SuiBcs.Address).parse(bytes);
    return [
      for (final id in vecSet['contents'] as List)
        normalizeSuiAddress(id as String),
    ];
  }
}
