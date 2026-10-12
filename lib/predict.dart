/// DeepBook Predict — `package:deepbook/predict.dart`.
///
/// Mirrors the official `@mysten/deepbook-v3/predict` subpath: market
/// discovery, quotes, mint/redeem/claim, PLP, typed receipts, the client-side
/// board pricer (`pricing`), and the exact-integer cost engine (`cost`). Like
/// the official subpath, this entry point is a separate library — importing
/// it does not load spot or margin code, and
/// `package:deepbook/deepbook.dart` is unchanged.
///
/// The curated surface is the [PredictClient] facade plus the value types,
/// unit conversions, tick helpers, typed errors, and typed execution-result
/// decoders — and, for composing your own PTBs, the auth/derivation
/// primitives and trade-call compositions below plus the generated move-call
/// bindings.
///
/// ### Differences from the TypeScript SDK
///
///  - **No `predict()` client extension.** The official subpath registers
///    itself on a Sui client via `client.$extend(predict({ network }))` and
///    exports a `PredictCompatibleClient` type. Dart has no client-extension
///    mechanism, so construct [PredictClient] directly — it is the same
///    facade (`tx.*` / `read.*` / `decode.*`) the extension would have
///    installed, and there is no `predict` function or
///    `PredictCompatibleClient` type here.
///  - **`PredictConfig.predictV1` is required.** The official field is
///    optional and falls back to `packages.predict`. The shipped deployment
///    records always carry it; when hand-building a config for your own
///    not-yet-upgraded deployment, set `predictV1` to the same value as
///    `predict`.
///
/// ### Namespacing differences
///
/// The official subpath exports `pricing.*` and `cost.*` as namespaces and 17
/// generated binding modules as `*MoveCalls` / `*Events` namespaces. Dart has
/// no namespace exports, so:
///
///  - The float pricer (`pricing.*`) and integer cost engine (`cost.*`) are
///    exported FLAT here. Two official names are adjusted to avoid collision:
///    `cost.rangeProbability` is [rangeProbabilityRaw] (the float
///    `pricing.rangeProbability` keeps the plain name), and the package
///    root's testnet convenience `POSITION_LOT_SIZE` is
///    [TESTNET_POSITION_LOT_SIZE] (the Move constant keeps
///    [POSITION_LOT_SIZE]).
///  - The generated binding modules are exported flat with the generic
///    object-id/cap helpers (`id`, `destroy`) hidden, since several modules
///    define them; every other builder and BCS struct keeps its official
///    name. Every module is also published whole as its own library —
///    `package:deepbook/predict/<module>.dart` (for example
///    `package:deepbook/predict/pause_cap.dart` for `pause_cap.destroy`, or
///    `package:deepbook/predict/expiry_market.dart` for the on-chain
///    `MintQuote` BCS struct) and `package:deepbook/predict/propbook/...`
///    for the pricer-store modules — import one with a prefix to reach
///    hidden symbols or to avoid collisions with your own code.
library;

// === Facade ===
export 'src/predict/client.dart'
    show
        TESTNET_POSITION_LOT_SIZE,
        PredictClient,
        PredictTxBuilders,
        PredictReads,
        PredictDecoders,
        ActiveMarket,
        CloseOptions,
        MarketDescriptor,
        MarketSummary,
        MintAmountOptions,
        MintCostOptions,
        MintOptions,
        MintQuote,
        MintQuoteRaw,
        PlpSupplyOptions,
        PlpWithdrawOptions,
        PoolSummary,
        RedeemQuote,
        RedeemQuoteRaw,
        BoardPricerWithSources;

// === Composition with foreign packages === auth + deterministic account
// addressing for PTBs that compose predict accounts with packages this SDK
// doesn't know (e.g. `deepbook_core_account` spot trading).
// `deriveAccountWrapperId` is the pure `(cfg, owner)` form of `wrapperIdFor`
// for contexts with no client instance. These are Predict-config-bound
// conveniences over `package:deepbook/account.dart`, which owns the shared
// account primitive — reach for its `AccountContract` to drive it directly.
export 'src/predict/tx/common.dart'
    show deriveAccountWrapperId, generateAuth, withAuth;

// === Config ===
export 'src/predict/config.dart'
    show
        MAINNET_CONFIG,
        TESTNET_CONFIG,
        getConfig,
        getDeployment,
        getUnits,
        toGeneratedConfig,
        GeneratedConfig,
        PredictConfig,
        PredictIds,
        PredictPackages,
        PredictObjects,
        PredictCoinTypes,
        UnderlyingConfig,
        UnderlyingIds,
        DeploymentInfo,
        DeploymentUnits;
export 'src/deployments/deployments.dart'
    show MAINNET_DEPLOYMENT, MAINNET_UNITS, TESTNET_DEPLOYMENT, TESTNET_UNITS;

// === Units (raw ⇄ human conversions) === domain-specific only; the generic
// `toRaw`/`fromRaw` primitives stay internal to avoid colliding with
// consumers' own helpers — except `fromRaw`, which `cost.*` result docs
// reference; it remains internal here too, matching the official surface.
export 'src/predict/units.dart'
    show
        U64_MAX,
        priceToRaw,
        probabilityToRaw,
        rawToPrice,
        rawToProbability,
        rawToUsdc,
        usdcToRaw;

// === Ticks ===
export 'src/predict/ticks.dart'
    show POS_INF_TICK, RangeTicks, Side, binaryRangeTicks;

// === Client-side pricing === the deployed SVI digital math (skew-corrected,
// signed params, roll-down) as a float port: `upProbability`, `boardPricer`,
// `rollDown`, `forward`, types `Svi` / `PricerInputs` / `BoardPricer`.
// Turnkey path: `client.read.pricer(...)` reads the chain's resolved pricer
// once, then prices a whole board locally.
export 'src/predict/pricing.dart';
export 'src/predict/reads/pricing.dart' show PricerSnapshot, PricerSources;

// === Client-side cost === the deployed FEE math as an exact integer port, so
// a quote needs no chain call: `mintCost` (all-in debit for a quantity),
// `mintCostForBudget` (the `mint_exact_cost` budget search),
// `redeemLiveProceeds` (net credited by a live close), plus the components
// they are built from. Probabilities come from the pricing exports or from
// the chain (`client.read.price`); the fee policy is the market's
// `MarketCreated` snapshot, with `SHIPPED_FEE_POLICY` as the shipped
// template.
export 'src/predict/cost.dart';

// === Errors === includes the shared package error types this subpath's
// config accessors throw ([ConfigurationError] from `getConfig` and friends),
// so a predict-only consumer can catch them without importing the root.
export 'src/errors.dart'
    show DeepBookError, ConfigurationError, ValidationError;
export 'src/predict/errors.dart'
    show PredictInputError, PredictMoveError, decodeMoveAbort;

// === Client seam + position type used in public read signatures ===
export 'src/predict/reads/inspect.dart'
    show ReadClient, inspectReturns, simulateWithEvents;
export 'src/predict/reads/positions.dart' show OpenPosition, PositionsHandle;

// === Execution-result decoders and receipt types ===
export 'src/predict/decode.dart';

// The `/sessions` Predict wrappers take `pricer` as a PTB result of
// `loadLivePricer`, so it has to be reachable from the published surface for
// those builders to be composable at all — along with the trade-call
// compositions built on it.
export 'src/predict/tx/trade.dart'
    show
        MarketFeeds,
        loadLivePricer,
        mintExactAmount,
        mintExactCost,
        mintExactQuantity,
        redeemLive,
        redeemSettled;

// === Move-call bindings === the generated transaction thunks for every
// Predict module with a callable function, for putting Predict calls into a
// PTB you are building — each facade `tx.*` builder returns a finished
// `Transaction` instead. Pass `config: toGeneratedConfig(cfg)` and the shared
// objects fill themselves in; owner-authorized calls take an `Auth` from
// `generateAuth(cfg)`. Each module also carries its BCS structs; the
// `*_events` modules are event layouts only. The generic `id`/`destroy`
// helpers several modules share are hidden from this flat export — import
// the module's own library, `package:deepbook/predict/<module>.dart`, with a
// prefix to reach them (and anything else hidden below).
export 'src/contracts/deepbook_predict/admin.dart' hide $moduleName, id;
export 'src/contracts/deepbook_predict/builder_code.dart' hide $moduleName, id;
export 'src/contracts/deepbook_predict/builder_code_events.dart'
    hide $moduleName;
export 'src/contracts/deepbook_predict/config_events.dart' hide $moduleName;
export 'src/contracts/deepbook_predict/expiry_market.dart'
    hide
        $moduleName,
        id,
        loadLivePricer,
        mintExactAmount,
        mintExactCost,
        mintExactQuantity,
        redeemLive,
        redeemSettled,
        // These three carry the names of the cost engine's exports (the BCS
        // struct of the on-chain MintQuote and two fee getters); the exact
        // integer ports keep the flat names.
        MintQuote,
        builderFee,
        feeIncentiveSubsidy,
        tradingFee;
export 'src/contracts/deepbook_predict/market_lifecycle_cap.dart'
    hide $moduleName, id, destroy;
export 'src/contracts/deepbook_predict/market_manager.dart' hide $moduleName;
export 'src/contracts/deepbook_predict/order_events.dart' hide $moduleName;
export 'src/contracts/deepbook_predict/pause_cap.dart'
    hide $moduleName, id, destroy;
export 'src/contracts/deepbook_predict/plp.dart' hide $moduleName, id;
export 'src/contracts/deepbook_predict/pool_valuation_cap.dart'
    hide $moduleName, id, destroy;
export 'src/contracts/deepbook_predict/predict_account.dart' hide $moduleName;
export 'src/contracts/deepbook_predict/pricing.dart'
    hide $moduleName, probability;
export 'src/contracts/deepbook_predict/protocol_config.dart'
    hide $moduleName, id;
export 'src/contracts/deepbook_predict/range_codec.dart' hide $moduleName;
export 'src/contracts/deepbook_predict/registry.dart' hide $moduleName, id;
export 'src/contracts/deepbook_predict/vault_events.dart' hide $moduleName;
