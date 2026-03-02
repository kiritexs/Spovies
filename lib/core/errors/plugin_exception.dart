/// Base class for plugin-specific exceptions.
sealed class PluginException implements Exception {
  final String message;
  const PluginException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a plugin manifest fails schema validation.
class InvalidManifestException extends PluginException {
  const InvalidManifestException(super.message);
}

/// Thrown when a plugin manifest cannot be fetched.
class PluginNetworkException extends PluginException {
  final int? statusCode;
  const PluginNetworkException(super.message, {this.statusCode});
}

/// Thrown when a plugin URL fails validation.
class PluginUrlValidationException extends PluginException {
  const PluginUrlValidationException(super.message);
}

/// Thrown when a plugin is already installed.
class PluginAlreadyInstalledException extends PluginException {
  const PluginAlreadyInstalledException(super.message);
}
