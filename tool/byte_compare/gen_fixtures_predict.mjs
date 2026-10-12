// Generates comparison fixtures for the /predict subpath from the OFFICIAL
// @mysten/deepbook-v3 TypeScript SDK. Companion to gen_fixtures.mjs and
// gen_fixtures_sessions.mjs (kept separate so the suites regenerate
// independently).
//
// Node resolves bare imports against the SCRIPT's own path, so copy this file
// into the package before running (the package must be built:
// `pnpm --filter @mysten/deepbook-v3 build`):
//   cd <ts-sdks>/packages/deepbook-v3
//   cp <this-file> ./gen.tmp.mjs && node ./gen.tmp.mjs <out-dir>; rm ./gen.tmp.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { toBase64 } from '@mysten/sui/utils';
import {
  PredictClient,
  getConfig,
  toGeneratedConfig,
  generateAuth,
  deriveAccountWrapperId,
  loadLivePricer,
  binaryRangeTicks,
  POS_INF_TICK,
  U64_MAX,
  cost,
  pricing,
  expiryMarketMoveCalls,
  orderEvents,
  vaultEvents,
  builderCodeEvents,
} from '@mysten/deepbook-v3/predict';
import { accountEvents } from '@mysten/deepbook-v3/account';
import { Transaction } from '@mysten/sui/transactions';

const outDir = process.argv[2] ?? 'fixtures';
mkdirSync(outDir, { recursive: true });

const OWNER =
  '0x00000000000000000000000000000000000000000000000000000000000000aa';
const OWNER2 =
  '0x000000000000000000000000000000000000000000000000000000000000cafe';
const MARKET =
  '0x0000000000000000000000000000000000000000000000000000000000000011';
const BUILDER_CODE =
  '0x0000000000000000000000000000000000000000000000000000000000000033';

const cfg = getConfig('testnet');
const gen = toGeneratedConfig(cfg);
const feeds = cfg.underlyings['BTC'];
const FEEDS = {
  pythFeed: feeds.pythFeed,
  blockScholesValueStore: feeds.blockScholesValueStore,
  blockScholesSviStore: feeds.blockScholesSviStore,
};
// The sync tx.* builders never touch the client; reads are not exercised here.
const client = new PredictClient({ network: 'testnet', client: undefined });

const write = (name, data) =>
  writeFileSync(
    join(outDir, `${name}.json`),
    JSON.stringify(
      data,
      (_, v) => (typeof v === 'bigint' ? v.toString() : v),
      2,
    ),
  );

// === 1. Sync facade builders: full Transaction JSON =========================
const syncCases = {
  predict_create_manager: () => client.tx.createManager(),
  predict_deposit: () => client.tx.deposit(OWNER, '12.5'),
  predict_deposit_create: () => client.tx.deposit(OWNER, 3, { create: true }),
  predict_withdraw: () => client.tx.withdraw(OWNER, '1.75'),
  predict_withdraw_coin: () =>
    client.tx.withdraw(OWNER, 2, { toCoinObject: true }),
  predict_supply_plp: () => client.tx.supplyPlp(OWNER, 100),
  predict_supply_plp_floor: () =>
    client.tx.supplyPlp(OWNER, '250.25', { minPlpOut: 123456789n }),
  predict_withdraw_plp: () => client.tx.withdrawPlp(OWNER, 5000000n),
  predict_withdraw_plp_floor: () =>
    client.tx.withdrawPlp(OWNER, 5000000n, { minUsdcOut: '4.5' }),
  predict_cancel_supply: () => client.tx.cancelSupplyPlp(OWNER, 7n),
  predict_cancel_withdraw: () => client.tx.cancelWithdrawPlp(OWNER, 0n),
  predict_set_builder_code: () =>
    client.tx.setBuilderCode(OWNER, BUILDER_CODE),
  predict_unset_builder_code: () => client.tx.unsetBuilderCode(OWNER),
};
// `supportedIntents` keeps CoinWithBalance as a raw `$Intent` command instead
// of resolving it against a client — the same unresolved shape the Dart
// builder serializes, so the two JSONs stay comparable without a network.
const TO_JSON = { supportedIntents: ['CoinWithBalance'] };
for (const [name, build] of Object.entries(syncCases)) {
  const tx = build();
  tx.setSender(OWNER);
  writeFileSync(join(outDir, `${name}.json`), await tx.toJSON(TO_JSON));
}

// === 2. Trade compositions ===================================================
// The facade's mint/redeem builders resolve markets over the network; their
// command COMPOSITION, which is what must match byte for byte, is replicated
// here from the official tx/trade.ts over public exports: pricer → auth →
// expiry_market call (U64_MAX / 0 defaults).
const WRAPPER = deriveAccountWrapperId(cfg, OWNER);

const pricerOf = (tx) =>
  tx.add(loadLivePricer(gen, { expiryMarketId: MARKET, ...FEEDS }));
const authOf = (tx) => tx.add(generateAuth(cfg));

const tradeCases = {
  predict_mint_quantity: (tx) => {
    const pricer = pricerOf(tx);
    const auth = authOf(tx);
    tx.add(
      expiryMarketMoveCalls.mintExactQuantity({
        config: gen,
        arguments: {
          market: MARKET,
          wrapper: WRAPPER,
          auth,
          pricer,
          lowerTick: 123n,
          higherTick: POS_INF_TICK,
          quantity: 5_000_000n,
          maxCost: 4_000_000n,
          maxProbability: 800_000_000n,
        },
      }),
    );
  },
  predict_mint_quantity_defaults: (tx) => {
    const pricer = pricerOf(tx);
    const auth = authOf(tx);
    tx.add(
      expiryMarketMoveCalls.mintExactQuantity({
        config: gen,
        arguments: {
          market: MARKET,
          wrapper: WRAPPER,
          auth,
          pricer,
          lowerTick: 0n,
          higherTick: 321n,
          quantity: 10_000n,
          maxCost: U64_MAX,
          maxProbability: U64_MAX,
        },
      }),
    );
  },
  predict_mint_amount: (tx) => {
    const pricer = pricerOf(tx);
    const auth = authOf(tx);
    tx.add(
      expiryMarketMoveCalls.mintExactAmount({
        config: gen,
        arguments: {
          market: MARKET,
          wrapper: WRAPPER,
          auth,
          pricer,
          lowerTick: 10n,
          higherTick: 20n,
          maxPremium: 1_000_000n,
          minQuantity: 10_000n,
          maxCost: 2_000_000n,
        },
      }),
    );
  },
  predict_mint_cost: (tx) => {
    const pricer = pricerOf(tx);
    const auth = authOf(tx);
    tx.add(
      expiryMarketMoveCalls.mintExactCost({
        config: gen,
        arguments: {
          market: MARKET,
          wrapper: WRAPPER,
          auth,
          pricer,
          lowerTick: 10n,
          higherTick: 20n,
          maxCost: 3_000_000n,
          minQuantity: 0n,
        },
      }),
    );
  },
  predict_redeem_live: (tx) => {
    const pricer = pricerOf(tx);
    const auth = authOf(tx);
    tx.add(
      expiryMarketMoveCalls.redeemLive({
        config: gen,
        arguments: {
          market: MARKET,
          wrapper: WRAPPER,
          auth,
          pricer,
          orderId: 2n ** 200n + 7n,
          closeQuantity: 20_000n,
          minProbability: 0n,
          minProceeds: 0n,
        },
      }),
    );
  },
  predict_redeem_settled: (tx) => {
    const auth = authOf(tx);
    tx.add(
      expiryMarketMoveCalls.redeemSettled({
        config: gen,
        arguments: {
          market: MARKET,
          wrapper: WRAPPER,
          auth,
          orderId: 2n ** 200n + 7n,
        },
      }),
    );
  },
};
for (const [name, build] of Object.entries(tradeCases)) {
  const tx = new Transaction();
  tx.setSender(OWNER);
  build(tx);
  writeFileSync(join(outDir, `${name}.json`), await tx.toJSON(TO_JSON));
}

// === 3. Cost-engine parity ===================================================
const EXPIRY = 1_800_000_000_000n;
const NOW_FAR = EXPIRY - 1_000_000_000n; // far outside the one-day window
const NOW_RAMP = EXPIRY - 43_200_000n; // half-way into the window

const P0 = cost.SHIPPED_FEE_POLICY;
const P1 = {
  ...P0,
  inventoryImpactMaxRate: 50_000_000n,
  inventoryImpactScale: 10_000_000_000n,
};
const P2 = { ...P0, expiryFeeMaxMultiplier: 3_000_000_000n };

const BOOK = {
  maxPayout: 400_000_000_000n,
  totalPayout: 900_000_000_000n,
  rangeMaxPayout: 100_000_000_000n,
};
const CLOSE_BOOK = { ...BOOK, complementMaxPayout: 400_000_000_000n };

const up = (p) => ({ lowerUp: p, higherUp: null });
const down = (p) => ({ lowerUp: null, higherUp: p });
const range = (lo, hi) => ({ lowerUp: lo, higherUp: hi });

const mintCases = {
  up_plain: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), quantity: 100,
  },
  up_builder_penalty_subsidy: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), quantity: 100,
    builderCode: true, feeIncentiveBalance: 0.5, penaltyRate: 2_000_000n,
  },
  up_subsidy_rate_bound: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), quantity: 100,
    feeIncentiveBalance: 1_000_000_000_000n,
  },
  down_raw_quantity: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: down(600_000_000n), quantity: 5_000_000n,
  },
  range_two_legs: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: range(700_000_000n, 300_000_000n), quantity: 50,
  },
  band_edge_max: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(990_000_000n), quantity: 1000,
  },
  ramp_half_window: {
    fees: P2, expiryMs: EXPIRY, nowMs: NOW_RAMP,
    probabilities: up(500_000_000n), quantity: 100,
  },
  impact_enabled: {
    fees: P1, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(500_000_000n), quantity: 2000, book: BOOK,
  },
  lot_cap_scale: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(500_000_000n),
    quantity: (2n ** 32n - 1n) * 10_000n,
  },
};
const mintErrorCases = {
  premium_below_min: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(500_000_000n), quantity: 10_000n,
  },
  off_lot: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(900_000_000n), quantity: 2_005_000n,
  },
  band_breach: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(995_000_000n), quantity: 100,
  },
  cost_above_payout: {
    fees: P2, expiryMs: EXPIRY, nowMs: EXPIRY - 1n,
    probabilities: up(985_000_000n), quantity: 100,
    builderCode: true, penaltyRate: 1_000_000_000n,
  },
  both_infinite: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: range(null, null), quantity: 100,
  },
  expired: {
    fees: P0, expiryMs: EXPIRY, nowMs: EXPIRY,
    probabilities: up(500_000_000n), quantity: 100,
  },
};

const budgetCases = {
  plain: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), budget: 100,
  },
  balance_capped: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), budget: 100, accountBalance: 40.5,
  },
  whole_balance_sentinel: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), budget: U64_MAX, accountBalance: 25,
  },
  impact_enabled: {
    fees: P1, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(500_000_000n), budget: 5000, book: BOOK,
  },
  lot_cap_binding: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(10_000_000n), budget: 10_000_000_000_000_000_000n,
  },
  // An empty book makes the impact term quadratic in quantity, so the budget
  // fill breaches `cost <= quantity` while smaller fills are admissible — the
  // step-down fallback path, which both sides must size identically.
  stepdown_fallback: {
    fees: { ...P1, inventoryImpactScale: 10_000_000_000n },
    expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(970_000_000n), budget: 20000,
    book: { maxPayout: 0n, totalPayout: 0n, rangeMaxPayout: 0n },
    builderCode: true,
  },
};
const budgetErrorCases = {
  min_quantity_miss: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), budget: 5, minQuantity: 10,
  },
};

const redeemCases = {
  plain: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), closeQuantity: 100,
  },
  fee_clamped_to_gross: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(5_000_000n), closeQuantity: 100,
    builderCode: true, penaltyRate: 1_000_000_000n,
  },
  rebate_with_clamp: {
    fees: P1, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(5_000_000n), closeQuantity: 100, book: CLOSE_BOOK,
    builderCode: true,
  },
  partial_with_remaining: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: range(800_000_000n, 200_000_000n),
    closeQuantity: 25, positionQuantity: 100,
  },
};
const redeemErrorCases = {
  close_exceeds_position: {
    fees: P0, expiryMs: EXPIRY, nowMs: NOW_FAR,
    probabilities: up(650_000_000n), closeQuantity: 100, positionQuantity: 50,
  },
};

const runCase = (fn, inputs) => {
  try {
    return { ok: fn(inputs) };
  } catch (e) {
    return { error: { name: e.name, message: e.message } };
  }
};
write('predict_cost_parity', {
  mint: Object.fromEntries(
    Object.entries({ ...mintCases, ...mintErrorCases }).map(([k, v]) => [
      k,
      { inputs: v, result: runCase(cost.mintCost, v) },
    ]),
  ),
  budget: Object.fromEntries(
    Object.entries({ ...budgetCases, ...budgetErrorCases }).map(([k, v]) => [
      k,
      { inputs: v, result: runCase(cost.mintCostForBudget, v) },
    ]),
  ),
  redeem: Object.fromEntries(
    Object.entries({ ...redeemCases, ...redeemErrorCases }).map(([k, v]) => [
      k,
      { inputs: v, result: runCase(cost.redeemLiveProceeds, v) },
    ]),
  ),
  components: {
    bernoulli: [0n, 1_000_000_000n, 500_000_000n, 250_000_000n, 10_000_000n,
      999_999_999n].map((p) => ({
      p,
      rate: cost.bernoulliFeeRate(100_000_000n, p),
    })),
    sqrtDown: [0n, 1n, 2n, 1_000_000_000n, 250_000_000n, 123_456_789n,
      999_999_999_999n].map((x) => ({ x, v: cost.sqrtDown(x) })),
    expiryMultiplier: [0n, 1n, 43_200_000n, 86_399_999n, 86_400_000n,
      100_000_000n].map((t) => ({
      t,
      v: cost.expiryFeeMultiplier(P2, t),
    })),
    tradingFeeTwoLegs: cost.tradingFee(
      P0,
      range(700_000_000n, 300_000_000n),
      100_000_000n,
      100_000_000n,
    ),
    congestion: [
      { gas: 1_000n, fires: false },
      { gas: 100_000n, fires: true },
    ].map(({ gas }) => ({
      gas,
      rate: cost.congestionPenaltyRate(
        { enabled: true, penaltyRate: 30_000_000n, zScoreThreshold: 3_000_000_000n },
        { mean: 1_000_000_000_000n, variance: 4_000_000_000_000n },
        gas,
      ),
    })),
    impactPotential: [0n, 5_000_000_000n, 10_000_000_000n,
      20_000_000_000n].map((l) => ({
      l,
      v: cost.inventoryImpactPotential(P1, l),
    })),
    mintImpact: cost.mintInventoryImpact(P1, BOOK, 2_000_000_000n),
    closeImpact: cost.closeInventoryImpact(P1, CLOSE_BOOK, 2_000_000_000n),
    rangeProbability: [
      range(700_000_000n, 300_000_000n),
      up(650_000_000n),
      down(650_000_000n),
      range(300_000_000n, 700_000_000n), // saturates to 0
    ].map((b) => ({ b, v: cost.rangeProbability(b) })),
  },
});

// === 4. Float pricer parity ==================================================
const SNAP1 = {
  forward: 65000,
  svi: { a: 0.0005, b: 0.012, rho: -0.35, m: 0.01, sigma: 0.08 },
};
const SNAP2 = {
  forward: 2.5,
  svi: { a: 0.002, b: 0.0, rho: 0.0, m: 0.0, sigma: 0.05 },
};
const strikesOf = (s) => [
  s.forward * 0.9, s.forward, s.forward * 1.001, s.forward * 1.5, 0.5, 0,
];
write('predict_pricing_parity', {
  snapshots: [SNAP1, SNAP2].map((snap) => ({
    snap,
    up: strikesOf(snap).map((k) => pricing.upProbability(snap, k)),
    down: strikesOf(snap).map((k) => pricing.downProbability(snap, k)),
    range: [
      pricing.rangeProbability(snap, snap.forward * 0.95, snap.forward * 1.05),
      pricing.rangeProbability(snap, 0, snap.forward),
      pricing.rangeProbability(snap, snap.forward, Infinity),
    ],
    strikeAt: [0.25, 0.5, 0.75, 0.999].map((p) =>
      pricing.strikeAtProbability(snap, p),
    ),
  })),
  rollDown: pricing.rollDown(SNAP1.svi, 3_600_000, 86_400_000),
  forward: [
    pricing.forward(65000, 64900, 65200),
    pricing.forward(0, 64900, 65200),
  ],
});

// === 5. Order-id codec + tick parity ========================================
const orderIds = [
  (777n << 100n) | (123n << 70n) | (POS_INF_TICK << 40n) | 0x123456789n,
  (1n << 100n) | (0n << 70n) | (321n << 40n),
  ((2n ** 32n - 1n) << 100n) | (99n << 70n) | (100n << 40n) | (2n ** 40n - 1n),
];
write('predict_order_id', {
  decode: orderIds.map((id) => {
    const r = cost.decodeOrderRange(id);
    return {
      id,
      range: r,
      strikes: cost.orderStrikes(r, 10_000_000n),
    };
  }),
  binaryTicks: [
    { strikeRaw: 1_230_000_000n, side: 'up', tickSize: 10_000_000n },
    { strikeRaw: 1_230_000_000n, side: 'down', tickSize: 10_000_000n },
  ].map((c) => ({ c, ticks: binaryRangeTicks(c.strikeRaw, c.side, c.tickSize) })),
});

// === 6. Event decode parity ==================================================
const mintEvent = {
  expiry_market_id: MARKET,
  account_id: OWNER2,
  order_id: (2n ** 200n + 7n).toString(),
  position_root_id: (2n ** 200n + 7n).toString(),
  owner: OWNER,
  lower_tick: '123',
  higher_tick: POS_INF_TICK.toString(),
  entry_probability: '650000000',
  quantity: '5000000',
  premium: '3250000',
  trading_fee: '110000',
  fee_incentive_subsidy: '22000',
  builder_fee: '11000',
  penalty_fee: '0',
  referral_fee: '5000',
  inventory_impact_charge: '0',
  builder_code_id: BUILDER_CODE,
  referrer_account_id: null,
  onchain_timestamp_ms: '1799999000000',
  pyth_spot_source_timestamp_ms: '1799998000000',
  block_scholes_spot_source_timestamp_ms: '1799998000001',
  block_scholes_forward_source_timestamp_ms: '1799998000002',
  block_scholes_svi_source_timestamp_ms: '1799998000003',
};
const redeemEvent = {
  expiry_market_id: MARKET,
  account_id: OWNER2,
  order_id: (2n ** 200n + 7n).toString(),
  position_root_id: (2n ** 200n + 7n).toString(),
  owner: OWNER,
  quantity_closed: '20000',
  remaining_quantity: '4980000',
  replacement_order_id: (2n ** 201n + 9n).toString(),
  redeem_amount: '13000',
  trading_fee: '440',
  builder_fee: '44',
  penalty_fee: '0',
  inventory_impact_rebate: '12',
  builder_code_id: null,
  onchain_timestamp_ms: '1799999100000',
  pyth_spot_source_timestamp_ms: '1799999000000',
  block_scholes_spot_source_timestamp_ms: '1799999000001',
  block_scholes_forward_source_timestamp_ms: '1799999000002',
  block_scholes_svi_source_timestamp_ms: '1799999000003',
};
const claimEvent = {
  expiry_market_id: MARKET,
  account_id: OWNER2,
  order_id: '77',
  position_root_id: '77',
  owner: OWNER,
  payout_amount: '5000000',
  onchain_timestamp_ms: '1800000100000',
};
const createdEvent = {
  account_id: OWNER2,
  wrapper_id: WRAPPER,
  owner: OWNER,
  self_owned: true,
  referrer_account_id: null,
};
const depositEvent = {
  account_id: OWNER2,
  coin_type: cfg.quoteCoinType,
  amount: '12500000',
  new_balance: '22500000',
};
const supplyReqEvent = {
  pool_vault_id: cfg.objects.poolVault,
  account_id: OWNER2,
  recipient: OWNER,
  index: '7',
  amount: '100000000',
  min_plp_out: '123456789',
  requests_pending_after: '8',
};
const cancelEvent = {
  pool_vault_id: cfg.objects.poolVault,
  account_id: OWNER2,
  recipient: OWNER,
  index: '7',
  amount: '100000000',
  is_supply: true,
  reason: 1,
  requests_pending_after: '7',
};
const builderSetEvent = {
  account_id: OWNER2,
  owner: OWNER,
  builder_code_id: BUILDER_CODE,
};
const evt = (pkg, module, name, layout, value) => ({
  eventType: `${pkg}::${module}::${name}`,
  bcs: toBase64(layout.serialize(value).toBytes()),
});
const pkgV1 = cfg.packages.predictV1 ?? cfg.packages.predict;
const events = [
  evt(pkgV1, 'order_events', 'OrderMinted', orderEvents.OrderMinted, mintEvent),
  evt(pkgV1, 'order_events', 'LiveOrderRedeemed', orderEvents.LiveOrderRedeemed,
    redeemEvent),
  evt(pkgV1, 'order_events', 'SettledOrderRedeemed',
    orderEvents.SettledOrderRedeemed, claimEvent),
  evt(cfg.packages.account, 'account_events', 'AccountCreated',
    accountEvents.AccountCreated, createdEvent),
  evt(cfg.packages.account, 'account_events', 'Deposited',
    accountEvents.Deposited, depositEvent),
  evt(cfg.packages.account, 'account_events', 'Withdrawn',
    accountEvents.Withdrawn, depositEvent),
  evt(pkgV1, 'vault_events', 'SupplyRequested', vaultEvents.SupplyRequested,
    supplyReqEvent),
  evt(pkgV1, 'vault_events', 'RequestCancelled', vaultEvents.RequestCancelled,
    cancelEvent),
  evt(pkgV1, 'builder_code_events', 'BuilderCodeSet',
    builderCodeEvents.BuilderCodeSet, builderSetEvent),
];
const result = { events };
write('predict_decode_events', {
  events,
  decoded: {
    mint: client.decode.mint(result),
    redeem: client.decode.redeem(result),
    claim: client.decode.claim(result),
    createManager: client.decode.createManager(result),
    deposit: client.decode.deposit(result),
    withdraw: client.decode.withdraw(result),
    plpRequest: client.decode.plpRequest(result),
    plpCancel: client.decode.plpCancel(result),
    builderCode: client.decode.builderCode(result),
  },
});

// === 7. Derivation parity ====================================================
write('predict_derive', ['testnet', 'mainnet'].map((network) => {
  const c = getConfig(network);
  return {
    network,
    rows: [OWNER, OWNER2].map((owner) => ({
      owner,
      wrapperId: deriveAccountWrapperId(c, owner),
    })),
  };
}));

console.log('predict fixtures written to', outDir);
