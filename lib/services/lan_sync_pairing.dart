import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models.dart';
import 'todo_lww_service.dart';

/// 面对面二维码配对载荷（带一次性 Token 与过期时间）。
class LanPairingPayload {
  const LanPairingPayload({
    this.version = 1,
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    required this.ip,
    required this.port,
    required this.token,
    required this.expiresAt,
  });

  final int version;
  final String deviceId;
  final String userId;
  final String deviceName;
  final String ip;
  final int port;
  final String token;
  final int expiresAt;

  static const String uriScheme = 'cdt-lan';
  static const String uriHost = 'sync';

  /// 生成加密安全的 32 位十六进制一次性令牌。
  static String generateOneTimeToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool isExpired({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return expiresAt > 0 && now > expiresAt;
  }

  Map<String, dynamic> toJson() => {
    'v': version,
    'deviceId': deviceId,
    'userId': userId,
    'deviceName': deviceName,
    'ip': ip,
    'port': port,
    'token': token,
    'expiresAt': expiresAt,
  };

  String toUriString() => Uri(
    scheme: uriScheme,
    host: uriHost,
    queryParameters: {
      'v': '$version',
      'deviceId': deviceId,
      'userId': userId,
      'deviceName': deviceName,
      'ip': ip,
      'port': '$port',
      'token': token,
      'expiresAt': '$expiresAt',
    },
  ).toString();

  /// 解析 `cdt-lan://sync?...` 或 JSON 格式的配对信息。
  static LanPairingPayload? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('{')) {
      try {
        final map = jsonDecode(trimmed);
        if (map is! Map) return null;
        return _fromMap(map);
      } catch (_) {
        return null;
      }
    }

    try {
      final uri = Uri.parse(trimmed);
      if (uri.scheme != uriScheme || uri.host != uriHost) {
        return null;
      }
      return _fromMap(uri.queryParameters);
    } catch (_) {
      return null;
    }
  }

  static LanPairingPayload? _fromMap(Map<dynamic, dynamic> map) {
    final ip = map['ip']?.toString().trim() ?? '';
    final port = int.tryParse(map['port']?.toString() ?? '') ?? 0;
    final token = map['token']?.toString().trim() ?? '';
    if (ip.isEmpty || port <= 0 || port > 65535 || token.isEmpty) {
      return null;
    }

    return LanPairingPayload(
      version: int.tryParse(map['v']?.toString() ?? '') ?? 1,
      deviceId: map['deviceId']?.toString().trim() ?? '',
      userId: map['userId']?.toString().trim() ?? '',
      deviceName: map['deviceName']?.toString().trim() ?? '未知设备',
      ip: ip,
      port: port,
      token: token,
      expiresAt: int.tryParse(map['expiresAt']?.toString() ?? '') ?? 0,
    );
  }
}

/// 局域网同步合并规则，统一委托给 [TodoLwwService] 的严格 LWW 比较。
class LanSyncLww {
  const LanSyncLww._();

  static bool isTodoWinner(TodoItem incoming, TodoItem current) =>
      TodoLwwService.isIncomingWinner(
        incomingUpdatedAt: incoming.updatedAt,
        incomingVersion: incoming.version,
        currentUpdatedAt: current.updatedAt,
        currentVersion: current.version,
      );

  static bool isCountdownWinner(CountdownItem incoming, CountdownItem current) =>
      TodoLwwService.isIncomingWinner(
        incomingUpdatedAt: incoming.updatedAt,
        incomingVersion: incoming.version,
        currentUpdatedAt: current.updatedAt,
        currentVersion: current.version,
      );

  static bool isTimeLogWinner(TimeLogItem incoming, TimeLogItem current) =>
      TodoLwwService.isIncomingWinner(
        incomingUpdatedAt: incoming.updatedAt,
        incomingVersion: incoming.version,
        currentUpdatedAt: current.updatedAt,
        currentVersion: current.version,
      );
}

/// 局域网发现阶段使用的账号摘要工具，避免在广播/mDNS 中明文暴露用户名或邮箱。
class LanDiscoveryIdentity {
  static const String _hashSalt = 'cdtodo_lan_user_v1:';
  static const String _hashPrefix = 'u1:';

  static String hashUserId(String? rawUserId) {
    final normalized = (rawUserId ?? '').trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'local') return 'local';
    final digest = sha256.convert(utf8.encode('$_hashSalt$normalized'));
    return '$_hashPrefix${digest.toString().substring(0, 16)}';
  }

  static bool isSameUser(String? candidate, String? currentRawUserId) {
    final c = (candidate ?? '').trim();
    final current = (currentRawUserId ?? '').trim();
    if (c.isEmpty || current.isEmpty) return false;
    if (c == hashUserId(current)) return true;
    // 兼容尚未升级的旧版客户端明文 userId
    if (!c.startsWith(_hashPrefix)) {
      return c.toLowerCase() == current.toLowerCase();
    }
    return false;
  }
}
