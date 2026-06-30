import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../models/data_export_models.dart';
import '../storage_service.dart';
import '../utils/text_file_reader.dart';
import 'api_service.dart';
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
    'settings': '偏好设置',
  };

  // UUID 重映射表
  static final Map<String, String> _uuidRemap = {};
  // 用于确定性 UUID v5 的用户盐值，在 importData 开始时设置
  static String _uuidNamespaceSalt = '';

  /// 使用 UUID v5 确定性重映射，确保同源 UUID 在同一目标账号下始终映射到同一个新 UUID，
  /// 避免重复导入产生重复数据。
  static String _remapUuid(String? oldUuid, {bool shouldRegenerate = false}) {
    if (oldUuid == null || oldUuid.isEmpty) return oldUuid ?? '';
    if (!shouldRegenerate) return oldUuid;

    if (_uuidRemap.containsKey(oldUuid)) {
      return _uuidRemap[oldUuid]!;
    }
    final newUuid =
        const Uuid().v5(Uuid.NAMESPACE_URL, '$_uuidNamespaceSalt|$oldUuid');
    _uuidRemap[oldUuid] = newUuid;
    return newUuid;
  }

  static Future<Set<String>> _getJoinedTeamUuids() async {
    try {
      final teamData = await ApiService.fetchTeams();
      return teamData
          .map((t) => (t['uuid'] ?? t['team_uuid'] ?? '').toString())
          .where((uuid) => uuid.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('⚠️ 获取团队列表失败: $e');
      return {};
    }
  }

  static Future<ImportPreview> parseFile(String filePath) async {
    final jsonString = await readTextFile(filePath);
    return parseJsonString(jsonString);
  }

  static Future<ImportPreview> parseBytes(Uint8List bytes) {
    return parseJsonString(utf8.decode(bytes));
  }

  static Future<ImportPreview> parseJsonString(String jsonString) async {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    final version = json['version'] as int? ?? 1;
    final exportedAt =
        DateTime.fromMillisecondsSinceEpoch(json['exportedAt'] as int? ?? 0);
    final data = json['data'] as Map<String, dynamic>? ?? {};

    final types = <ImportTypePreview>[];
    for (final entry in data.entries) {
      final key = entry.key;
      // settings 是 Map 类型，单独处理
      if (key == 'settings') {
        types.add(ImportTypePreview(
          key: key,
          label: '偏好设置',
          count: 1,
        ));
        continue;
      }
      // 其他数据类型应该是 List
      if (entry.value is List) {
        final items = entry.value as List<dynamic>;
        int teamCount = 0;
        for (final item in items) {
          if (item is Map<String, dynamic>) {
            final teamUuid = item['team_uuid'] ?? item['teamUuid'];
            if (teamUuid != null && teamUuid.toString().isNotEmpty) {
              teamCount++;
            }
          }
        }
        types.add(ImportTypePreview(
          key: key,
          label: _typeLabels[key] ?? key,
          count: items.length,
          teamCount: teamCount,
        ));
      }
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
    ImportOptions options = const ImportOptions(),
  }) async {
    final jsonString = await readTextFile(filePath);
    return importDataFromJsonString(
      username: username,
      jsonString: jsonString,
      options: options,
    );
  }

  static Future<ImportResult> importDataFromJsonString({
    required String username,
    required String jsonString,
    ImportOptions options = const ImportOptions(),
  }) async {
    try {
      // 重置 UUID 重映射，设置用户盐值确保同账号内确定性映射
      _uuidRemap.clear();
      _uuidNamespaceSalt = '${ApiService.currentUserId}_$username';

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>? ?? {};

      // 获取用户当前加入的团队列表
      final joinedTeamUuids = await _getJoinedTeamUuids();
      debugPrint('📋 用户已加入的团队: $joinedTeamUuids');

      // 如果调用方没有显式指定 uuidStrategy，则自动检测
      UuidStrategy uuidStrategy = options.uuidStrategy;
      if (uuidStrategy == UuidStrategy.keepOriginal) {
        // 默认策略：自动检测是否需要重新生成
        final currentDeviceId = await StorageService.getDeviceId();
        final fileDeviceId = json['deviceId']?.toString();
        final fileUsername = json['username']?.toString();
        final fileUserId = json['userId'] as int?;
        final currentUserId = ApiService.currentUserId;

        // 判断逻辑：
        // 1. 优先使用 userId 比较（最可靠）
        // 2. 其次使用 username 比较
        // 3. 都没有则默认同账号
        final bool needRegenerate;
        if (fileUserId != null && fileUserId > 0) {
          // 有 userId，直接比较
          needRegenerate = fileUserId != currentUserId;
        } else if (fileUsername != null) {
          // 没有 userId，用 username 比较
          needRegenerate = fileUsername != username;
        } else {
          // 旧版本导出的文件，保守策略
          needRegenerate = false;
        }

        uuidStrategy = needRegenerate
            ? UuidStrategy.regenerate
            : UuidStrategy.keepOriginal;

        if (needRegenerate) {
          debugPrint(
              '⚠️ 检测到不同账号 (userId: $fileUserId -> $currentUserId)，将重新生成 UUID');
        } else if (fileDeviceId != null && fileDeviceId != currentDeviceId) {
          debugPrint('ℹ️ 检测到同账号不同设备，保留原始 UUID');
        }
      }

      int importedCount = 0;
      int skippedCount = 0;
      int updatedCount = 0;

      if (data.containsKey('todo_groups') && data['todo_groups'] is List) {
        final result = await _importTodoGroups(
          username,
          data['todo_groups'] as List<dynamic>,
          joinedTeamUuids,
          options.teamStrategy,
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('todos') && data['todos'] is List) {
        final result = await _importTodos(
          username,
          data['todos'] as List<dynamic>,
          joinedTeamUuids,
          options.teamStrategy,
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('countdowns') && data['countdowns'] is List) {
        final result = await _importCountdowns(
          username,
          data['countdowns'] as List<dynamic>,
          joinedTeamUuids,
          options.teamStrategy,
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      // pomodoro_tags 必须在 time_logs 和 pomodoro_records 之前导入，
      // 以便 tagUuids 的重映射表 (_uuidRemap) 在相关数据导入时已就绪
      if (data.containsKey('pomodoro_tags') && data['pomodoro_tags'] is List) {
        final result = await _importPomodoroTags(
          data['pomodoro_tags'] as List<dynamic>,
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('time_logs') && data['time_logs'] is List) {
        final result = await _importTimeLogs(
          username,
          data['time_logs'] as List<dynamic>,
          joinedTeamUuids,
          options.teamStrategy,
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('todo_plan_blocks') &&
          data['todo_plan_blocks'] is List) {
        final result = await _importPlanBlocks(
          username,
          data['todo_plan_blocks'] as List<dynamic>,
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('courses') && data['courses'] is List) {
        final result = await _importCourses(
          username,
          data['courses'] as List<dynamic>,
          joinedTeamUuids,
          options.teamStrategy,
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('pomodoro_records') &&
          data['pomodoro_records'] is List) {
        final result = await _importPomodoroRecords(
          data['pomodoro_records'] as List<dynamic>,
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data.containsKey('settings') && data['settings'] is Map) {
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
    Set<String> joinedTeamUuids,
    TeamDataStrategy teamStrategy,
    UuidStrategy uuidStrategy,
  ) async {
    final localGroups =
        await StorageService.getTodoGroups(username, includeDeleted: true);
    final localMap = {for (var g in localGroups) g.id: g};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final group = TodoGroup.fromJson(map);

      // 处理团队数据
      if (group.teamUuid != null && group.teamUuid!.isNotEmpty) {
        if (!joinedTeamUuids.contains(group.teamUuid)) {
          if (teamStrategy == TeamDataStrategy.skip) {
            skipped++;
            continue;
          } else {
            // 转为个人数据
            group.teamUuid = null;
            group.teamName = null;
            group.creatorId = null;
            group.creatorName = null;
          }
        }
      }

      // 处理 UUID
      final oldId = group.id;
      group.id = _remapUuid(oldId, shouldRegenerate: shouldRegenerate);

      // 检查本地是否存在（用原始 ID 或新 ID）
      final existing = localMap[oldId] ?? localMap[group.id];

      if (existing == null) {
        localGroups.add(group);
        imported++;
      } else if (group.updatedAt > existing.updatedAt) {
        final index = localGroups.indexWhere((g) => g.id == existing.id);
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
    Set<String> joinedTeamUuids,
    TeamDataStrategy teamStrategy,
    UuidStrategy uuidStrategy,
  ) async {
    final localTodos =
        await StorageService.getTodos(username, includeDeleted: true);
    final localMap = {for (var t in localTodos) t.id: t};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final todo = TodoItem.fromJson(map);

      // 处理团队数据
      if (todo.teamUuid != null && todo.teamUuid!.isNotEmpty) {
        if (!joinedTeamUuids.contains(todo.teamUuid)) {
          if (teamStrategy == TeamDataStrategy.skip) {
            skipped++;
            continue;
          } else {
            // 转为个人数据
            todo.teamUuid = null;
            todo.teamName = null;
            todo.creatorId = null;
            todo.creatorName = null;
          }
        }
      }

      // 清理冲突数据和图片路径（跨设备无效）
      todo.hasConflict = false;
      todo.serverVersionData = null;
      todo.imagePath = null;

      // 处理 UUID
      final oldId = todo.id;
      todo.id = _remapUuid(oldId, shouldRegenerate: shouldRegenerate);

      // 处理关联的 groupId
      if (todo.groupId != null && _uuidRemap.containsKey(todo.groupId)) {
        todo.groupId = _uuidRemap[todo.groupId];
      }

      // 检查本地是否存在
      final existing = localMap[oldId] ?? localMap[todo.id];

      if (existing == null) {
        localTodos.add(todo);
        imported++;
      } else if (todo.updatedAt > existing.updatedAt) {
        final index = localTodos.indexWhere((t) => t.id == existing.id);
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
    Set<String> joinedTeamUuids,
    TeamDataStrategy teamStrategy,
    UuidStrategy uuidStrategy,
  ) async {
    final localCds =
        await StorageService.getCountdowns(username, includeDeleted: true);
    final localMap = {for (var c in localCds) c.id: c};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final countdown = CountdownItem.fromJson(map);

      // 处理团队数据
      if (countdown.teamUuid != null && countdown.teamUuid!.isNotEmpty) {
        if (!joinedTeamUuids.contains(countdown.teamUuid)) {
          if (teamStrategy == TeamDataStrategy.skip) {
            skipped++;
            continue;
          } else {
            // 转为个人数据
            countdown.teamUuid = null;
            countdown.teamName = null;
            countdown.creatorId = null;
            countdown.creatorName = null;
          }
        }
      }

      // 清理冲突数据
      countdown.hasConflict = false;
      countdown.conflictData = null;

      // 处理 UUID
      final oldId = countdown.id;
      countdown.id = _remapUuid(oldId, shouldRegenerate: shouldRegenerate);

      // 检查本地是否存在
      final existing = localMap[oldId] ?? localMap[countdown.id];

      if (existing == null) {
        localCds.add(countdown);
        imported++;
      } else if (countdown.updatedAt > existing.updatedAt) {
        final index = localCds.indexWhere((c) => c.id == existing.id);
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
    Set<String> joinedTeamUuids,
    TeamDataStrategy teamStrategy,
    UuidStrategy uuidStrategy,
  ) async {
    final localLogs = await StorageService.getTimeLogs(username);
    final localMap = {for (var l in localLogs) l.id: l};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final log = TimeLogItem.fromJson(map);

      // 处理团队数据
      if (log.teamUuid != null && log.teamUuid!.isNotEmpty) {
        if (!joinedTeamUuids.contains(log.teamUuid)) {
          if (teamStrategy == TeamDataStrategy.skip) {
            skipped++;
            continue;
          } else {
            // 转为个人数据
            log.teamUuid = null;
          }
        }
      }

      // 清理设备ID（跨设备无效）
      log.deviceId = null;

      // 处理 UUID
      final oldId = log.id;
      log.id = _remapUuid(oldId, shouldRegenerate: shouldRegenerate);

      // 处理关联的 tagUuids（必须在 pomodoro_tags 导入之后执行）
      if (shouldRegenerate) {
        log.tagUuids = log.tagUuids.map((tagUuid) {
          return _uuidRemap[tagUuid] ?? tagUuid;
        }).toList();
      }

      // 检查本地是否存在
      final existing = localMap[oldId] ?? localMap[log.id];

      if (existing == null) {
        localLogs.add(log);
        imported++;
      } else if (log.updatedAt > existing.updatedAt) {
        final index = localLogs.indexWhere((l) => l.id == existing.id);
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
    UuidStrategy uuidStrategy,
  ) async {
    final localBlocks =
        await StorageService.getPlanBlocks(username, includeDeleted: true);
    final localMap = {for (var b in localBlocks) b.id: b};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final block = TodoPlanBlock.fromJson(map);

      // 清理设备ID（跨设备无效）
      block.deviceId = null;

      // 处理 UUID
      final oldId = block.id;
      block.id = _remapUuid(oldId, shouldRegenerate: shouldRegenerate);

      // 处理关联的 todoId
      if (_uuidRemap.containsKey(block.todoId)) {
        block.todoId = _uuidRemap[block.todoId]!;
      }

      // 检查本地是否存在
      final existing = localMap[oldId] ?? localMap[block.id];

      if (existing == null) {
        localBlocks.add(block);
        imported++;
      } else if (block.updatedAt > existing.updatedAt) {
        final index = localBlocks.indexWhere((b) => b.id == existing.id);
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
    Set<String> joinedTeamUuids,
    TeamDataStrategy teamStrategy,
    UuidStrategy uuidStrategy,
  ) async {
    final localCourses = await CourseService.getAllCourses(
      username,
      applyCalendarAdjustments: false,
    );
    final localMap = {for (var c in localCourses) c.uuid: c};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;

    int imported = 0, skipped = 0, updated = 0;
    final mergedCourses = List<CourseItem>.from(localCourses);

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      var course = CourseItem.fromJson(map);

      // 处理 UUID（课程使用确定性 UUID，重新生成会改变）
      final oldUuid = course.uuid;
      if (shouldRegenerate) {
        // 课程需要特殊处理：uuid 是 final，需修改 JSON 后重建
        final newUuid = _remapUuid(oldUuid, shouldRegenerate: true);
        map['uuid'] = newUuid;
        course = CourseItem.fromJson(map);
      }

      // 处理团队数据
      if (course.teamUuid != null && course.teamUuid!.isNotEmpty) {
        if (!joinedTeamUuids.contains(course.teamUuid)) {
          if (teamStrategy == TeamDataStrategy.skip) {
            skipped++;
            continue;
          } else {
            // 转为个人数据
            course.teamUuid = null;
          }
        }
      }

      // 检查本地是否存在
      final existing = localMap[oldUuid] ?? localMap[course.uuid];

      if (existing == null) {
        mergedCourses.add(course);
        imported++;
      } else if (course.updatedAt > existing.updatedAt) {
        final index = mergedCourses.indexWhere((c) => c.uuid == existing.uuid);
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
    UuidStrategy uuidStrategy,
  ) async {
    final localTags = await PomodoroService.getTags();
    final localMap = {for (var t in localTags) t.uuid: t};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;

    int imported = 0, skipped = 0, updated = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final tag = PomodoroTag.fromJson(map);

      // 清理冲突数据
      tag.hasConflict = false;
      tag.conflictData = null;

      // 处理 UUID
      final oldUuid = tag.uuid;
      tag.uuid = _remapUuid(oldUuid, shouldRegenerate: shouldRegenerate);

      // 检查本地是否存在
      final existing = localMap[oldUuid] ?? localMap[tag.uuid];

      if (existing == null) {
        localTags.add(tag);
        imported++;
      } else if (tag.updatedAt > existing.updatedAt) {
        final index = localTags.indexWhere((t) => t.uuid == existing.uuid);
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
    UuidStrategy uuidStrategy,
  ) async {
    final localRecords = await PomodoroService.getRecords();
    final localMap = {for (var r in localRecords) r.uuid: r};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;

    int imported = 0, skipped = 0, updated = 0;
    final mergedRecords = List<PomodoroRecord>.from(localRecords);

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final record = PomodoroRecord.fromJson(map);

      // 清理设备ID和冲突数据
      record.deviceId = null;
      record.hasConflict = false;
      record.conflictData = null;

      // 处理 UUID
      final oldUuid = record.uuid;
      record.uuid = _remapUuid(oldUuid, shouldRegenerate: shouldRegenerate);

      // 处理关联的 tagUuids
      if (shouldRegenerate) {
        record.tagUuids = record.tagUuids.map((tagUuid) {
          return _uuidRemap[tagUuid] ?? tagUuid;
        }).toList();
      }

      // 检查本地是否存在
      final existing = localMap[oldUuid] ?? localMap[record.uuid];

      if (existing == null) {
        mergedRecords.add(record);
        imported++;
      } else if (record.updatedAt > existing.updatedAt) {
        final index = mergedRecords.indexWhere((r) => r.uuid == existing.uuid);
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
          'conflict_data':
              r.conflictData != null ? jsonEncode(r.conflictData) : null,
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
