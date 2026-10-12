/// Market discovery and state reads, mirroring `predict/reads/markets.ts`.
library;

import 'dart:typed_data';

import 'package:sui/sui.dart' show Transaction;

import '../../contracts/deepbook_predict/expiry_market.dart' as expiry_market;
import '../../contracts/deepbook_predict/plp.dart' as plp;
import '../../contracts/deepbook_predict/pricing.dart' as pricing;
import '../../contracts/deepbook_predict/range_codec.dart' as range_codec;
import '../../contracts/deepbook_predict/registry.dart' as registry;
import '../../contracts/utils.dart' show MoveCallBuilder;
import '../config.dart' show GeneratedConfig, UnderlyingConfig;
import '../errors.dart';
import '../ticks.dart' show POS_INF_TICK;
import '../tx/trade.dart' show MarketFeeds, loadLivePricer;
import 'inspect.dart';
import 'parse.dart';

/// On-chain ids of the pool's active (live, not-yet-settled) expiry markets.
/// `plp::active_expiry_markets(vault)`.
Future<List<String>> activeMarketIds(
    ReadClient client, GeneratedConfig config) async {
  final tx = Transaction();
  plp.activeExpiryMarkets(config: config)(tx);
  final cmds = await inspectReturns(client, tx);
  return parseVectorOfIds(cmds[0][0]);
}

/// The expiry market id for one underlying at one expiry, or null if none
/// exists. `registry::expiry_market_id(registry, propbook_underlying_id: u32,
/// expiry: u64): Option&lt;ID&gt;`.
Future<String?> expiryMarketId(
  ReadClient client,
  GeneratedConfig config,
  UnderlyingConfig underlying,
  BigInt expiryMs,
) async {
  final tx = Transaction();
  registry.expiryMarketId(
    config: config,
    arguments: {
      'propbookUnderlyingId': underlying.propbookUnderlyingId,
      'expiry': expiryMs,
    },
  )(tx);
  final cmds = await inspectReturns(client, tx);
  return parseOptionalId(cmds[0][0]);
}

/// One market's state, as the per-market getters return it.
class MarketState {
  final BigInt expiryMs;
  final BigInt tickSizeRaw;

  /// The COARSER raw-price step new finite mint boundaries must align to
  /// (`expiry_market::admission_tick_size`). A numeric strike must be a whole
  /// multiple of this — the fine [tickSizeRaw] grid alone is not sufficient —
  /// or the chain aborts `EInvalidAdmissionTick`. The market's reference tick
  /// is the one finite boundary allowed to bypass it.
  final BigInt admissionTickSizeRaw;
  final bool mintPaused;

  /// The reference fine-grid tick (Polymarket-style anchor strike: derived
  /// on-chain from the exact previous-window oracle observation), or null
  /// while the keeper has not seeded it. Reference PRICE raw = tick ·
  /// tickSizeRaw.
  final BigInt? referenceTickRaw;

  const MarketState({
    required this.expiryMs,
    required this.tickSizeRaw,
    required this.admissionTickSizeRaw,
    required this.mintPaused,
    required this.referenceTickRaw,
  });
}

// The per-market state getters, in fixed order. `reference_tick` returns
// Option (no abort risk); settlement is read separately via
// [settlementPrice] (its own non-batched getter below).
List<MoveCallBuilder> _stateFns(GeneratedConfig config, String marketId) => [
      expiry_market.expiry(config: config, arguments: {'market': marketId}),
      expiry_market.tickSize(config: config, arguments: {'market': marketId}),
      expiry_market
          .admissionTickSize(config: config, arguments: {'market': marketId}),
      expiry_market.mintPaused(config: config, arguments: {'market': marketId}),
      expiry_market
          .referenceTick(config: config, arguments: {'market': marketId}),
    ];

const int _stateFnCount = 5;

MarketState _parseStateAt(List<List<Uint8List>> cmds, int base) => MarketState(
      expiryMs: parseU64LE(cmds[base][0]),
      tickSizeRaw: parseU64LE(cmds[base + 1][0]),
      admissionTickSizeRaw: parseU64LE(cmds[base + 2][0]),
      mintPaused: parseBool(cmds[base + 3][0]),
      referenceTickRaw: parseOptionalU64(cmds[base + 4][0]),
    );

Future<MarketState> marketState(
    ReadClient client, GeneratedConfig config, String marketId) async {
  final states = await marketStates(client, config, [marketId]);
  return states[0];
}

/// Batched [marketState] for N markets in ONE PTB (five commands per market,
/// same order). Returns states aligned with [marketIds].
Future<List<MarketState>> marketStates(
  ReadClient client,
  GeneratedConfig config,
  List<String> marketIds,
) async {
  if (marketIds.isEmpty) return [];
  final tx = Transaction();
  for (final id in marketIds) {
    for (final fn in _stateFns(config, id)) {
      fn(tx);
    }
  }
  final cmds = await inspectReturns(client, tx);
  return [
    for (var i = 0; i < marketIds.length; i++)
      _parseStateAt(cmds, _stateFnCount * i)
  ];
}

/// Anonymous both-sides pricing for one strike: the chain's own probability
/// for `(strike, +inf]` and `(-inf, strike]`. The deployed
/// `pricing::range_price` takes typed `range_codec::Strike`s (NOT raw u64) —
/// each boundary is built via `range_codec::strike_from_tick(tick,
/// tick_size)`, which maps tick 0 → −∞, [POS_INF_TICK] → +∞, and any finite
/// tick → tick·tick_size. Both sides read the SAME pricer in one PTB, so
/// `down` is the chain's number, not 1 − up.
///
/// `range_price` returns a `RangePrice` carrying both boundary probabilities
/// so the fee can charge each leg separately; `probability()` is the combined
/// range number this function has always returned
/// (`lower_up.saturating_sub(higher_up)`). The extra call per side is what
/// keeps the u64 parse below reading a u64 rather than the struct's BCS.
Future<({BigInt upRaw, BigInt downRaw})> rangePrices(
  ReadClient client,
  GeneratedConfig config,
  String marketId,
  MarketFeeds feeds,
  BigInt strikeRaw,
  BigInt tickSizeRaw,
) async {
  final tx = Transaction();
  final pricer =
      loadLivePricer(config, expiryMarketId: marketId, feeds: feeds)(tx);
  // strikeRaw is a whole tick multiple (the caller validates divisibility),
  // so the finite boundary is `strike_from_tick(strikeRaw / tickSize,
  // tickSize)`.
  final strikeTick = strikeRaw ~/ tickSizeRaw;
  dynamic mkStrike(BigInt tick) => range_codec.strikeFromTick(
        config: config,
        arguments: {'tick': tick, 'tickSize': tickSizeRaw},
      )(tx);
  final strike = mkStrike(strikeTick);
  final posInf = mkStrike(POS_INF_TICK);
  final negInf = mkStrike(BigInt.zero);
  // UP: (strike, +inf], then DOWN: (-inf, strike]. The two `probability`
  // reductions are the last two commands, which is what the tail-relative
  // parse below indexes.
  final up = pricing.rangePrice(
    config: config,
    arguments: {'pricer': pricer, 'lower': strike, 'higher': posInf},
  )(tx);
  final down = pricing.rangePrice(
    config: config,
    arguments: {'pricer': pricer, 'lower': negInf, 'higher': strike},
  )(tx);
  pricing.probability(config: config, arguments: {'price': up})(tx);
  pricing.probability(config: config, arguments: {'price': down})(tx);
  final cmds = await inspectReturns(client, tx);
  return (
    upRaw: parseU64LE(cmds[cmds.length - 2][0]),
    downRaw: parseU64LE(cmds[cmds.length - 1][0]),
  );
}

/// Fresh single read of the reference tick — used by mint-at-reference, which
/// must not trust a cached state (the reference is unset early in a window
/// until the keeper seeds it).
Future<BigInt?> referenceTick(
    ReadClient client, GeneratedConfig config, String marketId) async {
  final tx = Transaction();
  expiry_market
      .referenceTick(config: config, arguments: {'market': marketId})(tx);
  final cmds = await inspectReturns(client, tx);
  return parseOptionalU64(cmds[0][0]);
}

/// The recorded settlement price, or null while the market is unsettled.
///
/// On the deployed package `expiry_market::settlement_price` is public and
/// `destroy_some`s the stored Option — callable here only because simulate
/// runs with checks disabled, and it aborts in `std::option`
/// (EOPTION_NOT_SET) when the market has not settled; we map exactly that
/// abort (and the public EMarketNotSettled variant, should a future package
/// guard it directly) to null.
Future<BigInt?> settlementPrice(
    ReadClient client, GeneratedConfig config, String marketId) async {
  final tx = Transaction();
  expiry_market
      .settlementPrice(config: config, arguments: {'market': marketId})(tx);
  try {
    final cmds = await inspectReturns(client, tx);
    return parseU64LE(cmds[0][0]);
  } on PredictMoveError catch (e) {
    if (e.module == 'option' ||
        (e.module == 'expiry_market' && e.abortName == 'EMarketNotSettled')) {
      return null;
    }
    rethrow;
  }
}

/// A market's current NAV mark (the per-expiry recoverable value the flush
/// prices against). Loads a fresh live pricer, then reads
/// `current_nav(market, &pricer)`. `Pricer` has copy+drop, so the unconsumed
/// borrow is fine in a read-only inspect.
Future<BigInt> currentNav(
  ReadClient client,
  GeneratedConfig config,
  String marketId,
  UnderlyingConfig underlying,
) async {
  final tx = Transaction();
  final pricer = loadLivePricer(
    config,
    expiryMarketId: marketId,
    feeds: MarketFeeds(
      pythFeed: underlying.pythFeed,
      blockScholesValueStore: underlying.blockScholesValueStore,
      blockScholesSviStore: underlying.blockScholesSviStore,
    ),
  )(tx);
  expiry_market.currentNav(
      config: config, arguments: {'market': marketId, 'pricer': pricer})(tx);
  final cmds = await inspectReturns(client, tx);
  // current_nav is the last command; load_live_pricer precedes it.
  return parseU64LE(cmds[cmds.length - 1][0]);
}
