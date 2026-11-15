import '../models/auto_backup_models.dart';

/// Web 端不支持静默写入本地文件系统，提供安全空实现。
class AutoBackupService {
  static bool get isSupported => false;

  static Future<AutoBackupConfig> getConfig({String? username}) async {
    return const AutoBackupConfig(enabled: false);
  }

  static Future<void> saveConfig(
    AutoBackupConfig config, {
    String? username,
  }) async {}

  static Future<String> resolveBackupDirectoryPath({
    AutoBackupConfig? config,
    String? username,
  }) async {
    return '';
  }

  static Future<AutoBackupResult> runBackupIfDue({String? username}) async {
    return const AutoBackupResult(success: true, skipped: true);
  }

  static Future<AutoBackupResult> performBackupNow({String? username}) async {
    return const AutoBackupResult(
      success: false,
      errorMessage: 'Web 端不支持本地自动备份，请使用手动数据导出',
    );
  }

  static Future<List<AutoBackupEntry>> listBackups({String? username}) async {
    return const [];
  }

  static Future<bool> deleteBackup(String filePath) async => false;

  static Future<String?> readBackupContent(String filePath) async => null;
}
