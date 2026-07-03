import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/data_export_models.dart';
import '../storage_service.dart';
import 'api_service.dart';
import 'browser_file_service.dart';
import 'course_service.dart';
import 'pomodoro_service.dart';

class DataExportService {
  static const int _exportVersion = 1;

  static Future<List<ExportTypeOption>> getAvailableTypes(
      String username) async {
    final todos = await StorageService.getTodos(username);
    final countdowns = await StorageService.getCountdowns(username);
    final groups = await StorageService.getTodoGroups(username);
    final timeLogs = await StorageService.getTimeLogs(username);
    final planBlocks = await StorageService.getPlanBlocks(username);
    final courses = await CourseService.getAllCourses(username);
    final tags = await PomodoroService.getTags();
    final records = await PomodoroService.getRecords();

    return [
      ExportTypeOption(
        key: 'todos',
        label: '待办事项',
        icon: Icons.check_circle_outline,
        count: todos.where((t) => !t.isDeleted).length,
        description: '所有待办任务',
      ),
      ExportTypeOption(
        key: 'countdowns',
        label: '倒计时',
        icon: Icons.timer_outlined,
        count: countdowns.where((c) => !c.isDeleted).length,
        description: '重要日和倒计时',
      ),
      ExportTypeOption(
        key: 'todo_groups',
        label: '待办分组',
        icon: Icons.folder_outlined,
        count: groups.where((g) => !g.isDeleted).length,
        description: '待办的分组和文件夹',
      ),
      ExportTypeOption(
        key: 'time_logs',
        label: '专注记录',
        icon: Icons.hourglass_bottom,
        count: timeLogs.where((t) => !t.isDeleted).length,
        description: '专注时间日志',
      ),
      ExportTypeOption(
        key: 'todo_plan_blocks',
        label: '规划区块',
        icon: Icons.calendar_view_week,
        count: planBlocks.where((b) => !b.isDeleted).length,
        description: '待办规划时间块',
      ),
      ExportTypeOption(
        key: 'courses',
        label: '课表',
        icon: Icons.school_outlined,
        count: courses.where((c) => !c.isDeleted).length,
        description: '课程表数据',
      ),
      ExportTypeOption(
        key: 'pomodoro_tags',
        label: '番茄钟标签',
        icon: Icons.label_outline,
        count: tags.where((t) => !t.isDeleted).length,
        description: '番茄钟和专注标签',
      ),
      ExportTypeOption(
        key: 'pomodoro_records',
        label: '番茄钟记录',
        icon: Icons.timer,
        count: records.where((r) => !r.isDeleted).length,
        description: '番茄钟专注记录',
      ),
      ExportTypeOption(
        key: 'settings',
        label: '偏好设置',
        icon: Icons.settings_outlined,
        count: 1,
        description: '主题、通知、壁纸等应用设置',
      ),
    ];
  }

  static Future<ExportResult> exportData({
    required String username,
    required List<String> selectedTypes,
    required bool saveToFile,
    ExportOptions options = const ExportOptions(),
  }) async {
    try {
      final deviceId = await StorageService.getDeviceId();
      final data = <String, dynamic>{};
      int totalItems = 0;

      if (selectedTypes.contains('todos')) {
        var items =
            await StorageService.getTodos(username, includeDeleted: true);
        if (options.removeTeamBinding) {
          items = items.map((t) {
            t.teamUuid = null;
            t.teamName = null;
            t.creatorId = null;
            t.creatorName = null;
            return t;
          }).toList();
        }
        if (options.removeImagePath) {
          for (var t in items) {
            t.imagePath = null;
          }
        }
        if (options.removeConflictData) {
          for (var t in items) {
            t.hasConflict = false;
            t.serverVersionData = null;
          }
        }
        data['todos'] = items.map((e) => e.toJson()).toList();
        totalItems += items.length;
      }

      if (selectedTypes.contains('countdowns')) {
        var items =
            await StorageService.getCountdowns(username, includeDeleted: true);
        if (options.removeTeamBinding) {
          items = items.map((c) {
            c.teamUuid = null;
            c.teamName = null;
            c.creatorId = null;
            c.creatorName = null;
            return c;
          }).toList();
        }
        if (options.removeConflictData) {
          for (var c in items) {
            c.hasConflict = false;
            c.conflictData = null;
          }
        }
        data['countdowns'] = items.map((e) => e.toJson()).toList();
        totalItems += items.length;
      }

      if (selectedTypes.contains('todo_groups')) {
        var items =
            await StorageService.getTodoGroups(username, includeDeleted: true);
        if (options.removeTeamBinding) {
          items = items.map((g) {
            g.teamUuid = null;
            g.teamName = null;
            g.creatorId = null;
            g.creatorName = null;
            return g;
          }).toList();
        }
        data['todo_groups'] = items.map((e) => e.toJson()).toList();
        totalItems += items.length;
      }

      if (selectedTypes.contains('time_logs')) {
        var items = await StorageService.getTimeLogs(username);
        if (options.removeTeamBinding) {
          for (var l in items) {
            l.teamUuid = null;
          }
        }
        if (options.removeDeviceId) {
          for (var l in items) {
            l.deviceId = null;
          }
        }
        data['time_logs'] = items.map((e) => e.toJson()).toList();
        totalItems += items.length;
      }

      if (selectedTypes.contains('todo_plan_blocks')) {
        var items =
            await StorageService.getPlanBlocks(username, includeDeleted: true);
        if (options.removeDeviceId) {
          for (var b in items) {
            b.deviceId = null;
          }
        }
        data['todo_plan_blocks'] = items.map((e) => e.toJson()).toList();
        totalItems += items.length;
      }

      if (selectedTypes.contains('courses')) {
        var items = await CourseService.getAllCourses(username,
            applyCalendarAdjustments: false);
        if (options.removeTeamBinding) {
          for (var c in items) {
            c.teamUuid = null;
          }
        }
        data['courses'] = items.map((e) => e.toJson()).toList();
        totalItems += items.length;
      }

      if (selectedTypes.contains('pomodoro_tags')) {
        final items = await PomodoroService.getTags();
        if (options.removeConflictData) {
          for (var t in items) {
            t.hasConflict = false;
            t.conflictData = null;
          }
        }
        data['pomodoro_tags'] = items.map((e) => e.toJson()).toList();
        totalItems += items.length;
      }

      if (selectedTypes.contains('pomodoro_records')) {
        final items = await PomodoroService.getRecords();
        if (options.removeDeviceId) {
          for (var r in items) {
            r.deviceId = null;
          }
        }
        if (options.removeConflictData) {
          for (var r in items) {
            r.hasConflict = false;
            r.conflictData = null;
          }
        }
        data['pomodoro_records'] = items.map((e) => e.toJson()).toList();
        totalItems += items.length;
      }

      if (selectedTypes.contains('settings')) {
        data['settings'] = await _exportSettings(username);
        totalItems += 1;
      }

      final exportJson = {
        'version': _exportVersion,
        'exportedAt': DateTime.now().millisecondsSinceEpoch,
        'deviceId': deviceId,
        'userId': ApiService.currentUserId,
        'username': username,
        'selectedTypes': selectedTypes,
        'data': data,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportJson);

      if (saveToFile) {
        final filePath = await BrowserFileService.saveTextFile(
          jsonString,
          _buildExportFileName(),
          mimeType: 'application/json;charset=utf-8',
        );
        return ExportResult(
          success: true,
          filePath: filePath,
          totalItems: totalItems,
        );
      } else {
        await BrowserFileService.shareTextFile(
          jsonString,
          'cdt_backup.json',
          subject: 'CountDownTodo 数据备份',
          mimeType: 'application/json;charset=utf-8',
        );
        return ExportResult(
          success: true,
          totalItems: totalItems,
        );
      }
    } catch (e) {
      // debugPrint('❌ DataExportService: exportData error: $e');
      return ExportResult(
        success: false,
        errorMessage: e.toString(),
        totalItems: 0,
      );
    }
  }

  static String _buildExportFileName() {
    final now = DateTime.now();
    return 'cdt_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.json';
  }

  static Future<Map<String, dynamic>> _exportSettings(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};

    // 获取所有键
    final keys = prefs.getKeys();

    // 排除不需要导出的键（临时数据、缓存、敏感信息）
    final excludedKeys = {
      StorageService.KEY_CURRENT_USER,
      StorageService.KEY_AUTH_TOKEN,
      StorageService.KEY_DEVICE_ID,
      StorageService.KEY_LAST_AUTO_SYNC,
      StorageService.KEY_LAST_SCREEN_TIME_SYNC,
      StorageService.KEY_LAST_MAPPINGS_SYNC,
      StorageService.KEY_PRIVACY_AGREED,
      StorageService.KEY_PRIVACY_DATE,
      StorageService.KEY_PRIVACY_CACHED_VERSION,
      StorageService.KEY_PRIVACY_CACHE_TIME,
      StorageService.KEY_LOCAL_SCREEN_TIME,
      StorageService.KEY_SCREEN_TIME_CACHE,
      StorageService.KEY_USERS,
      StorageService.KEY_LEADERBOARD,
    };

    // 用户特定的键后缀
    final userSuffix = '_$username';

    for (final key in keys) {
      // 跳过排除的键
      if (excludedKeys.contains(key)) continue;

      // 跳过其他用户的数据（包含 _ 且不是当前用户的）
      if (key.contains('_') &&
          !key.startsWith('app_') &&
          !key.startsWith('notify_') &&
          !key.startsWith('todo_') &&
          !key.startsWith('semester_') &&
          !key.startsWith('conflict_') &&
          !key.startsWith('system_') &&
          !key.startsWith('course_') &&
          !key.startsWith('category_') &&
          !key.startsWith('llm_') &&
          !key.startsWith('pending_') &&
          !key.startsWith('windows_')) {
        // 检查是否是用户特定的键
        if (key.endsWith(userSuffix) || key.contains('_default')) {
          // 当前用户的数据，导出时去掉用户后缀
          final baseKey = key.endsWith(userSuffix)
              ? key.substring(0, key.length - userSuffix.length)
              : key;
          final value = prefs.get(key);
          if (value != null) {
            settings[baseKey] = value;
          }
          continue;
        }
        // 跳过其他用户的数据
        if (RegExp(r'_\w+$').hasMatch(key) && !key.endsWith(userSuffix)) {
          continue;
        }
      }

      // 导出设置值
      final value = prefs.get(key);
      if (value != null) {
        settings[key] = value;
      }
    }

    return settings;
  }
}
