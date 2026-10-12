/// Time-limited trading sessions over a canonical Account, mirroring the
/// official SDK's `src/sessions.ts` (`@mysten/deepbook-v3/sessions`).
///
/// Every builder returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

// Official constant names are kept verbatim.
// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show Transaction, TransactionResult;
import 'package:sui/utils/dynamic_fields.dart' show deriveDynamicFieldID;

import '../account/account_contract.dart';
import '../account/derived_objects.dart';
import '../contracts/account/account_registry.dart' as account_registry;
import '../contracts/deepbook_sessions/sessions.dart' as sessions;
import '../deployments/deployments.dart';
import '../errors.dart';

/// Deployed ids the sessions builders address.
///
/// [accountPackageId] / [accountRegistry] are the same shared-account ids
/// [AccountContract] takes — sessions is an Account app, so it addresses the
/// same registry. [sessionsPackageId] and [sessionsConfig] come from the
/// sessions deployment.
class SessionsConfig {
  /// The latest `deepbook_sessions` Move-call package id.
  final String sessionsPackageId;

  /// Original ID for v1 structs. Omit only for an unupgraded custom
  /// deployment.
  final String? sessionsPackageIdV1;

  /// The shared `SessionsConfig` object id.
  final String sessionsConfig;

  /// The shared `account` Move package id.
  final String accountPackageId;

  /// The shared `AccountRegistry` object id.
  final String accountRegistry;

  const SessionsConfig({
    required this.sessionsPackageId,
    this.sessionsPackageIdV1,
    required this.sessionsConfig,
    required this.accountPackageId,
    required this.accountRegistry,
  });
}

/// Ids the DeepBook **spot** session wrappers need on top of
/// [SessionsConfig]. The Predict wrappers never take these, so they are kept
/// off the main config rather than made optional there.
abstract interface class SessionsSpotIds {
  /// DeepBook's shared `Registry` — `deepbook_registry` on the spot
  /// entrypoints.
  String get deepbookRegistry;

  /// The `deepbook_core_account` Move package id.
  String get deepbookCoreAccountPackageId;
}

/// Ids the Predict session wrappers need beyond [SessionsConfig].
abstract interface class SessionsPredictIds {
  /// Every Predict wrapper takes `config: &ProtocolConfig`.
  String get protocolConfig;
}

/// A [SessionsConfig] that also carries the [SessionsSpotIds] and
/// [SessionsPredictIds] of a recorded deployment — what [getSessionsConfig]
/// returns.
class SessionsDeploymentConfig extends SessionsConfig
    implements SessionsSpotIds, SessionsPredictIds {
  @override
  final String deepbookRegistry;
  @override
  final String deepbookCoreAccountPackageId;
  @override
  final String protocolConfig;

  const SessionsDeploymentConfig({
    required super.sessionsPackageId,
    super.sessionsPackageIdV1,
    required super.sessionsConfig,
    required super.accountPackageId,
    required super.accountRegistry,
    required this.deepbookRegistry,
    required this.deepbookCoreAccountPackageId,
    required this.protocolConfig,
  });

  /// The deployment record's ids, verbatim.
  SessionsDeploymentConfig._of(SessionsIds ids)
      : this(
          sessionsPackageId: ids.sessionsPackageId,
          sessionsPackageIdV1: ids.sessionsPackageIdV1,
          sessionsConfig: ids.sessionsConfig,
          accountPackageId: ids.accountPackageId,
          accountRegistry: ids.accountRegistry,
          deepbookRegistry: ids.deepbookRegistry,
          deepbookCoreAccountPackageId: ids.deepbookCoreAccountPackageId,
          protocolConfig: ids.protocolConfig,
        );
}

/// The deployed sessions ids for [network], so a caller does not transcribe
/// them. Generated from the deploy manifest — see `lib/src/deployments/`. The
/// returned object also carries [SessionsSpotIds] for the generated spot
/// wrappers.
///
/// Throws if the network has no recorded deployment, rather than returning
/// placeholder ids.
///
/// ```dart
/// final sessions = SessionsContract(getSessionsConfig('testnet'));
/// ```
SessionsDeploymentConfig getSessionsConfig(String network) {
  if (network == 'testnet') return _testnetSessionsConfig;
  if (network == 'mainnet') return _mainnetSessionsConfig;
  throw ConfigurationError(
      "deepbook/sessions: no sessions deployment recorded for network "
      "'$network'. Sessions is recorded for testnet and mainnet; for your "
      'own deployment construct a SessionsConfig and pass it to '
      'SessionsContract directly.');
}

final _testnetSessionsConfig = SessionsDeploymentConfig._of(testnetSessions);
final _mainnetSessionsConfig = SessionsDeploymentConfig._of(mainnetSessions);

/// The maximum session duration the contract accepts: 30 days, in
/// milliseconds.
const MAX_SESSION_DURATION_MS = 30 * 24 * 60 * 60 * 1000;

/// The maximum number of distinct session addresses one Account may store.
const MAX_SESSIONS_PER_ACCOUNT = 20;

// `sui::dynamic_field::Field<DataKey<SessionsApp>, SessionsData>` — what a
// core `getObject` on the grant field actually returns. `DataKey` is
// source-empty, but Move inserts a hidden `dummy_field: bool` into empty
// structs, so the name occupies ONE zero byte between the id and the value.
// Decoding the value alone would read the field id's first byte as the VecMap
// length: garbage grants, or a silent empty list.
final _sessionsDataField = Bcs.struct('Field<DataKey,SessionsData>', {
  'id': SuiBcs.Address,
  'name': SuiBcs.BOOL, // DataKey's hidden dummy_field
  'value': sessions.SessionsData,
});

/// One stored session grant.
class SessionGrant {
  /// The authorized ephemeral address.
  final String session;

  /// Absolute expiry, ms since epoch. The grant is dead AT this timestamp
  /// (strict `<`).
  final BigInt expiresAtMs;

  const SessionGrant({required this.session, required this.expiresAtMs});

  @override
  String toString() => 'SessionGrant($session, expiresAtMs: $expiresAtMs)';
}

/// SessionsContract — time-limited trading sessions over a canonical Account.
///
/// An Account owner authorizes an ephemeral address to submit a bounded set
/// of transactions on the Account's behalf until a fixed expiry. The session
/// key never receives a reusable `Auth`: each wrapper mints app authorization
/// internally and consumes it in the same call.
///
/// WHAT A SESSION KEY CAN DO. It cannot withdraw to an address, cannot grant
/// or revoke sessions, and cannot outlive its expiry — those all require
/// owner auth. It CAN trade the Account's full balance: the spot wrappers
/// take a caller-chosen `Pool` and, through `deepbook_core_account`, pull the
/// account's entire Base, Quote and DEEP balance (stored plus unsettled) into
/// the embedded manager for the duration of the call, with `price_limit`
/// supplied by the caller. Nothing caps notional, restricts which pools are
/// reachable, or bounds loss to adverse pricing. Treat a session key as
/// authority over everything the Account holds, and fund an
/// ephemeral-session Account accordingly.
///
/// Operational precondition: an admin must have authorized `SessionsApp` on
/// the account registry. Until then — or after a `deauthorize_app` — the
/// TRADING wrappers abort with `EAppNotAuthorized`; [authorizeSession],
/// [revokeSession] and [sessionExpirationMs] use owner auth or no auth and
/// keep working. Note that `deauthorize_app` does not clear `SessionsData`,
/// so re-authorizing makes every still-unexpired grant live again at once —
/// it is a pause, not a kill switch. Revoking, and reading expirations, also
/// keep working if the sessions package is later version-gated.
///
/// This class wraps the session lifecycle and the **Predict** entrypoints.
/// The DeepBook spot session wrappers are generated (see the flat-exported
/// `placeLimitOrder` / `placeMarketOrder` / `cancelLiveOrder` /
/// `cancelLiveOrders` / `withdrawSettledAmounts` builders) but are not
/// wrapped here — note `placeLimitOrder` and `placeMarketOrder` put
/// `accountRegistry` at index 2 and `sessionsConfig` at 4, because
/// `deepbookRegistry` sits between them; the other three take no
/// `deepbookRegistry` and so keep 1 and 3 like the Predict wrappers: the
/// surrounding spot-over-Account workflow — discovering the embedded balance
/// manager, reading resting orders and locked balances — is not modelled yet,
/// so a wrapped builder would be hard to use well. They are reachable from
/// the generated bindings meanwhile.
class SessionsContract {
  final SessionsConfig _config;

  SessionsContract(this._config);

  // The generated builders resolve the package address and auto-inject the
  // shared `SessionsConfig` from this map. `accountRegistry` stays an
  // explicit argument — it belongs to the account package, which is a
  // separate codegen entry.
  Map<String, dynamic> get _generatedConfig => {
        'sessionsPackageId': _config.sessionsPackageId,
        'sessionsConfig': _config.sessionsConfig,
      };

  /// The owner's canonical `AccountWrapper` id — derived off-chain, no read.
  /// Every builder here takes that id.
  String deriveAccountWrapperId(String owner) => AccountContract(AccountConfig(
        accountPackageId: _config.accountPackageId,
        accountRegistry: _config.accountRegistry,
      )).deriveAccountWrapperId(owner);

  /// The owner's canonical ACCOUNT id — a different derived object from the
  /// wrapper. The session grants hang off this one, so this is what
  /// [deriveSessionsFieldId] and [decodeSessions] work from.
  String deriveAccountId(String owner) {
    // `AccountKey(owner)` is a one-field positional struct: 32 bytes.
    final key = Uint8List.fromList(
        account_registry.AccountKey.serialize([owner]).toBytes());
    return deriveObjectID(
      _config.accountRegistry,
      '${_config.accountPackageId}::account_registry::AccountKey',
      key,
    );
  }

  /// The object id of the owner's `DataKey<SessionsApp>` dynamic field —
  /// fetch this object and pass its BCS contents to [decodeSessions]. There
  /// is no bulk on-chain read, so this is the route to enumerating grants.
  String deriveSessionsFieldId(String owner) {
    // A PLAIN dynamic field, not a derived object: `account::attach` writes
    // it with `df::add` (`use fun df::add as UID.add`), whereas the account
    // and wrapper ids are claimed through `derived_object::claim`.
    // `deriveObjectID` would wrap the tag in
    // `0x2::derived_object::DerivedObjectKey<..>` and yield an id that
    // points at nothing.
    final sessionsPackage =
        _config.sessionsPackageIdV1 ?? _config.sessionsPackageId;
    return deriveDynamicFieldID(
      deriveAccountId(owner),
      '${_config.accountPackageId}::account::DataKey'
      '<$sessionsPackage::sessions::SessionsApp>',
      // DataKey is source-empty; Move's hidden `dummy_field: bool` is the
      // key's one byte.
      Uint8List.fromList([0]),
    );
  }

  /// Grant [session] authority over the Account until `now + durationMs`.
  /// Authority is derived from the transaction SENDER, so the owner must sign
  /// this. [durationMs] (int or BigInt, raw milliseconds) must be > 0 and
  /// <= [MAX_SESSION_DURATION_MS]; an Account holds at most
  /// [MAX_SESSIONS_PER_ACCOUNT] distinct addresses. Re-authorizing an address
  /// replaces its expiry in place and consumes no additional slot.
  void Function(Transaction) authorizeSession({
    required String wrapperId,
    required String session,
    required Object durationMs,
  }) =>
      (tx) {
        sessions.authorizeSession(
          config: _generatedConfig,
          arguments: {
            'wrapper': wrapperId,
            'session': session,
            'durationMs': durationMs,
          },
        )(tx);
      };

  /// Remove [session]'s grant. Owner-signed, like [authorizeSession].
  /// Deliberately takes no `SessionsConfig`: revocation is not version-gated,
  /// so it keeps working after the package is retired. Revoking an address
  /// that holds no grant is a silent no-op — it neither aborts nor emits, so
  /// read before and after if you need to distinguish "revoked" from "was
  /// never granted".
  void Function(Transaction) revokeSession({
    required String wrapperId,
    required String session,
  }) =>
      (tx) {
        sessions.revokeSession(
          config: _generatedConfig,
          arguments: {'wrapper': wrapperId, 'session': session},
        )(tx);
      };

  /// Read one session's absolute expiry as `Option<u64>`. Compose in a
  /// dev-inspect/simulate PTB and decode the returned BCS. Not version-gated.
  TransactionResult Function(Transaction) sessionExpirationMs({
    required String wrapperId,
    required String session,
  }) =>
      (tx) => sessions.sessionExpirationMs(
            config: _generatedConfig,
            arguments: {'wrapper': wrapperId, 'session': session},
          )(tx);

  // === Predict wrappers ===
  //
  // Each mirrors the Predict entrypoint of the same name, with two
  // differences: the caller supplies NO `Auth` (the wrapper mints and
  // consumes app authorization internally), and `accountRegistry` +
  // `sessionsConfig` are threaded in. `pricer` is a PTB RESULT, not an
  // object — it comes from a preceding `expiry_market::load_live_pricer`
  // command in the same transaction. Everything else matches Predict
  // exactly, and Predict still performs all parameter validation.

  /// Mint a position of an exact payout quantity, as `session`. Pass
  /// `u64` max (`BigInt.parse('18446744073709551615')`) for [maxCost] /
  /// [maxProbability] to leave either slippage cap effectively unbounded —
  /// the chain asserts `value <= cap`, so the max value can never trip. Both
  /// are required; there is no default. Quantities are raw Move units, int
  /// or BigInt.
  ///
  /// Returns the new order id (u256).
  TransactionResult Function(Transaction) mintExactQuantity({
    required String expiryMarketId,
    required String wrapperId,
    required String protocolConfig,
    required dynamic pricer,
    required Object lowerTick,
    required Object higherTick,
    required Object quantity,
    required Object maxCost,
    required Object maxProbability,
  }) =>
      (tx) => sessions.mintExactQuantity(
            config: _generatedConfig,
            arguments: {
              'market': expiryMarketId,
              'accountRegistry': _config.accountRegistry,
              'wrapper': wrapperId,
              'config': protocolConfig,
              'pricer': pricer,
              'lowerTick': lowerTick,
              'higherTick': higherTick,
              'quantity': quantity,
              'maxCost': maxCost,
              'maxProbability': maxProbability,
            },
          )(tx);

  /// Mint by spending up to a premium budget, flooring the quantity
  /// received. The chain requires `maxCost > 0`. Amounts are raw Move units,
  /// int or BigInt.
  ///
  /// Returns the new order id (u256).
  TransactionResult Function(Transaction) mintExactAmount({
    required String expiryMarketId,
    required String wrapperId,
    required String protocolConfig,
    required dynamic pricer,
    required Object lowerTick,
    required Object higherTick,
    required Object maxPremium,
    required Object minQuantity,
    required Object maxCost,
  }) =>
      (tx) => sessions.mintExactAmount(
            config: _generatedConfig,
            arguments: {
              'market': expiryMarketId,
              'accountRegistry': _config.accountRegistry,
              'wrapper': wrapperId,
              'config': protocolConfig,
              'pricer': pricer,
              'lowerTick': lowerTick,
              'higherTick': higherTick,
              'maxPremium': maxPremium,
              'minQuantity': minQuantity,
              'maxCost': maxCost,
            },
          )(tx);

  /// Mint within an all-in budget as a session. Amounts are raw Move units.
  /// Requires Sessions/Predict v2 or later.
  TransactionResult Function(Transaction) mintExactCost({
    required String expiryMarketId,
    required String wrapperId,
    required String protocolConfig,
    required dynamic pricer,
    required Object lowerTick,
    required Object higherTick,
    required Object maxCost,
    required Object minQuantity,
  }) =>
      (tx) => sessions.mintExactCost(
            config: _generatedConfig,
            arguments: {
              'market': expiryMarketId,
              'accountRegistry': _config.accountRegistry,
              'wrapper': wrapperId,
              'config': protocolConfig,
              'pricer': pricer,
              'lowerTick': lowerTick,
              'higherTick': higherTick,
              'maxCost': maxCost,
              'minQuantity': minQuantity,
            },
          )(tx);

  /// Close part or all of a live position at the pricer's mark, as
  /// `session`. [minProbability] / [minProceeds] are close-side slippage
  /// floors; `0` disables either, and OMITTING them is `0` — unlike the mint
  /// caps, which are required. On a delegated key this is the direction that
  /// closes a position at any price, so pass real floors unless you mean to
  /// accept whatever the mark gives you.
  ///
  /// Returns `Option<u256>` — the replacement order id when a partial close
  /// leaves quantity open.
  TransactionResult Function(Transaction) redeemLive({
    required String expiryMarketId,
    required String wrapperId,
    required String protocolConfig,
    required dynamic pricer,
    required BigInt orderId,
    required Object closeQuantity,
    Object? minProbability,
    Object? minProceeds,
  }) =>
      (tx) => sessions.redeemLive(
            config: _generatedConfig,
            arguments: {
              'market': expiryMarketId,
              'accountRegistry': _config.accountRegistry,
              'wrapper': wrapperId,
              'config': protocolConfig,
              'pricer': pricer,
              'orderId': orderId,
              'closeQuantity': closeQuantity,
              'minProbability': minProbability ?? 0,
              'minProceeds': minProceeds ?? 0,
            },
          )(tx);

  /// Claim a settled position in full, as `session`. Takes no pricer — the
  /// settlement price is fixed — and no quantity: a settled claim is
  /// all-or-nothing.
  void Function(Transaction) redeemSettled({
    required String expiryMarketId,
    required String wrapperId,
    required String protocolConfig,
    required BigInt orderId,
  }) =>
      (tx) {
        sessions.redeemSettled(
          config: _generatedConfig,
          arguments: {
            'market': expiryMarketId,
            'accountRegistry': _config.accountRegistry,
            'wrapper': wrapperId,
            'config': protocolConfig,
            'orderId': orderId,
          },
        )(tx);
      };

  /// Decode an Account's stored grants from the raw BCS content of its
  /// `DataKey<SessionsApp>` dynamic FIELD object — the whole
  /// `Field<DataKey<SessionsApp>, SessionsData>`, as the core API returns
  /// it, not the inner `SessionsData`. Get the id from
  /// [deriveSessionsFieldId].
  ///
  /// There is no bulk on-chain read — [sessionExpirationMs] answers one
  /// address at a time — so listing grants means fetching that field and
  /// decoding it here. Note the field hangs off the DERIVED ACCOUNT address,
  /// not the wrapper address; they are different objects.
  ///
  /// Expired grants are never pruned automatically and keep occupying slots,
  /// so callers managing the [MAX_SESSIONS_PER_ACCOUNT] cap should list,
  /// drop anything already expired, and revoke before granting again.
  static List<SessionGrant> decodeSessions(Uint8List contents) {
    // Assert full consumption: re-serializing and comparing lengths turns
    // both truncation and trailing junk into a throw, so "no grants" can
    // only ever mean no grants.
    final field = _sessionsDataField.parse(contents) as Map;
    final reencoded = _sessionsDataField.serialize(field).toBytes();
    if (reencoded.length != contents.length) {
      throw ValidationError(
          'sessions field is ${contents.length} bytes but its contents '
          'encode to ${reencoded.length}; the bytes are truncated or carry '
          'trailing data');
    }
    final entries =
        ((field['value'] as Map)['sessions'] as Map)['contents'] as List;
    return [
      for (final entry in entries.cast<Map>())
        SessionGrant(
          session: entry['key'] as String,
          expiresAtMs: entry['value'] as BigInt,
        ),
    ];
  }

  /// Grants from [decodeSessions] that are still live at [nowMs] (int or
  /// BigInt, ms since epoch).
  static List<SessionGrant> activeSessions(
      List<SessionGrant> grants, Object nowMs) {
    final now = _toBigInt(nowMs);
    // The chain asserts `now < expiresAtMs`, so a grant is dead AT its
    // expiry.
    return grants.where((g) => now < g.expiresAtMs).toList();
  }

  /// Grants that are already dead at [nowMs] — the complement of
  /// [activeSessions], and the list to revoke when reclaiming slots. Use
  /// this rather than filtering by hand: `nowMs > expiresAtMs` looks
  /// equivalent but leaves the grant expiring exactly at [nowMs] occupying a
  /// slot forever.
  static List<SessionGrant> expiredSessions(
      List<SessionGrant> grants, Object nowMs) {
    final now = _toBigInt(nowMs);
    return grants.where((g) => now >= g.expiresAtMs).toList();
  }

  static BigInt _toBigInt(Object value) => switch (value) {
        BigInt v => v,
        int v => BigInt.from(v),
        _ => throw ValidationError(
            'expected int or BigInt, got ${value.runtimeType}'),
      };
}
