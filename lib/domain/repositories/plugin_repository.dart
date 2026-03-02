import '../../domain/entities/plugin_manifest.dart';
import '../../plugins/protocol/trigger_hook.dart';

/// Abstract repository for plugin CRUD operations.
abstract class PluginRepository {
  /// Install a plugin by fetching its manifest from [url].
  Future<PluginManifest> install(String url);

  /// Uninstall a plugin by its [pluginId].
  Future<void> uninstall(String pluginId);

  /// Get all currently installed plugin manifests.
  Future<List<PluginManifest>> getInstalled();

  /// Get plugins that support a specific [hook].
  Future<List<PluginManifest>> getForHook(TriggerHook hook);
}
