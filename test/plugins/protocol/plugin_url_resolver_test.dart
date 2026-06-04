// Unit tests for PluginUrlResolver — the centralised plugin selection and
// URL templating logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:spovies/domain/entities/media_item.dart';
import 'package:spovies/domain/entities/media_metadata.dart';
import 'package:spovies/domain/entities/media_type.dart';
import 'package:spovies/domain/entities/plugin_manifest.dart';
import 'package:spovies/plugins/protocol/action_type.dart';
import 'package:spovies/plugins/protocol/plugin_url_resolver.dart';
import 'package:spovies/plugins/protocol/trigger_hook.dart';

PluginManifest _plugin(String id, {String? template}) {
  return PluginManifest(
    pluginId: id,
    version: '1.0.0',
    name: id,
    description: '',
    hooks: const [TriggerHook.mediaHeader],
    urlTemplate: template ?? 'https://embed.example/$id/{{tmdbId}}',
    actionType: ActionType.webview,
  );
}

MediaItem _movie({int tmdbId = 42, String title = 'The Thing'}) {
  return MediaItem(
    id: '$tmdbId',
    tmdbId: tmdbId,
    type: MediaType.movie,
    title: title,
  );
}

MediaItem _tv({int tmdbId = 7, String title = 'Show'}) {
  return MediaItem(
    id: '$tmdbId',
    tmdbId: tmdbId,
    type: MediaType.tv,
    title: title,
    metadata: const MediaMetadata(imdbId: 'tt1234567'),
  );
}

void main() {
  group('PluginUrlResolver.pickPlugin', () {
    test('returns null when the plugin list is empty', () {
      expect(PluginUrlResolver.pickPlugin(const []), isNull);
    });

    test('savedId beats preferredId beats the first plugin', () {
      final plugins = [_plugin('a'), _plugin('b'), _plugin('c')];
      // savedId wins outright
      expect(
        PluginUrlResolver.pickPlugin(
          plugins,
          savedId: 'c',
          preferredId: 'b',
        )?.pluginId,
        'c',
      );
      // preferredId used when savedId is missing
      expect(
        PluginUrlResolver.pickPlugin(plugins, preferredId: 'b')?.pluginId,
        'b',
      );
      // falls back to first when neither matches
      expect(
        PluginUrlResolver.pickPlugin(
          plugins,
          savedId: 'x',
          preferredId: 'y',
        )?.pluginId,
        'a',
      );
    });
  });

  group('PluginUrlResolver.resolve', () {
    test('substitutes movie placeholders', () {
      final url = PluginUrlResolver.resolve(
        _plugin('mov', template: 'https://e.example/{{type}}/{{tmdbId}}'),
        _movie(),
      );
      expect(url, 'https://e.example/movie/42');
    });

    test(
      'appends /season/episode for TV when template has no placeholders',
      () {
        final url = PluginUrlResolver.resolve(
          _plugin('tv', template: 'https://e.example/embed/{{tmdbId}}?c=red'),
          _tv(),
          season: 2,
          episode: 5,
        );
        // The resolver should insert /2/5 *before* the query string.
        expect(url, 'https://e.example/embed/7/2/5?c=red');
      },
    );

    test('strips season/episode placeholders for movies', () {
      final url = PluginUrlResolver.resolve(
        _plugin(
          'mov',
          template: 'https://e.example/m/{{tmdbId}}{{/season}}{{/episode}}',
        ),
        _movie(),
      );
      expect(url, 'https://e.example/m/42');
    });

    test('TV defaults to S1E1 when no season/episode given', () {
      final url = PluginUrlResolver.resolve(
        _plugin('tv', template: 'https://e.example/tv/{{tmdbId}}'),
        _tv(),
      );
      expect(url, 'https://e.example/tv/7/1/1');
    });

    test('uri-encodes the title placeholder', () {
      final url = PluginUrlResolver.resolve(
        _plugin('s', template: 'https://e.example/q?t={{title}}'),
        _movie(title: 'Hot & Cold'),
      );
      expect(url, contains('Hot%20%26%20Cold'));
    });
  });
}
