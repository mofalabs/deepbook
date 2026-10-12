/// Raw ⇄ human unit conversions for Predict, mirroring `predict/units.ts`.
///
/// Decimal→raw is EXACT string math ([toRaw] rejects negatives and excess
/// precision); raw→decimal is for display only ([fromRaw] casts through
/// double, so values above 2^53 raw lose precision in the low digits — fine
/// for UI, not for accounting; the primitives keep exact [BigInt]s).
library;

import 'dart:math' as math;

import 'errors.dart';

// Official constant names are kept verbatim (U64_MAX …) so code ports
// from the TypeScript SDK line for line.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

/// The largest u64: the "no cap" sentinel the trade entrypoints take.
final BigInt U64_MAX = (BigInt.one << 64) - BigInt.one;

// Expand exponential notation to a plain decimal string, exactly (string
// math). Dart's double.toString() emits exponentials for small/large values,
// which the plain-decimal regex in [toRaw] would otherwise reject with a
// misleading "invalid" error even when the value is exactly representable.
String _expandExponential(String s) {
  final m = RegExp(r'^(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$').firstMatch(s);
  if (m == null) return s;
  final whole = m.group(1)!;
  final frac = m.group(2) ?? '';
  final digits = whole + frac;
  final point = whole.length + int.parse(m.group(3)!);
  if (point <= 0) return '0.${'0' * -point}$digits';
  if (point >= digits.length) return digits + '0' * (point - digits.length);
  return '${digits.substring(0, point)}.${digits.substring(point)}';
}

/// Exact decimal→raw conversion via string math. [value] is a non-negative
/// [num] or decimal [String]. Throws on negatives and excess precision.
BigInt toRaw(Object value, int decimals) {
  final String s;
  if (value is num) {
    s = _expandExponential(value.toString());
  } else if (value is String) {
    s = _expandExponential(value.trim());
  } else {
    throw PredictInputError(
        'expected a num or decimal String, got ${value.runtimeType}');
  }
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) {
    throw PredictInputError('invalid or negative decimal value: $s');
  }
  final parts = s.split('.');
  final whole = parts[0];
  final frac = parts.length > 1 ? parts[1] : '';
  if (frac.length > decimals) {
    throw PredictInputError('$s exceeds $decimals decimals');
  }
  final padded = frac.padRight(decimals, '0');
  return BigInt.parse(whole) * BigInt.from(10).pow(decimals) +
      (padded.isEmpty ? BigInt.zero : BigInt.parse(padded));
}

/// Raw→decimal for display. Casts through double, so values above 2^53 raw
/// lose precision in the low digits.
double fromRaw(BigInt raw, int decimals) =>
    raw.toDouble() / math.pow(10, decimals);

/// USDC (6-decimal) human → raw.
BigInt usdcToRaw(Object v) => toRaw(v, 6);

/// USDC raw → human (display).
double rawToUsdc(BigInt raw) => fromRaw(raw, 6);

/// USD price (9-decimal raw) human → raw.
BigInt priceToRaw(Object v) => toRaw(v, 9);

/// USD price raw → human (display).
double rawToPrice(BigInt raw) => fromRaw(raw, 9);

/// Probability in `[0, 1]` → raw 1e9.
BigInt probabilityToRaw(double p) {
  if (p < 0 || p > 1) {
    throw PredictInputError('probability must be in [0,1], got $p');
  }
  return toRaw(p, 9);
}

/// Raw 1e9 probability → `[0, 1]` double (display).
double rawToProbability(BigInt raw) => fromRaw(raw, 9);
