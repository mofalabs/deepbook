/// Pyth price feed queries, mirroring the official SDK's
/// `queries/priceFeedQueries.ts`.
library;

import 'dart:typed_data';

import 'package:sui/sui.dart' show Transaction;

import '../config.dart';
import '../constants.dart';
import '../contracts/pyth/price_info.dart' as price_info;
import '../errors.dart';
import '../pyth/price_service_connection.dart';
import '../pyth/sui_pyth_client.dart';
import 'query_context.dart';

class PriceFeedQueries {
  final QueryContext _ctx;

  PriceFeedQueries(this._ctx);

  /// The Hermes endpoint serving the Pyth deployment margin is configured
  /// against.
  ///
  /// There are two routes, chosen by whether the caller brought credentials.
  /// With `accessToken` set, the SDK talks to Pyth directly and no DeepBook
  /// infrastructure is in the path — the token is sent to Pyth's own host, so
  /// a token minted for some other endpoint must be paired with an explicit
  /// `hermesEndpoint`.
  ///
  /// Note the converse too: an explicit `hermesEndpoint` wins over
  /// everything, and the token is sent to whatever host it names.
  ///
  /// Without a token it falls back to the DeepBook-operated proxy, which
  /// supplies credentials server-side; that proxy is not deployed yet, so
  /// today this path throws a [ConfigurationError] instead.
  String _hermesEndpoint() {
    final pyth = _ctx.config.pyth;
    // Empty strings count as "not provided", matching the official SDK's
    // truthiness checks on these fields.
    final hermesEndpoint = pyth.hermesEndpoint;
    if (hermesEndpoint != null && hermesEndpoint.isNotEmpty) {
      return hermesEndpoint;
    }
    final accessToken = pyth.accessToken;
    if (accessToken != null && accessToken.isNotEmpty) {
      return PYTH_UPGRADED_HERMES;
    }
    if (DEEPBOOK_HERMES_PROXY != null) {
      return DEEPBOOK_HERMES_PROXY!;
    }
    throw ConfigurationError(
        "Pushing price updates against Pyth's upgraded Core needs "
        'credentials: its Hermes answers 401 unauthenticated. Set the '
        "client's `pythAccessToken` option (or `pyth.accessToken`), or point "
        '`pyth.hermesEndpoint` at an endpoint that supplies credentials '
        'itself.');
  }

  /// A Hermes connection for the active Pyth deployment, carrying any
  /// configured auth headers. The endpoint serving the upgraded Core requires
  /// an `Authorization` header and answers 401 without one.
  SuiPriceServiceConnection _connection() {
    final accessToken = _ctx.config.pyth.accessToken;
    return SuiPriceServiceConnection(
      _hermesEndpoint(),
      accessToken:
          accessToken != null && accessToken.isNotEmpty ? accessToken : null,
    );
  }

  /// Ensures a fresh PriceInfoObject for [coinKey]: if the on-chain object is
  /// recent enough its id is returned directly, otherwise price-update
  /// commands are added to [tx] via Hermes/Pyth and the updated object id is
  /// returned.
  Future<String> getPriceInfoObject(Transaction tx, String coinKey) async {
    _ctx.config.requirePyth();
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final priceInfoObjectAge = await getPriceInfoObjectAge(coinKey);
    if (priceInfoObjectAge != 0 &&
        currentTime - priceInfoObjectAge * 1000 <
            PRICE_INFO_OBJECT_MAX_AGE_MS) {
      return _ctx.config.getPriceInfoObjectId(coinKey);
    }

    final connection = _connection();

    final priceIds = [_ctx.config.getFeedId(coinKey)];

    final priceUpdateData = await connection.getPriceFeedsUpdateData(priceIds);

    final client = SuiPythClient(
      _ctx.core,
      pythStateId: _ctx.config.pyth.pythStateId,
      wormholeStateId: _ctx.config.pyth.wormholeStateId,
    );

    return (await client.updatePriceFeeds(tx, priceUpdateData, priceIds))[0];
  }

  /// Ensures fresh PriceInfoObjects for [coinKeys]; stale feeds get update
  /// commands added to [tx]. Returns coin key → PriceInfoObject id.
  Future<Map<String, String>> getPriceInfoObjects(
      Transaction tx, List<String> coinKeys) async {
    _ctx.config.requirePyth();
    if (coinKeys.isEmpty) return {};

    final currentTime = DateTime.now().millisecondsSinceEpoch;

    final coinToObjectId = <String, String>{};
    final objectIds = <String>[];
    for (final coinKey in coinKeys) {
      final priceInfoObjectId = _ctx.config.getPriceInfoObjectId(coinKey);
      coinToObjectId[coinKey] = priceInfoObjectId;
      objectIds.add(priceInfoObjectId);
    }

    final res =
        await _ctx.core.getObjects(objectIds, readMask: const ['contents']);

    final staleCoinKeys = <String>[];
    final result = <String, String>{};

    for (var i = 0; i < coinKeys.length; i++) {
      final coinKey = coinKeys[i];
      final obj = res[i];

      if (!obj.hasObject() || obj.object.contents.value.isEmpty) {
        staleCoinKeys.add(coinKey);
        continue;
      }

      final priceInfoObject = price_info.PriceInfoObject.parse(
          Uint8List.fromList(obj.object.contents.value));
      final arrivalTime =
          ((priceInfoObject['price_info'] as Map)['arrival_time'] as BigInt)
              .toInt();
      final age = currentTime - arrivalTime * 1000;

      if (age >= PRICE_INFO_OBJECT_MAX_AGE_MS) {
        staleCoinKeys.add(coinKey);
      } else {
        result[coinKey] = coinToObjectId[coinKey]!;
      }
    }

    if (staleCoinKeys.isEmpty) return result;

    // Distinct coins can share a feed. No shipped map has a collision, but
    // `coins` is a public constructor option, and coins tracking the same
    // underlying (a wrapped asset priced off its reference, say) are the
    // normal reason to supply one. Deduplicate before building the update: a
    // feed listed twice would emit two `update_single_price_feed` calls
    // against the same object off one hot-potato vector, and pay two update
    // fees for it. One feed can also map to several coins, so the reverse
    // index holds a list, not a single key.
    final staleFeedIds = <String>[];
    final feedIdToCoinKeys = <String, List<String>>{};
    for (final coinKey in staleCoinKeys) {
      final feedId = _ctx.config.getFeedId(coinKey);
      if (!feedIdToCoinKeys.containsKey(feedId)) {
        feedIdToCoinKeys[feedId] = [];
        staleFeedIds.add(feedId);
      }
      feedIdToCoinKeys[feedId]!.add(coinKey);
    }

    final connection = _connection();

    final priceUpdateData =
        await connection.getPriceFeedsUpdateData(staleFeedIds);

    final pythClient = SuiPythClient(
      _ctx.core,
      pythStateId: _ctx.config.pyth.pythStateId,
      wormholeStateId: _ctx.config.pyth.wormholeStateId,
    );

    final updatedObjectIds =
        await pythClient.updatePriceFeeds(tx, priceUpdateData, staleFeedIds);

    for (var i = 0; i < staleFeedIds.length; i++) {
      for (final coinKey in feedIdToCoinKeys[staleFeedIds[i]]!) {
        result[coinKey] = updatedObjectIds[i];
      }
    }

    return result;
  }

  /// The arrival time (unix seconds) of the on-chain PriceInfoObject for
  /// [coinKey].
  Future<int> getPriceInfoObjectAge(String coinKey) async {
    final priceInfoObjectId = _ctx.config.getPriceInfoObjectId(coinKey);
    final res = await _ctx.core
        .getObject(priceInfoObjectId, readMask: const ['contents']);

    if (res.contents.value.isEmpty) {
      throw DeepBookError('Price info object not found for $coinKey');
    }

    final priceInfoObject = price_info.PriceInfoObject.parse(
        Uint8List.fromList(res.contents.value));
    return ((priceInfoObject['price_info'] as Map)['arrival_time'] as BigInt)
        .toInt();
  }
}
