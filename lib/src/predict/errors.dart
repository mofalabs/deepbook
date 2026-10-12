/// Typed errors for the Predict SDK, mirroring the official `predict/errors.ts`.
///
/// Two failure kinds cross the SDK boundary:
///  - [PredictInputError] — a caller gave us something we rejected before
///    touching the chain (unknown underlying, malformed argument, …).
///  - [PredictMoveError] — a Move `abort` surfaced by a read/simulate. The
///    deployed Predict packages are compiled with clever errors, so the
///    fullnode decodes the `E…` error-constant name out of the abort code's
///    high bits and returns it on the structured execution error. We read
///    that name straight from chain instead of maintaining a
///    module→code→name table that goes stale on every redeploy.
library;

import 'package:sui/grpc/proto/sui/rpc/v2/execution_status.pb.dart'
    show ExecutionError;

/// A caller-supplied argument the SDK rejected before building/sending a tx.
class PredictInputError implements Exception {
  final String message;
  PredictInputError(this.message);

  @override
  String toString() => 'PredictInputError: $message';
}

/// A Move `abort` decoded from a simulate/read failure.
class PredictMoveError implements Exception {
  /// The aborting module's short name.
  final String module;

  /// Exact u64 abort code — [BigInt] because clever-error encodings pack data
  /// into the high bits, which an `int` cast could misrepresent.
  final BigInt code;

  /// The `E…` constant name, decoded from the clever-error abort code by the
  /// fullnode, or null when the transport surfaced no name (a non-clever
  /// abort).
  final String? abortName;

  PredictMoveError(this.module, this.code, this.abortName);

  @override
  String toString() => abortName != null
      ? 'PredictMoveError: Move abort in $module: $abortName (code $code)'
      : 'PredictMoveError: Move abort in $module: code $code';
}

/// Decode a gRPC [ExecutionError] into a [PredictMoveError].
///
/// Returns null when [error] carries no Move abort (insufficient gas, a size
/// error, any non-abort failure), so callers can fall back to a plain error
/// with the failure description. The field provenance mirrors the official
/// decoder: `abort.abortCode` (u64, read unsigned), `abort.location.module`,
/// and `abort.cleverError.constantName` — the chain-decoded clever-error
/// constant that replaces the old hand-maintained abort tables.
PredictMoveError? decodeMoveAbort(ExecutionError? error) {
  if (error == null || !error.hasAbort()) return null;
  final abort = error.abort;
  final module = abort.hasLocation() ? abort.location.module : '';
  final code = BigInt.parse(abort.abortCode.toStringUnsigned());
  final abortName =
      abort.hasCleverError() && abort.cleverError.constantName.isNotEmpty
          ? abort.cleverError.constantName
          : null;
  return PredictMoveError(module, code, abortName);
}
