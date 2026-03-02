import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/hive_service.dart';

// ─── Theme Mode ─────────────────────────────────────────────────────────

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = HiveService.settingsBox.get('themeMode') as String?;
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await HiveService.settingsBox.put('themeMode', mode.name);
  }
}

/// Persisted theme mode provider.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// ─── Preferred Plugin ───────────────────────────────────────────────────

class PreferredPluginNotifier extends Notifier<String?> {
  @override
  String? build() {
    return HiveService.settingsBox.get('preferredPlugin') as String?;
  }

  Future<void> set(String? pluginId) async {
    state = pluginId;
    if (pluginId == null) {
      await HiveService.settingsBox.delete('preferredPlugin');
    } else {
      await HiveService.settingsBox.put('preferredPlugin', pluginId);
    }
  }
}

/// The user's preferred streaming plugin (null = "Auto" = first available).
final preferredPluginProvider =
    NotifierProvider<PreferredPluginNotifier, String?>(
      PreferredPluginNotifier.new,
    );
