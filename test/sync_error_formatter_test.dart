import 'dart:async';

import 'package:countdown_todo/utils/sync_error_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncErrorFormatter', () {
    test('formatTransportError distinguishes network and format errors', () {
      expect(
        SyncErrorFormatter.formatTransportError(TimeoutException('timed out')),
        '请求超时，请检查网络连接',
      );
      expect(
        SyncErrorFormatter.formatTransportError(
          Exception('SocketException: Failed host lookup: api.example.com'),
        ),
        '域名解析失败，请检查网络或服务器线路',
      );
      expect(
        SyncErrorFormatter.formatTransportError(
          Exception('SocketException: Connection refused'),
        ),
        '服务器拒绝连接，请检查服务是否可用',
      );
      expect(
        SyncErrorFormatter.formatTransportError(
          Exception('HandshakeException: CERTIFICATE_VERIFY_FAILED'),
        ),
        '安全连接 (TLS/SSL) 握手失败',
      );
    });

    test('formatSyncFailure preserves specific server and local causes', () {
      expect(
        SyncErrorFormatter.formatSyncFailure(
          Exception('LIMIT_EXCEEDED:今日同步次数已达上限'),
        ),
        '今日同步次数已达上限',
      );
      expect(
        SyncErrorFormatter.formatSyncFailure(Exception('服务端响应格式异常 (HTTP 502)')),
        '同步失败: 服务端响应格式异常 (HTTP 502)',
      );
      expect(
        SyncErrorFormatter.formatSyncFailure(StateError('账户已切换，已取消旧账户异步操作')),
        '同步已取消: 账户已切换，已取消旧账户异步操作',
      );
      expect(
        SyncErrorFormatter.formatSyncFailure(
          Exception('DatabaseException(database is locked)'),
        ),
        '同步失败: 本地数据库读写异常',
      );
    });

    test('isAuthExpiredError detects token and session revocation errors', () {
      expect(
        SyncErrorFormatter.isAuthExpiredError(Exception('无效的Token')),
        isTrue,
      );
      expect(
        SyncErrorFormatter.isAuthExpiredError(
          Exception('该设备登录已失效，请重新登录 (SESSION_REVOKED)'),
        ),
        isTrue,
      );
      expect(SyncErrorFormatter.isAuthExpiredError(Exception('请求超时')), isFalse);
    });
  });
}
