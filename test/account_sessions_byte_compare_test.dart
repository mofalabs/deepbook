@TestOn('vm') // reads fixture files from disk
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart';
import 'package:deepbook/account.dart' as account;
import 'package:deepbook/sessions.dart' as sessions;

/// Builder-level cross-check of the /account and /sessions subpaths against
/// the OFFICIAL TypeScript SDK (`@mysten/deepbook-v3/account`, `/sessions`).
///
/// Fixtures in test/fixtures/byte_compare/ are the official Transaction JSON
/// for the same calls (regenerate with
/// tool/byte_compare/gen_fixtures_sessions.mjs). This test rebuilds the
/// identical transactions with the Dart SDK and requires the normalized
/// inputs (pure BCS bytes! / object ids) and command structure to match
/// exactly. It also checks the off-chain derivations (wrapper / account /
/// sessions-field ids) and the `decodeSessions` BCS parity.
void main() {
  const address =
      '0x00000000000000000000000000000000000000000000000000000000000000aa';
  const sessionKey =
      '0x00000000000000000000000000000000000000000000000000000000000000ab';
  const coin =
      '0x00000000000000000000000000000000000000000000000000000000000000ee';
  const market =
      '0x0000000000000000000000000000000000000000000000000000000000000011';
  const suiType = '0x2::sui::SUI';
  final u64Max = BigInt.parse('18446744073709551615');
  final orderId = BigInt.two.pow(200) + BigInt.from(7);

  final acct = account.AccountContract(account.getAccountConfig('testnet'));
  final customAcct = account.AccountContract(const account.AccountConfig(
    accountPackageId:
        '0x0000000000000000000000000000000000000000000000000000000000000077',
    accountRegistry:
        '0x0000000000000000000000000000000000000000000000000000000000000088',
  ));
  final sess = sessions.SessionsContract(sessions.getSessionsConfig('testnet'));
  final protocolConfig = sessions.getSessionsConfig('testnet').protocolConfig;

  final wrapper = acct.deriveAccountWrapperId(address);

  TransactionResult loadPricer(Transaction tx) => tx.moveCall(
        '${sessions.getSessionsConfig('testnet').sessionsPackageId}'
        '::expiry_market::load_live_pricer',
        arguments: [tx.object(market)],
      );

  final cases = <String, void Function(Transaction tx)>{
    'account_lifecycle': (tx) {
      acct.createAccount()(tx);
      acct.depositFunds(
          wrapperId: wrapper, coin: tx.object(coin), coinType: suiType)(tx);
      acct.withdrawFunds(
          wrapperId: wrapper,
          amount: BigInt.from(12345),
          coinType: suiType)(tx);
      acct.loadAccount(wrapperId: wrapper)(tx);
      acct.balance(owner: address, coinType: suiType)(tx);
    },
    'account_create_deposit': (tx) {
      customAcct.createAccountAndDeposit(
          coin: tx.object(coin), coinType: suiType)(tx);
      customAcct.generateAuth()(tx);
    },
    'sessions_lifecycle': (tx) {
      sess.authorizeSession(
          wrapperId: wrapper, session: sessionKey, durationMs: 86400000)(tx);
      sess.revokeSession(wrapperId: wrapper, session: sessionKey)(tx);
      sess.sessionExpirationMs(wrapperId: wrapper, session: sessionKey)(tx);
    },
    'sessions_predict_mint': (tx) {
      final pricer = loadPricer(tx);
      sess.mintExactQuantity(
        expiryMarketId: market,
        wrapperId: wrapper,
        protocolConfig: protocolConfig,
        pricer: pricer,
        lowerTick: 10,
        higherTick: 20,
        quantity: BigInt.from(5000000),
        maxCost: u64Max,
        maxProbability: u64Max,
      )(tx);
      sess.mintExactAmount(
        expiryMarketId: market,
        wrapperId: wrapper,
        protocolConfig: protocolConfig,
        pricer: pricer,
        lowerTick: 10,
        higherTick: 20,
        maxPremium: BigInt.from(1000000),
        minQuantity: BigInt.one,
        maxCost: BigInt.from(2000000),
      )(tx);
      sess.mintExactCost(
        expiryMarketId: market,
        wrapperId: wrapper,
        protocolConfig: protocolConfig,
        pricer: pricer,
        lowerTick: 10,
        higherTick: 20,
        maxCost: BigInt.from(3000000),
        minQuantity: BigInt.one,
      )(tx);
    },
    'sessions_predict_redeem': (tx) {
      final pricer = loadPricer(tx);
      sess.redeemLive(
        expiryMarketId: market,
        wrapperId: wrapper,
        protocolConfig: protocolConfig,
        pricer: pricer,
        orderId: orderId,
        closeQuantity: BigInt.from(1000000),
        // floors omitted on purpose: checks the `?? 0` default
      )(tx);
      sess.redeemSettled(
        expiryMarketId: market,
        wrapperId: wrapper,
        protocolConfig: protocolConfig,
        orderId: orderId,
      )(tx);
    },
  };

  // Fixtures are generated from the official TS SDK and are not shipped in
  // the published package; skip rather than fail when they are absent.
  if (!Directory('test/fixtures/byte_compare').existsSync()) {
    test('official SDK byte comparison (account/sessions)', () {
      markTestSkipped('fixtures absent — regenerate with '
          'tool/byte_compare/gen_fixtures_sessions.mjs');
    });
    return;
  }

  Map<String, dynamic> readFixture(String name) {
    final file = File('test/fixtures/byte_compare/$name.json');
    expect(file.existsSync(), isTrue,
        reason:
            'fixture missing — run tool/byte_compare/gen_fixtures_sessions.mjs');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  for (final entry in cases.entries) {
    test('matches official SDK builder output: ${entry.key}', () {
      final official = readFixture(entry.key);

      final tx = Transaction();
      tx.setSender(address);
      entry.value(tx);
      final ours = jsonDecode(tx.toJson()) as Map<String, dynamic>;

      expect(_normalize(ours), _normalize(official),
          reason: 'builder output diverges from official SDK');
    });
  }

  test('derivations match the official SDK on both networks', () {
    final fixture = File('test/fixtures/byte_compare/derive_parity.json');
    expect(fixture.existsSync(), isTrue,
        reason:
            'fixture missing — run tool/byte_compare/gen_fixtures_sessions.mjs');
    final rows = (jsonDecode(fixture.readAsStringSync()) as List).cast<Map>();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final s = sessions.SessionsContract(
          sessions.getSessionsConfig(row['network'] as String));
      final owner = row['owner'] as String;
      expect(s.deriveAccountWrapperId(owner), row['wrapperId'],
          reason: 'wrapper id for $owner on ${row['network']}');
      expect(s.deriveAccountId(owner), row['accountId'],
          reason: 'account id for $owner on ${row['network']}');
      expect(s.deriveSessionsFieldId(owner), row['sessionsFieldId'],
          reason: 'sessions field id for $owner on ${row['network']}');
    }
  });

  group('decodeSessions', () {
    test('decodes the official SDK byte layout identically', () {
      final fixture = readFixture('decode_sessions');
      final bytes = base64Decode(fixture['bytesBase64'] as String);
      final grants =
          sessions.SessionsContract.decodeSessions(Uint8List.fromList(bytes));
      final expected = (fixture['grants'] as List).cast<Map>();
      expect(grants.length, expected.length);
      for (var i = 0; i < grants.length; i++) {
        expect(grants[i].session, expected[i]['session']);
        expect(grants[i].expiresAtMs,
            BigInt.parse(expected[i]['expiresAtMs'] as String));
      }
    });

    test('rejects truncated or over-long bytes rather than misreading', () {
      final fixture = readFixture('decode_sessions');
      final bytes = base64Decode(fixture['bytesBase64'] as String);
      expect(
        () => sessions.SessionsContract.decodeSessions(
            Uint8List.fromList(bytes.sublist(0, bytes.length - 1))),
        throwsA(anything),
        reason: 'truncated field must not decode silently',
      );
      expect(
        () => sessions.SessionsContract.decodeSessions(
            Uint8List.fromList([...bytes, 0])),
        throwsA(anything),
        reason: 'trailing junk must not decode silently',
      );
    });

    test('active/expired split: a grant is dead AT its expiry', () {
      final grants = [
        sessions.SessionGrant(
            session: sessionKey, expiresAtMs: BigInt.from(1000)),
      ];
      expect(
          sessions.SessionsContract.activeSessions(grants, 999), hasLength(1));
      expect(sessions.SessionsContract.activeSessions(grants, 1000), isEmpty);
      expect(sessions.SessionsContract.expiredSessions(grants, 999), isEmpty);
      expect(sessions.SessionsContract.expiredSessions(grants, 1000),
          hasLength(1));
      expect(
          sessions.SessionsContract.activeSessions(grants, BigInt.from(999))
              .single
              .session,
          sessionKey);
    });
  });
}

/// Canonicalizes a Transaction JSON (either the official TS `toJSON()` shape
/// or the Dart builder snapshot) down to the semantically meaningful parts:
/// input kinds/payloads and command structure. Mirrors the helper in
/// byte_compare_test.dart.
Map<String, dynamic> _normalize(Map<String, dynamic> tx) {
  return {
    'sender': tx['sender'],
    'inputs': [
      for (final input in (tx['inputs'] as List).cast<Map>())
        _normalizeInput(input)
    ],
    'commands': [
      for (final command in (tx['commands'] as List).cast<Map>())
        _normalizeCommand(command)
    ],
  };
}

Map<String, dynamic> _normalizeInput(Map input) {
  if (input.containsKey('Pure')) {
    return {'pure': input['Pure']['bytes']};
  }
  if (input.containsKey('UnresolvedObject')) {
    return {'object': input['UnresolvedObject']['objectId']};
  }
  if (input.containsKey('Object')) {
    final object = input['Object'] as Map;
    final ref = (object['ImmOrOwnedObject'] ??
        object['SharedObject'] ??
        object['Receiving']) as Map;
    return {'object': ref['objectId']};
  }
  throw StateError('unknown input shape: $input');
}

dynamic _normalizeArgument(dynamic argument) {
  if (argument is Map) {
    if (argument.containsKey('Input')) return {'Input': argument['Input']};
    if (argument.containsKey('Result')) return {'Result': argument['Result']};
    if (argument.containsKey('NestedResult')) {
      return {'NestedResult': List.of(argument['NestedResult'] as List)};
    }
    if (argument.containsKey('GasCoin')) return 'GasCoin';
  }
  throw StateError('unknown argument shape: $argument');
}

Map<String, dynamic> _normalizeCommand(Map command) {
  final kind = command.keys.firstWhere((k) => k != r'$kind');
  final body = command[kind] as Map;
  switch (kind) {
    case 'MoveCall':
      return {
        'MoveCall': {
          'target':
              '${body['package']}::${body['module']}::${body['function']}',
          'typeArguments': List.of(body['typeArguments'] as List? ?? const []),
          'arguments': [
            for (final a in (body['arguments'] as List? ?? const []))
              _normalizeArgument(a)
          ],
        }
      };
    case 'TransferObjects':
      return {
        'TransferObjects': {
          'objects': [
            for (final o in (body['objects'] as List)) _normalizeArgument(o)
          ],
          'address': _normalizeArgument(body['address']),
        }
      };
    case 'SplitCoins':
      return {
        'SplitCoins': {
          'coin': _normalizeArgument(body['coin']),
          'amounts': [
            for (final a in (body['amounts'] as List)) _normalizeArgument(a)
          ],
        }
      };
    case 'MergeCoins':
      return {
        'MergeCoins': {
          'destination': _normalizeArgument(body['destination']),
          'sources': [
            for (final s in (body['sources'] as List)) _normalizeArgument(s)
          ],
        }
      };
    default:
      return {kind: body.toString()};
  }
}
