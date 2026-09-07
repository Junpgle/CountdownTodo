import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../models/data_export_models.dart';
import '../features/finance/services/finance_storage.dart';
import '../features/habits/models/habit_checkin.dart';
import '../features/habits/models/habit_goal.dart';
import '../features/habits/models/habit_goal_rule.dart';
import '../features/habits/models/habit_sleep_coaching_plan.dart';
import '../storage_service.dart';
import '../utils/text_file_reader.dart';
import 'api_service.dart';
import 'course_service.dart';
import 'database_helper.dart';
import 'minor_mode_policy.dart';
import 'minor_mode_service.dart';
import 'pomodoro_service.dart';
import '../features/habits/services/habit_reminder_service.dart';
import 'reminder_schedule_service.dart';
import 'sidebar_menu_service.dart';
import 'storage/habit_storage.dart';

class DataImportService {
  static const Map<String, String> _typeLabels = {
    'todos': '待办事项',
    'countdowns': '倒计时',
    'todo_groups': '待办分组',
    'time_logs': '专注记录',
    'todo_plan_blocks': '规划区块',
    'fixed_schedules': '固定日程',
    'courses': '课表',
    'pomodoro_tags': '番茄钟标签',
    'pomodoro_records': '番茄钟记录',
    'habits': '习惯与睡眠训练',
    'finance': '记账数据',
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
        const Uuid().v5(Namespace.url.value, '$_uuidNamespaceSalt|$oldUuid');
    _uuidRemap[oldUuid] = newUuid;
    return newUuid;
  }

  static String? _remapNullableReference(String? oldUuid) {
    if (oldUuid == null || oldUuid.isEmpty) return null;
    return _uuidRemap[oldUuid];
  }

  static void _validateImportPayload(Map<String, dynamic> data) {
    const listKeys = {
      'todo_groups',
      'todos',
      'countdowns',
      'time_logs',
      'todo_plan_blocks',
      'fixed_schedules',
      'courses',
      'pomodoro_tags',
      'pomodoro_records',
    };
    for (final entry in data.entries) {
      if (entry.key == 'settings' || entry.key == 'finance') {
        if (entry.value is! Map) {
          throw FormatException('${entry.key} 必须是对象');
        }
        continue;
      }
      if (entry.key == 'habits') {
        if (entry.value is! Map) {
          throw const FormatException('habits 必须是对象');
        }
        final bundle = Map<String, dynamic>.from(entry.value as Map);
        for (final key in const [
          'goals',
          'rules',
          'check_ins',
          'sleep_coaching_plans',
        ]) {
          final value = bundle[key];
          if (value != null && value is! List) {
            throw FormatException('habits.$key 必须是数组');
          }
        }
        continue;
      }
      if (listKeys.contains(entry.key)) {
        if (entry.value is! List) {
          throw FormatException('${entry.key} 必须是数组');
        }
        for (final item in entry.value as List) {
          if (item is! Map) {
            throw FormatException('${entry.key} 中包含无效数据项');
          }
        }
      }
    }
  }

  static Future<Set<String>> _getJoinedTeamUuids() async {
    try {
      final teamData = await ApiService.fetchTeams();
      return teamData
          .map((t) => (t['uuid'] ?? t['team_uuid'] ?? '').toString())
          .where((uuid) => uuid.isNotEmpty)
          .toSet();
    } catch (e) {
//       debugPrint('⚠️ 获取团队列表失败: $e');
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

    final version = int.tryParse(json['version']?.toString() ?? '') ?? 1;
    final exportedAt = DateTime.fromMillisecondsSinceEpoch(
      int.tryParse(json['exportedAt']?.toString() ?? '') ?? 0,
    );
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
      if (key == 'finance' && entry.value is Map) {
        final finance = Map<String, dynamic>.from(entry.value as Map);
        final transactions = finance['transactions'];
        final budgets = finance['budgets'];
        final recurringRules = finance['recurring_rules'];
        final templates = finance['templates'];
        final loans = finance['loans'];
        final loanInstallments = finance['loan_installments'];
        types.add(ImportTypePreview(
          key: key,
          label: _typeLabels[key] ?? key,
          count: (transactions is List ? transactions.length : 0) +
              (budgets is List ? budgets.length : 0) +
              (recurringRules is List ? recurringRules.length : 0) +
              (templates is List ? templates.length : 0) +
              (loans is List ? loans.length : 0) +
              (loanInstallments is List ? loanInstallments.length : 0),
        ));
        continue;
      }
      if (key == 'habits' && entry.value is Map) {
        final habits = Map<String, dynamic>.from(entry.value as Map);
        final goals = habits['goals'];
        final rules = habits['rules'];
        final checkIns = habits['check_ins'];
        final sleepPlans = habits['sleep_coaching_plans'];
        types.add(ImportTypePreview(
          key: key,
          label: _typeLabels[key] ?? key,
          count: (goals is List ? goals.length : 0) +
              (rules is List ? rules.length : 0) +
              (checkIns is List ? checkIns.length : 0) +
              (sleepPlans is List ? sleepPlans.length : 0),
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
    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.dataImport,
    );
    if (!authorized) {
      return ImportResult(
        success: false,
        errorMessage: MinorModeService.instance.authorizationFailureMessage(
          MinorModeAction.dataImport,
        ),
        importedCount: 0,
        skippedCount: 0,
        updatedCount: 0,
      );
    }

    _DataImportRollbackSnapshot? rollbackSnapshot;
    try {
      // 重置 UUID 重映射，设置用户盐值确保同账号内确定性映射
      _uuidRemap.clear();
      _uuidNamespaceSalt = '${ApiService.currentUserId}_$username';

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>? ?? {};
      _validateImportPayload(data);

      // 获取用户当前加入的团队列表
      final joinedTeamUuids = await _getJoinedTeamUuids();
//       debugPrint('📋 用户已加入的团队: $joinedTeamUuids');

      // 如果调用方没有显式指定 uuidStrategy，则自动检测
      UuidStrategy uuidStrategy = options.uuidStrategy;
      if (uuidStrategy == UuidStrategy.keepOriginal) {
        // 默认策略：自动检测是否需要重新生成
        final currentDeviceId = await StorageService.getDeviceId();
        final fileDeviceId = json['deviceId']?.toString();
        final fileUsername = json['username']?.toString();
        final fileUserId = int.tryParse(json['userId']?.toString() ?? '');
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
//           debugPrint(
//               '⚠️ 检测到不同账号 (userId: $fileUserId -> $currentUserId)，将重新生成 UUID');
        } else if (fileDeviceId != null && fileDeviceId != currentDeviceId) {
//           debugPrint('ℹ️ 检测到同账号不同设备，保留原始 UUID');
        }
      }

      int importedCount = 0;
      int skippedCount = 0;
      int updatedCount = 0;
      rollbackSnapshot = await _DataImportRollbackSnapshot.capture();

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

      if (data.containsKey('fixed_schedules') &&
          data['fixed_schedules'] is List) {
        final result = await _importFixedSchedules(
          username,
          data['fixed_schedules'] as List<dynamic>,
          joinedTeamUuids,
          options.teamStrategy,
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

      if (data['habits'] is Map) {
        final result = await _importHabits(
          Map<String, dynamic>.from(data['habits'] as Map),
          uuidStrategy,
        );
        importedCount += result['imported']!;
        skippedCount += result['skipped']!;
        updatedCount += result['updated']!;
      }

      if (data['finance'] is Map) {
        final result = await FinanceStorage.importBundle(
          Map<String, dynamic>.from(data['finance'] as Map),
          remapUuid: (uuid) => _remapUuid(
            uuid,
            shouldRegenerate: uuidStrategy == UuidStrategy.regenerate,
          ),
        );
        importedCount += result['imported'] ?? 0;
        skippedCount += result['skipped'] ?? 0;
        updatedCount += result['updated'] ?? 0;
      }

      if (data.containsKey('settings') && data['settings'] is Map) {
        await _importSettings(
          data['settings'] as Map<String, dynamic>,
          username: username,
        );
        importedCount += 1;
      }

      // Imported todos, courses, fixed schedules, finance rules and habits
      // all feed the reminder registry. Refresh it after the data write, but
      // keep notification failures from turning a successful data import into
      // a rollback-worthy error.
      try {
        await ReminderScheduleService.scheduleCurrentUser();
        await HabitReminderService.rescheduleAll();
      } catch (error) {
        debugPrint('⚠️ 数据导入后刷新提醒失败: $error');
      }

      StorageService.triggerRefresh();

      return ImportResult(
        success: true,
        importedCount: importedCount,
        skippedCount: skippedCount,
        updatedCount: updatedCount,
      );
    } catch (e) {
//       debugPrint('❌ DataImportService: importData error: $e');
      if (rollbackSnapshot != null) {
        try {
          await rollbackSnapshot.restore();
        } catch (restoreError) {
          debugPrint('❌ DataImportService rollback failed: $restoreError');
        }
      }
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
      final existing = shouldRegenerate
          ? localMap[group.id]
          : localMap[oldId] ?? localMap[group.id];

      if (existing == null) {
        localGroups.add(group);
        localMap[group.id] = group;
        imported++;
      } else if (group.updatedAt > existing.updatedAt) {
        final index = localGroups.indexWhere((g) => g.id == existing.id);
        if (index != -1) {
          localGroups[index] = group;
          localMap[group.id] = group;
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
      if (todo.recurrenceSeriesId?.isNotEmpty == true) {
        todo.recurrenceSeriesId = _remapUuid(
          todo.recurrenceSeriesId,
          shouldRegenerate: shouldRegenerate,
        );
      }

      // 处理关联的 groupId
      if (shouldRegenerate && todo.groupId?.isNotEmpty == true) {
        todo.groupId = _uuidRemap[todo.groupId];
      }

      // 检查本地是否存在
      final existing = shouldRegenerate
          ? localMap[todo.id]
          : localMap[oldId] ?? localMap[todo.id];

      if (existing == null) {
        localTodos.add(todo);
        localMap[todo.id] = todo;
        imported++;
      } else if (todo.updatedAt > existing.updatedAt) {
        final index = localTodos.indexWhere((t) => t.id == existing.id);
        if (index != -1) {
          localTodos[index] = todo;
          localMap[todo.id] = todo;
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
      final existing = shouldRegenerate
          ? localMap[countdown.id]
          : localMap[oldId] ?? localMap[countdown.id];

      if (existing == null) {
        localCds.add(countdown);
        localMap[countdown.id] = countdown;
        imported++;
      } else if (countdown.updatedAt > existing.updatedAt) {
        final index = localCds.indexWhere((c) => c.id == existing.id);
        if (index != -1) {
          localCds[index] = countdown;
          localMap[countdown.id] = countdown;
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
        log.tagUuids = log.tagUuids
            .map((tagUuid) {
              return _uuidRemap[tagUuid];
            })
            .whereType<String>()
            .toList();
      }

      // 检查本地是否存在
      final existing = shouldRegenerate
          ? localMap[log.id]
          : localMap[oldId] ?? localMap[log.id];

      if (existing == null) {
        localLogs.add(log);
        localMap[log.id] = log;
        imported++;
      } else if (log.updatedAt > existing.updatedAt) {
        final index = localLogs.indexWhere((l) => l.id == existing.id);
        if (index != -1) {
          localLogs[index] = log;
          localMap[log.id] = log;
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
      if (block.todoId.isNotEmpty) {
        block.todoId = _remapUuid(
          block.todoId,
          shouldRegenerate: shouldRegenerate,
        );
      }

      // 检查本地是否存在
      final existing = shouldRegenerate
          ? localMap[block.id]
          : localMap[oldId] ?? localMap[block.id];

      if (existing == null) {
        localBlocks.add(block);
        localMap[block.id] = block;
        imported++;
      } else if (block.updatedAt > existing.updatedAt) {
        final index = localBlocks.indexWhere((b) => b.id == existing.id);
        if (index != -1) {
          localBlocks[index] = block;
          localMap[block.id] = block;
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
      final existing = shouldRegenerate
          ? localMap[course.uuid]
          : localMap[oldUuid] ?? localMap[course.uuid];

      if (existing == null) {
        mergedCourses.add(course);
        localMap[course.uuid] = course;
        imported++;
      } else if (course.updatedAt > existing.updatedAt) {
        final index = mergedCourses.indexWhere((c) => c.uuid == existing.uuid);
        if (index != -1) {
          mergedCourses[index] = course;
          localMap[course.uuid] = course;
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

  static Future<Map<String, int>> _importFixedSchedules(
    String username,
    List<dynamic> items,
    Set<String> joinedTeamUuids,
    TeamDataStrategy teamStrategy,
    UuidStrategy uuidStrategy,
  ) async {
    final localItems = await StorageService.getFixedSchedules(
      username,
      includeDeleted: true,
    );
    final localMap = {for (final item in localItems) item.id: item};
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;
    var imported = 0;
    var skipped = 0;
    var updated = 0;

    for (final raw in items) {
      final item = FixedScheduleItem.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      item.deviceId = null;

      if (item.teamUuid?.isNotEmpty == true &&
          !joinedTeamUuids.contains(item.teamUuid)) {
        if (teamStrategy == TeamDataStrategy.skip) {
          skipped++;
          continue;
        }
        item.teamUuid = null;
      }

      final oldId = item.id;
      item.id = _remapUuid(oldId, shouldRegenerate: shouldRegenerate);
      if (item.recurrenceSeriesId?.isNotEmpty == true) {
        item.recurrenceSeriesId = _remapUuid(
          item.recurrenceSeriesId,
          shouldRegenerate: shouldRegenerate,
        );
      }
      if (shouldRegenerate) {
        item.relatedTodoIds = item.relatedTodoIds
            .map((id) => _uuidRemap[id])
            .whereType<String>()
            .toList(growable: false);
      }

      final existing = shouldRegenerate
          ? localMap[item.id]
          : localMap[oldId] ?? localMap[item.id];
      if (existing == null) {
        localItems.add(item);
        localMap[item.id] = item;
        imported++;
      } else if (item.updatedAt > existing.updatedAt) {
        final index = localItems.indexWhere((value) => value.id == existing.id);
        if (index >= 0) {
          localItems[index] = item;
          localMap[item.id] = item;
          updated++;
        }
      } else {
        skipped++;
      }
    }

    if (imported > 0 || updated > 0) {
      await StorageService.saveFixedSchedules(username, localItems);
    }
    return {'imported': imported, 'skipped': skipped, 'updated': updated};
  }

  static Future<Map<String, int>> _importHabits(
    Map<String, dynamic> bundle,
    UuidStrategy uuidStrategy,
  ) async {
    final shouldRegenerate = uuidStrategy == UuidStrategy.regenerate;
    final rawGoals = bundle['goals'] is List
        ? bundle['goals'] as List<dynamic>
        : const <dynamic>[];
    final rawRules = bundle['rules'] is List
        ? bundle['rules'] as List<dynamic>
        : const <dynamic>[];
    final rawCheckIns = bundle['check_ins'] is List
        ? bundle['check_ins'] as List<dynamic>
        : const <dynamic>[];
    final rawSleepPlans = bundle['sleep_coaching_plans'] is List
        ? bundle['sleep_coaching_plans'] as List<dynamic>
        : const <dynamic>[];

    var imported = 0;
    var skipped = 0;
    var updated = 0;

    final localGoals = await HabitStorage.getHabitGoals(includeDeleted: true);
    final localGoalsById = {for (final goal in localGoals) goal.uuid: goal};
    for (final raw in rawGoals) {
      final goal = HabitGoal.fromJson(Map<String, dynamic>.from(raw as Map));
      final oldUuid = goal.uuid;
      goal.uuid = _remapUuid(oldUuid, shouldRegenerate: shouldRegenerate);
      goal.sourceIds = goal.sourceIds
          .map((id) => _remapUuid(id, shouldRegenerate: shouldRegenerate))
          .toList(growable: false);
      goal.currentRuleUuid = goal.currentRuleUuid == null
          ? null
          : _remapUuid(
              goal.currentRuleUuid,
              shouldRegenerate: shouldRegenerate,
            );
      goal.deviceId = null;
      goal.hasConflict = false;
      goal.conflictData = null;

      final existing = shouldRegenerate
          ? localGoalsById[goal.uuid]
          : localGoalsById[oldUuid] ?? localGoalsById[goal.uuid];
      if (existing == null) {
        localGoals.add(goal);
        localGoalsById[goal.uuid] = goal;
        imported++;
      } else if (goal.updatedAt > existing.updatedAt) {
        final index = localGoals.indexOf(existing);
        if (index >= 0) {
          localGoals[index] = goal;
          localGoalsById[goal.uuid] = goal;
          updated++;
        }
      } else {
        skipped++;
      }
    }
    if (imported > 0 || updated > 0) {
      await HabitStorage.saveHabitGoals(localGoals);
    }

    final localRules =
        await HabitStorage.getRuleRevisions(includeDeleted: true);
    final localRulesById = {for (final rule in localRules) rule.uuid: rule};
    for (final raw in rawRules) {
      final rule = HabitGoalRuleRevision.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      final oldUuid = rule.uuid;
      rule.uuid = _remapUuid(oldUuid, shouldRegenerate: shouldRegenerate);
      rule.habitUuid = _remapUuid(
        rule.habitUuid,
        shouldRegenerate: shouldRegenerate,
      );
      rule.deviceId = null;
      rule.hasConflict = false;
      rule.conflictData = null;

      final existing = shouldRegenerate
          ? localRulesById[rule.uuid]
          : localRulesById[oldUuid] ?? localRulesById[rule.uuid];
      if (existing == null) {
        localRules.add(rule);
        localRulesById[rule.uuid] = rule;
        imported++;
      } else if (rule.updatedAt > existing.updatedAt) {
        final index = localRules.indexOf(existing);
        if (index >= 0) {
          localRules[index] = rule;
          localRulesById[rule.uuid] = rule;
          updated++;
        }
      } else {
        skipped++;
      }
    }
    if (rawRules.isNotEmpty && (imported > 0 || updated > 0)) {
      await HabitStorage.saveRuleRevisions(localRules);
    }

    final localCheckIns = await HabitStorage.getCheckIns(includeDeleted: true);
    final localCheckInsById = {
      for (final checkIn in localCheckIns) checkIn.uuid: checkIn,
    };
    for (final raw in rawCheckIns) {
      final checkIn = HabitCheckIn.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      final oldUuid = checkIn.uuid;
      checkIn.uuid = _remapUuid(oldUuid, shouldRegenerate: shouldRegenerate);
      if (shouldRegenerate) {
        final remappedHabitUuid = _uuidRemap[checkIn.habitUuid];
        if (remappedHabitUuid == null) {
          skipped++;
          continue;
        }
        checkIn.habitUuid = remappedHabitUuid;
        checkIn.ruleRevisionUuid = _remapNullableReference(
          checkIn.ruleRevisionUuid,
        );
      }
      checkIn.deviceId = null;

      final existing = shouldRegenerate
          ? localCheckInsById[checkIn.uuid]
          : localCheckInsById[oldUuid] ?? localCheckInsById[checkIn.uuid];
      if (existing == null) {
        localCheckIns.add(checkIn);
        localCheckInsById[checkIn.uuid] = checkIn;
        imported++;
      } else if (checkIn.updatedAt > existing.updatedAt) {
        final index = localCheckIns.indexOf(existing);
        if (index >= 0) {
          localCheckIns[index] = checkIn;
          localCheckInsById[checkIn.uuid] = checkIn;
          updated++;
        }
      } else {
        skipped++;
      }
    }
    if (rawCheckIns.isNotEmpty && (imported > 0 || updated > 0)) {
      await HabitStorage.saveCheckIns(localCheckIns);
    }

    final localSleepPlans =
        await HabitStorage.getSleepCoachingPlans(includeDeleted: true);
    final localSleepPlansById = {
      for (final plan in localSleepPlans) plan.uuid: plan,
    };
    for (final raw in rawSleepPlans) {
      final plan = HabitSleepCoachingPlan.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      final oldUuid = plan.uuid;
      plan.uuid = _remapUuid(oldUuid, shouldRegenerate: shouldRegenerate);
      plan.deviceId = null;

      final existing = shouldRegenerate
          ? localSleepPlansById[plan.uuid]
          : localSleepPlansById[oldUuid] ?? localSleepPlansById[plan.uuid];
      if (existing == null) {
        localSleepPlans.add(plan);
        localSleepPlansById[plan.uuid] = plan;
        imported++;
      } else if (plan.updatedAt > existing.updatedAt) {
        final index = localSleepPlans.indexOf(existing);
        if (index >= 0) {
          localSleepPlans[index] = plan;
          localSleepPlansById[plan.uuid] = plan;
          updated++;
        }
      } else {
        skipped++;
      }
    }
    if (rawSleepPlans.isNotEmpty && (imported > 0 || updated > 0)) {
      await HabitStorage.saveSleepCoachingPlans(localSleepPlans);
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
      final existing = shouldRegenerate
          ? localMap[tag.uuid]
          : localMap[oldUuid] ?? localMap[tag.uuid];

      if (existing == null) {
        localTags.add(tag);
        localMap[tag.uuid] = tag;
        imported++;
      } else if (tag.updatedAt > existing.updatedAt) {
        final index = localTags.indexWhere((t) => t.uuid == existing.uuid);
        if (index != -1) {
          localTags[index] = tag;
          localMap[tag.uuid] = tag;
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

      if (shouldRegenerate) {
        record.todoUuid = _remapNullableReference(record.todoUuid);
        record.planBlockId = _remapNullableReference(record.planBlockId);
      }

      // 处理关联的 tagUuids
      if (shouldRegenerate) {
        record.tagUuids = record.tagUuids
            .map((tagUuid) {
              return _uuidRemap[tagUuid];
            })
            .whereType<String>()
            .toList();
      }

      // 检查本地是否存在
      final existing = shouldRegenerate
          ? localMap[record.uuid]
          : localMap[oldUuid] ?? localMap[record.uuid];

      if (existing == null) {
        mergedRecords.add(record);
        localMap[record.uuid] = record;
        imported++;
      } else if (record.updatedAt > existing.updatedAt) {
        final index = mergedRecords.indexWhere((r) => r.uuid == existing.uuid);
        if (index != -1) {
          mergedRecords[index] = record;
          localMap[record.uuid] = record;
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

  static Future<void> _importSettings(
    Map<String, dynamic> settings, {
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    for (final entry in settings.entries) {
      final key = entry.key;
      final value = entry.value;

      // 跳过敏感信息
      if (key == StorageService.keyAuthToken ||
          key == StorageService.keyDeviceId ||
          key == StorageService.keyCurrentUser) {
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
      StorageService.keyTodos,
      StorageService.keyTodoGroups,
      StorageService.keyCountdowns,
      StorageService.keyTimeLogs,
      StorageService.keySettings,
      StorageService.keyScreenTimeHistory,
      StorageService.keyAppMappings,
      StorageService.keyIgnoredScheduleConflicts,
      StorageService.keyConflictDetectionEnabled,
      StorageService.keySyncInterval,
      StorageService.keySemesterStart,
      StorageService.keySemesterEnd,
      StorageService.keySemesters,
      StorageService.keyActiveSemester,
    };

    return keysNeedingSuffix.contains(key) ||
        SidebarMenuService.isUserSpecificKey(key);
  }
}

/// Import writes are made through several storage facades, each of which
/// owns its own batch/transaction. A single outer sqflite transaction cannot
/// safely wrap those facades, so keep a database + preference snapshot and
/// restore it if any later phase fails. The snapshot is taken only after all
/// payload shape and account-preparation checks have completed.
final class _DataImportRollbackSnapshot {
  final Map<String, List<Map<String, Object?>>> _tables;
  final Map<String, Object?> _preferences;

  _DataImportRollbackSnapshot(this._tables, this._preferences);

  static Future<_DataImportRollbackSnapshot> capture() async {
    final db = await DatabaseHelper.instance.database;
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
      "AND (sql IS NULL OR UPPER(sql) NOT LIKE 'CREATE VIRTUAL TABLE%')",
    );
    final tables = <String, List<Map<String, Object?>>>{};
    for (final row in tableRows) {
      final name = row['name']?.toString();
      if (name == null || name.isEmpty) continue;
      tables[name] = await db.query(name);
    }

    final prefs = await SharedPreferences.getInstance();
    final preferences = <String, Object?>{
      for (final key in prefs.getKeys()) key: prefs.get(key),
    };
    return _DataImportRollbackSnapshot(tables, preferences);
  }

  Future<void> restore() async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      for (final table in _tables.keys.toList().reversed) {
        await txn.delete(table);
      }
      for (final entry in _tables.entries) {
        for (final row in entry.value) {
          await txn.insert(
            entry.key,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final currentKeys = prefs.getKeys();
    for (final key in currentKeys.difference(_preferences.keys.toSet())) {
      await prefs.remove(key);
    }
    for (final entry in _preferences.entries) {
      final value = entry.value;
      if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is List) {
        await prefs.setStringList(
          entry.key,
          value.map((item) => item.toString()).toList(growable: false),
        );
      }
    }
  }
}
