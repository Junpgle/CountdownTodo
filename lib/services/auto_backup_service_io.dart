import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auto_backup_models.dart';
import '../models/data_export_models.dart';
import '../storage_service.dart';
import 'data_export_service.dart';

/// 本地定期自动备份服务（Android / iOS / macOS / Windows / Linux）。
class AutoBackupService {
  static const String _configKeyPrefix = 'auto_backup_config_';
  static bool _isRunning = false;
  static int _lastCheckAtMs = 0;

  static bool get isSupported => true;

  static String _configKey(String username) {
    final safeUser = AutoBackupPolicy.sanitizeUsernameForPath(username);
    return '$_configKeyPrefix$safeUser';
  }

  static Future<String?> _resolveUsername(String? username) async {
    if (username != null && username.trim().isNotEmpty) {
      return username.trim();
    }
    final session = await StorageService.getLoginSession();
    if (session == null || session.trim().isEmpty) return null;
    return session.trim();
  }

  static Future<AutoBackupConfig> getConfig({String? username}) async {
    final user = await _resolveUsername(username);
    if (user == null) return const AutoBackupConfig();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey(user));
    if (raw == null || raw.isEmpty) return const AutoBackupConfig();
    try {
      return AutoBackupConfig.fromJsonString(raw);
    } catch (_) {
      return const AutoBackupConfig();
    }
  }

  static Future<void> saveConfig(
    AutoBackupConfig config, {
    String? username,
  }) async {
    final user = await _resolveUsername(username);
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey(user), config.toJsonString());
  }

  static Future<Directory> _resolveDefaultDirectory(String username) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final safeUser = AutoBackupPolicy.sanitizeUsernameForPath(username);
    return Directory(
      p.join(docsDir.path, 'CountdownTodo', 'auto_backups', safeUser),
    );
  }

  static Future<String> resolveBackupDirectoryPath({
    AutoBackupConfig? config,
    String? username,
  }) async {
    final user = await _resolveUsername(username) ?? 'default';
    final effectiveConfig = config ?? await getConfig(username: user);
    final customDir = effectiveConfig.customDirectory?.trim();
    if (customDir != null && customDir.isNotEmpty) {
      return customDir;
    }
    final dir = await _resolveDefaultDirectory(user);
    return dir.path;
  }

  /// 检查是否到达备份周期，若到期则静默执行一次全量备份。
  static Future<AutoBackupResult> runBackupIfDue({String? username}) async {
    if (_isRunning) {
      return const AutoBackupResult(success: true, skipped: true);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastCheckAtMs < 60 * 1000) {
      return const AutoBackupResult(success: true, skipped: true);
    }
    _lastCheckAtMs = nowMs;

    final user = await _resolveUsername(username);
    if (user == null) {
      return const AutoBackupResult(success: true, skipped: true);
    }

    final config = await getConfig(username: user);
    if (!AutoBackupPolicy.isBackupDue(config: config, nowMs: nowMs)) {
      return const AutoBackupResult(success: true, skipped: true);
    }

    return performBackupNow(username: user);
  }

  /// 立即执行一次全量本地备份，并按保留策略清理旧快照。
  static Future<AutoBackupResult> performBackupNow({String? username}) async {
    if (_isRunning) {
      return const AutoBackupResult(
        success: false,
        skipped: true,
        errorMessage: '正在执行备份，请稍候',
      );
    }

    _isRunning = true;
    String? resolvedUser;
    AutoBackupConfig currentConfig = const AutoBackupConfig();

    try {
      resolvedUser = await _resolveUsername(username);
      if (resolvedUser == null) {
        return const AutoBackupResult(
          success: false,
          skipped: true,
          errorMessage: '未登录账号，无法执行备份',
        );
      }

      currentConfig = await getConfig(username: resolvedUser);
      final dirPath = await resolveBackupDirectoryPath(
        config: currentConfig,
        username: resolvedUser,
      );
      final targetDir = Directory(dirPath);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final bundle = await DataExportService.buildExportJson(
        username: resolvedUser,
        selectedTypes: DataExportService.allExportTypeKeys,
        options: const ExportOptions(
          removeDeviceId: false,
          removeConflictData: false,
        ),
      );

      final now = DateTime.now();
      var fileName = AutoBackupPolicy.buildBackupFileName(now);
      var targetFile = File(p.join(targetDir.path, fileName));
      if (await targetFile.exists()) {
        fileName =
            '${AutoBackupPolicy.filePrefix}${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_${now.millisecond.toString().padLeft(3, '0')}${AutoBackupPolicy.fileExtension}';
        targetFile = File(p.join(targetDir.path, fileName));
      }

      // 原子写入：先写临时文件，再重命名，避免写入中断留下损坏的 JSON。
      final tempFile = File('${targetFile.path}.tmp');
      await tempFile.writeAsString(bundle.jsonString, flush: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      await _pruneOldBackups(targetDir, currentConfig.maxKeepCount);

      final updatedConfig = currentConfig.copyWith(
        lastBackupAt: now.millisecondsSinceEpoch,
        lastBackupFilePath: targetFile.path,
        clearLastBackupError: true,
      );
      await saveConfig(updatedConfig, username: resolvedUser);

      return AutoBackupResult(
        success: true,
        filePath: targetFile.path,
        totalItems: bundle.totalItems,
      );
    } catch (e) {
      if (resolvedUser != null) {
        await saveConfig(
          currentConfig.copyWith(lastBackupError: e.toString()),
          username: resolvedUser,
        );
      }
      return AutoBackupResult(success: false, errorMessage: e.toString());
    } finally {
      _isRunning = false;
    }
  }

  static Future<void> _pruneOldBackups(Directory dir, int maxKeepCount) async {
    final entries = await _readBackupEntriesFromDir(dir);
    final toDelete = AutoBackupPolicy.selectFilesToPrune(entries, maxKeepCount);
    for (final entry in toDelete) {
      try {
        final file = File(entry.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // 单个旧快照删除失败不影响主流程。
      }
    }
  }

  static Future<List<AutoBackupEntry>> listBackups({String? username}) async {
    final user = await _resolveUsername(username);
    if (user == null) return const [];
    final config = await getConfig(username: user);
    final dirPath = await resolveBackupDirectoryPath(
      config: config,
      username: user,
    );
    final dir = Directory(dirPath);
    if (!await dir.exists()) return const [];
    return _readBackupEntriesFromDir(dir);
  }

  static Future<List<AutoBackupEntry>> _readBackupEntriesFromDir(
    Directory dir,
  ) async {
    final entries = <AutoBackupEntry>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!AutoBackupPolicy.isAutoBackupFileName(name)) continue;
        final stat = await entity.stat();
        entries.add(
          AutoBackupEntry(
            fileName: name,
            filePath: entity.path,
            createdAt: stat.modified,
            sizeBytes: stat.size,
          ),
        );
      }
    } catch (_) {
      return const [];
    }

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  static Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> readBackupContent(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }
}
