/// Sui Pyth client: verifies wormhole VAAs and updates on-chain price feeds.
/// Mirrors the official SDK's `pyth/pyth.ts`.
library;

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/bcs/type_tag_serializer.dart';
import 'package:sui/sui.dart' show GrpcCoreClient, Transaction;
import 'package:sui/utils/dynamic_fields.dart' show deriveDynamicFieldID;

import '../contracts/pyth/state.dart' as pyth_state;
import '../contracts/wormhole/state.dart' as wormhole_state;
import '../errors.dart';
import 'pyth_helpers.dart';

const _suiType = '0x2::sui::SUI';
const _clockId = '0x6';

/// Location of the on-chain Pyth price table.
class PriceTableInfo {
  /// The price table object id.
  final String id;

  /// The package address that defines the table's `PriceIdentifier` field
  /// type.
  final String fieldType;

  /// Creates a price table descriptor from [id] and [fieldType].
  const PriceTableInfo({required this.id, required this.fieldType});
}

/// Client that verifies Wormhole VAAs and updates Pyth price feeds on Sui.
class SuiPythClient {
  /// The gRPC client used for on-chain reads.
  final GrpcCoreClient provider;

  /// The Pyth `State` shared object id.
  final String pythStateId;

  /// The Wormhole `State` shared object id.
  final String wormholeStateId;

  Future<String>? _pythPackageId;
  Future<String>? _wormholePackageId;
  final Map<String, Future<String>> _priceFeedObjectIdCache = {};
  Future<PriceTableInfo>? _priceTableInfo;
  Future<BigInt>? _baseUpdateFee;

  /// Creates a client that reads Pyth and Wormhole state through [provider].
  SuiPythClient(this.provider,
      {required this.pythStateId, required this.wormholeStateId});

  /// Verifies [vaas] through the Wormhole contract; returns the verified VAA
  /// arguments.
  Future<List<dynamic>> verifyVaas(List<Uint8List> vaas, Transaction tx) async {
    final wormholePackageId = await getWormholePackageId();
    final verifiedVaas = <dynamic>[];
    for (final vaa in vaas) {
      final verifiedVaa = tx.moveCall(
        '$wormholePackageId::vaa::parse_and_verify',
        arguments: [
          tx.object(wormholeStateId),
          tx.pure('vector<u8>', vaa),
          tx.object(_clockId),
        ],
      );
      verifiedVaas.add(verifiedVaa[0]);
    }
    return verifiedVaas;
  }

  /// Adds the commands updating the Pyth price feeds for [feedIds] to [tx];
  /// returns the PriceInfoObject ids.
  Future<List<String>> updatePriceFeeds(
      Transaction tx, List<Uint8List> updates, List<String> feedIds) async {
    final packageId = await getPythPackageId();
    if (updates.length > 1) {
      throw DeepBookError(
          'SDK does not support sending multiple accumulator messages in a '
          'single transaction');
    }
    final vaa = extractVaaBytesFromAccumulatorMessage(updates[0]);
    final verifiedVaas = await verifyVaas([vaa], tx);

    dynamic priceUpdatesHotPotato = tx.moveCall(
      '$packageId::pyth::create_authenticated_price_infos_using_accumulator',
      arguments: [
        tx.object(pythStateId),
        tx.pure(Bcs.vector(SuiBcs.U8).serialize(updates[0])),
        verifiedVaas[0],
        tx.object(_clockId),
      ],
    )[0];

    final priceInfoObjects = <String>[];
    final baseUpdateFee = await getBaseUpdateFee();
    for (final feedId in feedIds) {
      final priceInfoObjectId = await getPriceFeedObjectId(feedId);
      priceInfoObjects.add(priceInfoObjectId);
      priceUpdatesHotPotato = tx.moveCall(
        '$packageId::pyth::update_single_price_feed',
        arguments: [
          tx.object(pythStateId),
          priceUpdatesHotPotato,
          tx.object(priceInfoObjectId),
          tx.coin(_suiType, baseUpdateFee),
          tx.object(_clockId),
        ],
      )[0];
    }
    tx.moveCall(
      '$packageId::hot_potato_vector::destroy',
      arguments: [priceUpdatesHotPotato],
      typeArguments: ['$packageId::price_info::PriceInfo'],
    );
    return priceInfoObjects;
  }

  /// The PriceInfoObject id for a hex [feedId], cached. Failed lookups are
  /// evicted so they can be retried.
  Future<String> getPriceFeedObjectId(String feedId) {
    return _priceFeedObjectIdCache.putIfAbsent(
      feedId,
      () => _fetchPriceFeedObjectId(feedId).catchError((Object err) {
        _priceFeedObjectIdCache.remove(feedId);
        throw err;
      }),
    );
  }

  Future<String> _fetchPriceFeedObjectId(String feedId) async {
    final tableInfo = await getPriceTableInfo();
    final nameBytes = Bcs.vector(SuiBcs.U8)
        .serialize(hexDecode(feedId.replaceFirst('0x', '')))
        .toBytes();

    final fieldId = deriveDynamicFieldID(
      tableInfo.id,
      '${tableInfo.fieldType}::price_identifier::PriceIdentifier',
      nameBytes,
    );
    final field = await provider
        .getObject(fieldId, readMask: const ['object_id', 'contents']);
    if (field.contents.value.isEmpty) {
      throw DeepBookError(
          'Price feed object ID for feed ID $feedId not found.');
    }
    // Field<PriceIdentifier, ID>: { id: UID, name: {bytes}, value: address }
    final fieldStruct = Bcs.struct('Field', {
      'id': SuiBcs.Address,
      'name': Bcs.struct('PriceIdentifier', {
        'bytes': Bcs.vector(SuiBcs.U8),
      }),
      'value': SuiBcs.Address,
    });
    final parsed = fieldStruct.parse(Uint8List.fromList(field.contents.value));
    return parsed['value'] as String;
  }

  /// The Pyth price table id and its PriceIdentifier field package, cached.
  Future<PriceTableInfo> getPriceTableInfo() {
    return _priceTableInfo ??= _fetchPriceTableInfo().catchError((Object err) {
      _priceTableInfo = null;
      throw err;
    });
  }

  Future<PriceTableInfo> _fetchPriceTableInfo() async {
    final nameBcs = SuiBcs.STRING.serialize('price_info').toBytes();
    final table = await provider.getDynamicObjectField(
      pythStateId,
      'vector<u8>',
      nameBcs,
      readMask: const ['object_id', 'object_type'],
    );
    if (table.objectId.isEmpty) {
      throw DeepBookError(
          'Price Table not found, contract may not be initialized');
    }
    final tableType = TypeTagSerializer.parseFromStr(table.objectType);
    final typeParams =
        (tableType['struct']?['typeParams'] as List?) ?? const [];
    if (typeParams.isEmpty) throw DeepBookError('fieldType not found');
    final first = typeParams.first as Map;
    final struct = first['struct'] as Map?;
    if (struct == null || struct['name'] != 'PriceIdentifier') {
      throw DeepBookError('fieldType not found');
    }
    return PriceTableInfo(
        id: table.objectId, fieldType: struct['address'] as String);
  }

  /// The Wormhole package id (from its State's upgrade cap), cached.
  Future<String> getWormholePackageId() =>
      _wormholePackageId ??= _fetchPackageId(wormholeStateId, isPyth: false);

  /// The Pyth package id (from its State's upgrade cap), cached.
  Future<String> getPythPackageId() =>
      _pythPackageId ??= _fetchPackageId(pythStateId, isPyth: true);

  Future<String> _fetchPackageId(String stateId, {required bool isPyth}) async {
    final object =
        await provider.getObject(stateId, readMask: const ['contents']);
    if (object.contents.value.isEmpty) {
      throw DeepBookError('Unable to fetch state object $stateId');
    }
    final bytes = Uint8List.fromList(object.contents.value);
    final Map<String, dynamic> state = isPyth
        ? pyth_state.State.parse(bytes)
        : wormhole_state.State.parse(bytes);
    return (state['upgrade_cap'] as Map)['package'] as String;
  }

  /// The base update fee from the Pyth state object, cached.
  Future<BigInt> getBaseUpdateFee() => _baseUpdateFee ??= _fetchBaseUpdateFee();

  Future<BigInt> _fetchBaseUpdateFee() async {
    final object =
        await provider.getObject(pythStateId, readMask: const ['contents']);
    if (object.contents.value.isEmpty) {
      throw DeepBookError('Unable to fetch Pyth state object');
    }
    final state =
        pyth_state.State.parse(Uint8List.fromList(object.contents.value));
    return state['base_update_fee'] as BigInt;
  }
}
