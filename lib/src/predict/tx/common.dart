/// Shared tx plumbing, mirroring `predict/tx/common.ts`.
///
/// Predict's accounts ARE the shared on-chain account primitive
/// (`packages/account`), so the builders live in
/// `package:deepbook/account.dart` and this is the thin adapter that drives
/// them with Predict's deployed ids.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../../account/account_contract.dart'
    show AccountConfig, AccountContract;
import '../../contracts/account/account.dart' as account;
import '../../contracts/utils.dart' show MoveCallBuilder;
import '../../deployments/deployments.dart' show AccountIds;
import '../config.dart';

/// An [AccountContract] bound to Predict's deployed account ids.
AccountContract accountContract(PredictConfig cfg) => AccountContract(
      AccountConfig(
        accountPackageId: cfg.packages.account,
        accountRegistry: cfg.objects.accountRegistry,
      ),
    );

/// Mint owner authority for the transaction sender. Owner authority is a
/// hot-potato `Auth` minted from the tx sender (`ctx` is implicit in a PTB)
/// and consumed by the very next account-loading call (`load_account_mut`
/// inside `deposit_funds` / `withdraw_funds` / `mint` / …). It resolves to
/// owner auth for whoever signs the transaction.
TransactionResult Function(Transaction) generateAuth(PredictConfig cfg) =>
    (tx) => account.generateAuth(config: toGeneratedConfig(cfg))(tx);

/// Every owner-authorized call in this SDK is the same two commands — mint
/// the hot-potato `Auth`, then make the generated call that consumes it. This
/// lifts a generated-call closure into that pair: [build] receives the minted
/// auth handle and returns the one call consuming it. Mirrors the official
/// `withAuth` (which lifts at the type level; Dart lifts at the call site).
MoveCallBuilder withAuth(
  GeneratedConfig config,
  MoveCallBuilder Function(TransactionResult auth) build,
) {
  return (tx) {
    final auth = account.generateAuth(config: config)(tx);
    return build(auth)(tx);
  };
}

/// The deterministic id of an owner's canonical account wrapper, from the
/// flat config slice. The derivation must agree with on-chain
/// `derive_address`, so it is owned in one place —
/// `package:deepbook/account.dart` — and this projects Predict's config onto
/// that contract.
String deriveAccountWrapperIdFrom(GeneratedConfig config, String owner) {
  return AccountContract(
    AccountIds(
      accountPackageId: config['accountPackageId'] as String,
      accountRegistry: config['accountRegistry'] as String,
    ),
  ).deriveAccountWrapperId(owner);
}

/// The deterministic id of an owner's canonical account wrapper — no chain
/// read needed. The pure `(cfg, owner)` form of `PredictClient.wrapperIdFor`
/// for contexts with no client instance.
String deriveAccountWrapperId(PredictConfig cfg, String owner) =>
    deriveAccountWrapperIdFrom(toGeneratedConfig(cfg), owner);
