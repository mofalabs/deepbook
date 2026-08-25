/// MarginManager queries, mirroring the official SDK's
/// `queries/marginManagerQueries.ts`.
library;

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/grpc/proto/sui/rpc/v2/transaction_execution_service.pb.dart'
    show CommandResult;
import 'package:sui/sui.dart' show Transaction;
import 'package:sui/types/common.dart' show normalizeSuiAddress;

import '../config.dart';
import '../errors.dart';
import '../transactions/margin_manager.dart';
import '../types.dart';
import 'query_context.dart';

class MarginManagerQueries {
  final QueryContext _ctx;
  final MarginManagerContract _marginManager;

  MarginManagerQueries(this._ctx)
      : _marginManager = MarginManagerContract(_ctx.config);

  Uint8List _bytes(CommandResult result, int index) =>
      Uint8List.fromList(result.returnValues[index].value.value);

  /// The owner address of the margin manager [marginManagerKey].
  Future<String> getMarginManagerOwner(String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.ownerByPoolKey(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return normalizeSuiAddress(SuiBcs.Address.parse(bytes));
  }

  /// The DeepBook pool id associated with margin manager [marginManagerKey].
  Future<String> getMarginManagerDeepbookPool(String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.deepbookPool(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return normalizeSuiAddress(SuiBcs.Address.parse(bytes));
  }

  /// The margin pool id (if any) associated with margin manager
  /// [marginManagerKey]; null when no loan is outstanding.
  Future<String?> getMarginManagerMarginPoolId(String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.marginPoolId(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final option = Bcs.option(SuiBcs.Address).parse(bytes);
    return option != null ? normalizeSuiAddress(option) : null;
  }

  /// Borrowed base and quote shares for margin manager [marginManagerKey].
  Future<BorrowedShares> getMarginManagerBorrowedShares(
      String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.borrowedShares(manager.poolKey, manager.address)(tx);

    final results = await _ctx.simulate(tx);
    final baseShares = SuiBcs.U64.parse(_bytes(results[0], 0)).toString();
    final quoteShares = SuiBcs.U64.parse(_bytes(results[0], 1)).toString();

    return BorrowedShares(baseShares: baseShares, quoteShares: quoteShares);
  }

  /// Borrowed base shares for margin manager [marginManagerKey].
  Future<String> getMarginManagerBorrowedBaseShares(
      String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.borrowedBaseShares(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toString();
  }

  /// Borrowed quote shares for margin manager [marginManagerKey].
  Future<String> getMarginManagerBorrowedQuoteShares(
      String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.borrowedQuoteShares(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.U64.parse(bytes).toString();
  }

  /// Whether margin manager [marginManagerKey] has base-asset debt.
  Future<bool> getMarginManagerHasBaseDebt(String marginManagerKey) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.hasBaseDebt(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    return SuiBcs.BOOL.parse(bytes);
  }

  /// The underlying BalanceManager id of the margin manager object at
  /// [marginManagerAddress], read directly from its on-chain contents.
  Future<String> getMarginManagerBalanceManagerId(
      String marginManagerAddress) async {
    final res = await _ctx.core
        .getObject(marginManagerAddress, readMask: const ['contents']);

    if (res.contents.value.isEmpty) {
      throw DeepBookError('Margin manager not found: $marginManagerAddress');
    }

    // Prefix of the on-chain MarginManager struct: the nested BalanceManager
    // starts with its UID, so parsing an Address at that position yields the
    // BalanceManager id (mirrors the official partial-struct parse).
    final marginManagerBalanceManagerId =
        Bcs.struct('MarginManagerBalanceManagerId', {
      'id': SuiBcs.Address,
      'owner': SuiBcs.Address,
      'deepbook_pool': SuiBcs.Address,
      'margin_pool_id': Bcs.option(SuiBcs.Address),
      'balance_manager_id': SuiBcs.Address,
    });

    final parsed = marginManagerBalanceManagerId
        .parse(Uint8List.fromList(res.contents.value));
    return normalizeSuiAddress(parsed['balance_manager_id'] as String);
  }

  /// Base and quote assets of margin manager [marginManagerKey], formatted
  /// with [decimals] fractional digits.
  Future<MarginManagerAssets> getMarginManagerAssets(String marginManagerKey,
      [int decimals = 6]) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.calculateAssets(manager.poolKey, manager.address)(tx);

    final results = await _ctx.simulate(tx);
    final pool = _ctx.config.getPool(manager.poolKey);
    final baseCoin = _ctx.config.getCoin(pool.baseCoin);
    final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);

    final baseAsset = formatTokenAmount(
        SuiBcs.U64.parse(_bytes(results[0], 0)), baseCoin.scalar, decimals);
    final quoteAsset = formatTokenAmount(
        SuiBcs.U64.parse(_bytes(results[0], 1)), quoteCoin.scalar, decimals);

    return MarginManagerAssets(baseAsset: baseAsset, quoteAsset: quoteAsset);
  }

  /// Base and quote debts of margin manager [marginManagerKey], formatted
  /// with [decimals] fractional digits.
  Future<MarginManagerDebts> getMarginManagerDebts(String marginManagerKey,
      [int decimals = 6]) async {
    final hasBaseDebt = await getMarginManagerHasBaseDebt(marginManagerKey);

    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final pool = _ctx.config.getPool(manager.poolKey);
    final debtCoinKey = hasBaseDebt ? pool.baseCoin : pool.quoteCoin;

    final tx = Transaction();
    _marginManager.calculateDebts(
        manager.poolKey, debtCoinKey, manager.address)(tx);

    final results = await _ctx.simulate(tx);
    if (results.isEmpty || results[0].returnValues.length < 2) {
      throw DeepBookError('Failed to get margin manager debts: Unknown error');
    }

    final debtCoin = _ctx.config.getCoin(debtCoinKey);
    final baseDebt = formatTokenAmount(
        SuiBcs.U64.parse(_bytes(results[0], 0)), debtCoin.scalar, decimals);
    final quoteDebt = formatTokenAmount(
        SuiBcs.U64.parse(_bytes(results[0], 1)), debtCoin.scalar, decimals);

    return MarginManagerDebts(baseDebt: baseDebt, quoteDebt: quoteDebt);
  }

  MarginManagerState _parseManagerState(
      CommandResult commandResult, String poolKey, int decimals) {
    final pool = _ctx.config.getPool(poolKey);
    final baseCoin = _ctx.config.getCoin(pool.baseCoin);
    final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);

    final managerId =
        normalizeSuiAddress(SuiBcs.Address.parse(_bytes(commandResult, 0)));
    final deepbookPoolId =
        normalizeSuiAddress(SuiBcs.Address.parse(_bytes(commandResult, 1)));
    final riskRatio =
        SuiBcs.U64.parse(_bytes(commandResult, 2)).toDouble() / FLOAT_SCALAR;
    final baseAsset = formatTokenAmount(
        SuiBcs.U64.parse(_bytes(commandResult, 3)), baseCoin.scalar, decimals);
    final quoteAsset = formatTokenAmount(
        SuiBcs.U64.parse(_bytes(commandResult, 4)), quoteCoin.scalar, decimals);
    final baseDebt = formatTokenAmount(
        SuiBcs.U64.parse(_bytes(commandResult, 5)), baseCoin.scalar, decimals);
    final quoteDebt = formatTokenAmount(
        SuiBcs.U64.parse(_bytes(commandResult, 6)), quoteCoin.scalar, decimals);
    final basePythPrice = SuiBcs.U64.parse(_bytes(commandResult, 7));
    final basePythDecimals = SuiBcs.U8.parse(_bytes(commandResult, 8));
    final quotePythPrice = SuiBcs.U64.parse(_bytes(commandResult, 9));
    final quotePythDecimals = SuiBcs.U8.parse(_bytes(commandResult, 10));
    final currentPrice = SuiBcs.U64.parse(_bytes(commandResult, 11));
    final lowestTriggerAbovePrice = SuiBcs.U64.parse(_bytes(commandResult, 12));
    final highestTriggerBelowPrice =
        SuiBcs.U64.parse(_bytes(commandResult, 13));

    return MarginManagerState(
      managerId: managerId,
      deepbookPoolId: deepbookPoolId,
      riskRatio: riskRatio,
      baseAsset: baseAsset,
      quoteAsset: quoteAsset,
      baseDebt: baseDebt,
      quoteDebt: quoteDebt,
      basePythPrice: basePythPrice.toString(),
      basePythDecimals: basePythDecimals,
      quotePythPrice: quotePythPrice.toString(),
      quotePythDecimals: quotePythDecimals,
      currentPrice: currentPrice,
      lowestTriggerAbovePrice: lowestTriggerAbovePrice,
      highestTriggerBelowPrice: highestTriggerBelowPrice,
    );
  }

  /// Comprehensive state of margin manager [marginManagerKey].
  Future<MarginManagerState> getMarginManagerState(String marginManagerKey,
      [int decimals = 6]) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.managerState(manager.poolKey, manager.address)(tx);

    final results = await _ctx.simulate(tx);
    if (results.isEmpty || results[0].returnValues.isEmpty) {
      throw DeepBookError('Failed to get margin manager state: Unknown error');
    }

    return _parseManagerState(results[0], manager.poolKey, decimals);
  }

  /// States for multiple margin managers, keyed by manager id.
  /// [marginManagers] maps manager id (address) to its pool key.
  Future<Map<String, MarginManagerState>> getMarginManagerStates(
      Map<String, String> marginManagers,
      [int decimals = 6]) async {
    final entries = marginManagers.entries.toList();
    if (entries.isEmpty) return {};

    final tx = Transaction();
    for (final entry in entries) {
      _marginManager.managerState(entry.value, entry.key)(tx);
    }

    final commandResults = await _ctx.simulate(tx);

    final results = <String, MarginManagerState>{};
    for (var i = 0; i < entries.length; i++) {
      if (i >= commandResults.length ||
          commandResults[i].returnValues.isEmpty) {
        throw DeepBookError('Failed to get margin manager state for index $i: '
            'No return values');
      }
      final state =
          _parseManagerState(commandResults[i], entries[i].value, decimals);
      results[state.managerId] = state;
    }
    return results;
  }

  /// Base asset balance of margin manager [marginManagerKey], formatted with
  /// [decimals] fractional digits.
  Future<String> getMarginManagerBaseBalance(String marginManagerKey,
      [int decimals = 9]) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.baseBalance(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final pool = _ctx.config.getPool(manager.poolKey);
    final baseCoin = _ctx.config.getCoin(pool.baseCoin);

    return formatTokenAmount(
        SuiBcs.U64.parse(bytes), baseCoin.scalar, decimals);
  }

  /// Quote asset balance of margin manager [marginManagerKey], formatted
  /// with [decimals] fractional digits.
  Future<String> getMarginManagerQuoteBalance(String marginManagerKey,
      [int decimals = 9]) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.quoteBalance(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final pool = _ctx.config.getPool(manager.poolKey);
    final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);

    return formatTokenAmount(
        SuiBcs.U64.parse(bytes), quoteCoin.scalar, decimals);
  }

  /// DEEP token balance of margin manager [marginManagerKey], formatted with
  /// [decimals] fractional digits.
  Future<String> getMarginManagerDeepBalance(String marginManagerKey,
      [int decimals = 6]) async {
    final manager = _ctx.config.getMarginManager(marginManagerKey);
    final tx = Transaction();
    _marginManager.deepBalance(manager.poolKey, manager.address)(tx);

    final bytes = await _ctx.simulateReturn(tx);
    final deepCoin = _ctx.config.getCoin('DEEP');

    return formatTokenAmount(
        SuiBcs.U64.parse(bytes), deepCoin.scalar, decimals);
  }

  /// Base/quote/DEEP balances for multiple margin managers, keyed by manager
  /// id. [marginManagers] maps manager id (address) to its pool key.
  Future<Map<String, MarginManagerBalancesResult>> getMarginManagerBalances(
      Map<String, String> marginManagers,
      [int decimals = 9]) async {
    final entries = marginManagers.entries.toList();
    if (entries.isEmpty) return {};

    final tx = Transaction();
    for (final entry in entries) {
      _marginManager.baseBalance(entry.value, entry.key)(tx);
      _marginManager.quoteBalance(entry.value, entry.key)(tx);
      _marginManager.deepBalance(entry.value, entry.key)(tx);
    }

    final commandResults = await _ctx.simulate(tx);

    final results = <String, MarginManagerBalancesResult>{};
    final deepCoin = _ctx.config.getCoin('DEEP');

    for (var i = 0; i < entries.length; i++) {
      final managerId = entries[i].key;
      final poolKey = entries[i].value;
      final pool = _ctx.config.getPool(poolKey);
      final baseCoin = _ctx.config.getCoin(pool.baseCoin);
      final quoteCoin = _ctx.config.getCoin(pool.quoteCoin);

      final baseResult = commandResults[i * 3];
      final quoteResult = commandResults[i * 3 + 1];
      final deepResult = commandResults[i * 3 + 2];

      if (baseResult.returnValues.isEmpty ||
          quoteResult.returnValues.isEmpty ||
          deepResult.returnValues.isEmpty) {
        throw DeepBookError('Failed to get balances for margin manager '
            '$managerId: No return values');
      }

      results[managerId] = MarginManagerBalancesResult(
        base: formatTokenAmount(
            SuiBcs.U64.parse(_bytes(baseResult, 0)), baseCoin.scalar, decimals),
        quote: formatTokenAmount(SuiBcs.U64.parse(_bytes(quoteResult, 0)),
            quoteCoin.scalar, decimals),
        deep: formatTokenAmount(
            SuiBcs.U64.parse(_bytes(deepResult, 0)), deepCoin.scalar, decimals),
      );
    }

    return results;
  }
}
