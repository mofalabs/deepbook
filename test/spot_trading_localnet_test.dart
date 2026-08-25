import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bcs/bcs.dart';
import 'package:sui/sui.dart' hide Coin;
import 'package:deepbook/deepbook.dart';
import 'package:deepbook/src/contracts/deepbook/pool.dart' as pool_calls;

/// Real spot-trading round trip on localnet: create/reuse a whitelisted
/// DEEP/SUI pool, fund a BalanceManager, place a limit order, read it back,
/// cancel it, withdraw. All transactions are actually executed.
///
/// Run with: flutter test test/spot_trading_localnet_test.dart
void main() async {
  final idsFile = File('tool/localnet/localnet_ids.json');
  if (!idsFile.existsSync()) {
    test('localnet spot suite', () {
      markTestSkipped('run tool/localnet/setup.sh first');
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
    test('localnet spot suite', () {
      markTestSkipped('localnet not reachable');
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

  test(
    'spot: fund manager, place limit order, read back, cancel, withdraw',
    () async {
      final bootstrapConfig = DeepBookConfig(
        network: 'localnet',
        address: admin.getAddress(),
        adminCap: ids['adminCap'] as String,
        packageIds: DeepbookPackageIds(
          deepbookPackageId: pkg,
          registryId: ids['registryId'] as String,
          deepTreasuryId: ids['deepTreasuryId'] as String,
        ),
        coins: coins,
        pools: const {},
      );
      final ctx = QueryContext(core: core, config: bootstrapConfig);

      // --- Pool: reuse or create whitelisted DEEP/SUI. ---
      Future<String?> resolvePoolId() async {
        final idTx = Transaction();
        pool_calls.getPoolIdByAsset(
          package: pkg,
          arguments: {'registry': bootstrapConfig.REGISTRY_ID},
          typeArguments: [coins['DEEP']!.type, coins['SUI']!.type],
        )(idTx);
        try {
          return SuiBcs.Address.parse(await ctx.simulateReturn(idTx));
        } on DeepBookError {
          return null;
        }
      }

      var poolId = await resolvePoolId();
      if (poolId == null) {
        final createTx = Transaction();
        DeepBookAdminContract(bootstrapConfig)
            .createPoolAdmin(const CreatePoolAdminParams(
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

      // --- BalanceManager: reuse or create+register+share. ---
      // A fresh localnet registry has no balance-manager map yet; initialize
      // it (admin op) on first use.
      final bmQueries = BalanceManagerQueries(ctx);
      List<String> managerIds;
      try {
        managerIds = await bmQueries.getBalanceManagerIds(admin.getAddress());
      } on DeepBookError {
        final initTx = Transaction();
        DeepBookAdminContract(bootstrapConfig).initBalanceManagerMap()(initTx);
        final inited = await core.signAndExecuteTransaction(admin, initTx);
        expect(inited.effects.status.success, isTrue,
            reason: inited.effects.status.error.description);
        await core.waitForTransaction(inited.digest,
            timeout: const Duration(minutes: 3));
        managerIds = await bmQueries.getBalanceManagerIds(admin.getAddress());
      }
      if (managerIds.isEmpty) {
        final tx = Transaction();
        final contract = BalanceManagerContract(bootstrapConfig);
        final manager =
            contract.createBalanceManagerWithOwner(admin.getAddress())(tx);
        tx.moveCall(
          '$pkg::balance_manager::register_balance_manager',
          arguments: [manager, tx.object(bootstrapConfig.REGISTRY_ID)],
        );
        contract.shareBalanceManager(manager)(tx);
        final executed = await core.signAndExecuteTransaction(admin, tx);
        expect(executed.effects.status.success, isTrue,
            reason: executed.effects.status.error.description);
        // A busy localnet can lag well past the 60s default.
        await core.waitForTransaction(executed.digest,
            timeout: const Duration(minutes: 3));
        managerIds = await bmQueries.getBalanceManagerIds(admin.getAddress());
      }
      expect(managerIds, isNotEmpty);

      final config = DeepBookConfig(
        network: 'localnet',
        address: admin.getAddress(),
        adminCap: ids['adminCap'] as String,
        packageIds: DeepbookPackageIds(
          deepbookPackageId: pkg,
          registryId: ids['registryId'] as String,
          deepTreasuryId: ids['deepTreasuryId'] as String,
        ),
        coins: coins,
        pools: {
          'DEEP_SUI':
              Pool(address: poolId!, baseCoin: 'DEEP', quoteCoin: 'SUI'),
        },
        balanceManagers: {
          'MAIN': BalanceManager(address: managerIds.first),
        },
      );
      final ctx2 = QueryContext(core: core, config: config);
      final bm = BalanceManagerContract(config);
      final deepBook = DeepBookContract(config);
      final queries = BalanceManagerQueries(ctx2);

      // --- Fund the manager: 100 DEEP + 5 SUI. ---
      final fundTx = Transaction();
      bm.depositIntoManager('MAIN', 'DEEP', 100)(fundTx);
      bm.depositIntoManager('MAIN', 'SUI', 5)(fundTx);
      final funded = await core.signAndExecuteTransaction(admin, fundTx);
      expect(funded.effects.status.success, isTrue,
          reason: funded.effects.status.error.description);
      await core.waitForTransaction(funded.digest,
          timeout: const Duration(minutes: 3));

      final deepBalance = await queries.checkManagerBalance('MAIN', 'DEEP');
      expect(deepBalance.balance, greaterThanOrEqualTo(100));

      // --- Place a limit bid: 10 DEEP @ 0.1 SUI. ---
      final orderTx = Transaction();
      deepBook.placeLimitOrder(const PlaceLimitOrderParams(
        poolKey: 'DEEP_SUI',
        balanceManagerKey: 'MAIN',
        clientOrderId: '42',
        price: 0.1,
        quantity: 10,
        isBid: true,
        payWithDeep: false, // whitelisted pool: no fees
      ))(orderTx);
      final placed = await core.signAndExecuteTransaction(admin, orderTx);
      expect(placed.effects.status.success, isTrue,
          reason: placed.effects.status.error.description);
      await core.waitForTransaction(placed.digest,
          timeout: const Duration(minutes: 3));

      // --- Read the open order back (devInspect). ---
      final openTx = Transaction();
      deepBook.accountOpenOrders('DEEP_SUI', 'MAIN')(openTx);
      final openBytes = await ctx2.simulateReturn(openTx);
      final orderIds =
          Bcs.struct('VecSet', {'contents': Bcs.vector(Bcs.u128())})
              .parse(openBytes)['contents'] as List;
      expect(orderIds, hasLength(1));

      // --- Cancel it. ---
      final cancelTx = Transaction();
      deepBook.cancelAllOrders('DEEP_SUI', 'MAIN')(cancelTx);
      final cancelled = await core.signAndExecuteTransaction(admin, cancelTx);
      expect(cancelled.effects.status.success, isTrue,
          reason: cancelled.effects.status.error.description);
      await core.waitForTransaction(cancelled.digest,
          timeout: const Duration(minutes: 3));

      final afterTx = Transaction();
      deepBook.accountOpenOrders('DEEP_SUI', 'MAIN')(afterTx);
      final afterIds =
          Bcs.struct('VecSet', {'contents': Bcs.vector(Bcs.u128())})
              .parse(await ctx2.simulateReturn(afterTx))['contents'] as List;
      expect(afterIds, isEmpty);

      // --- Withdraw everything back. ---
      final withdrawTx = Transaction();
      bm.withdrawAllFromManager('MAIN', 'DEEP', admin.getAddress())(withdrawTx);
      bm.withdrawAllFromManager('MAIN', 'SUI', admin.getAddress())(withdrawTx);
      final withdrawn = await core.signAndExecuteTransaction(admin, withdrawTx);
      expect(withdrawn.effects.status.success, isTrue,
          reason: withdrawn.effects.status.error.description);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
