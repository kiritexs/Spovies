import '../../plugins/protocol/action_type.dart';
import '../../plugins/protocol/trigger_hook.dart';

/// Domain entity representing an installed plugin's manifest.
///
/// This is the validated, immutable representation of a plugin.
/// The raw JSON from a manifest URL is parsed into this via [PluginManifestModel].
class PluginManifest {
  final String pluginId;
  final String version;
  final String name;
  final String description;
  final String? iconUrl;
  final List<TriggerHook> hooks;
  final String urlTemplate;
  final ActionType actionType;
  final PresentationMode presentationMode;
  final EventBridgeConfig? eventBridgeConfig;

  const PluginManifest({
    required this.pluginId,
    required this.version,
    required this.name,
    required this.description,
    this.iconUrl,
    required this.hooks,
    required this.urlTemplate,
    required this.actionType,
    this.presentationMode = PresentationMode.fullscreen,
    this.eventBridgeConfig,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginManifest &&
          runtimeType == other.runtimeType &&
          pluginId == other.pluginId;

  @override
  int get hashCode => pluginId.hashCode;

  @override
  String toString() => 'PluginManifest($pluginId v$version)';
}

/// Configuration for the WebView ↔ App event bridge.
class EventBridgeConfig {
  final String postMessageOrigin;
  final List<String> allowedEventTypes;

  const EventBridgeConfig({
    required this.postMessageOrigin,
    this.allowedEventTypes = const ['progress', 'pause', 'stop', 'heartbeat'],
  });
}
