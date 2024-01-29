
import 'dart:convert';

import 'package:deepbook/client.dart';
import 'package:deepbook/types/index.dart';
import 'package:deepbook/utils/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart';

import 'setup.dart';

const DEPOSIT_AMOUNT = 100;
const LIMIT_ORDER_PRICE = 1;
const LIMIT_ORDER_QUANTITY = 1 * DEFAULT_LOT_SIZE;

void main() {

  group('Interacting with the pool', () {
    
    late TestToolbox toolbox;
	  // late PoolSummary pool;
	  // String? accountCapId;
	  // String? accountCapId2;

	  final baseAsset = "0x3a678c27b2df65b466be4539629e2dba73e013e6454bc7b478285a3fd2c6211e::test::TEST";
	  final quoteAsset = NORMALIZED_SUI_COIN_TYPE;
    late PoolSummary pool = PoolSummary(
      "0x997c4bc9ccdb6a4e54578ec77f486c168b22cf171dd57fc34e3f26ac57711b9a",
      baseAsset,
      quoteAsset
    );
    String? accountCapId = "0xeff8d76415eafa502e5f30c0d1b68874a973620d855f326f98c62c98cd9df304";
	  String? accountCapId2 = "0x65b89e43465147f56bb548e813f336e1346d1a47fa8d83977555d84cf290d0b4";

    setUpAll(() async {
      toolbox = await setupSuiClient();
    });

    test('test creating a pool', () async {
      pool = await setupPool(toolbox);
      expect(pool.poolId.isNotEmpty, true);
      final deepbook = DeepBookClient(client: toolbox.client);
      final pools = await deepbook.getAllPools(descendingOrder: true);
      expect(pools.data.where((p) => p.poolId == pool.poolId).isNotEmpty, true);
    });

    test('test creating a custodian account', () async {
      accountCapId = await setupDeepbookAccount(toolbox);
      expect(accountCapId != null, true);
      accountCapId2 = await setupDeepbookAccount(toolbox);
      expect(accountCapId2 != null, true);
    });

    test('test depositing quote asset with account 1', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId);
      final txb = await deepbook.deposit(poolId: pool.poolId, quantity: DEPOSIT_AMOUNT);
      await executeTransactionBlock(toolbox, txb);
      final resp = await deepbook.getUserPosition(poolId: pool.poolId);
      expect(resp.availableQuoteAmount, DEPOSIT_AMOUNT);
    });

    test('test depositing base asset with account 2', () async {
      final resp = await toolbox.client.getCoins(
        toolbox.address(),
        coinType: pool.baseAsset,
      );
      final baseCoin = resp.data[0].coinObjectId;

      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId2);
      final txb = await deepbook.deposit(poolId: pool.poolId, coinId: baseCoin, quantity: DEPOSIT_AMOUNT);
      await executeTransactionBlock(toolbox, txb);
      final userPosition = await deepbook.getUserPosition(poolId: pool.poolId);
      expect(userPosition.availableBaseAmount, DEPOSIT_AMOUNT);
    });

    test('test withdrawing quote asset with account 1', () async {
      expect(accountCapId != null, true);
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId, currentAddress: toolbox.address());
      final txb = await deepbook.withdraw(pool.poolId, DEPOSIT_AMOUNT, AssetType.quote);
      await executeTransactionBlock(toolbox, txb);
      final resp = await deepbook.getUserPosition(poolId: pool.poolId);
      expect(resp.availableQuoteAmount, 0);
    });

    test('test placing limit order with account 1', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId);
      const depositAmount = DEPOSIT_AMOUNT;
      final depositTxb = await deepbook.deposit(poolId: pool.poolId, quantity: depositAmount);
      await executeTransactionBlock(toolbox, depositTxb);
      final position = await deepbook.getUserPosition(poolId: pool.poolId);
      expect(position.availableQuoteAmount, depositAmount);

      const totalLocked = LIMIT_ORDER_PRICE * LIMIT_ORDER_QUANTITY;
      final txb = await deepbook.placeLimitOrder(
        poolId: pool.poolId,
        price: LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        quantity: LIMIT_ORDER_QUANTITY,
        orderType: OrderType.bid
      );
      await executeTransactionBlock(toolbox, txb);

      final position2 = await deepbook.getUserPosition(poolId: pool.poolId);
      expect(position2.availableQuoteAmount, depositAmount - totalLocked);
      expect(position2.lockedQuoteAmount, totalLocked);
    });

    test('test listing open orders', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId, currentAddress: toolbox.address());
      final openOrders = await deepbook.listOpenOrders(poolId: pool.poolId);
      expect(openOrders.length, 1);
      final order = openOrders[0];
      expect(order.price, LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE);
      expect(order.originalQuantity, LIMIT_ORDER_QUANTITY);

      final orderStatus = (await deepbook.getOrderStatus(poolId: pool.poolId, orderId: order.orderId))!;
      expect(orderStatus.price, order.price);
    });

    test('test getting market price', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId, currentAddress: toolbox.address());
      final price = await deepbook.getMarketPrice(pool.poolId);
      expect(price.bestBidPrice, LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE);
    });

    test('test getting Level 2 Book status', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId, currentAddress: toolbox.address());
      final status = await deepbook.getLevel2BookStatus(
        poolId: pool.poolId,
        lowerPrice: LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        higherPrice: LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        side: OrderType.bid
      );
      expect(status.length, 1);
      expect(status[0].price, LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE);
      expect(status[0].depth, LIMIT_ORDER_QUANTITY);
    });

    test('test placing market order with Account 2', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId2, currentAddress: toolbox.address());
      final resp = await toolbox.client.getCoins(
        toolbox.address(),
        coinType: pool.baseAsset,
      );
      final baseCoin = resp.data[0].coinObjectId;

      final balanceBefore =(
          await toolbox.client.getBalance(
            toolbox.address(),
            coinType: pool.baseAsset,
          )
        ).totalBalance;

      final txb = await deepbook.placeMarketOrder(
        accountCap: accountCapId2!,
        poolId: pool.poolId,
        quantity: LIMIT_ORDER_QUANTITY,
        orderType: OrderType.ask,
        baseCoin: baseCoin,
      );
      await executeTransactionBlock(toolbox, txb);

      // the limit order should be cleared out after matching with the market order
      final openOrders = await deepbook.listOpenOrders(poolId: pool.poolId);
      expect(openOrders.length, 0);

      final balanceAfter = 
        (
          await toolbox.client.getBalance(
            toolbox.address(),
            coinType: pool.baseAsset,
          )
        ).totalBalance;
      expect(balanceBefore, balanceAfter + BigInt.from(LIMIT_ORDER_QUANTITY));
    });

    test('test cancelling limit order with account 1', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId);
      final txb = await deepbook.placeLimitOrder(
        poolId: pool.poolId,
        price: LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        quantity: LIMIT_ORDER_QUANTITY,
        orderType: OrderType.bid,
      );
      await executeTransactionBlock(toolbox, txb);

      final openOrdersBefore = await deepbook.listOpenOrders(poolId: pool.poolId);
      expect(openOrdersBefore.length, 1);
      final orderId = openOrdersBefore[0].orderId;

      final txbForCancel = await deepbook.cancelOrder(poolId: pool.poolId, orderId: orderId);
      await executeTransactionBlock(toolbox, txbForCancel);

      final openOrdersAfter = await deepbook.listOpenOrders(poolId: pool.poolId);
      expect(openOrdersAfter.length, 0);
    });

    test('Test parsing sui coin id', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId);
      final resp = await toolbox.client.getCoins(
        toolbox.account.getAddress(),
        coinType: pool.baseAsset,
      );
      final baseCoin = resp.data[0].coinObjectId;
      final type = await deepbook.getCoinType(baseCoin);
      expect(type, resp.data[0].coinType);
    });

    test('Test parsing complex coin id', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId);
      final resp = await toolbox.client.getCoins(
        toolbox.address(),
        coinType: pool.baseAsset,
      );
      final baseCoin = resp.data[0].coinObjectId;
      final type = await deepbook.getCoinType(baseCoin);
      expect(type, resp.data[0].coinType);
    });

    test('Test getting level 2 book status, both sides', () async {
      final deepbook1 = DeepBookClient(client: toolbox.client, accountCap: accountCapId);
      final deepbook2 = DeepBookClient(client: toolbox.client, accountCap: accountCapId2);
      final txb1 = await deepbook1.placeLimitOrder(
        poolId: pool.poolId,
        price: LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        quantity: LIMIT_ORDER_QUANTITY,
        orderType: OrderType.bid
      );
      await executeTransactionBlock(toolbox, txb1);
      final txb2 = await deepbook2.placeLimitOrder(
        poolId: pool.poolId,
        price: 2 * LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        quantity: LIMIT_ORDER_QUANTITY,
        orderType: OrderType.ask
      );
      await executeTransactionBlock(toolbox, txb2);
      final txb3 = await deepbook2.placeLimitOrder(
        poolId: pool.poolId,
        price: 3 * LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        quantity: LIMIT_ORDER_QUANTITY,
        orderType: OrderType.ask
      );
      await executeTransactionBlock(toolbox, txb3);
      final status = (await deepbook2.getLevel2BookStatus(
        poolId: pool.poolId,
        lowerPrice: LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        higherPrice: 3 * LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE,
        side: OrderType.both
      )) as List<List<Level2BookStatusPoint>>;
      expect(status.length, 2);
      expect(status[0].length, 1);
      expect(status[1].length, 2);
      expect(status[0][0].price, LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE);
      expect(status[1][0].price, 2 * LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE);
      expect(status[1][1].price, 3 * LIMIT_ORDER_PRICE * DEFAULT_TICK_SIZE);
    });

    test('Test split gas', () async {
      var txb = TransactionBlock();
      
      final gasCoin = txb.splitCoins(txb.gas, [txb.pureInt(1000000000), txb.pureInt(1000000000)]);
      txb.transferObjects([gasCoin[0], gasCoin[1]], txb.pureAddress(toolbox.address()));

      await executeTransactionBlock(toolbox, txb);
    });

    test('Test swap exact base asset for quote asset', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId);

      final balanceBefore =(
          await toolbox.client.getBalance(
            toolbox.address(),
            coinType: pool.baseAsset,
          )
        ).totalBalance;

      debugPrint("balance before: $balanceBefore");

      final resp = await toolbox.client.getCoins(
        toolbox.address(),
        coinType: pool.baseAsset,
      );

      final totalBefore = resp.data.map((e) => int.parse(e.balance)).toList();
      debugPrint("total before: ${jsonEncode(totalBefore)}");
      
      final amount = 50;

      final baseCoin = resp.data.firstWhere((e) => int.parse(e.balance) > amount);
      final coinBalanceBefore = int.parse(baseCoin.balance);
      final baseCoinId = baseCoin.coinObjectId;

      var txb = TransactionBlock();
      final coinInput = txb.splitCoins(txb.object(baseCoinId), [txb.pureInt(amount)]);
      txb = await deepbook.swapExactBaseForQuote(
        poolId: pool.poolId, 
        tokenObjectIn: coinInput,
        amountIn: amount,
        currentAddress: toolbox.address(),
        txb: txb
      );

      await executeTransactionBlock(toolbox, txb);

      final balanceAfter =(
          await toolbox.client.getBalance(
            toolbox.address(),
            coinType: pool.baseAsset,
          )
        ).totalBalance;

      debugPrint("balance after: $balanceAfter");

      final resp2 = await toolbox.client.getCoins(
        toolbox.address(),
        coinType: pool.baseAsset,
      );

      final totalAfter = resp2.data.map((e) => int.parse(e.balance)).toList();
      final coinBalanceAfter = int.parse(resp2.data.firstWhere((e) => e.objectId == baseCoinId).balance);

      debugPrint("total after: ${jsonEncode(totalAfter)}");

      expect(coinBalanceBefore, coinBalanceAfter + amount);
    });

   test('Test swap exact quote asset for base asset', () async {
      final deepbook = DeepBookClient(client: toolbox.client, accountCap: accountCapId2);
      
      final coinsBefore = await toolbox.client.getCoins(
        toolbox.address(),
        coinType: pool.quoteAsset,
      );

      final totalBefore = coinsBefore.data.map((e) => int.parse(e.balance)).toList();
      debugPrint("total before: ${jsonEncode(totalBefore)}");

      final amount = 1000000;

      final quoteCoin = coinsBefore.data.firstWhere((e) => int.parse(e.balance) > amount);
      final quoteCoinId = quoteCoin.objectId;
      final balanceBefore = int.parse(quoteCoin.balance);
      
      var txb = TransactionBlock();

      final coinInput = txb.splitCoins(txb.object(quoteCoinId), [txb.pureInt(amount)]);
      
      txb = await deepbook.swapExactQuoteForBase(
        poolId: pool.poolId, 
        tokenObjectIn: coinInput,
        amountIn: amount,
        currentAddress: toolbox.address(),
        txb: txb
      );

      await executeTransactionBlock(toolbox, txb);

      final coinsAfter = await toolbox.client.getCoins(
        toolbox.address(),
        coinType: pool.quoteAsset,
      );

      final totalAfter = coinsAfter.data.map((e) => int.parse(e.balance)).toList();
      debugPrint("total after: ${jsonEncode(totalAfter)}");

      final balanceAfter = int.parse(coinsAfter.data.firstWhere((e) => e.objectId == quoteCoinId).balance);

      expect(balanceBefore, balanceAfter + amount);

    });

  });

}