/// Trade-call composition, mirroring `predict/tx/trade.ts`.
///
/// The three commands every live-flow trade is: load a fresh market-bound
/// `Pricer`, mint owner auth, then the one `expiry_market::*` call that
/// consumes both.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../../contracts/deepbook_predict/expiry_market.dart' as expiry_market;
import '../../contracts/utils.dart' show MoveCallBuilder;
import '../config.dart' show GeneratedConfig;
import '../units.dart' show U64_MAX;
import 'common.dart' show withAuth;

/// The oracle feed object ids a live market's pricer reads. Grouped so
/// callers pass one bundle; the deployment's per-underlying ids live in
/// `cfg.underlyings[symbol]`, named to match the deployment manifest.
class MarketFeeds {
  /// `&PythFeed` — spot price feed.
  final String pythFeed;

  /// `&BlockScholesValueStore` — Black-Scholes value store.
  final String blockScholesValueStore;

  /// `&BlockScholesSVIStore` — SVI-surface store.
  final String blockScholesSviStore;

  const MarketFeeds({
    required this.pythFeed,
    required this.blockScholesValueStore,
    required this.blockScholesSviStore,
  });
}

/// Load a fresh `Pricer` from the live oracle feeds. Every live-flow trade
/// call (`mint_*`, `redeem_live`) borrows this `&Pricer` and it must be
/// loaded first in the PTB. Deployed sig `load_live_pricer`
/// (expiry_market.move): market, config, propbook_registry
/// (&OracleRegistry), pyth, bs_values, bs_svi, clock (auto-injected).
/// `config` and `propbook_registry` are supplied by the config slice, not
/// named here.
///
/// The `/sessions` Predict wrappers take `pricer` as a PTB result of this
/// call, so it is part of the published surface.
TransactionResult Function(Transaction) loadLivePricer(
  GeneratedConfig config, {
  required String expiryMarketId,
  required MarketFeeds feeds,
}) {
  return (tx) => expiry_market.loadLivePricer(
        config: config,
        arguments: {
          'market': expiryMarketId,
          'pyth': feeds.pythFeed,
          'bsValues': feeds.blockScholesValueStore,
          'bsSvi': feeds.blockScholesSviStore,
        },
      )(tx);
}

// The three commands every live-flow trade is: load a fresh market-bound
// `Pricer`, mint owner auth, then the one call that consumes both. Only the
// pricer is composed here — [build] returns a `withAuth` call, which is the
// other two commands.
MoveCallBuilder _liveTrade(
  GeneratedConfig config,
  String expiryMarketId,
  MarketFeeds feeds,
  MoveCallBuilder Function(TransactionResult pricer) build,
) {
  return (tx) {
    final pricer = loadLivePricer(config,
        expiryMarketId: expiryMarketId, feeds: feeds)(tx);
    return build(pricer)(tx);
  };
}

/// Mint a position of an exact [quantityRaw], capped by cost/probability
/// ceilings, returning the new order id (u256). Command order is pricer →
/// auth → mint (auth is a hot potato consumed by this call).
/// [maxCostRaw]/[maxProbabilityRaw] default to [U64_MAX] (no slippage cap).
/// Deployed sig `mint_exact_quantity`.
MoveCallBuilder mintExactQuantity(
  GeneratedConfig config, {
  required String expiryMarketId,
  required String wrapperId,
  required BigInt lowerTick,
  required BigInt higherTick,
  required BigInt quantityRaw,
  BigInt? maxCostRaw,
  BigInt? maxProbabilityRaw,
  required MarketFeeds feeds,
}) {
  return _liveTrade(
      config,
      expiryMarketId,
      feeds,
      (pricer) => withAuth(
          config,
          (auth) => expiry_market.mintExactQuantity(
                config: config,
                arguments: {
                  'market': expiryMarketId,
                  'wrapper': wrapperId,
                  'auth': auth,
                  'pricer': pricer,
                  'lowerTick': lowerTick,
                  'higherTick': higherTick,
                  'quantity': quantityRaw,
                  'maxCost': maxCostRaw ?? U64_MAX,
                  'maxProbability': maxProbabilityRaw ?? U64_MAX,
                },
              )));
}

/// Mint by spending up to [maxPremiumRaw] (raw quote units), enforcing a
/// [minQuantityRaw] floor on the position received and a [maxCostRaw] all-in
/// ceiling, returning the new order id (u256). Command order is pricer → auth
/// → mint. Deployed sig `mint_exact_amount`.
MoveCallBuilder mintExactAmount(
  GeneratedConfig config, {
  required String expiryMarketId,
  required String wrapperId,
  required BigInt lowerTick,
  required BigInt higherTick,
  required BigInt maxPremiumRaw,
  required BigInt minQuantityRaw,
  BigInt? maxCostRaw,
  required MarketFeeds feeds,
}) {
  return _liveTrade(
      config,
      expiryMarketId,
      feeds,
      (pricer) => withAuth(
          config,
          (auth) => expiry_market.mintExactAmount(
                config: config,
                arguments: {
                  'market': expiryMarketId,
                  'wrapper': wrapperId,
                  'auth': auth,
                  'pricer': pricer,
                  'lowerTick': lowerTick,
                  'higherTick': higherTick,
                  'maxPremium': maxPremiumRaw,
                  'minQuantity': minQuantityRaw,
                  'maxCost': maxCostRaw ?? U64_MAX,
                },
              )));
}

/// Mint within an all-in budget, including fees, using the v2 entrypoint.
MoveCallBuilder mintExactCost(
  GeneratedConfig config, {
  required String expiryMarketId,
  required String wrapperId,
  required BigInt lowerTick,
  required BigInt higherTick,
  required BigInt maxCostRaw,
  required BigInt minQuantityRaw,
  required MarketFeeds feeds,
}) {
  return _liveTrade(
      config,
      expiryMarketId,
      feeds,
      (pricer) => withAuth(
          config,
          (auth) => expiry_market.mintExactCost(
                config: config,
                arguments: {
                  'market': expiryMarketId,
                  'wrapper': wrapperId,
                  'auth': auth,
                  'pricer': pricer,
                  'lowerTick': lowerTick,
                  'higherTick': higherTick,
                  'maxCost': maxCostRaw,
                  'minQuantity': minQuantityRaw,
                },
              )));
}

/// Owner-authorized redeem of a live (not-yet-settled) position: close
/// [closeQuantityRaw] of [orderId] at the live pricer's mark, enforcing
/// close-side slippage floors ([minProbabilityRaw]/[minProceedsRaw], default
/// 0 = uncapped). Returns `Option<u256>`: the replacement order id when a
/// partial close leaves quantity open, else none. Command order is pricer →
/// auth → redeem. Deployed sig `redeem_live`.
MoveCallBuilder redeemLive(
  GeneratedConfig config, {
  required String expiryMarketId,
  required String wrapperId,
  required BigInt orderId,
  required BigInt closeQuantityRaw,
  BigInt? minProbabilityRaw,
  BigInt? minProceedsRaw,
  required MarketFeeds feeds,
}) {
  return _liveTrade(
      config,
      expiryMarketId,
      feeds,
      (pricer) => withAuth(
          config,
          (auth) => expiry_market.redeemLive(
                config: config,
                arguments: {
                  'market': expiryMarketId,
                  'wrapper': wrapperId,
                  'auth': auth,
                  'pricer': pricer,
                  'orderId': orderId,
                  'closeQuantity': closeQuantityRaw,
                  'minProbability': minProbabilityRaw ?? BigInt.zero,
                  'minProceeds': minProceedsRaw ?? BigInt.zero,
                },
              )));
}

/// Owner-authorized redeem of a settled position: closes [orderId] IN FULL
/// against the recorded settlement price (the deployed entrypoint takes no
/// quantity — a settled claim is all-or-nothing). No live pricer (settlement
/// price is fixed); auth is consumed by the call. Deployed sig
/// `redeem_settled` (owner-auth form). The keeper-facing
/// `redeem_settled_permissionless` is a separate entrypoint, out of scope for
/// this SDK.
MoveCallBuilder redeemSettled(
  GeneratedConfig config, {
  required String expiryMarketId,
  required String wrapperId,
  required BigInt orderId,
}) {
  return withAuth(
      config,
      (auth) => expiry_market.redeemSettled(
            config: config,
            arguments: {
              'market': expiryMarketId,
              'wrapper': wrapperId,
              'auth': auth,
              'orderId': orderId,
            },
          ));
}
