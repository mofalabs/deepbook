// Generates builder-level comparison fixtures from the OFFICIAL
// @mysten/deepbook-v3 TypeScript SDK. Each fixture is the official
// Transaction JSON for a representative SDK call; the Dart test
// (test/byte_compare_test.dart) rebuilds the same transaction with the Dart
// SDK and compares the normalized command/input structure.
//
// ESM resolves bare imports from the script's own location, so copy this
// file into the package before running (and build the workspace first:
// packages/{utils,bcs,sui,deepbook-v3} each `pnpm run build`, in that order):
//   cd <ts-sdks>/packages/deepbook-v3
//   cp <this-file> gen_fixtures_tmp.mjs
//   node gen_fixtures_tmp.mjs <this-repo>/deepbook/test/fixtures/byte_compare
//   rm gen_fixtures_tmp.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { Transaction } from '@mysten/sui/transactions';
import {
  DeepBookConfig,
  BalanceManagerContract,
  DeepBookContract,
  DeepBookAdminContract,
  FlashLoanContract,
  GovernanceContract,
  MarginManagerContract,
  MarginTPSLContract,
  PoolProxyContract,
} from '@mysten/deepbook-v3';

// Not exported from the package root; load it from the built output of the
// workspace this script runs in (cwd = packages/deepbook-v3).
const { MarginLiquidationsContract } = await import(
  pathToFileURL(
    join(process.cwd(), 'dist/transactions/marginLiquidations.mjs'),
  ).href
);

const outDir = process.argv[2] ?? 'fixtures';
mkdirSync(outDir, { recursive: true });

const ADDRESS =
  '0x00000000000000000000000000000000000000000000000000000000000000aa';
const MANAGER =
  '0x00000000000000000000000000000000000000000000000000000000000000bb';

const MARGIN_MANAGER =
  '0x00000000000000000000000000000000000000000000000000000000000000dd';

const config = new DeepBookConfig({
  network: 'testnet',
  address: ADDRESS,
  adminCap:
    '0x00000000000000000000000000000000000000000000000000000000000000cc',
  balanceManagers: { M: { address: MANAGER } },
  marginManagers: { MM: { address: MARGIN_MANAGER, poolKey: 'SUI_DBUSDC' } },
});

const bm = new BalanceManagerContract(config);
const db = new DeepBookContract(config);
const admin = new DeepBookAdminContract(config);
const flash = new FlashLoanContract(config);
const gov = new GovernanceContract(config);

const marginManager = new MarginManagerContract(config);
const poolProxy = new PoolProxyContract(config);
const marginTPSL = new MarginTPSLContract(config);
const marginLiquidations = new MarginLiquidationsContract(config);

const VAULT =
  '0x00000000000000000000000000000000000000000000000000000000000000ee';

const cases = {
  margin_manager_new: (tx) => {
    tx.add(marginManager.newMarginManager('SUI_DBUSDC'));
  },
  pool_proxy_orders: (tx) => {
    tx.add(
      poolProxy.placeLimitOrder({
        poolKey: 'SUI_DBUSDC',
        marginManagerKey: 'MM',
        clientOrderId: '777',
        price: 1.5,
        quantity: 4,
        isBid: false,
      }),
    );
    tx.add(poolProxy.cancelAllOrders('MM'));
  },
  // Oracle-taking entrypoints that moved to the upgraded-Pyth modules.
  margin_withdraw_borrow: (tx) => {
    tx.add(marginManager.withdrawBase('MM', 1));
    tx.add(marginManager.borrowQuote('MM', 5));
    tx.add(marginManager.managerState('SUI_DBUSDC', MARGIN_MANAGER));
  },
  margin_liquidation: (tx) => {
    tx.add(marginLiquidations.liquidateBase(VAULT, MARGIN_MANAGER, 'SUI_DBUSDC'));
    tx.add(marginLiquidations.liquidateQuote(VAULT, MARGIN_MANAGER, 'SUI_DBUSDC', 3));
  },
  tpsl_execute: (tx) => {
    tx.add(marginTPSL.executeConditionalOrders(MARGIN_MANAGER, 'SUI_DBUSDC', 10));
  },
  bm_withdraw: (tx) => {
    tx.add(bm.withdrawFromManager('M', 'SUI', 1.5, ADDRESS));
  },
  bm_caps: (tx) => {
    tx.add(bm.mintTradeCap('M'));
    tx.add(bm.generateProofAsOwner(MANAGER));
  },
  place_limit_order: (tx) => {
    tx.add(
      db.placeLimitOrder({
        poolKey: 'SUI_DBUSDC',
        balanceManagerKey: 'M',
        clientOrderId: '12345',
        price: 2.5,
        quantity: 7,
        isBid: true,
      }),
    );
  },
  cancel_orders: (tx) => {
    tx.add(db.cancelOrder('SUI_DBUSDC', 'M', '170141183460469231731687303715884105728'));
    tx.add(db.cancelAllOrders('SUI_DBUSDC', 'M'));
  },
  governance: (tx) => {
    tx.add(gov.stake('SUI_DBUSDC', 'M', 100));
    tx.add(gov.vote('SUI_DBUSDC', 'M', MANAGER));
  },
  flash_loan_roundtrip: (tx) => {
    const [coin, loan] = tx.add(flash.borrowBaseAsset('SUI_DBUSDC', 3));
    tx.add(flash.returnBaseAsset('SUI_DBUSDC', 3, coin, loan));
  },
  admin_create_pool: (tx) => {
    tx.add(
      admin.createPoolAdmin({
        baseCoinKey: 'DEEP',
        quoteCoinKey: 'SUI',
        tickSize: 0.001,
        lotSize: 1,
        minSize: 10,
        whitelisted: true,
        stablePool: false,
      }),
    );
  },
  order_reads: (tx) => {
    tx.add(db.accountOpenOrders('SUI_DBUSDC', 'M'));
    tx.add(db.midPrice('SUI_DBUSDC'));
    tx.add(db.poolTradeParams('SUI_DBUSDC'));
  },
};

for (const [name, build] of Object.entries(cases)) {
  const tx = new Transaction();
  tx.setSender(ADDRESS);
  build(tx);
  const json = JSON.parse(await tx.toJSON());
  writeFileSync(join(outDir, `${name}.json`), JSON.stringify(json, null, 2));
  console.log('wrote', name);
}
