import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models.dart';
import '../models/data_export_models.dart';
import '../storage_service.dart';
import 'course_service.dart';
import 'database_helper.dart';
import 'pomodoro_service.dart';

class DataImportService {
  static const Map<String, String> _typeLabels = {
    'todos': '待办事项',
    'countdowns': '倒计时',
    'todo_groups': '待办分组',
    'time_logs': '专注记录',
    'todo_plan_blocks': '规划区块',
    'courses': '课表',
    'pomodoro_tags': '番茄钟标签',
    'pomodoro_records': '番茄钟记录',
  };

  static Future<ImportPreview> parseFile(String filePath) async {
    final file = File(filePath);
    final jsonString = await file.readAsString();
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    final version = json['version'] as int? ?? 1;
    final exportedAt = DateTime.fromMillisecondsSinceEpoch(
        json['exportedAt'] as int? ?? 0);
    final data = json['data'] as Map<String, dynamic>? ?? {};

    final types = <ImportTypePreview>[];
    for (final entry in data.entries) {
      final key = entry.key;
      final items = entry.value as List<dynamic>? ?? [];
      types.add(ImportTypePreview(
        key: key,
        label: _typeLabels[key] ?? key,
        count: items.length,
      ));
    }

    return ImportPreview(
      fileVersion: version,
      exportedAt: exportedAt,
      types: types,
    );
  }

  static Future<ImportResult> importData({
    required String username,
    required String filePath,
  }) async {
    try {
      final file = File(filePath);
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>? ?? {};

      int importedCount = 0;
      int skippedCount = 0;
      int updatedCount = 0;

      if (data.containsKey('todo_groups')) {
        final result = await _importTodoGroups(
          username,
          data['todo_groups'] as List<dynamic>,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('todos')) {
        final result = await _importTodos(
          username,
          data['todos'] as List<dynamic>,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('countdowns')) {
        final result = await _importCountdowns(
          username,
          data['countdowns'] as List<dynamic>,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('time_logs')) {
        final result = await _importTimeLogs(
          username,
          data['time_logs'] as List<dynamic>,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('todo_plan_blocks')) {
        final result = await _importPlanBlocks(
          username,
          data['todo_plan_blocks'] as List<dynamic>,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('courses')) {
        final result = await _importCourses(
          username,
          data['courses'] as List<dynamic>,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('pomodoro_tags')) {
        final result = await _importPomodoroTags(
          data['pomodoro_tags'] as List<dynamic>,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('pomodoro_records')) {
        final result = await _importPomodoroRecords(
          data['pomodoro_records'] as List<dynamic>,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('settings')) {
        await _importSettings(data['settings'] as Map<String, dynamic>);
        importedCount += 1;
      }

      StorageService.triggerRefresh();

      return ImportResult(
        success: true,
        importedCount: importedCount,
        skippedCount: skippedCount,
        updatedCount: updatedCount,
      );
    } catch (e) {
      debugPrint('❌ DataImportService: importData error: $e');
      return ImportResult(
        success: false,
        errorMessage: e.toString(),
        importedCount: 0,
        skippedCount: 0,
        updatedCount: 0,
      );
    }
  }

  static Future<Map<String, int>> _importTodoGroups(
    String username,
    List<dynamic> items,
  ) async {
    final localGroups = await StorageService.getTodoGroups(username, includeDeleted: true);
    final localMap = {for (var g in localGroups) g.id: g};

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final group = TodoGroup.fromJson(map);
      final existing = localMap[group.id];

      if (existing == null) {
        localGroups.add(group);
        imported++;
      } else if (group.updatedAt > existing.updatedAt) {
        final index = localGroups.indexWhere((g) => g.id == group.id);
        if (index != -1) {
          localGroups[index] = group;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await StorageService.saveTodoGroups(username, localGroups, sync: false);
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<Map<String, int>> _importTodos(
    String username,
    List<dynamic> items,
  ) async {
    final localTodos = await StorageService.getTodos(username, includeDeleted: true);
    final localMap = {for (var t in localTodos) t.id: t};

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final todo = TodoItem.fromJson(map);
      final existing = localMap[todo.id];

      if (existing == null) {
        localTodos.add(todo);
        imported++;
      } else if (todo.updatedAt > existing.updatedAt) {
        final index = localTodos.indexWhere((t) => t.id == todo.id);
        if (index != -1) {
          localTodos[index] = todo;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await StorageService.saveTodos(username, localTodos, sync: false);
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<Map<String, int>> _importCountdowns(
    String username,
    List<dynamic> items,
  ) async {
    final localCds = await StorageService.getCountdowns(username, includeDeleted: true);
    final localMap = {for (var c in localCds) c.id: c};

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final countdown = CountdownItem.fromJson(map);
      final existing = localMap[countdown.id];

      if (existing == null) {
        localCds.add(countdown);
        imported++;
      } else if (countdown.updatedAt > existing.updatedAt) {
        final index = localCds.indexWhere((c) => c.id == countdown.id);
        if (index != -1) {
          localCds[index] = countdown;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await StorageService.saveCountdowns(username, localCds, sync: false);
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<Map<String, int>> _importTimeLogs(
    String username,
    List<dynamic> items,
  ) async {
    final localLogs = await StorageService.getTimeLogs(username);
    final localMap = {for (var l in localLogs) l.id: l};

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final log = TimeLogItem.fromJson(map);
      final existing = localMap[log.id];

      if (existing == null) {
        localLogs.add(log);
        imported++;
      } else if (log.updatedAt > existing.updatedAt) {
        final index = localLogs.indexWhere((l) => l.id == log.id);
        if (index != -1) {
          localLogs[index] = log;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await StorageService.saveTimeLogs(username, localLogs, sync: false);
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<Map<String, int>> _importPlanBlocks(
    String username,
    List<dynamic> items,
  ) async {
    final localBlocks = await StorageService.getPlanBlocks(username, includeDeleted: true);
    final localMap = {for (var b in localBlocks) b.id: b};

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final block = TodoPlanBlock.fromJson(map);
      final existing = localMap[block.id];

      if (existing == null) {
        localBlocks.add(block);
        imported++;
      } else if (block.updatedAt > existing.updatedAt) {
        final index = localBlocks.indexWhere((b) => b.id == block.id);
        if (index != -1) {
          localBlocks[index] = block;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await StorageService.savePlanBlocks(username, localBlocks, sync: false);
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<Map<String, int>> _importCourses(
    String username,
    List<dynamic> items,
  ) async {
    final localCourses = await CourseService.getAllCourses(
      username,
      applyCalendarAdjustments: false,
    );
    final localMap = {for (var c in localCourses) c.uuid: c};

    int imported = 0, skipped = 0, updated = 0;
    final mergedCourses = List<CourseItem>.from(localCourses);

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final course = CourseItem.fromJson(map);
      final existing = localMap[course.uuid];

      if (existing == null) {
        mergedCourses.add(course);
        imported++;
      } else if (course.updatedAt > existing.updatedAt) {
        final index = mergedCourses.indexWhere((c) => c.uuid == course.uuid);
        if (index != -1) {
          mergedCourses[index] = course;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await CourseService.saveCourses(username, mergedCourses);
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<Map<String, int>> _importPomodoroTags(
    List<dynamic> items,
  ) async {
    final localTags = await PomodoroService.getTags();
    final localMap = {for (var t in localTags) t.uuid: t};

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final tag = PomodoroTag.fromJson(map);
      final existing = localMap[tag.uuid];

      if (existing == null) {
        localTags.add(tag);
        imported++;
      } else if (tag.updatedAt > existing.updatedAt) {
        final index = localTags.indexWhere((t) => t.uuid == tag.uuid);
        if (index != -1) {
          localTags[index] = tag;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await PomodoroService.saveTags(localTags);
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<Map<String, int>> _importPomodoroRecords(
    List<dynamic> items,
  ) async {
    final localRecords = await PomodoroService.getRecords();
    final localMap = {for (var r in localRecords) r.uuid: r};

    int imported = 0, skipped = 0, updated = 0;
    final mergedRecords = List<PomodoroRecord>.from(localRecords);

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final record = PomodoroRecord.fromJson(map);
      final existing = localMap[record.uuid];

      if (existing == null) {
        mergedRecords.add(record);
        imported++;
      } else if (record.updatedAt > existing.updatedAt) {
        final index = mergedRecords.indexWhere((r) => r.uuid == record.uuid);
        if (index != -1) {
          mergedRecords[index] = record;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await _savePomodoroRecords(mergedRecords);
    }

    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<void> _savePomodoroRecords(List<PomodoroRecord> records) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final r in records) {
      batch.insert(
        'pomodoro_records',
        {
          'uuid': r.uuid,
          'todo_uuid': r.todoUuid,
          'todo_title': r.todoTitle,
          'tag_uuids': jsonEncode(r.tagUuids),
          'start_time': r.startTime,
          'end_time': r.endTime,
          'planned_duration': r.plannedDuration,
          'actual_duration': r.actualDuration,
          'status': r.status == PomodoroRecordStatus.completed
              ? 'completed'
              : r.status == PomodoroRecordStatus.interrupted
                  ? 'interrupted'
                  : 'switched',
          'device_id': r.deviceId,
          'plan_block_id': r.planBlockId,
          'note': r.note,
          'is_deleted': r.isDeleted ? 1 : 0,
          'version': r.version,
          'created_at': r.createdAt,
          'updated_at': r.updatedAt,
          'has_conflict': r.hasConflict ? 1 : 0,
          'conflict_data': r.conflictData != null ? jsonEncode(r.conflictData) : null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (records.isNotEmpty) {
      await batch.commit(noResult: true);
    }
  }

  static Future<void> _importSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';

    for (final entry in settings.entries) {
      final key = entry.key;
      final value = entry.value;

      // 跳过敏感信息
      if (key == StorageService.KEY_AUTH_TOKEN || 
          key == StorageService.KEY_DEVICE_ID ||
          key == StorageService.KEY_CURRENT_USER) {
        continue;
      }

      // 处理用户特定的键（需要添加用户后缀）
      String targetKey = key;
      if (_isUserSpecificKey(key)) {
        targetKey = '${key}_$username';
      }

      // 根据值类型保存
      if (value is bool) {
        await prefs.setBool(targetKey, value);
      } else if (value is int) {
        await prefs.setInt(targetKey, value);
      } else if (value is double) {
        await prefs.setDouble(targetKey, value);
      } else if (value is String) {
        await prefs.setString(targetKey, value);
      } else if (value is List) {
        // 尝试作为字符串列表保存
        try {
          final stringList = value.map((e) => e.toString()).toList();
          await prefs.setStringList(targetKey, stringList);
        } catch (_) {
          // 如果失败，序列化为 JSON 字符串
          await prefs.setString(targetKey, jsonEncode(value));
        }
      } else if (value is Map) {
        // 序列化为 JSON 字符串
        await prefs.setString(targetKey, jsonEncode(value));
      }
    }

    // 触发主题刷新
    StorageService.initTheme();

    // 触发壁纸刷新
    StorageService.triggerWallpaperRefresh();
  }

  static bool _isUserSpecificKey(String key) {
    // 这些键是用户特定的，需要添加用户后缀
    final userSpecificKeys = {
      'history_',
      'pomodoro_tags_',
      'category_reminder_minutes_',
      'ignored_schedule_conflicts_',
    };

    for (final prefix in userSpecificKeys) {
      if (key.startsWith(prefix)) return true;
    }

    // 这些键名本身就是用户特定的（在 StorageService 中会自动加后缀）
    final keysNeedingSuffix = {
      StorageService.KEY_TODOS,
      StorageService.KEY_TODO_GROUPS,
      StorageService.KEY_COUNTDOWNS,
      StorageService.KEY_TIME_LOGS,
      StorageService.KEY_SETTINGS,
      StorageService.KEY_SCREEN_TIME_HISTORY,
      StorageService.KEY_APP_MAPPINGS,
      StorageService.KEY_IGNORED_SCHEDULE_CONFLICTS,
      StorageService.KEY_CONFLICT_DETECTION_ENABLED,
      StorageService.KEY_SYNC_INTERVAL,
    };

    return keysNeedingSuffix.contains(key);
  }
}
