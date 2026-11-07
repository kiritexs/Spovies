import '../../domain/entities/plugin_manifest.dart';

/// Abstract repository for plugin CRUD operations.
abstract class PluginRepository {
  /// Install a plugin by fetching its manifest from [url].
  Future<PluginManifest> install(String url);

  /// Install multiple plugins from a single [url] (registry).
  /// The URL may return a single manifest, an array of manifest URLs or inline
  /// manifests, or an object with a "plugins" array. Returns the list of
  /// manifests that were installed (skips already-installed).
  Future<List<PluginManifest>> installFromRegistry(String url);

  /// Uninstall a plugin by its [pluginId].
  Future<void> uninstall(String pluginId);

  /// Get all currently installed plugin manifests.
  Future<List<PluginManifest>> getInstalled();
}
