/// Account custody-balance reads, mirroring `predict/reads/balances.ts`.
library;

import 'package:sui/sui.dart' show Transaction;

import '../../contracts/account/account.dart' as account;
import '../../contracts/deepbook_predict/predict_account.dart'
    as predict_account;
import '../config.dart' show GeneratedConfig;
import '../tx/common.dart' show deriveAccountWrapperIdFrom;
import 'inspect.dart';
import 'parse.dart';

/// An owner's stored account balance for [coinType] (the deployment's quote
/// coin unless the caller asks for another). Chains
/// `account::load_account(wrapper)` → `account::balance&lt;T&gt;(account, root,
/// clock)`; the u64 is command 1's return. The clock is auto-injected by the
/// generated `balance` wrapper; the wrapper id is derived off-chain (no
/// read).
Future<BigInt> accountBalance(
  ReadClient client,
  GeneratedConfig config,
  String owner,
  String coinType,
) async {
  final tx = Transaction();
  final acct = account.loadAccount(
    config: config,
    arguments: {'self': deriveAccountWrapperIdFrom(config, owner)},
  )(tx);
  account.balance(
    config: config,
    typeArguments: [coinType],
    arguments: {'self': acct},
  )(tx);
  final cmds = await inspectReturns(client, tx);
  return parseU64LE(cmds[1][0]);
}

/// Whether the owner's account still holds [orderId] on [marketId]. The cheap
/// on-chain validator for app-stored order ids (stale after a full close or a
/// partial-close replacement — see `RedeemReceipt.replacementOrderId`).
/// Chains `account::load_account(wrapper)` →
/// `predict_account::has_position(account, market_id, order_id)`.
Future<bool> hasPosition(
  ReadClient client,
  GeneratedConfig config,
  String owner,
  String marketId,
  BigInt orderId,
) async {
  final tx = Transaction();
  final acct = account.loadAccount(
    config: config,
    arguments: {'self': deriveAccountWrapperIdFrom(config, owner)},
  )(tx);
  predict_account.hasPosition(
    config: config,
    arguments: {
      'account': acct,
      'expiryMarketId': marketId,
      'orderId': orderId
    },
  )(tx);
  final cmds = await inspectReturns(client, tx);
  return parseBool(cmds[1][0]);
}
