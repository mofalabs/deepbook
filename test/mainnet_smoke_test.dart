import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart' hide Coin;
import 'package:deepbook/deepbook.dart';

/// Read-only smoke test for the pinned MAINNET constants.
///
/// The package ships a snapshot of DeepBook's mainnet addresses (packages,
/// pools, coins, margin pools). If Mysten redeploys, those constants go
/// stale and every mainnet user gets dead addresses — this suite catches
/// that by checking the objects actually exist and are the expected types.
///
/// Run with: flutter test test/mainnet_smoke_test.dart
void main() {
  final grpc = SuiGrpcClient(network: SuiNetwork.mainnet);
  final core = grpc.core as GrpcCoreClient;
  const address =
      '0x0000000000000000000000000000000000000000000000000000000000000001';
  final client =
      DeepBookClient(client: core, network: 'mainnet', address: address);

  test('package and shared object ids exist on mainnet', () async {
    for (final entry in {
      'registry': mainnetPackageIds.registryId,
      'deepTreasury': mainnetPackageIds.deepTreasuryId,
      'marginRegistry': mainnetPackageIds.marginRegistryId,
    }.entries) {
      final object = await core
          .getObject(entry.value, readMask: const ['object_id', 'object_type']);
      expect(object.objectId, entry.value, reason: '${entry.key} missing');
      expect(object.objectType, isNotEmpty);
    }

    // Package ids must resolve as Move packages.
    for (final pkg in [
      mainnetPackageIds.deepbookPackageId,
      mainnetPackageIds.marginPackageId,
    ]) {
      final package = await core.getPackage(pkg);
      expect(package.modules, isNotEmpty, reason: '$pkg has no modules');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('every pinned mainnet pool is live and registered', () async {
    for (final entry in mainnetPools.entries) {
      final object = await entry.value.address.let((id) =>
          core.getObject(id, readMask: const ['object_id', 'object_type']));
      expect(object.objectType, contains('::pool::Pool<'),
          reason: '${entry.key} is not a Pool');

      // The registry agrees this pool exists for its coin pair.
      final base = mainnetCoins[entry.value.baseCoin];
      final quote = mainnetCoins[entry.value.quoteCoin];
      expect(base, isNotNull, reason: '${entry.key} base coin unknown');
      expect(quote, isNotNull, reason: '${entry.key} quote coin unknown');
      final resolved = await client.getPoolIdByAssets(base!.type, quote!.type);
      expect(resolved, entry.value.address,
          reason: '${entry.key} address drifted from the registry');
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('every pinned mainnet coin type resolves on chain', () async {
    for (final entry in mainnetCoins.entries) {
      final metadata = await core.getCoinInfo(entry.value.type);
      expect(metadata.metadata.decimals,
          entry.value.scalar.toInt().toString().length - 1,
          reason: '${entry.key} scalar disagrees with on-chain decimals');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('pinned mainnet margin pools exist', () async {
    for (final entry in mainnetMarginPools.entries) {
      final object = await core.getObject(entry.value.address,
          readMask: const ['object_id', 'object_type']);
      expect(object.objectType, contains('::margin_pool::MarginPool<'),
          reason: '${entry.key} is not a MarginPool');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('pinned mainnet Pyth state objects exist', () async {
    for (final id in [
      mainnetPythConfigs.pythStateId,
      mainnetPythConfigs.wormholeStateId,
    ]) {
      final object = await core
          .getObject(id, readMask: const ['object_id', 'object_type']);
      expect(object.objectType, contains('::state::State'));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
