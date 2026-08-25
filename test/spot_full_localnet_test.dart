import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart' hide Coin;
import 'package:deepbook/deepbook.dart';

/// Full-function REAL-EXECUTION suite on localnet: every test in this file
/// actually executes transactions on chain — matched trades, market orders,
/// order modification, swaps against live liquidity, flash loans, cap-based
/// permissions and governance — and asserts the resulting on-chain state.
///
/// Requires a localnet deployed via tool/localnet/setup.sh (plus the dusdc
/// test coin; see localnet_ids.json). Skips itself otherwise.
///
/// Run with: flutter test test/spot_full_localnet_test.dart
void main() async {
  final idsFile = File('tool/localnet/localnet_ids.json');
  if (!idsFile.existsSync()) {
    test('localnet full spot suite', () {
      markTestSkipped('run tool/localnet/setup.sh first');
    });
    return;
  }
  final ids = jsonDecode(idsFile.readAsStringSync()) as Map<String, dynamic>;
  final grpc = SuiGrpcClient(
      network: SuiNetwork.localnet, endpoint: ids['endpoint'] as String);
  final core = grpc.core as GrpcCoreClient;
  final admin = SuiAccount.fromPrivateKey(ids['adminKey'] as String);

  var reachable = true;
  try {
    await core.getChainIdentifier();
  } catch (_) {
    reachable = false;
  }
  if (!reachable || ids['dusdcPackageId'] == null) {
    test('localnet full spot suite', () {
      markTestSkipped('localnet not reachable or dusdc not deployed');
    });
    return;
  }

  final pkg = ids['deepbookPackageId'] as String;
  // DEEP now lives in its own token package (older deployments inlined it).
  final tokenPkg = (ids['tokenPackageId'] ?? pkg) as String;
  final dusdcPkg = ids['dusdcPackageId'] as String;
  final coins = <String, Coin>{
    'DEEP':
        Coin(address: tokenPkg, type: '$tokenPkg::deep::DEEP', scalar: 1000000),
    'SUI': const Coin(
      address: '0x2',
      type:
          '0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI',
      scalar: 1000000000,
    ),
    'DUSDC': Coin(
        address: dusdcPkg, type: '$dusdcPkg::dusdc::DUSDC', scalar: 1000000),
  };

  DeepBookConfig baseConfig({
    PoolMap pools = const {},
    Map<String, BalanceManager> managers = const {},
  }) =>
      DeepBookConfig(
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
        balanceManagers: managers,
      );

  Future<void> execute(Transaction tx, [String? what]) async {
    final executed = await core.signAndExecuteTransaction(admin, tx);
    expect(executed.effects.status.success, isTrue,
        reason:
            '${what ?? 'tx'}: ${executed.effects.status.error.description}');
    // A busy localnet can lag well past the 60s default.
    await core.waitForTransaction(executed.digest,
        timeout: const Duration(minutes: 3));
  }

  // --- Shared setup: pools + two funded balance managers. ---
  late final String deepSuiPoolId;
  late final String suiDusdcPoolId;
  late final String m1;
  late final String m2;
  late final DeepBookConfig config;
  late final DeepBookClient client;

  setUpAll(() async {
    final bootstrap = baseConfig();

    // Each run gets FRESH pools (clean books, deterministic): unregister any
    // pool left by a previous run for this pair, then create a new one.
    Future<String> ensurePool(
        String baseKey, String quoteKey, bool whitelisted) async {
      final probe = DeepBookClient(
        client: core,
        network: 'localnet',
        address: admin.getAddress(),
        packageIds: DeepbookPackageIds(
          deepbookPackageId: pkg,
          registryId: ids['registryId'] as String,
          deepTreasuryId: ids['deepTreasuryId'] as String,
        ),
        coins: coins,
      );
      try {
        final stale = await probe.getPoolIdByAssets(
            coins[baseKey]!.type, coins[quoteKey]!.type);
        final staleConfig = baseConfig(pools: {
          'STALE': Pool(address: stale, baseCoin: baseKey, quoteCoin: quoteKey),
        });
        final unregTx = Transaction();
        DeepBookAdminContract(staleConfig)
            .unregisterPoolAdmin('STALE')(unregTx);
        await execute(unregTx, 'unregister stale pool');
      } on DeepBookError {
        // No pool registered for this pair — nothing to clean up.
      }
      final tx = Transaction();
      DeepBookAdminContract(bootstrap).createPoolAdmin(CreatePoolAdminParams(
        baseCoinKey: baseKey,
        quoteCoinKey: quoteKey,
        tickSize: 0.001,
        lotSize: 1,
        minSize: 1,
        whitelisted: whitelisted,
        stablePool: false,
      ))(tx);
      await execute(tx, 'create pool $baseKey/$quoteKey');
      return await probe.getPoolIdByAssets(
          coins[baseKey]!.type, coins[quoteKey]!.type);
    }

    deepSuiPoolId = await ensurePool('DEEP', 'SUI', true);
    suiDusdcPoolId = await ensurePool('SUI', 'DUSDC', false);

    // Two FRESH managers per run (epoch-scoped state like governance
    // proposals is keyed by manager, so reuse breaks idempotency).
    final bmQueries =
        BalanceManagerQueries(QueryContext(core: core, config: bootstrap));
    Set<String> before;
    try {
      before =
          (await bmQueries.getBalanceManagerIds(admin.getAddress())).toSet();
    } on DeepBookError {
      // Fresh registry: initialize the balance-manager map first (admin op).
      final initTx = Transaction();
      DeepBookAdminContract(bootstrap).initBalanceManagerMap()(initTx);
      await execute(initTx, 'init balance manager map');
      before =
          (await bmQueries.getBalanceManagerIds(admin.getAddress())).toSet();
    }
    final createTx = Transaction();
    final contract = BalanceManagerContract(bootstrap);
    for (var i = 0; i < 2; i++) {
      final manager =
          contract.createBalanceManagerWithOwner(admin.getAddress())(createTx);
      createTx.moveCall(
        '$pkg::balance_manager::register_balance_manager',
        arguments: [manager, createTx.object(ids['registryId'] as String)],
      );
      contract.shareBalanceManager(manager)(createTx);
    }
    await execute(createTx, 'create managers');
    final fresh = (await bmQueries.getBalanceManagerIds(admin.getAddress()))
        .where((id) => !before.contains(id))
        .toList();
    expect(fresh, hasLength(2));
    m1 = fresh[0];
    m2 = fresh[1];

    config = baseConfig(
      pools: {
        'DEEP_SUI':
            Pool(address: deepSuiPoolId, baseCoin: 'DEEP', quoteCoin: 'SUI'),
        'SUI_DUSDC':
            Pool(address: suiDusdcPoolId, baseCoin: 'SUI', quoteCoin: 'DUSDC'),
      },
      managers: {
        'M1': BalanceManager(address: m1),
        'M2': BalanceManager(address: m2),
      },
    );
    client = DeepBookClient(
      client: core,
      network: 'localnet',
      address: admin.getAddress(),
      packageIds: DeepbookPackageIds(
        deepbookPackageId: pkg,
        registryId: ids['registryId'] as String,
        deepTreasuryId: ids['deepTreasuryId'] as String,
      ),
      coins: coins,
      pools: {
        'DEEP_SUI':
            Pool(address: deepSuiPoolId, baseCoin: 'DEEP', quoteCoin: 'SUI'),
        'SUI_DUSDC':
            Pool(address: suiDusdcPoolId, baseCoin: 'SUI', quoteCoin: 'DUSDC'),
      },
      balanceManagers: {
        'M1': BalanceManager(address: m1),
        'M2': BalanceManager(address: m2),
      },
      adminCap: ids['adminCap'] as String,
    );

    // Fund: M1/M2 each with DEEP, SUI and DUSDC.
    final bm = BalanceManagerContract(config);
    final fundTx = Transaction();
    for (final key in ['M1', 'M2']) {
      bm.depositIntoManager(key, 'DEEP', 500)(fundTx);
      bm.depositIntoManager(key, 'SUI', 20)(fundTx);
      bm.depositIntoManager(key, 'DUSDC', 500)(fundTx);
    }
    await execute(fundTx, 'fund managers');
  });

  tearDownAll(() async {
    // Cancel leftovers and withdraw everything back to the admin address.
    final bm = BalanceManagerContract(config);
    final db = DeepBookContract(config);
    final tx = Transaction();
    for (final key in ['M1', 'M2']) {
      db.cancelAllOrders('DEEP_SUI', key)(tx);
      db.cancelAllOrders('SUI_DUSDC', key)(tx);
      for (final coin in ['DEEP', 'SUI', 'DUSDC']) {
        bm.withdrawAllFromManager(key, coin, admin.getAddress())(tx);
      }
    }
    try {
      await execute(tx, 'teardown');
    } catch (_) {/* best effort */}
  });

  Future<void> resetBooks() async {
    final db = DeepBookContract(config);
    final tx = Transaction();
    for (final key in ['M1', 'M2']) {
      db.cancelAllOrders('DEEP_SUI', key)(tx);
      db.cancelAllOrders('SUI_DUSDC', key)(tx);
    }
    await execute(tx, 'reset books');
  }

  test('crossing limit orders really match and settle', () async {
    final db = DeepBookContract(config);
    await resetBooks();

    // M1 bids 10 DEEP @ 0.5 SUI; M2 asks the same → full fill.
    final before1 = await client.checkManagerBalance('M1', 'DEEP');
    final before1Sui = await client.checkManagerBalance('M1', 'SUI');

    final bidTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M1',
      clientOrderId: '1001',
      price: 0.5,
      quantity: 10,
      isBid: true,
      payWithDeep: false,
    ))(bidTx);
    await execute(bidTx, 'M1 bid');

    final askTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M2',
      clientOrderId: '1002',
      price: 0.5,
      quantity: 10,
      isBid: false,
      payWithDeep: false,
    ))(askTx);
    await execute(askTx, 'M2 ask (taker)');

    // Both books empty; taker (M2) settled instantly, maker (M1) settles on
    // its next pool interaction (a no-op cancelAll works).
    expect(await client.accountOpenOrders('DEEP_SUI', 'M2'), isEmpty);
    final settleTx = Transaction();
    db.withdrawSettledAmounts('DEEP_SUI', 'M1')(settleTx);
    await execute(settleTx, 'M1 settle');
    expect(await client.accountOpenOrders('DEEP_SUI', 'M1'), isEmpty);

    // M1 bought 10 DEEP for 5 SUI (whitelisted pool → zero fees).
    final after1 = await client.checkManagerBalance('M1', 'DEEP');
    final after1Sui = await client.checkManagerBalance('M1', 'SUI');
    expect(after1.balance - before1.balance, closeTo(10, 1e-6));
    expect(before1Sui.balance - after1Sui.balance, closeTo(5, 1e-6));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('market order fills against resting liquidity', () async {
    final db = DeepBookContract(config);
    await resetBooks();

    final restTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M1',
      clientOrderId: '2001',
      price: 0.6,
      quantity: 20,
      isBid: false,
      payWithDeep: false,
    ))(restTx);
    await execute(restTx, 'M1 resting ask');

    final beforeDeep = await client.checkManagerBalance('M2', 'DEEP');
    final marketTx = Transaction();
    db.placeMarketOrder(const PlaceMarketOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M2',
      clientOrderId: '2002',
      quantity: 10,
      isBid: true,
      payWithDeep: false,
    ))(marketTx);
    await execute(marketTx, 'M2 market buy');

    final afterDeep = await client.checkManagerBalance('M2', 'DEEP');
    expect(afterDeep.balance - beforeDeep.balance, closeTo(10, 1e-6));

    // Remainder still resting, then cancel.
    final open = await client.accountOpenOrders('DEEP_SUI', 'M1');
    expect(open, hasLength(1));
    final cancelTx = Transaction();
    db.cancelAllOrders('DEEP_SUI', 'M1')(cancelTx);
    await execute(cancelTx, 'cancel rest');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('modifyOrder really shrinks a resting order', () async {
    final db = DeepBookContract(config);
    await resetBooks();

    final placeTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M1',
      clientOrderId: '3001',
      price: 0.1,
      quantity: 20,
      isBid: true,
      payWithDeep: false,
    ))(placeTx);
    await execute(placeTx, 'place');

    final open = await client.accountOpenOrders('DEEP_SUI', 'M1');
    expect(open, hasLength(1));
    final orderId = open.first;

    final order = await client.getOrder('DEEP_SUI', orderId);
    expect(order, isNotNull);
    expect((order!['quantity'] as BigInt).toInt(), 20 * 1000000);

    final modifyTx = Transaction();
    db.modifyOrder('DEEP_SUI', 'M1', orderId, 10)(modifyTx);
    await execute(modifyTx, 'modify');

    final modified = await client.getOrder('DEEP_SUI', orderId);
    expect((modified!['quantity'] as BigInt).toInt(), 10 * 1000000);

    final cancelTx = Transaction();
    db.cancelOrder('DEEP_SUI', 'M1', orderId)(cancelTx);
    await execute(cancelTx, 'cancel');
    expect(await client.accountOpenOrders('DEEP_SUI', 'M1'), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('swapExactQuoteForBase executes against the live book', () async {
    final db = DeepBookContract(config);
    await resetBooks();

    final restTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M1',
      clientOrderId: '4001',
      price: 0.5,
      quantity: 20,
      isBid: false,
      payWithDeep: false,
    ))(restTx);
    await execute(restTx, 'resting ask');

    // Swap 1 SUI → DEEP directly from the admin wallet (no manager).
    final swapTx = Transaction();
    final result = db.swapExactQuoteForBase(const SwapParams(
      poolKey: 'DEEP_SUI',
      amount: 1, // 1 SUI
      deepAmount: 0, // whitelisted pool: no DEEP fee
      minOut: 1.5, // expect 2 DEEP at 0.5, allow slack
    ))(swapTx);
    swapTx
        .transferObjects([result[0], result[1], result[2]], admin.getAddress());
    await execute(swapTx, 'swap');

    final cancelTx = Transaction();
    db.cancelAllOrders('DEEP_SUI', 'M1')(cancelTx);
    await execute(cancelTx, 'cancel rest');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('flash loan borrows and returns within one transaction', () async {
    final db = DeepBookContract(config);
    final flash = FlashLoanContract(config);
    await resetBooks();

    final restTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M1',
      clientOrderId: '5001',
      price: 0.5,
      quantity: 20,
      isBid: false,
      payWithDeep: false,
    ))(restTx);
    await execute(restTx, 'vault liquidity');

    final loanTx = Transaction();
    final borrowed = flash.borrowBaseAsset('DEEP_SUI', 10)(loanTx);
    final leftover =
        flash.returnBaseAsset('DEEP_SUI', 10, borrowed[0], borrowed[1])(loanTx);
    // The repay amount is split out of the borrowed coin; the (now empty)
    // original coin must still be consumed.
    loanTx.transferObjects([leftover], admin.getAddress());
    await execute(loanTx, 'flash loan round trip');

    final cancelTx = Transaction();
    db.cancelAllOrders('DEEP_SUI', 'M1')(cancelTx);
    await execute(cancelTx, 'cancel rest');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('trade caps: mint, trade via TradeCap, revoke', () async {
    final bm = BalanceManagerContract(config);

    final mintTx = Transaction();
    final cap = bm.mintTradeCap('M1')(mintTx);
    mintTx.transferObjects([cap], admin.getAddress());
    final minted = await core.signAndExecuteTransaction(admin, mintTx);
    expect(minted.effects.status.success, isTrue,
        reason: minted.effects.status.error.description);
    await core.waitForTransaction(minted.digest,
        timeout: const Duration(minutes: 3));

    // The freshly created object in this transaction is the TradeCap
    // (earlier runs may have left revoked caps in the wallet).
    final created = minted.effects.changedObjects
        .where((o) => o.idOperation.name == 'CREATED')
        .toList();
    expect(created, isNotEmpty);
    final tradeCapId = created.first.objectId;

    // Trade via the cap (generateProofAsTrader path).
    final capConfig = baseConfig(
      pools: {
        'DEEP_SUI':
            Pool(address: deepSuiPoolId, baseCoin: 'DEEP', quoteCoin: 'SUI'),
      },
      managers: {
        'M1': BalanceManager(address: m1, tradeCap: tradeCapId),
      },
    );
    final capDb = DeepBookContract(capConfig);
    final orderTx = Transaction();
    capDb.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M1',
      clientOrderId: '6001',
      price: 0.1,
      quantity: 10,
      isBid: true,
      payWithDeep: false,
    ))(orderTx);
    capDb.cancelAllOrders('DEEP_SUI', 'M1')(orderTx);
    await execute(orderTx, 'trade via TradeCap');

    // Revoke the cap.
    final revokeTx = Transaction();
    bm.revokeTradeCap('M1', tradeCapId)(revokeTx);
    await execute(revokeTx, 'revoke trade cap');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('governance: stake, submit proposal, vote on a fee-based pool',
      () async {
    final db = DeepBookContract(config);
    final gov = GovernanceContract(config);

    // DEEP-fee pools need a DEEP price: maintain a two-sided book on the
    // whitelisted DEEP/SUI pool and feed a price point into DEEP/DUSDC.
    final feedTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M2',
      clientOrderId: '7101',
      price: 0.4,
      quantity: 10,
      isBid: true,
      payWithDeep: false,
    ))(feedTx);
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M2',
      clientOrderId: '7102',
      price: 0.6,
      quantity: 10,
      isBid: false,
      payWithDeep: false,
    ))(feedTx);
    db.addDeepPricePoint('SUI_DUSDC', 'DEEP_SUI')(feedTx);
    await execute(feedTx, 'feed deep price');

    // Orders on the non-whitelisted pool pay DEEP fees — place and cancel
    // one to prove the DEEP-fee path executes too.
    final orderTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'SUI_DUSDC',
      balanceManagerKey: 'M1',
      clientOrderId: '7001',
      price: 0.5,
      quantity: 5,
      isBid: true,
      payWithDeep: true,
    ))(orderTx);
    db.cancelAllOrders('SUI_DUSDC', 'M1')(orderTx);
    await execute(orderTx, 'DEEP-fee order round trip');

    // Stake and govern. Stake activates in the NEXT epoch, so wait for an
    // epoch boundary (the test localnet runs 60s epochs).
    final stakeTx = Transaction();
    gov.stake('SUI_DUSDC', 'M1', 150)(stakeTx);
    await execute(stakeTx, 'stake');

    final stakedEpoch =
        (await core.getEpoch(readMask: const ['epoch'])).epoch.toInt();
    final deadline = DateTime.now().add(const Duration(seconds: 150));
    while ((await core.getEpoch(readMask: const ['epoch'])).epoch.toInt() <=
        stakedEpoch) {
      if (DateTime.now().isAfter(deadline)) {
        fail('epoch did not advance within 150s — start the localnet with '
            '--epoch-duration-ms 60000 (see tool/localnet/setup.sh)');
      }
      await Future.delayed(const Duration(seconds: 5));
    }

    final proposalTx = Transaction();
    gov.submitProposal(const ProposalParams(
      poolKey: 'SUI_DUSDC',
      balanceManagerKey: 'M1',
      takerFee: 0.0008,
      makerFee: 0.0004,
      stakeRequired: 100,
    ))(proposalTx);
    await execute(proposalTx, 'submit proposal');

    // Voting requires the proposal id — proposals are keyed by the
    // proposer's balance manager id.
    final voteTx = Transaction();
    gov.vote('SUI_DUSDC', 'M1', m1)(voteTx);
    await execute(voteTx, 'vote');

    final unstakeTx = Transaction();
    gov.unstake('SUI_DUSDC', 'M1')(unstakeTx);
    await execute(unstakeTx, 'unstake');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('reverse swap: base → quote against the live book', () async {
    final db = DeepBookContract(config);
    await resetBooks();

    // Resting bid provides the quote-side liquidity for a base sale.
    final restTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M1',
      clientOrderId: '10001',
      price: 0.4,
      quantity: 20,
      isBid: true,
      payWithDeep: false,
    ))(restTx);
    await execute(restTx, 'resting bid');

    final swapTx = Transaction();
    final result = db.swapExactBaseForQuote(const SwapParams(
      poolKey: 'DEEP_SUI',
      amount: 10, // DEEP in
      deepAmount: 0,
      minOut: 3, // ≈4 SUI at 0.4, allow slack
    ))(swapTx);
    swapTx
        .transferObjects([result[0], result[1], result[2]], admin.getAddress());
    await execute(swapTx, 'swap base → quote');

    final cancelTx = Transaction();
    db.cancelAllOrders('DEEP_SUI', 'M1')(cancelTx);
    await execute(cancelTx, 'cancel rest');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('deposit/withdraw caps really move funds', () async {
    final bm = BalanceManagerContract(config);

    // Mint both caps in one transaction, then identify each by object type.
    final mintTx = Transaction();
    final depositCap = bm.mintDepositCap('M1')(mintTx);
    final withdrawCap = bm.mintWithdrawalCap('M1')(mintTx);
    mintTx.transferObjects([depositCap, withdrawCap], admin.getAddress());
    final minted = await core.signAndExecuteTransaction(admin, mintTx);
    expect(minted.effects.status.success, isTrue,
        reason: minted.effects.status.error.description);
    await core.waitForTransaction(minted.digest,
        timeout: const Duration(minutes: 3));

    String? depositCapId, withdrawCapId;
    for (final changed in minted.effects.changedObjects
        .where((o) => o.idOperation.name == 'CREATED')) {
      final object = await core.getObject(changed.objectId,
          readMask: const ['object_id', 'object_type']);
      if (object.objectType.endsWith('::DepositCap')) {
        depositCapId = changed.objectId;
      } else if (object.objectType.endsWith('::WithdrawCap')) {
        withdrawCapId = changed.objectId;
      }
    }
    expect(depositCapId, isNotNull);
    expect(withdrawCapId, isNotNull);

    final capConfig = baseConfig(
      pools: {
        'DEEP_SUI':
            Pool(address: deepSuiPoolId, baseCoin: 'DEEP', quoteCoin: 'SUI'),
      },
      managers: {
        'M1': BalanceManager(
            address: m1, depositCap: depositCapId, withdrawCap: withdrawCapId),
      },
    );
    final capBm = BalanceManagerContract(capConfig);
    final capClient = DeepBookClient(
      client: core,
      network: 'localnet',
      address: admin.getAddress(),
      packageIds: DeepbookPackageIds(
        deepbookPackageId: pkg,
        registryId: ids['registryId'] as String,
        deepTreasuryId: ids['deepTreasuryId'] as String,
      ),
      coins: coins,
      balanceManagers: {
        'M1': BalanceManager(
            address: m1, depositCap: depositCapId, withdrawCap: withdrawCapId),
      },
    );

    final before = await capClient.checkManagerBalance('M1', 'DUSDC');
    final depositTx = Transaction();
    capBm.depositWithCap('M1', 'DUSDC', 25)(depositTx);
    await execute(depositTx, 'deposit with cap');
    final afterDeposit = await capClient.checkManagerBalance('M1', 'DUSDC');
    expect(afterDeposit.balance - before.balance, closeTo(25, 1e-6));

    final withdrawTx = Transaction();
    final coin = capBm.withdrawWithCap('M1', 'DUSDC', 25)(withdrawTx);
    withdrawTx.transferObjects([coin], admin.getAddress());
    await execute(withdrawTx, 'withdraw with cap');
    final afterWithdraw = await capClient.checkManagerBalance('M1', 'DUSDC');
    expect(afterWithdraw.balance, closeTo(before.balance, 1e-6));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('order type variants really execute (IOC, FOK, post-only)', () async {
    final db = DeepBookContract(config);
    await resetBooks();

    // Resting ask for the IOC/FOK takers to hit.
    final restTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M1',
      clientOrderId: '11001',
      price: 0.5,
      quantity: 30,
      isBid: false,
      payWithDeep: false,
    ))(restTx);
    await execute(restTx, 'resting ask');

    // IOC: fills what it can, never rests.
    final iocTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M2',
      clientOrderId: '11002',
      price: 0.5,
      quantity: 10,
      isBid: true,
      orderType: OrderType.immediateOrCancel,
      payWithDeep: false,
    ))(iocTx);
    await execute(iocTx, 'IOC buy');
    expect(await client.accountOpenOrders('DEEP_SUI', 'M2'), isEmpty);

    // FOK: fully fillable, so it succeeds.
    final fokTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M2',
      clientOrderId: '11003',
      price: 0.5,
      quantity: 10,
      isBid: true,
      orderType: OrderType.fillOrKill,
      payWithDeep: false,
    ))(fokTx);
    await execute(fokTx, 'FOK buy');

    // POST_ONLY away from the book: rests without crossing.
    final postTx = Transaction();
    db.placeLimitOrder(const PlaceLimitOrderParams(
      poolKey: 'DEEP_SUI',
      balanceManagerKey: 'M2',
      clientOrderId: '11004',
      price: 0.1,
      quantity: 10,
      isBid: true,
      orderType: OrderType.postOnly,
      payWithDeep: false,
    ))(postTx);
    await execute(postTx, 'POST_ONLY bid');
    expect(await client.accountOpenOrders('DEEP_SUI', 'M2'), hasLength(1));

    final cleanTx = Transaction();
    db.cancelAllOrders('DEEP_SUI', 'M1')(cleanTx);
    db.cancelAllOrders('DEEP_SUI', 'M2')(cleanTx);
    await execute(cleanTx, 'cleanup');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
