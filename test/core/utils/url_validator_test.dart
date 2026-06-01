// Unit tests for UrlValidator — the security boundary on plugin URLs.

import 'package:flutter_test/flutter_test.dart';
import 'package:spovies/core/utils/url_validator.dart';

void main() {
  group('validate (manifest URL)', () {
    test('accepts a normal HTTPS URL', () {
      expect(UrlValidator.validate('https://example.com/plugin.json'), isNull);
    });

    test('rejects http://', () {
      expect(
        UrlValidator.validate('http://example.com/plugin.json'),
        contains('HTTPS'),
      );
    });

    test('rejects localhost and loopback', () {
      expect(
        UrlValidator.validate('https://localhost/plugin.json'),
        contains('Localhost'),
      );
      expect(
        UrlValidator.validate('https://127.0.0.1/plugin.json'),
        contains('Localhost'),
      );
    });

    test('rejects empty / blank input', () {
      expect(UrlValidator.validate(''), isNotNull);
      expect(UrlValidator.validate('   '), isNotNull);
    });

    test('rejects malformed URLs', () {
      expect(UrlValidator.validate('not a url'), isNotNull);
      expect(UrlValidator.validate('https://'), isNotNull);
    });
  });

  group('validateUrlTemplate', () {
    test('accepts a normal HTTPS template with placeholders', () {
      expect(
        UrlValidator.validateUrlTemplate(
          'https://embed.example/{{tmdbId}}/{{season}}/{{episode}}',
        ),
        isNull,
      );
    });

    test('accepts http:// templates (plain HTTP is allowed by template)', () {
      // Templates may use http for legitimate embeds; the manifest URL
      // is HTTPS-only, but a plugin can target an HTTP embed page.
      expect(
        UrlValidator.validateUrlTemplate('http://embed.example/{{tmdbId}}'),
        isNull,
      );
    });

    test('rejects javascript: scheme', () {
      expect(
        UrlValidator.validateUrlTemplate('javascript:alert(1)//'),
        contains('http://'),
      );
    });

    test('rejects data: scheme', () {
      expect(
        UrlValidator.validateUrlTemplate('data:text/html,<script>x</script>'),
        contains('http://'),
      );
    });

    test('rejects file: scheme', () {
      expect(
        UrlValidator.validateUrlTemplate('file:///etc/passwd'),
        contains('http://'),
      );
    });

    test('rejects empty templates', () {
      expect(UrlValidator.validateUrlTemplate(''), isNotNull);
      expect(UrlValidator.validateUrlTemplate('   '), isNotNull);
    });

    test('rejects templates over the length cap', () {
      final big = 'https://e.example/${'a' * 4000}';
      expect(
        UrlValidator.validateUrlTemplate(big),
        contains('character limit'),
      );
    });

    test('scheme check is case-insensitive', () {
      expect(
        UrlValidator.validateUrlTemplate('HTTPS://embed.example/{{tmdbId}}'),
        isNull,
      );
      expect(
        UrlValidator.validateUrlTemplate('JavaScript:alert(1)'),
        isNotNull,
      );
    });
  });
}
