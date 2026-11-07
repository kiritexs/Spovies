// PluginManifestModel.fromJson is the single gate for every manifest
// source (remote install, Hive reload, backup import), so its validation
// and defaults are locked in here.

import 'package:flutter_test/flutter_test.dart';

import 'package:spovies/data/models/plugin_manifest_model.dart';
import 'package:spovies/plugins/protocol/action_type.dart';
import 'package:spovies/plugins/protocol/trigger_hook.dart';

void main() {
  Map<String, dynamic> minimal() => {
    'pluginId': 'example',
    'name': 'Example',
    'urlTemplate': 'https://example.com/{{type}}/{{tmdbId}}',
  };

  test('applies defaults to a minimal manifest', () {
    final m = PluginManifestModel.fromJson(minimal());

    expect(m.pluginId, 'example');
    expect(m.version, '1.0.0');
    expect(m.description, '');
    expect(m.hooks, [TriggerHook.mediaHeader]);
    expect(m.actionType, ActionType.webview);
    expect(m.presentationMode, PresentationMode.fullscreen);
    expect(m.eventBridgeConfig, isNull);
  });

  test('parses hooks, action type and event bridge', () {
    final m = PluginManifestModel.fromJson({
      ...minimal(),
      'hooks': ['media_header', 'episode_item'],
      'actionType': 'externalLink',
      'presentationMode': 'popover',
      'eventBridgeConfig': {
        'postMessageOrigin': 'https://player.example.com',
        'allowedEventTypes': ['progress'],
      },
    });

    expect(m.hooks, [TriggerHook.mediaHeader, TriggerHook.episodeItem]);
    expect(m.actionType, ActionType.externalLink);
    expect(m.presentationMode, PresentationMode.popover);
    expect(
      m.eventBridgeConfig?.postMessageOrigin,
      'https://player.example.com',
    );
    expect(m.eventBridgeConfig?.allowedEventTypes, ['progress']);
  });

  group('rejects', () {
    for (final field in ['pluginId', 'name', 'urlTemplate']) {
      test('a missing or blank $field', () {
        expect(
          () => PluginManifestModel.fromJson(minimal()..remove(field)),
          throwsFormatException,
        );
        expect(
          () => PluginManifestModel.fromJson(minimal()..[field] = '  '),
          throwsFormatException,
        );
      });
    }

    for (final template in [
      'javascript:alert(1)',
      'intent://scan/#Intent;end',
      'content://x',
      'file:///etc/passwd',
    ]) {
      test('a non-http urlTemplate ($template)', () {
        expect(
          () => PluginManifestModel.fromJson(
            minimal()..['urlTemplate'] = template,
          ),
          throwsFormatException,
        );
      });
    }

    test('an unknown actionType', () {
      expect(
        () => PluginManifestModel.fromJson(minimal()..['actionType'] = 'eval'),
        throwsFormatException,
      );
    });
  });

  test('toJson round-trips through fromJson', () {
    final original = PluginManifestModel.fromJson({
      ...minimal(),
      'hooks': ['episode_item'],
      'presentationMode': 'popover',
      'eventBridgeConfig': {'postMessageOrigin': '*'},
    });
    final again = PluginManifestModel.fromJson(
      PluginManifestModel.toJson(original),
    );

    expect(again.pluginId, original.pluginId);
    expect(again.hooks, original.hooks);
    expect(again.presentationMode, original.presentationMode);
    expect(
      again.eventBridgeConfig?.allowedEventTypes,
      original.eventBridgeConfig?.allowedEventTypes,
    );
  });
}
