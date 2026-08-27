/// Builds and parses public team-share links for the Flutter Web client.
///
/// The API host is not a web page host. Share links must open the Flutter Web
/// app and pass the code through its hash route so the browser does not send a
/// `/share/...` request to the API server.
class TeamShareLink {
  static const webAppBaseUrl = 'https://cdt.junpgle.me';

  static String build(String shareCode) {
    final query = Uri(queryParameters: {'code': shareCode}).query;
    return '$webAppBaseUrl/#/share?$query';
  }

  /// Keeps a valid server-provided hash link, but repairs old `/share/...`
  /// links that point at the API host.
  static String normalize({String? shareUrl, String? shareCode}) {
    final rawUrl = shareUrl?.trim();
    final parsed =
        rawUrl == null || rawUrl.isEmpty ? null : Uri.tryParse(rawUrl);
    final code = shareCode?.trim().isNotEmpty == true
        ? shareCode!.trim()
        : parsed == null
            ? null
            : _extractCode(parsed);

    final fallback = code == null || code.isEmpty ? null : build(code);
    if (rawUrl == null || rawUrl.isEmpty) return fallback ?? '';
    if (parsed == null) return fallback ?? rawUrl;

    if (_isPathShare(parsed.path)) return fallback ?? rawUrl;
    return rawUrl;
  }

  /// Extracts a share code from either `/share/<code>` or `?code=<code>`.
  static String? codeFromRoute(String route) {
    var value = route.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.isEmpty) return null;

    final uri = _parseRoute(value);
    if (uri == null) return null;

    final directCode = _extractCode(uri);
    if (directCode != null) return directCode;

    // Uri.parse(fullUrl) stores `#/share?code=...` in fragment instead of
    // query/path. Support that form as a final fallback for startup routing.
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final fragmentUri = _parseRoute(fragment);
      if (fragmentUri != null) return _extractCode(fragmentUri);
    }
    return null;
  }

  static bool _isPathShare(String path) {
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    return normalized == '/share' || normalized.startsWith('/share/');
  }

  static String? _extractCode(Uri uri) {
    final queryCode = uri.queryParameters['code']?.trim();
    if (queryCode != null && queryCode.isNotEmpty) return queryCode;

    final segments = uri.pathSegments;
    final shareIndex = segments.lastIndexWhere(
      (segment) => segment.toLowerCase() == 'share',
    );
    if (shareIndex == -1 || shareIndex + 1 >= segments.length) return null;

    final code = Uri.decodeComponent(segments[shareIndex + 1]).trim();
    return code.isEmpty ? null : code;
  }

  static Uri? _parseRoute(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Uri.tryParse(value);
    }
    final route = value.startsWith('/') ? value : '/$value';
    return Uri.tryParse('http://localhost$route');
  }
}
