import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart' hide Coin;
import 'package:deepbook/deepbook.dart';

/// Read-only query tests through the DeepBookClient facade against the
/// PUBLIC testnet deployment (official pools/margin pools from constants).
///
/// Run with: flutter test test/queries_live_test.dart
void main() {
  final grpc = SuiGrpcClient(network: SuiNetwork.testnet);
  const address =
      '0x00000000000000000000000000000000000000000000000000000000000000aa';

  final client = DeepBookClient(
    client: grpc.core as GrpcCoreClient,
    network: 'testnet',
    address: address,
  );

  group('spot queries (testnet live)', () {
    test('poolTradeParams / poolBookParams for SUI_DBUSDC', () async {
      final trade = await client.poolTradeParams('SUI_DBUSDC');
      expect(trade.takerFee, greaterThanOrEqualTo(0));
      expect(trade.makerFee, greaterThanOrEqualTo(0));

      final book = await client.poolBookParams('SUI_DBUSDC');
      expect(book.tickSize, greaterThan(0));
      expect(book.lotSize, greaterThan(0));
      expect(book.minSize, greaterThanOrEqualTo(book.lotSize));
    });

    test('midPrice and level2 book for SUI_DBUSDC', () async {
      final mid = await client.midPrice('SUI_DBUSDC');
      expect(mid, greaterThan(0));

      final ticks = await client.getLevel2TicksFromMid('SUI_DBUSDC', 5);
      expect(ticks.bidPrices.length, ticks.bidQuantities.length);
      expect(ticks.askPrices.length, ticks.askQuantities.length);
    });

    test('pool registration and pool id round-trip', () async {
      final registered = await client.registeredPool('SUI_DBUSDC');
      expect(registered, isTrue);

      final poolId = await client.getPoolIdByAssets(
          testnetCoins['SUI']!.type, testnetCoins['DBUSDC']!.type);
      expect(poolId, testnetPools['SUI_DBUSDC']!.address);
    });

    test('quantity out calculations on SUI_DBUSDC', () async {
      final out = await client.getQuoteQuantityOut('SUI_DBUSDC', 10);
      expect(out.baseQuantity, 10);
      expect(out.quoteOut, greaterThanOrEqualTo(0));
      expect(out.deepRequired, greaterThanOrEqualTo(0));
    });

    test('whitelisted flag for DEEP_SUI', () async {
      expect(await client.whitelisted('DEEP_SUI'), isA<bool>());
    });
  });

  group('margin queries (testnet live)', () {
    test('margin pool state for SUI margin pool', () async {
      // Token amounts come back as formatted decimal strings (official
      // formatTokenAmount behaviour).
      final supply = await client.getMarginPoolTotalSupply('SUI');
      expect(double.parse(supply), greaterThanOrEqualTo(0));
      final cap = await client.getMarginPoolSupplyCap('SUI');
      expect(double.parse(cap), greaterThan(0));
      final rate = await client.getMarginPoolInterestRate('SUI');
      expect(rate, greaterThanOrEqualTo(0));
    });

    test('margin registry flags resolve', () async {
      try {
        final enabled = await client.isPoolEnabledForMargin('SUI_DBUSDC');
        expect(enabled, isA<bool>());
        final maintainers = await client.getAllowedMaintainers();
        expect(maintainers, isA<List<String>>());
      } on DeepBookError catch (e) {
        // The testnet margin registry version-gates `load_inner`; when the
        // deployed package version is disabled on-chain the official TS SDK
        // aborts identically — environment state, not an SDK defect.
        if (e.message.contains('load_inner')) {
          markTestSkipped('testnet margin registry version disabled: $e');
          return;
        }
        rethrow;
      }
    });
  });
}
