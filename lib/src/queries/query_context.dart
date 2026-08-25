/// Shared query plumbing, mirroring the official SDK's `queries/context.ts`.
///
/// All DeepBook queries are devInspect-style: build a read-only transaction,
/// `simulateTransaction` it (server mocks the gas coin), and BCS-parse the
/// per-command return values.
library;

import 'dart:typed_data';

import 'package:sui/builder/transaction_block_data.dart'
    show TransactionBlockDataBuilder;
import 'package:sui/grpc/grpc_transaction_mapper.dart'
    show transactionDataToGrpcTransaction;
import 'package:sui/grpc/proto/sui/rpc/v2/transaction_execution_service.pb.dart'
    show CommandResult;
import 'package:sui/sui.dart'
    show BuildOptions, GrpcBuilderAdapter, GrpcCoreClient, Transaction;

import '../config.dart';
import '../errors.dart';

class QueryContext {
  final GrpcCoreClient core;
  final DeepBookConfig config;

  QueryContext({required this.core, required this.config});

  String get address => config.address;

  /// Simulates a read-only [tx] and returns the per-command results.
  ///
  /// The transaction's object inputs are resolved through gRPC, gas is left
  /// unset (the server mocks a gas coin), and `command_outputs` is requested —
  /// mirroring the official `core.simulateTransaction({include:
  /// {commandResults: true, effects: true}})`.
  Future<List<CommandResult>> simulate(Transaction tx) async {
    tx.setSenderIfNotSet(config.address);
    await tx.build(BuildOptions(
      client: GrpcBuilderAdapter(core),
      onlyTransactionKind: true,
    ));
    final grpcTx = transactionDataToGrpcTransaction(
      TransactionBlockDataBuilder(tx.getData()),
      includeGas: false,
    );
    final res = await core.simulateStructured(
      grpcTx,
      doGasSelection: false,
      readMask: const ['transaction.effects.status', 'command_outputs'],
    );
    final status = res.transaction.effects.status;
    if (!status.success) {
      throw DeepBookError('Transaction failed: ${status.error.description}');
    }
    return res.commandOutputs;
  }

  /// Convenience: simulate and return the BCS bytes of return value
  /// [returnIndex] of command [commandIndex].
  Future<Uint8List> simulateReturn(Transaction tx,
      {int commandIndex = 0, int returnIndex = 0}) async {
    final results = await simulate(tx);
    if (commandIndex >= results.length ||
        returnIndex >= results[commandIndex].returnValues.length) {
      throw DeepBookError('No return value at '
          'command $commandIndex, index $returnIndex');
    }
    return Uint8List.fromList(
        results[commandIndex].returnValues[returnIndex].value.value);
  }
}

/// Formats a raw on-chain token amount as a decimal string, truncated to
/// [decimals] fractional digits. Mirrors the official `formatTokenAmount`.
String formatTokenAmount(BigInt rawAmount, num scalar, int decimals) {
  final scalarBigInt = BigInt.from(scalar);
  final integerPart = rawAmount ~/ scalarBigInt;
  final fractionalPart = rawAmount % scalarBigInt;

  if (fractionalPart == BigInt.zero) return integerPart.toString();

  final scalarDigits = scalar.toInt().toString().length - 1;
  final fractionalStr = fractionalPart.toString().padLeft(scalarDigits, '0');
  final truncated = fractionalStr.substring(
      0, decimals < fractionalStr.length ? decimals : fractionalStr.length);
  final trimmed = truncated.replaceFirst(RegExp(r'0+$'), '');

  if (trimmed.isEmpty) return integerPart.toString();
  return '$integerPart.$trimmed';
}
