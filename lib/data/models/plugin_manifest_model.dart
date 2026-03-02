import '../../plugins/protocol/action_type.dart';
import '../../plugins/protocol/trigger_hook.dart';
import '../../domain/entities/plugin_manifest.dart';

/// Data model for parsing and serializing plugin manifests from JSON.
///
/// Handles both remote JSON fetch and Hive persistence.
class PluginManifestModel {
  /// Parse remote JSON manifest into a [PluginManifest] entity.
  static PluginManifest fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      pluginId: json['pluginId'] as String,
      version: json['version'] as String? ?? '1.0.0',
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      iconUrl: json['iconUrl'] as String?,
      hooks:
          (json['hooks'] as List<dynamic>?)
              ?.map((h) => TriggerHook.fromString(h as String))
              .toList() ??
          [TriggerHook.mediaHeader],
      urlTemplate: json['urlTemplate'] as String,
      actionType: ActionType.fromString(
        json['actionType'] as String? ?? 'webview',
      ),
      presentationMode: PresentationMode.fromString(
        json['presentationMode'] as String?,
      ),
      eventBridgeConfig: json['eventBridgeConfig'] != null
          ? _parseEventBridge(
              Map<String, dynamic>.from(json['eventBridgeConfig'] as Map),
            )
          : null,
    );
  }

  /// Serialize a [PluginManifest] entity back to JSON (for Hive caching).
  static Map<String, dynamic> toJson(PluginManifest manifest) {
    return {
      'pluginId': manifest.pluginId,
      'version': manifest.version,
      'name': manifest.name,
      'description': manifest.description,
      'iconUrl': manifest.iconUrl,
      'hooks': manifest.hooks.map((h) => h.value).toList(),
      'urlTemplate': manifest.urlTemplate,
      'actionType': manifest.actionType.value,
      'presentationMode': manifest.presentationMode == PresentationMode.popover
          ? 'popover'
          : 'fullscreen',
      if (manifest.eventBridgeConfig != null)
        'eventBridgeConfig': {
          'postMessageOrigin': manifest.eventBridgeConfig!.postMessageOrigin,
          'allowedEventTypes': manifest.eventBridgeConfig!.allowedEventTypes,
        },
    };
  }

  static EventBridgeConfig _parseEventBridge(Map<String, dynamic> json) {
    return EventBridgeConfig(
      postMessageOrigin: json['postMessageOrigin'] as String? ?? '*',
      allowedEventTypes:
          (json['allowedEventTypes'] as List<dynamic>?)?.cast<String>() ??
          const ['progress', 'pause', 'stop', 'heartbeat'],
    );
  }
}
