import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart';
import 'package:deepbook/deepbook.dart';

/// Live testnet tests for the BalanceManager module (M4).
///
/// Uses the sui package's stable funded test account. The write test creates
/// (or reuses) a registered BalanceManager, deposits 0.05 SUI, checks the
/// balance via devInspect, then withdraws everything back — so the account's
/// SUI balance is preserved across runs (minus gas).
///
/// Run with: flutter test test/balance_manager_live_test.dart
void main() {
  const testPrivKey =
      'suiprivkey1qrhwmd5a92dkdym3mp3ldk9w6pr94xrkku6yp5lm97kv4dnvp30njag85ke';
  final account = SuiAccount.fromPrivateKey(testPrivKey);
  final address = account.getAddress();

  final client = SuiGrpcClient(network: SuiNetwork.testnet);
  final core = client.core as GrpcCoreClient;

  DeepBookConfig configWith(Map<String, BalanceManager> managers) =>
      DeepBookConfig(
          network: 'testnet', address: address, balanceManagers: managers);

  test('getBalanceManagerIds parses (possibly empty) id vector', () async {
    final ctx = QueryContext(core: core, config: configWith({}));
    final ids = await BalanceManagerQueries(ctx).getBalanceManagerIds(address);
    expect(ids, isA<List<String>>());
    for (final id in ids) {
      expect(id, startsWith('0x'));
      expect(id.length, 66);
    }
  });

  test('simulate create+share BalanceManager succeeds', () async {
    final ctx = QueryContext(core: core, config: configWith({}));
    final tx = Transaction();
    BalanceManagerContract(ctx.config).createAndShareBalanceManager()(tx);
    final results = await ctx.simulate(tx);
    expect(results, isNotEmpty);
  });

  test(
    'write path: create/reuse manager, deposit, check balance, withdraw',
    () async {
      final ctx = QueryContext(core: core, config: configWith({}));
      final queries = BalanceManagerQueries(ctx);
      final contract = BalanceManagerContract(ctx.config);

      // Reuse a registered manager when one exists; otherwise create,
      // share and register one.
      var ids = await queries.getBalanceManagerIds(address);
      if (ids.isEmpty) {
        final tx = Transaction();
        final manager = contract.createBalanceManagerWithOwner(address)(tx);
        tx.moveCall(
          '${ctx.config.DEEPBOOK_PACKAGE_ID}::balance_manager::register_balance_manager',
          arguments: [manager, tx.object(ctx.config.REGISTRY_ID)],
        );
        contract.shareBalanceManager(manager)(tx);
        final executed = await core.signAndExecuteTransaction(account, tx);
        expect(executed.effects.status.success, isTrue,
            reason: executed.effects.status.error.description);
        await core.waitForTransaction(executed.digest,
            timeout: const Duration(minutes: 3));
        ids = await queries.getBalanceManagerIds(address);
      }
      expect(ids, isNotEmpty);
      final managerId = ids.first;

      final config = configWith({'MAIN': BalanceManager(address: managerId)});
      final ctx2 = QueryContext(core: core, config: config);
      final queries2 = BalanceManagerQueries(ctx2);
      final contract2 = BalanceManagerContract(config);

      // Deposit 0.05 SUI.
      final depositTx = Transaction();
      contract2.depositIntoManager('MAIN', 'SUI', 0.05)(depositTx);
      final deposited =
          await core.signAndExecuteTransaction(account, depositTx);
      expect(deposited.effects.status.success, isTrue,
          reason: deposited.effects.status.error.description);
      await core.waitForTransaction(deposited.digest,
          timeout: const Duration(minutes: 3));

      // Balance now ≥ 0.05 SUI.
      final balance = await queries2.checkManagerBalance('MAIN', 'SUI');
      expect(balance.coinType, contains('::sui::SUI'));
      expect(balance.balance, greaterThanOrEqualTo(0.05));

      // The address-based variants agree.
      final byAddress =
          await queries2.checkManagerBalanceWithAddress(managerId, 'SUI');
      expect(byAddress.balance, balance.balance);
      final matrix = await queries2
          .checkManagerBalancesWithAddress([managerId], ['SUI', 'DEEP']);
      final suiType = testnetCoins['SUI']!.type;
      expect(matrix[managerId]![suiType], balance.balance);
      expect(matrix[managerId]!.length, 2);

      // Withdraw everything back to the owner.
      final withdrawTx = Transaction();
      contract2.withdrawAllFromManager('MAIN', 'SUI', address)(withdrawTx);
      final withdrawn =
          await core.signAndExecuteTransaction(account, withdrawTx);
      expect(withdrawn.effects.status.success, isTrue,
          reason: withdrawn.effects.status.error.description);
      await core.waitForTransaction(withdrawn.digest,
          timeout: const Duration(minutes: 3));

      final after = await queries2.checkManagerBalance('MAIN', 'SUI');
      expect(after.balance, 0);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
