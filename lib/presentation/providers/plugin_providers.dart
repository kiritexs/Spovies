import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/hive_service.dart';
import '../../data/repositories/plugin_repository_impl.dart';
import '../../domain/entities/plugin_manifest.dart';
import '../../domain/repositories/plugin_repository.dart';
import '../../plugins/discovery/plugin_discovery_service.dart';
import '../../plugins/protocol/trigger_hook.dart';

// ─── Infrastructure ─────────────────────────────────────────────────────

/// Dio instance for plugin manifest fetches (no TMDB auth headers).
final _pluginDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'accept': 'application/json'},
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestHeader: false,
        responseHeader: false,
        responseBody: true,
      ),
    );
  }
  return dio;
});

/// Plugin discovery service.
final pluginDiscoveryProvider = Provider<PluginDiscoveryService>((ref) {
  return PluginDiscoveryService(ref.watch(_pluginDioProvider));
});

/// Plugin repository.
final pluginRepositoryProvider = Provider<PluginRepository>((ref) {
  return PluginRepositoryImpl(ref.watch(pluginDiscoveryProvider));
});

// ─── Enable / Disable ────────────────────────────────────────────────────

/// Notifier that persists per-plugin enabled/disabled state in [HiveService.settingsBox].
///
/// State is a `Map<pluginId, isEnabled>`. Missing keys are treated as enabled.
class PluginEnabledNotifier extends Notifier<Map<String, bool>> {
  static const _prefix = 'plugin_enabled:';

  @override
  Map<String, bool> build() {
    // Read every matching key from the settings box on startup
    final box = HiveService.settingsBox;
    final map = <String, bool>{};
    for (final key in box.keys) {
      if (key is String && key.startsWith(_prefix)) {
        final id = key.substring(_prefix.length);
        map[id] = box.get(key) as bool? ?? true;
      }
    }
    return map;
  }

  /// Returns `true` if the plugin is enabled (default: enabled).
  bool isEnabled(String pluginId) => state[pluginId] ?? true;

  /// Toggle and persist a plugin's enabled state.
  void toggle(String pluginId) {
    final next = !(state[pluginId] ?? true);
    unawaited(HiveService.settingsBox.put('$_prefix$pluginId', next));
    state = {...state, pluginId: next};
  }
}

final pluginEnabledProvider =
    NotifierProvider<PluginEnabledNotifier, Map<String, bool>>(
      PluginEnabledNotifier.new,
    );

// ─── Data Providers ─────────────────────────────────────────────────────

/// All installed plugin manifests.
///
/// FutureProvider so it auto-refreshes when invalidated.
final installedPluginsProvider = FutureProvider<List<PluginManifest>>((
  ref,
) async {
  final repo = ref.watch(pluginRepositoryProvider);
  return repo.getInstalled();
});

/// Plugins that support a given [TriggerHook], filtered by enabled state.
///
/// Watches [installedPluginsProvider] so it automatically re-evaluates
/// whenever a plugin is installed or uninstalled — no restart required.
final pluginsForHookProvider =
    FutureProvider.family<List<PluginManifest>, TriggerHook>((ref, hook) async {
      // Re-run when the installed list changes (install / uninstall)
      final installed = await ref.watch(installedPluginsProvider.future);
      // Filter by enabled state
      final enabledMap = ref.watch(pluginEnabledProvider);
      return installed
          .where((p) => p.hooks.contains(hook))
          .where((p) => enabledMap[p.pluginId] ?? true)
          .toList();
    });

// ─── Install / Uninstall Notifier ───────────────────────────────────────

/// Manages plugin install and uninstall with loading states.
class PluginInstallNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Install a plugin from a manifest URL.
  Future<PluginManifest> install(String url) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(pluginRepositoryProvider);
      final manifest = await repo.install(url);
      state = const AsyncData(null);
      ref.invalidate(installedPluginsProvider);
      return manifest;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Install one or more plugins from a single URL (registry).
  /// The URL may return a single manifest, an array of manifest URLs or inline
  /// manifests, or an object with a "plugins" array.
  Future<List<PluginManifest>> installFromRegistry(String url) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(pluginRepositoryProvider);
      final installed = await repo.installFromRegistry(url);
      state = const AsyncData(null);
      ref.invalidate(installedPluginsProvider);
      return installed;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Uninstall a plugin by its ID.
  Future<void> uninstall(String pluginId) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(pluginRepositoryProvider);
      await repo.uninstall(pluginId);
      state = const AsyncData(null);
      ref.invalidate(installedPluginsProvider);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final pluginInstallProvider =
    AsyncNotifierProvider<PluginInstallNotifier, void>(
      PluginInstallNotifier.new,
    );
