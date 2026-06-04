import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/plugin_exception.dart';
import '../../core/utils/url_validator.dart';
import '../../domain/entities/plugin_manifest.dart';
import '../../data/models/plugin_manifest_model.dart';

/// Fetches, parses, and validates plugin manifests from remote URLs.
class PluginDiscoveryService {
  final Dio _dio;

  /// Maximum acceptable manifest body size. A hostile URL could otherwise
  /// stream gigabytes and OOM the app; this cap is generous for any
  /// legitimate manifest (typically <10 KB) or registry (<256 KB).
  static const int _maxManifestBytes = 512 * 1024; // 512 KB

  PluginDiscoveryService(this._dio);

  /// Fetches and validates a plugin manifest from the given [url].
  ///
  /// Throws [PluginUrlValidationException] if the URL is invalid.
  /// Throws [PluginNetworkException] if the fetch fails.
  /// Throws [InvalidManifestException] if the JSON schema is invalid.
  Future<PluginManifest> fetchAndValidate(String url) async {
    // 1. Validate URL
    final urlError = UrlValidator.validate(url);
    if (urlError != null) {
      throw PluginUrlValidationException(urlError);
    }

    // 2. Fetch (size-capped) and decode
    final raw = await _fetchBytes(url.trim(), const Duration(seconds: 10));
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      } else {
        throw const InvalidManifestException('Invalid response format');
      }
    } on FormatException catch (e) {
      throw InvalidManifestException('Manifest is not valid JSON: ${e.message}');
    }

    // 3. Validate required fields
    _validateSchema(json);

    // 4. Parse into entity
    return PluginManifestModel.fromJson(json);
  }

  /// Fetches a URL that may be a single manifest or a registry (multiple plugins).
  ///
  /// - If the response is a JSON object with required manifest fields, returns
  ///   a list of one manifest.
  /// - If the response is a JSON array, each element is either:
  ///   - a string (URL of a manifest to fetch), or
  ///   - an inline manifest object.
  /// - If the response is an object with a "plugins" array, same handling as array.
  ///
  /// Returns the list of manifests (one or many). Skips invalid entries in arrays.
  Future<List<PluginManifest>> fetchRegistry(String url) async {
    final urlError = UrlValidator.validate(url);
    if (urlError != null) {
      throw PluginUrlValidationException(urlError);
    }

    final dynamic data = await _fetchJson(url);

    if (data is Map<String, dynamic>) {
      if (data['plugins'] is List) {
        return _parseManifestList(data['plugins'] as List<dynamic>, url);
      }
      if (data['pluginId'] != null && data['urlTemplate'] != null) {
        _validateSchema(data);
        return [PluginManifestModel.fromJson(data)];
      }
      throw const InvalidManifestException(
        'Expected a plugin manifest or an object with "plugins" array',
      );
    }

    if (data is List) {
      return _parseManifestList(data, url);
    }

    throw const InvalidManifestException(
      'Expected a JSON object (manifest or registry) or array of plugins',
    );
  }

  Future<dynamic> _fetchJson(String url) async {
    final raw = await _fetchBytes(url.trim(), const Duration(seconds: 15));
    try {
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is Map<String, dynamic> || decoded is List) return decoded;
      throw const InvalidManifestException('Invalid response format');
    } on FormatException catch (e) {
      throw InvalidManifestException('Response is not valid JSON: ${e.message}');
    }
  }

  /// Fetches the response body as bytes with a hard size cap enforced
  /// **mid-stream** via Dio's `onReceiveProgress` + `CancelToken`.
  ///
  /// Without mid-stream cancellation a hostile server that omits
  /// `Content-Length` (or lies) would simply stream gigabytes — Dio buffers
  /// the whole `ResponseType.bytes` body before returning, so a post-hoc
  /// length check fires too late to prevent OOM. Here we abort the request
  /// as soon as `received` crosses the cap.
  Future<List<int>> _fetchBytes(String url, Duration receiveTimeout) async {
    final cancelToken = CancelToken();
    try {
      // 1. Pre-flight content-length check: cheap reject if the server is
      //    honest about the body size.
      // (The progress-callback check below handles the dishonest cases.)
      final response = await _dio.get<List<int>>(
        url,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: receiveTimeout,
          responseType: ResponseType.bytes,
        ),
        onReceiveProgress: (received, _) {
          if (received > _maxManifestBytes && !cancelToken.isCancelled) {
            cancelToken.cancel(
              'Manifest body exceeded $_maxManifestBytes bytes',
            );
          }
        },
      );
      // Defence-in-depth: also reject if Content-Length advertised too big,
      // or if the cap was breached without our progress callback firing
      // (very small bodies that arrive in a single chunk).
      final advertised =
          int.tryParse(response.headers.value('content-length') ?? '');
      if (advertised != null && advertised > _maxManifestBytes) {
        throw PluginNetworkException(
          'Manifest body too large (${advertised}B > ${_maxManifestBytes}B)',
        );
      }
      final bytes = response.data;
      if (bytes == null) {
        throw const InvalidManifestException('Empty response body');
      }
      if (bytes.length > _maxManifestBytes) {
        throw PluginNetworkException(
          'Manifest body too large (${bytes.length}B > ${_maxManifestBytes}B)',
        );
      }
      return bytes;
    } on DioException catch (e) {
      // Our own cancellation surfaces as DioExceptionType.cancel — translate
      // it back to PluginNetworkException so callers see the size-cap
      // message instead of a generic "request cancelled".
      if (CancelToken.isCancel(e)) {
        throw PluginNetworkException(
          'Manifest body exceeded $_maxManifestBytes bytes',
        );
      }
      if (kDebugMode) {
        debugPrint(
          'PluginDiscoveryService: DioException [${e.type}]: ${e.error}',
        );
      }
      final message = switch (e.type) {
        DioExceptionType.connectionTimeout => 'Connection timed out',
        DioExceptionType.receiveTimeout => 'Server took too long to respond',
        DioExceptionType.badResponse =>
          'Server returned error: ${e.response?.statusCode}',
        DioExceptionType.connectionError =>
          'Connection failed. Check your internet or if the URL is accessible.',
        _ => e.message ?? 'Unknown network error',
      };
      throw PluginNetworkException(
        'Failed to fetch: $message',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<List<PluginManifest>> _parseManifestList(
    List<dynamic> items,
    String registryUrl,
  ) async {
    final manifests = <PluginManifest>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      try {
        if (item is String) {
          final m = await fetchAndValidate(item.trim());
          manifests.add(m);
        } else if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          _validateSchema(map);
          manifests.add(PluginManifestModel.fromJson(map));
        }
      } catch (e) {
        debugPrint('PluginDiscoveryService: skip item $i: $e');
      }
    }
    return manifests;
  }

  /// Validates that a JSON manifest has all required fields.
  void _validateSchema(Map<String, dynamic> json) {
    final requiredFields = ['pluginId', 'name', 'urlTemplate'];

    for (final field in requiredFields) {
      if (!json.containsKey(field) || json[field] == null) {
        throw InvalidManifestException('Missing required field: "$field"');
      }
      if (json[field] is String && (json[field] as String).trim().isEmpty) {
        throw InvalidManifestException('Field "$field" cannot be empty');
      }
    }

    // urlTemplate is loaded directly in a WebView, so it must use a safe
    // scheme — javascript:, data:, file:, etc. would otherwise execute in
    // the WebView context. UrlValidator.validateUrlTemplate also bounds
    // length to guard against pathological payloads.
    final templateError = UrlValidator.validateUrlTemplate(
      json['urlTemplate'] as String,
    );
    if (templateError != null) {
      throw InvalidManifestException(templateError);
    }

    // Validate hooks are known values
    if (json.containsKey('hooks') && json['hooks'] is List) {
      final validHooks = ['media_header', 'episode_item', 'media_card_context'];
      for (final hook in json['hooks'] as List) {
        if (hook is! String || !validHooks.contains(hook)) {
          throw InvalidManifestException(
            'Invalid hook: "$hook". Valid: $validHooks',
          );
        }
      }
    }

    // Validate action type
    if (json.containsKey('actionType') && json['actionType'] is String) {
      final validTypes = ['webview', 'externalLink', 'metadataFetch'];
      if (!validTypes.contains(json['actionType'])) {
        throw InvalidManifestException(
          'Invalid actionType: "${json['actionType']}". Valid: $validTypes',
        );
      }
    }
  }
}
