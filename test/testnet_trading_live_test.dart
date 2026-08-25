import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart' hide Coin;
import 'package:deepbook/deepbook.dart';

/// REAL trading against the PUBLIC testnet order books.
///
/// Flow: acquire DEEP via a real swap on the whitelisted DEEP/SUI pool (only
/// when the wallet doesn't already hold enough), place a real non-crossing
/// ask on DEEP/SUI, read it back from the live book, cancel it and withdraw.
/// When the wallet has spare SUI, additionally exercises the DEEP-fee path
/// with an ask on SUI/DBUSDC. Everything returns to the wallet afterwards.
///
/// Run with: flutter test test/testnet_trading_live_test.dart
void main() {
  const testPrivKey =
      'suiprivkey1qrhwmd5a92dkdym3mp3ldk9w6pr94xrkku6yp5lm97kv4dnvp30njag85ke';
  final account = SuiAccount.fromPrivateKey(testPrivKey);
  final address = account.getAddress();

  final grpc = SuiGrpcClient(network: SuiNetwork.testnet);
  final core = grpc.core as GrpcCoreClient;

  Future<double> balanceOf(String coinKey) async {
    final balance =
        await core.getBalance(address, coinType: testnetCoins[coinKey]!.type);
    return BigInt.parse(balance.balance.toString()).toDouble() /
        testnetCoins[coinKey]!.scalar;
  }

  Future<void> execute(Transaction tx, String what) async {
    final executed = await core.signAndExecuteTransaction(account, tx);
    expect(executed.effects.status.success, isTrue,
        reason: '$what: ${executed.effects.status.error.description}');
    await core.waitForTransaction(executed.digest,
        timeout: const Duration(minutes: 3));
  }

  test(
    'real swap for DEEP, real order on the live book, cancel, withdraw',
    () async {
      final probe =
          DeepBookClient(client: core, network: 'testnet', address: address);

      if (!await probe.whitelisted('DEEP_SUI')) {
        markTestSkipped('testnet DEEP_SUI pool is not whitelisted');
        return;
      }
      final double deepMid;
      try {
        deepMid = await probe.midPrice('DEEP_SUI');
      } on DeepBookError {
        markTestSkipped('testnet DEEP_SUI book has no mid price');
        return;
      }
      final book = await probe.poolBookParams('DEEP_SUI');

      // --- 1. Ensure DEEP: real swap SUI → DEEP when the wallet is short.
      final neededDeep = book.minSize + 1;
      if (await balanceOf('DEEP') < neededDeep) {
        final suiIn = book.minSize * 2 * deepMid * 1.1;
        if (await balanceOf('SUI') < suiIn + 0.1) {
          markTestSkipped('wallet lacks SUI for the bootstrap swap; '
              'top up via the testnet faucet');
          return;
        }
        final db = DeepBookContract(
            DeepBookConfig(network: 'testnet', address: address));
        final swapTx = Transaction();
        final swapped = db.swapExactQuoteForBase(SwapParams(
          poolKey: 'DEEP_SUI',
          amount: suiIn,
          deepAmount: 0,
          minOut: 0,
        ))(swapTx);
        swapTx.transferObjects([swapped[0], swapped[1], swapped[2]], address);
        await execute(swapTx, 'bootstrap swap');
        expect(await balanceOf('DEEP'), greaterThanOrEqualTo(neededDeep),
            reason: 'swap returned no DEEP (below pool min size?)');
      }

      // --- 2. Fund the registered manager with DEEP.
      final managerIds = await probe.getBalanceManagerIds(address);
      expect(managerIds, isNotEmpty,
          reason: 'balance_manager_live_test creates this manager');
      final config = DeepBookConfig(
        network: 'testnet',
        address: address,
        balanceManagers: {'MAIN': BalanceManager(address: managerIds.first)},
      );
      final client = DeepBookClient(
        client: core,
        network: 'testnet',
        address: address,
        balanceManagers: {'MAIN': BalanceManager(address: managerIds.first)},
      );
      final bm = BalanceManagerContract(config);
      final db = DeepBookContract(config);

      final fundTx = Transaction();
      bm.depositIntoManager('MAIN', 'DEEP', neededDeep)(fundTx);
      await execute(fundTx, 'fund manager');

      // --- 3. Real ask on the LIVE public book, priced far above mid so it
      // rests (2× mid, rounded up to a tick multiple).
      final price =
          ((deepMid * 2) / book.tickSize).ceilToDouble() * book.tickSize;
      final orderTx = Transaction();
      db.placeLimitOrder(PlaceLimitOrderParams(
        poolKey: 'DEEP_SUI',
        balanceManagerKey: 'MAIN',
        clientOrderId: '20260729',
        price: price,
        quantity: book.minSize,
        isBid: false,
        payWithDeep: false, // whitelisted pool
      ))(orderTx);
      await execute(orderTx, 'place resting ask');

      final open = await client.accountOpenOrders('DEEP_SUI', 'MAIN');
      expect(open, hasLength(1));
      final order = await client.getOrder('DEEP_SUI', open.first);
      expect(order, isNotNull);

      // --- 4. Cancel and withdraw everything back.
      final cleanTx = Transaction();
      db.cancelAllOrders('DEEP_SUI', 'MAIN')(cleanTx);
      for (final coin in ['DEEP', 'SUI']) {
        bm.withdrawAllFromManager('MAIN', coin, address)(cleanTx);
      }
      await execute(cleanTx, 'cancel + withdraw');
      expect(await client.accountOpenOrders('DEEP_SUI', 'MAIN'), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'DEEP-fee order on SUI/DBUSDC (runs when the wallet has spare SUI)',
    () async {
      final probe =
          DeepBookClient(client: core, network: 'testnet', address: address);
      final book = await probe.poolBookParams('SUI_DBUSDC');
      final needed = book.minSize + 0.3; // escrow + gas headroom

      if (await balanceOf('SUI') < needed) {
        // One polite faucet attempt, then skip if still short.
        try {
          await Dio().post(
            'https://faucet.testnet.sui.io/v2/gas',
            data: {
              'FixedAmountRequest': {'recipient': address}
            },
            options: Options(receiveTimeout: const Duration(seconds: 20)),
          );
          await Future.delayed(const Duration(seconds: 5));
        } catch (_) {/* rate limited */}
        if (await balanceOf('SUI') < needed) {
          markTestSkipped(
              'wallet SUI below ${needed.toStringAsFixed(2)} and faucet is '
              'rate-limited — rerun later for the DEEP-fee path');
          return;
        }
      }
      if (await balanceOf('DEEP') < 1) {
        markTestSkipped('no DEEP for fees — first test must run before this');
        return;
      }

      final managerIds = await probe.getBalanceManagerIds(address);
      final config = DeepBookConfig(
        network: 'testnet',
        address: address,
        balanceManagers: {'MAIN': BalanceManager(address: managerIds.first)},
      );
      final client = DeepBookClient(
        client: core,
        network: 'testnet',
        address: address,
        balanceManagers: {'MAIN': BalanceManager(address: managerIds.first)},
      );
      final bm = BalanceManagerContract(config);
      final db = DeepBookContract(config);

      final mid = await client.midPrice('SUI_DBUSDC');
      final price = ((mid * 2) / book.tickSize).ceilToDouble() * book.tickSize;

      final fundTx = Transaction();
      bm.depositIntoManager('MAIN', 'SUI', book.minSize)(fundTx);
      bm.depositIntoManager('MAIN', 'DEEP', 1)(fundTx);
      await execute(fundTx, 'fund');

      final orderTx = Transaction();
      db.placeLimitOrder(PlaceLimitOrderParams(
        poolKey: 'SUI_DBUSDC',
        balanceManagerKey: 'MAIN',
        clientOrderId: '20260730',
        price: price,
        quantity: book.minSize,
        isBid: false,
        payWithDeep: true, // fee pool: fees escrowed in DEEP
      ))(orderTx);
      await execute(orderTx, 'place DEEP-fee ask');

      expect(
          await client.accountOpenOrders('SUI_DBUSDC', 'MAIN'), hasLength(1));

      final cleanTx = Transaction();
      db.cancelAllOrders('SUI_DBUSDC', 'MAIN')(cleanTx);
      for (final coin in ['SUI', 'DEEP', 'DBUSDC']) {
        bm.withdrawAllFromManager('MAIN', coin, address)(cleanTx);
      }
      await execute(cleanTx, 'cancel + withdraw');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
