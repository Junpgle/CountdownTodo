import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Configuration constants for ClipboardService
class ClipboardConfig {
  ClipboardConfig._();

  /// Polling interval for clipboard changes
  static const Duration pollInterval = Duration(seconds: 1);

  /// Maximum URL length to consider valid
  static const int maxUrlLength = 2048;

  /// Maximum display URL length before truncation
  static const int maxDisplayLength = 30;

  /// Allowed URL schemes
  static const Set<String> allowedSchemes = {'http', 'https', 'ftp'};
}

/// Service for monitoring clipboard and detecting copied URLs.
/// Uses Win32 API for direct clipboard access on Windows.
class ClipboardService {
  static final ClipboardService _instance = ClipboardService._internal();

  factory ClipboardService() => _instance;

  ClipboardService._internal();

  Timer? _pollTimer;
  String? _lastClipboardContent;
  final _urlController = StreamController<String>.broadcast();
  bool _initialized = false;

  /// Stream of detected URLs from clipboard
  Stream<String> get onUrlCopied => _urlController.stream;

  /// Whether the service is currently listening
  bool get isListening => _pollTimer?.isActive ?? false;

  /// Whether the service has been initialized
  bool get isInitialized => _initialized;

  /// Validate if a string is a valid URL
  bool _isValidUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > ClipboardConfig.maxUrlLength) {
      return false;
    }

    // Add scheme if missing before parsing
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://').hasMatch(trimmed);
    final toParse = hasScheme ? trimmed : 'https://$trimmed';

    final uri = Uri.tryParse(toParse);
    if (uri == null || !uri.hasScheme) {
      debugPrint('[ClipboardService] URL parse failed: $trimmed');
      return false;
    }

    // Allow URIs without authority for certain schemes (like mailto:)
    if (!uri.hasAuthority) {
      // But for http/https, we need authority
      if (['http', 'https'].contains(uri.scheme.toLowerCase())) {
        debugPrint('[ClipboardService] HTTP URL without authority: $trimmed');
        return false;
      }
    }

    if (!ClipboardConfig.allowedSchemes.contains(uri.scheme.toLowerCase())) {
      debugPrint('[ClipboardService] Scheme not allowed: ${uri.scheme}');
      return false;
    }

    final host = uri.host;
    if (host.isEmpty) {
      debugPrint('[ClipboardService] Empty host: $trimmed');
      return false;
    }

    // Valid hosts: localhost, IPv4, or domain with at least one dot
    final isValidHost = host == 'localhost' ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
        RegExp(r'^[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)+$').hasMatch(host);

    if (!isValidHost) {
      debugPrint('[ClipboardService] Invalid host: $host');
    }

    return isValidHost;
  }

  /// Truncate URL for display purposes
  String _truncateForDisplay(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;

    try {
      final hasScheme =
          RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://').hasMatch(trimmed);
      final uri = Uri.parse(hasScheme ? trimmed : 'https://$trimmed');

      final host = uri.host;
      final path = uri.path.isEmpty || uri.path == '/' ? '' : uri.path;

      final display = path.isNotEmpty ? '$host$path' : host;

      if (display.length > ClipboardConfig.maxDisplayLength) {
        return '${display.substring(0, ClipboardConfig.maxDisplayLength)}...';
      }
      return display.isNotEmpty ? display : trimmed;
    } catch (_) {
      return trimmed.length > ClipboardConfig.maxDisplayLength
          ? '${trimmed.substring(0, ClipboardConfig.maxDisplayLength)}...'
          : trimmed;
    }
  }

  /// Get text from Windows clipboard using Win32 API
  String? _getClipboardText() {
    if (IsClipboardFormatAvailable(CF_UNICODETEXT) == 0) {
      return null;
    }
    if (OpenClipboard(NULL) == 0) {
      return null;
    }
    try {
      final hData = GetClipboardData(CF_UNICODETEXT);
      if (hData == 0) return null;

      final handle = Pointer.fromAddress(hData);
      final pData = GlobalLock(handle);
      if (pData == nullptr) return null;

      try {
        return pData.cast<Utf16>().toDartString();
      } finally {
        GlobalUnlock(handle);
      }
    } finally {
      CloseClipboard();
    }
  }

  /// Initialize clipboard state
  Future<void> _initClipboard() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _lastClipboardContent = _getClipboardText()?.trim();
      debugPrint('[ClipboardService] Initialized');
    } catch (e) {
      debugPrint('[ClipboardService] Init error: $e');
      _initialized = false;
    }
  }

  /// Start listening for clipboard changes
  void startListening() async {
    await _initClipboard();
    if (_pollTimer?.isActive == true) {
      debugPrint('[ClipboardService] Already listening');
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(ClipboardConfig.pollInterval, (_) {
      try {
        final content = _getClipboardText()?.trim();
        if (content == null || content.isEmpty) return;

        final isNew = content != _lastClipboardContent;
        if (!isNew) return;

        _lastClipboardContent = content;
        debugPrint(
            '[ClipboardService] New content detected: ${content.length > 50 ? "${content.substring(0, 50)}..." : content}');

        if (_isValidUrl(content)) {
          final displayUrl = _truncateForDisplay(content);
          debugPrint('[ClipboardService] URL detected: $displayUrl');
          _urlController.add(content);
        } else {
          debugPrint('[ClipboardService] Content is not a valid URL');
        }
      } catch (e) {
        debugPrint('[ClipboardService] Error: $e');
      }
    });
    debugPrint('[ClipboardService] Started listening');
  }

  /// Stop listening for clipboard changes
  void stopListening() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Reset the last known clipboard content (useful after URL is processed)
  void resetLastContent() {
    _lastClipboardContent = _getClipboardText()?.trim();
  }

  /// Dispose resources
  void dispose() {
    stopListening();
    if (!_urlController.isClosed) {
      _urlController.close();
    }
  }
}
