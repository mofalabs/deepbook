import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart' hide Coin;
import 'package:deepbook/deepbook.dart';
import 'package:deepbook/src/contracts/deepbook/pool.dart' as pool_calls;

/// AdminCap-gated flows, executed for real against a localnet where we hold
/// the DeepbookAdminCap (deployed by tool/localnet/setup.sh).
///
/// Skips itself when tool/localnet/localnet_ids.json is missing or the
/// localnet is unreachable.
///
/// Run with: flutter test test/admin_localnet_test.dart
void main() async {
  final idsFile = File('tool/localnet/localnet_ids.json');
  if (!idsFile.existsSync()) {
    test('localnet admin suite', () {
      markTestSkipped('tool/localnet/localnet_ids.json not found — '
          'run tool/localnet/setup.sh first');
    });
    return;
  }
  final ids = jsonDecode(idsFile.readAsStringSync()) as Map<String, dynamic>;

  final client = SuiGrpcClient(
      network: SuiNetwork.localnet, endpoint: ids['endpoint'] as String);
  final core = client.core as GrpcCoreClient;
  final admin = SuiAccount.fromPrivateKey(ids['adminKey'] as String);

  var reachable = true;
  try {
    await core.getChainIdentifier();
  } catch (_) {
    reachable = false;
  }
  if (!reachable) {
    test('localnet admin suite', () {
      markTestSkipped('localnet not reachable at ${ids['endpoint']}');
    });
    return;
  }

  final pkg = ids['deepbookPackageId'] as String;
  // DEEP now lives in its own token package (older deployments inlined it).
  final tokenPkg = (ids['tokenPackageId'] ?? pkg) as String;
  final coins = <String, Coin>{
    'DEEP':
        Coin(address: tokenPkg, type: '$tokenPkg::deep::DEEP', scalar: 1000000),
    'SUI': const Coin(
      address: '0x2',
      type:
          '0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI',
      scalar: 1000000000,
    ),
  };

  DeepBookConfig makeConfig(PoolMap pools) => DeepBookConfig(
        network: 'localnet',
        address: admin.getAddress(),
        adminCap: ids['adminCap'] as String,
        packageIds: DeepbookPackageIds(
          deepbookPackageId: pkg,
          registryId: ids['registryId'] as String,
          deepTreasuryId: ids['deepTreasuryId'] as String,
        ),
        coins: coins,
        pools: pools,
      );

  test(
    'admin: create whitelisted pool, tune it, stablecoin round-trip, unregister',
    () async {
      final config = makeConfig(const {});
      final adminContract = DeepBookAdminContract(config);
      final ctx = QueryContext(core: core, config: config);

      Future<String?> resolvePoolId() async {
        final idTx = Transaction();
        pool_calls.getPoolIdByAsset(
          package: pkg,
          arguments: {'registry': config.REGISTRY_ID},
          typeArguments: [coins['DEEP']!.type, coins['SUI']!.type],
        )(idTx);
        try {
          return SuiBcs.Address.parse(await ctx.simulateReturn(idTx));
        } on DeepBookError {
          return null; // EPoolDoesNotExist
        }
      }

      // 1. Create a whitelisted DEEP/SUI pool (idempotent: reuse if a
      // previous run left one registered).
      var poolId = await resolvePoolId();
      if (poolId == null) {
        final createTx = Transaction();
        adminContract.createPoolAdmin(const CreatePoolAdminParams(
          baseCoinKey: 'DEEP',
          quoteCoinKey: 'SUI',
          tickSize: 0.001,
          lotSize: 1,
          minSize: 10,
          whitelisted: true,
          stablePool: false,
        ))(createTx);
        final created = await core.signAndExecuteTransaction(admin, createTx);
        expect(created.effects.status.success, isTrue,
            reason: created.effects.status.error.description);
        await core.waitForTransaction(created.digest,
            timeout: const Duration(minutes: 3));
        poolId = await resolvePoolId();
      }
      expect(poolId, isNotNull);
      expect(poolId!, startsWith('0x'));

      // 3. Rebuild config with the pool registered under a key.
      final config2 = makeConfig({
        'DEEP_SUI': Pool(address: poolId, baseCoin: 'DEEP', quoteCoin: 'SUI'),
      });
      final admin2 = DeepBookAdminContract(config2);
      final ctx2 = QueryContext(core: core, config: config2);

      // Whitelisted flag reads back true (query path on localnet).
      final wlTx = Transaction();
      pool_calls.whitelisted(
        package: pkg,
        arguments: {'self': poolId},
        typeArguments: [coins['DEEP']!.type, coins['SUI']!.type],
      )(wlTx);
      expect(SuiBcs.BOOL.parse(await ctx2.simulateReturn(wlTx)), isTrue);

      // 4. Tune the pool: tick size + lot/min size.
      final tuneTx = Transaction();
      // On-chain constraint: tick/lot sizes must be powers of ten (in raw
      // units): 0.01 → 1e7 ticks, lot 10 → 1e7, min 100 → 1e8.
      // and the new lot size must divide the current one (shrink only).
      admin2.adjustTickSize('DEEP_SUI', 0.01)(tuneTx);
      admin2.adjustMinLotSize('DEEP_SUI', 0.1, 1)(tuneTx);
      final tuned = await core.signAndExecuteTransaction(admin, tuneTx);
      expect(tuned.effects.status.success, isTrue,
          reason: tuned.effects.status.error.description);
      await core.waitForTransaction(tuned.digest,
          timeout: const Duration(minutes: 3));

      // 5. Stablecoin whitelist round-trip.
      final stableTx = Transaction();
      admin2.addStableCoin('SUI')(stableTx);
      final added = await core.signAndExecuteTransaction(admin, stableTx);
      expect(added.effects.status.success, isTrue);
      await core.waitForTransaction(added.digest,
          timeout: const Duration(minutes: 3));
      final unstableTx = Transaction();
      admin2.removeStableCoin('SUI')(unstableTx);
      final removed = await core.signAndExecuteTransaction(admin, unstableTx);
      expect(removed.effects.status.success, isTrue);
      await core.waitForTransaction(removed.digest,
          timeout: const Duration(minutes: 3));

      // 6. Unregister the pool.
      final unregTx = Transaction();
      admin2.unregisterPoolAdmin('DEEP_SUI')(unregTx);
      final unregistered = await core.signAndExecuteTransaction(admin, unregTx);
      expect(unregistered.effects.status.success, isTrue,
          reason: unregistered.effects.status.error.description);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
