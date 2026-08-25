/// DeepBook error types, mirroring the official SDK's `utils/errors.ts`.
library;

/// Base class for DeepBook errors.
class DeepBookError implements Exception {
  final String message;
  DeepBookError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a configured resource (coin, pool, manager) is not found.
class ResourceNotFoundError extends DeepBookError {
  ResourceNotFoundError(String resourceType, String key)
      : super('$resourceType not found for key: $key');
}

/// Thrown when configuration is invalid or missing.
class ConfigurationError extends DeepBookError {
  ConfigurationError(super.message);
}

/// Thrown when transaction validation fails.
class ValidationError extends DeepBookError {
  ValidationError(super.message);
}

/// Standard error messages, aligned with the official SDK.
abstract final class ErrorMessages {
  static const adminCapNotSet = 'Admin capability not configured';
  static const marginAdminCapNotSet = 'Margin admin capability not configured';
  static const marginMaintainerCapNotSet =
      'Margin maintainer capability not configured';

  static String coinNotFound(String key) => 'Coin not found for key: $key';
  static String poolNotFound(String key) => 'Pool not found for key: $key';
  static String marginPoolNotFound(String key) =>
      'Margin pool not found for key: $key';
  static String balanceManagerNotFound(String key) =>
      'Balance manager with key $key not found';
  static String marginManagerNotFound(String key) =>
      'Margin manager with key $key not found';
  static String priceInfoNotFound(String coinKey) =>
      'Price info object not found for $coinKey';
}
