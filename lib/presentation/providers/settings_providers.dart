import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/hive_service.dart';

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
