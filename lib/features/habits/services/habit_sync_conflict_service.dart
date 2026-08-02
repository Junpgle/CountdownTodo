import 'dart:convert';

/// 习惯同步时用于判断“业务内容是否一致”的工具。
///
/// 版本号、设备号、时间戳和冲突标记属于同步元数据，不应该因为它们不同
/// 就把两份业务内容一致的习惯再次展示为冲突。
abstract final class HabitSyncConflictService {
  static const _metadataKeys = {
    'id',
    'uuid',
    'user_id',
    'version',
    'device_id',
    'created_at',
    'updated_at',
    'has_conflict',
    'conflict_data',
    'server_version_data',
  };

  /// 判断目标或规则的业务字段是否一致。
  ///
  /// 支持服务端的 snake_case 和客户端可能出现的 camelCase，并将 JSON
  /// 字符串、List、Map 归一化后再比较，避免字段格式差异制造假冲突。
  static bool hasSameBusinessContent(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    return jsonEncode(_businessFields(local)) ==
        jsonEncode(_businessFields(remote));
  }

  static Map<String, dynamic> _businessFields(Map<String, dynamic> data) {
    final fields = <String, dynamic>{};
    for (final entry in data.entries) {
      final key = _snakeCase(entry.key);
      if (_metadataKeys.contains(key)) continue;
      final value = _normalizeValue(entry.value);
      if (value != null) fields[key] = value;
    }
    final sortedKeys = fields.keys.toList()..sort();
    return <String, dynamic>{
      for (final key in sortedKeys) key: fields[key],
    };
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return _normalizeValue(jsonDecode(trimmed));
        } catch (_) {
          // 不是合法 JSON 时按普通字符串比较。
        }
      }
      return value;
    }
    if (value is List) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    if (value is Map) {
      final normalized = <String, dynamic>{};
      for (final entry in value.entries) {
        final normalizedValue = _normalizeValue(entry.value);
        if (normalizedValue != null) {
          normalized[entry.key.toString()] = normalizedValue;
        }
      }
      final sortedKeys = normalized.keys.toList()..sort();
      return <String, dynamic>{
        for (final key in sortedKeys) key: normalized[key],
      };
    }
    return value.toString();
  }

  static String _snakeCase(String value) => value
      .replaceAllMapped(
          RegExp(r'[A-Z]'), (match) => '_${match[0]!.toLowerCase()}')
      .replaceAll('__', '_');
}
