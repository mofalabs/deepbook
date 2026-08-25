/// Take Profit / Stop Loss queries, mirroring the official SDK's
/// `queries/tpslQueries.ts`.
library;

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;

import '../transactions/margin_tpsl.dart';
import 'query_context.dart';

class TPSLQueries {
  final QueryContext _ctx;
  final MarginTPSLContract _marginTPSL;

  TPSLQueries(this._ctx) : _marginTPSL = MarginTPSLContract(_ctx.config);

  /// All conditional order ids for margin manager [marginManagerKey].
  Future<List<String>> getConditionalOrderIds(String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginTPSL.conditionalOrderIds(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final orderIds = Bcs.vector(SuiBcs.U64).parse(bytes);
    return [for (final id in orderIds) id.toString()];
  }

  /// The lowest trigger price among trigger_above orders for margin manager
  /// [marginManagerKey]. Returns `max_u64` if there are none.
  Future<BigInt> getLowestTriggerAbovePrice(String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginTPSL.lowestTriggerAbovePrice(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes);
  }

  /// The highest trigger price among trigger_below orders for margin manager
  /// [marginManagerKey]. Returns 0 if there are none.
  Future<BigInt> getHighestTriggerBelowPrice(String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginTPSL.highestTriggerBelowPrice(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes);
  }
}
