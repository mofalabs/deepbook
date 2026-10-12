/// Shapes for the generated deployment records.
///
/// Mirrors the official `src/deployments/types.ts`: canonical per-network ids
/// for the account primitive, sessions, and DeepBook Predict, all read from
/// one generated record so the subpaths cannot drift apart across a redeploy.
library;

/// Which on-chain deployment a set of ids came from.
class DeploymentInfo {
  /// Deployment name, e.g. `deepbook-predict-testnet`.
  final String deployment;

  /// Network the deployment lives on (`testnet` / `mainnet`).
  final String network;

  /// The network's chain identifier.
  final String chainId;

  /// The initial deployment's source commit; later package IDs come from
  /// Published.toml.
  final String sourceCommit;

  const DeploymentInfo({
    required this.deployment,
    required this.network,
    required this.chainId,
    required this.sourceCommit,
  });
}

/// Scale constants the deployment owns rather than the SDK.
///
/// Only [positionLotSize] is currently read by the SDK; the other three are
/// shipped as the deployment's own record of its scales.
class DeploymentUnits {
  /// Predict-only: order quantity must be a whole number of these.
  final int positionLotSize;
  final int fixedPointScale;
  final int quoteCoinDecimals;
  final int positionQuantityDecimals;

  const DeploymentUnits({
    required this.positionLotSize,
    required this.fixedPointScale,
    required this.quoteCoinDecimals,
    required this.positionQuantityDecimals,
  });
}

/// Ids for the shared `account` primitive.
class AccountIds {
  final String accountPackageId;
  final String accountRegistry;

  const AccountIds({
    required this.accountPackageId,
    required this.accountRegistry,
  });
}

/// Ids for time-limited sessions, including the spot- and Predict-only extras.
class SessionsIds implements AccountIds {
  final String sessionsPackageId;

  /// Original package ID for existing structs and dynamic-field keys.
  final String sessionsPackageIdV1;
  final String sessionsConfig;
  @override
  final String accountPackageId;
  @override
  final String accountRegistry;

  /// Spot wrappers only.
  final String deepbookRegistry;

  /// Spot wrappers only.
  final String deepbookCoreAccountPackageId;

  /// Every Predict wrapper takes `config: &ProtocolConfig`.
  final String protocolConfig;

  const SessionsIds({
    required this.sessionsPackageId,
    required this.sessionsPackageIdV1,
    required this.sessionsConfig,
    required this.accountPackageId,
    required this.accountRegistry,
    required this.deepbookRegistry,
    required this.deepbookCoreAccountPackageId,
    required this.protocolConfig,
  });
}

/// Per-underlying oracle wiring.
class UnderlyingIds {
  final String symbol;
  final int propbookUnderlyingId;
  final String pythFeed;
  final String blockScholesValueStore;
  final String blockScholesSviStore;

  const UnderlyingIds({
    required this.symbol,
    required this.propbookUnderlyingId,
    required this.pythFeed,
    required this.blockScholesValueStore,
    required this.blockScholesSviStore,
  });
}

/// Package ids for DeepBook Predict.
class PredictPackages {
  final String predict;

  /// Original package ID; Move type tags keep it across upgrades.
  ///
  /// Required here, unlike the official SDK where it is optional and falls
  /// back to [predict]: the shipped deployment records always carry it, and
  /// when hand-building a config for a not-yet-upgraded deployment, set it to
  /// the same value as [predict].
  final String predictV1;
  final String account;
  final String propbook;

  const PredictPackages({
    required this.predict,
    required this.predictV1,
    required this.account,
    required this.propbook,
  });
}

/// Shared object ids for DeepBook Predict.
class PredictObjects {
  final String registry;
  final String protocolConfig;
  final String poolVault;
  final String oracleRegistry;
  final String accountRegistry;

  const PredictObjects({
    required this.registry,
    required this.protocolConfig,
    required this.poolVault,
    required this.oracleRegistry,
    required this.accountRegistry,
  });
}

/// Coin types DeepBook Predict reads.
class PredictCoinTypes {
  /// The LP share coin type. NOT derivable from `packages.predict`: a Move
  /// type tag keeps the ORIGINAL package id across an upgrade, while
  /// `packages.predict` moves to the latest.
  final String plp;
  final String deep;

  const PredictCoinTypes({required this.plp, required this.deep});
}

/// Ids for DeepBook Predict.
class PredictIds {
  final String network;
  final PredictPackages packages;
  final PredictObjects objects;
  final String quoteCoinType;
  final PredictCoinTypes coinTypes;
  final DeploymentUnits units;
  final Map<String, UnderlyingIds> underlyings;

  const PredictIds({
    required this.network,
    required this.packages,
    required this.objects,
    required this.quoteCoinType,
    required this.coinTypes,
    required this.units,
    required this.underlyings,
  });
}
