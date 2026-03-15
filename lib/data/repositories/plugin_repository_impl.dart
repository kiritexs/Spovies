import 'package:flutter/foundation.dart';

import '../../core/errors/plugin_exception.dart';
import '../../domain/entities/plugin_manifest.dart';
import '../../domain/repositories/plugin_repository.dart';
import '../../plugins/discovery/plugin_discovery_service.dart';
import '../../plugins/protocol/trigger_hook.dart';
import '../datasources/local/hive_service.dart';
import '../models/plugin_manifest_model.dart';

/// Concrete implementation of [PluginRepository].
///
/// Uses [PluginDiscoveryService] to fetch & validate manifests,
/// and Hive's `pluginsBox` for local persistence.
class PluginRepositoryImpl implements PluginRepository {
  final PluginDiscoveryService _discoveryService;

  PluginRepositoryImpl(this._discoveryService);

  @override
  Future<PluginManifest> install(String url) async {
    // 1. Fetch and validate manifest from URL
    final manifest = await _discoveryService.fetchAndValidate(url);

    // 2. Check if already installed
    if (HiveService.pluginsBox.containsKey(manifest.pluginId)) {
      throw PluginAlreadyInstalledException(
        '${manifest.name} is already installed',
      );
    }

    // 3. Persist to Hive
    final json = PluginManifestModel.toJson(manifest);
    await HiveService.pluginsBox.put(manifest.pluginId, json);

    return manifest;
  }

  @override
  Future<List<PluginManifest>> installFromRegistry(String url) async {
    final manifests = await _discoveryService.fetchRegistry(url);
    final installed = <PluginManifest>[];
    for (final manifest in manifests) {
      if (HiveService.pluginsBox.containsKey(manifest.pluginId)) continue;
      final json = PluginManifestModel.toJson(manifest);
      await HiveService.pluginsBox.put(manifest.pluginId, json);
      installed.add(manifest);
    }
    return installed;
  }

  @override
  Future<void> uninstall(String pluginId) async {
    await HiveService.pluginsBox.delete(pluginId);
  }

  @override
  Future<List<PluginManifest>> getInstalled() async {
    final manifests = <PluginManifest>[];
    for (final entry in HiveService.pluginsBox.values) {
      try {
        final map = Map<String, dynamic>.from(entry);
        manifests.add(PluginManifestModel.fromJson(map));
      } catch (e) {
        // Log corruption so we can debug "show nothing" issues
        debugPrint('Error parsing plugin manifest from Hive: $e');
      }
    }
    return manifests;
  }

  @override
  Future<List<PluginManifest>> getForHook(TriggerHook hook) async {
    final installed = await getInstalled();
    return installed.where((p) => p.hooks.contains(hook)).toList();
  }
}
