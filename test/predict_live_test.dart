import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart';
import 'package:deepbook/predict.dart' as predict;

/// Read-only Predict queries against the PUBLIC testnet deployment (the
/// recorded `deepbook-predict-testnet` ids). Network required.
///
/// Run with: flutter test test/predict_live_test.dart
void main() {
  final grpc = SuiGrpcClient(network: SuiNetwork.testnet);
  const anyOwner =
      '0x00000000000000000000000000000000000000000000000000000000000000aa';

  final client = predict.PredictClient(
    network: 'testnet',
    client: grpc.core as GrpcCoreClient,
  );

  group('predict reads (testnet live)', () {
    test('pool stats are readable and sane', () async {
      final pool = await client.read.pool();
      expect(pool.plpTotalSupply, greaterThanOrEqualTo(BigInt.zero));
      expect(pool.idleUsdc, greaterThanOrEqualTo(0));
      expect(pool.supplyRequestsPending, greaterThanOrEqualTo(0));
      expect(pool.withdrawRequestsPending, greaterThanOrEqualTo(0));
    });

    test('markets enumerate with consistent state', () async {
      final markets = await client.read.markets();
      // The vault may legitimately have no live market between expiries; the
      // state checks only apply to what is there.
      for (final m in markets) {
        expect(m.id, startsWith('0x'));
        expect(m.expiryMs, greaterThan(BigInt.zero));
        expect(m.tickSize, greaterThan(0));
        expect(m.admissionTickSize, greaterThanOrEqualTo(m.tickSize));
      }
    });

    test('anonymous board price for a live market', () async {
      final markets = await client.read.markets();
      final live = markets.where((m) =>
          !m.mintPaused &&
          m.expiryMs >
              BigInt.from(DateTime.now().millisecondsSinceEpoch + 60000));
      if (live.isEmpty) {
        markTestSkipped('no live unexpired market on testnet right now');
        return;
      }
      final m = live.first;
      final strike = m.referencePrice;
      if (strike == null) {
        markTestSkipped('reference price not seeded yet for ${m.id}');
        return;
      }
      try {
        final price = await client.read.price(predict.MarketDescriptor.up(
          underlying: 'BTC',
          expiryMs: m.expiryMs,
          strike: 'reference',
          marketId: m.id,
        ));
        expect(price.up, inInclusiveRange(0, 1));
        expect(price.down, inInclusiveRange(0, 1));
        // Both sides are the chain's own numbers from one pricer; they need
        // not sum exactly to 1 but must be jointly coherent.
        expect(price.up + price.down, inInclusiveRange(0.98, 1.02));

        // The local board pricer agrees with the chain to the documented
        // ~1e-4.
        final board =
            await client.read.pricer(underlying: 'BTC', expiryMs: m.expiryMs);
        expect(board.up(strike), closeTo(price.up, 5e-4));
      } on predict.PredictMoveError catch (e) {
        // `load_live_pricer` aborts when a testnet oracle feed is stale or
        // the surface fails the pricing-safe envelope — exactly when the
        // chain itself cannot quote (the official SDK surfaces the same
        // typed error). Environmental, not a port defect.
        markTestSkipped('chain cannot quote right now: $e');
      }
    });

    test('positions of a never-onboarded owner resolve to empty', () async {
      final positions = await client.read.positions(anyOwner);
      expect(positions, isEmpty);
    });
  });
}
