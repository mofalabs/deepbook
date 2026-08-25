/// Hermes price-service REST client, mirroring the official SDK's
/// `pyth/PriceServiceConnection.ts`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Hermes endpoints used by DeepBook (testnet uses the beta instance).
String hermesEndpoint(String network) => network == 'testnet'
    ? 'https://hermes-beta.pyth.network'
    : 'https://hermes.pyth.network';

/// Minimal REST client for the Pyth Hermes price service.
class PriceServiceConnection {
  final Dio _http;

  /// Creates a connection to the Hermes [endpoint], optionally overriding
  /// the request [timeout] or supplying a custom [dio] instance.
  PriceServiceConnection(String endpoint,
      {Duration timeout = const Duration(seconds: 5), Dio? dio})
      : _http = dio ??
            Dio(BaseOptions(
              baseUrl: endpoint,
              connectTimeout: timeout,
              receiveTimeout: timeout,
            ));

  /// Fetch the latest VAAs for [priceIds] (hex feed ids), base64-encoded.
  Future<List<String>> getLatestVaas(List<String> priceIds) async {
    DioException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _http.get<List<dynamic>>(
          '/api/latest_vaas',
          queryParameters: {'ids[]': priceIds},
        );
        return (response.data ?? const []).cast<String>();
      } on DioException catch (e) {
        lastError = e;
        await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
    throw lastError!;
  }
}

/// Hermes connection that returns price feed updates in the binary form
/// expected by the Sui Pyth contract.
class SuiPriceServiceConnection extends PriceServiceConnection {
  /// Creates a Sui-flavored Hermes connection to [endpoint].
  SuiPriceServiceConnection(super.endpoint, {super.timeout, super.dio});

  /// Fetch price feed update data (decoded VAA/accumulator payloads).
  Future<List<Uint8List>> getPriceFeedsUpdateData(List<String> priceIds) async {
    final latestVaas = await getLatestVaas(priceIds);
    return latestVaas
        .map((vaa) => Uint8List.fromList(base64Decode(vaa)))
        .toList();
  }
}
