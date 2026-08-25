/// Pyth accumulator-message helpers, mirroring the official SDK's
/// `pyth/pyth-helpers.ts`.
library;

import 'dart:typed_data';

/// Extracts the VAA bytes embedded in an accumulator message.
Uint8List extractVaaBytesFromAccumulatorMessage(Uint8List accumulatorMessage) {
  final view = ByteData.sublistView(accumulatorMessage);
  final trailingPayloadSize = view.getUint8(6);
  // Header (7 bytes), trailing payload size, proof type.
  final vaaSizeOffset = 7 + trailingPayloadSize + 1;
  final vaaSize = view.getUint16(vaaSizeOffset); // big-endian
  final vaaOffset = vaaSizeOffset + 2;
  return Uint8List.sublistView(
      accumulatorMessage, vaaOffset, vaaOffset + vaaSize);
}
