@TestOn('vm') // reads fixture files from disk
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart' hide Coin;
import 'package:deepbook/deepbook.dart';

/// Builder-level cross-check against the OFFICIAL TypeScript SDK.
///
/// Fixtures in test/fixtures/byte_compare/ are the official
/// `@mysten/deepbook-v3` Transaction JSON for representative calls
/// (regenerate with tool/byte_compare/gen_fixtures.mjs). This test rebuilds
/// the identical transactions with the Dart SDK and requires the normalized
/// inputs (pure BCS bytes! / object ids) and command structure to match
/// exactly.
void main() {
  const address =
      '0x00000000000000000000000000000000000000000000000000000000000000aa';
  const manager =
      '0x00000000000000000000000000000000000000000000000000000000000000bb';

  const marginManager =
      '0x00000000000000000000000000000000000000000000000000000000000000dd';

  final config = DeepBookConfig(
    network: 'testnet',
    address: address,
    adminCap:
        '0x00000000000000000000000000000000000000000000000000000000000000cc',
    balanceManagers: {'M': const BalanceManager(address: manager)},
    marginManagers: {
      'MM': const MarginManager(address: marginManager, poolKey: 'SUI_DBUSDC'),
    },
  );

  final bm = BalanceManagerContract(config);
  final db = DeepBookContract(config);
  final admin = DeepBookAdminContract(config);
  final flash = FlashLoanContract(config);
  final gov = GovernanceContract(config);
  final margin = MarginManagerContract(config);
  final proxy = PoolProxyContract(config);

  final cases = <String, void Function(Transaction tx)>{
    'margin_manager_new': (tx) {
      margin.newMarginManager('SUI_DBUSDC')(tx);
    },
    'pool_proxy_orders': (tx) {
      proxy.placeLimitOrder(const PlaceMarginLimitOrderParams(
        poolKey: 'SUI_DBUSDC',
        marginManagerKey: 'MM',
        clientOrderId: '777',
        price: 1.5,
        quantity: 4,
        isBid: false,
      ))(tx);
      proxy.cancelAllOrders('MM')(tx);
    },
    'bm_withdraw': (tx) {
      bm.withdrawFromManager('M', 'SUI', 1.5, address)(tx);
    },
    'bm_caps': (tx) {
      bm.mintTradeCap('M')(tx);
      bm.generateProofAsOwner(manager)(tx);
    },
    'place_limit_order': (tx) {
      db.placeLimitOrder(const PlaceLimitOrderParams(
        poolKey: 'SUI_DBUSDC',
        balanceManagerKey: 'M',
        clientOrderId: '12345',
        price: 2.5,
        quantity: 7,
        isBid: true,
      ))(tx);
    },
    'cancel_orders': (tx) {
      db.cancelOrder(
          'SUI_DBUSDC', 'M', '170141183460469231731687303715884105728')(tx);
      db.cancelAllOrders('SUI_DBUSDC', 'M')(tx);
    },
    'governance': (tx) {
      gov.stake('SUI_DBUSDC', 'M', 100)(tx);
      gov.vote('SUI_DBUSDC', 'M', manager)(tx);
    },
    'flash_loan_roundtrip': (tx) {
      final result = flash.borrowBaseAsset('SUI_DBUSDC', 3)(tx);
      flash.returnBaseAsset('SUI_DBUSDC', 3, result[0], result[1])(tx);
    },
    'admin_create_pool': (tx) {
      admin.createPoolAdmin(const CreatePoolAdminParams(
        baseCoinKey: 'DEEP',
        quoteCoinKey: 'SUI',
        tickSize: 0.001,
        lotSize: 1,
        minSize: 10,
        whitelisted: true,
        stablePool: false,
      ))(tx);
    },
    'order_reads': (tx) {
      db.accountOpenOrders('SUI_DBUSDC', 'M')(tx);
      db.midPrice('SUI_DBUSDC')(tx);
      db.poolTradeParams('SUI_DBUSDC')(tx);
    },
  };

  // Fixtures are generated from the official TS SDK and are not shipped in
  // the published package; skip rather than fail when they are absent.
  if (!Directory('test/fixtures/byte_compare').existsSync()) {
    test('official SDK byte comparison', () {
      markTestSkipped('fixtures absent — regenerate with '
          'tool/byte_compare/gen_fixtures.mjs');
    });
    return;
  }

  for (final entry in cases.entries) {
    test('matches official SDK builder output: ${entry.key}', () {
      final fixtureFile = File('test/fixtures/byte_compare/${entry.key}.json');
      expect(fixtureFile.existsSync(), isTrue,
          reason: 'fixture missing — run tool/byte_compare/gen_fixtures.mjs');
      final official =
          jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;

      final tx = Transaction();
      tx.setSender(address);
      entry.value(tx);
      final ours = jsonDecode(tx.toJson()) as Map<String, dynamic>;

      expect(_normalize(ours), _normalize(official),
          reason: 'builder output diverges from official SDK');
    });
  }
}

/// Canonicalizes a Transaction JSON (either the official TS `toJSON()` shape
/// or the Dart builder snapshot) down to the semantically meaningful parts:
/// input kinds/payloads and command structure.
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
