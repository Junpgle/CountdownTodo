import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage_service.dart';
import 'course_service.dart';
import 'pomodoro_service.dart';
import '../models.dart';

class MigrationProgress {
  final String stage;
  final double progress; 
  final bool isCompleted;
  final List<String> errors;
  final int totalSuccess;

  MigrationProgress({
    required this.stage,
    required this.progress,
    this.isCompleted = false,
    this.errors = const [],
    this.totalSuccess = 0,
  });
}

class LocalMigrationService {
  static const String KEY_MIGRATION_COMPLETED_V4 = 'migration_completed_v4';

  static Future<bool> needsMigration() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(KEY_MIGRATION_COMPLETED_V4) ?? false) return false;

    final keys = prefs.getKeys();
    final legacyKeys = [
      'todo_list',
      'countdown_list',
      'course_data',
      'time_logs',
      'pomodoro_tags',
      'pomodoro_records'
    ];

    for (var key in keys) {
      if (legacyKeys.any((lk) => key.contains(lk))) {
        return true;
      }
    }

    return false;
  }

  static Stream<MigrationProgress> performMigration(String username) async* {
    List<String> errors = [];
    int totalSuccess = 0;

    yield MigrationProgress(stage: '正在准备本地引擎升级...', progress: 0.1, errors: errors);
    final prefs = await SharedPreferences.getInstance();
    await Future.delayed(const Duration(milliseconds: 500));

    // 1. 迁移待办事项
    yield MigrationProgress(stage: '正在迁移待办事项...', progress: 0.2, errors: errors);
    try {
      List<String> legacyTodos = prefs.getStringList("todo_list_$username") ?? 
                                prefs.getStringList("todo_list") ?? [];
      List<TodoItem> items = [];
      for (var jsonStr in legacyTodos) {
        try {
          items.add(TodoItem.fromJson(jsonDecode(jsonStr)));
          totalSuccess++;
        } catch (e) {
          errors.add("待办解析失败: ${jsonStr.substring(0, jsonStr.length > 20 ? 20 : jsonStr.length)}... ($e)");
        }
      }
      if (items.isNotEmpty) {
        await StorageService.saveTodos(username, items, sync: true, isSyncSource: false);
      }
    } catch (e) {
      errors.add("待办迁移致命错误: $e");
    }
    yield MigrationProgress(stage: '待办迁移完成', progress: 0.3, errors: errors, totalSuccess: totalSuccess);

    // 2. 迁移倒计时
    yield MigrationProgress(stage: '正在迁移倒计时...', progress: 0.4, errors: errors);
    try {
      List<String> legacyCDs = prefs.getStringList("countdown_list_$username") ?? 
                              prefs.getStringList("countdown_list") ?? [];
      List<CountdownItem> items = [];
      for (var jsonStr in legacyCDs) {
        try {
          items.add(CountdownItem.fromJson(jsonDecode(jsonStr)));
          totalSuccess++;
        } catch (e) {
          errors.add("倒计时解析失败: ${jsonStr.substring(0, jsonStr.length > 20 ? 20 : jsonStr.length)}... ($e)");
        }
      }
      if (items.isNotEmpty) {
        await StorageService.saveCountdowns(username, items, sync: true, isSyncSource: false);
      }
    } catch (e) {
      errors.add("倒计时迁移致命错误: $e");
    }
    yield MigrationProgress(stage: '倒计时迁移完成', progress: 0.5, errors: errors, totalSuccess: totalSuccess);

    // 3. 其他静默迁移 (保持原逻辑)
    yield MigrationProgress(stage: '正在迁移文件夹...', progress: 0.6, errors: errors);
    await StorageService.getTodoGroups(username, includeDeleted: true);
    
    yield MigrationProgress(stage: '正在迁移时间日志...', progress: 0.75, errors: errors);
    await StorageService.getTimeLogs(username);

    yield MigrationProgress(stage: '正在迁移课表与专注数据...', progress: 0.9, errors: errors);
    await CourseService.getAllCourses(username);
    await PomodoroService.getTags();

    await prefs.setBool(KEY_MIGRATION_COMPLETED_V4, true);
    yield MigrationProgress(stage: '本地升级完成！', progress: 1.0, isCompleted: true, errors: errors, totalSuccess: totalSuccess);
  }
}
