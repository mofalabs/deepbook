/// Pyth price feed queries, mirroring the official SDK's
/// `queries/priceFeedQueries.ts`.
library;

import 'dart:typed_data';

import 'package:sui/sui.dart' show Transaction;

import '../config.dart';
import '../contracts/pyth/price_info.dart' as price_info;
import '../errors.dart';
import '../pyth/price_service_connection.dart';
import '../pyth/sui_pyth_client.dart';
import 'query_context.dart';

class PriceFeedQueries {
  final QueryContext _ctx;

  PriceFeedQueries(this._ctx);

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
      return _ctx.config.getCoin(coinKey).priceInfoObjectId!;
    }

    final connection =
        SuiPriceServiceConnection(hermesEndpoint(_ctx.config.network));

    final priceIds = [_ctx.config.getCoin(coinKey).feed!];

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
      final priceInfoObjectId = _ctx.config.getCoin(coinKey).priceInfoObjectId!;
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

    final staleFeedIds = <String>[];
    final feedIdToCoinKey = <String, String>{};
    for (final coinKey in staleCoinKeys) {
      final feedId = _ctx.config.getCoin(coinKey).feed!;
      staleFeedIds.add(feedId);
      feedIdToCoinKey[feedId] = coinKey;
    }

    final connection =
        SuiPriceServiceConnection(hermesEndpoint(_ctx.config.network));

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
      final coinKey = feedIdToCoinKey[staleFeedIds[i]]!;
      result[coinKey] = updatedObjectIds[i];
    }

    return result;
  }

  /// The arrival time (unix seconds) of the on-chain PriceInfoObject for
  /// [coinKey].
  Future<int> getPriceInfoObjectAge(String coinKey) async {
    final priceInfoObjectId = _ctx.config.getCoin(coinKey).priceInfoObjectId!;
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
