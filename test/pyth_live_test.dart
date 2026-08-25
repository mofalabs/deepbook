import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart';
import 'package:deepbook/deepbook.dart';

/// Live tests for the Pyth layer (M9): Hermes beta REST + testnet on-chain
/// Pyth/Wormhole state, plus a full simulated price-feed update.
///
/// Run with: flutter test test/pyth_live_test.dart
void main() {
  final client = SuiGrpcClient(network: SuiNetwork.testnet);
  final core = client.core as GrpcCoreClient;
  const address =
      '0x0000000000000000000000000000000000000000000000000000000000000001';

  final config = DeepBookConfig(network: 'testnet', address: address);
  final pythClient = SuiPythClient(
    core,
    pythStateId: config.pyth.pythStateId,
    wormholeStateId: config.pyth.wormholeStateId,
  );

  test('Hermes returns accumulator update data for testnet feeds', () async {
    final connection =
        SuiPriceServiceConnection(hermesEndpoint(config.network));
    final feed = config.getCoin('SUI').feed!;
    final updates = await connection.getPriceFeedsUpdateData([feed]);
    expect(updates, hasLength(1));
    expect(updates.first.length, greaterThan(100));
    // Accumulator magic "PNAU".
    expect(updates.first.sublist(0, 4), [0x50, 0x4e, 0x41, 0x55]);
  });

  test('package ids and price table resolve from on-chain state', () async {
    final pythPackage = await pythClient.getPythPackageId();
    final wormholePackage = await pythClient.getWormholePackageId();
    expect(pythPackage, startsWith('0x'));
    expect(wormholePackage, startsWith('0x'));
    expect(pythPackage.length, 66);

    final tableInfo = await pythClient.getPriceTableInfo();
    expect(tableInfo.id, startsWith('0x'));
    expect(tableInfo.fieldType, startsWith('0x'));

    final fee = await pythClient.getBaseUpdateFee();
    expect(fee, greaterThanOrEqualTo(BigInt.zero));
  });

  test('price feed object id matches the pinned constants', () async {
    final coin = config.getCoin('SUI');
    final objectId = await pythClient.getPriceFeedObjectId(coin.feed!);
    expect(objectId, coin.priceInfoObjectId);
  });

  test('simulated updatePriceFeeds executes successfully', () async {
    // Sender needs SUI for the update fee's coinWithBalance split, so use
    // the funded test account address.
    final funded = SuiAccount.fromPrivateKey(
            'suiprivkey1qrhwmd5a92dkdym3mp3ldk9w6pr94xrkku6yp5lm97kv4dnvp30njag85ke')
        .getAddress();
    final ctx = QueryContext(
        core: core,
        config: DeepBookConfig(network: 'testnet', address: funded));

    final connection =
        SuiPriceServiceConnection(hermesEndpoint(config.network));
    final feed = config.getCoin('SUI').feed!;
    final updates = await connection.getPriceFeedsUpdateData([feed]);

    final tx = Transaction();
    final priceInfoObjects =
        await pythClient.updatePriceFeeds(tx, updates, [feed]);
    expect(priceInfoObjects, hasLength(1));

    final results = await ctx.simulate(tx);
    expect(results, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
