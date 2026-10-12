/// Predict deployment configuration, mirroring `predict/config/`.
///
/// The per-network configs read the shared generated record in
/// `lib/src/deployments/` rather than transcribing ids here. `/account` and
/// `/sessions` read slices of that same record, so a redeploy moves every
/// subpath together and they cannot end up addressing different deployments.
library;

// Official constant names kept verbatim (TESTNET_CONFIG …).
// ignore_for_file: non_constant_identifier_names

import '../deployments/deployments.dart';
import '../errors.dart' show ConfigurationError;

export '../deployments/deployments.dart'
    show
        getDeployment,
        getUnits,
        DeploymentInfo,
        DeploymentUnits,
        PredictIds,
        PredictPackages,
        PredictObjects,
        PredictCoinTypes,
        UnderlyingIds;

/// Everything a tx builder or read needs to address a Predict deployment on
/// one network — the deployment record's Predict slice, used directly (the
/// official `PredictConfig` interface is the same shape the record carries).
///
/// `quoteCoinType` is the deployment's settlement coin type — always read it
/// rather than assuming a type or symbol: mainnet settles in Circle's native
/// USDC, testnet in a mintable test coin that DISPLAYS as DUSDC but resolves
/// the same `usdc::usdc::USDC` module path.
typedef PredictConfig = PredictIds;

/// Per-underlying oracle wiring: the propbook underlying id plus the feed
/// object ids the live pricer reads.
typedef UnderlyingConfig = UnderlyingIds;

/// Testnet deployment constants, from the shared generated record.
final PredictConfig TESTNET_CONFIG = testnetPredict;

/// Mainnet deployment constants, from the shared generated record.
final PredictConfig MAINNET_CONFIG = mainnetPredict;

/// The recorded Predict config for [network] (`'testnet'` / `'mainnet'`).
///
/// Throws for other networks rather than returning placeholder ids; for your
/// own deployment pass a [PredictConfig] to `PredictClient` directly.
PredictConfig getConfig(String network) {
  if (network == 'testnet') return TESTNET_CONFIG;
  if (network == 'mainnet') return MAINNET_CONFIG;
  throw ConfigurationError(
      "deepbook/predict: no Predict deployment recorded for network "
      "'$network'. Predict is recorded for testnet and mainnet; for your own "
      'deployment pass `config` to PredictClient.');
}

/// The flat config slice the generated bindings resolve `config:` against,
/// projected from the nested public [PredictConfig]. Each generated call
/// declares only the keys it consumes, so a single map carrying all of them
/// satisfies every call site.
///
/// `predictPackageId` always carries the LATEST package (used for Move
/// calls); `predictPackageIdV1` separately supplies the original identity for
/// existing struct tags and dynamic-field keys.
typedef GeneratedConfig = Map<String, dynamic>;

/// Project a [PredictConfig] onto the flat [GeneratedConfig] slice.
GeneratedConfig toGeneratedConfig(PredictConfig cfg) => {
      'predictPackageId': cfg.packages.predict,
      'predictPackageIdV1': cfg.packages.predictV1,
      'accountPackageId': cfg.packages.account,
      'protocolConfig': cfg.objects.protocolConfig,
      'poolVault': cfg.objects.poolVault,
      'registry': cfg.objects.registry,
      'oracleRegistry': cfg.objects.oracleRegistry,
      'accountRegistry': cfg.objects.accountRegistry,
    };
