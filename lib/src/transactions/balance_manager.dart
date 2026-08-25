/// BalanceManager transaction builders, mirroring the official SDK's
/// `transactions/balanceManager.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook/balance_manager.dart' as balance_manager;
import '../conversion.dart';
import '../errors.dart';

/// BalanceManagerContract class for managing BalanceManager operations.
class BalanceManagerContract {
  final DeepBookConfig _config;

  BalanceManagerContract(this._config);

  /// Create and share a new BalanceManager.
  void Function(Transaction) createAndShareBalanceManager() => (tx) {
        // Positional moveCalls, kept verbatim from the official SDK (the
        // zero-arg on-chain `new` drifted from the codegen binding, and
        // `public_share_object` is a framework call with no binding).
        final manager =
            tx.moveCall('${_config.DEEPBOOK_PACKAGE_ID}::balance_manager::new');
        tx.moveCall(
          '0x2::transfer::public_share_object',
          arguments: [manager],
          typeArguments: [
            '${_config.DEEPBOOK_PACKAGE_ID}::balance_manager::BalanceManager'
          ],
        );
      };

  /// Create a new BalanceManager with an explicit owner; returns the manager.
  TransactionResult Function(Transaction) createBalanceManagerWithOwner(
          String ownerAddress) =>
      (tx) => balance_manager.newWithCustomOwner(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {'owner': ownerAddress},
          )(tx);

  /// Share the BalanceManager.
  void Function(Transaction) shareBalanceManager(dynamic manager) => (tx) {
        tx.moveCall(
          '0x2::transfer::public_share_object',
          arguments: [manager],
          typeArguments: [
            '${_config.DEEPBOOK_PACKAGE_ID}::balance_manager::BalanceManager'
          ],
        );
      };

  /// Deposit funds into the BalanceManager.
  void Function(Transaction) depositIntoManager(
          String managerKey, String coinKey, Object amountToDeposit) =>
      (tx) {
        tx.setSenderIfNotSet(_config.address);
        final managerId = _config.getBalanceManager(managerKey).address;
        final coin = _config.getCoin(coinKey);
        final depositInput = convertQuantity(amountToDeposit, coin.scalar);
        final deposit = tx.coin(coin.type, depositInput);

        balance_manager.deposit(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'balanceManager': managerId, 'coin': deposit},
          typeArguments: [coin.type],
        )(tx);
      };

  /// Withdraw funds from the BalanceManager to [recipient].
  void Function(Transaction) withdrawFromManager(String managerKey,
          String coinKey, Object amountToWithdraw, String recipient) =>
      (tx) {
        final managerId = _config.getBalanceManager(managerKey).address;
        final coin = _config.getCoin(coinKey);
        final withdrawInput = convertQuantity(amountToWithdraw, coin.scalar);
        final coinObject = balance_manager.withdraw(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'balanceManager': managerId,
            'withdrawAmount': withdrawInput,
          },
          typeArguments: [coin.type],
        )(tx);

        tx.transferObjects([coinObject], recipient);
      };

  /// Withdraw all funds of [coinKey] from the BalanceManager to [recipient].
  void Function(Transaction) withdrawAllFromManager(
          String managerKey, String coinKey, String recipient) =>
      (tx) {
        final managerId = _config.getBalanceManager(managerKey).address;
        final coin = _config.getCoin(coinKey);
        final withdrawalCoin = balance_manager.withdrawAll(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'balanceManager': managerId},
          typeArguments: [coin.type],
        )(tx);

        tx.transferObjects([withdrawalCoin], recipient);
      };

  /// Check the balance of the BalanceManager (returns u64 on-chain).
  void Function(Transaction) checkManagerBalance(
          String managerKey, String coinKey) =>
      (tx) {
        final managerId = _config.getBalanceManager(managerKey).address;
        final coin = _config.getCoin(coinKey);
        balance_manager.balance(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'balanceManager': managerId},
          typeArguments: [coin.type],
        )(tx);
      };

  /// Generate a trade proof; uses the TradeCap when one is configured.
  TransactionResult Function(Transaction) generateProof(String managerKey) =>
      (tx) {
        final balanceManager = _config.getBalanceManager(managerKey);
        final tradeCap = balanceManager.tradeCap;
        return tradeCap != null
            ? generateProofAsTrader(balanceManager.address, tradeCap)(tx)
            : generateProofAsOwner(balanceManager.address)(tx);
      };

  /// Generate a trade proof as the owner.
  TransactionResult Function(Transaction) generateProofAsOwner(
          String managerId) =>
      (tx) => balance_manager.generateProofAsOwner(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {'balanceManager': managerId},
          )(tx);

  /// Generate a trade proof as a trader.
  TransactionResult Function(Transaction) generateProofAsTrader(
          String managerId, String tradeCapId) =>
      (tx) => balance_manager.generateProofAsTrader(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {'balanceManager': managerId, 'tradeCap': tradeCapId},
          )(tx);

  /// Mint a TradeCap.
  TransactionResult Function(Transaction) mintTradeCap(String managerKey) =>
      (tx) => balance_manager.mintTradeCap(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {
              'balanceManager': _config.getBalanceManager(managerKey).address,
            },
          )(tx);

  /// Mint a DepositCap.
  TransactionResult Function(Transaction) mintDepositCap(String managerKey) =>
      (tx) => balance_manager.mintDepositCap(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {
              'balanceManager': _config.getBalanceManager(managerKey).address,
            },
          )(tx);

  /// Mint a WithdrawalCap.
  TransactionResult Function(Transaction) mintWithdrawalCap(
          String managerKey) =>
      (tx) => balance_manager.mintWithdrawCap(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {
              'balanceManager': _config.getBalanceManager(managerKey).address,
            },
          )(tx);

  /// Deposit using the DepositCap.
  void Function(Transaction) depositWithCap(
          String managerKey, String coinKey, Object amountToDeposit) =>
      (tx) {
        tx.setSenderIfNotSet(_config.address);
        final manager = _config.getBalanceManager(managerKey);
        final depositCapId = manager.depositCap;
        if (depositCapId == null) {
          throw DeepBookError('DepositCap not set for $managerKey');
        }
        final coin = _config.getCoin(coinKey);
        final depositInput = convertQuantity(amountToDeposit, coin.scalar);
        final deposit = tx.coin(coin.type, depositInput);
        balance_manager.depositWithCap(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'balanceManager': manager.address,
            'depositCap': depositCapId,
            'coin': deposit,
          },
          typeArguments: [coin.type],
        )(tx);
      };

  /// Withdraw using the WithdrawCap.
  TransactionResult Function(Transaction) withdrawWithCap(
          String managerKey, String coinKey, Object amountToWithdraw) =>
      (tx) {
        tx.setSenderIfNotSet(_config.address);
        final manager = _config.getBalanceManager(managerKey);
        final withdrawCapId = manager.withdrawCap;
        if (withdrawCapId == null) {
          throw DeepBookError('WithdrawCap not set for $managerKey');
        }
        final coin = _config.getCoin(coinKey);
        final withdrawAmount = convertQuantity(amountToWithdraw, coin.scalar);
        return balance_manager.withdrawWithCap(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'balanceManager': manager.address,
            'withdrawCap': withdrawCapId,
            'withdrawAmount': withdrawAmount,
          },
          typeArguments: [coin.type],
        )(tx);
      };

  /// Set the referral (DeepBookPoolReferral) for the BalanceManager.
  void Function(Transaction) setBalanceManagerReferral(
          String managerKey, String referral, dynamic tradeCap) =>
      (tx) {
        final managerId = _config.getBalanceManager(managerKey).address;
        balance_manager.setBalanceManagerReferral(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'balanceManager': managerId,
            'referral': referral,
            'tradeCap': tradeCap,
          },
        )(tx);
      };

  /// Unset the referral for the BalanceManager for a specific pool.
  void Function(Transaction) unsetBalanceManagerReferral(
          String managerKey, String poolKey, dynamic tradeCap) =>
      (tx) {
        final managerId = _config.getBalanceManager(managerKey).address;
        final poolId = _config.getPool(poolKey).address;
        balance_manager.unsetBalanceManagerReferral(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'balanceManager': managerId,
            'poolId': poolId,
            'tradeCap': tradeCap,
          },
        )(tx);
      };

  /// Register the BalanceManager in the registry.
  void Function(Transaction) registerBalanceManager(String managerKey) => (tx) {
        final managerId = _config.getBalanceManager(managerKey).address;
        balance_manager.registerBalanceManager(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'balanceManager': managerId,
            'registry': _config.REGISTRY_ID,
          },
        )(tx);
      };

  /// Get the owner of the BalanceManager.
  void Function(Transaction) owner(String managerKey) => (tx) {
        balance_manager.owner(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'balanceManager': _config.getBalanceManager(managerKey).address,
          },
        )(tx);
      };

  /// Get the ID of the BalanceManager.
  void Function(Transaction) id(String managerKey) => (tx) {
        balance_manager.id(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'balanceManager': _config.getBalanceManager(managerKey).address,
          },
        )(tx);
      };

  /// Get the owner of a referral (DeepBookPoolReferral).
  TransactionResult Function(Transaction) balanceManagerReferralOwner(
          String referralId) =>
      (tx) => balance_manager.balanceManagerReferralOwner(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {'referral': referralId},
          )(tx);

  /// Get the pool ID associated with a referral (DeepBookPoolReferral).
  TransactionResult Function(Transaction) balanceManagerReferralPoolId(
          String referralId) =>
      (tx) => balance_manager.balanceManagerReferralPoolId(
            package: _config.DEEPBOOK_PACKAGE_ID,
            arguments: {'referral': referralId},
          )(tx);

  /// Get the referral ID from the balance manager for a specific pool.
  TransactionResult Function(Transaction) getBalanceManagerReferralId(
          String managerKey, String poolKey) =>
      (tx) {
        final managerId = _config.getBalanceManager(managerKey).address;
        final poolId = _config.getPool(poolKey).address;
        return balance_manager.getBalanceManagerReferralId(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'balanceManager': managerId, 'poolId': poolId},
        )(tx);
      };

  /// Revoke a TradeCap (also revokes the associated Deposit/Withdraw caps).
  void Function(Transaction) revokeTradeCap(
          String managerKey, String tradeCapId) =>
      (tx) {
        final managerId = _config.getBalanceManager(managerKey).address;
        balance_manager.revokeTradeCap(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'balanceManager': managerId, 'tradeCapId': tradeCapId},
        )(tx);
      };
}
