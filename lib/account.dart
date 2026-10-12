/// The shared on-chain account primitive — `package:deepbook/account.dart`.
///
/// Mirrors the official `@mysten/deepbook-v3/account` subpath: the primitive
/// is shared infrastructure (DeepBook's core account wrapper and DeepBook
/// Predict both build on the same Move package), so it lives alongside spot
/// and margin rather than in either consumer. Like the official subpath, this
/// entry point is a separate library: importing it does not load spot or
/// margin code, and `package:deepbook/deepbook.dart` is unchanged.
///
/// NOTE: the [Account] BCS struct exported here is the account primitive's
/// custody account (`account::account::Account`). It is a DIFFERENT type from
/// the `Account` exported by `package:deepbook/deepbook.dart`
/// (`@deepbook/core::account::Account`, the per-pool trading account) and the
/// two have unrelated layouts. Keep them separated by import, or import this
/// library with a prefix.
library;

export 'src/account/account_contract.dart';

// The error types this subpath throws ([ConfigurationError] from
// `getAccountConfig`), so an account-only consumer can catch them without
// importing the root.
export 'src/errors.dart'
    show DeepBookError, ConfigurationError, ValidationError;

// Provenance: which on-chain deployment the ids above came from. Re-exported
// so a consumer can answer "which deploy is this build pinned to?" without
// reaching for another subpath.
export 'src/deployments/deployments.dart'
    show
        getDeployment,
        getUnits,
        TESTNET_DEPLOYMENT,
        TESTNET_UNITS,
        AccountIds,
        DeploymentInfo,
        DeploymentUnits;

// === Generated bindings ===
// The move-call builders and BCS structs, for consumers composing their own
// PTBs or parsing account objects/events (e.g. `AccountWrapper.parse`, the
// event layouts). The official SDK exports these as the `accountMoveCalls`,
// `accountRegistryMoveCalls` and `accountEvents` namespaces; Dart has no
// namespace export, so they are exported flat — import this library with a
// prefix when the bare builder names (`share`, `settle`, …) would collide, or
// import a single module whole via `package:deepbook/account/<module>.dart`.
export 'src/contracts/account/account.dart' hide $moduleName;
export 'src/contracts/account/account_events.dart' hide $moduleName;
export 'src/contracts/account/account_registry.dart' hide $moduleName;
