/// Admin (AdminCap-gated) transaction builders, mirroring the official SDK's
/// `transactions/deepbookAdmin.ts`.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook/pool.dart' as pool_calls;
import '../contracts/deepbook/registry.dart' as registry_calls;
import '../conversion.dart';
import '../errors.dart';
import '../types.dart';

/// DeepBookAdminContract class for managing admin actions.
class DeepBookAdminContract {
  final DeepBookConfig _config;

  DeepBookAdminContract(this._config);

  String get _adminCap {
    final adminCap = _config.adminCap;
    if (adminCap == null) {
      throw ConfigurationError('ADMIN_CAP environment variable not set');
    }
    return adminCap;
  }

  /// Create a new pool as admin.
  void Function(Transaction) createPoolAdmin(CreatePoolAdminParams params) =>
      (tx) {
        tx.setSenderIfNotSet(_config.address);
        final baseCoin = _config.getCoin(params.baseCoinKey);
        final quoteCoin = _config.getCoin(params.quoteCoinKey);

        final adjustedTickSize = convertPrice(
            params.tickSize, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        final adjustedLotSize =
            convertQuantity(params.lotSize, baseCoin.scalar);
        final adjustedMinSize =
            convertQuantity(params.minSize, baseCoin.scalar);

        pool_calls.createPoolAdmin(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'registry': _config.REGISTRY_ID,
            'tickSize': adjustedTickSize,
            'lotSize': adjustedLotSize,
            'minSize': adjustedMinSize,
            'whitelistedPool': params.whitelisted,
            'stablePool': params.stablePool,
            'Cap': _adminCap,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Unregister a pool as admin.
  void Function(Transaction) unregisterPoolAdmin(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_calls.unregisterPoolAdmin(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'registry': _config.REGISTRY_ID,
            'Cap': _adminCap,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Update the allowed versions for a pool.
  void Function(Transaction) updateAllowedVersions(String poolKey) => (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_calls.updateAllowedVersions(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'registry': _config.REGISTRY_ID,
            'Cap': _adminCap,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Enable a specific version.
  void Function(Transaction) enableVersion(int version) => (tx) {
        registry_calls.enableVersion(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': _config.REGISTRY_ID,
            'version': version,
            'Cap': _adminCap,
          },
        )(tx);
      };

  /// Disable a specific version.
  void Function(Transaction) disableVersion(int version) => (tx) {
        registry_calls.disableVersion(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': _config.REGISTRY_ID,
            'version': version,
            'Cap': _adminCap,
          },
        )(tx);
      };

  /// Sets the treasury address where pool creation fees will be sent.
  void Function(Transaction) setTreasuryAddress(String treasuryAddress) =>
      (tx) {
        registry_calls.setTreasuryAddress(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': _config.REGISTRY_ID,
            'treasuryAddress': treasuryAddress,
            'Cap': _adminCap,
          },
        )(tx);
      };

  /// Add a coin to the whitelist of stable coins.
  void Function(Transaction) addStableCoin(String stableCoinKey) => (tx) {
        registry_calls.addStablecoin(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': _config.REGISTRY_ID, 'Cap': _adminCap},
          typeArguments: [_config.getCoin(stableCoinKey).type],
        )(tx);
      };

  /// Remove a coin from the whitelist of stable coins.
  void Function(Transaction) removeStableCoin(String stableCoinKey) => (tx) {
        registry_calls.removeStablecoin(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': _config.REGISTRY_ID, 'Cap': _adminCap},
          typeArguments: [_config.getCoin(stableCoinKey).type],
        )(tx);
      };

  /// Adjust the tick size of a pool.
  void Function(Transaction) adjustTickSize(
          String poolKey, Object newTickSize) =>
      (tx) {
        tx.setSenderIfNotSet(_config.address);
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final adjustedTickSize = convertPrice(
            newTickSize, FLOAT_SCALAR, quoteCoin.scalar, baseCoin.scalar);
        pool_calls.adjustTickSizeAdmin(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'newTickSize': adjustedTickSize,
            'Cap': _adminCap,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Adjust the lot size and min size of a pool.
  void Function(Transaction) adjustMinLotSize(
          String poolKey, Object newLotSize, Object newMinSize) =>
      (tx) {
        tx.setSenderIfNotSet(_config.address);
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_calls.adjustMinLotSizeAdmin(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'newLotSize': convertQuantity(newLotSize, baseCoin.scalar),
            'newMinSize': convertQuantity(newMinSize, baseCoin.scalar),
            'Cap': _adminCap,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Initialize the balance manager map.
  void Function(Transaction) initBalanceManagerMap() => (tx) {
        registry_calls.initBalanceManagerMap(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': _config.REGISTRY_ID, 'Cap': _adminCap},
        )(tx);
      };

  /// Set the EWMA parameters for a pool.
  void Function(Transaction) setEwmaParams(
          String poolKey, SetEwmaParams params) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_calls.setEwmaParams(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'Cap': _adminCap,
            'alpha': convertRate(params.alpha, FLOAT_SCALAR),
            'zScoreThreshold':
                convertRate(params.zScoreThreshold, FLOAT_SCALAR),
            'additionalTakerFee':
                convertRate(params.additionalTakerFee, FLOAT_SCALAR),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Enable or disable the EWMA state for a pool.
  void Function(Transaction) enableEwmaState(String poolKey, bool enable) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        pool_calls.enableEwmaState(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'Cap': _adminCap,
            'enable': enable,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Authorize the MarginApp to access protected features of DeepBook.
  void Function(Transaction) authorizeMarginApp() => (tx) {
        registry_calls.authorizeApp(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': _config.REGISTRY_ID, 'AdminCap': _adminCap},
          typeArguments: ['${_config.MARGIN_V1}::margin_manager::MarginApp'],
        )(tx);
      };

  /// Deauthorize the MarginApp; returns a bool.
  TransactionResult Function(Transaction) deauthorizeMarginApp() =>
      (tx) => registry_calls.deauthorizeApp(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {'self': _config.REGISTRY_ID, 'AdminCap': _adminCap},
            typeArguments: ['${_config.MARGIN_V1}::margin_manager::MarginApp'],
          )(tx);

  /// Mint a `DeepbookCorePauseCap`; returns the new pause cap.
  TransactionResult Function(Transaction) mintCorePauseCap() =>
      (tx) => registry_calls.mintPauseCap(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {'self': _config.REGISTRY_ID, 'Cap': _adminCap},
          )(tx);

  /// Revoke a previously minted `DeepbookCorePauseCap` by ID.
  void Function(Transaction) revokeCorePauseCap(String pauseCapId) => (tx) {
        registry_calls.revokePauseCap(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': _config.REGISTRY_ID,
            'Cap': _adminCap,
            'pauseCapId': pauseCapId,
          },
        )(tx);
      };

  /// Emergency kill switch — disable an allowed core package version using a
  /// held `DeepbookCorePauseCap`. Re-enable later via [enableVersion].
  void Function(Transaction) disableVersionWithCorePauseCap(
          Object version, String pauseCapId) =>
      (tx) {
        registry_calls.disableVersionPauseCap(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': _config.REGISTRY_ID,
            'version': version,
            'pauseCap': pauseCapId,
          },
        )(tx);
      };

  /// Get the set of allowed `DeepbookCorePauseCap` IDs; returns a
  /// `VecSet<ID>`.
  TransactionResult Function(Transaction) corePauseCaps() =>
      (tx) => registry_calls.allowedPauseCaps(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {'self': _config.REGISTRY_ID},
          )(tx);
}
