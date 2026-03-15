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

    // 2. Fetch JSON
    final Map<String, dynamic> json;
    try {
      final response = await _dio.get<dynamic>(
        url.trim(),
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.json,
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        json = data;
      } else if (data is String) {
        json = jsonDecode(data) as Map<String, dynamic>;
      } else {
        throw const InvalidManifestException('Invalid response format');
      }
    } on DioException catch (e) {
      // Print full error to console for developer debugging
      debugPrint(
        'PluginDiscoveryService: DioException [${e.type}]: ${e.error}',
      );
      debugPrint('Stacktrace: ${e.stackTrace}');

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
        'Failed to fetch manifest: $message',
        statusCode: e.response?.statusCode,
      );
    } catch (e) {
      throw PluginNetworkException('Unexpected error: $e');
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
    try {
      final response = await _dio.get<dynamic>(
        url.trim(),
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.json,
        ),
      );
      final raw = response.data;
      if (raw is Map<String, dynamic>) return raw;
      if (raw is List) return raw;
      if (raw is String) return jsonDecode(raw);
      throw const InvalidManifestException('Invalid response format');
    } on DioException catch (e) {
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
          final map = Map<String, dynamic>.from(item as Map);
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
