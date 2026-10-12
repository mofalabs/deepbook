/// Pricer-snapshot read, mirroring `predict/reads/pricing.ts`.
library;

import 'package:sui/sui.dart' show Transaction;

import '../../contracts/deepbook_predict/pricing.dart' show Pricer;
import '../config.dart' show GeneratedConfig;
import '../pricing.dart';
import '../tx/trade.dart' show MarketFeeds, loadLivePricer;
import 'inspect.dart';

// The chain's fixed-point scales for the rolled `PricingSVI` (see the
// generated `Pricer`/`PricingSVI` struct): forward and rho/m/sigma at 1e9;
// the rolled `a`/`b` land at 1e18 (roll_down multiplies the 1e9 raw by an
// extra 1e9). Converting to double is deliberate — this is a display pricer;
// `a` is a variance ~O(1e-2), so f64's ~15 significant digits are ample and,
// per pricing.dart, more precise than the chain's fixed point on the
// short-dated surfaces this prices.
const double _forwardScale = 1e9;
const double _abScale = 1e18;
const double _rmsScale = 1e9; // rho, m, sigma

double _num(Object v) => double.parse(v.toString());

double _i64(Map v) =>
    ((v['is_negative'] as bool) ? -1 : 1) * _num(v['magnitude'] as Object);

/// The oracle source timestamps behind a pricer snapshot (ms; for staleness
/// display — Pyth is 0 when no usable spot existed). The Block-Scholes
/// entries are the provider's PER-UPDATE source timestamps
/// (`value_timestamp` for spot/forward, `svi_timestamp` for SVI) — the clocks
/// freshness and the SVI roll-down anchor on.
class PricerSources {
  final int pythSpotMs;
  final int blockScholesSpotMs;
  final int blockScholesForwardMs;
  final int blockScholesSviMs;

  const PricerSources({
    required this.pythSpotMs,
    required this.blockScholesSpotMs,
    required this.blockScholesForwardMs,
    required this.blockScholesSviMs,
  });
}

/// A resolved pricer snapshot read from the chain: the decimal forward +
/// rolled SVI the client-side math consumes, plus the oracle source
/// timestamps behind it.
class PricerSnapshot extends PricerInputs {
  final PricerSources sources;

  const PricerSnapshot({
    required super.forward,
    required super.svi,
    required this.sources,
  });
}

// Decode a `Pricer` (already forward-resolved + roll-down-applied on-chain)
// into decimal inputs. Signed fields (`a`, `rho`, `m`) carry the
// magnitude/flag pair the chain uses; `b`/`sigma` are non-negative.
PricerSnapshot _decodePricer(Map pricer) {
  final s = pricer['svi'] as Map;
  final svi = Svi(
    a: ((s['a_is_negative'] as bool) ? -1 : 1) *
        _num(s['a_magnitude'] as Object) /
        _abScale,
    b: _num(s['b'] as Object) / _abScale,
    rho: _i64(s['rho'] as Map) / _rmsScale,
    m: _i64(s['m'] as Map) / _rmsScale,
    sigma: _num(s['sigma'] as Object) / _rmsScale,
  );
  return PricerSnapshot(
    forward: _num(pricer['forward'] as Object) / _forwardScale,
    svi: svi,
    sources: PricerSources(
      pythSpotMs: int.parse(pricer['pyth_spot_source_timestamp_ms'].toString()),
      blockScholesSpotMs: int.parse(
          pricer['block_scholes_spot_source_timestamp_ms'].toString()),
      blockScholesForwardMs: int.parse(
          pricer['block_scholes_forward_source_timestamp_ms'].toString()),
      blockScholesSviMs:
          int.parse(pricer['block_scholes_svi_source_timestamp_ms'].toString()),
    ),
  );
}

/// Read one live pricer snapshot for [marketId]: a single simulate of
/// `load_live_pricer` — the chain reads the oracle feeds, picks the forward
/// (Pyth-vs-Block-Scholes admin policy + freshness), and rolls the SVI down
/// to now, then returns the whole `Pricer` by value (copy+drop), whose BCS we
/// decode. One round trip; then a `boardPricer` prices every strike locally.
///
/// `load_live_pricer` ABORTS (a typed [PredictMoveError]) when the market is
/// expired, a feed is stale, or the surface fails the pricing-safe envelope —
/// i.e. exactly when the chain itself cannot quote. Callers surface that the
/// same way `read.price` does.
Future<PricerSnapshot> readPricerSnapshot(
  ReadClient client,
  GeneratedConfig config,
  String marketId,
  MarketFeeds feeds,
) async {
  final tx = Transaction();
  loadLivePricer(config, expiryMarketId: marketId, feeds: feeds)(tx);
  final cmds = await inspectReturns(client, tx);
  return _decodePricer(Pricer.parse(cmds[0][0]) as Map);
}
