/// The shared on-chain account primitive, mirroring the official SDK's
/// `src/account.ts` (`@mysten/deepbook-v3/account`).
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'dart:typed_data';

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../contracts/account/account.dart' as account;
import '../contracts/account/account_registry.dart' as account_registry;
import '../deployments/deployments.dart';
import '../errors.dart';
import 'derived_objects.dart';

/// The deployed ids of the shared `account` package this contract builds
/// against.
///
/// Kept deliberately minimal — ids only — so any consumer of the shared
/// account primitive (DeepBook core's account wrapper, Predict, …) can drive
/// these builders with its OWN deployment's ids without constructing a full
/// product-SDK config. The same shape the deployment records carry, so
/// [getAccountConfig] hands the record straight through.
typedef AccountConfig = AccountIds;

/// The deployed `account` ids for [network], so a caller does not transcribe
/// them. Generated from the deploy manifest — see `lib/src/deployments/`.
///
/// Throws if the network has no recorded deployment, rather than returning
/// placeholder ids that would fail as a confusing on-chain abort.
///
/// ```dart
/// final account = AccountContract(getAccountConfig('testnet'));
/// ```
AccountConfig getAccountConfig(String network) {
  if (network == 'testnet') return testnetAccount;
  if (network == 'mainnet') return mainnetAccount;
  throw ConfigurationError(
      "deepbook/account: no account deployment recorded for network "
      "'$network'. The account primitive is recorded for testnet and "
      'mainnet; for your own deployment pass AccountConfig('
      'accountPackageId: ..., accountRegistry: ...) to AccountContract '
      'directly.');
}

/// AccountContract — the reusable on-chain account primitive
/// (`packages/account`).
///
/// An owner has one canonical `AccountWrapper`, a *derived* object of the
/// account registry, so its id is computable off-chain (no read). The wrapper
/// holds an `Account` whose custody balances apps deposit into and withdraw
/// from; app-specific data hangs off it under an app-keyed slot. Authority is
/// a hot-potato `Auth` minted from the tx sender and consumed by the very
/// next account-loading call.
class AccountContract {
  final AccountConfig _config;

  /// [config] carries the deployed ids of the shared `account` package.
  AccountContract(this._config);

  Map<String, dynamic> get _generatedConfig => {
        'accountPackageId': _config.accountPackageId,
        'accountRegistry': _config.accountRegistry,
      };

  /// The deterministic id of an owner's canonical account wrapper — no chain
  /// read needed. The wrapper is a derived object of the account registry, so
  /// its id is `derive_address(registry, AccountWrapperKey(owner))`.
  String deriveAccountWrapperId(String owner) {
    // `AccountWrapperKey(address)` is a one-field positional struct, so its
    // BCS is just the owner's 32-byte address.
    final key = Uint8List.fromList(
        account_registry.AccountWrapperKey.serialize([owner]).toBytes());
    return deriveObjectID(
      _config.accountRegistry,
      '${_config.accountPackageId}::account_registry::AccountWrapperKey',
      key,
    );
  }

  /// Mint owner authority for the transaction sender. A hot-potato `Auth`
  /// consumed by the very next account-loading call (`load_account_mut`
  /// inside `deposit_funds` / `withdraw_funds` / an app's own entrypoints).
  TransactionResult Function(Transaction) generateAuth() =>
      (tx) => account.generateAuth(config: _generatedConfig)(tx);

  /// Create the sender's canonical account wrapper and share it. `new`
  /// derives the wrapper at its deterministic address (see
  /// [deriveAccountWrapperId]) and aborts if it already exists; `share`
  /// publishes the shared object apps borrow against.
  void Function(Transaction) createAccount() => (tx) {
        final wrapper = account_registry.new_(config: _generatedConfig)(tx);
        account.share(
          config: _generatedConfig,
          arguments: {'self': wrapper},
        )(tx);
      };

  /// First-time funding in ONE PTB: create the sender's wrapper, deposit
  /// [coin] through the fresh handle, then `share` LAST (once shared,
  /// by-value use of the handle is over). This cannot be split into
  /// [createAccount] + [depositFunds]: an object input can only address an
  /// object that pre-exists the PTB, so a wrapper created inside it is
  /// reachable only through `new`'s result handle.
  ///
  /// [coin] is a transaction argument (an input object or a prior command's
  /// result) carrying a `Coin<coinType>`.
  void Function(Transaction) createAccountAndDeposit({
    required dynamic coin,
    required String coinType,
  }) =>
      (tx) {
        final wrapper = account_registry.new_(config: _generatedConfig)(tx);
        final auth = generateAuth()(tx);
        account.depositFunds(
          config: _generatedConfig,
          arguments: {'wrapper': wrapper, 'auth': auth, 'coin': coin},
          typeArguments: [coinType],
        )(tx);
        account.share(
          config: _generatedConfig,
          arguments: {'self': wrapper},
        )(tx);
      };

  /// Deposit a caller-provided [coin] into the account's stored balance via
  /// the PTB-callable `deposit_funds` (folds settle → authorize → load →
  /// deposit; clock and accumulator root auto-injected). The caller owns coin
  /// sourcing.
  void Function(Transaction) depositFunds({
    required String wrapperId,
    required dynamic coin,
    required String coinType,
  }) =>
      (tx) {
        final auth = generateAuth()(tx);
        account.depositFunds(
          config: _generatedConfig,
          arguments: {'wrapper': wrapperId, 'auth': auth, 'coin': coin},
          typeArguments: [coinType],
        )(tx);
      };

  /// Withdraw [amount] (raw u64 units) from the account's stored balance via
  /// the PTB-callable `withdraw_funds` (folds settle → authorize → load →
  /// withdraw; clock and accumulator root auto-injected), returning the
  /// minted `Coin<T>` for the caller to transfer or compose.
  TransactionResult Function(Transaction) withdrawFunds({
    required String wrapperId,
    required BigInt amount,
    required String coinType,
  }) =>
      (tx) {
        final auth = generateAuth()(tx);
        return account.withdrawFunds(
          config: _generatedConfig,
          arguments: {'wrapper': wrapperId, 'auth': auth, 'amount': amount},
          typeArguments: [coinType],
        )(tx);
      };

  /// Borrow the `Account` out of its wrapper — the read-side entry point apps
  /// chain their own getters onto (`account::balance<T>`, an app's own data
  /// accessors).
  TransactionResult Function(Transaction) loadAccount(
          {required String wrapperId}) =>
      (tx) => account.loadAccount(
            config: _generatedConfig,
            arguments: {'self': wrapperId},
          )(tx);

  /// Read an owner's stored custody balance for a coin type: chains
  /// `load_account(wrapper)` → `balance<T>(account, root, clock)`. Compose in
  /// a dev-inspect/simulate PTB and read the u64 return of the LAST command.
  TransactionResult Function(Transaction) balance({
    required String owner,
    required String coinType,
  }) =>
      (tx) {
        final acct = loadAccount(wrapperId: deriveAccountWrapperId(owner))(tx);
        return account.balance(
          config: _generatedConfig,
          typeArguments: [coinType],
          arguments: {'self': acct},
        )(tx);
      };
}
