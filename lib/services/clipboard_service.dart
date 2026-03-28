import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

class ClipboardService {
  Timer? _pollTimer;
  String? _lastClipboardContent;
  final _urlController = StreamController<String>.broadcast();
  bool _initialized = false;

  Stream<String> get onUrlCopied => _urlController.stream;

  bool _isValidUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 2048) return false;
    final urlRegex = RegExp(
      r'^(https?|ftp)://[^\s/$.?#].[^\s]*$',
      caseSensitive: false,
    );
    return urlRegex.hasMatch(trimmed);
  }

  String _truncateForDisplay(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.length > 20) {
        return '${host.substring(0, 20)}...';
      }
      return host;
    } catch (_) {
      if (url.length > 25) {
        return '${url.substring(0, 25)}...';
      }
      return url;
    }
  }

  String? _getClipboardText() {
    if (IsClipboardFormatAvailable(CF_UNICODETEXT) == 0) {
      return null;
    }
    if (OpenClipboard(NULL) == 0) {
      return null;
    }
    try {
      final hData = GetClipboardData(CF_UNICODETEXT);
      if (hData == 0) {
        return null;
      }
      final pData = GlobalLock(hData);
      if (pData == nullptr) {
        return null;
      }
      try {
        final text = pData.cast<Utf16>().toDartString();
        return text;
      } finally {
        GlobalUnlock(hData);
      }
    } finally {
      CloseClipboard();
    }
  }

  Future<void> _initClipboard() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _lastClipboardContent = _getClipboardText()?.trim();
      final preview = _lastClipboardContent?.length ?? 0;
      debugPrint(
          '[ClipboardService] Initialized, current clipboard: ${preview > 30 ? "..." : ""}');
    } catch (e) {
      debugPrint('[ClipboardService] Init error: $e');
      _initialized = false;
    }
  }

  void startListening() async {
    await _initClipboard();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      try {
        final content = _getClipboardText()?.trim();
        if (content == null || content.isEmpty) return;

        final isNew = content != _lastClipboardContent;
        debugPrint(
            '[ClipboardService] Clipboard check: ${content.length > 20 ? "..." : ""}, isNew=$isNew');

        if (!isNew) return;
        _lastClipboardContent = content;

        if (_isValidUrl(content)) {
          final displayUrl = _truncateForDisplay(content);
          _urlController.add(content);
          debugPrint('[ClipboardService] URL detected: $displayUrl');
        }
      } catch (e) {
        debugPrint('[ClipboardService] Error: $e');
      }
    });
  }

  void stopListening() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() {
    stopListening();
    _urlController.close();
  }
}
