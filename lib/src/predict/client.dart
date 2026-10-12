/// The PredictClient facade, mirroring `predict/client.ts`.
library;

// Official constant name kept for line-for-line ports.
// ignore_for_file: non_constant_identifier_names

import 'package:sui/sui.dart' show GrpcCoreClient, Transaction;
import 'package:sui/types/common.dart'
    show isValidSuiObjectId, normalizeSuiAddress;

import '../deployments/deployments.dart' show testnetPredict;
import 'config.dart';
import 'decode.dart';
import 'errors.dart';
import 'pricing.dart' show BoardPricer, boardPricer;
import 'reads/balances.dart' as balances_reads;
import 'reads/inspect.dart' show ReadClient, simulateWithEvents;
import 'reads/markets.dart' as markets_reads;
import 'reads/markets.dart' show MarketState;
import 'reads/pool.dart' as pool_reads;
import 'reads/positions.dart' as positions_reads;
import 'reads/positions.dart' show OpenPosition, PositionsHandle;
import 'reads/pricing.dart' show PricerSources, readPricerSnapshot;
import 'ticks.dart';
import 'tx/authed.dart' as authed;
import 'tx/common.dart' show accountContract, deriveAccountWrapperIdFrom;
import 'tx/trade.dart' as trade;
import 'tx/trade.dart' show MarketFeeds;
import 'units.dart';

/// Testnet's `position_lot_size`, read from the deployment record. Validation
/// uses the lot size of the config actually in play; this is the convenience
/// constant for testnet callers.
///
/// (The official SDK exports this as `POSITION_LOT_SIZE` from the package
/// root; Dart renames it so it cannot shadow the Move constant
/// `cost.POSITION_LOT_SIZE` in a flat export.)
final BigInt TESTNET_POSITION_LOT_SIZE =
    BigInt.from(testnetPredict.units.positionLotSize);

// Most `tx.*` builders are one builder's worth of commands in a fresh PTB.
Transaction _txOf(dynamic Function(Transaction) command) {
  final tx = Transaction();
  command(tx);
  return tx;
}

/// A live/settled market addressed by its human coordinates: a binary
/// position (single strike + side) or a two-strike range position.
///
/// Mirrors the official tagged union: use [MarketDescriptor.up] /
/// [MarketDescriptor.down] for a binary position (strike in USD, or
/// `'reference'` to trade at the market's on-chain reference price — the
/// Polymarket-style anchor, derived from the exact previous-window oracle
/// observation so consecutive windows chain settlement → next strike), and
/// [MarketDescriptor.range] for a range paying out when settlement lands
/// inside `(lower, upper]` (left-open, right-closed — the on-chain range key
/// convention).
class MarketDescriptor {
  final String underlying;

  /// Expiry in ms since epoch ([int] or [BigInt]).
  final Object expiryMs;

  /// Pin resolution to this exact `ExpiryMarket` object, skipping the
  /// underlying+expiry lookup — a caller that reviewed a specific market
  /// object mints against exactly that object, not whatever resolves at
  /// submit time.
  final String? marketId;

  /// `'up'`, `'down'`, or `'range'`.
  final Side side;

  /// Binary arm: strike in USD ([num]), or the [String] `'reference'`.
  final Object? strike;

  /// Range arm: lower strike bound in USD — finite, on the tick grid.
  final num? lower;

  /// Range arm: upper strike bound in USD — finite, on the tick grid, above
  /// [lower].
  final num? upper;

  const MarketDescriptor.up({
    required this.underlying,
    required this.expiryMs,
    required this.strike,
    this.marketId,
  })  : side = 'up',
        lower = null,
        upper = null;

  const MarketDescriptor.down({
    required this.underlying,
    required this.expiryMs,
    required this.strike,
    this.marketId,
  })  : side = 'down',
        lower = null,
        upper = null;

  const MarketDescriptor.range({
    required this.underlying,
    required this.expiryMs,
    required num this.lower,
    required num this.upper,
    this.marketId,
  })  : side = 'range',
        strike = null;
}

/// Options for the friendly `mint` (exact payout quantity).
class MintOptions {
  final num quantity;
  final num? maxCost;
  final double? maxProbability;
  const MintOptions(
      {required this.quantity, this.maxCost, this.maxProbability});
}

/// Options for `mintAmount` (spend up to a premium budget, floor the quantity
/// received).
class MintAmountOptions {
  /// Premium budget in quote units — the max premium paid (chain also caps it
  /// at the account balance).
  final num spend;
  final num minQuantity;

  /// All-in cost ceiling in quote units (premium + fees). Omitted → uncapped.
  final num? maxCost;
  const MintAmountOptions(
      {required this.spend, required this.minQuantity, this.maxCost});
}

/// Options for `mintCost`: all-in budget. Requires Predict v2 or later.
class MintCostOptions {
  /// All-in USDC budget; the chain also caps it at the account balance.
  final num spend;

  /// Minimum payout received. Zero disables this slippage floor.
  final num minQuantity;
  const MintCostOptions({required this.spend, required this.minQuantity});
}

/// Options for `redeem`: which order and how much to close. `claimSettled`
/// takes only the order id — a settled claim closes the order in full.
class CloseOptions {
  final BigInt orderId;
  final num quantity;
  const CloseOptions({required this.orderId, required this.quantity});
}

/// Options for `supplyPlp`.
class PlpSupplyOptions {
  /// Floor on the PLP minted for the whole request, as raw [BigInt] shares —
  /// PLP is raw everywhere in this SDK. It is a floor on the MARK, not a
  /// share count: a flush quoting less does not fill smaller, it declines.
  /// Omitted → 0, no floor.
  ///
  /// How a miss is handled is the deployment's
  /// `lp_request_limit_flush_attempts`: at the shipped count of one the first
  /// flush below the floor cancels and refunds the request.
  final BigInt? minPlpOut;
  const PlpSupplyOptions({this.minPlpOut});
}

/// Options for `withdrawPlp`.
class PlpWithdrawOptions {
  /// Floor on the USDC paid for the whole request, in USD decimals like every
  /// other amount here ([num] or decimal [String]). A floor on the MARK, not
  /// an amount: a flush quoting less declines rather than paying out smaller.
  /// Omitted → no floor. Measured after the protocol's withdraw fee.
  final Object? minUsdcOut;
  const PlpWithdrawOptions({this.minUsdcOut});
}

/// One tradeable market as returned by `read.markets()`.
class ActiveMarket {
  final String id;
  final BigInt expiryMs;

  /// Strike granularity in USD (e.g. 0.01).
  final double tickSize;

  /// Coarser step new mint strikes must align to. A numeric strike must be a
  /// whole multiple of this (the market's [referencePrice] is the one
  /// exception the chain admits off-grid); otherwise the mint aborts
  /// `EInvalidAdmissionTick`.
  final double admissionTickSize;
  final bool mintPaused;

  /// The window's anchor strike in USD, or null until the keeper seeds it.
  final double? referencePrice;

  const ActiveMarket({
    required this.id,
    required this.expiryMs,
    required this.tickSize,
    required this.admissionTickSize,
    required this.mintPaused,
    required this.referencePrice,
  });
}

/// A resolved live market: its on-chain state summary for the caller.
class MarketSummary {
  final String id;
  final BigInt expiryMs;
  final double tickSize;

  /// Coarser step new mint strikes must align to (see
  /// [ActiveMarket.admissionTickSize]).
  final double admissionTickSize;
  final bool mintPaused;
  final double nav;

  /// The window's anchor strike in USD, or null until the keeper seeds it.
  final double? referencePrice;

  const MarketSummary({
    required this.id,
    required this.expiryMs,
    required this.tickSize,
    required this.admissionTickSize,
    required this.mintPaused,
    required this.nav,
    required this.referencePrice,
  });
}

/// Aggregate pool figures. Balances in human units (shares raw); the pending
/// fields are request COUNTS, not amounts — the on-chain getters expose queue
/// lengths, and the escrowed USDC/PLP behind them is tracked separately.
class PoolSummary {
  final BigInt plpTotalSupply;
  final double idleUsdc;

  /// Number of LP supply requests queued for the next flush.
  final int supplyRequestsPending;

  /// Number of LP withdraw requests queued for the next flush.
  final int withdrawRequestsPending;

  const PoolSummary({
    required this.plpTotalSupply,
    required this.idleUsdc,
    required this.supplyRequestsPending,
    required this.withdrawRequestsPending,
  });
}

/// Raw integers of a mint quote.
class MintQuoteRaw {
  final BigInt premium;
  final BigInt cost;
  final BigInt quantity;
  final BigInt entryProbability;
  const MintQuoteRaw({
    required this.premium,
    required this.cost,
    required this.quantity,
    required this.entryProbability,
  });
}

/// Exact pre-trade quote: the dry-run receipt of the mint you are about to
/// send.
class MintQuote {
  /// Fill price, 0..1 per $1 payout.
  final double entryProbability;

  /// Premium paid into LP backing (quote units).
  final double premium;

  /// Fee breakdown. `referral` is a PORTION of the trader-paid trading fee
  /// and congestion surcharge routed to the referrer — it is already inside
  /// those numbers and is NOT an extra debit. `inventoryImpact` is a separate
  /// charge and IS part of [cost].
  final MintReceiptFees fees;

  /// All-in account debit: premium + (trading − subsidy) + builder + penalty
  /// + inventoryImpact — exactly what the chain withdraws (the deployed
  /// `compute_mint_quote`'s `all_in_cost`); pass this (plus your buffer) as
  /// maxCost.
  final double cost;
  final double quantity;
  final MintQuoteRaw raw;

  /// True: computed by the real mint code path against real account state.
  final bool feesExact;

  const MintQuote({
    required this.entryProbability,
    required this.premium,
    required this.fees,
    required this.cost,
    required this.quantity,
    required this.raw,
    this.feesExact = true,
  });
}

/// Raw integers of a redeem quote.
class RedeemQuoteRaw {
  final BigInt proceeds;
  final BigInt gross;
  final BigInt quantityClosed;
  const RedeemQuoteRaw({
    required this.proceeds,
    required this.gross,
    required this.quantityClosed,
  });
}

/// Exact pre-close quote: the dry-run receipt of the redeem you are about to
/// send.
class RedeemQuote {
  /// NET quote credited to the account.
  final double proceeds;

  /// Gross close value before fees.
  final double gross;

  /// `inventoryImpactRebate` is credited back on the close, so [proceeds] is
  /// gross + rebate − trading − builder − penalty.
  final RedeemReceiptFees fees;
  final double quantityClosed;
  final double remaining;
  final RedeemQuoteRaw raw;
  final bool feesExact;

  const RedeemQuote({
    required this.proceeds,
    required this.gross,
    required this.fees,
    required this.quantityClosed,
    required this.remaining,
    required this.raw,
    this.feesExact = true,
  });
}

class _ResolvedMarket {
  final String id;
  final MarketState state;
  const _ResolvedMarket({required this.id, required this.state});
}

/// A client-side board pricer bound to one market snapshot, with the oracle
/// source timestamps it was read at.
class BoardPricerWithSources extends BoardPricer {
  /// The oracle source timestamps behind the snapshot.
  final PricerSources asOf;
  BoardPricerWithSources(
      {required super.forward, required super.svi, required this.asOf});
}

/// The one object an app constructs. Wraps the config, a client for reads,
/// and a derived-account model so callers pass owner addresses, decimal
/// amounts, and human market coordinates — the facade converts to raw units,
/// resolves markets (cached), and delegates to the internal tx primitives /
/// reads. Each `tx.*` builder returns a finished [Transaction]; callers
/// composing their own PTBs use the trade primitives and generated move-call
/// bindings this subpath exports.
class PredictClient {
  final PredictConfig cfg;
  final ReadClient _client;

  // underlying:expiryMs → resolved market. The id and tickSizeRaw — the only
  // state tx building depends on — are immutable per (underlying, expiry), so
  // one resolution per market per client suffices. (mintPaused IS mutable;
  // the cached copy is never consulted for a tx decision — the chain
  // enforces it.)
  final Map<String, _ResolvedMarket> _marketCache = {};

  // owner → resolved position-store ids. accountUid and the table id are
  // immutable once created, so cache-forever; a missing table (no Predict
  // data yet) is NOT cached — it appears after the owner's first trade.
  final Map<String, PositionsHandle> _positionsCache = {};

  /// Namespaced tx builders (`client.tx.mint(...)`), mirroring the official
  /// `client.predict.tx.*` facade.
  late final PredictTxBuilders tx;

  /// Namespaced reads (`client.read.markets()`).
  late final PredictReads read;

  /// Namespaced execution-result decoders (`client.decode.mint(result)`).
  late final PredictDecoders decode;

  /// [network] is `'testnet'` or `'mainnet'`; [config] overrides the recorded
  /// deployment (for a custom deployment).
  PredictClient({
    required String network,
    required GrpcCoreClient client,
    PredictConfig? config,
  })  : cfg = config ?? getConfig(network),
        _client = client {
    tx = PredictTxBuilders._(this);
    read = PredictReads._(this);
    decode = PredictDecoders._(this);
  }

  // The flat slice every generated call resolves `config:` against.
  GeneratedConfig get _config => toGeneratedConfig(cfg);

  /// The deterministic id of an owner's canonical account wrapper — no chain
  /// read.
  String wrapperIdFor(String owner) =>
      deriveAccountWrapperIdFrom(_config, owner);

  // The deployment's wiring for a symbol; throws a typed error on an unknown
  // symbol. Per-underlying ids are the one thing the flat config slice does
  // not carry.
  UnderlyingConfig _underlying(String underlying) {
    final u = cfg.underlyings[underlying];
    if (u == null) throw PredictInputError('unknown underlying: $underlying');
    return u;
  }

  // The oracle feed ids for a symbol; throws a typed error on an unknown
  // symbol.
  MarketFeeds _feeds(String underlying) {
    final u = _underlying(underlying);
    return MarketFeeds(
      pythFeed: u.pythFeed,
      blockScholesValueStore: u.blockScholesValueStore,
      blockScholesSviStore: u.blockScholesSviStore,
    );
  }

  static BigInt _expiryOf(Object expiryMs) =>
      expiryMs is BigInt ? expiryMs : BigInt.from(expiryMs as int);

  // Resolve (and cache) a market's id + state from its human coordinates. An
  // explicit `marketId` pin skips the underlying+expiry lookup but still
  // reads that market's state — tx building depends on tickSizeRaw.
  Future<_ResolvedMarket> _resolveMarket(
      {required String underlying,
      required Object expiryMs,
      String? marketId}) async {
    if (marketId != null) {
      // Validate the id as given (no pre-normalization): the official SDK
      // rejects short forms like '0x2' here.
      if (!isValidSuiObjectId(marketId)) {
        throw PredictInputError('invalid marketId: "$marketId"');
      }
      final resolved = _marketCache[marketId] ??
          _ResolvedMarket(
            id: marketId,
            state: await markets_reads.marketState(_client, _config, marketId),
          );
      // The pin must agree with the descriptor's coordinates: catching a
      // stale or wrong-market id here beats minting against mismatched oracle
      // feeds. (The underlying cannot be cross-checked — market state does
      // not carry it.)
      if (resolved.state.expiryMs != _expiryOf(expiryMs)) {
        throw PredictInputError(
            'pinned market $marketId expires at ${resolved.state.expiryMs}, '
            'descriptor says ${_expiryOf(expiryMs)}');
      }
      _marketCache[marketId] = resolved;
      return resolved;
    }
    final expiry = _expiryOf(expiryMs);
    final key = '$underlying:$expiry';
    final hit = _marketCache[key];
    if (hit != null) return hit;
    final u = _underlying(underlying);
    final id = await markets_reads.expiryMarketId(_client, _config, u, expiry);
    if (id == null) {
      throw PredictInputError('no market for $underlying at expiry $expiry');
    }
    final state = await markets_reads.marketState(_client, _config, id);
    final resolved = _ResolvedMarket(id: id, state: state);
    _marketCache[key] = resolved;
    return resolved;
  }

  // Reference PRICE in USD from a state (tick index × tick size), or null.
  static double? _referencePriceOf(MarketState state) {
    final tick = state.referenceTickRaw;
    return tick == null ? null : fromRaw(tick * state.tickSizeRaw, 9);
  }

  // A finite tick from a USD strike, validated exactly like binaryRangeTicks:
  // whole-tick multiple, inside the finite domain (1..POS_INF_TICK-1).
  BigInt _gridTick(num strike, BigInt tickSizeRaw) {
    final raw = priceToRaw(strike);
    final tick = raw ~/ tickSizeRaw;
    if (tick * tickSizeRaw != raw) {
      throw PredictInputError(
          'strike $strike is not on the ${fromRaw(tickSizeRaw, 9)} tick grid');
    }
    if (tick <= BigInt.zero || tick >= POS_INF_TICK) {
      throw PredictInputError(
          'strike tick $tick outside the finite tick domain '
          '(1..POS_INF_TICK-1)');
    }
    return tick;
  }

  // New finite MINT boundaries must land on the market's coarser ADMISSION
  // grid, not merely the fine tick grid — the chain asserts exactly this
  // (`assert_admitted_mint_ticks`, `EInvalidAdmissionTick`). The ±inf
  // sentinels are exempt, and the market's reference tick is the one finite
  // boundary allowed to bypass the grid, so an off-grid tick is only rejected
  // after confirming it is not the reference (one extra read, and only on the
  // failing path).
  Future<void> _assertAdmittedTick(
      BigInt tick, String marketId, MarketState state) async {
    if (tick == BigInt.zero || tick == POS_INF_TICK) return;
    final multiple = state.admissionTickSizeRaw ~/ state.tickSizeRaw;
    if (multiple > BigInt.zero && tick % multiple == BigInt.zero) return;
    final reference =
        await markets_reads.referenceTick(_client, _config, marketId);
    if (reference != null && reference == tick) return;
    final admission = fromRaw(state.admissionTickSizeRaw, 9);
    throw PredictInputError(
        'strike ${fromRaw(tick * state.tickSizeRaw, 9)} is not on the '
        '$admission admission grid (mint boundaries must be a multiple of '
        "$admission, or the market's reference strike)");
  }

  // Resolve a descriptor's strike(s) to the (lower, higher) tick pair. A
  // binary numeric strike converts and validates against the tick grid;
  // 'reference' reads the market's reference tick FRESH (never cached — it is
  // unset early in a window) and uses it directly: it is on the tick grid by
  // construction. A range descriptor converts both bounds to finite grid
  // ticks ('reference' is binary-only: a range has no single reference
  // strike).
  Future<RangeTicks> _strikeTicks(
      MarketDescriptor m, String marketId, MarketState state) async {
    if (m.side == 'range') {
      final lower = m.lower!;
      final upper = m.upper!;
      if (!(lower < upper)) {
        throw PredictInputError(
            'range lower $lower must be below upper $upper');
      }
      final lowerTick = _gridTick(lower, state.tickSizeRaw);
      final higherTick = _gridTick(upper, state.tickSizeRaw);
      await _assertAdmittedTick(lowerTick, marketId, state);
      await _assertAdmittedTick(higherTick, marketId, state);
      return RangeTicks(lowerTick: lowerTick, higherTick: higherTick);
    }
    final strike = m.strike;
    if (strike != 'reference') {
      if (strike is! num) {
        throw PredictInputError(
            "strike must be a number or 'reference', got $strike");
      }
      final ticks =
          binaryRangeTicks(priceToRaw(strike), m.side, state.tickSizeRaw);
      await _assertAdmittedTick(ticks.lowerTick, marketId, state);
      await _assertAdmittedTick(ticks.higherTick, marketId, state);
      return ticks;
    }
    final tick = await markets_reads.referenceTick(_client, _config, marketId);
    if (tick == null) {
      throw PredictInputError(
          'reference price not set yet for ${m.underlying} @ ${m.expiryMs} — '
          'retry shortly or pass a numeric strike');
    }
    return m.side == 'up'
        ? RangeTicks(lowerTick: tick, higherTick: POS_INF_TICK)
        : RangeTicks(lowerTick: BigInt.zero, higherTick: tick);
  }

  // Raw payout quantity must land on a lot boundary — the chain rejects
  // otherwise. From the config in play, not the exported testnet constant — a
  // deployment with a different `position_lot_size` must not be validated
  // against testnet's.
  void _assertLot(BigInt quantityRaw) {
    final lot = BigInt.from(cfg.units.positionLotSize);
    if (quantityRaw % lot != BigInt.zero) {
      throw PredictInputError('quantity $quantityRaw raw is not a whole '
          '$lot-unit lot (position_lot_size)');
    }
  }

  // Shared construction for tx.mint and read.quoteMint. The quote dry-runs
  // the same mint the trade sends; quoteMint omits the caller's
  // cost/probability caps (they only gate via abort and don't change the
  // receipt numbers).
  Future<Transaction> _buildMint(
      String owner, MarketDescriptor m, MintOptions opts) async {
    final feeds = _feeds(m.underlying);
    final resolved = await _resolveMarket(
        underlying: m.underlying, expiryMs: m.expiryMs, marketId: m.marketId);
    final quantityRaw = usdcToRaw(opts.quantity);
    _assertLot(quantityRaw);
    final ticks = await _strikeTicks(m, resolved.id, resolved.state);
    final maxCost = opts.maxCost;
    final maxProbability = opts.maxProbability;
    return _txOf(trade.mintExactQuantity(
      _config,
      expiryMarketId: resolved.id,
      wrapperId: wrapperIdFor(owner),
      lowerTick: ticks.lowerTick,
      higherTick: ticks.higherTick,
      quantityRaw: quantityRaw,
      maxCostRaw: maxCost != null ? usdcToRaw(maxCost) : null,
      maxProbabilityRaw:
          maxProbability != null ? probabilityToRaw(maxProbability) : null,
      feeds: feeds,
    ));
  }

  Future<Transaction> _buildMintCost(
      String owner, MarketDescriptor m, MintCostOptions opts) async {
    final feeds = _feeds(m.underlying);
    final maxCostRaw = usdcToRaw(opts.spend);
    final minQuantityRaw = usdcToRaw(opts.minQuantity);
    final resolved = await _resolveMarket(
        underlying: m.underlying, expiryMs: m.expiryMs, marketId: m.marketId);
    final ticks = await _strikeTicks(m, resolved.id, resolved.state);
    return _txOf(trade.mintExactCost(
      _config,
      expiryMarketId: resolved.id,
      wrapperId: wrapperIdFor(owner),
      lowerTick: ticks.lowerTick,
      higherTick: ticks.higherTick,
      maxCostRaw: maxCostRaw,
      minQuantityRaw: minQuantityRaw,
      feeds: feeds,
    ));
  }

  Future<MintQuote> _quoteMintTransaction(String owner, Transaction tx) async {
    final events = await simulateWithEvents(_client, tx, owner);
    final r = exactlyOne(
        decodeMints(cfg, DecodableTransactionResult.fromProtoEvents(events)),
        'OrderMinted');
    // Mirrors the deployed `compute_mint_quote`'s all_in_cost exactly:
    // premium + (trading − subsidy) + builder + penalty + inventory-impact.
    // `referral_fee` is deliberately NOT added — it is a portion OF the
    // trader-paid trading fee and congestion surcharge, not an extra debit.
    final costRaw = r.raw.premium +
        (r.raw.tradingFee - r.raw.feeIncentiveSubsidy) +
        r.raw.builderFee +
        r.raw.penaltyFee +
        r.raw.inventoryImpactCharge;
    return MintQuote(
      entryProbability: r.entryProbability,
      premium: r.premium,
      fees: r.fees,
      cost: rawToUsdc(costRaw),
      quantity: r.quantity,
      raw: MintQuoteRaw(
        premium: r.raw.premium,
        cost: costRaw,
        quantity: r.raw.quantity,
        entryProbability: r.raw.entryProbability,
      ),
    );
  }

  // Shared construction for tx.redeem and read.quoteRedeem.
  Future<Transaction> _buildRedeem(
      String owner, MarketDescriptor m, CloseOptions opts) async {
    final feeds = _feeds(m.underlying);
    final resolved = await _resolveMarket(
        underlying: m.underlying, expiryMs: m.expiryMs, marketId: m.marketId);
    final closeQuantityRaw = usdcToRaw(opts.quantity);
    _assertLot(closeQuantityRaw);
    return _txOf(trade.redeemLive(
      _config,
      expiryMarketId: resolved.id,
      wrapperId: wrapperIdFor(owner),
      orderId: opts.orderId,
      closeQuantityRaw: closeQuantityRaw,
      feeds: feeds,
    ));
  }

  // Raw strike for anonymous pricing: numeric strikes validate against the
  // tick grid; 'reference' reads the market's reference tick fresh (unset →
  // typed error).
  Future<BigInt> _strikeRawFor(
      MarketDescriptor m, String marketId, MarketState state) async {
    final strike = m.strike;
    if (strike != 'reference') {
      if (strike is! num) {
        throw PredictInputError(
            "strike must be a number or 'reference', got $strike");
      }
      // Same validation as the mint path: on the grid AND inside the finite
      // tick domain (0 / POS_INF are the ±inf sentinels, not quotable
      // strikes).
      return _gridTick(strike, state.tickSizeRaw) * state.tickSizeRaw;
    }
    final tick = await markets_reads.referenceTick(_client, _config, marketId);
    if (tick == null) {
      throw PredictInputError(
          'reference price not set yet for ${m.underlying} @ ${m.expiryMs} — '
          'retry shortly or pass a numeric strike');
    }
    return tick * state.tickSizeRaw;
  }
}

/// `client.tx.*` — each returns a ready-to-sign [Transaction].
/// Market-resolving builders are async.
class PredictTxBuilders {
  final PredictClient _c;
  PredictTxBuilders._(this._c);

  /// Create the sender's canonical account wrapper and share it.
  Transaction createManager() => _txOf(accountContract(_c.cfg).createAccount());

  /// Deposit [amountUsdc] (human units, [num] or decimal [String]) into the
  /// owner's account.
  ///
  /// `create: true` composes first-time funding into ONE PTB: create the
  /// account wrapper, deposit into it through the fresh handle, and `share`
  /// it LAST (once shared, by-value use of the handle is over). The wrapper
  /// is derived from the transaction SENDER (`account_registry::new` takes no
  /// owner), so [owner] MUST be the address that signs this transaction — a
  /// sponsored/backend signer would silently fund its own fresh account
  /// instead. The caller also asserts the account does not exist yet: `new`
  /// ABORTS at the deterministic address if it already exists — no chain read
  /// is done here. Gate on your own existence check (`wrapperIdFor(owner)` +
  /// a getObject), or retry without the flag on that abort.
  ///
  /// Without `create`, the sourced coin goes into the existing account's
  /// stored balance via the PTB-callable `deposit_funds` (folds settle →
  /// authorize → load → deposit; clock auto-injected). Command order is auth
  /// → deposit (auth is a hot potato consumed by the deposit).
  Transaction deposit(String owner, Object amountUsdc, {bool create = false}) {
    final tx = Transaction();
    final coin =
        tx.coin(_c.cfg.quoteCoinType, usdcToRaw(amountUsdc), useGasCoin: false);
    if (create) {
      accountContract(_c.cfg).createAccountAndDeposit(
        coin: coin,
        coinType: _c.cfg.quoteCoinType,
      )(tx);
    } else {
      authed.depositFunds(
        config: _c._config,
        wrapper: _c.wrapperIdFor(owner),
        coin: coin,
        typeArguments: [_c.cfg.quoteCoinType],
      )(tx);
    }
    return tx;
  }

  /// Withdraw [amountUsdc] from the account back to [owner]. By default the
  /// funds land in the owner's USDC *address balance* (the versionless
  /// accumulator) via `0x2::coin::send_funds` — no coin-object churn, and
  /// they merge into the same balance [deposit] draws from, closing the loop.
  /// Pass `toCoinObject: true` to instead receive a discrete `Coin<T>` object
  /// (for wallets/explorers that only render coin objects, or to compose the
  /// coin further in your own PTB). Either way the underlying
  /// `withdraw_funds` returns the raw `Coin<T>` — the PTB-callable form that
  /// folds settle → authorize → load → withdraw; command order is auth →
  /// withdraw.
  Transaction withdraw(String owner, Object amountUsdc,
      {bool toCoinObject = false}) {
    final tx = Transaction();
    final coin = authed.withdrawFunds(
      config: _c._config,
      wrapper: _c.wrapperIdFor(owner),
      amount: usdcToRaw(amountUsdc),
      typeArguments: [_c.cfg.quoteCoinType],
    )(tx);
    if (toCoinObject) {
      tx.transferObjects([coin], owner);
    } else {
      // The full-length framework address: the TS builder normalizes the
      // target at serialization, the Dart builder keeps it verbatim.
      tx.moveCall(
        '${normalizeSuiAddress('0x2')}::coin::send_funds',
        typeArguments: [_c.cfg.quoteCoinType],
        arguments: [coin, tx.pureAddress(owner)],
      );
    }
    return tx;
  }

  /// Mint an exact payout quantity (see [MintOptions]).
  Future<Transaction> mint(
          String owner, MarketDescriptor m, MintOptions opts) =>
      _c._buildMint(owner, m, opts);

  /// V2 all-in budget mint; use `minQuantity` to protect the fill against
  /// slippage.
  Future<Transaction> mintCost(
          String owner, MarketDescriptor m, MintCostOptions opts) =>
      _c._buildMintCost(owner, m, opts);

  /// Mint by spending up to a premium budget (see [MintAmountOptions]).
  Future<Transaction> mintAmount(
      String owner, MarketDescriptor m, MintAmountOptions opts) async {
    final feeds = _c._feeds(m.underlying);
    // The chain requires a positive all-in cost cap (EMintCostCapRequired);
    // reject a zero cap pre-flight rather than surface a cryptic Move abort.
    final maxCost = opts.maxCost;
    if (maxCost != null && maxCost <= 0) {
      throw PredictInputError('maxCost must be > 0');
    }
    final resolved = await _c._resolveMarket(
        underlying: m.underlying, expiryMs: m.expiryMs, marketId: m.marketId);
    // No lot check: min_quantity is a floor the chain compares against an
    // already-lot-floored minted quantity, so any floor value is legal.
    final minQuantityRaw = usdcToRaw(opts.minQuantity);
    final ticks = await _c._strikeTicks(m, resolved.id, resolved.state);
    return _txOf(trade.mintExactAmount(
      _c._config,
      expiryMarketId: resolved.id,
      wrapperId: _c.wrapperIdFor(owner),
      lowerTick: ticks.lowerTick,
      higherTick: ticks.higherTick,
      maxPremiumRaw: usdcToRaw(opts.spend),
      minQuantityRaw: minQuantityRaw,
      maxCostRaw: maxCost != null ? usdcToRaw(maxCost) : null,
      feeds: feeds,
    ));
  }

  /// Close a live position (see [CloseOptions]).
  Future<Transaction> redeem(
          String owner, MarketDescriptor m, CloseOptions opts) =>
      _c._buildRedeem(owner, m, opts);

  /// Claim a settled position in full. Takes only the order id — a settled
  /// claim closes the order in full.
  Future<Transaction> claimSettled(
    String owner, {
    required String underlying,
    required Object expiryMs,
    String? marketId,
    required BigInt orderId,
  }) async {
    final resolved = await _c._resolveMarket(
        underlying: underlying, expiryMs: expiryMs, marketId: marketId);
    return _txOf(trade.redeemSettled(
      _c._config,
      expiryMarketId: resolved.id,
      wrapperId: _c.wrapperIdFor(owner),
      orderId: orderId,
    ));
  }

  /// Queue a supply request pulling [amountUsdc] from the account's existing
  /// custody balance. `request_supply` auto-settles USDC then
  /// `account.withdraw`s the payment into queue escrow; the PLP fill is
  /// delivered at the next flush, not returned here. Command order is auth →
  /// request (auth is a hot potato consumed by this call). The `minPlpOut`
  /// slot is the per-request floor on PLP minted at flush —
  /// [PlpSupplyOptions.minPlpOut] when given, otherwise 0 (no floor). At the
  /// shipped attempt count of one, the first flush whose mark quotes less
  /// cancels and refunds the request; three is the configurable maximum, not
  /// the default.
  Transaction supplyPlp(String owner, Object amountUsdc,
          [PlpSupplyOptions options = const PlpSupplyOptions()]) =>
      _txOf(authed.requestSupply(
        config: _c._config,
        wrapper: _c.wrapperIdFor(owner),
        amount: usdcToRaw(amountUsdc),
        minPlpOut: options.minPlpOut ?? BigInt.zero,
      ));

  /// Queue a withdraw request pulling [shares] (raw PLP u64) from account
  /// custody into queue escrow — the Move parameter is named `amount`, but on
  /// `request_withdraw` it counts PLP SHARES, not USDC. Auto-settles
  /// flush-delivered PLP first; the USDC fill lands on the account at the
  /// next flush (no `withdraw_settled` entrypoint). Command order is auth →
  /// request. The `minUsdcOut` slot is the per-request floor on USDC paid at
  /// flush — [PlpWithdrawOptions.minUsdcOut] when given, otherwise 0 (no
  /// floor). At the shipped attempt count of one, the first flush whose mark
  /// quotes less cancels and refunds the request; three is the configurable
  /// maximum, not the default.
  Transaction withdrawPlp(String owner, BigInt shares,
      [PlpWithdrawOptions options = const PlpWithdrawOptions()]) {
    final minUsdcOut = options.minUsdcOut;
    return _txOf(authed.requestWithdraw(
      config: _c._config,
      wrapper: _c.wrapperIdFor(owner),
      amount: shares,
      minUsdcOut: minUsdcOut == null ? BigInt.zero : usdcToRaw(minUsdcOut),
    ));
  }

  /// Cancel a still-pending supply request by queue [index], refunding its
  /// escrowed USDC straight back into the requesting account. Command order
  /// is auth → cancel.
  Transaction cancelSupplyPlp(String owner, BigInt index) =>
      _txOf(authed.cancelSupplyRequest(
        config: _c._config,
        wrapper: _c.wrapperIdFor(owner),
        index: index,
      ));

  /// Cancel a still-pending withdraw request by queue [index], refunding its
  /// escrowed PLP straight back into the requesting account. Command order is
  /// auth → cancel.
  Transaction cancelWithdrawPlp(String owner, BigInt index) =>
      _txOf(authed.cancelWithdrawRequest(
        config: _c._config,
        wrapper: _c.wrapperIdFor(owner),
        index: index,
      ));

  /// Set the account's sticky builder-code attribution to [builderCodeId], an
  /// existing `BuilderCode` object borrowed as `&BuilderCode`. Command order
  /// is auth → set (auth is a hot potato consumed by this call). Lives in the
  /// PREDICT package's `predict_account` module, NOT the account package.
  Transaction setBuilderCode(String owner, String builderCodeId) =>
      _txOf(authed.setBuilderCode(
        config: _c._config,
        wrapper: _c.wrapperIdFor(owner),
        code: builderCodeId,
      ));

  /// Clear the account's sticky builder-code attribution. Command order is
  /// auth → unset.
  Transaction unsetBuilderCode(String owner) => _txOf(authed.unsetBuilderCode(
        config: _c._config,
        wrapper: _c.wrapperIdFor(owner),
      ));
}

/// `client.read.*` — chain reads and dry-run quotes.
class PredictReads {
  final PredictClient _c;
  PredictReads._(this._c);

  /// All tradeable (active) markets with the state a frontend needs to render
  /// and mint: one chain read for ids + one batched PTB for the states.
  Future<List<ActiveMarket>> markets() async {
    final ids = await markets_reads.activeMarketIds(_c._client, _c._config);
    final states =
        await markets_reads.marketStates(_c._client, _c._config, ids);
    return [
      for (var i = 0; i < ids.length; i++)
        ActiveMarket(
          id: ids[i],
          expiryMs: states[i].expiryMs,
          tickSize: fromRaw(states[i].tickSizeRaw, 9),
          admissionTickSize: fromRaw(states[i].admissionTickSizeRaw, 9),
          mintPaused: states[i].mintPaused,
          referencePrice: PredictClient._referencePriceOf(states[i]),
        )
    ];
  }

  /// Validate an app-stored order id against the chain (stale after full
  /// close or partial-close replacement — see
  /// [RedeemReceipt.replacementOrderId]).
  Future<bool> hasPosition(String owner, String marketId, BigInt orderId) =>
      balances_reads.hasPosition(
          _c._client, _c._config, owner, marketId, orderId);

  /// All open positions for an owner, enumerated from the chain (the
  /// account's positions Table): 1 call per page warm, +2 resolution calls
  /// once per owner. Returns `[]` for owners with no Predict account.
  Future<List<OpenPosition>> positions(String owner) async {
    var handle = _c._positionsCache[owner];
    if (handle?.positionsTableId == null) {
      final resolved = await positions_reads.resolvePositionsTable(
          _c._client, _c._config, owner);
      if (resolved == null) return []; // never onboarded — do not cache
      if (resolved.positionsTableId != null) {
        _c._positionsCache[owner] = resolved;
      }
      handle = resolved;
    }
    final tableId = handle!.positionsTableId;
    if (tableId == null) return [];
    return positions_reads.positionsFromTable(_c._client, tableId);
  }

  /// Anonymous board pricing: the chain's probability for both sides of a
  /// strike, from one fresh pricer (no account needed). This is the ↑/↓
  /// button price before a user has onboarded. [m] must be a binary
  /// descriptor (strike-bearing) — anonymous board pricing has no range
  /// semantics.
  Future<({double up, double down})> price(MarketDescriptor m) async {
    final feeds = _c._feeds(m.underlying);
    final resolved = await _c._resolveMarket(
        underlying: m.underlying, expiryMs: m.expiryMs, marketId: m.marketId);
    final strikeRaw = await _c._strikeRawFor(m, resolved.id, resolved.state);
    final prices = await markets_reads.rangePrices(
      _c._client,
      _c._config,
      resolved.id,
      feeds,
      strikeRaw,
      resolved.state.tickSizeRaw,
    );
    return (
      up: rawToProbability(prices.upRaw),
      down: rawToProbability(prices.downRaw),
    );
  }

  /// A client-side board pricer for one market: ONE simulate reads the
  /// chain's resolved pricer (already forward-selected + rolled to now), then
  /// prices every strike LOCALLY with no further chain calls —
  /// `pricer.up(strike)`, `.down(strike)`, `.range(lo, hi)`,
  /// `.strikeAt(p)`. Use this to paint a whole board instantly; [price] /
  /// [quoteMint] stay the authoritative per-strike quote at trade time.
  /// Throws the same typed stale-oracle/expired [PredictMoveError] that
  /// [price] would when the chain itself cannot quote.
  Future<BoardPricerWithSources> pricer(
      {required String underlying, required Object expiryMs}) async {
    final feeds = _c._feeds(underlying);
    final resolved =
        await _c._resolveMarket(underlying: underlying, expiryMs: expiryMs);
    final snap =
        await readPricerSnapshot(_c._client, _c._config, resolved.id, feeds);
    final board = boardPricer(snap);
    return BoardPricerWithSources(
        forward: board.forward, svi: board.svi, asOf: snap.sources);
  }

  /// Exact pre-trade quote: dry-runs the caller's own mint (same tx as
  /// `tx.mint`) and decodes the receipt. Requires a funded account; throws
  /// the same typed errors the real trade would — quote doubles as preflight.
  Future<MintQuote> quoteMint(String owner, MarketDescriptor m,
      {required num quantity}) async {
    final tx = await _c._buildMint(owner, m, MintOptions(quantity: quantity));
    return _c._quoteMintTransaction(owner, tx);
  }

  /// Simulate the v2 all-in budget mint against current account and market
  /// state.
  Future<MintQuote> quoteMintCost(
          String owner, MarketDescriptor m, MintCostOptions opts) async =>
      _c._quoteMintTransaction(owner, await _c._buildMintCost(owner, m, opts));

  /// Exact pre-close quote: dry-runs the caller's own redeem and decodes the
  /// receipt — the informed close against the floor-less deployed redeem.
  Future<RedeemQuote> quoteRedeem(
      String owner, MarketDescriptor m, CloseOptions opts) async {
    final tx = await _c._buildRedeem(owner, m, opts);
    final events = await simulateWithEvents(_c._client, tx, owner);
    final r = exactlyOne(
        decodeRedeems(
            _c.cfg, DecodableTransactionResult.fromProtoEvents(events)),
        'order-redeemed');
    return RedeemQuote(
      proceeds: r.proceeds,
      gross: r.gross,
      fees: r.fees,
      quantityClosed: r.quantityClosed,
      remaining: r.remaining,
      raw: RedeemQuoteRaw(
        proceeds: r.raw.proceeds,
        gross: r.raw.gross,
        quantityClosed: r.raw.quantityClosed,
      ),
    );
  }

  /// A resolved live market's on-chain state summary, or null when no market
  /// exists for the coordinates. Deliberately re-queries and overwrites the
  /// cache instead of reading through it: this read must return live state
  /// (nav, mintPaused), and refreshing the cache on the way keeps later tx
  /// builds consistent.
  Future<MarketSummary?> market(
      {required String underlying, required Object expiryMs}) async {
    final expiry = PredictClient._expiryOf(expiryMs);
    final u = _c._underlying(underlying);
    final id =
        await markets_reads.expiryMarketId(_c._client, _c._config, u, expiry);
    if (id == null) return null;
    final state = await markets_reads.marketState(_c._client, _c._config, id);
    _c._marketCache['$underlying:$expiry'] =
        _ResolvedMarket(id: id, state: state);
    final navRaw =
        await markets_reads.currentNav(_c._client, _c._config, id, u);
    return MarketSummary(
      id: id,
      expiryMs: state.expiryMs,
      tickSize: fromRaw(state.tickSizeRaw, 9), // strike/price scale
      admissionTickSize: fromRaw(state.admissionTickSizeRaw, 9),
      mintPaused: state.mintPaused,
      nav: rawToUsdc(navRaw),
      referencePrice: PredictClient._referencePriceOf(state),
    );
  }

  /// The owner's stored quote-coin balance, in human units.
  Future<double> balance(String owner) async => rawToUsdc(await balances_reads
      .accountBalance(_c._client, _c._config, owner, _c.cfg.quoteCoinType));

  /// PLP shares held in the owner's account custody (raw u64, 6-decimal PLP
  /// coin).
  Future<BigInt> plpBalance(String owner) => balances_reads.accountBalance(
      _c._client, _c._config, owner, _c.cfg.coinTypes.plp);

  /// Aggregate pool figures (see [PoolSummary]).
  Future<PoolSummary> pool() async {
    final s = await pool_reads.poolStats(_c._client, _c._config);
    return PoolSummary(
      plpTotalSupply: s.plpTotalSupply, // shares raw (6-decimal)
      idleUsdc: rawToUsdc(s.idleBalance),
      // These are queue LENGTHS (counts of pending requests), not amounts.
      supplyRequestsPending: s.supplyRequestsPending.toInt(),
      withdrawRequestsPending: s.withdrawRequestsPending.toInt(),
    );
  }
}

/// `client.decode.*` — pure event parsing (no network): pass the
/// executed/simulated transaction result (with events included) and get a
/// typed receipt back. Singular forms throw unless exactly one matching event
/// exists; plural forms return all (an integrator batching N actions in one
/// PTB gets N receipts).
class PredictDecoders {
  final PredictClient _c;
  PredictDecoders._(this._c);

  MintReceipt mint(DecodableTransactionResult r) =>
      exactlyOne(decodeMints(_c.cfg, r), 'OrderMinted');
  List<MintReceipt> mints(DecodableTransactionResult r) =>
      decodeMints(_c.cfg, r);
  RedeemReceipt redeem(DecodableTransactionResult r) =>
      exactlyOne(decodeRedeems(_c.cfg, r), 'order-redeemed');
  List<RedeemReceipt> redeems(DecodableTransactionResult r) =>
      decodeRedeems(_c.cfg, r);
  ClaimReceipt claim(DecodableTransactionResult r) =>
      exactlyOne(decodeClaims(_c.cfg, r), 'SettledOrderRedeemed');
  List<ClaimReceipt> claims(DecodableTransactionResult r) =>
      decodeClaims(_c.cfg, r);
  CreateManagerReceipt createManager(DecodableTransactionResult r) =>
      exactlyOne(decodeAccountsCreated(_c.cfg, r), 'AccountCreated');
  BalanceChangeReceipt deposit(DecodableTransactionResult r) =>
      exactlyOne(decodeDeposits(_c.cfg, r), 'Deposited');
  BalanceChangeReceipt withdraw(DecodableTransactionResult r) =>
      exactlyOne(decodeWithdrawals(_c.cfg, r), 'Withdrawn');
  PlpRequestReceipt plpRequest(DecodableTransactionResult r) =>
      exactlyOne(decodePlpRequests(_c.cfg, r), 'supply/withdraw-requested');
  PlpCancelReceipt plpCancel(DecodableTransactionResult r) =>
      exactlyOne(decodePlpCancels(_c.cfg, r), 'RequestCancelled');
  BuilderCodeReceipt builderCode(DecodableTransactionResult r) =>
      exactlyOne(decodeBuilderCodeSets(_c.cfg, r), 'BuilderCodeSet');
}
