import 'dart:convert';

/// 解析来自 SQLite、JSON 和后端接口的常见数值/时间字段。
abstract final class JsonValueParser {
  static int? toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static int toInt(dynamic value, {int fallback = 0}) {
    return toNullableInt(value) ?? fallback;
  }

  /// 将数据库中的 JSON 字符串或动态 Map 安全转换为字符串键 Map。
  /// 非法 JSON 和非对象值统一视为缺失，避免单条脏数据中断整批读取。
  static Map<String, dynamic>? toMap(dynamic value) {
    if (value == null) return null;
    dynamic decoded = value;
    if (value is String) {
      if (value.trim().isEmpty) return null;
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    if (decoded is Map) {
      try {
        return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 解析服务器毫秒时间戳；缺失或非法值沿用模型层的当前时间兜底。
  static int epochMillisOrNow(dynamic value) {
    final parsed = toNullableInt(value);
    if (parsed != null) return parsed;

    if (value is String) {
      final date = DateTime.tryParse(value.trim());
      if (date != null) return date.toUtc().millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// 解析服务器时间字段为本地时间；无效值返回 null。
  static DateTime? localDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();

    final milliseconds = toNullableInt(value);
    if (milliseconds != null) {
      if (milliseconds <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ).toLocal();
    }

    if (value is String) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }
}
