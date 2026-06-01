import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// ─── Why a remote community blocklist ─────────────────────────────────────────
//
// A hand-curated list of ~70 domains can't cover the thousands of ad networks
// seen across streaming sites. This service maintains a living, community-driven
// blocklist that is refreshed automatically every 24 hours.
//
// Sources (ordered by preference):
//
//   1. OISD "small" — false-positive-aware, streaming-friendly, ~35k domains.
//      Plain domain-per-line format. Updated daily.
//      https://small.oisd.nl
//
//   2. OISD "big" — more aggressive, ~250k domains.  Tried if small fails.
//      https://big.oisd.nl
//
//   3. Peter Lowe's Ad & Tracker server list — classic, ~4k high-confidence domains.
//      Plain domain-per-line format. Low false-positives.
//      https://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml&...
//
//   4. AdGuard DNS filter — parses ||domain^ rules, ~60k entries.
//      https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
//
//   5. Steven Black unified hosts — hosts-file format, ~100k domains.
//      Fallback of last resort — large but very diverse.
//      https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
//
//   6. NoCoin filter list — cryptocurrency mining scripts.
//      https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt
//
// Lookup: O(1) HashSet — no performance cost per intercepted request.
// Memory: ~35k entries ≈ 2–3 MB — negligible.
// Network: background-only fetch, compressed to ~800 KB for OISD basic.
// Cache: survives app restarts; expires after 24 h.

// ─── Remote source definitions ────────────────────────────────────────────────

enum _BlocklistFormat { plainDomain, hostsFile, adGuardRules }

class _BlocklistSource {
  final String url;
  final _BlocklistFormat format;
  final String name;

  const _BlocklistSource({
    required this.url,
    required this.format,
    required this.name,
  });
}

const _kSources = [
  // 1. OISD small — best quality/coverage ratio for streaming sites
  _BlocklistSource(
    url: 'https://small.oisd.nl',
    format: _BlocklistFormat.plainDomain,
    name: 'OISD Small',
  ),
  // 2. Peter Lowe — small, zero false-positives
  _BlocklistSource(
    url:
        'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml&showintro=0&mimetype=plaintext',
    format: _BlocklistFormat.plainDomain,
    name: 'Peter Lowe',
  ),
  // 3. AdGuard DNS filter — catches many streaming-site ad CDNs
  _BlocklistSource(
    url: 'https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt',
    format: _BlocklistFormat.adGuardRules,
    name: 'AdGuard DNS',
  ),
  // 4. OISD big — aggressive, ~250k (tried if small fails)
  _BlocklistSource(
    url: 'https://big.oisd.nl',
    format: _BlocklistFormat.plainDomain,
    name: 'OISD Big',
  ),
  // 5. NoCoin — crypto mining scripts
  _BlocklistSource(
    url:
        'https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt',
    format: _BlocklistFormat.hostsFile,
    name: 'NoCoin',
  ),
  // 6. Steven Black unified hosts — large fallback
  _BlocklistSource(
    url: 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts',
    format: _BlocklistFormat.hostsFile,
    name: 'Steven Black',
  ),
];

const _kCacheTtl = Duration(hours: 24);
const _kCacheFile = 'spovies_blocklist_v2.txt';
const _kCacheMetaFile = 'spovies_blocklist_v2_meta.json';
const _kConnectTimeout = Duration(seconds: 15);
const _kResponseTimeout = Duration(seconds: 45);

// ─── Built-in fallback ────────────────────────────────────────────────────────
//
// Always available immediately — used while remote fetch is in progress.
// Covers the most aggressive ad networks on popular streaming sites.

const _kFallbackDomains = <String>[
  // Google ad stack
  'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
  'google-analytics.com', 'analytics.google.com', 'adservice.google.com',
  // Major ad exchanges
  'adnxs.com', 'adsrvr.org', 'outbrain.com', 'taboola.com',
  'criteo.com', 'rubiconproject.com', 'openx.net', 'pubmatic.com',
  'indexexchange.com', 'appnexus.com', 'smartadserver.com',
  // Pop / redirect networks (most aggressive on streaming sites)
  'popads.net', 'popcash.net', 'juicyads.com', 'exoclick.com',
  'trafficjunky.com', 'propellerads.com', 'hilltopads.net', 'adsterra.com',
  'revenuehits.com', 'onclkds.com', 'onclickmax.com', 'pushame.com',
  'clickadu.com', 'clickaine.com', 'adtng.com', 'adrunnr.com',
  'adskeeper.co.uk', 'a-ads.com', 'ad-maven.com', 'admaven.co',
  'revcontent.com', 'mgid.com', 'bidvertiser.com', 'richpush.co',
  'galaksion.com', 'acint.net',
  // ACS / example.com specific
  'acscdn.com', 'adexchangeclear.com', 'crcdn.org',
  // Streaming-site aggressive redirectors
  'gamerhit.co', 'trakzon.com', 'goosebomb.com', 'gryphline.com',
  'mafroad.com', 'healthington.net', 'total-block.net',
  'pops.best', 'topofads.com', 'fastpopads.com',
  'megapush.com', 'moneytag.com',
  // URL shorteners / link monetization
  'adf.ly', 'shorte.st', 'linkvertise.com', 'bc.vc', 'ouo.io', 'sh.st',
  'exe.io', 'shrinkme.io', 'gplinks.co', 'adrinolinks.com',
  // Social trackers / analytics
  'connect.facebook.net', 'hotjar.com', 'cdn.mouseflow.com', 'clarity.ms',
  'statcounter.com', 'quantserve.com', 'scorecardresearch.com',
  // Crypto mining
  'coinhive.com', 'coin-hive.com', 'cryptoloot.pro', 'minero.cc',
  // Push notification spam
  'pushcrew.com',
  // CDN ad loaders
  'betrad.com', 'serving-sys.com', 'yieldmanager.com', 'cpmstar.com',
  // Yahoo/Oath
  'ads.yahoo.com', 'advertising.com',
  // Trackers
  'usrpubtrk.com', 'histats.com',
];

// ─── AdBlocklist ──────────────────────────────────────────────────────────────

/// Thread-safe, O(1) lookup blocklist backed by a community-maintained
/// remote list with local disk cache.
class AdBlocklist {
  final HashSet<String> _domains;

  /// Number of unique domains in the list.
  final int domainCount;

  /// True if remote/cached data was loaded; false if fallback only.
  final bool isRemote;

  /// Which source successfully provided the list (for debug/logging).
  final String sourceName;

  /// LRU cache for domain lookups to speed up suffix walks.
  final LinkedHashMap<String, bool> _cache = LinkedHashMap<String, bool>();
  static const int _maxCacheSize = 1000;

  AdBlocklist._({
    required HashSet<String> domains,
    required this.domainCount,
    required this.isRemote,
    required this.sourceName,
  }) : _domains = domains;

  // ── Factory ─────────────────────────────────────────────────────────────────

  /// Synchronous fallback — always available immediately.
  factory AdBlocklist.fallback() => AdBlocklist._(
    domains: HashSet<String>.from(_kFallbackDomains),
    domainCount: _kFallbackDomains.length,
    isRemote: false,
    sourceName: 'Built-in fallback',
  );

  /// Load the blocklist (async):
  ///   1. Return disk-cached list if within TTL.
  ///   2. Try each remote source in order; use the first that succeeds.
  ///   3. Fall back to built-in on network failure.
  ///
  /// Never throws.
  static Future<AdBlocklist> load() async {
    final fallbackSet = HashSet<String>.from(_kFallbackDomains);

    try {
      final dir = await getApplicationSupportDirectory();
      final cacheFile = File(
        '${dir.path}${Platform.pathSeparator}$_kCacheFile',
      );
      final metaFile = File(
        '${dir.path}${Platform.pathSeparator}$_kCacheMetaFile',
      );

      // ── 1. Try disk cache ──────────────────────────────────────────────────
      // existsSync is faster than the async variant for a single stat call
      // — there is no concurrency win and the async wrapper just queues a
      // microtask. Used only on startup, so blocking is negligible.
      if (cacheFile.existsSync() && metaFile.existsSync()) {
        try {
          final meta =
              jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
          final cachedAt = DateTime.parse(meta['cachedAt'] as String);
          final source = (meta['source'] as String?) ?? 'cached';
          if (DateTime.now().difference(cachedAt) < _kCacheTtl) {
            final raw = await cacheFile.readAsString();
            final sourceObj = _kSources.firstWhere(
              (s) => s.name == source,
              orElse: () => _kSources.first,
            );
            final domains = _parseRaw(raw, sourceObj.format, fallbackSet);
            if (kDebugMode) {
              debugPrint(
                '[AdBlocklist] Cache hit ($source): ${domains.length} domains '
                '(${DateTime.now().difference(cachedAt).inHours}h old)',
              );
            }
            return AdBlocklist._(
              domains: domains,
              domainCount: domains.length,
              isRemote: true,
              sourceName: '$source (cached)',
            );
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[AdBlocklist] Cache read failed: $e');
          // Fall through to network fetch.
        }
      }

      // ── 2. Try each source in order ─────────────────────────────────────
      for (final source in _kSources) {
        final raw = await _fetch(source.url);
        if (raw == null) continue;

        final domains = _parseRaw(raw, source.format, fallbackSet);
        if (domains.length < 100) {
          // Suspiciously small — likely an error page, try next.
          if (kDebugMode) {
            debugPrint(
              '[AdBlocklist] ${source.name}: only ${domains.length} domains, skipping.',
            );
          }
          continue;
        }

        // Persist to disk.
        try {
          await cacheFile.writeAsString(raw);
          await metaFile.writeAsString(
            jsonEncode({
              'cachedAt': DateTime.now().toIso8601String(),
              'source': source.name,
              'domainCount': domains.length,
            }),
          );
        } catch (e) {
          if (kDebugMode) debugPrint('[AdBlocklist] Cache write failed: $e');
        }

        if (kDebugMode) {
          debugPrint(
            '[AdBlocklist] Loaded ${domains.length} domains from ${source.name}.',
          );
        }
        return AdBlocklist._(
          domains: domains,
          domainCount: domains.length,
          isRemote: true,
          sourceName: source.name,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AdBlocklist] Load error: $e');
    }

    if (kDebugMode) debugPrint('[AdBlocklist] Using built-in fallback.');
    return AdBlocklist.fallback();
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Returns `true` if [url] should be blocked.
  ///
  /// Check order:
  ///   1. Exact hostname match — for domains stored as full subdomains.
  ///   2. Suffix walk — catches CDN subdomains like `cdn2.acscdn.com` AND
  ///      naturally covers the registered domain (eTLD+1) since the walk
  ///      visits every suffix `parts[i..]`. The previous explicit eTLD+1
  ///      step was redundant for 3+-part hosts and only added string
  ///      allocations.
  bool isBlocked(String url) {
    if (url.isEmpty) return false;
    final host = _hostOf(url);
    if (host.isEmpty) return false;

    // Check LRU cache
    if (_cache.containsKey(host)) {
      final cachedResult = _cache.remove(host)!;
      _cache[host] = cachedResult; // Move to end (most recently used)
      return cachedResult;
    }

    bool computeBlock() {
      // 1. Exact host
      if (_domains.contains(host)) return true;
      // 2. Suffix walk (subdomain cascade + registered domain)
      final parts = host.split('.');
      for (var i = 1; i < parts.length; i++) {
        if (_domains.contains(parts.sublist(i).join('.'))) return true;
      }
      return false;
    }

    final result = computeBlock();
    _cache[host] = result;
    if (_cache.length > _maxCacheSize) {
      _cache.remove(_cache.keys.first); // Remove oldest
    }
    return result;
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  static Future<String?> _fetch(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _kConnectTimeout;
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = true;
      req.maxRedirects = 5;
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'Spovies/1.0 (ad-blocklist)')
        ..set(HttpHeaders.acceptEncodingHeader, 'gzip, deflate')
        ..set(HttpHeaders.acceptHeader, 'text/plain, */*');
      final resp = await req.close().timeout(_kResponseTimeout);
      if (resp.statusCode == 200) {
        // The .timeout() above only bounds req.close(); a slow streaming
        // response could otherwise hold the connection open indefinitely
        // while we drain the body. Bound the body read separately.
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(_kResponseTimeout);
        client.close();
        return body;
      }
      if (kDebugMode) {
        debugPrint('[AdBlocklist] HTTP ${resp.statusCode} from $url');
      }
      client.close();
    } catch (e) {
      if (kDebugMode) debugPrint('[AdBlocklist] Fetch failed ($url): $e');
      client?.close(force: true);
    }
    return null;
  }

  /// Parse raw text based on format, merging with [base] (fallback) domains.
  static HashSet<String> _parseRaw(
    String raw,
    _BlocklistFormat format,
    HashSet<String> base,
  ) {
    final result = HashSet<String>.from(base);
    for (var line in raw.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
        continue;
      }

      String? domain;

      switch (format) {
        case _BlocklistFormat.plainDomain:
          // OISD / Peter Lowe: one bare domain per line
          if (_validDomain(line)) domain = line;

        case _BlocklistFormat.hostsFile:
          // 0.0.0.0 example.com  OR  127.0.0.1 example.com
          if (line.startsWith('0.0.0.0 ') ||
              line.startsWith('127.0.0.1 ') ||
              line.startsWith('::1 ')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) domain = parts[1];
          } else if (_validDomain(line)) {
            // Some hosts files include bare domains too
            domain = line;
          }

        case _BlocklistFormat.adGuardRules:
          // ||example.com^  — the most common rule type
          if (line.startsWith('||') && line.contains('^')) {
            // Split off options suffix (e.g. $important, $dnstype=A)
            const dollarSign = r'$';
            domain = line
                .substring(2) // strip ||
                .split('^')
                .first // take the part before ^
                .split('/') // drop any path
                .first
                .split(dollarSign) // drop options like $important
                .first;
          } else if (!line.startsWith('@') &&
              !line.startsWith('[') &&
              !line.contains('*') &&
              !line.contains('/') &&
              _validDomain(line)) {
            // Plain domain in an AdGuard file
            domain = line;
          }
      }

      if (domain == null) continue;
      domain = domain.trim().toLowerCase();

      // Skip localhost / broadcast addresses
      if (domain == 'localhost' ||
          domain == 'local' ||
          domain == '0.0.0.0' ||
          domain == 'broadcasthost') {
        continue;
      }

      if (_validDomain(domain)) result.add(domain);
    }
    return result;
  }

  static bool _validDomain(String s) {
    if (s.isEmpty || s.length > 253 || !s.contains('.')) return false;
    // Reject raw IP addresses
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(s)) return false;
    // Only allow valid domain characters
    return RegExp(r'^[a-zA-Z0-9.\-]+$').hasMatch(s);
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host.toLowerCase();
    } catch (_) {
      return '';
    }
  }
}

// ─── Riverpod providers ───────────────────────────────────────────────────────

/// Async provider — resolves to the full remote/cached list.
/// While loading, widgets should fall back to [adBlocklistFallbackProvider].
final adBlocklistProvider = FutureProvider<AdBlocklist>(
  (ref) => AdBlocklist.load(),
);

/// Synchronous provider — always ready immediately (built-in ~70 domains).
/// Use this for the first few requests while [adBlocklistProvider] warms up.
final adBlocklistFallbackProvider = Provider<AdBlocklist>(
  (_) => AdBlocklist.fallback(),
);
