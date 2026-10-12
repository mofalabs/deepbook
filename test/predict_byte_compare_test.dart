@TestOn('vm') // reads fixture files from disk
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart';
import 'package:deepbook/predict.dart' as predict;

/// Builder-level cross-check of the /predict subpath against the OFFICIAL
/// TypeScript SDK (`@mysten/deepbook-v3/predict`).
///
/// Fixtures in test/fixtures/byte_compare/ are the official Transaction JSON
/// for the same calls (regenerate with
/// tool/byte_compare/gen_fixtures_predict.mjs). This test rebuilds the
/// identical transactions with the Dart SDK and requires the normalized
/// inputs (pure BCS bytes / object ids / intents) and command structure to
/// match exactly. It also checks the execution-result decoders and the
/// off-chain wrapper-id derivation against official outputs.
void main() {
  const owner =
      '0x00000000000000000000000000000000000000000000000000000000000000aa';
  const market =
      '0x0000000000000000000000000000000000000000000000000000000000000011';
  const builderCodeId =
      '0x0000000000000000000000000000000000000000000000000000000000000033';

  final cfg = predict.getConfig('testnet');
  final gen = predict.toGeneratedConfig(cfg);
  final btc = cfg.underlyings['BTC']!;
  final feeds = predict.MarketFeeds(
    pythFeed: btc.pythFeed,
    blockScholesValueStore: btc.blockScholesValueStore,
    blockScholesSviStore: btc.blockScholesSviStore,
  );
  // The sync tx.* builders never touch the network; the client is only a
  // handle here (its transport dials lazily).
  final client = predict.PredictClient(
    network: 'testnet',
    client: GrpcCoreClient(network: SuiNetwork.testnet),
  );
  final wrapper = client.wrapperIdFor(owner);
  final orderId = BigInt.two.pow(200) + BigInt.from(7);

  // === Sync facade builders: each returns a finished Transaction. ===
  final syncCases = <String, Transaction Function()>{
    'predict_create_manager': () => client.tx.createManager(),
    'predict_deposit': () => client.tx.deposit(owner, '12.5'),
    'predict_deposit_create': () => client.tx.deposit(owner, 3, create: true),
    'predict_withdraw': () => client.tx.withdraw(owner, '1.75'),
    'predict_withdraw_coin': () =>
        client.tx.withdraw(owner, 2, toCoinObject: true),
    'predict_supply_plp': () => client.tx.supplyPlp(owner, 100),
    'predict_supply_plp_floor': () => client.tx.supplyPlp(owner, '250.25',
        predict.PlpSupplyOptions(minPlpOut: BigInt.from(123456789))),
    'predict_withdraw_plp': () =>
        client.tx.withdrawPlp(owner, BigInt.from(5000000)),
    'predict_withdraw_plp_floor': () => client.tx.withdrawPlp(
        owner,
        BigInt.from(5000000),
        const predict.PlpWithdrawOptions(minUsdcOut: '4.5')),
    'predict_cancel_supply': () =>
        client.tx.cancelSupplyPlp(owner, BigInt.from(7)),
    'predict_cancel_withdraw': () =>
        client.tx.cancelWithdrawPlp(owner, BigInt.zero),
    'predict_set_builder_code': () =>
        client.tx.setBuilderCode(owner, builderCodeId),
    'predict_unset_builder_code': () => client.tx.unsetBuilderCode(owner),
  };

  // === Trade compositions: the internal primitives the async facade
  // builders delegate to, with the market pre-resolved (the official fixture
  // replicates tx/trade.ts over the official public exports). ===
  final tradeCases = <String, void Function(Transaction tx)>{
    'predict_mint_quantity': (tx) {
      predict.mintExactQuantity(
        gen,
        expiryMarketId: market,
        wrapperId: wrapper,
        lowerTick: BigInt.from(123),
        higherTick: predict.POS_INF_TICK,
        quantityRaw: BigInt.from(5000000),
        maxCostRaw: BigInt.from(4000000),
        maxProbabilityRaw: BigInt.from(800000000),
        feeds: feeds,
      )(tx);
    },
    'predict_mint_quantity_defaults': (tx) {
      predict.mintExactQuantity(
        gen,
        expiryMarketId: market,
        wrapperId: wrapper,
        lowerTick: BigInt.zero,
        higherTick: BigInt.from(321),
        quantityRaw: BigInt.from(10000),
        feeds: feeds,
      )(tx);
    },
    'predict_mint_amount': (tx) {
      predict.mintExactAmount(
        gen,
        expiryMarketId: market,
        wrapperId: wrapper,
        lowerTick: BigInt.from(10),
        higherTick: BigInt.from(20),
        maxPremiumRaw: BigInt.from(1000000),
        minQuantityRaw: BigInt.from(10000),
        maxCostRaw: BigInt.from(2000000),
        feeds: feeds,
      )(tx);
    },
    'predict_mint_cost': (tx) {
      predict.mintExactCost(
        gen,
        expiryMarketId: market,
        wrapperId: wrapper,
        lowerTick: BigInt.from(10),
        higherTick: BigInt.from(20),
        maxCostRaw: BigInt.from(3000000),
        minQuantityRaw: BigInt.zero,
        feeds: feeds,
      )(tx);
    },
    'predict_redeem_live': (tx) {
      predict.redeemLive(
        gen,
        expiryMarketId: market,
        wrapperId: wrapper,
        orderId: orderId,
        closeQuantityRaw: BigInt.from(20000),
        feeds: feeds,
      )(tx);
    },
    'predict_redeem_settled': (tx) {
      predict.redeemSettled(
        gen,
        expiryMarketId: market,
        wrapperId: wrapper,
        orderId: orderId,
      )(tx);
    },
  };

  // Fixtures are generated from the official TS SDK and are not shipped in
  // the published package; skip rather than fail when they are absent.
  if (!Directory('test/fixtures/byte_compare').existsSync()) {
    test('official SDK byte comparison (predict)', () {
      markTestSkipped('fixtures absent — regenerate with '
          'tool/byte_compare/gen_fixtures_predict.mjs');
    });
    return;
  }

  Map<String, dynamic> readFixture(String name) {
    final file = File('test/fixtures/byte_compare/$name.json');
    expect(file.existsSync(), isTrue,
        reason:
            'fixture missing — run tool/byte_compare/gen_fixtures_predict.mjs');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  for (final entry in syncCases.entries) {
    test('matches official SDK builder output: ${entry.key}', () {
      final official = readFixture(entry.key);
      final tx = entry.value();
      tx.setSender(owner);
      final ours = jsonDecode(tx.toJson()) as Map<String, dynamic>;
      expect(_normalize(ours), _normalize(official),
          reason: 'builder output diverges from official SDK');
    });
  }

  for (final entry in tradeCases.entries) {
    test('matches official SDK builder output: ${entry.key}', () {
      final official = readFixture(entry.key);
      final tx = Transaction();
      tx.setSender(owner);
      entry.value(tx);
      final ours = jsonDecode(tx.toJson()) as Map<String, dynamic>;
      expect(_normalize(ours), _normalize(official),
          reason: 'builder output diverges from official SDK');
    });
  }

  test('wrapper-id derivation matches the official SDK on both networks', () {
    // This fixture is a top-level list keyed by network.
    final networks = (jsonDecode(
            File('test/fixtures/byte_compare/predict_derive.json')
                .readAsStringSync()) as List)
        .cast<Map>();
    expect(networks, hasLength(2));
    for (final net in networks) {
      final c = predict.getConfig(net['network'] as String);
      for (final row in (net['rows'] as List).cast<Map>()) {
        expect(predict.deriveAccountWrapperId(c, row['owner'] as String),
            row['wrapperId'],
            reason: 'wrapper id for ${row['owner']} on ${net['network']}');
      }
    }
  });

  group('execution-result decoders', () {
    late predict.DecodableTransactionResult result;
    late Map<String, dynamic> expected;

    setUpAll(() {
      final fixture = readFixture('predict_decode_events');
      result = predict.DecodableTransactionResult(events: [
        for (final e in (fixture['events'] as List).cast<Map>())
          predict.DecodableEvent(
              eventType: e['eventType'] as String, bcs: e['bcs'] as String)
      ]);
      expected = fixture['decoded'] as Map<String, dynamic>;
    });

    BigInt big(Object v) => BigInt.parse(v.toString());

    test('mint receipt', () {
      final r = client.decode.mint(result);
      final x = expected['mint'] as Map;
      expect(r.marketId, x['marketId']);
      expect(r.accountId, x['accountId']);
      expect(r.owner, x['owner']);
      expect(r.orderId, big(x['orderId'] as Object));
      expect(r.positionRootId, big(x['positionRootId'] as Object));
      expect(r.lowerTick, big(x['lowerTick'] as Object));
      expect(r.higherTick, big(x['higherTick'] as Object));
      expect(r.builderCodeId, x['builderCodeId']);
      final xr = x['raw'] as Map;
      expect(r.raw.quantity, big(xr['quantity'] as Object));
      expect(r.raw.premium, big(xr['premium'] as Object));
      expect(r.raw.tradingFee, big(xr['tradingFee'] as Object));
      expect(
          r.raw.feeIncentiveSubsidy, big(xr['feeIncentiveSubsidy'] as Object));
      expect(r.raw.builderFee, big(xr['builderFee'] as Object));
      expect(r.raw.penaltyFee, big(xr['penaltyFee'] as Object));
      expect(r.raw.referralFee, big(xr['referralFee'] as Object));
      expect(r.raw.inventoryImpactCharge,
          big(xr['inventoryImpactCharge'] as Object));
      expect(r.raw.entryProbability, big(xr['entryProbability'] as Object));
      expect(r.quantity, closeTo((x['quantity'] as num).toDouble(), 1e-12));
      expect(r.premium, closeTo((x['premium'] as num).toDouble(), 1e-12));
      expect(r.entryProbability,
          closeTo((x['entryProbability'] as num).toDouble(), 1e-12));
      final xf = x['fees'] as Map;
      expect(r.fees.trading, closeTo((xf['trading'] as num).toDouble(), 1e-12));
      expect(
          r.fees.referral, closeTo((xf['referral'] as num).toDouble(), 1e-12));
    });

    test('redeem receipt (net-proceeds accounting)', () {
      final r = client.decode.redeem(result);
      final x = expected['redeem'] as Map;
      final xr = x['raw'] as Map;
      expect(r.raw.proceeds, big(xr['proceeds'] as Object));
      expect(r.raw.gross, big(xr['gross'] as Object));
      expect(r.raw.quantityClosed, big(xr['quantityClosed'] as Object));
      expect(r.raw.remaining, big(xr['remaining'] as Object));
      expect(r.replacementOrderId, big(x['replacementOrderId'] as Object));
      expect(r.builderCodeId, isNull);
      expect(r.proceeds, closeTo((x['proceeds'] as num).toDouble(), 1e-12));
    });

    test('claim / createManager / balance-change receipts', () {
      final claim = client.decode.claim(result);
      final xc = expected['claim'] as Map;
      expect(claim.rawPayout, big((xc['raw'] as Map)['payout'] as Object));

      final created = client.decode.createManager(result);
      final xm = expected['createManager'] as Map;
      expect(created.wrapperId, xm['wrapperId']);
      expect(created.selfOwned, xm['selfOwned']);

      final dep = client.decode.deposit(result);
      final xd = expected['deposit'] as Map;
      expect(dep.rawAmount, big((xd['raw'] as Map)['amount'] as Object));
      expect(dep.coinType, xd['coinType']);
      expect(client.decode.withdraw(result).rawNewBalance,
          big((expected['withdraw'] as Map)['raw']['newBalance'] as Object));
    });

    test('plp request/cancel + builder-code receipts', () {
      final req = client.decode.plpRequest(result);
      final xq = expected['plpRequest'] as Map;
      expect(req.kind, xq['kind']);
      expect(req.index, big(xq['index'] as Object));
      expect(req.rawAmount, big((xq['raw'] as Map)['amount'] as Object));

      final cancel = client.decode.plpCancel(result);
      final xl = expected['plpCancel'] as Map;
      expect(cancel.isSupply, xl['isSupply']);
      expect(cancel.index, big(xl['index'] as Object));

      final code = client.decode.builderCode(result);
      expect(code.builderCodeId,
          (expected['builderCode'] as Map)['builderCodeId']);
    });

    test('singular decoders throw on zero matches', () {
      final empty = predict.DecodableTransactionResult(events: const []);
      expect(() => client.decode.mint(empty),
          throwsA(isA<predict.PredictInputError>()));
    });
  });
}

/// Canonicalizes a Transaction JSON (either the official TS `toJSON()` shape
/// or the Dart builder snapshot) down to the semantically meaningful parts:
/// input kinds/payloads and command structure. Mirrors the helper in
/// byte_compare_test.dart, plus the `$Intent` arm (CoinWithBalance stays
/// unresolved on both sides).
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
    case r'$Intent':
      return {
        r'$Intent': {
          'name': body['name'],
          'data': jsonEncode(body['data']),
        }
      };
    default:
      return {kind: body.toString()};
  }
}
