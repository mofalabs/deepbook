/// Chain-only position enumeration, mirroring `predict/reads/positions.ts`.
///
/// Every open position is tracked under the owner's account:
/// `predict_account::PredictData.positions` is a
/// `Table<PositionKey{expiry_market_id, order_id}, Position>` — and Table
/// entries are dynamic fields, so the KEYS (everything redeem/claim need)
/// arrive directly from a dynamic-field listing. No indexer, no simulation.
///
/// The walk (all parsing is exact BCS; the account and PredictData struct
/// layouts come from the generated `contracts/*` MoveStructs so they can't
/// drift from the deployed `account`/`predict_account` sources):
///  1. wrapper object (id derived client-side)   → account UID
///  2. derived DataKey&lt;PredictApp&gt; field object   → positions Table id
///  3. listDynamicFields(table)                  → PositionKey per entry
///
/// Steps 1-2 resolve ids that are immutable once created — cache them per
/// owner (the facade does) and steady state is ONE call per page of
/// positions.
library;

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/sui.dart' show GrpcCoreClient;
import 'package:sui/types/common.dart' show normalizeSuiAddress;
import 'package:sui/utils/dynamic_fields.dart' show deriveDynamicFieldID;

import '../../contracts/account/account.dart' show AccountWrapper;
import '../../contracts/deepbook_predict/predict_account.dart'
    show PositionKey, PredictData;
import '../config.dart' show GeneratedConfig;
import '../tx/common.dart' show deriveAccountWrapperIdFrom;

// sui::dynamic_field::Field<DataKey<PredictApp>, PredictData>. DataKey is
// source-empty, but Move inserts a hidden `dummy_field: bool` into empty
// structs — so the name occupies ONE zero byte between id and value (and the
// same byte is the derived-field key, below). The `value` uses the generated
// `PredictData` layout so it tracks the deployed struct.
final _predictDataFieldBcs = Bcs.struct('Field<DataKey,PredictData>', {
  'id': SuiBcs.Address,
  'name': SuiBcs.BOOL, // DataKey's hidden dummy_field
  'value': PredictData,
});

/// One open position — the coordinates redeem/claim/hasPosition take.
class OpenPosition {
  final String marketId;
  final BigInt orderId;
  const OpenPosition({required this.marketId, required this.orderId});
}

/// Resolved-once ids for an owner's position store (cache these).
class PositionsHandle {
  final String accountUid;

  /// Null until the account's Predict data exists (first trade/builder-code).
  final String? positionsTableId;

  /// Open-position count at resolution time (from the Table's size).
  final BigInt positionCount;

  const PositionsHandle({
    required this.accountUid,
    required this.positionsTableId,
    required this.positionCount,
  });
}

Future<Uint8List?> _contentOf(GrpcCoreClient client, String objectId) async {
  // Only a genuinely absent object means "no positions" (never-onboarded
  // owner, or no Predict data yet). Anything else — transport failures, rate
  // limits — must surface, not silently read as an empty portfolio.
  try {
    final results = await client
        .getObjects([objectId], readMask: const ['object_id', 'contents']);
    if (results.isEmpty) {
      // One id in, zero results out is a malformed response, not "no
      // positions" — surface it rather than render an empty portfolio.
      throw Exception('getObject($objectId) returned no result');
    }
    final result = results[0];
    if (!result.hasObject()) {
      if (result.hasError() &&
          !RegExp(r'not.?found|does not exist|deleted', caseSensitive: false)
              .hasMatch(result.error.toString())) {
        throw Exception('getObject($objectId) failed: ${result.error}');
      }
      return null;
    }
    final contents = result.object.contents.value;
    return contents.isEmpty ? null : Uint8List.fromList(contents);
  } catch (e) {
    if (RegExp(r'not.?found|does not exist|deleted|NOT_FOUND',
            caseSensitive: false)
        .hasMatch(e.toString())) {
      return null;
    }
    rethrow;
  }
}

/// Resolve the immutable id chain for an owner's positions: wrapper → account
/// UID → PredictData → positions Table. Returns null when the owner has never
/// created a Predict account.
Future<PositionsHandle?> resolvePositionsTable(
  GrpcCoreClient client,
  GeneratedConfig config,
  String owner,
) async {
  final wrapperContent =
      await _contentOf(client, deriveAccountWrapperIdFrom(config, owner));
  if (wrapperContent == null) return null;
  final wrapper = AccountWrapper.parse(wrapperContent) as Map;
  final accountUid =
      normalizeSuiAddress((wrapper['account'] as Map)['account_id'] as String);

  // The PredictData field id is derivable — no listing needed for this hop.
  final dataFieldId = deriveDynamicFieldID(
    accountUid,
    '${config['accountPackageId']}::account::DataKey'
    '<${config['predictPackageIdV1']}::predict_account::PredictApp>',
    Uint8List.fromList(const [0]), // DataKey's hidden dummy_field: bool = false
  );
  final fieldContent = await _contentOf(client, dataFieldId);
  if (fieldContent == null) {
    return PositionsHandle(
        accountUid: accountUid,
        positionsTableId: null,
        positionCount: BigInt.zero);
  }

  final data =
      (_predictDataFieldBcs.parse(fieldContent) as Map)['value'] as Map;
  final table = data['positions'] as Map;
  return PositionsHandle(
    accountUid: accountUid,
    positionsTableId: normalizeSuiAddress(table['id'] as String),
    positionCount: BigInt.parse(table['size'].toString()),
  );
}

/// List open positions from a resolved positions Table: one call per page,
/// keys parsed from the dynamic-field NAMES (no per-entry fetches).
Future<List<OpenPosition>> positionsFromTable(
  GrpcCoreClient client,
  String positionsTableId, {
  int limit = 1000,
  int maxPages = 10,
}) async {
  final out = <OpenPosition>[];
  Uint8List? cursor;
  for (var page = 0; page < maxPages; page++) {
    final res = await client.listDynamicFields(
      positionsTableId,
      pageSize: limit,
      pageToken: cursor,
      readMask: const ['field_id', 'name'],
    );
    for (final entry in res.dynamicFields) {
      final key =
          PositionKey.parse(Uint8List.fromList(entry.name.value)) as Map;
      out.add(OpenPosition(
        marketId: normalizeSuiAddress(key['expiry_market_id'] as String),
        orderId: BigInt.parse(key['order_id'].toString()),
      ));
    }
    if (!res.hasNextPageToken() || res.nextPageToken.isEmpty) return out;
    cursor = Uint8List.fromList(res.nextPageToken);
  }
  throw Exception('positions listing exceeded $maxPages pages '
      '(${out.length} so far) — raise maxPages');
}

/// Convenience: resolve + list in one call (uncached; the facade caches).
Future<List<OpenPosition>> positions(
  GrpcCoreClient client,
  GeneratedConfig config,
  String owner, {
  int limit = 1000,
  int maxPages = 10,
}) async {
  final handle = await resolvePositionsTable(client, config, owner);
  final tableId = handle?.positionsTableId;
  if (tableId == null) return [];
  return positionsFromTable(client, tableId, limit: limit, maxPages: maxPages);
}
