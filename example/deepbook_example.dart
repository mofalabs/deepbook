// Reading the order book and composing a trade with the DeepBook V3 SDK.
//
// This package depends on Flutter (through `package:sui`), so `dart run`
// cannot execute this file — call [main] from a Flutter app, or copy the
// body into a widget. For a runnable equivalent against live mainnet data,
// see `test/queries_live_test.dart`.
//
// ignore_for_file: avoid_print

import 'package:sui/sui.dart' hide Coin; // `Coin` also exists in deepbook
import 'package:deepbook/deepbook.dart';

Future<void> main() async {
  final grpc = SuiGrpcClient(network: SuiNetwork.mainnet);
  final client = DeepBookClient(
    client: grpc.core as GrpcCoreClient,
    network: 'mainnet',
    // Any address works for read-only queries; use your own to trade.
    address: '0x2',
    balanceManagers: {
      // Register your BalanceManager under a key to trade with it.
      // 'MAIN': BalanceManager(address: '0x...'),
    },
  );

  // --- Read the SUI/USDC book. ---
  final mid = await client.midPrice('SUI_USDC');
  print('SUI_USDC mid price: $mid');

  final book = await client.getLevel2TicksFromMid('SUI_USDC', 5);
  print('top bids: ${book.bidPrices} x ${book.bidQuantities}');
  print('top asks: ${book.askPrices} x ${book.askQuantities}');

  final params = await client.poolBookParams('SUI_USDC');
  print('tick ${params.tickSize}, lot ${params.lotSize}');

  // Quote: what does selling 10 SUI yield?
  final quote = await client.getBaseQuantityOut('SUI_USDC', 10);
  print('10 SUI -> ${quote.quoteOut} USDC '
      '(DEEP fee required: ${quote.deepRequired})');

  // --- Compose a trade (requires a funded BalanceManager). ---
  // Builder methods return a closure applied to a Transaction, so several
  // calls compose into one programmable transaction block:
  //
  //   final tx = Transaction();
  //   client.balanceManager.depositIntoManager('MAIN', 'SUI', 10)(tx);
  //   client.deepBook.placeLimitOrder(PlaceLimitOrderParams(
  //     poolKey: 'SUI_USDC',
  //     balanceManagerKey: 'MAIN',
  //     clientOrderId: '1',
  //     price: 3.05,          // human units; BigInt = raw on-chain u64
  //     quantity: 10,
  //     isBid: true,
  //   ))(tx);
  //
  //   final account = SuiAccount.fromPrivateKey('suiprivkey...');
  //   final executed = await (grpc.core as GrpcCoreClient)
  //       .signAndExecuteTransaction(account, tx);
  //   print(executed.digest);
}
