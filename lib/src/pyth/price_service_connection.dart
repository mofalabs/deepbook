/// Hermes price-service REST client, mirroring the official SDK's
/// `pyth/PriceServiceConnection.ts`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Minimal REST client for the Pyth Hermes price service.
class PriceServiceConnection {
  final Dio _http;
  final String? _accessToken;
  final Duration _timeout;

  /// Creates a connection to the Hermes [endpoint], optionally overriding
  /// the request [timeout], supplying an [accessToken] (sent as
  /// `Authorization: Bearer`; the endpoint serving Pyth's upgraded Core
  /// answers 401 without one), or a custom [dio] instance.
  ///
  /// [accessToken] and [timeout] are applied per request, so they take
  /// effect with a custom [dio] too — except the connect timeout, which dio
  /// only supports client-wide and which therefore stays under the custom
  /// instance's own configuration.
  PriceServiceConnection(String endpoint,
      {Duration timeout = const Duration(seconds: 5),
      String? accessToken,
      Dio? dio})
      : _accessToken = accessToken,
        _timeout = timeout,
        _http =
            dio ?? Dio(BaseOptions(baseUrl: endpoint, connectTimeout: timeout));

  /// Fetch the latest price update data for [priceIds] (hex feed ids).
  ///
  /// Uses Hermes v2 (`/v2/updates/price/latest`). The v1 endpoint
  /// (`/api/latest_vaas`) is deprecated; it returned the same payload this
  /// reads out of `binary.data`.
  ///
  /// Hermes returns one accumulator message covering every requested feed,
  /// not one per feed, so the result is normally a single element regardless
  /// of `priceIds.length`.
  ///
  /// Returns base64-encoded update messages.
  Future<List<String>> getLatestVaas(List<String> priceIds) async {
    Response<Map<String, dynamic>> response;
    try {
      response = await _requestWithRetry(priceIds);
    } on DioException catch (e) {
      // A DioException carries its RequestOptions — including the
      // Authorization header — and `toString()`/logging interceptors
      // serialize it. Callers log failed requests, so letting the raw error
      // escape would put the bearer token in their logs. Re-throw a plain
      // error carrying only what is useful for diagnosis.
      throw Exception('Hermes request failed: ${_describeRequestError(e)}');
    }

    final binary = response.data?['binary'];
    final data = binary is Map ? binary['data'] : null;
    if (data is! List) {
      final body = jsonEncode(response.data);
      throw Exception(
          "Unexpected Hermes response: expected 'binary.data' array from "
          '/v2/updates/price/latest, got '
          '${body.length > 200 ? body.substring(0, 200) : body}');
    }
    return data.cast<String>();
  }

  /// One initial attempt plus up to [_maxRetries] retries, mirroring the
  /// official client's axios-retry configuration (`retries: 3`, exponential
  /// delay): only network errors and 5xx responses are retried — a 4xx
  /// (bad token, bad feed id) fails immediately.
  static const _maxRetries = 3;

  Future<Response<Map<String, dynamic>>> _requestWithRetry(
      List<String> priceIds) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _http.get<Map<String, dynamic>>(
          '/v2/updates/price/latest',
          queryParameters: {
            'ids[]': priceIds,
            'encoding': 'base64',
            'parsed': 'false',
          },
          options: Options(
            headers: _accessToken != null
                ? {'Authorization': 'Bearer $_accessToken'}
                : null,
            receiveTimeout: _timeout,
            sendTimeout: _timeout,
          ),
        );
      } on DioException catch (e) {
        if (attempt >= _maxRetries || !_isRetryable(e)) rethrow;
        // axios-retry's exponentialDelay: 100ms * 2^retryNumber.
        await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
      }
    }
  }

  /// Network errors and 5xx responses are transient; everything with a
  /// definitive answer (4xx) or a broken peer certificate is not.
  static bool _isRetryable(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) return status >= 500;
    return e.type != DioExceptionType.cancel &&
        e.type != DioExceptionType.badCertificate;
  }
}

/// A diagnosable one-line summary of a failed request that cannot contain
/// the access token: status and response body only, never the request
/// options or their headers.
String _describeRequestError(DioException error) {
  final response = error.response;
  if (response != null) {
    final data = response.data;
    final body = data is String ? data : jsonEncode(data);
    final truncated = body.length > 200 ? body.substring(0, 200) : body;
    return '${response.statusCode ?? '?'} '
            '${response.statusMessage ?? ''} $truncated'
        .trim();
  }
  // No response: a transport failure. The type name and dio's fixed
  // description text ([DioException.message]) embed no header material,
  // unlike the full exception, whose RequestOptions carry Authorization.
  final message = error.message;
  return message == null || message.isEmpty
      ? error.type.name
      : '${error.type.name}: $message';
}

/// Hermes connection that returns price feed updates in the binary form
/// expected by the Sui Pyth contract.
class SuiPriceServiceConnection extends PriceServiceConnection {
  /// Creates a Sui-flavored Hermes connection to [endpoint].
  SuiPriceServiceConnection(super.endpoint,
      {super.timeout, super.accessToken, super.dio});

  /// Fetch price feed update data (decoded VAA/accumulator payloads).
  Future<List<Uint8List>> getPriceFeedsUpdateData(List<String> priceIds) async {
    final latestVaas = await getLatestVaas(priceIds);
    return latestVaas
        .map((vaa) => Uint8List.fromList(base64Decode(vaa)))
        .toList();
  }
}
