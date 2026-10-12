// Generates builder-level comparison fixtures for the /account and /sessions
// subpaths from the OFFICIAL @mysten/deepbook-v3 TypeScript SDK. Companion to
// gen_fixtures.mjs (kept separate so the suites can regenerate independently).
//
// Node resolves bare imports against the SCRIPT's own path, so copy this file
// into the package before running (the package must be built:
// `pnpm --filter @mysten/deepbook-v3 build`):
//   cd <ts-sdks>/packages/deepbook-v3
//   cp <this-file> ./gen.tmp.mjs && node ./gen.tmp.mjs <out-dir>; rm ./gen.tmp.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { Transaction } from '@mysten/sui/transactions';
import { bcs } from '@mysten/sui/bcs';
import { AccountContract, getAccountConfig } from '@mysten/deepbook-v3/account';
import {
  SessionsContract,
  getSessionsConfig,
  SessionsData,
} from '@mysten/deepbook-v3/sessions';

const outDir = process.argv[2] ?? 'fixtures';
mkdirSync(outDir, { recursive: true });

const ADDRESS =
  '0x00000000000000000000000000000000000000000000000000000000000000aa';
const OWNER2 =
  '0x000000000000000000000000000000000000000000000000000000000000cafe';
const SESSION_KEY =
  '0x00000000000000000000000000000000000000000000000000000000000000ab';
const COIN =
  '0x00000000000000000000000000000000000000000000000000000000000000ee';
const MARKET =
  '0x0000000000000000000000000000000000000000000000000000000000000011';
const SUI_TYPE = '0x2::sui::SUI';
const U64_MAX = 18446744073709551615n;
const ORDER_ID = 2n ** 200n + 7n;

const account = new AccountContract(getAccountConfig('testnet'));
const customAccount = new AccountContract({
  accountPackageId:
    '0x0000000000000000000000000000000000000000000000000000000000000077',
  accountRegistry:
    '0x0000000000000000000000000000000000000000000000000000000000000088',
});
const sessions = new SessionsContract(getSessionsConfig('testnet'));
const PROTOCOL_CONFIG = getSessionsConfig('testnet').protocolConfig;

const WRAPPER = account.deriveAccountWrapperId(ADDRESS);

// The pricer is a PTB result from a preceding load_live_pricer command; a raw
// moveCall with a fixed target keeps both sides byte-identical.
const loadPricer = (tx) =>
  tx.moveCall({
    target: `${getSessionsConfig('testnet').sessionsPackageId}::expiry_market::load_live_pricer`,
    arguments: [tx.object(MARKET)],
  });

const cases = {
  account_lifecycle: (tx) => {
    tx.add(account.createAccount());
    tx.add(
      account.depositFunds({
        wrapperId: WRAPPER,
        coin: tx.object(COIN),
        coinType: SUI_TYPE,
      }),
    );
    tx.add(
      account.withdrawFunds({
        wrapperId: WRAPPER,
        amount: 12345n,
        coinType: SUI_TYPE,
      }),
    );
    tx.add(account.loadAccount({ wrapperId: WRAPPER }));
    tx.add(account.balance({ owner: ADDRESS, coinType: SUI_TYPE }));
  },
  account_create_deposit: (tx) => {
    // Custom (non-deployment) ids prove the config path resolves the package
    // address and registry from the caller's own deployment.
    tx.add(
      customAccount.createAccountAndDeposit({
        coin: tx.object(COIN),
        coinType: SUI_TYPE,
      }),
    );
    tx.add(customAccount.generateAuth());
  },
  sessions_lifecycle: (tx) => {
    tx.add(
      sessions.authorizeSession({
        wrapperId: WRAPPER,
        session: SESSION_KEY,
        durationMs: 86400000,
      }),
    );
    tx.add(
      sessions.revokeSession({ wrapperId: WRAPPER, session: SESSION_KEY }),
    );
    tx.add(
      sessions.sessionExpirationMs({
        wrapperId: WRAPPER,
        session: SESSION_KEY,
      }),
    );
  },
  sessions_predict_mint: (tx) => {
    const pricer = loadPricer(tx);
    tx.add(
      sessions.mintExactQuantity({
        expiryMarketId: MARKET,
        wrapperId: WRAPPER,
        protocolConfig: PROTOCOL_CONFIG,
        pricer,
        lowerTick: 10,
        higherTick: 20,
        quantity: 5000000n,
        maxCost: U64_MAX,
        maxProbability: U64_MAX,
      }),
    );
    tx.add(
      sessions.mintExactAmount({
        expiryMarketId: MARKET,
        wrapperId: WRAPPER,
        protocolConfig: PROTOCOL_CONFIG,
        pricer,
        lowerTick: 10,
        higherTick: 20,
        maxPremium: 1000000n,
        minQuantity: 1n,
        maxCost: 2000000n,
      }),
    );
    tx.add(
      sessions.mintExactCost({
        expiryMarketId: MARKET,
        wrapperId: WRAPPER,
        protocolConfig: PROTOCOL_CONFIG,
        pricer,
        lowerTick: 10,
        higherTick: 20,
        maxCost: 3000000n,
        minQuantity: 1n,
      }),
    );
  },
  sessions_predict_redeem: (tx) => {
    const pricer = loadPricer(tx);
    tx.add(
      sessions.redeemLive({
        expiryMarketId: MARKET,
        wrapperId: WRAPPER,
        protocolConfig: PROTOCOL_CONFIG,
        pricer,
        orderId: ORDER_ID,
        closeQuantity: 1000000n,
        // floors omitted on purpose: checks the `?? 0` default
      }),
    );
    tx.add(
      sessions.redeemSettled({
        expiryMarketId: MARKET,
        wrapperId: WRAPPER,
        protocolConfig: PROTOCOL_CONFIG,
        orderId: ORDER_ID,
      }),
    );
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

// --- Derivation parity: wrapper / account / sessions-field ids per network.
const deriveParity = [];
for (const network of ['testnet', 'mainnet']) {
  const s = new SessionsContract(getSessionsConfig(network));
  for (const owner of [ADDRESS, OWNER2]) {
    deriveParity.push({
      network,
      owner,
      wrapperId: s.deriveAccountWrapperId(owner),
      accountId: s.deriveAccountId(owner),
      sessionsFieldId: s.deriveSessionsFieldId(owner),
    });
  }
}
writeFileSync(
  join(outDir, 'derive_parity.json'),
  JSON.stringify(deriveParity, null, 2),
);
console.log('wrote derive_parity');

// --- decodeSessions parity: official BCS bytes + the official decoder's view.
const SessionsDataField = bcs.struct('Field<DataKey,SessionsData>', {
  id: bcs.Address,
  name: bcs.bool(),
  value: SessionsData,
});
const fieldBytes = SessionsDataField.serialize({
  id: '0x00000000000000000000000000000000000000000000000000000000000000fd',
  name: false,
  value: {
    sessions: {
      contents: [
        { key: SESSION_KEY, value: 1700000000000n },
        { key: OWNER2, value: 1800000000001n },
      ],
    },
  },
}).toBytes();
const grants = SessionsContract.decodeSessions(fieldBytes);
writeFileSync(
  join(outDir, 'decode_sessions.json'),
  JSON.stringify(
    {
      bytesBase64: Buffer.from(fieldBytes).toString('base64'),
      grants: grants.map((g) => ({
        session: g.session,
        expiresAtMs: g.expiresAtMs.toString(),
      })),
    },
    null,
    2,
  ),
);
console.log('wrote decode_sessions');
