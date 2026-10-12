/// Client-side board pricing, mirroring `predict/pricing.ts`.
///
/// Faithful float port of `deepbook_predict::pricing::compute_nd2` — the
/// SVI-adjusted digital probability, WITH the skew-correction term. It
/// operates on the pricer's ALREADY-RESOLVED forward and ALREADY-ROLLED-DOWN
/// SVI, exactly as `load_live_pricer` returns them (decoded by
/// `reads/pricing.dart`). The two on-chain steps that pick the forward
/// (Pyth-spot vs Block-Scholes, admin flag + freshness) and roll `a`/`b` down
/// by remaining/anchored time already happened on-chain — this module never
/// re-derives them, which is what keeps it faithful.
///
/// This is the fast client-side board pricer: read one `Pricer` snapshot,
/// then price every strike locally with no further chain calls. `read.price`
/// / `read.quoteMint` (a chain dry-run) stay the authoritative quote at trade
/// time. Divergence vs the chain is up to ~1e-4 in probability, dominated by
/// the chain's fixed-point truncation near ATM when sigma sits at its floor
/// (float64 here is the more precise side, not the less); negligible for
/// display.
///
/// The on-chain formula (pricing/pricing.move `compute_nd2`):
/// ```text
///   k  = ln(strike / forward)
///   x  = k - m
///   w  = a + b·(ρ·x + √(x² + σ²))              // a, b already rolled down
///   d2 = −(k + w/2) / √w                       // clamped to ±8
///   w′ = b·(ρ + x/√(x² + σ²))                  // SVI slope
///   price = N(d2) − φ(d2)·w′ / (2·√w)          // skew correction, clamped [0,1]
/// ```
library;

import 'dart:math' as math;

import 'errors.dart';

/// Rolled-down SVI parameters for one expiry, in decimal (NOT the chain's
/// 1e9/1e18 integer scaling) — the surface AFTER Predict's remaining-time
/// roll-down, as carried by the on-chain `Pricer`. [a], [rho], [m] are
/// signed; [b], [sigma] are non-negative.
class Svi {
  final double a;
  final double b;
  final double rho;
  final double m;
  final double sigma;

  const Svi({
    required this.a,
    required this.b,
    required this.rho,
    required this.m,
    required this.sigma,
  });
}

/// A resolved pricer snapshot: the forward the contract prices against and
/// its rolled SVI surface, both in decimal. Produced by
/// `read.pricer(market)`; consume via [boardPricer] or the pure functions
/// below.
class PricerInputs {
  /// Forward price the digital settles against, in decimal (same units as
  /// `strike`).
  final double forward;
  final Svi svi;

  const PricerInputs({required this.forward, required this.svi});
}

/// Standard normal CDF via erf (Abramowitz–Stegun 7.1.26, |err| < 1.5e-7).
double _normalCdf(double x) => 0.5 * (1 + _erf(x / math.sqrt2));

/// Standard normal PDF.
double _normalPdf(double x) => math.exp(-0.5 * x * x) / math.sqrt(2 * math.pi);

double _erf(double x) {
  final sign = x >= 0 ? 1.0 : -1.0;
  final ax = x.abs();
  final t = 1 / (1 + 0.3275911 * ax);
  final y = 1 -
      ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) *
                  t +
              0.254829592) *
          t *
          math.exp(-ax * ax);
  return sign * y;
}

// Clamp |d2| at 8, matching the chain (`normal_cdf`/`normal_pdf` saturate
// beyond that).
double _clampD2(double d2) => d2 > 8
    ? 8
    : d2 < -8
        ? -8
        : d2;

/// P(settle > strike) — the UP digital, with the SVI skew correction.
/// `inputs.svi` is the already-rolled surface (no roll-down applied here).
/// [strike] shares units with `inputs.forward`. Returns a probability in
/// `[0, 1]`.
double upProbability(PricerInputs inputs, double strike) {
  final forward = inputs.forward;
  final svi = inputs.svi;
  if (!(forward > 0)) return 0;
  if (strike <= 0) return 1; // neg-inf limit
  final k = math.log(strike / forward);
  final km = k - svi.m;
  final root = math.sqrt(km * km + svi.sigma * svi.sigma);
  final inner = svi.rho * km + root; // >= 0 for |rho| <= 1
  final w = svi.a + svi.b * inner; // total variance
  // The chain guarantees w > 0 at every strike
  // (assert_min_total_variance_positive at load time), so this branch is
  // unreachable in practice; return the variance→0 tail limit rather than
  // throw, so a UI never crashes on a degenerate snapshot.
  if (w <= 0) return k < 0 ? 1 : 0;
  final sq = math.sqrt(w);
  final d2 = _clampD2(-((k + w / 2) / sq));
  final nd2 = _normalCdf(d2);
  final wPrime = svi.b * (svi.rho + km / root); // SVI slope × b
  final price = nd2 - (_normalPdf(d2) * wPrime) / (2 * sq); // skew correction
  return price < 0
      ? 0
      : price > 1
          ? 1
          : price;
}

/// P(settle < strike) — the DOWN digital. Exactly `1 − up`, matching the
/// chain's `range_price(-inf, strike] = up(-inf) − up(strike) = 1 − up`.
double downProbability(PricerInputs inputs, double strike) =>
    1 - upProbability(inputs, strike);

/// Probability mass in `(lower, higher]`, floored at 0 (matches
/// `compute_range_price`'s saturating subtraction). Use `lower <= 0` for the
/// −∞ bound and `higher = double.infinity` for +∞.
double rangeProbability(PricerInputs inputs, double lower, double higher) {
  // up(lower) − up(higher), where up(+inf) = 0 and up(<= 0) = 1.
  final upLower = lower <= 0 ? 1.0 : upProbability(inputs, lower);
  final upHigher =
      higher == double.infinity ? 0.0 : upProbability(inputs, higher);
  final d = upLower - upHigher;
  return d < 0 ? 0 : d;
}

/// Binary probability at [strike] for the given side (`'up'` = P(>strike),
/// `'down'` = 1 − up).
double probability(PricerInputs inputs, double strike, String side) {
  // Anything not exactly 'up'/'down' must throw rather than silently price
  // the DOWN side: `side` arrives from UI state, JSON, or a DB column at
  // runtime, where a type alone does not protect (same guard as
  // `binaryRangeTicks`).
  if (side != 'up' && side != 'down') {
    throw PredictInputError("side must be 'up' or 'down', got '$side'");
  }
  final up = upProbability(inputs, strike);
  return side == 'up' ? up : 1 - up;
}

/// Strike where P(settle > strike) = [p], by bisection (UP is
/// monotone-decreasing in strike). Null when no crossing exists within ±64%
/// of forward.
double? strikeAtProbability(PricerInputs inputs, double p) {
  final forward = inputs.forward;
  if (!(forward > 0) || !(p > 0 && p < 1)) return null;
  double up(double strike) => upProbability(inputs, strike);
  var r = 0.01;
  while (up(forward * (1 - r)) < p || up(forward * (1 + r)) > p) {
    r *= 2;
    if (r > 0.64) return null;
  }
  var lo = forward * (1 - r);
  var hi = forward * (1 + r);
  for (var i = 0; i < 64; i++) {
    final mid = (lo + hi) / 2;
    if (up(mid) > p) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

// --- Resolving raw feed data client-side (for consumers that hold their own
// live oracle feed and want to price with NO chain call). The turnkey path is
// `read.pricer(market)`, which reads these already resolved from the chain's
// `Pricer`; these two helpers reproduce the on-chain resolution when you'd
// rather not read the chain.

/// Roll `a` and `b` down by the fraction of anchored time remaining, matching
/// the chain's `roll_down_svi` (variance decays toward expiry). [remainingMs]
/// = expiry − now; [anchorTteMs] = expiry − the SVI observation's provider
/// `svi_timestamp` (its per-update source timestamp) — the same clock the
/// freshness gate accepts, and what the chain anchors on. Anchoring on the
/// batch's ingestion time instead rolls by the wrong fraction. `read.pricer`
/// avoids the question entirely (the chain has already rolled). `rho`, `m`,
/// `sigma` are unchanged. Feed an UNrolled provider surface; the result is
/// what [upProbability] expects.
Svi rollDown(Svi svi, double remainingMs, double anchorTteMs) {
  final frac = anchorTteMs > 0 ? remainingMs / anchorTteMs : 0.0;
  return Svi(
      a: svi.a * frac,
      b: svi.b * frac,
      rho: svi.rho,
      m: svi.m,
      sigma: svi.sigma);
}

/// The forward the contract prices against: Pyth spot re-anchored by the
/// Block-Scholes basis (`spot · forward/bsSpot`), falling back to the
/// Block-Scholes forward when Pyth is absent. Pass `pythSpot <= 0` to force
/// the fallback. NOTE: on-chain this branch is also gated by the admin flag
/// `use_pyth_spot_for_forward` (default on) and a Pyth freshness window —
/// when the flag is off or the Pyth spot is stale, the chain uses
/// [bsForward]. If you track that config/freshness, apply it before calling
/// (or use `read.pricer`, which gets the resolved forward from the chain).
double forward(double pythSpot, double bsSpot, double bsForward) {
  if (pythSpot > 0 && bsSpot > 0) return pythSpot * (bsForward / bsSpot);
  return bsForward;
}

/// A pricer bound to one resolved snapshot: price a whole board of strikes
/// locally, no chain calls. Returned by `read.pricer(market)`; also
/// constructable directly from inputs you already hold (e.g. from a `Pricer`
/// snapshot decoded elsewhere).
class BoardPricer extends PricerInputs {
  const BoardPricer({required super.forward, required super.svi});

  /// P(settle > strike).
  double up(double strike) => upProbability(this, strike);

  /// P(settle < strike) = 1 − up.
  double down(double strike) => downProbability(this, strike);

  /// P(side wins at strike).
  double probabilityOf(double strike, String side) =>
      probability(this, strike, side);

  /// Probability mass in `(lower, higher]` (use `lower <= 0` /
  /// `higher = double.infinity` for the tails).
  double range(double lower, double higher) =>
      rangeProbability(this, lower, higher);

  /// Strike where P(> strike) = [p], or null if outside ±64% of forward.
  double? strikeAt(double p) => strikeAtProbability(this, p);
}

/// Build a [BoardPricer] from a resolved snapshot (decimal forward + rolled
/// SVI). Pure.
BoardPricer boardPricer(PricerInputs inputs) =>
    BoardPricer(forward: inputs.forward, svi: inputs.svi);
