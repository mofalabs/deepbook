/// Flash loan transaction builders, mirroring the official SDK's
/// `transactions/flashLoans.ts`.
///
/// Every method returns a closure to apply to a [Transaction]
/// (`contract.method(...)(tx)`), matching the official
/// `tx.add(contract.method(...))` composition style.
library;

import 'package:sui/sui.dart' show Transaction, TransactionResult;

import '../config.dart';
import '../contracts/deepbook/pool.dart' as pool_calls;
import '../conversion.dart';

/// FlashLoanContract class for managing flash loans.
class FlashLoanContract {
  final DeepBookConfig _config;

  /// `config` Configuration object for DeepBook.
  FlashLoanContract(this._config);

  /// Coerces a coin argument (a [TransactionResult] or an already-built
  /// argument map) into the map form `tx.splitCoins` expects.
  static Map<String, dynamic> _asArgumentMap(dynamic value) =>
      value is TransactionResult
          ? value.result
          : (value as Map).cast<String, dynamic>();

  /// Borrow base asset from the pool.
  ///
  /// The result supports `[0]` (the borrowed base coin) and `[1]` (the
  /// FlashLoan hot potato).
  ///
  /// [poolKey] The key to identify the pool.
  /// [borrowAmount] The amount to borrow.
  TransactionResult Function(Transaction) borrowBaseAsset(
          String poolKey, Object borrowAmount) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputQuantity = convertQuantity(borrowAmount, baseCoin.scalar);

        return pool_calls.borrowFlashloanBase(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'baseAmount': inputQuantity},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Return base asset to the pool after a flash loan.
  ///
  /// Returns [baseCoinInput] (the remainder after the repayment split).
  ///
  /// [poolKey] The key to identify the pool.
  /// [borrowAmount] The amount of the base asset to return.
  /// [baseCoinInput] Coin object representing the base asset to be returned.
  /// [flashLoan] FlashLoan object representing the loan to be settled.
  dynamic Function(Transaction) returnBaseAsset(String poolKey,
          Object borrowAmount, dynamic baseCoinInput, dynamic flashLoan) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final borrowScalar = baseCoin.scalar;

        final baseCoinReturn = tx.splitCoins(
          _asArgumentMap(baseCoinInput),
          [convertQuantity(borrowAmount, borrowScalar)],
        )[0];
        pool_calls.returnFlashloanBase(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'coin': baseCoinReturn,
            'flashLoan': flashLoan,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);

        return baseCoinInput;
      };

  /// Borrow quote asset from the pool.
  ///
  /// The result supports `[0]` (the borrowed quote coin) and `[1]` (the
  /// FlashLoan hot potato).
  ///
  /// [poolKey] The key to identify the pool.
  /// [borrowAmount] The amount to borrow.
  TransactionResult Function(Transaction) borrowQuoteAsset(
          String poolKey, Object borrowAmount) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final inputQuantity = convertQuantity(borrowAmount, quoteCoin.scalar);

        return pool_calls.borrowFlashloanQuote(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {'self': pool.address, 'quoteAmount': inputQuantity},
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);
      };

  /// Return quote asset to the pool after a flash loan.
  ///
  /// Returns [quoteCoinInput] (the remainder after the repayment split).
  ///
  /// [poolKey] The key to identify the pool.
  /// [borrowAmount] The amount of the quote asset to return.
  /// [quoteCoinInput] Coin object representing the quote asset to be returned.
  /// [flashLoan] FlashLoan object representing the loan to be settled.
  dynamic Function(Transaction) returnQuoteAsset(String poolKey,
          Object borrowAmount, dynamic quoteCoinInput, dynamic flashLoan) =>
      (tx) {
        final pool = _config.getPool(poolKey);
        final baseCoin = _config.getCoin(pool.baseCoin);
        final quoteCoin = _config.getCoin(pool.quoteCoin);
        final borrowScalar = quoteCoin.scalar;

        final quoteCoinReturn = tx.splitCoins(
          _asArgumentMap(quoteCoinInput),
          [convertQuantity(borrowAmount, borrowScalar)],
        )[0];
        pool_calls.returnFlashloanQuote(
          package: _config.DEEPBOOK_PACKAGE_ID,
          arguments: {
            'self': pool.address,
            'coin': quoteCoinReturn,
            'flashLoan': flashLoan,
          },
          typeArguments: [baseCoin.type, quoteCoin.type],
        )(tx);

        return quoteCoinInput;
      };
}
