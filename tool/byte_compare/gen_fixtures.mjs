// Generates builder-level comparison fixtures from the OFFICIAL
// @mysten/deepbook-v3 TypeScript SDK. Each fixture is the official
// Transaction JSON for a representative SDK call; the Dart test
// (test/byte_compare_test.dart) rebuilds the same transaction with the Dart
// SDK and compares the normalized command/input structure.
//
// Run from the ts-sdks workspace so bare imports resolve:
//   cd <ts-sdks>/packages/deepbook-v3
//   node <this-repo>/deepbook/tool/byte_compare/gen_fixtures.mjs <out-dir>
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { Transaction } from '@mysten/sui/transactions';
import {
  DeepBookConfig,
  BalanceManagerContract,
  DeepBookContract,
  DeepBookAdminContract,
  FlashLoanContract,
  GovernanceContract,
  MarginManagerContract,
  PoolProxyContract,
} from '@mysten/deepbook-v3';

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
