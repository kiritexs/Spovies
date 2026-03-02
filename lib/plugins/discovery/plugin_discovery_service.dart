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
