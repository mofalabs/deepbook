/// BalanceManager queries, mirroring the official SDK's
/// `queries/balanceManagerQueries.ts`.
library;

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction;
import 'package:sui/types/common.dart' show normalizeSuiAddress;

import '../contracts/deepbook/pool.dart' as pool_calls;
import '../contracts/deepbook/registry.dart' as registry_calls;
import '../errors.dart';
import '../transactions/balance_manager.dart';
import '../types.dart';
import 'query_context.dart';

class BalanceManagerQueries {
  final QueryContext _ctx;
  final BalanceManagerContract _balanceManager;

  BalanceManagerQueries(this._ctx)
      : _balanceManager = BalanceManagerContract(_ctx.config);

  /// The balance of [coinKey] held by the configured manager [managerKey],
  /// in human units.
  Future<ManagerBalance> checkManagerBalance(
      String managerKey, String coinKey) async {
    final coin = _ctx.config.getCoin(coinKey);
    final tx = Transaction();
    _balanceManager.checkManagerBalance(managerKey, coinKey)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final balance = SuiBcs.U64.parse(bytes);
    final adjusted = balance.toDouble() / coin.scalar;
    return ManagerBalance(
      coinType: coin.type,
      balance: double.parse(adjusted.toStringAsFixed(9)),
    );
  }

  /// Like [checkManagerBalance], for a manager referenced by address.
  Future<ManagerBalance> checkManagerBalanceWithAddress(
      String managerAddress, String coinKey) async {
    final coin = _ctx.config.getCoin(coinKey);
    final tx = Transaction();
    tx.moveCall(
      '${_ctx.config.DEEPBOOK_PACKAGE_ID}::balance_manager::balance',
      arguments: [tx.object(managerAddress)],
      typeArguments: [coin.type],
    );

    final bytes = await _ctx.simulateReturn(tx);
    final balance = SuiBcs.U64.parse(bytes);
    final adjusted = balance.toDouble() / coin.scalar;
    return ManagerBalance(
      coinType: coin.type,
      balance: double.parse(adjusted.toStringAsFixed(9)),
    );
  }

  /// Balances for the cross product of [managerAddresses] × [coinKeys], keyed
  /// by manager address then coin type.
  Future<Map<String, Map<String, double>>> checkManagerBalancesWithAddress(
      List<String> managerAddresses, List<String> coinKeys) async {
    if (managerAddresses.isEmpty || coinKeys.isEmpty) return {};

    final coins = coinKeys.map(_ctx.config.getCoin).toList();
    final tx = Transaction();
    for (final managerAddress in managerAddresses) {
      for (final coin in coins) {
        tx.moveCall(
          '${_ctx.config.DEEPBOOK_PACKAGE_ID}::balance_manager::balance',
          arguments: [tx.object(managerAddress)],
          typeArguments: [coin.type],
        );
      }
    }

    final commandResults = await _ctx.simulate(tx);
    final results = <String, Map<String, double>>{};
    for (var m = 0; m < managerAddresses.length; m++) {
      final managerBalances = <String, double>{};
      for (var c = 0; c < coins.length; c++) {
        final coin = coins[c];
        final commandResult = commandResults[m * coins.length + c];
        if (commandResult.returnValues.isEmpty) {
          throw DeepBookError(
              'Failed to get balance for ${coin.type}: No return values');
        }
        final balance = SuiBcs.U64.parse(
            Uint8List.fromList(commandResult.returnValues[0].value.value));
        managerBalances[coin.type] =
            double.parse((balance.toDouble() / coin.scalar).toStringAsFixed(9));
      }
      results[managerAddresses[m]] = managerBalances;
    }
    return results;
  }

  /// The BalanceManager ids registered by [owner].
  Future<List<String>> getBalanceManagerIds(String owner) async {
    final tx = Transaction();
    registry_calls.getBalanceManagerIds(
      package: _ctx.config.DEEPBOOK_PACKAGE_ID,
      arguments: {'self': _ctx.config.REGISTRY_ID, 'owner': owner},
    )(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final ids = Bcs.vector(SuiBcs.Address).parse(bytes);
    return [for (final String id in ids) normalizeSuiAddress(id)];
  }

  /// Whether [managerKey] has an account in [poolKey].
  Future<bool> accountExists(String poolKey, String managerKey) async {
    final pool = _ctx.config.getPool(poolKey);
    final manager = _ctx.config.getBalanceManager(managerKey);
    final baseCoin = _ctx.config.getCoin(pool.baseCoin);
    final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);

    final tx = Transaction();
    pool_calls.accountExists(
      package: _ctx.config.DEEPBOOK_PACKAGE_ID,
      arguments: {'self': pool.address, 'balanceManager': manager.address},
      typeArguments: [baseCoin.type, quoteCoin.type],
    )(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }
}
