/// Time-limited trading sessions — `package:deepbook/sessions.dart`.
///
/// Mirrors the official `@mysten/deepbook-v3/sessions` subpath: an Account
/// owner authorizes an ephemeral address to act for the Account until a fixed
/// expiry, and the session key never holds a reusable `Auth` — each wrapper
/// mints app authorization internally and consumes it in the same call. Like
/// the official subpath, this entry point is a separate library: importing it
/// does not load spot or margin code, and `package:deepbook/deepbook.dart` is
/// unchanged.
library;

export 'src/sessions/sessions_contract.dart';

// The error types this subpath throws ([ConfigurationError] from
// `getSessionsConfig`, [ValidationError] from `decodeSessions`), so a
// sessions-only consumer can catch them without importing the root.
export 'src/errors.dart'
    show DeepBookError, ConfigurationError, ValidationError;

// Provenance and scale constants, so a sessions-only consumer can answer
// "which deployment is this pinned to?" and format a custody balance without
// importing another subpath.
export 'src/deployments/deployments.dart'
    show
        getDeployment,
        getUnits,
        TESTNET_DEPLOYMENT,
        TESTNET_UNITS,
        DeploymentInfo,
        DeploymentUnits;

// === Generated bindings ===
// NOTE: the sessions module carries the DeepBook spot session calls too
// (`placeLimitOrder`, `placeMarketOrder`, `cancelLiveOrder(s)`,
// `withdrawSettledAmounts`). They are generated and callable; they are simply
// not wrapped on `SessionsContract`. The official SDK exports these as the
// `sessionsMoveCalls` and `sessionConfigMoveCalls` namespaces; Dart has no
// namespace export, so they are exported flat — import this library with a
// prefix when the bare builder names would collide. The generated
// `SessionsConfig` BCS struct is hidden here because the high-level config
// class of the same name takes the root export, as in the official SDK;
// to parse the shared object, import the module's own library with a prefix:
// `import 'package:deepbook/sessions/session_config.dart' as sc;`.
export 'src/contracts/deepbook_sessions/sessions.dart' hide $moduleName;
export 'src/contracts/deepbook_sessions/session_config.dart'
    hide $moduleName, SessionsConfig;
