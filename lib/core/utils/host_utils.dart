import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:public_suffix/public_suffix.dart';

/// Centralised host / eTLD+1 utilities backed by the Mozilla Public Suffix
/// List.
///
/// The hand-rolled "last two dotted segments" approach used previously was
/// wrong for any multi-part TLD (`example.co.uk` → `co.uk`, breaking both
/// the cross-domain navigation guard and the ad blocklist's registered-
/// domain lookup). This wrapper delegates to [PublicSuffix] when available
/// and falls back gracefully if the PSL never loaded (e.g. asset missing
/// in a non-Flutter test context).
class HostUtils {
  HostUtils._();

  /// Path to the bundled Mozilla PSL asset. Refreshed periodically via
  /// `tool/update_psl.dart` — see assets/public_suffix_list.dat header.
  static const String _pslAssetPath = 'assets/public_suffix_list.dat';

  static bool _initialised = false;

  /// Loads the bundled PSL into [DefaultSuffixRules]. Safe to call more
  /// than once — subsequent calls are no-ops.
  ///
  /// Should be awaited in `main()` before `runApp` so the very first
  /// [registeredDomain] call (typically from a WebView navigation event)
  /// returns the correct answer instead of the fallback.
  static Future<void> init() async {
    if (_initialised) return;
    try {
      final raw = await rootBundle.loadString(_pslAssetPath);
      DefaultSuffixRules.initFromString(raw);
      _initialised = true;
    } catch (e) {
      // Asset missing or unparsable. We log once and fall back to the
      // naive "last two parts" heuristic, which is still correct for the
      // common case (single-level TLDs) and only wrong for multi-part
      // TLDs.
      if (kDebugMode) {
        debugPrint('HostUtils: PSL load failed, using fallback. ($e)');
      }
    }
  }

  /// Returns the registered domain (eTLD+1) for [host], lower-cased.
  ///
  /// - `cdn.foo.co.uk` → `foo.co.uk`
  /// - `bar.example.com` → `example.com`
  /// - empty / invalid → empty string
  ///
  /// Never throws.
  static String registeredDomain(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return '';

    if (_initialised) {
      try {
        final parsed = PublicSuffix(urlString: 'https://$h');
        final domain = parsed.domain;
        if (domain != null && domain.isNotEmpty) return domain.toLowerCase();
      } catch (_) {
        // PSL couldn't classify this host — fall through to the heuristic.
      }
    }

    // Fallback: last two dotted segments. Correct for `*.com`, `*.net`,
    // wrong for `*.co.uk` & similar — but better than crashing.
    final parts = h.split('.');
    if (parts.length < 2) return h;
    return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  }
}
