import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sui/grpc/transport/grpc_web_transport.dart';
import 'package:bcs/bcs.dart';
import 'package:deepbook/deepbook.dart';

/// Web-platform checks for the layers that a browser build depends on.
///
/// Run with: flutter test test/web_transport_test.dart --platform chrome
/// (also passes on the VM).
///
/// The full [GrpcCoreClient] is deliberately NOT constructed here: the TEST
/// RUNNER's web compiler stalls on the generated `sui.rpc.v2` protobuf set
/// (124 files, ~18k lines). That is a `flutter test --platform chrome`
/// limitation, not a platform one — `flutter build web --release` compiles
/// the same code in ~25s, and `tool/webcheck/run.sh` proves the client does
/// live gRPC-web reads from a headless browser.
void main() {
  test('dio — the HTTP stack under gRPC-web — works in the browser', () {
    expect(Dio(), isNotNull);
  });

  test('the gRPC-web transport compiles and constructs on the web', () {
    final transport =
        GrpcWebTransport('https://fullnode.mainnet.sui.io:443', dio: Dio());
    expect(transport, isNotNull);
  });

  test('config, constants and conversion behave identically on the web', () {
    final config = DeepBookConfig(network: 'mainnet', address: '0x1');
    expect(config.getPool('SUI_USDC').baseCoin, 'SUI');
    expect(config.getCoin('DEEP').scalar, 1000000);
    expect(mainnetPools.length, greaterThan(20));
  });

  test('BCS schemas parse identically on the web', () {
    // Order ids are u128; web numbers are doubles, so this exercises the
    // BigInt path that a browser build depends on.
    final encoded = Bcs.u128()
        .serialize(BigInt.parse('170141183460469231731687303715884105728'));
    expect(Bcs.u128().parse(encoded.toBytes()),
        BigInt.parse('170141183460469231731687303715884105728'));
  });
}
