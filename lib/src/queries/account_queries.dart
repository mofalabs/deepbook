/// Account queries, mirroring the official SDK's `queries/accountQueries.ts`.
library;

import 'dart:typed_data';

import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;

import '../config.dart';
import '../contracts/deepbook/account.dart' as account_bcs;
import '../contracts/deepbook/deep_price.dart' as deep_price;
import '../transactions/deepbook.dart';
import '../types.dart';
import 'query_context.dart';

class AccountQueries {
  final QueryContext _ctx;
  final DeepBookContract _deepBook;

  AccountQueries(this._ctx) : _deepBook = DeepBookContract(_ctx.config);

  /// The account state of [managerKey] in [poolKey], in human units.
  Future<AccountInfo> account(String poolKey, String managerKey) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.account(poolKey, managerKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final accountInfo = account_bcs.Account.parse(bytes);

    final openOrders = (accountInfo['open_orders'] as Map)['contents'] as List;
    final unclaimedRebates = accountInfo['unclaimed_rebates'] as Map;
    final settledBalances = accountInfo['settled_balances'] as Map;
    final owedBalances = accountInfo['owed_balances'] as Map;

    return AccountInfo(
      epoch: accountInfo['epoch'].toString(),
      openOrders: [for (final id in openOrders) id.toString()],
      takerVolume:
          (accountInfo['taker_volume'] as BigInt).toDouble() / baseScalar,
      makerVolume:
          (accountInfo['maker_volume'] as BigInt).toDouble() / baseScalar,
      activeStake:
          (accountInfo['active_stake'] as BigInt).toDouble() / DEEP_SCALAR,
      inactiveStake:
          (accountInfo['inactive_stake'] as BigInt).toDouble() / DEEP_SCALAR,
      createdProposal: accountInfo['created_proposal'] as bool,
      votedProposal: accountInfo['voted_proposal'] as String?,
      unclaimedRebates: AccountBalances(
        base: (unclaimedRebates['base'] as BigInt).toDouble() / baseScalar,
        quote: (unclaimedRebates['quote'] as BigInt).toDouble() / quoteScalar,
        deep: (unclaimedRebates['deep'] as BigInt).toDouble() / DEEP_SCALAR,
      ),
      settledBalances: AccountBalances(
        base: (settledBalances['base'] as BigInt).toDouble() / baseScalar,
        quote: (settledBalances['quote'] as BigInt).toDouble() / quoteScalar,
        deep: (settledBalances['deep'] as BigInt).toDouble() / DEEP_SCALAR,
      ),
      owedBalances: AccountBalances(
        base: (owedBalances['base'] as BigInt).toDouble() / baseScalar,
        quote: (owedBalances['quote'] as BigInt).toDouble() / quoteScalar,
        deep: (owedBalances['deep'] as BigInt).toDouble() / DEEP_SCALAR,
      ),
    );
  }

  /// The locked balances of [balanceManagerKey] in [poolKey], in human units.
  Future<LockedBalances> lockedBalance(
      String poolKey, String balanceManagerKey) async {
    final pool = _ctx.config.getPool(poolKey);
    final baseScalar = _ctx.config.getCoin(pool.baseCoin).scalar;
    final quoteScalar = _ctx.config.getCoin(pool.quoteCoin).scalar;

    final tx = Transaction();
    _deepBook.lockedBalance(poolKey, balanceManagerKey)(tx);

    final res = await _ctx.simulate(tx);
    final rv = res[0].returnValues;
    final baseLocked =
        SuiBcs.U64.parse(Uint8List.fromList(rv[0].value.value)).toDouble();
    final quoteLocked =
        SuiBcs.U64.parse(Uint8List.fromList(rv[1].value.value)).toDouble();
    final deepLocked =
        SuiBcs.U64.parse(Uint8List.fromList(rv[2].value.value)).toDouble();

    return LockedBalances(
      base: double.parse((baseLocked / baseScalar).toStringAsFixed(9)),
      quote: double.parse((quoteLocked / quoteScalar).toStringAsFixed(9)),
      deep: double.parse((deepLocked / DEEP_SCALAR).toStringAsFixed(9)),
    );
  }

  /// The pool's DEEP price conversion rate, in human units.
  Future<PoolDeepPrice> getPoolDeepPrice(String poolKey) async {
    final pool = _ctx.config.getPool(poolKey);
    final tx = Transaction();
    _deepBook.getPoolDeepPrice(poolKey)(tx);

    final baseCoin = _ctx.config.getCoin(pool.baseCoin);
    final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);
    final deepCoin = _ctx.config.getCoin('DEEP');

    final bytes = await _ctx.simulateReturn(tx);
    final poolDeepPrice = deep_price.OrderDeepPrice.parse(bytes);

    final assetIsBase = poolDeepPrice['asset_is_base'] as bool;
    final deepPerAsset = (poolDeepPrice['deep_per_asset'] as BigInt).toDouble();

    if (assetIsBase) {
      return PoolDeepPrice(
        assetIsBase: assetIsBase,
        deepPerBase:
            deepPerAsset / FLOAT_SCALAR * baseCoin.scalar / deepCoin.scalar,
      );
    } else {
      return PoolDeepPrice(
        assetIsBase: assetIsBase,
        deepPerQuote:
            deepPerAsset / FLOAT_SCALAR * quoteCoin.scalar / deepCoin.scalar,
      );
    }
  }
}
