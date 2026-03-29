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

    // 没有 scheme 时补上 https:// 再解析
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://').hasMatch(trimmed);
    final toParse = hasScheme ? trimmed : 'https://$trimmed';

    final uri = Uri.tryParse(toParse);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;

    // 只允许常见协议
    if (!['http', 'https', 'ftp'].contains(uri.scheme.toLowerCase())) {
      return false;
    }

    final host = uri.host;
    if (host.isEmpty) return false;

    // localhost、IPv4、普通域名（至少有一个点）
    final isValidHost = host == 'localhost' ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
        RegExp(r'^[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)+$').hasMatch(host);

    return isValidHost;
  }

  String _truncateForDisplay(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;

    try {
      // 与 _isValidUrl 保持一致：没有 scheme 时补上再解析
      final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://').hasMatch(trimmed);
      final uri = Uri.parse(hasScheme ? trimmed : 'https://$trimmed');

      final host = uri.host;
      final path = uri.path.isEmpty || uri.path == '/' ? '' : uri.path;

      // 优先显示 host + 部分 path，更有辨识度
      final display = path.isNotEmpty ? '$host$path' : host;

      if (display.length > 30) {
        return '${display.substring(0, 30)}...';
      }
      return display.isNotEmpty ? display : trimmed;
    } catch (_) {
      return trimmed.length > 30 ? '${trimmed.substring(0, 30)}...' : trimmed;
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
      final pData = Pointer<Uint8>.fromAddress(hData);
      if (pData == nullptr) {
        return null;
      }
      try {
        final text = pData.cast<Utf16>().toDartString();
        return text;
      } finally {
        GlobalUnlock(Pointer.fromAddress(hData));
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
