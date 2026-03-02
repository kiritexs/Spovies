/// Validates plugin manifest URLs.
///
/// Enforces HTTPS and valid URL format for security.
class UrlValidator {
  /// Returns `null` if valid, or a human-readable error string.
  static String? validate(String url) {
    if (url.trim().isEmpty) {
      return 'URL cannot be empty';
    }

    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
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

  /// Returns true if the URL is valid HTTPS.
  static bool isValid(String url) => validate(url) == null;
}
