/// Human-readable ↔ on-chain integer conversions, mirroring the official
/// SDK's `utils/conversion.ts`.
///
/// Quantity-like inputs across the SDK accept either:
///  - a [num]: human units, scaled by the relevant coin scalar; or
///  - a [BigInt]: the raw on-chain u64, used as-is.
library;

/// Converts a quantity (amount, deposit, …) to its on-chain u64.
BigInt convertQuantity(Object value, num scalar) {
  if (value is BigInt) return value;
  if (value is num) return BigInt.from((value * scalar).round());
  throw ArgumentError.value(value, 'value', 'expected num or BigInt');
}

/// Converts a price to its on-chain u64 using the cross-scalar formula.
BigInt convertPrice(
    Object value, num floatScalar, num quoteScalar, num baseScalar) {
  if (value is BigInt) return value;
  if (value is num) {
    return BigInt.from(
        (value * floatScalar * quoteScalar / baseScalar).round());
  }
  throw ArgumentError.value(value, 'value', 'expected num or BigInt');
}

/// Converts a rate/fee to its on-chain u64 (scaled by `FLOAT_SCALAR`).
BigInt convertRate(Object value, num floatScalar) {
  if (value is BigInt) return value;
  if (value is num) return BigInt.from((value * floatScalar).round());
  throw ArgumentError.value(value, 'value', 'expected num or BigInt');
}
