/// Mainnet deployment record, ported verbatim from the official
/// `src/deployments/mainnet.ts` (generated there by `pnpm sync-deployment`).
/// Do not hand-edit ids: re-port from upstream on a redeploy.
///
/// Deployment: deepbook-predict-mainnet
/// sourceCommit: 7b169bde2c2a25fee3ac9aa4686e346309bfe570
// Official SCREAMING_CAPS constant names are kept verbatim.
// ignore_for_file: constant_identifier_names
library;

import 'types.dart';

/// Which on-chain deployment the ids below came from.
const MAINNET_DEPLOYMENT = DeploymentInfo(
  deployment: 'deepbook-predict-mainnet',
  network: 'mainnet',
  chainId: '35834a8a',
  sourceCommit: '7b169bde2c2a25fee3ac9aa4686e346309bfe570',
);

/// Ids for the shared `account` primitive — the `/account` subpath's slice.
const mainnetAccount = AccountIds(
  accountPackageId:
      '0x4e1dd01465713c9d832313fed5f45c222a4d5c62a533d6da96764c8b2a245d58',
  accountRegistry:
      '0x8c52c6f5b2374e33f4a726d9c32337b1aee3a71410d41c18faa91d938d66e4bc',
);

/// Ids for time-limited sessions — the `/sessions` subpath's slice.
///
/// `deepbookRegistry` is only needed by the DeepBook **spot** session
/// wrappers; the Predict wrappers never take it.
const mainnetSessions = SessionsIds(
  sessionsPackageId:
      '0xec678aee98cd161bdce62ff3dcf4893574df29d927dc8b573f6b4563ec960a1a',
  sessionsPackageIdV1:
      '0x9a068beffa019ae756f4a6d2611e9899d3c6dd888812dd9eca87535d2ac55e2a',
  sessionsConfig:
      '0xb2fba483748aac7508676020d4e691d68239b66f8bf7c5e7634dd1a76a329317',
  accountPackageId:
      '0x4e1dd01465713c9d832313fed5f45c222a4d5c62a533d6da96764c8b2a245d58',
  accountRegistry:
      '0x8c52c6f5b2374e33f4a726d9c32337b1aee3a71410d41c18faa91d938d66e4bc',
  deepbookRegistry:
      '0xaf16199a2dff736e9f07a845f23c5da6df6f756eddb631aed9d24a93efc4549d',
  deepbookCoreAccountPackageId:
      '0xd71b5a341dc8dc7e187517849edf61e54670b60fe496e07186c09a65fa7afdb7',
  protocolConfig:
      '0x5fa6efbe7691809565a660adde23f0c184ca1d19cefafa4e1c88d655fe279580',
);

/// Scale constants the deployment owns rather than the SDK.
const MAINNET_UNITS = DeploymentUnits(
  positionLotSize: 10000,
  fixedPointScale: 1000000000,
  quoteCoinDecimals: 6,
  positionQuantityDecimals: 6,
);

/// Ids for DeepBook Predict — the `/predict` subpath's slice.
const mainnetPredict = PredictIds(
  network: 'mainnet',
  packages: PredictPackages(
    predict:
        '0x08fa3ef1b047d87b0b4ce1c7e5f8b42d8bfdea9a70547efe3cce5d8d6e47ee53',
    predictV1:
        '0x89aea622e7bb3bdd598bde87dde40ee31c9eed4971b9546e23ec83de3c48bbba',
    account:
        '0x4e1dd01465713c9d832313fed5f45c222a4d5c62a533d6da96764c8b2a245d58',
    propbook:
        '0xa6c8f32015b5b41d34ee09995a2e9d7a21cdecf0e1910a50b264fd252cd33831',
  ),
  objects: PredictObjects(
    registry:
        '0x94327dbc256a2cfabd164c2bf4b3fe033bfaa4771f7a6f716954e07cb1b4beba',
    protocolConfig:
        '0x5fa6efbe7691809565a660adde23f0c184ca1d19cefafa4e1c88d655fe279580',
    poolVault:
        '0x4d227a1baf8cfcaf6e652a9182d0e63f85f9ce82cd542fdf3356bb3581be3b99',
    oracleRegistry:
        '0x5d62c0d9be43efa769a708ade53fbe5bea98c15c865b64ca7c498c87b045a698',
    accountRegistry:
        '0x8c52c6f5b2374e33f4a726d9c32337b1aee3a71410d41c18faa91d938d66e4bc',
  ),
  quoteCoinType:
      '0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC',
  coinTypes: PredictCoinTypes(
    plp:
        '0x89aea622e7bb3bdd598bde87dde40ee31c9eed4971b9546e23ec83de3c48bbba::plp::PLP',
    deep:
        '0xdeeb7a4662eec9f2f3def03fb937a663dddaa2e215b8078a284d026b7946c270::deep::DEEP',
  ),
  units: MAINNET_UNITS,
  underlyings: {
    'BTC': UnderlyingIds(
      symbol: 'BTC',
      propbookUnderlyingId: 1,
      pythFeed:
          '0x4c5d2b4c8238f04b7687c3a8df915b69c50d5f4d291fc49aea44bdb6b52e1a20',
      blockScholesValueStore:
          '0xe83f843b15ae63045b2cea445fb8ea7ad85c5fc2a05f66db122a511e1f2c67bc',
      blockScholesSviStore:
          '0xfdd447be39d847747caf18ecf3355031bb33979c472581f1a5481375d3748bfb',
    ),
  },
);
