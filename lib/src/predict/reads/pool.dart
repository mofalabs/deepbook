/// Pool vault stats, mirroring `predict/reads/pool.ts`.
library;

import 'package:sui/sui.dart' show Transaction;

import '../../contracts/deepbook_predict/plp.dart' as plp;
import '../config.dart' show GeneratedConfig;
import 'inspect.dart';
import 'parse.dart';

/// The pool vault's four u64 stats.
class PoolStats {
  final BigInt plpTotalSupply;
  final BigInt idleBalance;
  final BigInt supplyRequestsPending;
  final BigInt withdrawRequestsPending;

  const PoolStats({
    required this.plpTotalSupply,
    required this.idleBalance,
    required this.supplyRequestsPending,
    required this.withdrawRequestsPending,
  });
}

/// The pool's four u64 vault stats batched into one PTB (command order fixed
/// below). `plp::{plp_total_supply, idle_balance, supply_requests_pending,
/// withdraw_requests_pending}(vault)`.
Future<PoolStats> poolStats(ReadClient client, GeneratedConfig config) async {
  final tx = Transaction();
  plp.plpTotalSupply(config: config)(tx);
  plp.idleBalance(config: config)(tx);
  plp.supplyRequestsPending(config: config)(tx);
  plp.withdrawRequestsPending(config: config)(tx);
  final cmds = await inspectReturns(client, tx);
  return PoolStats(
    plpTotalSupply: parseU64LE(cmds[0][0]),
    idleBalance: parseU64LE(cmds[1][0]),
    supplyRequestsPending: parseU64LE(cmds[2][0]),
    withdrawRequestsPending: parseU64LE(cmds[3][0]),
  );
}
