// Offline checks for the Pyth surface: the old-style (positional) generated
// builders and the Hermes v2 request shape.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sui/sui.dart' show Transaction;

import 'package:deepbook/src/contracts/pyth/pyth.dart' as pyth;
import 'package:deepbook/src/contracts/pyth/price.dart' as pyth_price;
import 'package:deepbook/src/pyth/price_service_connection.dart';

void main() {
  group('old-style pyth builders take positional arguments', () {
    // These modules come from the official SDK's older codegen (no
    // parameterNames); a regression here means the generator mistook
    // "no names" for "no user arguments" again.
    test('initPyth applies with 8 positional arguments', () {
      final tx = Transaction();
      tx.setSenderIfNotSet('0x2');
      final builder = pyth.initPyth(arguments: [
        '0x1234567890123456789012345678901234567890123456789012345678901234',
        '0x2345678901234567890123456789012345678901234567890123456789012345',
        1, // stale_price_threshold
        2, // governance emitter chain
        List<int>.filled(32, 7), // governance emitter address
        <int>[1, 2], // data source chains
        [List<int>.filled(32, 1), List<int>.filled(32, 2)], // source addrs
        3, // update fee
      ]);
      expect(() => builder(tx), returnsNormally);
    });

    test('arity is still enforced', () {
      final tx = Transaction();
      expect(() => pyth_price.new_(arguments: [1])(tx), throwsArgumentError);
    });
  });

  group('Hermes v2 request shape', () {
    test('ids[] repeats per element and Authorization reaches a custom dio',
        () async {
      Uri? captured;
      Map<String, dynamic>? capturedHeaders;
      final dio = Dio(BaseOptions(baseUrl: 'https://hermes.example'));
      dio.httpClientAdapter = _StubAdapter((options) {
        captured = options.uri;
        capturedHeaders = options.headers;
        return ResponseBody.fromString(
          jsonEncode({
            'binary': {
              'data': [
                base64Encode([1, 2, 3])
              ],
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final connection = SuiPriceServiceConnection(
        'https://hermes.example',
        accessToken: 'secret-token',
        dio: dio,
      );
      final updates =
          await connection.getPriceFeedsUpdateData(['0xfeed1', '0xfeed2']);

      expect(updates.single, Uint8List.fromList([1, 2, 3]));
      // dio's default ListFormat.multi repeats the key per element, which
      // Hermes decodes identically to axios's literal `ids[]=` form.
      expect(captured!.query.split('&').where((p) => p.startsWith('ids')),
          hasLength(2));
      expect(captured!.queryParametersAll['ids[]'], ['0xfeed1', '0xfeed2']);
      expect(captured!.queryParameters['encoding'], 'base64');
      expect(captured!.queryParameters['parsed'], 'false');
      // The token must be applied per request, not lost with a custom dio.
      expect(capturedHeaders!['Authorization'], 'Bearer secret-token');
    });

    test('a 4xx fails immediately without retries', () async {
      var calls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://hermes.example'));
      dio.httpClientAdapter = _StubAdapter((options) {
        calls += 1;
        return ResponseBody.fromString('{"error":"unauthorized"}', 401,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            });
      });

      final connection =
          SuiPriceServiceConnection('https://hermes.example', dio: dio);
      await expectLater(
          connection.getPriceFeedsUpdateData(['0xfeed']), throwsException);
      expect(calls, 1);
    });

    test('a 5xx is retried up to 1+3 attempts', () async {
      var calls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://hermes.example'));
      dio.httpClientAdapter = _StubAdapter((options) {
        calls += 1;
        return ResponseBody.fromString('oops', 503);
      });

      final connection =
          SuiPriceServiceConnection('https://hermes.example', dio: dio);
      await expectLater(
          connection.getPriceFeedsUpdateData(['0xfeed']), throwsException);
      expect(calls, 4);
    });

    test('failure messages never contain the bearer token', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://hermes.example'));
      dio.httpClientAdapter = _StubAdapter((options) =>
          ResponseBody.fromString('{"error":"unauthorized"}', 401, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          }));

      final connection = SuiPriceServiceConnection('https://hermes.example',
          accessToken: 'secret-token', dio: dio);
      Object? error;
      try {
        await connection.getPriceFeedsUpdateData(['0xfeed']);
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect('$error', isNot(contains('secret-token')));
      expect('$error', contains('401'));
    });
  });
}

class _StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) _respond;
  _StubAdapter(this._respond);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      _respond(options);

  @override
  void close({bool force = false}) {}
}
