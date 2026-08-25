// ignore_for_file: avoid_print — the console IS this harness's output channel.
//
// Minimal Flutter Web app exercising the DeepBook SDK's NETWORK layer from a
// real browser: gRPC-web client construction + live reads. Result is printed
// to the browser console so a headless run can assert on it.
import 'package:flutter/material.dart';
import 'package:sui/sui.dart' show GrpcCoreClient, SuiGrpcClient, SuiNetwork;
import 'package:deepbook/deepbook.dart';

void main() {
  probe().then((r) => print('PROBE_RESULT $r'))
         .catchError((e) => print('PROBE_ERROR $e'));
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('running')))));
}

Future<String> probe() async {
  final grpc = SuiGrpcClient(network: SuiNetwork.mainnet);
  final core = grpc.core as GrpcCoreClient;
  final chainId = await core.getChainIdentifier();
  final client =
      DeepBookClient(client: core, network: 'mainnet', address: '0x1');
  final mid = await client.midPrice('SUI_USDC');
  final book = await client.poolBookParams('SUI_USDC');
  return 'chain=$chainId mid=$mid tick=${book.tickSize}';
}
