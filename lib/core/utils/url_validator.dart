/// Validates plugin manifest URLs and plugin url templates.
///
/// Enforces HTTPS and valid URL format for security.
class UrlValidator {
  /// Maximum acceptable length of a plugin url template. Browsers cap real
  /// URLs at ~8000 chars; embed templates are far shorter in practice.
  static const int _maxTemplateLength = 2000;

  /// Returns `null` if valid, or a human-readable error string.
  static String? validate(String url) {
    if (url.trim().isEmpty) {
      return 'URL cannot be empty';
    }

    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      return 'Invalid URL format';
    }

    if (uri.scheme != 'https') {
      return 'Only HTTPS URLs are allowed';
    }

    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      return 'Localhost URLs are not allowed';
    }

    return null; // Valid
  }

  /// Validates a plugin URL template (the `urlTemplate` field of a manifest).
  ///
  /// Templates contain placeholders like `{{tmdbId}}`, `{{type}}`, etc., so
  /// we can't fully parse them as URIs. We instead enforce:
  ///   - non-empty
  ///   - length cap (defence against pathological payloads)
  ///   - scheme prefix `http://` or `https://` only — explicitly rejects
  ///     `javascript:`, `data:`, `file:`, `vbscript:`, `about:`, etc. which
  ///     would otherwise be loaded verbatim by the WebView.
  ///
  /// Returns `null` if valid, or a human-readable error string.
  static String? validateUrlTemplate(String template) {
    final trimmed = template.trim();
    if (trimmed.isEmpty) {
      return 'urlTemplate cannot be empty';
    }
    if (trimmed.length > _maxTemplateLength) {
      return 'urlTemplate exceeds $_maxTemplateLength character limit';
    }
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return 'urlTemplate must start with http:// or https://';
    }
    return null;
  }
}
