/// Execution-result decoders, mirroring `predict/decode.ts`.
///
/// Every `tx.*` builder returns a Transaction; after the app executes it
/// (with events included), the deployed contracts emit typed events carrying
/// the full receipt — order ids, fills, fees, queue indexes, new balances.
/// These pure functions turn that result into typed receipts. No network, no
/// client.
///
/// Decoding uses each event's BCS bytes, not a JSON rendering: BCS is
/// canonical across transports. Layouts come from the GENERATED event
/// MoveStructs (`lib/src/contracts/{deepbook_predict,account}/*_events.dart`),
/// whose field order mirrors the deployed Move — regenerate the bindings if
/// the package changes.
library;

import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:bcs/bcs.dart' show BcsType;
import 'package:sui/grpc/proto/sui/rpc/v2/event.pb.dart' as pb show Event;
import 'package:sui/types/common.dart' show normalizeSuiAddress;

import '../contracts/account/account_events.dart' as account_events;
import '../contracts/deepbook_predict/builder_code_events.dart'
    as builder_code_events;
import '../contracts/deepbook_predict/order_events.dart' as order_events;
import '../contracts/deepbook_predict/vault_events.dart' as vault_events;
import 'config.dart' show PredictConfig;
import 'errors.dart';
import 'units.dart' show fromRaw;

/// The slice of an executed/simulated transaction result the decoders need.
/// Transport-agnostic: construct from a gRPC event proto with
/// [DecodableEvent.fromProto], or structurally from any transport's fields.
class DecodableEvent {
  /// Full type tag `0xpkg::module::Name`.
  final String? eventType;

  /// Defining package id, when the transport supplies it separately.
  final String? packageId;

  /// Module short name, when supplied separately from a full type tag.
  final String? module;

  /// Struct name, when supplied separately from a full type tag.
  final String? name;

  /// Canonical BCS payload; a [Uint8List], or a base64 [String] on transports
  /// that deliver it encoded.
  final Object? bcs;

  const DecodableEvent({
    this.eventType,
    this.packageId,
    this.module,
    this.name,
    this.bcs,
  });

  /// Build from the gRPC `sui.rpc.v2.Event` proto (execute or simulate with
  /// events included).
  factory DecodableEvent.fromProto(pb.Event e) => DecodableEvent(
        eventType: e.eventType.isEmpty ? null : e.eventType,
        packageId: e.packageId.isEmpty ? null : e.packageId,
        module: e.module.isEmpty ? null : e.module,
        bcs: e.contents.value.isEmpty
            ? null
            : Uint8List.fromList(e.contents.value),
      );
}

/// The decodable slice of an executed/simulated transaction result.
class DecodableTransactionResult {
  final List<DecodableEvent>? events;
  const DecodableTransactionResult({this.events});

  /// Build from a gRPC event list.
  factory DecodableTransactionResult.fromProtoEvents(List<pb.Event> events) =>
      DecodableTransactionResult(
          events: [for (final e in events) DecodableEvent.fromProto(e)]);
}

// --- matching + plumbing ----------------------------------------------------

Uint8List? _eventBytes(DecodableEvent e) {
  final bcs = e.bcs;
  if (bcs is Uint8List) return bcs;
  if (bcs is String) return base64Decode(bcs);
  return null;
}

// Match by defining package + module + struct name. Events are typed by the
// package version that introduced their struct, not the latest Move-call
// target. All events decoded here were introduced in v1.
bool _matches(DecodableEvent e, String pkg, String module, String name) {
  final tag = e.eventType;
  if (tag != null) {
    final parts = tag.split('::');
    if (parts.length != 3) return false;
    return normalizeSuiAddress(parts[0]) == normalizeSuiAddress(pkg) &&
        parts[1] == module &&
        parts[2] == name;
  }
  // No type tag. Match on what the transport did give us — and on `name` when
  // it is present, because module+package alone matches EVERY struct in the
  // module, so one decoder would happily take another's event and fail deep
  // inside BCS.
  if (e.module != module || e.packageId == null) return false;
  if (normalizeSuiAddress(e.packageId!) != normalizeSuiAddress(pkg)) {
    return false;
  }
  return e.name == null || e.name == name;
}

List<T> _decodeAll<T>(
  DecodableTransactionResult result,
  String pkg,
  String module,
  String name,
  BcsType<dynamic, dynamic> layout,
  T Function(Map e) make,
) {
  final out = <T>[];
  for (final e in result.events ?? const <DecodableEvent>[]) {
    if (!_matches(e, pkg, module, name)) continue;
    final bytes = _eventBytes(e);
    if (bytes == null) {
      throw PredictInputError('$module::$name event has no BCS payload — '
          'execute/simulate with events included');
    }
    out.add(make(layout.parse(bytes) as Map));
  }
  return out;
}

/// Throw unless exactly one [what] receipt was decoded; return it. The
/// singular decoders use this; the plural forms return all matches (an
/// integrator batching N actions in one PTB gets N receipts).
T exactlyOne<T>(List<T> items, String what) {
  if (items.length != 1) {
    throw PredictInputError(
        'expected exactly one $what event, found ${items.length}');
  }
  return items[0];
}

String? _optId(Object? v) =>
    v == null ? null : normalizeSuiAddress(v as String);
BigInt _big(Object v) => BigInt.parse(v.toString());
BigInt? _optBig(Object? v) => v == null ? null : BigInt.parse(v.toString());

// --- receipts ---------------------------------------------------------------

/// Fee breakdown of a mint. `referral` is a PORTION of the trader-paid
/// trading fee and congestion surcharge routed to the referrer — it is
/// already inside those numbers and is NOT an extra debit; `inventoryImpact`
/// is a separate charge.
class MintReceiptFees {
  final double trading;
  final double subsidy;
  final double builder;
  final double penalty;
  final double referral;
  final double inventoryImpact;
  const MintReceiptFees({
    required this.trading,
    required this.subsidy,
    required this.builder,
    required this.penalty,
    required this.referral,
    required this.inventoryImpact,
  });
}

/// Exact integers of a mint receipt.
class MintReceiptRaw {
  final BigInt quantity;
  final BigInt premium;
  final BigInt tradingFee;
  final BigInt feeIncentiveSubsidy;
  final BigInt builderFee;
  final BigInt penaltyFee;
  final BigInt referralFee;
  final BigInt inventoryImpactCharge;
  final BigInt entryProbability;
  const MintReceiptRaw({
    required this.quantity,
    required this.premium,
    required this.tradingFee,
    required this.feeIncentiveSubsidy,
    required this.builderFee,
    required this.penaltyFee,
    required this.referralFee,
    required this.inventoryImpactCharge,
    required this.entryProbability,
  });
}

/// Typed `OrderMinted` receipt.
class MintReceipt {
  final String marketId;
  final String accountId;
  final String owner;

  /// Persist this: required to redeem/claim the position later.
  final BigInt orderId;

  /// Stable across partial-close replacements; equals orderId at mint.
  final BigInt positionRootId;
  final BigInt lowerTick;
  final BigInt higherTick;

  /// 0..1 range probability quoted at entry (your fill price per $1 payout).
  final double entryProbability;

  /// Max payout actually minted, in quote units (mintAmount: chain-floored).
  final double quantity;

  /// Premium paid into LP backing, in quote units.
  final double premium;
  final MintReceiptFees fees;
  final String? builderCodeId;
  final MintReceiptRaw raw;

  const MintReceipt({
    required this.marketId,
    required this.accountId,
    required this.owner,
    required this.orderId,
    required this.positionRootId,
    required this.lowerTick,
    required this.higherTick,
    required this.entryProbability,
    required this.quantity,
    required this.premium,
    required this.fees,
    required this.builderCodeId,
    required this.raw,
  });
}

/// Fee breakdown of a live close. `inventoryImpactRebate` is the
/// path-independent inventory-impact rebate credited back on the close.
class RedeemReceiptFees {
  final double trading;
  final double builder;
  final double penalty;
  final double inventoryImpactRebate;
  const RedeemReceiptFees({
    required this.trading,
    required this.builder,
    required this.penalty,
    required this.inventoryImpactRebate,
  });
}

/// Exact integers of a redeem receipt.
class RedeemReceiptRaw {
  final BigInt quantityClosed;
  final BigInt remaining;
  final BigInt proceeds;
  final BigInt gross;
  final BigInt tradingFee;
  final BigInt builderFee;
  final BigInt penaltyFee;
  final BigInt inventoryImpactRebate;
  const RedeemReceiptRaw({
    required this.quantityClosed,
    required this.remaining,
    required this.proceeds,
    required this.gross,
    required this.tradingFee,
    required this.builderFee,
    required this.penaltyFee,
    required this.inventoryImpactRebate,
  });
}

/// Typed `LiveOrderRedeemed` receipt.
class RedeemReceipt {
  final String marketId;
  final String accountId;
  final String owner;
  final BigInt orderId;
  final BigInt positionRootId;
  final double quantityClosed;
  final double remaining;

  /// A partial close RETIRES the old order id and issues this replacement for
  /// the remaining quantity — update your stored id or it goes silently
  /// stale.
  final BigInt? replacementOrderId;

  /// NET quote credited to the account: gross + inventoryImpactRebate −
  /// trading − builder − penalty — the same expression the chain asserts
  /// `min_proceeds` against, and what `settle_live_redeem_payment` actually
  /// deposits.
  final double proceeds;

  /// Gross close value before fees (the event's redeem_amount).
  final double gross;
  final RedeemReceiptFees fees;
  final String? builderCodeId;
  final RedeemReceiptRaw raw;

  const RedeemReceipt({
    required this.marketId,
    required this.accountId,
    required this.owner,
    required this.orderId,
    required this.positionRootId,
    required this.quantityClosed,
    required this.remaining,
    required this.replacementOrderId,
    required this.proceeds,
    required this.gross,
    required this.fees,
    required this.builderCodeId,
    required this.raw,
  });
}

/// Typed `SettledOrderRedeemed` receipt. A settled claim closes the order in
/// full.
class ClaimReceipt {
  final String marketId;
  final String accountId;
  final String owner;
  final BigInt orderId;
  final BigInt positionRootId;

  /// Quote units paid out.
  final double payout;
  final BigInt rawPayout;

  const ClaimReceipt({
    required this.marketId,
    required this.accountId,
    required this.owner,
    required this.orderId,
    required this.positionRootId,
    required this.payout,
    required this.rawPayout,
  });
}

/// Typed `AccountCreated` receipt.
class CreateManagerReceipt {
  final String accountId;
  final String wrapperId;
  final String owner;
  final bool selfOwned;
  const CreateManagerReceipt({
    required this.accountId,
    required this.wrapperId,
    required this.owner,
    required this.selfOwned,
  });
}

/// Typed `Deposited`/`Withdrawn` receipt. Display values assume a 6-decimal
/// coin (quote + PLP both are).
class BalanceChangeReceipt {
  final String accountId;
  final String coinType;
  final double amount;
  final double newBalance;
  final BigInt rawAmount;
  final BigInt rawNewBalance;
  const BalanceChangeReceipt({
    required this.accountId,
    required this.coinType,
    required this.amount,
    required this.newBalance,
    required this.rawAmount,
    required this.rawNewBalance,
  });
}

/// Typed `SupplyRequested`/`WithdrawRequested` receipt.
class PlpRequestReceipt {
  /// `'supply'` or `'withdraw'`.
  final String kind;
  final String vaultId;
  final String accountId;
  final String recipient;

  /// Feed straight into cancelSupplyPlp / cancelWithdrawPlp.
  final BigInt index;

  /// Quote units for supply; PLP shares (6-dec) for withdraw.
  final double amount;
  final BigInt rawAmount;
  const PlpRequestReceipt({
    required this.kind,
    required this.vaultId,
    required this.accountId,
    required this.recipient,
    required this.index,
    required this.amount,
    required this.rawAmount,
  });
}

/// Typed `RequestCancelled` receipt.
class PlpCancelReceipt {
  final String vaultId;
  final String accountId;
  final String recipient;
  final BigInt index;
  final bool isSupply;

  /// Refund returned to the account (quote for supply, PLP for withdraw).
  final double amount;
  final BigInt rawAmount;
  const PlpCancelReceipt({
    required this.vaultId,
    required this.accountId,
    required this.recipient,
    required this.index,
    required this.isSupply,
    required this.amount,
    required this.rawAmount,
  });
}

/// Typed `BuilderCodeSet` receipt.
class BuilderCodeReceipt {
  final String accountId;
  final String owner;

  /// Null after unsetBuilderCode.
  final String? builderCodeId;
  const BuilderCodeReceipt({
    required this.accountId,
    required this.owner,
    required this.builderCodeId,
  });
}

// --- decoders (plural = all matching events, in event order) ----------------

/// All `OrderMinted` receipts in [result].
List<MintReceipt> decodeMints(
    PredictConfig cfg, DecodableTransactionResult result) {
  return _decodeAll(result, cfg.packages.predictV1, 'order_events',
      'OrderMinted', order_events.OrderMinted, (e) {
    final raw = MintReceiptRaw(
      quantity: _big(e['quantity'] as Object),
      premium: _big(e['premium'] as Object),
      tradingFee: _big(e['trading_fee'] as Object),
      feeIncentiveSubsidy: _big(e['fee_incentive_subsidy'] as Object),
      builderFee: _big(e['builder_fee'] as Object),
      penaltyFee: _big(e['penalty_fee'] as Object),
      referralFee: _big(e['referral_fee'] as Object),
      inventoryImpactCharge: _big(e['inventory_impact_charge'] as Object),
      entryProbability: _big(e['entry_probability'] as Object),
    );
    return MintReceipt(
      marketId: normalizeSuiAddress(e['expiry_market_id'] as String),
      accountId: normalizeSuiAddress(e['account_id'] as String),
      owner: normalizeSuiAddress(e['owner'] as String),
      orderId: _big(e['order_id'] as Object),
      positionRootId: _big(e['position_root_id'] as Object),
      lowerTick: _big(e['lower_tick'] as Object),
      higherTick: _big(e['higher_tick'] as Object),
      entryProbability: fromRaw(raw.entryProbability, 9),
      quantity: fromRaw(raw.quantity, 6),
      premium: fromRaw(raw.premium, 6),
      fees: MintReceiptFees(
        trading: fromRaw(raw.tradingFee, 6),
        subsidy: fromRaw(raw.feeIncentiveSubsidy, 6),
        builder: fromRaw(raw.builderFee, 6),
        penalty: fromRaw(raw.penaltyFee, 6),
        referral: fromRaw(raw.referralFee, 6),
        inventoryImpact: fromRaw(raw.inventoryImpactCharge, 6),
      ),
      builderCodeId: _optId(e['builder_code_id']),
      raw: raw,
    );
  });
}

/// All `LiveOrderRedeemed` receipts in [result].
List<RedeemReceipt> decodeRedeems(
    PredictConfig cfg, DecodableTransactionResult result) {
  return _decodeAll(result, cfg.packages.predictV1, 'order_events',
      'LiveOrderRedeemed', order_events.LiveOrderRedeemed, (e) {
    // Mirrors the deployed close-side accounting exactly (the same expression
    // `min_proceeds` is asserted against): the net credited to the account is
    // redeem_amount PLUS the inventory-impact rebate, minus trading, builder
    // and penalty fees. The event's redeem_amount is GROSS.
    final gross = _big(e['redeem_amount'] as Object);
    final trading = _big(e['trading_fee'] as Object);
    final builder = _big(e['builder_fee'] as Object);
    final penalty = _big(e['penalty_fee'] as Object);
    final rebate = _big(e['inventory_impact_rebate'] as Object);
    final proceeds = gross + rebate - trading - builder - penalty;
    final raw = RedeemReceiptRaw(
      quantityClosed: _big(e['quantity_closed'] as Object),
      remaining: _big(e['remaining_quantity'] as Object),
      proceeds: proceeds,
      gross: gross,
      tradingFee: trading,
      builderFee: builder,
      penaltyFee: penalty,
      inventoryImpactRebate: rebate,
    );
    return RedeemReceipt(
      marketId: normalizeSuiAddress(e['expiry_market_id'] as String),
      accountId: normalizeSuiAddress(e['account_id'] as String),
      owner: normalizeSuiAddress(e['owner'] as String),
      orderId: _big(e['order_id'] as Object),
      positionRootId: _big(e['position_root_id'] as Object),
      quantityClosed: fromRaw(raw.quantityClosed, 6),
      remaining: fromRaw(raw.remaining, 6),
      replacementOrderId: _optBig(e['replacement_order_id']),
      proceeds: fromRaw(proceeds, 6),
      gross: fromRaw(gross, 6),
      fees: RedeemReceiptFees(
        trading: fromRaw(trading, 6),
        builder: fromRaw(builder, 6),
        penalty: fromRaw(penalty, 6),
        inventoryImpactRebate: fromRaw(rebate, 6),
      ),
      builderCodeId: _optId(e['builder_code_id']),
      raw: raw,
    );
  });
}

/// All `SettledOrderRedeemed` receipts in [result].
List<ClaimReceipt> decodeClaims(
    PredictConfig cfg, DecodableTransactionResult result) {
  return _decodeAll(result, cfg.packages.predictV1, 'order_events',
      'SettledOrderRedeemed', order_events.SettledOrderRedeemed, (e) {
    final payout = _big(e['payout_amount'] as Object);
    return ClaimReceipt(
      marketId: normalizeSuiAddress(e['expiry_market_id'] as String),
      accountId: normalizeSuiAddress(e['account_id'] as String),
      owner: normalizeSuiAddress(e['owner'] as String),
      orderId: _big(e['order_id'] as Object),
      positionRootId: _big(e['position_root_id'] as Object),
      payout: fromRaw(payout, 6),
      rawPayout: payout,
    );
  });
}

/// All `AccountCreated` receipts in [result].
List<CreateManagerReceipt> decodeAccountsCreated(
    PredictConfig cfg, DecodableTransactionResult result) {
  return _decodeAll(result, cfg.packages.account, 'account_events',
      'AccountCreated', account_events.AccountCreated, (e) {
    return CreateManagerReceipt(
      accountId: normalizeSuiAddress(e['account_id'] as String),
      wrapperId: normalizeSuiAddress(e['wrapper_id'] as String),
      owner: normalizeSuiAddress(e['owner'] as String),
      selfOwned: e['self_owned'] as bool,
    );
  });
}

List<BalanceChangeReceipt> _decodeBalanceChanges(
    PredictConfig cfg, DecodableTransactionResult result, String name) {
  final layout =
      name == 'Deposited' ? account_events.Deposited : account_events.Withdrawn;
  return _decodeAll(
      result, cfg.packages.account, 'account_events', name, layout, (e) {
    final amount = _big(e['amount'] as Object);
    final newBalance = _big(e['new_balance'] as Object);
    return BalanceChangeReceipt(
      accountId: normalizeSuiAddress(e['account_id'] as String),
      coinType: e['coin_type'] as String,
      amount: fromRaw(amount, 6),
      newBalance: fromRaw(newBalance, 6),
      rawAmount: amount,
      rawNewBalance: newBalance,
    );
  });
}

/// All `Deposited` receipts in [result].
List<BalanceChangeReceipt> decodeDeposits(
        PredictConfig cfg, DecodableTransactionResult result) =>
    _decodeBalanceChanges(cfg, result, 'Deposited');

/// All `Withdrawn` receipts in [result].
List<BalanceChangeReceipt> decodeWithdrawals(
        PredictConfig cfg, DecodableTransactionResult result) =>
    _decodeBalanceChanges(cfg, result, 'Withdrawn');

/// All `SupplyRequested`/`WithdrawRequested` receipts in [result].
List<PlpRequestReceipt> decodePlpRequests(
    PredictConfig cfg, DecodableTransactionResult result) {
  final pkg = cfg.packages.predictV1;
  PlpRequestReceipt make(String kind, Map e) {
    final amount = _big(e['amount'] as Object);
    return PlpRequestReceipt(
      kind: kind,
      vaultId: normalizeSuiAddress(e['pool_vault_id'] as String),
      accountId: normalizeSuiAddress(e['account_id'] as String),
      recipient: normalizeSuiAddress(e['recipient'] as String),
      index: _big(e['index'] as Object),
      amount: fromRaw(amount, 6),
      rawAmount: amount,
    );
  }

  return [
    ..._decodeAll(result, pkg, 'vault_events', 'SupplyRequested',
        vault_events.SupplyRequested, (e) => make('supply', e)),
    ..._decodeAll(result, pkg, 'vault_events', 'WithdrawRequested',
        vault_events.WithdrawRequested, (e) => make('withdraw', e)),
  ];
}

/// All `RequestCancelled` receipts in [result].
List<PlpCancelReceipt> decodePlpCancels(
    PredictConfig cfg, DecodableTransactionResult result) {
  return _decodeAll(result, cfg.packages.predictV1, 'vault_events',
      'RequestCancelled', vault_events.RequestCancelled, (e) {
    final amount = _big(e['amount'] as Object);
    return PlpCancelReceipt(
      vaultId: normalizeSuiAddress(e['pool_vault_id'] as String),
      accountId: normalizeSuiAddress(e['account_id'] as String),
      recipient: normalizeSuiAddress(e['recipient'] as String),
      index: _big(e['index'] as Object),
      isSupply: e['is_supply'] as bool,
      amount: fromRaw(amount, 6),
      rawAmount: amount,
    );
  });
}

/// All `BuilderCodeSet` receipts in [result].
List<BuilderCodeReceipt> decodeBuilderCodeSets(
    PredictConfig cfg, DecodableTransactionResult result) {
  return _decodeAll(result, cfg.packages.predictV1, 'builder_code_events',
      'BuilderCodeSet', builder_code_events.BuilderCodeSet, (e) {
    return BuilderCodeReceipt(
      accountId: normalizeSuiAddress(e['account_id'] as String),
      owner: normalizeSuiAddress(e['owner'] as String),
      builderCodeId: _optId(e['builder_code_id']),
    );
  });
}
