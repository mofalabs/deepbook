/// Input validation helpers, mirroring the official SDK's
/// `utils/validation.ts`.
library;

import 'package:sui/types/common.dart' show normalizeSuiAddress;

import 'errors.dart';

/// Validates that a required configuration [value] is set.
T validateRequired<T>(T? value, String errorMessage) {
  if (value == null) throw ConfigurationError(errorMessage);
  return value;
}

final _addressRegex = RegExp(r'^0x[0-9a-fA-F]{1,64}$');

/// Validates that [address] is a valid Sui address and returns it normalized.
String validateAddress(String address, [String fieldName = 'Address']) {
  if (!_addressRegex.hasMatch(address)) {
    throw ValidationError('$fieldName must be a valid Sui address');
  }
  return normalizeSuiAddress(address);
}

/// Validates that [value] is positive.
num validatePositiveNumber(num value, String fieldName) {
  if (value <= 0) {
    throw ValidationError('$fieldName must be a positive number');
  }
  return value;
}

/// Validates that [value] is non-negative.
num validateNonNegativeNumber(num value, String fieldName) {
  if (value < 0) {
    throw ValidationError('$fieldName must be non-negative');
  }
  return value;
}

/// Validates that [value] is within `[min, max]` (inclusive).
num validateRange(num value, num min, num max, String fieldName) {
  if (value < min || value > max) {
    throw ValidationError('$fieldName must be between $min and $max');
  }
  return value;
}

/// Validates that [array] is non-empty.
List<T> validateNonEmptyArray<T>(List<T> array, String fieldName) {
  if (array.isEmpty) throw ValidationError('$fieldName cannot be empty');
  return array;
}
