import '../../core/utils/url_validator.dart';
import '../../plugins/protocol/action_type.dart';
import '../../plugins/protocol/trigger_hook.dart';
import '../../domain/entities/plugin_manifest.dart';

/// Data model for parsing and serializing plugin manifests from JSON.
///
/// Handles both remote JSON fetch and Hive persistence.
class PluginManifestModel {
  /// Parse a JSON manifest into a [PluginManifest] entity.
  ///
  /// Validates schema and URL scheme **at parse time** so that every entry
  /// point — remote fetch, Hive reload, user-supplied `.spovies` import —
  /// goes through the same guard. The install path
  /// (`PluginDiscoveryService.fetchAndValidate`) ran the same checks before
  /// reaching the model; the import path
  /// (`ExportImportService._mergePlugins`) historically did not, so a hostile
  /// backup could land an `intent://` or `content://` `urlTemplate` straight
  /// into `HiveService.pluginsBox` and then into `launchUrl` /
  /// `InAppWebView.initialUrlRequest` without any validation. Pulling the
  /// validation into [fromJson] closes that gap regardless of caller.
  ///
  /// Throws [FormatException] on any schema or scheme violation.
  static PluginManifest fromJson(Map<String, dynamic> json) {
    _requireString(json, 'pluginId');
    _requireString(json, 'name');
    _requireString(json, 'urlTemplate');

    final urlTemplate = json['urlTemplate'] as String;
    final templateError = UrlValidator.validateUrlTemplate(urlTemplate);
    if (templateError != null) {
      throw FormatException(templateError);
    }

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
      urlTemplate: urlTemplate,
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

  static void _requireString(Map<String, dynamic> json, String field) {
    final v = json[field];
    if (v is! String || v.trim().isEmpty) {
      throw FormatException('Missing or empty required field: "$field"');
    }
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
