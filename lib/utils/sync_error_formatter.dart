import 'dart:async';

/// Formats sync exceptions and server error payloads into specific, user-facing
/// Chinese error messages instead of a generic catch-all.
class SyncErrorFormatter {
  const SyncErrorFormatter._();

  static String formatTransportError(Object error) {
    final raw = _stripExceptionPrefix(error.toString());
    final lower = raw.toLowerCase();

    if (error is TimeoutException ||
        lower.contains('timeoutexception') ||
        lower.contains('timed out') ||
        raw.contains('超时')) {
      return '请求超时，请检查网络连接';
    }
    if (lower.contains('handshakeexception') ||
        lower.contains('tlsexception') ||
        lower.contains('certificate_verify_failed')) {
      return '安全连接 (TLS/SSL) 握手失败';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('nodename nor servname')) {
      return '域名解析失败，请检查网络或服务器线路';
    }
    if (lower.contains('connection refused')) {
      return '服务器拒绝连接，请检查服务是否可用';
    }
    if (lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('broken pipe')) {
      return '网络连接中断，请稍后重试';
    }
    if (lower.contains('network is unreachable') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception')) {
      return '网络连接失败，无法连接服务器';
    }
    if (error is FormatException || lower.contains('formatexception')) {
      return '服务器返回数据格式异常';
    }
    return raw.isEmpty ? '网络请求异常' : '网络异常: ${_truncate(raw)}';
  }

  static String formatSyncFailure(Object error) {
    final raw = _stripExceptionPrefix(error.toString());
    if (raw.contains('LIMIT_EXCEEDED:')) {
      final detail = raw.split('LIMIT_EXCEEDED:').last.trim();
      return detail.isEmpty ? '今日同步次数已达上限' : detail;
    }

    final lower = raw.toLowerCase();
    if (error is TimeoutException ||
        lower.contains('timeoutexception') ||
        lower.contains('timed out')) {
      return '同步失败: 请求超时，请检查网络连接';
    }
    if (lower.contains('handshakeexception') ||
        lower.contains('tlsexception') ||
        lower.contains('certificate_verify_failed')) {
      return '同步失败: 安全连接 (TLS/SSL) 握手失败';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('nodename nor servname')) {
      return '同步失败: 域名解析失败，请检查网络或服务器线路';
    }
    if (lower.contains('connection refused')) {
      return '同步失败: 服务器拒绝连接';
    }
    if (lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('broken pipe')) {
      return '同步失败: 网络连接中断，请稍后重试';
    }
    if (lower.contains('socketexception') ||
        lower.contains('network is unreachable') ||
        lower.contains('clientexception')) {
      return '同步失败: 网络连接失败，无法连接服务器';
    }
    if (error is FormatException || lower.contains('formatexception')) {
      return '同步失败: 服务器返回数据格式异常';
    }
    if (lower.contains('databaseexception') || lower.contains('sqlite')) {
      return '同步失败: 本地数据库读写异常';
    }
    if (raw.contains('账户已切换')) {
      return '同步已取消: $raw';
    }
    if (raw.isEmpty) {
      return '同步失败: 未知异常';
    }
    if (raw.startsWith('同步失败:') || raw.startsWith('同步失败：')) {
      return _truncate(raw);
    }
    return '同步失败: ${_truncate(raw)}';
  }

  static bool isAuthExpiredError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    return lower.contains('无效的token') ||
        lower.contains('invalid_token') ||
        lower.contains('session_revoked') ||
        raw.contains('登录已失效') ||
        raw.contains('未授权') ||
        raw.contains('401');
  }

  static String _stripExceptionPrefix(String raw) {
    var result = raw.trim();
    const prefixes = [
      'Exception: ',
      'Bad state: ',
      'StateError: ',
      'FormatException: ',
    ];
    for (final prefix in prefixes) {
      if (result.startsWith(prefix)) {
        result = result.substring(prefix.length).trim();
      }
    }
    return result;
  }

  static String _truncate(String value, {int maxLength = 80}) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}…';
  }
}
