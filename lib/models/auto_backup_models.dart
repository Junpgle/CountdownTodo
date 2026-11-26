import 'dart:convert';

import '../utils/time_utils.dart';

/// 定期自动备份配置。
class AutoBackupConfig {
  static const int defaultIntervalDays = 1;
  static const int defaultMaxKeepCount = 7;

  final bool enabled;
  final int intervalDays;
  final int maxKeepCount;
  final String? customDirectory;
  final int? lastBackupAt;
  final String? lastBackupFilePath;
  final String? lastBackupError;

  const AutoBackupConfig({
    this.enabled = false,
    this.intervalDays = defaultIntervalDays,
    this.maxKeepCount = defaultMaxKeepCount,
    this.customDirectory,
    this.lastBackupAt,
    this.lastBackupFilePath,
    this.lastBackupError,
  });

  AutoBackupConfig copyWith({
    bool? enabled,
    int? intervalDays,
    int? maxKeepCount,
    String? customDirectory,
    bool clearCustomDirectory = false,
    int? lastBackupAt,
    String? lastBackupFilePath,
    String? lastBackupError,
    bool clearLastBackupError = false,
  }) {
    return AutoBackupConfig(
      enabled: enabled ?? this.enabled,
      intervalDays: intervalDays ?? this.intervalDays,
      maxKeepCount: maxKeepCount ?? this.maxKeepCount,
      customDirectory: clearCustomDirectory
          ? null
          : (customDirectory ?? this.customDirectory),
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastBackupFilePath: lastBackupFilePath ?? this.lastBackupFilePath,
      lastBackupError: clearLastBackupError
          ? null
          : (lastBackupError ?? this.lastBackupError),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'intervalDays': intervalDays,
      'maxKeepCount': maxKeepCount,
      'customDirectory': customDirectory,
      'lastBackupAt': lastBackupAt,
      'lastBackupFilePath': lastBackupFilePath,
      'lastBackupError': lastBackupError,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory AutoBackupConfig.fromJson(Map<String, dynamic> json) {
    final rawInterval = json['intervalDays'];
    final rawKeep = json['maxKeepCount'];
    final interval = rawInterval is int && rawInterval > 0
        ? rawInterval
        : defaultIntervalDays;
    final keep = rawKeep is int && rawKeep > 0 ? rawKeep : defaultMaxKeepCount;
    final rawDir = json['customDirectory']?.toString().trim();

    return AutoBackupConfig(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      intervalDays: interval,
      maxKeepCount: keep,
      customDirectory: (rawDir == null || rawDir.isEmpty) ? null : rawDir,
      lastBackupAt: json['lastBackupAt'] is int
          ? json['lastBackupAt'] as int
          : int.tryParse(json['lastBackupAt']?.toString() ?? ''),
      lastBackupFilePath: json['lastBackupFilePath']?.toString(),
      lastBackupError: json['lastBackupError']?.toString(),
    );
  }

  factory AutoBackupConfig.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return AutoBackupConfig.fromJson(decoded);
    }
    return const AutoBackupConfig();
  }
}

/// 单个本地自动备份快照条目。
class AutoBackupEntry {
  final String fileName;
  final String filePath;
  final DateTime createdAt;
  final int sizeBytes;

  const AutoBackupEntry({
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.sizeBytes,
  });
}

/// 单次自动/手动备份结果。
class AutoBackupResult {
  final bool success;
  final bool skipped;
  final String? filePath;
  final int totalItems;
  final String? errorMessage;

  const AutoBackupResult({
    required this.success,
    this.skipped = false,
    this.filePath,
    this.totalItems = 0,
    this.errorMessage,
  });
}

/// 纯 Dart 自动备份策略辅助函数。
class AutoBackupPolicy {
  static const String filePrefix = 'cdt_auto_backup_';
  static const String fileExtension = '.json';

  /// 判断当前时间是否应当执行自动备份。
  static bool isBackupDue({
    required AutoBackupConfig config,
    required int nowMs,
  }) {
    if (!config.enabled) return false;
    final lastAt = config.lastBackupAt;
    if (lastAt == null) return true;
    if (nowMs < lastAt) return true;
    final intervalMs = Duration(days: config.intervalDays).inMilliseconds;
    return (nowMs - lastAt) >= intervalMs;
  }

  /// 生成自动备份文件名：`cdt_auto_backup_yyyyMMdd_HHmmss.json`。
  static String buildBackupFileName(DateTime time) {
    return '$filePrefix${AppTimeFormats.fileTimestamp(time)}$fileExtension';
  }

  /// 判断文件名是否属于本功能生成的自动备份文件。
  static bool isAutoBackupFileName(String fileName) {
    return fileName.startsWith(filePrefix) &&
        fileName.endsWith(fileExtension) &&
        !fileName.endsWith('.tmp');
  }

  /// 从按最新到最旧排序的列表中选出需要清理的旧文件。
  static List<T> selectFilesToPrune<T>(
    List<T> sortedNewestFirst,
    int maxKeepCount,
  ) {
    if (maxKeepCount <= 0 || sortedNewestFirst.length <= maxKeepCount) {
      return const [];
    }
    return sortedNewestFirst.sublist(maxKeepCount);
  }

  /// 将用户名清理为安全的单段目录名。
  static String sanitizeUsernameForPath(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return 'default';
    final sanitized = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return sanitized.isEmpty ? 'default' : sanitized;
  }
}
