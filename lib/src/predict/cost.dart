/// Client-side ALL-IN cost math for Predict trades, mirroring
/// `predict/cost.ts` — the fee layer `pricing.dart` stops short of.
/// `pricing` answers "what is this contract worth?" (the probability); this
/// module answers "what does the chain debit me for it?" and "what does
/// closing it credit me?", with NO chain call: no devInspect, no dry run, no
/// simulate.
///
/// It is an EXACT integer port of the deployed cost path, function for
/// function:
///
///  - mint:   `expiry_market::mint_quote_at` / `compute_mint_quote`
///            → premium + (trading_fee − fee_incentive_subsidy) + builder_fee
///              + penalty_fee + inventory_impact_charge
///  - budget: `expiry_market::quote_exact_cost_terms` (the `mint_exact_cost`
///            lot search)
///  - redeem: `expiry_market::redeem_live`'s payment decomposition
///            → gross + inventory_impact_rebate − trading_fee − builder_fee
///              − penalty
///  - fees:   `strike_exposure_config::trading_fee` (per-boundary Bernoulli
///            fee + expiry ramp), `expiry_market::builder_fee_amount`,
///            `ewma::penalty_fee`,
///            `strike_exposure::mint_range_inventory_impact` /
///            `live_close_inventory_impact`
///
/// Every rounding step is the chain's: `mul_down`, `mul_div_down` and a
/// bit-identical `sqrt_down` (same Newton schedule as `fixed_math::math`),
/// all on [BigInt]s. So given the same inputs the chain uses, these return
/// the chain's numbers to the raw unit — the fee layer carries no
/// approximation of its own.
///
/// Local float probabilities (`upProbability`, ~1e-4) introduce
/// approximation. With raw probabilities AND the same fee, account, book and
/// clock inputs as execution, the arithmetic matches the chain.
/// `exactProbabilities` only identifies the probability input format; it does
/// not certify the source or freshness of any state. A nonzero
/// inventory-impact policy requires book data. Congestion defaults to a zero
/// rate; supply the actual rate when enabled. Use `read.quoteMint` /
/// `read.quoteRedeem` for a simulation against current account and market
/// state, including the execution gates these previews do not check
/// (ownership, pauses, trade window, oracle freshness and cash backing).
///
/// The fee POLICY is a per-market snapshot taken at creation
/// (`StrikeExposureConfig`), and the chain exposes no getter for
/// `base_fee`/`min_fee` — take it from the market's `MarketCreated` event (an
/// indexer, or `decode`), or use [SHIPPED_FEE_POLICY] for the shipped
/// template.
library;

// Official constant names kept verbatim so code ports line for line.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'errors.dart';
import 'pricing.dart';
import 'ticks.dart' show POS_INF_TICK;
import 'units.dart' show U64_MAX, fromRaw, usdcToRaw;

export 'ticks.dart' show POS_INF_TICK;

// === Protocol constants (mirrors of `deepbook_predict::constants` /
// `fixed_math::math`) ===

/// `math::float_scaling` — 1e9 is 1.0 for every rate and probability here.
final BigInt FLOAT_SCALING = BigInt.from(1000000000);

/// `constants::position_lot_size` — quantity is an integer number of these.
///
/// NOTE: the official SDK also exports a `POSITION_LOT_SIZE` from its package
/// root (testnet's deployed value, a caller convenience); Dart names that one
/// `TESTNET_POSITION_LOT_SIZE` — this is the Move constant.
final BigInt POSITION_LOT_SIZE = BigInt.from(10000);

/// `constants::min_premium` — a mint below this premium aborts
/// `EPremiumBelowMinimum`.
final BigInt MIN_PREMIUM = BigInt.from(1000000);

/// `constants::builder_fee_multiplier` — the builder's cut of the trading fee
/// (10%).
final BigInt BUILDER_FEE_MULTIPLIER = BigInt.from(100000000);

/// `constants::max_builder_fee_rate` — cap on the builder fee as a share of
/// quantity (0.5%).
final BigInt MAX_BUILDER_FEE_RATE = BigInt.from(5000000);

/// `constants::fee_incentive_subsidy_rate` — sponsor share of a trader's mint
/// fee (20%).
final BigInt FEE_INCENTIVE_SUBSIDY_RATE = BigInt.from(200000000);

/// `order::max_quantity_lots` — the order ID's 32-bit lot field.
final BigInt MAX_QUANTITY_LOTS = (BigInt.one << 32) - BigInt.one;

// === Fixed-point primitives (mirrors of `fixed_math::math`) ===

BigInt _mulDown(BigInt x, BigInt y) => (x * y) ~/ FLOAT_SCALING;
BigInt _divDown(BigInt x, BigInt y) => (x * FLOAT_SCALING) ~/ y;
BigInt _mulDivDown(BigInt x, BigInt y, BigInt denominator) =>
    (x * y) ~/ denominator;
BigInt _min(BigInt a, BigInt b) => a < b ? a : b;
BigInt _max(BigInt a, BigInt b) => a > b ? a : b;

// Move's unsigned types enforce these domains before arithmetic. Dart BigInt
// does not.
void _assertUint(BigInt value, String name,
    {BigInt? maximum, BigInt? minimum}) {
  final maxv = maximum ?? U64_MAX;
  final minv = minimum ?? BigInt.zero;
  if (value < minv || value > maxv) {
    throw PredictInputError(
        '$name must be an integer in [$minv, $maxv], got $value');
  }
}

// `math::sqrt_initial_guess_u128` — power-of-two seed for the Newton
// iteration.
BigInt _sqrtInitialGuess(BigInt x) {
  var bits = BigInt.zero;
  var val = x;
  if (val >= BigInt.one << 64) {
    val >>= 64;
    bits += BigInt.from(64);
  }
  if (val >= BigInt.one << 32) {
    val >>= 32;
    bits += BigInt.from(32);
  }
  if (val >= BigInt.one << 16) {
    val >>= 16;
    bits += BigInt.from(16);
  }
  if (val >= BigInt.one << 8) {
    val >>= 8;
    bits += BigInt.from(8);
  }
  if (val >= BigInt.one << 4) {
    val >>= 4;
    bits += BigInt.from(4);
  }
  if (val >= BigInt.one << 2) {
    val >>= 2;
    bits += BigInt.two;
  }
  if (val >= BigInt.two) bits += BigInt.one;
  return BigInt.one << ((bits + BigInt.one) ~/ BigInt.two).toInt();
}

// `math::sqrt_u128_down` — seven Newton steps then one correcting decrement,
// exactly as the chain runs them, so this agrees with the contract raw unit
// for raw unit rather than merely to within a rounding step.
BigInt _sqrtU128Down(BigInt x) {
  if (x == BigInt.zero) return BigInt.zero;
  if (x < BigInt.from(4)) return BigInt.one;
  var g = _sqrtInitialGuess(x);
  for (var i = 0; i < 7; i++) {
    g = (g + x ~/ g) ~/ BigInt.two;
  }
  if (g > x ~/ g) g -= BigInt.one;
  return g;
}

/// `math::sqrt_down` — square root of a 1e9-scaled value, 1e9-scaled, rounded
/// down.
BigInt sqrtDown(BigInt x) {
  _assertUint(x, 'sqrt input');
  return _sqrtU128Down(x * FLOAT_SCALING);
}

// === Policy and state inputs ===

/// One market's fee policy: the `StrikeExposureConfig` it snapshotted at
/// creation, in raw 1e9 rates. Snapshotted means later admin changes do NOT
/// reprice a market already trading, so read it per market (the
/// `MarketCreated` event carries every field) rather than assuming the
/// template. The last three are the inventory-impact parameters, inert while
/// [inventoryImpactMaxRate] is zero (the shipped value).
class FeePolicy {
  /// `base_fee` — multiplies `sqrt(p·(1−p))`.
  final BigInt baseFee;

  /// `min_fee` — per-unit floor, applied per boundary leg before the ramp.
  final BigInt minFee;

  /// `expiry_fee_window_ms` — window before expiry over which the fee ramps.
  final BigInt expiryFeeWindowMs;

  /// `expiry_fee_max_multiplier` — multiplier reached at expiry; 1e9 disables
  /// the ramp.
  final BigInt expiryFeeMaxMultiplier;

  /// `min_entry_probability` — mint admission floor on the entry probability.
  final BigInt minEntryProbability;

  /// `max_entry_probability` — mint admission ceiling on the entry
  /// probability.
  final BigInt maxEntryProbability;

  /// `inventory_impact_max_rate` — maximum marginal impact rate; zero
  /// disables impact.
  final BigInt inventoryImpactMaxRate;

  /// `inventory_impact_scale` — the market's `max_expiry_allocation`, the
  /// curve's `B`.
  final BigInt inventoryImpactScale;

  /// `backing_buffer_lambda` — the buffer on non-peak payout in the liability
  /// formula.
  final BigInt backingBufferLambda;

  const FeePolicy({
    required this.baseFee,
    required this.minFee,
    required this.expiryFeeWindowMs,
    required this.expiryFeeMaxMultiplier,
    required this.minEntryProbability,
    required this.maxEntryProbability,
    required this.inventoryImpactMaxRate,
    required this.inventoryImpactScale,
    required this.backingBufferLambda,
  });
}

/// The shipped template (`config_constants` defaults): 10% Bernoulli fee, a
/// 2.2% per-leg floor, a one-day ramp window that is inert at a 1.0
/// multiplier, a 1%–99% entry band, and inventory impact disabled. A market
/// created under these values charges exactly this; one created after an
/// admin change does not, which is why the per-market snapshot is the real
/// answer. Verify against the deployment's `MarketCreated` before pricing
/// money on it.
final FeePolicy SHIPPED_FEE_POLICY = FeePolicy(
  baseFee: BigInt.from(100000000),
  minFee: BigInt.from(22000000),
  expiryFeeWindowMs: BigInt.from(86400000),
  expiryFeeMaxMultiplier: FLOAT_SCALING,
  minEntryProbability: BigInt.from(10000000),
  maxEntryProbability: BigInt.from(990000000),
  inventoryImpactMaxRate: BigInt.zero,
  inventoryImpactScale: BigInt.zero,
  backingBufferLambda: BigInt.from(310000000),
);

/// Where a quote's probabilities come from: [Boundaries] you already hold
/// (raw 1e9), or a [PricerBoundaries] — a local pricer snapshot plus the
/// range's strikes in USD (null for an infinite side).
sealed class ProbabilitySource {
  const ProbabilitySource();
}

/// A range's two boundary UP probabilities, raw 1e9. Null is an infinite
/// boundary — the −∞ lower of a DOWN order and the +∞ higher of an UP order —
/// which is priced at the digital limit and pays no fee leg.
class Boundaries extends ProbabilitySource {
  /// `P(settle > lower)`, or null for the −∞ lower bound.
  final BigInt? lowerUp;

  /// `P(settle > higher)`, or null for the +∞ higher bound.
  final BigInt? higherUp;

  const Boundaries({required this.lowerUp, required this.higherUp});
}

/// A local pricer snapshot plus the range's strikes in USD (null for an
/// infinite side) — carries the float pricer's ~1e-4 approximation.
class PricerBoundaries extends ProbabilitySource {
  final PricerInputs pricer;

  /// Lower strike in USD, or null for −∞.
  final double? lower;

  /// Upper strike in USD, or null for +∞.
  final double? upper;

  const PricerBoundaries(
      {required this.pricer, required this.lower, required this.upper});
}

/// The market's gas-price EWMA (`ewma::EwmaState`), both fields 1e9-scaled.
class CongestionState {
  final BigInt mean;
  final BigInt variance;
  const CongestionState({required this.mean, required this.variance});
}

/// The protocol's congestion knobs (`EwmaConfig`). Shipped disabled.
class CongestionPolicy {
  final bool enabled;

  /// `penalty_rate` — per-unit surcharge charged when the z-score fires.
  final BigInt penaltyRate;

  /// `z_score_threshold` — how many standard deviations above the mean gas
  /// must sit.
  final BigInt zScoreThreshold;

  const CongestionPolicy({
    required this.enabled,
    required this.penaltyRate,
    required this.zScoreThreshold,
  });
}

/// Pre-trade payout-tree reads a mint's inventory-impact charge is evaluated
/// against (`strike_exposure::quote_mint_range`). All in quote units.
class MintBookTerms {
  /// `M` — largest summed net payout at any one settlement price.
  final BigInt maxPayout;

  /// `T` — sum of every live order's payout.
  final BigInt totalPayout;

  /// The payout peak inside the mint's own `(lower, higher]`.
  final BigInt rangeMaxPayout;

  const MintBookTerms({
    required this.maxPayout,
    required this.totalPayout,
    required this.rangeMaxPayout,
  });
}

/// The same reads for a live close, which also needs the peak OUTSIDE the
/// order's range (`strike_exposure::live_close_inventory_impact`).
class CloseBookTerms extends MintBookTerms {
  /// The payout peak in the complement of the order's range.
  final BigInt complementMaxPayout;

  const CloseBookTerms({
    required super.maxPayout,
    required super.totalPayout,
    required super.rangeMaxPayout,
    required this.complementMaxPayout,
  });
}

void _assertFeePolicy(FeePolicy policy) {
  _assertUint(policy.baseFee, 'baseFee', maximum: FLOAT_SCALING);
  _assertUint(policy.minFee, 'minFee', maximum: FLOAT_SCALING);
  _assertUint(policy.expiryFeeWindowMs, 'expiryFeeWindowMs',
      minimum: BigInt.one);
  _assertUint(policy.expiryFeeMaxMultiplier, 'expiryFeeMaxMultiplier',
      maximum: BigInt.from(10) * FLOAT_SCALING, minimum: FLOAT_SCALING);
  _assertUint(policy.minEntryProbability, 'minEntryProbability',
      maximum: FLOAT_SCALING);
  _assertUint(policy.maxEntryProbability, 'maxEntryProbability',
      maximum: FLOAT_SCALING);
  if (policy.minEntryProbability >= policy.maxEntryProbability) {
    throw PredictInputError(
        'minEntryProbability must be below maxEntryProbability');
  }
  _assertUint(policy.inventoryImpactMaxRate, 'inventoryImpactMaxRate',
      maximum: FLOAT_SCALING);
  _assertUint(policy.backingBufferLambda, 'backingBufferLambda',
      maximum: FLOAT_SCALING);
  _assertUint(policy.inventoryImpactScale, 'inventoryImpactScale',
      minimum: policy.inventoryImpactMaxRate == BigInt.zero
          ? BigInt.zero
          : BigInt.one);
}

void _assertBoundaries(Boundaries boundaries) {
  final lower = boundaries.lowerUp;
  if (lower != null) _assertUint(lower, 'lowerUp', maximum: FLOAT_SCALING);
  final higher = boundaries.higherUp;
  if (higher != null) _assertUint(higher, 'higherUp', maximum: FLOAT_SCALING);
}

void _assertBook(MintBookTerms book) {
  _assertUint(book.totalPayout, 'totalPayout');
  _assertUint(book.maxPayout, 'maxPayout', maximum: book.totalPayout);
  _assertUint(book.rangeMaxPayout, 'rangeMaxPayout', maximum: book.maxPayout);
}

void _assertCostInputs(
    FeePolicy fees, MintBookTerms? book, BigInt? penaltyRate, BigInt? lotSize) {
  _assertFeePolicy(fees);
  _assertUint(penaltyRate ?? BigInt.zero, 'penaltyRate',
      maximum: FLOAT_SCALING);
  _assertUint(lotSize ?? POSITION_LOT_SIZE, 'lotSize',
      maximum: U64_MAX ~/ MAX_QUANTITY_LOTS, minimum: BigInt.one);
  if (fees.inventoryImpactMaxRate > BigInt.zero && book == null) {
    throw PredictInputError(
        'book is required when inventory impact is enabled');
  }
  if (book != null) _assertBook(book);
}

// === Fee components ===

/// `strike_exposure_config::raw_bernoulli_fee_rate` — `base_fee ·
/// sqrt(p·(1−p))`, the fee rate before the `min_fee` floor and the expiry
/// ramp. Zero at the certain ends.
BigInt bernoulliFeeRate(BigInt baseFee, BigInt probability) {
  _assertUint(baseFee, 'baseFee', maximum: FLOAT_SCALING);
  _assertUint(probability, 'probability (EInvalidFeeProbability)',
      maximum: FLOAT_SCALING);
  if (probability == BigInt.zero || probability == FLOAT_SCALING) {
    return BigInt.zero;
  }
  return _mulDown(
      baseFee, sqrtDown(_mulDown(probability, FLOAT_SCALING - probability)));
}

/// `strike_exposure_config::expiry_fee_multiplier` — 1.0 outside the window,
/// rising linearly to `expiry_fee_max_multiplier` at expiry.
BigInt expiryFeeMultiplier(FeePolicy policy, BigInt timeToExpiryMs) {
  _assertFeePolicy(policy);
  _assertUint(timeToExpiryMs, 'timeToExpiryMs');
  if (timeToExpiryMs >= policy.expiryFeeWindowMs) return FLOAT_SCALING;
  return FLOAT_SCALING +
      _mulDivDown(
        policy.expiryFeeMaxMultiplier - FLOAT_SCALING,
        policy.expiryFeeWindowMs - timeToExpiryMs,
        policy.expiryFeeWindowMs,
      );
}

// `strike_exposure_config::leg_trading_fee` — one finite boundary's fee,
// floored then ramped, rounded down at each step.
BigInt _legTradingFee(FeePolicy policy, BigInt probability, BigInt quantity,
    BigInt timeToExpiryMs) {
  final base =
      _max(bernoulliFeeRate(policy.baseFee, probability), policy.minFee);
  return _mulDown(
      _mulDown(base, expiryFeeMultiplier(policy, timeToExpiryMs)), quantity);
}

/// `strike_exposure_config::trading_fee` — the fee for a whole range, charged
/// PER FINITE BOUNDARY with each leg floored and ramped independently. A
/// binary order has one finite boundary and pays one leg; a two-sided range
/// pays two, so it is not the same fee as the range's own probability would
/// suggest.
BigInt tradingFee(FeePolicy policy, Boundaries boundaries, BigInt quantity,
    BigInt timeToExpiryMs) {
  _assertFeePolicy(policy);
  _assertBoundaries(boundaries);
  _assertUint(quantity, 'quantity');
  _assertUint(timeToExpiryMs, 'timeToExpiryMs');
  final lowerUp = boundaries.lowerUp;
  final higherUp = boundaries.higherUp;
  final lower = lowerUp == null
      ? BigInt.zero
      : _legTradingFee(policy, lowerUp, quantity, timeToExpiryMs);
  final higher = higherUp == null
      ? BigInt.zero
      : _legTradingFee(policy, higherUp, quantity, timeToExpiryMs);
  return lower + higher;
}

/// `expiry_market::builder_fee_amount` — an account carrying a builder code
/// pays the builder a multiple of its trading fee, capped as a share of
/// quantity.
BigInt builderFee(BigInt fee, BigInt quantity, bool hasBuilderCode) {
  _assertUint(fee, 'fee');
  _assertUint(quantity, 'quantity');
  if (!hasBuilderCode) return BigInt.zero;
  return _min(_mulDown(fee, BUILDER_FEE_MULTIPLIER),
      _mulDown(quantity, MAX_BUILDER_FEE_RATE));
}

/// `expiry_market::fee_incentive_subsidy_amount` — a sponsor pays part of the
/// trader's MINT fee, bounded by the expiry's remaining sponsored balance.
/// Mints only; redeems pay in full.
BigInt feeIncentiveSubsidy(BigInt fee, BigInt feeIncentiveBalance) {
  _assertUint(fee, 'fee');
  _assertUint(feeIncentiveBalance, 'feeIncentiveBalance');
  return _min(_mulDown(fee, FEE_INCENTIVE_SUBSIDY_RATE), feeIncentiveBalance);
}

/// `ewma::penalty_fee`'s firing test, as a per-unit RATE: `penalty_rate` when
/// the transaction's gas price is a high outlier against the market's
/// pre-trade EWMA, else zero. It is a rate and not an amount because the
/// surcharge is `rate · quantity`, and a budget search has to reprice it at
/// every candidate quantity. [gasPrice] is the raw reference gas price (not
/// 1e9-scaled), as `tx_context::gas_price` reports it.
BigInt congestionPenaltyRate(
    CongestionPolicy policy, CongestionState state, BigInt gasPrice) {
  _assertUint(policy.penaltyRate, 'penaltyRate', maximum: FLOAT_SCALING);
  _assertUint(policy.zScoreThreshold, 'zScoreThreshold');
  _assertUint(state.mean, 'mean');
  _assertUint(state.variance, 'variance');
  _assertUint(gasPrice, 'gasPrice', maximum: U64_MAX ~/ FLOAT_SCALING);
  if (!policy.enabled || state.variance == BigInt.zero) return BigInt.zero;
  final scaled = gasPrice * FLOAT_SCALING;
  if (scaled <= state.mean) return BigInt.zero;
  final zScore = _divDown(scaled - state.mean, sqrtDown(state.variance));
  if (zScore <= policy.zScoreThreshold) return BigInt.zero;
  return policy.penaltyRate;
}

// `strike_exposure::live_payout_liability_from_terms` — `M + lambda·(T − M)`.
BigInt _payoutLiability(
        FeePolicy policy, BigInt maxPayout, BigInt totalPayout) =>
    maxPayout + _mulDown(policy.backingBufferLambda, totalPayout - maxPayout);

/// `strike_exposure::inventory_impact_potential_for_liability` — the
/// book-level potential `phi(L)`: marginal rate rising linearly to
/// `inventory_impact_max_rate` over the scale `B`, flat at the cap above it.
/// Trades are charged the DIFFERENCE of two evaluations, which is what makes
/// inventory cycles telescope to zero.
BigInt inventoryImpactPotential(FeePolicy policy, BigInt liability) {
  _assertFeePolicy(policy);
  _assertUint(liability, 'liability');
  if (policy.inventoryImpactMaxRate == BigInt.zero ||
      liability == BigInt.zero) {
    return BigInt.zero;
  }
  final scale = policy.inventoryImpactScale;
  final capped = _min(liability, scale);
  final utilization = _mulDivDown(capped, FLOAT_SCALING, scale);
  final marginalRate = _mulDown(policy.inventoryImpactMaxRate, utilization);
  final potentialAtCapped = _mulDown(marginalRate, capped) ~/ BigInt.two;
  if (liability <= scale) return potentialAtCapped;
  return potentialAtCapped +
      _mulDown(policy.inventoryImpactMaxRate, liability - scale);
}

/// `strike_exposure::mint_range_inventory_impact` — the charge a mint of
/// [quantity] over a range pays: the exact rise in the book potential. Zero
/// at the shipped rate of zero.
BigInt mintInventoryImpact(
    FeePolicy policy, MintBookTerms book, BigInt quantity) {
  _assertFeePolicy(policy);
  _assertBook(book);
  _assertUint(quantity, 'quantity', maximum: U64_MAX - book.totalPayout);
  if (policy.inventoryImpactMaxRate == BigInt.zero || quantity == BigInt.zero) {
    return BigInt.zero;
  }
  final before = _payoutLiability(policy, book.maxPayout, book.totalPayout);
  final after = _payoutLiability(
    policy,
    _max(book.maxPayout, book.rangeMaxPayout + quantity),
    book.totalPayout + quantity,
  );
  return inventoryImpactPotential(policy, after) -
      inventoryImpactPotential(policy, before);
}

/// `strike_exposure::live_close_inventory_impact` — the rebate a live close
/// of [payout] receives: the exact fall in the same potential. Zero at the
/// shipped rate of zero.
BigInt closeInventoryImpact(
    FeePolicy policy, CloseBookTerms book, BigInt payout) {
  _assertFeePolicy(policy);
  _assertBook(book);
  _assertUint(book.complementMaxPayout, 'complementMaxPayout',
      maximum: book.maxPayout);
  if (_max(book.rangeMaxPayout, book.complementMaxPayout) != book.maxPayout) {
    throw PredictInputError(
        'maxPayout must equal the larger range or complement payout');
  }
  _assertUint(payout, 'close payout', maximum: book.rangeMaxPayout);
  if (policy.inventoryImpactMaxRate == BigInt.zero || payout == BigInt.zero) {
    return BigInt.zero;
  }
  final before = _payoutLiability(policy, book.maxPayout, book.totalPayout);
  final after = _payoutLiability(
    policy,
    _max(book.rangeMaxPayout - payout, book.complementMaxPayout),
    book.totalPayout - payout,
  );
  return inventoryImpactPotential(policy, before) -
      inventoryImpactPotential(policy, after);
}

// === Probabilities ===

/// `pricing::probability` — the range's own probability, `up(lower) −
/// up(higher)` with the chain's saturating subtraction and its
/// infinite-boundary defaults.
///
/// Named with the `Raw` suffix (official: `cost.rangeProbability`) because
/// Dart exports this module flat and `pricing.dart` owns the float
/// `rangeProbability`.
BigInt rangeProbabilityRaw(Boundaries boundaries) {
  _assertBoundaries(boundaries);
  final lower = boundaries.lowerUp ?? FLOAT_SCALING;
  final higher = boundaries.higherUp ?? BigInt.zero;
  return lower > higher ? lower - higher : BigInt.zero;
}

// Float probability → the chain's raw 1e9 domain, clamped like
// `compute_nd2`'s own clamp.
BigInt _toRawProbability(double p) {
  if (!p.isFinite) {
    throw PredictInputError('probability is not finite: $p');
  }
  final raw = BigInt.from((p * FLOAT_SCALING.toDouble()).roundToDouble());
  return raw < BigInt.zero
      ? BigInt.zero
      : raw > FLOAT_SCALING
          ? FLOAT_SCALING
          : raw;
}

/// Price a range's two boundaries with the local float pricer.
/// [lower]/[upper] are strikes in USD; pass null for an infinite side
/// (`lower: strike, upper: null` is an UP order, `lower: null, upper: strike`
/// a DOWN order). Carries the pricer's ~1e-4 approximation.
Boundaries boundaryProbabilities(
    PricerInputs pricer, double? lower, double? upper) {
  return Boundaries(
    lowerUp:
        lower == null ? null : _toRawProbability(upProbability(pricer, lower)),
    higherUp:
        upper == null ? null : _toRawProbability(upProbability(pricer, upper)),
  );
}

({Boundaries boundaries, bool exact}) _resolveBoundaries(
    ProbabilitySource source) {
  Boundaries boundaries;
  bool exact;
  switch (source) {
    case PricerBoundaries(:final pricer, :final lower, :final upper):
      if (lower != null && upper != null && lower >= upper) {
        throw PredictInputError(
            'lower strike $lower must be below $upper (EInvalidRange)');
      }
      boundaries = boundaryProbabilities(pricer, lower, upper);
      exact = false;
    case Boundaries():
      boundaries = source;
      exact = true;
  }
  _assertBoundaries(boundaries);
  // `(-inf, +inf]` is the whole outcome space; `order::assert_valid_order_shape`
  // rejects it.
  if (boundaries.lowerUp == null && boundaries.higherUp == null) {
    throw PredictInputError(
        'a range cannot be infinite on both sides (EInvalidRange)');
  }
  return (boundaries: boundaries, exact: exact);
}

// A [num] is a human amount in USDC decimals, a [BigInt] is already raw — the
// SDK-wide convention for every financial parameter.
BigInt _rawAmount(Object value) {
  final raw = value is BigInt ? value : usdcToRaw(value);
  _assertUint(raw, 'amount');
  return raw;
}

BigInt _rawMs(Object value) {
  final BigInt raw;
  if (value is BigInt) {
    raw = value;
  } else if (value is int) {
    raw = BigInt.from(value);
  } else {
    throw PredictInputError(
        'timestamp must be an integer in milliseconds, got $value');
  }
  _assertUint(raw, 'timestamp');
  return raw;
}

// === Mint ===

/// Inputs shared by the exact-quantity mint quote and the budget-sized one.
abstract class MintInputsBase {
  /// The market's snapshotted fee policy.
  final FeePolicy fees;

  /// Market expiry, ms since epoch ([int] or [BigInt]).
  final Object expiryMs;

  /// The clock the trade will price against, ms since epoch. Defaults to the
  /// current wall clock.
  final Object? nowMs;

  /// Boundary probabilities, or a pricer snapshot plus the range's strikes.
  final ProbabilitySource probabilities;

  /// Whether the minting account carries a builder code (it pays the builder
  /// fee).
  final bool builderCode;

  /// The expiry's remaining sponsored fee balance (`fee_incentive_balance`).
  /// A [num] is human USDC, a [BigInt] raw. Default zero.
  final Object? feeIncentiveBalance;

  /// Per-unit congestion surcharge rate — see [congestionPenaltyRate].
  /// Default zero.
  final BigInt? penaltyRate;

  /// Pre-trade payout-tree terms. Required when inventory impact is enabled.
  final MintBookTerms? book;

  /// The deployment's `position_lot_size`. Defaults to the Move constant,
  /// 10 000.
  final BigInt? lotSize;

  const MintInputsBase({
    required this.fees,
    required this.expiryMs,
    this.nowMs,
    required this.probabilities,
    this.builderCode = false,
    this.feeIncentiveBalance,
    this.penaltyRate,
    this.book,
    this.lotSize,
  });
}

/// Inputs for [mintCost]: an exact payout quantity.
class MintCostInputs extends MintInputsBase {
  /// Maximum payout bought, in quote units — a [num] is human USD, a [BigInt]
  /// is raw.
  final Object quantity;

  const MintCostInputs({
    required super.fees,
    required super.expiryMs,
    super.nowMs,
    required super.probabilities,
    super.builderCode,
    super.feeIncentiveBalance,
    super.penaltyRate,
    super.book,
    super.lotSize,
    required this.quantity,
  });
}

/// Inputs for [mintCostForBudget]: an all-in budget, the `mint_exact_cost`
/// shape.
class MintBudgetInputs extends MintInputsBase {
  /// The total to spend, fees included.
  final Object budget;

  /// Floor on the fill; a smaller result aborts, as `mint_exact_cost` does.
  /// Default one lot.
  final Object? minQuantity;

  /// The account's settled USDC. The chain caps the budget at it before
  /// sizing; pass it to reproduce that cap (and to let [U64_MAX] mean "my
  /// whole balance").
  final Object? accountBalance;

  const MintBudgetInputs({
    required super.fees,
    required super.expiryMs,
    super.nowMs,
    required super.probabilities,
    super.builderCode,
    super.feeIncentiveBalance,
    super.penaltyRate,
    super.book,
    super.lotSize,
    required this.budget,
    this.minQuantity,
    this.accountBalance,
  });
}

/// One mint's fee decomposition in human units.
class MintFees {
  final double trading;
  final double subsidy;
  final double builder;
  final double penalty;
  final double impact;
  const MintFees({
    required this.trading,
    required this.subsidy,
    required this.builder,
    required this.penalty,
    required this.impact,
  });
}

/// Exact integer fields of a mint quote.
class MintCostRaw {
  final BigInt quantity;
  final BigInt entryProbability;
  final BigInt premium;
  final BigInt tradingFee;
  final BigInt subsidy;
  final BigInt builderFee;
  final BigInt penaltyFee;
  final BigInt impactCharge;
  final BigInt cost;
  const MintCostRaw({
    required this.quantity,
    required this.entryProbability,
    required this.premium,
    required this.tradingFee,
    required this.subsidy,
    required this.builderFee,
    required this.penaltyFee,
    required this.impactCharge,
    required this.cost,
  });
}

/// One mint's cost decomposition — the fields of the chain's `MintQuote`, in
/// human units with the exact integers alongside. [cost] is the account
/// debit.
class MintCost {
  /// Maximum payout bought (human quote units).
  final double quantity;

  /// Fill price, 0..1 per $1 of payout, before fees.
  final double entryProbability;

  /// Premium into LP backing.
  final double premium;

  /// `referral` is not here: it is a split of protocol proceeds, not a trader
  /// debit.
  final MintFees fees;

  /// All-in account debit: `premium + (trading − subsidy) + builder + penalty
  /// + impact`.
  final double cost;

  /// All-in price per $1 of payout — `cost / quantity`, the number to compare
  /// across venues.
  final double costPerContract;

  /// Maximum payout divided by the all-in debit, including fees.
  final double payoutMultiple;

  final MintCostRaw raw;

  /// True when boundary probabilities were supplied as raw integers rather
  /// than priced locally in float. Does not verify their source, freshness or
  /// the other quote inputs.
  final bool exactProbabilities;

  const MintCost({
    required this.quantity,
    required this.entryProbability,
    required this.premium,
    required this.fees,
    required this.cost,
    required this.costPerContract,
    required this.payoutMultiple,
    required this.raw,
    required this.exactProbabilities,
  });
}

/// Budget-sized mint plus the budget information needed to render an order
/// preview.
class MintBudgetCost extends MintCost {
  /// Requested all-in budget, before the optional account-balance cap.
  final double budget;

  /// Budget after the optional account-balance cap.
  final double effectiveBudget;

  /// Requested budget minus actual cost, including any balance-cap shortfall.
  final double unspentBudget;

  final BigInt rawBudget;
  final BigInt rawEffectiveBudget;
  final BigInt rawUnspentBudget;

  const MintBudgetCost({
    required super.quantity,
    required super.entryProbability,
    required super.premium,
    required super.fees,
    required super.cost,
    required super.costPerContract,
    required super.payoutMultiple,
    required super.raw,
    required super.exactProbabilities,
    required this.budget,
    required this.effectiveBudget,
    required this.unspentBudget,
    required this.rawBudget,
    required this.rawEffectiveBudget,
    required this.rawUnspentBudget,
  });
}

// `strike_exposure_config::assert_mint_probability_policy`, applied where
// `assert_range_mint_probability_policy` applies it: each finite leg and the
// range itself.
void _assertProbabilityPolicy(FeePolicy policy, BigInt probability) {
  if (probability < policy.minEntryProbability ||
      probability > policy.maxEntryProbability) {
    throw PredictInputError(
        'entry probability $probability outside the market\'s '
        '[${policy.minEntryProbability}, ${policy.maxEntryProbability}] '
        'admission band (EEntryProbabilityOutOfBounds)');
  }
}

void _assertRangeMintPolicy(FeePolicy policy, Boundaries boundaries) {
  final lowerUp = boundaries.lowerUp;
  if (lowerUp != null) _assertProbabilityPolicy(policy, lowerUp);
  final higherUp = boundaries.higherUp;
  if (higherUp != null) {
    _assertProbabilityPolicy(policy, FLOAT_SCALING - higherUp);
  }
  _assertProbabilityPolicy(policy, rangeProbabilityRaw(boundaries));
}

void _assertValidQuantity(BigInt quantity, BigInt lotSize) {
  if (quantity <= BigInt.zero ||
      quantity % lotSize != BigInt.zero ||
      quantity ~/ lotSize > MAX_QUANTITY_LOTS) {
    throw PredictInputError(
        'quantity $quantity must be a positive multiple of the $lotSize lot '
        'size, at most $MAX_QUANTITY_LOTS lots (EInvalidQuantity)');
  }
}

BigInt _timeToExpiry(BigInt expiryMs, BigInt nowMs) {
  if (nowMs >= expiryMs) {
    throw PredictInputError('market expired at $expiryMs; a live trade at '
        '$nowMs aborts (ELivePricingExpired)');
  }
  return expiryMs - nowMs;
}

// The all-in sum, `expiry_market::mint_quote_at`, with no admission checks —
// the one place the cost is assembled, shared by the quote and the budget
// search exactly as the contract shares it. Rounding order is the chain's:
// every component is floored before it is summed.
({
  BigInt premium,
  BigInt fee,
  BigInt subsidy,
  BigInt builder,
  BigInt penalty,
  BigInt impact,
  BigInt cost,
}) _mintQuoteAt(MintInputsBase inputs, Boundaries boundaries, BigInt quantity,
    BigInt timeToExpiryMs) {
  final premium = _mulDown(rangeProbabilityRaw(boundaries), quantity);
  final fee = tradingFee(inputs.fees, boundaries, quantity, timeToExpiryMs);
  final subsidy = feeIncentiveSubsidy(
      fee, _rawAmount(inputs.feeIncentiveBalance ?? BigInt.zero));
  final builder = builderFee(fee, quantity, inputs.builderCode);
  final penalty = _mulDown(inputs.penaltyRate ?? BigInt.zero, quantity);
  final book = inputs.book;
  final impact = book != null
      ? mintInventoryImpact(inputs.fees, book, quantity)
      : BigInt.zero;
  return (
    premium: premium,
    fee: fee,
    subsidy: subsidy,
    builder: builder,
    penalty: penalty,
    impact: impact,
    cost: premium + (fee - subsidy) + builder + penalty + impact,
  );
}

MintCost _mintCostFrom(MintInputsBase inputs, Boundaries boundaries, bool exact,
    BigInt quantity, BigInt timeToExpiryMs) {
  final q = _mintQuoteAt(inputs, boundaries, quantity, timeToExpiryMs);
  final probability = rangeProbabilityRaw(boundaries);
  return MintCost(
    quantity: fromRaw(quantity, 6),
    entryProbability: fromRaw(probability, 9),
    premium: fromRaw(q.premium, 6),
    fees: MintFees(
      trading: fromRaw(q.fee, 6),
      subsidy: fromRaw(q.subsidy, 6),
      builder: fromRaw(q.builder, 6),
      penalty: fromRaw(q.penalty, 6),
      impact: fromRaw(q.impact, 6),
    ),
    cost: fromRaw(q.cost, 6),
    costPerContract:
        quantity == BigInt.zero ? 0 : q.cost.toDouble() / quantity.toDouble(),
    payoutMultiple: quantity.toDouble() / q.cost.toDouble(),
    raw: MintCostRaw(
      quantity: quantity,
      entryProbability: probability,
      premium: q.premium,
      tradingFee: q.fee,
      subsidy: q.subsidy,
      builderFee: q.builder,
      penaltyFee: q.penalty,
      impactCharge: q.impact,
      cost: q.cost,
    ),
    exactProbabilities: exact,
  );
}

/// All-in cost of minting an exact payout quantity — the
/// `mint_exact_quantity` shape, priced entirely client-side. Mirrors
/// `compute_mint_quote`, including its admission checks: the
/// entry-probability band on each finite leg and on the range, the
/// `min_premium` floor, the lot grid, and the `all_in_cost <= quantity` bound
/// (a contract may never cost more than it can pay out). Each violation
/// throws the [PredictInputError] naming the abort the chain would have
/// raised.
MintCost mintCost(MintCostInputs inputs) {
  _assertCostInputs(
      inputs.fees, inputs.book, inputs.penaltyRate, inputs.lotSize);
  final resolved = _resolveBoundaries(inputs.probabilities);
  final boundaries = resolved.boundaries;
  final lotSize = inputs.lotSize ?? POSITION_LOT_SIZE;
  final quantity = _rawAmount(inputs.quantity);
  final ttl = _timeToExpiry(_rawMs(inputs.expiryMs),
      _rawMs(inputs.nowMs ?? DateTime.now().millisecondsSinceEpoch));

  _assertRangeMintPolicy(inputs.fees, boundaries);
  final premium = _mulDown(rangeProbabilityRaw(boundaries), quantity);
  if (premium < MIN_PREMIUM) {
    throw PredictInputError('premium $premium is below the $MIN_PREMIUM '
        'minimum (EPremiumBelowMinimum)');
  }
  _assertValidQuantity(quantity, lotSize);

  final quote =
      _mintCostFrom(inputs, boundaries, resolved.exact, quantity, ttl);
  if (quote.raw.cost > quantity) {
    throw PredictInputError('all-in cost ${quote.raw.cost} exceeds the '
        'maximum payout $quantity (EMintCostAboveMaxPayout)');
  }
  return quote;
}

/// A fill whose ALL-IN cost fits a budget — `expiry_market::mint_exact_cost`
/// computed client-side, with the same lot search over the same cost
/// function, so the answer is the quantity that entrypoint would size and the
/// cost it would debit.
///
/// Without it a "spend exactly $X" flow has to guess: every fee is charged ON
/// TOP of the premium, so the caller subtracts an estimated fee load, pads it
/// against an abort, and systematically underspends. Here the whole search
/// runs locally; submit the all-in budget through `tx.mintCost` on
/// deployments carrying `mint_exact_cost`.
///
/// Sizing also respects the fill's maximum payout and the 32-bit lot cap;
/// either can leave substantial budget unspent. When only the budget binds,
/// one more lot would exceed it. If the budget fill exceeds its maximum
/// payout, the contract's step-down is best effort: rounding can make it miss
/// a larger admissible fill, including one meeting `minQuantity`. The chain
/// caps the budget at the account balance first
/// ([MintBudgetInputs.accountBalance]).
MintBudgetCost mintCostForBudget(MintBudgetInputs inputs) {
  _assertCostInputs(
      inputs.fees, inputs.book, inputs.penaltyRate, inputs.lotSize);
  final resolved = _resolveBoundaries(inputs.probabilities);
  final boundaries = resolved.boundaries;
  final lotSize = inputs.lotSize ?? POSITION_LOT_SIZE;
  final ttl = _timeToExpiry(_rawMs(inputs.expiryMs),
      _rawMs(inputs.nowMs ?? DateTime.now().millisecondsSinceEpoch));
  final minQuantity =
      inputs.minQuantity == null ? lotSize : _rawAmount(inputs.minQuantity!);
  final requestedBudget = _rawAmount(inputs.budget);
  var budget = requestedBudget;
  final accountBalance = inputs.accountBalance;
  if (accountBalance != null) budget = _min(budget, _rawAmount(accountBalance));

  _assertRangeMintPolicy(inputs.fees, boundaries);

  // `strike_exposure::max_quantity_for_premium` — the premium-only fit bounds
  // the all-in fit from above, because every other term is non-negative.
  final probability = rangeProbabilityRaw(boundaries);
  var lo = BigInt.zero;
  var hi = MAX_QUANTITY_LOTS;
  while (lo < hi) {
    final mid = (lo + hi + BigInt.one) ~/ BigInt.two;
    if (_mulDown(probability, mid * lotSize) <= budget) {
      lo = mid;
    } else {
      hi = mid - BigInt.one;
    }
  }

  // `expiry_market::quote_exact_cost_terms`, first half: the budget search
  // proper. Exact, because every all-in term is nondecreasing in quantity for
  // fixed pre-trade state.
  BigInt allInCostAt(BigInt quantity) =>
      _mintQuoteAt(inputs, boundaries, quantity, ttl).cost;
  hi = lo;
  lo = BigInt.zero;
  while (lo < hi) {
    final mid = (lo + hi + BigInt.one) ~/ BigInt.two;
    if (allInCostAt(mid * lotSize) <= budget) {
      lo = mid;
    } else {
      hi = mid - BigInt.one;
    }
  }
  final budgetLots = lo;
  final budgetQuantity = budgetLots * lotSize;

  // Second half: the maximum-payout bound (`cost <= quantity`) is
  // deliberately NOT part of that search. It is not monotone — cost and
  // quantity both rise, and the independent floors in each cost term let
  // `cost(q) <= q` flip back to true at a larger lot wherever unit cost sits
  // within rounding of one — so binary-searching it would discard admissible
  // fills. It is consulted only when the budget fill breaches it, and the
  // step-down runs strictly below that fill, so every candidate already fits
  // the budget. This fallback mirrors Move's best-effort search; its
  // nonmonotone predicate means it can miss larger admissible fills,
  // including one satisfying minQuantity.
  var lots = budgetLots;
  if (budgetLots > BigInt.zero &&
      allInCostAt(budgetQuantity) > budgetQuantity) {
    var stepLo = BigInt.zero;
    var stepHi = budgetLots - BigInt.one;
    while (stepLo < stepHi) {
      final mid = (stepLo + stepHi + BigInt.one) ~/ BigInt.two;
      final candidate = mid * lotSize;
      if (allInCostAt(candidate) <= candidate) {
        stepLo = mid;
      } else {
        stepHi = mid - BigInt.one;
      }
    }
    // No admissible smaller fill: fall back to the budget fill, which then
    // fails the maximum-payout bound below exactly as the chain's own quote
    // aborts on it.
    lots = stepLo == BigInt.zero ? budgetLots : stepLo;
  }

  final quantity = lots * lotSize;
  if (quantity < minQuantity) {
    throw PredictInputError('budget $budget sizes $quantity, below the '
        '$minQuantity minimum (EMintQuantityBelowMin)');
  }
  final premium = _mulDown(probability, quantity);
  if (premium < MIN_PREMIUM) {
    throw PredictInputError('budget $budget sizes a premium of $premium, '
        'below the $MIN_PREMIUM minimum (EPremiumBelowMinimum)');
  }
  _assertValidQuantity(quantity, lotSize);
  final quote =
      _mintCostFrom(inputs, boundaries, resolved.exact, quantity, ttl);
  if (quote.raw.cost > quantity) {
    throw PredictInputError('sized fill inside budget $budget costs more '
        'than it can pay out: ${quote.raw.cost} exceeds $quantity '
        '(EMintCostAboveMaxPayout)');
  }
  return MintBudgetCost(
    quantity: quote.quantity,
    entryProbability: quote.entryProbability,
    premium: quote.premium,
    fees: quote.fees,
    cost: quote.cost,
    costPerContract: quote.costPerContract,
    payoutMultiple: quote.payoutMultiple,
    raw: quote.raw,
    exactProbabilities: quote.exactProbabilities,
    budget: fromRaw(requestedBudget, 6),
    effectiveBudget: fromRaw(budget, 6),
    unspentBudget: fromRaw(requestedBudget - quote.raw.cost, 6),
    rawBudget: requestedBudget,
    rawEffectiveBudget: budget,
    rawUnspentBudget: requestedBudget - quote.raw.cost,
  );
}

// === Live redeem ===

/// Inputs for [redeemLiveProceeds]. The range is the ORDER's own range — the
/// same two boundaries it was minted over, which is what `redeem_live`
/// reprices.
class RedeemLiveInputs {
  final FeePolicy fees;
  final Object expiryMs;
  final Object? nowMs;

  /// The order's boundary probabilities now, or a pricer snapshot plus the
  /// order's strikes.
  final ProbabilitySource probabilities;

  /// Payout being closed — the whole order, or part of it.
  final Object closeQuantity;

  /// Current position payout quantity, when known. Validates the close and
  /// returns the remainder.
  final Object? positionQuantity;
  final bool builderCode;
  final BigInt? penaltyRate;

  /// Pre-trade payout-tree terms. Required when inventory impact is enabled.
  final CloseBookTerms? book;
  final BigInt? lotSize;

  const RedeemLiveInputs({
    required this.fees,
    required this.expiryMs,
    this.nowMs,
    required this.probabilities,
    required this.closeQuantity,
    this.positionQuantity,
    this.builderCode = false,
    this.penaltyRate,
    this.book,
    this.lotSize,
  });
}

/// A live close's fee decomposition in human units.
class RedeemFees {
  final double trading;
  final double builder;
  final double penalty;
  final double impactRebate;
  const RedeemFees({
    required this.trading,
    required this.builder,
    required this.penalty,
    required this.impactRebate,
  });
}

/// Exact integer fields of a live-redeem preview.
class RedeemLiveRaw {
  final BigInt proceeds;
  final BigInt gross;
  final BigInt tradingFee;
  final BigInt builderFee;
  final BigInt penaltyFee;
  final BigInt impactRebate;
  final BigInt quantityClosed;
  final BigInt? remainingQuantity;

  /// 1e9-scaled range probability; locally priced inputs remain approximate.
  final BigInt probability;

  const RedeemLiveRaw({
    required this.proceeds,
    required this.gross,
    required this.tradingFee,
    required this.builderFee,
    required this.penaltyFee,
    required this.impactRebate,
    required this.quantityClosed,
    required this.remainingQuantity,
    required this.probability,
  });
}

/// What a live close credits the account, decomposed.
class RedeemLiveProceeds {
  /// NET credited to the account.
  final double proceeds;

  /// Close value before fees: the range's current probability times the
  /// closed payout.
  final double gross;
  final RedeemFees fees;
  final double quantityClosed;

  /// Unclosed payout quantity, or null when positionQuantity was not
  /// supplied.
  final double? remainingQuantity;

  /// Net credited per $1 of closed payout; includes fees and the inventory
  /// rebate.
  final double proceedsPerContract;

  /// Current range probability, 0..1, before amount rounding and fees.
  final double probability;
  final RedeemLiveRaw raw;

  /// Identifies raw probability inputs; does not verify their source or state
  /// freshness.
  final bool exactProbabilities;

  const RedeemLiveProceeds({
    required this.proceeds,
    required this.gross,
    required this.fees,
    required this.quantityClosed,
    required this.remainingQuantity,
    required this.proceedsPerContract,
    required this.probability,
    required this.raw,
    required this.exactProbabilities,
  });
}

/// Net proceeds of closing a live position — `expiry_market::redeem_live`'s
/// payment decomposition, client-side. The mirror of [mintCost]: the same
/// per-boundary trading fee and builder fee, the same congestion surcharge,
/// and the inventory-impact term as a REBATE rather than a charge. There is
/// no sponsor subsidy on a close (incentives subsidise mints only), and each
/// deduction is clamped at the payout remaining after the ones before it,
/// exactly as the contract clamps them, so a close can never cost more than
/// it releases.
///
/// Use this for a local UI preview from a supplied snapshot.
/// `read.quoteRedeem` simulates the actual close and remains the pre-trade
/// check for ownership, remaining position size, live-market gates and
/// current fees. [RedeemLiveProceeds.proceeds] is what `min_proceeds` is
/// compared against on the real call; this preview does not guarantee
/// execution at that amount.
RedeemLiveProceeds redeemLiveProceeds(RedeemLiveInputs inputs) {
  _assertCostInputs(
      inputs.fees, inputs.book, inputs.penaltyRate, inputs.lotSize);
  final resolved = _resolveBoundaries(inputs.probabilities);
  final boundaries = resolved.boundaries;
  final lotSize = inputs.lotSize ?? POSITION_LOT_SIZE;
  final quantity = _rawAmount(inputs.closeQuantity);
  final ttl = _timeToExpiry(_rawMs(inputs.expiryMs),
      _rawMs(inputs.nowMs ?? DateTime.now().millisecondsSinceEpoch));
  _assertValidQuantity(quantity, lotSize);

  final positionQuantityIn = inputs.positionQuantity;
  final BigInt? positionQuantity =
      positionQuantityIn == null ? null : _rawAmount(positionQuantityIn);
  if (positionQuantity != null) {
    _assertValidQuantity(positionQuantity, lotSize);
    if (quantity > positionQuantity) {
      throw PredictInputError('closeQuantity exceeds positionQuantity');
    }
  }
  final remainingQuantity =
      positionQuantity == null ? null : positionQuantity - quantity;
  final probability = rangeProbabilityRaw(boundaries);
  final gross = _mulDown(probability, quantity);
  final fee = _min(tradingFee(inputs.fees, boundaries, quantity, ttl), gross);
  final builder =
      _min(builderFee(fee, quantity, inputs.builderCode), gross - fee);
  final penalty = _min(_mulDown(inputs.penaltyRate ?? BigInt.zero, quantity),
      gross - fee - builder);
  final book = inputs.book;
  final rebate = book != null
      ? closeInventoryImpact(inputs.fees, book, quantity)
      : BigInt.zero;
  final proceeds = gross + rebate - fee - builder - penalty;

  return RedeemLiveProceeds(
    proceeds: fromRaw(proceeds, 6),
    gross: fromRaw(gross, 6),
    fees: RedeemFees(
      trading: fromRaw(fee, 6),
      builder: fromRaw(builder, 6),
      penalty: fromRaw(penalty, 6),
      impactRebate: fromRaw(rebate, 6),
    ),
    quantityClosed: fromRaw(quantity, 6),
    remainingQuantity:
        remainingQuantity == null ? null : fromRaw(remainingQuantity, 6),
    proceedsPerContract: proceeds.toDouble() / quantity.toDouble(),
    probability: fromRaw(probability, 9),
    raw: RedeemLiveRaw(
      proceeds: proceeds,
      gross: gross,
      tradingFee: fee,
      builderFee: builder,
      penaltyFee: penalty,
      impactRebate: rebate,
      quantityClosed: quantity,
      remainingQuantity: remainingQuantity,
      probability: probability,
    ),
    exactProbabilities: resolved.exact,
  );
}

// === Order IDs ===

final BigInt _quantityLotsOffset = BigInt.from(100);
final BigInt _lowerTickOffset = BigInt.from(70);
final BigInt _higherTickOffset = BigInt.from(40);
// `constants::pos_inf_tick` is the full 30-bit mask.
final BigInt _tickMask = POS_INF_TICK;
final BigInt _u32Mask = (BigInt.one << 32) - BigInt.one;

/// The contract terms packed into an order ID (`deepbook_predict::order`).
/// Tick 0 as the lower bound is −∞ and [POS_INF_TICK] as the higher is +∞;
/// multiply a finite tick by the market's `tickSize` for its raw strike. Use
/// it to feed a position from `read.positions` into [redeemLiveProceeds].
class OrderRange {
  final BigInt lowerTick;
  final BigInt higherTick;

  /// Minted payout: `quantity_lots · position_lot_size`.
  final BigInt quantity;

  const OrderRange({
    required this.lowerTick,
    required this.higherTick,
    required this.quantity,
  });
}

/// Decode an order ID's range and quantity — the Dart mirror of
/// `order::lower_tick` / `higher_tick` / `quantity`.
OrderRange decodeOrderRange(BigInt orderId, {BigInt? lotSize}) {
  return OrderRange(
    lowerTick: (orderId >> _lowerTickOffset.toInt()) & _tickMask,
    higherTick: (orderId >> _higherTickOffset.toInt()) & _tickMask,
    quantity: ((orderId >> _quantityLotsOffset.toInt()) & _u32Mask) *
        (lotSize ?? POSITION_LOT_SIZE),
  );
}

/// The strikes an [OrderRange] prices against, in USD, with null for each
/// infinite side — the shape [boundaryProbabilities] takes. [tickSizeRaw] is
/// the market's raw tick size.
({double? lower, double? upper}) orderStrikes(
    OrderRange range, BigInt tickSizeRaw) {
  return (
    lower: range.lowerTick == BigInt.zero
        ? null
        : fromRaw(range.lowerTick * tickSizeRaw, 9),
    upper: range.higherTick == POS_INF_TICK
        ? null
        : fromRaw(range.higherTick * tickSizeRaw, 9),
  );
}
