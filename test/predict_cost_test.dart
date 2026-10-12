@TestOn('vm') // reads fixture files from disk
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:deepbook/predict.dart' as predict;

/// Exact-value cross-check of the client-side cost engine and float pricer
/// against the OFFICIAL TypeScript SDK's `cost.*` / `pricing.*` outputs.
///
/// The cost engine is an exact integer port — every raw output must be EQUAL,
/// not close; the float pricer tolerates cross-runtime libm ulps. Fixtures
/// regenerate with tool/byte_compare/gen_fixtures_predict.mjs.
void main() {
  if (!Directory('test/fixtures/byte_compare').existsSync()) {
    test('official SDK cost/pricing parity (predict)', () {
      markTestSkipped('fixtures absent — regenerate with '
          'tool/byte_compare/gen_fixtures_predict.mjs');
    });
    return;
  }

  dynamic readFixture(String name) => jsonDecode(
      File('test/fixtures/byte_compare/$name.json').readAsStringSync());

  // JSON round-trip of the fixture INPUTS: a JSON string was a TS bigint
  // (raw), a JSON number a human amount — exactly the num-vs-BigInt split the
  // Dart API takes.
  Object amount(Object v) => v is String ? BigInt.parse(v) : v as num;
  BigInt big(Object v) => BigInt.parse(v.toString());
  BigInt? optBig(Object? v) => v == null ? null : big(v);

  predict.FeePolicy policy(Map f) => predict.FeePolicy(
        baseFee: big(f['baseFee'] as Object),
        minFee: big(f['minFee'] as Object),
        expiryFeeWindowMs: big(f['expiryFeeWindowMs'] as Object),
        expiryFeeMaxMultiplier: big(f['expiryFeeMaxMultiplier'] as Object),
        minEntryProbability: big(f['minEntryProbability'] as Object),
        maxEntryProbability: big(f['maxEntryProbability'] as Object),
        inventoryImpactMaxRate: big(f['inventoryImpactMaxRate'] as Object),
        inventoryImpactScale: big(f['inventoryImpactScale'] as Object),
        backingBufferLambda: big(f['backingBufferLambda'] as Object),
      );

  predict.Boundaries boundaries(Map p) => predict.Boundaries(
        lowerUp: optBig(p['lowerUp']),
        higherUp: optBig(p['higherUp']),
      );

  predict.MintBookTerms book(Map b) => predict.MintBookTerms(
        maxPayout: big(b['maxPayout'] as Object),
        totalPayout: big(b['totalPayout'] as Object),
        rangeMaxPayout: big(b['rangeMaxPayout'] as Object),
      );

  predict.CloseBookTerms closeBook(Map b) => predict.CloseBookTerms(
        maxPayout: big(b['maxPayout'] as Object),
        totalPayout: big(b['totalPayout'] as Object),
        rangeMaxPayout: big(b['rangeMaxPayout'] as Object),
        complementMaxPayout: big(b['complementMaxPayout'] as Object),
      );

  // The official error messages embed the Move abort-constant name — the two
  // ports must reject the same case with the same named abort.
  String abortNameOf(String message) {
    final m = RegExp(r'\(E[A-Za-z]+\)').firstMatch(message);
    return m?.group(0) ?? message;
  }

  group('cost engine parity', () {
    final fixture = readFixture('predict_cost_parity') as Map;

    void expectMintEqual(predict.MintCost ours, Map ok) {
      final raw = ok['raw'] as Map;
      expect(ours.raw.quantity, big(raw['quantity'] as Object));
      expect(ours.raw.entryProbability, big(raw['entryProbability'] as Object));
      expect(ours.raw.premium, big(raw['premium'] as Object));
      expect(ours.raw.tradingFee, big(raw['tradingFee'] as Object));
      expect(ours.raw.subsidy, big(raw['subsidy'] as Object));
      expect(ours.raw.builderFee, big(raw['builderFee'] as Object));
      expect(ours.raw.penaltyFee, big(raw['penaltyFee'] as Object));
      expect(ours.raw.impactCharge, big(raw['impactCharge'] as Object));
      expect(ours.raw.cost, big(raw['cost'] as Object));
      expect(ours.cost, closeTo((ok['cost'] as num).toDouble(), 1e-9));
      expect(ours.costPerContract,
          closeTo((ok['costPerContract'] as num).toDouble(), 1e-12));
      expect(ours.payoutMultiple,
          closeTo((ok['payoutMultiple'] as num).toDouble(), 1e-12));
      expect(ours.exactProbabilities, ok['exactProbabilities']);
    }

    for (final entry in (fixture['mint'] as Map).entries) {
      test('mintCost: ${entry.key}', () {
        final inputs = entry.value['inputs'] as Map;
        final result = entry.value['result'] as Map;
        predict.MintCost run() => predict.mintCost(predict.MintCostInputs(
              fees: policy(inputs['fees'] as Map),
              expiryMs: big(inputs['expiryMs'] as Object),
              nowMs: big(inputs['nowMs'] as Object),
              probabilities: boundaries(inputs['probabilities'] as Map),
              quantity: amount(inputs['quantity'] as Object),
              builderCode: inputs['builderCode'] as bool? ?? false,
              feeIncentiveBalance: inputs['feeIncentiveBalance'] == null
                  ? null
                  : amount(inputs['feeIncentiveBalance'] as Object),
              penaltyRate: optBig(inputs['penaltyRate']),
              book: inputs['book'] == null ? null : book(inputs['book'] as Map),
            ));
        if (result.containsKey('error')) {
          final official = result['error'] as Map;
          expect(
              run,
              throwsA(isA<predict.PredictInputError>().having(
                  (e) => abortNameOf(e.message),
                  'abort name',
                  abortNameOf(official['message'] as String))));
        } else {
          expectMintEqual(run(), result['ok'] as Map);
        }
      });
    }

    for (final entry in (fixture['budget'] as Map).entries) {
      test('mintCostForBudget: ${entry.key}', () {
        final inputs = entry.value['inputs'] as Map;
        final result = entry.value['result'] as Map;
        predict.MintBudgetCost run() =>
            predict.mintCostForBudget(predict.MintBudgetInputs(
              fees: policy(inputs['fees'] as Map),
              expiryMs: big(inputs['expiryMs'] as Object),
              nowMs: big(inputs['nowMs'] as Object),
              probabilities: boundaries(inputs['probabilities'] as Map),
              budget: amount(inputs['budget'] as Object),
              minQuantity: inputs['minQuantity'] == null
                  ? null
                  : amount(inputs['minQuantity'] as Object),
              accountBalance: inputs['accountBalance'] == null
                  ? null
                  : amount(inputs['accountBalance'] as Object),
              builderCode: inputs['builderCode'] as bool? ?? false,
              penaltyRate: optBig(inputs['penaltyRate']),
              book: inputs['book'] == null ? null : book(inputs['book'] as Map),
            ));
        if (result.containsKey('error')) {
          final official = result['error'] as Map;
          expect(
              run,
              throwsA(isA<predict.PredictInputError>().having(
                  (e) => abortNameOf(e.message),
                  'abort name',
                  abortNameOf(official['message'] as String))));
        } else {
          final ok = result['ok'] as Map;
          final ours = run();
          expectMintEqual(ours, ok);
          final raw = ok['raw'] as Map;
          expect(ours.rawBudget, big(raw['budget'] as Object));
          expect(
              ours.rawEffectiveBudget, big(raw['effectiveBudget'] as Object));
          expect(ours.rawUnspentBudget, big(raw['unspentBudget'] as Object));
        }
      });
    }

    for (final entry in (fixture['redeem'] as Map).entries) {
      test('redeemLiveProceeds: ${entry.key}', () {
        final inputs = entry.value['inputs'] as Map;
        final result = entry.value['result'] as Map;
        predict.RedeemLiveProceeds run() =>
            predict.redeemLiveProceeds(predict.RedeemLiveInputs(
              fees: policy(inputs['fees'] as Map),
              expiryMs: big(inputs['expiryMs'] as Object),
              nowMs: big(inputs['nowMs'] as Object),
              probabilities: boundaries(inputs['probabilities'] as Map),
              closeQuantity: amount(inputs['closeQuantity'] as Object),
              positionQuantity: inputs['positionQuantity'] == null
                  ? null
                  : amount(inputs['positionQuantity'] as Object),
              builderCode: inputs['builderCode'] as bool? ?? false,
              penaltyRate: optBig(inputs['penaltyRate']),
              book: inputs['book'] == null
                  ? null
                  : closeBook(inputs['book'] as Map),
            ));
        if (result.containsKey('error')) {
          expect(run, throwsA(isA<predict.PredictInputError>()));
        } else {
          final ok = result['ok'] as Map;
          final raw = ok['raw'] as Map;
          final ours = run();
          expect(ours.raw.proceeds, big(raw['proceeds'] as Object));
          expect(ours.raw.gross, big(raw['gross'] as Object));
          expect(ours.raw.tradingFee, big(raw['tradingFee'] as Object));
          expect(ours.raw.builderFee, big(raw['builderFee'] as Object));
          expect(ours.raw.penaltyFee, big(raw['penaltyFee'] as Object));
          expect(ours.raw.impactRebate, big(raw['impactRebate'] as Object));
          expect(ours.raw.quantityClosed, big(raw['quantityClosed'] as Object));
          expect(ours.raw.remainingQuantity, optBig(raw['remainingQuantity']));
          expect(ours.raw.probability, big(raw['probability'] as Object));
          expect(ours.exactProbabilities, ok['exactProbabilities']);
        }
      });
    }

    test('fee components match exactly', () {
      final c = fixture['components'] as Map;
      for (final row in (c['bernoulli'] as List).cast<Map>()) {
        expect(
            predict.bernoulliFeeRate(
                BigInt.from(100000000), big(row['p'] as Object)),
            big(row['rate'] as Object));
      }
      for (final row in (c['sqrtDown'] as List).cast<Map>()) {
        expect(
            predict.sqrtDown(big(row['x'] as Object)), big(row['v'] as Object));
      }
      final p2 = predict.FeePolicy(
        baseFee: predict.SHIPPED_FEE_POLICY.baseFee,
        minFee: predict.SHIPPED_FEE_POLICY.minFee,
        expiryFeeWindowMs: predict.SHIPPED_FEE_POLICY.expiryFeeWindowMs,
        expiryFeeMaxMultiplier: BigInt.from(3000000000),
        minEntryProbability: predict.SHIPPED_FEE_POLICY.minEntryProbability,
        maxEntryProbability: predict.SHIPPED_FEE_POLICY.maxEntryProbability,
        inventoryImpactMaxRate:
            predict.SHIPPED_FEE_POLICY.inventoryImpactMaxRate,
        inventoryImpactScale: predict.SHIPPED_FEE_POLICY.inventoryImpactScale,
        backingBufferLambda: predict.SHIPPED_FEE_POLICY.backingBufferLambda,
      );
      for (final row in (c['expiryMultiplier'] as List).cast<Map>()) {
        expect(predict.expiryFeeMultiplier(p2, big(row['t'] as Object)),
            big(row['v'] as Object));
      }
      expect(
          predict.tradingFee(
              predict.SHIPPED_FEE_POLICY,
              predict.Boundaries(
                  lowerUp: BigInt.from(700000000),
                  higherUp: BigInt.from(300000000)),
              BigInt.from(100000000),
              BigInt.from(100000000)),
          big(c['tradingFeeTwoLegs'] as Object));
      for (final row in (c['congestion'] as List).cast<Map>()) {
        expect(
            predict.congestionPenaltyRate(
              predict.CongestionPolicy(
                  enabled: true,
                  penaltyRate: BigInt.from(30000000),
                  zScoreThreshold: BigInt.from(3000000000)),
              predict.CongestionState(
                  mean: BigInt.parse('1000000000000'),
                  variance: BigInt.parse('4000000000000')),
              big(row['gas'] as Object),
            ),
            big(row['rate'] as Object));
      }
      final p1 = predict.FeePolicy(
        baseFee: predict.SHIPPED_FEE_POLICY.baseFee,
        minFee: predict.SHIPPED_FEE_POLICY.minFee,
        expiryFeeWindowMs: predict.SHIPPED_FEE_POLICY.expiryFeeWindowMs,
        expiryFeeMaxMultiplier:
            predict.SHIPPED_FEE_POLICY.expiryFeeMaxMultiplier,
        minEntryProbability: predict.SHIPPED_FEE_POLICY.minEntryProbability,
        maxEntryProbability: predict.SHIPPED_FEE_POLICY.maxEntryProbability,
        inventoryImpactMaxRate: BigInt.from(50000000),
        inventoryImpactScale: BigInt.parse('10000000000'),
        backingBufferLambda: predict.SHIPPED_FEE_POLICY.backingBufferLambda,
      );
      for (final row in (c['impactPotential'] as List).cast<Map>()) {
        expect(predict.inventoryImpactPotential(p1, big(row['l'] as Object)),
            big(row['v'] as Object));
      }
      final mintBook = predict.MintBookTerms(
        maxPayout: BigInt.parse('400000000000'),
        totalPayout: BigInt.parse('900000000000'),
        rangeMaxPayout: BigInt.parse('100000000000'),
      );
      expect(
          predict.mintInventoryImpact(p1, mintBook, BigInt.parse('2000000000')),
          big(c['mintImpact'] as Object));
      expect(
          predict.closeInventoryImpact(
              p1,
              predict.CloseBookTerms(
                maxPayout: BigInt.parse('400000000000'),
                totalPayout: BigInt.parse('900000000000'),
                rangeMaxPayout: BigInt.parse('100000000000'),
                complementMaxPayout: BigInt.parse('400000000000'),
              ),
              BigInt.parse('2000000000')),
          big(c['closeImpact'] as Object));
      for (final row in (c['rangeProbability'] as List).cast<Map>()) {
        expect(predict.rangeProbabilityRaw(boundaries(row['b'] as Map)),
            big(row['v'] as Object));
      }
    });
  });

  group('float pricer parity', () {
    final fixture = readFixture('predict_pricing_parity') as Map;

    predict.PricerInputs snap(Map s) {
      final svi = s['svi'] as Map;
      return predict.PricerInputs(
        forward: (s['forward'] as num).toDouble(),
        svi: predict.Svi(
          a: (svi['a'] as num).toDouble(),
          b: (svi['b'] as num).toDouble(),
          rho: (svi['rho'] as num).toDouble(),
          m: (svi['m'] as num).toDouble(),
          sigma: (svi['sigma'] as num).toDouble(),
        ),
      );
    }

    test('up/down/range probabilities', () {
      for (final row in (fixture['snapshots'] as List).cast<Map>()) {
        final inputs = snap(row['snap'] as Map);
        final strikes = [
          inputs.forward * 0.9,
          inputs.forward,
          inputs.forward * 1.001,
          inputs.forward * 1.5,
          0.5,
          0.0,
        ];
        final ups = (row['up'] as List).cast<num>();
        final downs = (row['down'] as List).cast<num>();
        for (var i = 0; i < strikes.length; i++) {
          expect(predict.upProbability(inputs, strikes[i]),
              closeTo(ups[i].toDouble(), 1e-12),
              reason: 'up(${strikes[i]})');
          expect(predict.downProbability(inputs, strikes[i]),
              closeTo(downs[i].toDouble(), 1e-12));
        }
        final ranges = (row['range'] as List).cast<num>();
        expect(
            predict.rangeProbability(
                inputs, inputs.forward * 0.95, inputs.forward * 1.05),
            closeTo(ranges[0].toDouble(), 1e-12));
        expect(predict.rangeProbability(inputs, 0, inputs.forward),
            closeTo(ranges[1].toDouble(), 1e-12));
        expect(
            predict.rangeProbability(inputs, inputs.forward, double.infinity),
            closeTo(ranges[2].toDouble(), 1e-12));
        final strikeAts = row['strikeAt'] as List;
        final ps = [0.25, 0.5, 0.75, 0.999];
        for (var i = 0; i < ps.length; i++) {
          final official = strikeAts[i] as num?;
          final ours = predict.strikeAtProbability(inputs, ps[i]);
          if (official == null) {
            expect(ours, isNull);
          } else {
            // Bisection over floats: tolerate relative libm drift.
            expect(ours, isNotNull);
            expect((ours! - official.toDouble()).abs() / official.toDouble(),
                lessThan(1e-6),
                reason: 'strikeAt(${ps[i]})');
          }
        }
      }
    });

    test('rollDown and forward resolution', () {
      final rolled = fixture['rollDown'] as Map;
      final base = snap((fixture['snapshots'] as List)[0]['snap'] as Map);
      final ours = predict.rollDown(base.svi, 3600000, 86400000);
      expect(ours.a, closeTo((rolled['a'] as num).toDouble(), 1e-15));
      expect(ours.b, closeTo((rolled['b'] as num).toDouble(), 1e-15));
      expect(ours.rho, (rolled['rho'] as num).toDouble());
      final forwards = (fixture['forward'] as List).cast<num>();
      expect(predict.forward(65000, 64900, 65200),
          closeTo(forwards[0].toDouble(), 1e-9));
      expect(predict.forward(0, 64900, 65200),
          closeTo(forwards[1].toDouble(), 1e-9));
    });
  });

  group('order-id codec parity', () {
    final fixture = readFixture('predict_order_id') as Map;

    test('decodeOrderRange + orderStrikes', () {
      for (final row in (fixture['decode'] as List).cast<Map>()) {
        final range = predict.decodeOrderRange(big(row['id'] as Object));
        final x = row['range'] as Map;
        expect(range.lowerTick, big(x['lowerTick'] as Object));
        expect(range.higherTick, big(x['higherTick'] as Object));
        expect(range.quantity, big(x['quantity'] as Object));
        final strikes = predict.orderStrikes(range, BigInt.from(10000000));
        final xs = row['strikes'] as Map;
        void check(double? ours, Object? official) {
          if (official == null) {
            expect(ours, isNull);
          } else {
            expect(ours, closeTo((official as num).toDouble(), 1e-12));
          }
        }

        check(strikes.lower, xs['lower']);
        check(strikes.upper, xs['upper']);
      }
    });

    test('binaryRangeTicks', () {
      for (final row in (fixture['binaryTicks'] as List).cast<Map>()) {
        final c = row['c'] as Map;
        final ticks = predict.binaryRangeTicks(big(c['strikeRaw'] as Object),
            c['side'] as String, big(c['tickSize'] as Object));
        expect(
            ticks.lowerTick, big((row['ticks'] as Map)['lowerTick'] as Object));
        expect(ticks.higherTick,
            big((row['ticks'] as Map)['higherTick'] as Object));
      }
    });
  });

  group('input validation (Dart-side unit checks)', () {
    test('toRaw-backed conversions are exact string math', () {
      expect(predict.usdcToRaw('12.5'), BigInt.from(12500000));
      expect(predict.usdcToRaw(0.000001), BigInt.one);
      expect(predict.usdcToRaw(1e-6), BigInt.one); // exponential expansion
      expect(() => predict.usdcToRaw('1.0000001'),
          throwsA(isA<predict.PredictInputError>())); // excess precision
      expect(() => predict.usdcToRaw('-1'),
          throwsA(isA<predict.PredictInputError>()));
      expect(predict.priceToRaw(0.01), BigInt.from(10000000));
      expect(predict.probabilityToRaw(0.65), BigInt.from(650000000));
      expect(() => predict.probabilityToRaw(1.5),
          throwsA(isA<predict.PredictInputError>()));
    });

    test('binaryRangeTicks rejects a side that is neither up nor down', () {
      expect(
          () => predict.binaryRangeTicks(
              BigInt.from(1230000000), 'range', BigInt.from(10000000)),
          throwsA(isA<predict.PredictInputError>()));
    });

    test('boundary source with inverted strikes is rejected', () {
      final inputs = predict.MintCostInputs(
        fees: predict.SHIPPED_FEE_POLICY,
        expiryMs: BigInt.parse('1800000000000'),
        nowMs: BigInt.parse('1799000000000'),
        probabilities: predict.PricerBoundaries(
          pricer: const predict.PricerInputs(
              forward: 100,
              svi: predict.Svi(a: 0.001, b: 0.01, rho: 0, m: 0, sigma: 0.1)),
          lower: 120,
          upper: 110,
        ),
        quantity: 100,
      );
      expect(() => predict.mintCost(inputs),
          throwsA(isA<predict.PredictInputError>()));
    });

    test('book required when inventory impact is enabled', () {
      final p1 = predict.FeePolicy(
        baseFee: BigInt.from(100000000),
        minFee: BigInt.from(22000000),
        expiryFeeWindowMs: BigInt.from(86400000),
        expiryFeeMaxMultiplier: BigInt.from(1000000000),
        minEntryProbability: BigInt.from(10000000),
        maxEntryProbability: BigInt.from(990000000),
        inventoryImpactMaxRate: BigInt.from(50000000),
        inventoryImpactScale: BigInt.from(1000000000),
        backingBufferLambda: BigInt.from(310000000),
      );
      expect(
          () => predict.mintCost(predict.MintCostInputs(
                fees: p1,
                expiryMs: BigInt.parse('1800000000000'),
                nowMs: BigInt.parse('1799000000000'),
                probabilities: predict.Boundaries(
                    lowerUp: BigInt.from(500000000), higherUp: null),
                quantity: 100,
              )),
          throwsA(isA<predict.PredictInputError>()));
    });
  });
}
