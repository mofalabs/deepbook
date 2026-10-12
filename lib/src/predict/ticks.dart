/// Strike-tick helpers, mirroring `predict/ticks.ts`.
library;

// ignore_for_file: non_constant_identifier_names

import 'errors.dart';

const int _tickBits = 30;

/// +inf sentinel tick: the upper bound of an UP range.
final BigInt POS_INF_TICK = (BigInt.one << _tickBits) - BigInt.one;

/// A binary position's side. The official SDK types this `'up' | 'down'`
/// (with `'range'` as the range-descriptor arm); Dart keeps the string form
/// so descriptors stay JSON/UI friendly — invalid values are rejected at
/// runtime exactly like the official guard.
typedef Side = String;

/// The `(lowerTick, higherTick)` pair of a range, as the `mint` entrypoint
/// takes directly.
class RangeTicks {
  final BigInt lowerTick;
  final BigInt higherTick;
  const RangeTicks({required this.lowerTick, required this.higherTick});
}

/// Convert a raw binary-range strike to the `(lower_tick, higher_tick)` pair
/// the `mint` entrypoint takes directly (there is no standalone packed range
/// key). An UP order is `(strike, +inf)` → lowerTick = strike/tickSize,
/// higherTick = [POS_INF_TICK]; a DOWN order is `(-inf, strike)` → lowerTick =
/// 0 (neg-inf), higherTick = strike/tickSize.
RangeTicks binaryRangeTicks(BigInt strikeRaw, Side side, BigInt tickSize) {
  // Anything not exactly 'up'/'down' must throw rather than fall through to a
  // byte-identical DOWN mint: `side` arrives from UI state, JSON, or a DB
  // column at runtime, where a type alone does not protect.
  if (side != 'up' && side != 'down') {
    throw PredictInputError("side must be 'up' or 'down', got '$side'");
  }
  final tick = strikeRaw ~/ tickSize;
  if (tick * tickSize != strikeRaw) {
    throw PredictInputError(
        'strike $strikeRaw is not a whole tick multiple of $tickSize');
  }
  if (tick <= BigInt.zero || tick >= POS_INF_TICK) {
    throw PredictInputError(
        'strike tick $tick outside the finite tick domain (1..POS_INF_TICK-1)');
  }
  final isUp = side == 'up';
  return RangeTicks(
    lowerTick: isUp ? tick : BigInt.zero,
    higherTick: isUp ? POS_INF_TICK : tick,
  );
}
