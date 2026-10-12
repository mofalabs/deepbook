/// The one network seam every Predict read sits on, mirroring
/// `predict/reads/inspect.ts`: run a read-only PTB through the gRPC
/// `simulateTransaction` (the devInspect replacement).
library;

import 'dart:typed_data';

import 'package:sui/builder/transaction_block_data.dart'
    show TransactionBlockDataBuilder;
import 'package:sui/grpc/grpc_transaction_mapper.dart'
    show transactionDataToGrpcTransaction;
import 'package:sui/grpc/proto/sui/rpc/v2/event.pb.dart' as pb show Event;
import 'package:sui/grpc/proto/sui/rpc/v2/transaction_execution_service.pb.dart'
    show SimulateTransactionResponse;
import 'package:sui/sui.dart'
    show BuildOptions, GrpcBuilderAdapter, GrpcCoreClient, Transaction;
import 'package:sui/types/common.dart' show normalizeSuiAddress;

import '../errors.dart';

/// The Sui client surface Predict reads through. The Dart SDK's core client
/// is the gRPC one; it provides both the `simulateTransaction` the
/// reads/quotes sit on and the object reads position enumeration needs.
typedef ReadClient = GrpcCoreClient;

Never _throwSimFailure(SimulateTransactionResponse res) {
  final status = res.transaction.effects.status;
  final error = status.hasError() ? status.error : null;
  final decoded = decodeMoveAbort(error);
  if (decoded != null) throw decoded;
  throw Exception(error != null && error.description.isNotEmpty
      ? error.description
      : 'simulateTransaction aborted (FailedTransaction)');
}

Future<SimulateTransactionResponse> _simulate(
  ReadClient client,
  Transaction tx,
  List<String> readMask,
) async {
  await tx.build(BuildOptions(
    client: GrpcBuilderAdapter(client),
    onlyTransactionKind: true,
  ));
  final grpcTx = transactionDataToGrpcTransaction(
    TransactionBlockDataBuilder(tx.getData()),
    includeGas: false,
  );
  // checks are left ENABLED-equivalent off: simulate with checks disabled so
  // non-entry public funs may be inspected, exactly like the official
  // `checksEnabled: false`.
  final res = await client.simulateStructured(
    grpcTx,
    doGasSelection: false,
    checksEnabled: false,
    readMask: readMask,
  );
  if (!res.transaction.effects.status.success) _throwSimFailure(res);
  return res;
}

/// Simulate a full transaction (typically one built by a `tx.*` builder) and
/// return the events it would emit — the quote path: dry-run the real action,
/// decode the receipt. [sender] must be the acting owner so account auth
/// resolves. Throws the same typed errors the real execution would surface.
Future<List<pb.Event>> simulateWithEvents(
  ReadClient client,
  Transaction tx,
  String sender,
) async {
  tx.setSender(sender);
  final res = await _simulate(
      client, tx, const ['transaction.effects.status', 'transaction.events']);
  return res.transaction.events.events;
}

/// Simulate a read-only PTB and return each command's BCS return values,
/// indexed `[commandIndex][returnValueIndex]`. A sender is required to
/// simulate; callers rarely have one for a pure read, so the zero address is
/// the default.
Future<List<List<Uint8List>>> inspectReturns(
  ReadClient client,
  Transaction tx, {
  String? sender,
}) async {
  tx.setSender(sender ?? normalizeSuiAddress('0x0'));
  final res = await _simulate(
      client, tx, const ['transaction.effects.status', 'command_outputs']);
  final commands = res.commandOutputs;
  if (commands.isEmpty) {
    throw PredictInputError('simulateTransaction returned no commandResults');
  }
  return [
    for (final c in commands)
      [for (final rv in c.returnValues) Uint8List.fromList(rv.value.value)]
  ];
}
