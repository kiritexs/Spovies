import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  // Add logging for plugin discovery debugging
  dio.interceptors.add(
    LogInterceptor(
      requestHeader: false,
      responseHeader: false,
      responseBody: true,
    ),
  );

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

// ─── Data Providers ─────────────────────────────────────────────────────

/// All installed plugin manifests.
///
/// This is a FutureProvider so it auto-refreshes when invalidated.
final installedPluginsProvider = FutureProvider<List<PluginManifest>>((
  ref,
) async {
  final repo = ref.watch(pluginRepositoryProvider);
  return repo.getInstalled();
});

/// Plugins that support a given [TriggerHook].
final pluginsForHookProvider =
    FutureProvider.family<List<PluginManifest>, TriggerHook>((ref, hook) async {
      final repo = ref.watch(pluginRepositoryProvider);
      return repo.getForHook(hook);
    });

// ─── Install / Uninstall Notifier ───────────────────────────────────────

/// Manages plugin install and uninstall with loading states.
///
/// After a successful install/uninstall, it invalidates [installedPluginsProvider]
/// so the list auto-refreshes.
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
