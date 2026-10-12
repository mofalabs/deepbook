/// Canonical per-network deployment ids.
///
/// Every subsystem (account, sessions, Predict) reads its slice of this one
/// record rather than carrying its own copy, so the subsystems cannot end up
/// addressing different deployments. Ported from the official
/// `src/deployments/index.ts`.
library;

import 'mainnet.dart';
import 'testnet.dart';
import 'types.dart';

export 'mainnet.dart';
export 'testnet.dart';
export 'types.dart';

StateError _unrecorded(String network, String override) =>
    StateError("deepbook: no deployment recorded for network '$network'. "
        'Predict, sessions and the account primitive are recorded for testnet '
        'and mainnet. For your own deployment, $override');

/// Which deployment the ids on [network] came from — its name and the
/// deepbookv3 commit they were generated at. Useful when a bug report needs
/// to say which on-chain deployment an SDK build was pinned to.
///
/// Throws if the network has no deployment recorded, rather than returning
/// placeholder ids.
DeploymentInfo getDeployment(String network) {
  if (network == 'testnet') return TESTNET_DEPLOYMENT;
  if (network == 'mainnet') return MAINNET_DEPLOYMENT;
  throw _unrecorded(network,
      'read the deployment name and commit from your own deploy manifest.');
}

/// Scale constants for [network] — lot size, fixed-point scale, and coin
/// decimals. Deployment-wide, so any subsystem formatting a custody balance
/// can read them rather than hardcoding 6.
///
/// Throws if the network has no recorded deployment.
DeploymentUnits getUnits(String network) {
  if (network == 'testnet') return TESTNET_UNITS;
  if (network == 'mainnet') return MAINNET_UNITS;
  throw _unrecorded(
      network, 'read these scale constants from your own deploy manifest.');
}
