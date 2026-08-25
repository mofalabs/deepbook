import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart' hide Coin;
import 'package:bcs/bcs.dart' show Bcs, hexDecode;
import 'package:sui/grpc/proto/sui/rpc/v2/executed_transaction.pb.dart'
    show ExecutedTransaction;
import 'package:deepbook/deepbook.dart';

/// REAL margin-trading execution on localnet.
///
/// The localnet carries the full vendored dependency chain (wormhole → pyth
/// → deepbook → deepbook_margin, deployed by tool/localnet/setup.sh), with a
/// patched pyth exposing `new_test_price_info_object` so oracle prices can
/// be minted without VAA machinery. This suite bootstraps the entire margin
/// stack (pyth config, pool registration, margin pools, liquidity) and then
/// actually executes the borrower lifecycle: create manager → deposit →
/// borrow → repay → withdraw, with real risk checks against our oracle
/// prices.
///
/// Run with: flutter test test/margin_localnet_test.dart
void main() async {
  final idsFile = File('tool/localnet/localnet_ids.json');
  if (!idsFile.existsSync()) {
    test('margin localnet suite', () {
      markTestSkipped('run tool/localnet/setup.sh first');
    });
    return;
  }
  final ids = jsonDecode(idsFile.readAsStringSync()) as Map<String, dynamic>;
  final required = [
    'marginPackageId',
    'marginRegistryId',
    'marginAdminCap',
    'pythPackageId',
    'tokenPackageId',
    'deepCurrencyId',
    'tusdcCurrencyId',
  ];
  if (required.any((k) => (ids[k] as String?)?.isEmpty ?? true)) {
    test('margin localnet suite', () {
      markTestSkipped('margin stack not deployed — run setup.sh');
    });
    return;
  }

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
  if (!reachable) {
    test('margin localnet suite', () {
      markTestSkipped('localnet not reachable');
    });
    return;
  }

  final pkg = ids['deepbookPackageId'] as String;
  final tokenPkg = ids['tokenPackageId'] as String;
  final tusdcPkg = ids['tusdcPackageId'] as String;
  final pythPkg = ids['pythPackageId'] as String;

  const deepFeed =
      '0x1111111111111111111111111111111111111111111111111111111111111111';
  const tusdcFeed =
      '0x2222222222222222222222222222222222222222222222222222222222222222';

  Future<ExecutedTransaction> execute(Transaction tx, String what) async {
    final executed = await core.signAndExecuteTransaction(admin, tx);
    expect(executed.effects.status.success, isTrue,
        reason: '$what: ${executed.effects.status.error.description}');
    // A busy localnet can lag well past the 60s default.
    await core.waitForTransaction(executed.digest,
        timeout: const Duration(minutes: 3));
    return executed;
  }

  List<String> createdIds(ExecutedTransaction executed) =>
      executed.effects.changedObjects
          .where((o) => o.idOperation.name == 'CREATED')
          .map((o) => o.objectId)
          .toList();

  Future<String> createdOfType(
      ExecutedTransaction executed, String typeSuffix) async {
    for (final id in createdIds(executed)) {
      try {
        final object = await core
            .getObject(id, readMask: const ['object_id', 'object_type']);
        if (object.objectType.split('<').first.endsWith(typeSuffix)) {
          return id;
        }
      } on StateError {
        // Created-then-wrapped objects (e.g. dynamic-field children) are not
        // individually fetchable — skip them.
      }
    }
    fail('no created object of type $typeSuffix');
  }

  // Mints a shared test PriceInfoObject via the patched pyth and returns its
  // id. [price] is expressed with exponent -8.
  Future<String> mintPriceObject(String feedHex, BigInt priceMag) async {
    final tx = Transaction();
    final nowSecs = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    tx.moveCall(
      '$pythPkg::price_info::new_test_price_info_object',
      arguments: [
        tx.pure('vector<u8>', hexDecode(feedHex.substring(2))),
        tx.pure('u64', priceMag),
        tx.pure('bool', false),
        tx.pure('u64', priceMag ~/ BigInt.from(10000)), // conf: 1 bps
        tx.pure('u64', 8),
        tx.pure('bool', true), // expo -8
        tx.pure('u64', nowSecs),
      ],
    );
    final executed = await execute(tx, 'mint price object $feedHex');
    final created = createdIds(executed);
    expect(created, hasLength(1));
    return created.first;
  }

  late final String deepPriceObject;
  late final String tusdcPriceObject;
  late final String poolId;
  late final String maintainerCap;
  late final String deepPoolCap;
  late final String tusdcPoolCap;
  late final String deepMarginPoolId;
  late final String tusdcMarginPoolId;
  late final String managerId;
  late final DeepBookConfig config;
  late final Map<String, Coin> coins;

  DeepBookConfig makeConfig({
    PoolMap pools = const {},
    MarginPoolMap marginPools = const {},
    Map<String, MarginManager> marginManagers = const {},
  }) =>
      DeepBookConfig(
        network: 'localnet',
        address: admin.getAddress(),
        adminCap: ids['adminCap'] as String,
        marginAdminCap: ids['marginAdminCap'] as String,
        packageIds: DeepbookPackageIds(
          deepbookPackageId: pkg,
          registryId: ids['registryId'] as String,
          deepTreasuryId: ids['deepTreasuryId'] as String,
          marginPackageId: ids['marginPackageId'] as String,
          marginV1: ids['marginPackageId'] as String,
          marginRegistryId: ids['marginRegistryId'] as String,
          liquidationPackageId: (ids['liquidationPackageId'] ?? '') as String,
        ),
        coins: coins,
        pools: pools,
        marginPools: marginPools,
        marginManagers: marginManagers,
      );

  setUpAll(() async {
    // Oracle prices: DEEP $2.00, DUSDC $1.00 (expo -8).
    deepPriceObject = await mintPriceObject(deepFeed, BigInt.from(200000000));
    tusdcPriceObject = await mintPriceObject(tusdcFeed, BigInt.from(100000000));

    coins = {
      'DEEP': Coin(
        address: tokenPkg,
        type: '$tokenPkg::deep::DEEP',
        scalar: 1000000,
        feed: deepFeed,
        currencyId: ids['deepCurrencyId'] as String,
        priceInfoObjectId: deepPriceObject,
      ),
      'TUSDC': Coin(
        address: tusdcPkg,
        type: '$tusdcPkg::tusdc::TUSDC',
        scalar: 1000000,
        feed: tusdcFeed,
        currencyId: ids['tusdcCurrencyId'] as String,
        priceInfoObjectId: tusdcPriceObject,
      ),
      'SUI': const Coin(
        address: '0x2',
        type:
            '0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI',
        scalar: 1000000000,
      ),
    };

    // Fresh DEEP/DUSDC deepbook pool.
    final bootstrap = makeConfig();
    final probe = QueryContext(core: core, config: bootstrap);
    Future<String?> resolvePool() async {
      final tx = Transaction();
      DeepBookContract(makeConfig(pools: {
        'X': Pool(address: '0x0', baseCoin: 'DEEP', quoteCoin: 'TUSDC'),
      }));
      // direct builder call to avoid config-pool requirements
      tx.moveCall(
        '$pkg::pool::get_pool_id_by_asset',
        arguments: [tx.object(ids['registryId'] as String)],
        typeArguments: [coins['DEEP']!.type, coins['TUSDC']!.type],
      );
      try {
        return SuiBcs.Address.parse(await probe.simulateReturn(tx));
      } on DeepBookError {
        return null;
      }
    }

    final stale = await resolvePool();
    if (stale != null) {
      final unregTx = Transaction();
      DeepBookAdminContract(makeConfig(pools: {
        'STALE': Pool(address: stale, baseCoin: 'DEEP', quoteCoin: 'TUSDC'),
      })).unregisterPoolAdmin('STALE')(unregTx);
      await execute(unregTx, 'unregister stale pool');
    }
    final createTx = Transaction();
    DeepBookAdminContract(bootstrap)
        .createPoolAdmin(const CreatePoolAdminParams(
      baseCoinKey: 'DEEP',
      quoteCoinKey: 'TUSDC',
      tickSize: 0.001,
      lotSize: 1,
      minSize: 1,
      whitelisted: false,
      stablePool: false,
    ))(createTx);
    await execute(createTx, 'create DEEP/DUSDC pool');
    poolId = (await resolvePool())!;

    final pools = {
      'DEEP_TUSDC': Pool(address: poolId, baseCoin: 'DEEP', quoteCoin: 'TUSDC'),
    };
    final adminConfig = makeConfig(pools: pools);
    final marginAdmin = MarginAdminContract(adminConfig);

    // Pyth config first (margin pools & pool registration need it). The
    // registry is a shared singleton, so drop any config left by a previous
    // run before adding ours.
    // The config contents are identical on every run, so an
    // already-present config (EFieldAlreadyExists) is equivalent to success.
    try {
      final setupTx = Transaction();
      final pythConfig = marginAdmin.newPythConfig(
        const [
          (coinKey: 'DEEP', maxConfBps: 100, maxEwmaDifferenceBps: 10000),
          (coinKey: 'TUSDC', maxConfBps: 100, maxEwmaDifferenceBps: 10000),
        ],
        300,
      )(setupTx);
      marginAdmin.addConfig(pythConfig)(setupTx);
      await execute(setupTx, 'pyth config');
    } on StateError catch (e) {
      if (!e.toString().contains('dynamic_field')) rethrow;
    }

    // Maintainer: protocol configs + the two margin pools.
    final stateFile0 = File('tool/localnet/margin_state.json');
    Map<String, dynamic> state0 = stateFile0.existsSync()
        ? jsonDecode(stateFile0.readAsStringSync()) as Map<String, dynamic>
        : {};
    if (state0['marginPackageId'] == ids['marginPackageId'] &&
        state0['maintainerCap'] != null) {
      maintainerCap = state0['maintainerCap'] as String;
    } else {
      final capTx = Transaction();
      final cap = marginAdmin.mintMaintainerCap()(capTx);
      capTx.transferObjects([cap], admin.getAddress());
      final capExec = await execute(capTx, 'mint maintainer cap');
      maintainerCap = createdIds(capExec).first;
      state0['maintainerCap'] = maintainerCap;
      state0['marginPackageId'] = ids['marginPackageId'];
      stateFile0.writeAsStringSync(jsonEncode(state0));
    }

    final maintainer = MarginMaintainerContract(DeepBookConfig(
      network: 'localnet',
      address: admin.getAddress(),
      marginMaintainerCap: maintainerCap,
      packageIds: DeepbookPackageIds(
        deepbookPackageId: pkg,
        registryId: ids['registryId'] as String,
        marginPackageId: ids['marginPackageId'] as String,
        marginV1: ids['marginPackageId'] as String,
        marginRegistryId: ids['marginRegistryId'] as String,
      ),
      coins: coins,
      pools: pools,
    ));

    DeepBookConfig config0() => makeConfig(pools: pools);

    // Margin pools are one-per-asset in the registry — create on first run,
    // then reuse via the cached state file.
    final stateFile = File('tool/localnet/margin_state.json');
    Map<String, dynamic> state = {};
    if (stateFile.existsSync()) {
      state = jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
      if (state['marginPackageId'] != ids['marginPackageId']) state = {};
    }

    Future<(String, String)> recoverMarginPool(String coinKey) async {
      // The pool exists on-chain from a previous run: resolve its id from
      // the registry and find our matching MarginPoolCap.
      final ctx = QueryContext(core: core, config: config0());
      final idTx = Transaction();
      idTx.moveCall(
        '${ids['marginPackageId']}::margin_registry::get_margin_pool_id',
        typeArguments: [coins[coinKey]!.type],
        arguments: [idTx.object(ids['marginRegistryId'] as String)],
      );
      final poolId = SuiBcs.Address.parse(await ctx.simulateReturn(idTx));
      final caps = await core.listOwnedObjects(
        admin.getAddress(),
        objectType: '${ids['marginPackageId']}::margin_registry::MarginPoolCap',
        readMask: const ['object_id', 'contents'],
      );
      for (final cap in caps.objects) {
        final bytes = cap.contents.value;
        if (bytes.length >= 64) {
          final capPool =
              '0x${bytes.sublist(32, 64).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
          if (capPool == poolId) return (poolId, cap.objectId);
        }
      }
      fail('MarginPoolCap for $coinKey pool not found among owned objects');
    }

    Future<(String, String)> createMarginPool(String coinKey) async {
      if (state['${coinKey}_pool'] != null) {
        return (
          state['${coinKey}_pool'] as String,
          state['${coinKey}_cap'] as String
        );
      }
      final tx = Transaction();
      final protocolConfig = maintainer.newProtocolConfig(
        coinKey,
        const MarginPoolConfigParams(
          supplyCap: 1000000,
          maxUtilizationRate: 0.8,
          protocolSpread: 0.05,
          minBorrow: 1,
        ),
        const InterestConfigParams(
          baseRate: 0.01,
          baseSlope: 0.1,
          optimalUtilization: 0.8,
          excessSlope: 2.0,
        ),
      )(tx);
      maintainer.createMarginPool(coinKey, protocolConfig)(tx);
      final ExecutedTransaction executed;
      try {
        executed = await execute(tx, 'create $coinKey margin pool');
      } on StateError catch (e) {
        if (e.toString().contains('register_margin_pool')) {
          final recovered = await recoverMarginPool(coinKey);
          state['${coinKey}_pool'] = recovered.$1;
          state['${coinKey}_cap'] = recovered.$2;
          return recovered;
        }
        rethrow;
      }
      final poolCap = await createdOfType(executed, '::MarginPoolCap');
      final marginPool = await createdOfType(executed, '::MarginPool');
      state['${coinKey}_pool'] = marginPool;
      state['${coinKey}_cap'] = poolCap;
      return (marginPool, poolCap);
    }

    (deepMarginPoolId, deepPoolCap) = await createMarginPool('DEEP');
    (tusdcMarginPoolId, tusdcPoolCap) = await createMarginPool('TUSDC');
    state['marginPackageId'] = ids['marginPackageId'];
    stateFile.writeAsStringSync(jsonEncode(state));

    final marginPools = {
      'DEEP': MarginPool(address: deepMarginPoolId, type: coins['DEEP']!.type),
      'TUSDC':
          MarginPool(address: tusdcMarginPoolId, type: coins['TUSDC']!.type),
    };
    config = makeConfig(pools: pools, marginPools: marginPools);

    // Allow both margin pools to lend to the deepbook pool, then add
    // DUSDC liquidity so borrowQuote has something to lend.
    final maintainer2 = MarginMaintainerContract(DeepBookConfig(
      network: 'localnet',
      address: admin.getAddress(),
      marginMaintainerCap: maintainerCap,
      packageIds: DeepbookPackageIds(
        deepbookPackageId: pkg,
        registryId: ids['registryId'] as String,
        marginPackageId: ids['marginPackageId'] as String,
        marginV1: ids['marginPackageId'] as String,
        marginRegistryId: ids['marginRegistryId'] as String,
      ),
      coins: coins,
      pools: pools,
      marginPools: marginPools,
    ));
    // Register the deepbook pool for margin (requires both margin pools),
    // then allow them to lend to it.
    final registerTx = Transaction();
    final marginAdmin2 = MarginAdminContract(config);
    final poolConfig = marginAdmin2.newPoolConfig(
      'DEEP_TUSDC',
      const PoolConfigParams(
        minWithdrawRiskRatio: 2.0,
        minBorrowRiskRatio: 1.5,
        liquidationRiskRatio: 1.1,
        targetLiquidationRiskRatio: 1.25,
        userLiquidationReward: 0.05,
        poolLiquidationReward: 0.05,
      ),
    )(registerTx);
    marginAdmin2.registerDeepbookPool('DEEP_TUSDC', poolConfig)(registerTx);
    marginAdmin2.enableDeepbookPool('DEEP_TUSDC')(registerTx);
    await execute(registerTx, 'register + enable deepbook pool for margin');

    // Authorize the MarginApp in the CORE deepbook registry (idempotent:
    // an already-authorized app trips a dynamic-field-exists abort).
    try {
      final authTx = Transaction();
      DeepBookAdminContract(config).authorizeMarginApp()(authTx);
      await execute(authTx, 'authorize MarginApp');
    } on StateError catch (e) {
      if (!e.toString().contains('dynamic_field')) rethrow;
    }

    final enableTx = Transaction();
    maintainer2.enableDeepbookPoolForLoan(
        'DEEP_TUSDC', 'DEEP', deepPoolCap)(enableTx);
    maintainer2.enableDeepbookPoolForLoan(
        'DEEP_TUSDC', 'TUSDC', tusdcPoolCap)(enableTx);
    await execute(enableTx, 'enable pools for loan');

    final marginPoolContract = MarginPoolContract(config);
    final supplyTx = Transaction();
    final supplierCap = marginPoolContract.mintSupplierCap()(supplyTx);
    supplyTx.transferObjects([supplierCap], admin.getAddress());
    final supplierExec = await execute(supplyTx, 'mint supplier cap');
    final supplierCapId = createdIds(supplierExec).first;

    final supply2Tx = Transaction();
    marginPoolContract.supplyToMarginPool(
        'TUSDC', supplierCapId, 500)(supply2Tx);
    await execute(supply2Tx, 'supply TUSDC liquidity');

    // Margin manager.
    final managerTx = Transaction();
    MarginManagerContract(config).newMarginManager('DEEP_TUSDC')(managerTx);
    final managerExec = await execute(managerTx, 'create margin manager');
    managerId = await createdOfType(managerExec, '::MarginManager');
  });

  test('margin lifecycle: deposit → borrow → state → repay → withdraw',
      () async {
    final fullConfig = makeConfig(
      pools: {
        'DEEP_TUSDC':
            Pool(address: poolId, baseCoin: 'DEEP', quoteCoin: 'TUSDC'),
      },
      marginPools: {
        'DEEP':
            MarginPool(address: deepMarginPoolId, type: coins['DEEP']!.type),
        'TUSDC':
            MarginPool(address: tusdcMarginPoolId, type: coins['TUSDC']!.type),
      },
      marginManagers: {
        'MM': MarginManager(address: managerId, poolKey: 'DEEP_TUSDC'),
      },
    );
    final manager = MarginManagerContract(fullConfig);
    final ctx = QueryContext(core: core, config: fullConfig);
    final managerQueries = MarginManagerQueries(ctx);
    final poolQueries = MarginPoolQueries(ctx);

    // Deposit 100 DEEP (worth $200 at our oracle price).
    final depositTx = Transaction();
    manager.depositBase(const DepositParams(managerKey: 'MM', amount: 100))(
        depositTx);
    await execute(depositTx, 'deposit 100 DEEP');

    // Borrow 20 DUSDC ($20) — comfortably above min borrow risk ratio.
    final borrowTx = Transaction();
    manager.borrowQuote('MM', 20)(borrowTx);
    await execute(borrowTx, 'borrow 20 TUSDC');

    // Real state reads against our oracle prices.
    final debts = await managerQueries.getMarginManagerDebts('MM');
    expect(double.parse(debts.quoteDebt), greaterThanOrEqualTo(20));
    expect(double.parse(debts.baseDebt), 0);

    final borrowed = await poolQueries.getMarginPoolTotalBorrow('TUSDC');
    expect(double.parse(borrowed), greaterThanOrEqualTo(20));

    // Repay in full and withdraw the collateral back to the wallet.
    final repayTx = Transaction();
    manager.repayQuote('MM')(repayTx);
    await execute(repayTx, 'repay all TUSDC');

    // A debt-free manager has no active margin pool link, so the on-chain
    // `calculate_debts` (and thus getMarginManagerDebts) aborts by design —
    // assert debt-free state via the share counters instead.
    final sharesAfter =
        await managerQueries.getMarginManagerBorrowedShares('MM');
    // Repaying in full can leave sub-unit dust shares behind.
    expect(double.parse(sharesAfter.baseShares), lessThan(2));
    expect(double.parse(sharesAfter.quoteShares), lessThan(2));

    // Dust debt left by the repay keeps a withdrawal risk-ratio floor, so
    // take most of the collateral back rather than all of it.
    final withdrawTx = Transaction();
    final withdrawn = manager.withdrawBase('MM', 90)(withdrawTx);
    withdrawTx.transferObjects([withdrawn], admin.getAddress());
    await execute(withdrawTx, 'withdraw 90 DEEP');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('leveraged trading via pool proxy: place, read book, cancel', () async {
    final fullConfig = makeConfig(
      pools: {
        'DEEP_TUSDC':
            Pool(address: poolId, baseCoin: 'DEEP', quoteCoin: 'TUSDC'),
      },
      marginPools: {
        'DEEP':
            MarginPool(address: deepMarginPoolId, type: coins['DEEP']!.type),
        'TUSDC':
            MarginPool(address: tusdcMarginPoolId, type: coins['TUSDC']!.type),
      },
      marginManagers: {
        'MM': MarginManager(address: managerId, poolKey: 'DEEP_TUSDC'),
      },
    );
    final manager = MarginManagerContract(fullConfig);
    final proxy = PoolProxyContract(fullConfig);
    final ctx = QueryContext(core: core, config: fullConfig);

    // Escrow for a bid comes from the manager's quote balance.
    final fundTx = Transaction();
    manager.depositQuote(const DepositParams(managerKey: 'MM', amount: 50))(
        fundTx);
    await execute(fundTx, 'deposit 50 TUSDC');

    // Margin order paths read a registry price snapshot (EPriceNotInitialized
    // otherwise), so publish one from the oracle first.
    final priceTx = Transaction();
    proxy.updateCurrentPrice('DEEP_TUSDC')(priceTx);
    await execute(priceTx, 'update current price');

    final orderTx = Transaction();
    proxy.placeLimitOrder(const PlaceMarginLimitOrderParams(
      poolKey: 'DEEP_TUSDC',
      marginManagerKey: 'MM',
      clientOrderId: '8001',
      price: 0.5,
      quantity: 5,
      isBid: true,
      payWithDeep: false,
    ))(orderTx);
    await execute(orderTx, 'proxy limit bid');

    // Read the manager's open orders straight off the book.
    final openTx = Transaction();
    manager.accountOpenOrders('DEEP_TUSDC', managerId)(openTx);
    final openBytes = await ctx.simulateReturn(openTx);
    final orderIds = Bcs.struct('VecSet', {'contents': Bcs.vector(Bcs.u128())})
        .parse(openBytes)['contents'] as List;
    expect(orderIds, hasLength(1));

    final cancelTx = Transaction();
    proxy.cancelAllOrders('MM')(cancelTx);
    await execute(cancelTx, 'proxy cancel all');

    final afterTx = Transaction();
    manager.accountOpenOrders('DEEP_TUSDC', managerId)(afterTx);
    final afterIds = Bcs.struct('VecSet', {'contents': Bcs.vector(Bcs.u128())})
        .parse(await ctx.simulateReturn(afterTx))['contents'] as List;
    expect(afterIds, isEmpty);

    final withdrawTx = Transaction();
    final coin = manager.withdrawQuote('MM', 50)(withdrawTx);
    withdrawTx.transferObjects([coin], admin.getAddress());
    await execute(withdrawTx, 'withdraw quote');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('TPSL: add conditional order, read it back, cancel', () async {
    final fullConfig = makeConfig(
      pools: {
        'DEEP_TUSDC':
            Pool(address: poolId, baseCoin: 'DEEP', quoteCoin: 'TUSDC'),
      },
      marginPools: {
        'DEEP':
            MarginPool(address: deepMarginPoolId, type: coins['DEEP']!.type),
        'TUSDC':
            MarginPool(address: tusdcMarginPoolId, type: coins['TUSDC']!.type),
      },
      marginManagers: {
        'MM': MarginManager(address: managerId, poolKey: 'DEEP_TUSDC'),
      },
    );
    final tpsl = MarginTPSLContract(fullConfig);
    final ctx = QueryContext(core: core, config: fullConfig);
    final tpslQueries = TPSLQueries(ctx);

    final addTx = Transaction();
    tpsl.addConditionalOrder(const AddConditionalOrderParams(
      marginManagerKey: 'MM',
      conditionalOrderId: '9001',
      triggerBelowPrice: true,
      triggerPrice: 1.0,
      pendingOrder: PendingLimitOrderParams(
        clientOrderId: '9002',
        price: 0.4,
        quantity: 2,
        isBid: true,
      ),
    ))(addTx);
    await execute(addTx, 'add conditional order');

    final ids0 = await tpslQueries.getConditionalOrderIds('MM');
    expect(ids0, isNotEmpty);

    final cancelTx = Transaction();
    tpsl.cancelConditionalOrder('MM', ids0.first.toString())(cancelTx);
    await execute(cancelTx, 'cancel conditional order');

    final ids1 = await tpslQueries.getConditionalOrderIds('MM');
    expect(ids1, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('liquidation: crash the oracle price and really liquidate', () async {
    // Fresh borrower so this test owns its risk position.
    final bootstrap = makeConfig(pools: {
      'DEEP_TUSDC': Pool(address: poolId, baseCoin: 'DEEP', quoteCoin: 'TUSDC'),
    });
    final managerTx = Transaction();
    MarginManagerContract(bootstrap).newMarginManager('DEEP_TUSDC')(managerTx);
    final managerExec = await execute(managerTx, 'create borrower manager');
    final borrowerId = await createdOfType(managerExec, '::MarginManager');

    final fullConfig = makeConfig(
      pools: {
        'DEEP_TUSDC':
            Pool(address: poolId, baseCoin: 'DEEP', quoteCoin: 'TUSDC'),
      },
      marginPools: {
        'DEEP':
            MarginPool(address: deepMarginPoolId, type: coins['DEEP']!.type),
        'TUSDC':
            MarginPool(address: tusdcMarginPoolId, type: coins['TUSDC']!.type),
      },
      marginManagers: {
        'B': MarginManager(address: borrowerId, poolKey: 'DEEP_TUSDC'),
      },
    );
    final manager = MarginManagerContract(fullConfig);
    final managerQueries =
        MarginManagerQueries(QueryContext(core: core, config: fullConfig));

    // Deposit $200 of DEEP collateral and borrow $120 of TUSDC.
    final fundTx = Transaction();
    manager
        .depositBase(const DepositParams(managerKey: 'B', amount: 100))(fundTx);
    await execute(fundTx, 'deposit collateral');
    final borrowTx = Transaction();
    manager.borrowQuote('B', 120)(borrowTx);
    await execute(borrowTx, 'borrow 120 TUSDC');

    // Crash DEEP from \$2.00 to \$0.10 → risk ratio ≈ 1.08 < 1.1.
    final nowSecs = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    final crashTx = Transaction();
    crashTx.moveCall(
      '$pythPkg::price_info::update_test_price_info_object',
      arguments: [
        crashTx.object(deepPriceObject),
        crashTx.pure('u64', BigInt.from(10000000)),
        crashTx.pure('bool', false),
        crashTx.pure('u64', BigInt.from(1000)),
        crashTx.pure('u64', 8),
        crashTx.pure('bool', true),
        crashTx.pure('u64', nowSecs),
      ],
    );
    await execute(crashTx, 'crash DEEP price');

    // Liquidation vault: create, then fund it with TUSDC to repay the debt.
    final liq = MarginLiquidationsContract(fullConfig);
    final vaultTx = Transaction();
    liq.createLiquidationVault(ids['liquidationAdminCap'] as String)(vaultTx);
    final vaultExec = await execute(vaultTx, 'create liquidation vault');
    final vaultId = await createdOfType(vaultExec, '::LiquidationVault');
    final vaultFundTx = Transaction();
    liq.deposit(vaultId, ids['liquidationAdminCap'] as String, 'TUSDC', 200)(
        vaultFundTx);
    await execute(vaultFundTx, 'fund vault');

    // REAL liquidation.
    final sharesBefore =
        await managerQueries.getMarginManagerBorrowedShares('B');
    expect(double.parse(sharesBefore.quoteShares), greaterThan(0));

    final liquidateTx = Transaction();
    liq.liquidateQuote(vaultId, borrowerId, 'DEEP_TUSDC')(liquidateTx);
    await execute(liquidateTx, 'liquidate');

    final sharesAfter =
        await managerQueries.getMarginManagerBorrowedShares('B');
    expect(double.parse(sharesAfter.quoteShares),
        lessThan(double.parse(sharesBefore.quoteShares)));

    // Restore the DEEP price for any later suites.
    final restoreTx = Transaction();
    restoreTx.moveCall(
      '$pythPkg::price_info::update_test_price_info_object',
      arguments: [
        restoreTx.object(deepPriceObject),
        restoreTx.pure('u64', BigInt.from(200000000)),
        restoreTx.pure('bool', false),
        restoreTx.pure('u64', BigInt.from(20000)),
        restoreTx.pure('u64', 8),
        restoreTx.pure('bool', true),
        restoreTx.pure(
            'u64', (DateTime.now().millisecondsSinceEpoch / 1000).floor()),
      ],
    );
    await execute(restoreTx, 'restore DEEP price');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
