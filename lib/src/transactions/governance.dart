/// Governance transaction builders, mirroring the official SDK's
/// `transactions/governance.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction;

import '../config.dart';
import '../contracts/deepbook/pool.dart' as pool_calls;
import '../conversion.dart';
import '../types.dart';
import 'balance_manager.dart';

/// GovernanceContract class for managing governance operations in DeepBook.
class GovernanceContract {
  final DeepBookConfig _config;
  final BalanceManagerContract _balanceManager;

  /// `config` — configuration for GovernanceContract.
  GovernanceContract(DeepBookConfig config)
      : _config = config,
        _balanceManager = BalanceManagerContract(config);

  /// Stake a specified amount in the pool.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  /// [stakeAmount] The amount to stake.
  void Function(Transaction) stake(
          String poolKey, String balanceManagerKey, Object stakeAmount) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final stakeInput = convertQuantity(stakeAmount, DEEP_SCALAR);

        pool_calls.stake(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'amount': stakeInput,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Unstake from the pool.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  void Function(Transaction) unstake(
          String poolKey, String balanceManagerKey) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.unstake(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Submit a governance proposal.
  ///
  /// [params] Parameters for the proposal.
  void Function(Transaction) submitProposal(ProposalParams params) => (tx) {
        final pool = _config.getPool(params.poolKey);
        final balanceManager =
            _config.getBalanceManager(params.balanceManagerKey);
        final tradeProof =
            _balanceManager.generateProof(params.balanceManagerKey)(tx);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.submitProposal(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'takerFee': convertRate(params.takerFee, FLOAT_SCALAR),
            'makerFee': convertRate(params.makerFee, FLOAT_SCALAR),
            'stakeRequired': convertQuantity(params.stakeRequired, DEEP_SCALAR),
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Vote on a proposal.
  ///
  /// [poolKey] The key to identify the pool.
  /// [balanceManagerKey] The key to identify the BalanceManager.
  /// [proposalId] The ID of the proposal to vote on.
  void Function(Transaction) vote(
          String poolKey, String balanceManagerKey, String proposalId) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final balanceManager = _config.getBalanceManager(balanceManagerKey);
        final tradeProof = _balanceManager.generateProof(balanceManagerKey)(tx);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);

        pool_calls.vote(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'balanceManager': balanceManager.address,
            'tradeProof': tradeProof,
            'proposalId': proposalId,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };
}
