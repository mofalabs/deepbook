/// Referral queries, mirroring the official SDK's
/// `queries/referralQueries.ts`.
library;

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;
import 'package:sui/types/common.dart' show normalizeSuiAddress;

import '../config.dart';
import '../errors.dart';
import '../transactions/balance_manager.dart';
import '../transactions/deepbook.dart';
import '../types.dart';
import 'query_context.dart';

class ReferralQueries {
  final QueryContext _ctx;
  final DeepBookContract _deepBook;
  final BalanceManagerContract _balanceManager;

  ReferralQueries(this._ctx)
      : _deepBook = DeepBookContract(_ctx.config),
        _balanceManager = BalanceManagerContract(_ctx.config);

  /// The owner address of the referral object [referral].
  Future<String> balanceManagerReferralOwner(String referral) async {
    final tx = Transaction();
    _balanceManager.balanceManagerReferralOwner(referral)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.Address.parse(bytes);
  }

  /// The accumulated referral balances of [referral] in [poolKey], in human
  /// units.
  Future<ReferralBalances> getPoolReferralBalances(
      String poolKey, String referral) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.getPoolReferralBalances(poolKey, referral)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseBalance =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteBalance =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepBalance =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return ReferralBalances(
      base: baseBalance / baseScalar,
      quote: quoteBalance / quoteScalar,
      deep: deepBalance / DEEP_SCALAR,
    );
  }

  /// The pool id the referral object [referral] belongs to.
  Future<String> balanceManagerReferralPoolId(String referral) async {
    final tx = Transaction();
    _balanceManager.balanceManagerReferralPoolId(referral)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return normalizeSuiAddress(SuiBcs.Address.parse(bytes));
  }

  /// The rebate multiplier of [referral] in [poolKey].
  Future<double> poolReferralMultiplier(String poolKey, String referral) async {
    final tx = Transaction();
    _deepBook.poolReferralMultiplier(poolKey, referral)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toDouble() / FLOAT_SCALAR;
  }

  /// The referral id set on [managerKey] for [poolKey], or null when unset.
  Future<String?> getBalanceManagerReferralId(
      String managerKey, String poolKey) async {
    final tx = Transaction();
    _balanceManager.getBalanceManagerReferralId(managerKey, poolKey)(tx);

    try {
      final bytes = await _ctx.simulateReturn(tx);
      final optionId = Bcs.option(SuiBcs.Address).parse(bytes);
      if (optionId == null) return null;
      return normalizeSuiAddress(optionId);
    } on DeepBookError {
      return null;
    }
  }
}
