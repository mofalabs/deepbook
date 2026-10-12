/// BCS decoders for the return values of on-chain reads, mirroring
/// `predict/reads/parse.ts` — built on the `bcs`/`sui` codecs so the read
/// layer decodes exactly the on-chain Move ABI (u64 LE, `vector<ID>`,
/// `Option`) with no hand-rolled byte walking.
library;

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';

/// BCS u64 → [BigInt].
BigInt parseU64LE(Uint8List bytes) =>
    BigInt.parse(SuiBcs.U64.parse(bytes).toString());

/// BCS `vector<ID>` / `vector<address>` → full-length 0x lowercase ids.
List<String> parseVectorOfIds(Uint8List bytes) =>
    (Bcs.vector(SuiBcs.Address).parse(bytes) as List).cast<String>();

/// BCS `Option<u64>`: None → null, Some(x) → x.
BigInt? parseOptionalU64(Uint8List bytes) {
  final dynamic v = Bcs.option(SuiBcs.U64).parse(bytes);
  return v == null ? null : BigInt.parse(v.toString());
}

/// BCS `Option<ID>`: None → null, Some(id) → normalized 0x id.
String? parseOptionalId(Uint8List bytes) {
  final dynamic v = Bcs.option(SuiBcs.Address).parse(bytes);
  return v as String?;
}

/// BCS bool: one byte.
bool parseBool(Uint8List bytes) => bytes.isNotEmpty && bytes[0] != 0;
