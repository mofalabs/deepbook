import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart';
import 'package:deepbook/deepbook.dart';

/// Live tests for the Pyth layer: Hermes v2 REST + testnet on-chain
/// Pyth/Wormhole state (upgraded Core), plus a full simulated price-feed
/// update.
///
/// The Hermes serving the upgraded Core answers 401 unauthenticated, so the
/// Hermes-dependent tests need a token:
///   PYTH_ACCESS_TOKEN=... flutter test test/pyth_live_test.dart
/// They skip when it is absent; the on-chain-state tests always run.
void main() {
  final accessToken = Platform.environment['PYTH_ACCESS_TOKEN'];
  final noToken = accessToken == null || accessToken.isEmpty;
  const needsToken =
      'Needs PYTH_ACCESS_TOKEN: upgraded-Core Hermes answers 401 without it.';
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
    final connection = SuiPriceServiceConnection(PYTH_UPGRADED_HERMES,
        accessToken: accessToken);
    final feed = config.getFeedId('SUI');
    final updates = await connection.getPriceFeedsUpdateData([feed]);
    expect(updates, hasLength(1));
    expect(updates.first.length, greaterThan(100));
    // Accumulator magic "PNAU".
    expect(updates.first.sublist(0, 4), [0x50, 0x4e, 0x41, 0x55]);
  }, skip: noToken ? needsToken : false);

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

    final connection = SuiPriceServiceConnection(PYTH_UPGRADED_HERMES,
        accessToken: accessToken);
    final feed = config.getFeedId('SUI');
    final updates = await connection.getPriceFeedsUpdateData([feed]);

    final tx = Transaction();
    final priceInfoObjects =
        await pythClient.updatePriceFeeds(tx, updates, [feed]);
    expect(priceInfoObjects, hasLength(1));

    final results = await ctx.simulate(tx);
    expect(results, isNotEmpty);
  },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: noToken ? needsToken : false);
}
