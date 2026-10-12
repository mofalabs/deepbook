/// Runtime support for the generated Move bindings under `lib/src/contracts/`.
///
/// Mirrors the official `@mysten/deepbook-v3` codegen runtime
/// (`src/contracts/utils/index.ts`): pure-vs-object argument normalization
/// driven by the Move type strings embedded in each generated builder.
library;

import 'dart:typed_data';

import 'package:bcs/bcs.dart';
import 'package:sui/bcs/sui_bcs.dart';
import 'package:sui/bcs/type_tag_serializer.dart';
import 'package:sui/sui.dart' show Transaction, TransactionResult;
import 'package:sui/types/common.dart' show normalizeSuiAddress;

/// A generated move-call builder: apply it to a [Transaction] to append the
/// call and get its result handle (usable as an argument to later commands).
typedef MoveCallBuilder = TransactionResult Function(Transaction tx);

const _stdAddress =
    '0x0000000000000000000000000000000000000000000000000000000000000001';
const _frameworkAddress =
    '0x0000000000000000000000000000000000000000000000000000000000000002';

/// Returns the BCS schema for a Move type that can be passed as a pure
/// argument, or `null` when the type is an object (or otherwise not pure).
BcsType<dynamic, dynamic>? getPureBcsSchema(String typeTag) {
  final parsed = TypeTagSerializer.parseFromStr(typeTag);
  return _pureSchemaFromParsed(parsed);
}

BcsType<dynamic, dynamic>? _pureSchemaFromParsed(dynamic parsed) {
  if (parsed is! Map) return null;
  if (parsed.containsKey('u8')) return SuiBcs.U8;
  if (parsed.containsKey('u16')) return SuiBcs.U16;
  if (parsed.containsKey('u32')) return SuiBcs.U32;
  if (parsed.containsKey('u64')) return SuiBcs.U64;
  if (parsed.containsKey('u128')) return SuiBcs.U128;
  if (parsed.containsKey('u256')) return SuiBcs.U256;
  if (parsed.containsKey('address')) return SuiBcs.Address;
  if (parsed.containsKey('bool')) return SuiBcs.BOOL;
  if (parsed.containsKey('vector')) {
    final inner = _pureSchemaFromParsed(parsed['vector']);
    return inner == null ? null : Bcs.vector(inner);
  }
  if (parsed.containsKey('struct')) {
    final struct = parsed['struct'] as Map;
    final pkg = normalizeSuiAddress(struct['address'] as String);
    final module = struct['module'] as String;
    final name = struct['name'] as String;
    if (pkg == _stdAddress) {
      if ((module == 'ascii' || module == 'string') && name == 'String') {
        return SuiBcs.STRING;
      }
      if (module == 'option' && name == 'Option') {
        final typeParams = struct['typeParams'] as List;
        if (typeParams.isEmpty) return null;
        final inner = _pureSchemaFromParsed(typeParams[0]);
        return inner == null ? null : Bcs.option(inner);
      }
    }
    if (pkg == _frameworkAddress &&
        module == 'object' &&
        (name == 'ID' || name == 'UID')) {
      return SuiBcs.Address;
    }
  }
  return null;
}

bool _isArgument(dynamic value) =>
    value is Map &&
    const ['Input', 'Result', 'NestedResult', 'GasCoin']
        .contains(value['\$kind']);

/// Well-known singleton shared objects addressable by bare id.
const _wellKnownObjects = {
  '0x2::clock::Clock': '0x6',
  '0x2::random::Random': '0x8',
  '0x2::deny_list::DenyList': '0x403',
  '0x2::accumulator::AccumulatorRoot': '0xacc',
  '0x3::sui_system::SuiSystemState': '0x5',
};

/// Fills named [arguments] (a `Map`, or null for none) with values from
/// [config] for the parameters listed in [defaults] (`param → config key`).
/// Mirrors the generated `{ ...options.arguments, x: options.arguments?.x ??
/// options.config?.y }` merge of the config-mapped builders.
Map<String, dynamic> withConfigDefaults(
  dynamic arguments,
  Map<String, dynamic>? config,
  Map<String, String> defaults,
) {
  if (arguments != null && arguments is! Map) {
    throw ArgumentError(
        'Expected named (Map) arguments for a config-mapped builder');
  }
  final merged = arguments == null
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(arguments as Map);
  for (final entry in defaults.entries) {
    if (merged[entry.key] != null) continue;
    final value = config?[entry.value];
    if (value != null) {
      merged[entry.key] = value;
    } else {
      merged.remove(entry.key);
      throw ArgumentError('Parameter ${entry.key} is required '
          '(pass it in arguments or provide config.${entry.value})');
    }
  }
  return merged;
}

/// Normalizes named (`Map`) or positional (`List`) arguments into transaction
/// arguments, serializing pure values by their Move type and passing object
/// ids through `tx.object`. Mirrors the official `normalizeMoveArguments`.
List<dynamic> normalizeMoveArguments(
  Transaction tx,
  dynamic args,
  List<String?> argTypes, [
  List<String>? parameterNames,
]) {
  final int argLen =
      args is List ? args.length : (args as Map<String, dynamic>).length;
  final int expected =
      argTypes.where((t) => !_wellKnownObjects.containsKey(t)).length;
  if (argLen != expected) {
    throw ArgumentError(
        'Invalid number of arguments, expected $expected, got $argLen');
  }

  final normalized = <dynamic>[];
  var index = 0;
  for (final argType in argTypes) {
    final wellKnown = _wellKnownObjects[argType];
    if (wellKnown != null) {
      normalized.add(tx.object(wellKnown));
      continue;
    }

    dynamic arg;
    if (args is List) {
      arg = args[index];
    } else {
      if (parameterNames == null) {
        throw ArgumentError('Expected arguments to be passed as a List');
      }
      final name = parameterNames[index];
      arg = (args as Map<String, dynamic>)[name];
      if (arg == null && !args.containsKey(name)) {
        throw ArgumentError('Parameter $name is required');
      }
    }
    index += 1;

    if (arg is Function) {
      normalized.add(arg(tx));
      continue;
    }
    if (arg is TransactionResult || _isArgument(arg)) {
      normalized.add(arg);
      continue;
    }

    final schema = argType == null ? null : getPureBcsSchema(argType);
    if (schema != null) {
      final SerializedBcs bytes = schema.serialize(arg);
      normalized.add(tx.pure(bytes));
      continue;
    }

    if (arg is String) {
      normalized.add(tx.object(arg));
      continue;
    }
    if (arg is Map) {
      // Fully-resolved object reference (Inputs.objectRef / sharedObjectRef).
      normalized.add(tx.object(arg));
      continue;
    }

    throw ArgumentError('Invalid argument $arg for type $argType');
  }
  return normalized;
}

/// Builds the full Move type tag for a (possibly generic) struct [name],
/// optionally re-homing it to [package] and filling [typeArguments].
/// Mirrors the official `MoveStruct.typeTag`.
String buildMoveTypeTag(
  String name, {
  String? package,
  List<Object>? typeArguments,
}) {
  final lt = name.indexOf('<');
  final base = lt == -1 ? name : name.substring(0, lt);
  if (base.split('::').length != 3) {
    throw ArgumentError('$name is not a top-level Move type');
  }

  var result = name;
  if (typeArguments != null) {
    final baked = lt == -1
        ? const <String>[]
        : _splitTopLevelTypeArgs(name.substring(lt + 1, name.length - 1));
    final supplied = typeArguments.map((arg) {
      if (arg is String) return arg;
      if (arg is BcsType) return arg.name;
      throw ArgumentError('Invalid type argument $arg');
    }).toList();
    if (supplied.length != baked.length) {
      throw ArgumentError('Expected ${baked.length} type arguments for $base, '
          'got ${supplied.length}');
    }
    result = supplied.isEmpty ? base : '$base<${supplied.join(', ')}>';
  }

  final hasPhantom = RegExp(r'phantom [A-Za-z_$][A-Za-z0-9_$]*');
  if (hasPhantom.hasMatch(result)) {
    throw ArgumentError(typeArguments != null
        ? 'A type argument contains an unfilled phantom parameter in $result'
        : 'Missing type arguments for $result');
  }

  if (package != null) {
    final parts = result.split('::');
    result = ([package, ...parts.sublist(1)]).join('::');
  }

  // Fully validate address-only tags (MVR names can't be parsed as type tags).
  if (!hasPhantom.hasMatch(result) && !RegExp(r'[@/]').hasMatch(result)) {
    TypeTagSerializer.parseFromStr(result);
  }
  return result;
}

/// Splits `A, B<C, D>, E` on top-level commas only.
List<String> _splitTopLevelTypeArgs(String src) {
  final parts = <String>[];
  var depth = 0;
  final current = StringBuffer();
  for (final char in src.split('')) {
    if (char == ',' && depth == 0) {
      parts.add(current.toString().trim());
      current.clear();
      continue;
    }
    if (char == '<') depth++;
    if (char == '>') depth--;
    current.write(char);
  }
  if (current.isNotEmpty) parts.add(current.toString().trim());
  return parts;
}

/// Parses BCS [bytes] with [schema]; convenience for query-layer code reading
/// `simulateTransaction` command return values.
T parseBcs<T>(BcsType<T, dynamic> schema, Uint8List bytes) =>
    schema.parse(bytes);
