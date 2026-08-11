import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/habits/models/habit_checkin.dart';
import '../../features/habits/models/habit_goal.dart';
import '../../features/habits/models/habit_goal_rule.dart';
import '../../features/habits/models/habit_sleep_coaching_plan.dart';
import '../database_helper.dart';

/// 习惯模块的 SQL 存取层。
///
/// 与固定日程一致，采用独立表 + oplog 写入；
/// 云同步接入（PR5）后向 op_logs 写入记录，由同步引擎消费。
abstract final class HabitStorage {
  /// 是否写入同步操作日志。云同步 PR5 已接入，置为 true。
  static const bool writeOplog = true;

  static const String tableGoals = 'habit_goals';
  static const String tableRules = 'habit_goal_rule_revisions';
  static const String tableCheckIns = 'habit_checkins';
  static const String tableSleepCoachingPlans = 'habit_sleep_coaching_plans';

  static const List<String> goalChangeColumns = [
    'name',
    'icon',
    'source_type',
    'source_ids',
    'current_rule_uuid',
    'display_mode',
    'default_focus_minutes',
    'sort_order',
    'is_archived',
    'is_deleted',
    'version',
    'device_id',
    'created_at',
    'updated_at',
    'has_conflict',
    'conflict_data',
  ];

  static const List<String> ruleChangeColumns = [
    'effective_from_date',
    'effective_to_date',
    'period_type',
    'weekdays_mask',
    'custom_interval_days',
    'target_value',
    'unit',
    'target_time_minute',
    'time_comparison',
    'time_tolerance_minutes',
    'day_boundary_minute',
    'quick_values_json',
    'reminder_policy_json',
    'is_deleted',
    'version',
    'device_id',
    'created_at',
    'updated_at',
    'has_conflict',
    'conflict_data',
  ];

  static const List<String> checkInChangeColumns = [
    'habit_uuid',
    'rule_revision_uuid',
    'occurred_at',
    'logical_date',
    'timezone_offset_minutes',
    'value',
    'note',
    'source',
    'dedupe_key',
    'is_deleted',
    'version',
    'device_id',
    'created_at',
    'updated_at',
  ];

  static const List<String> sleepCoachingPlanChangeColumns = [
    'kind',
    'enabled',
    'paused',
    'step_minutes',
    'stage_days',
    'started_logical_date',
    'baseline_bedtime_minute',
    'baseline_wake_minute',
    'baseline_sleep_minutes',
    'paused_stage_index',
    'paused_progress_days',
    'paused_logical_date',
    'timezone_offset_minutes',
    'is_deleted',
    'version',
    'device_id',
    'created_at',
    'updated_at',
  ];

  // ── 查询 ─────────────────────────────────────────────

  static Future<List<HabitGoal>> getHabitGoals({
    bool includeDeleted = false,
    bool includeArchived = true,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final where = <String>[];
      if (!includeDeleted) where.add('is_deleted = 0');
      if (!includeArchived) where.add('is_archived = 0');
      final maps = await db.query(
        tableGoals,
        where: where.isEmpty ? null : where.join(' AND '),
        orderBy: 'is_archived ASC, sort_order ASC, created_at ASC',
      );
      return maps.map(HabitGoal.fromJson).toList();
    } catch (e) {
      debugPrint('⚠️ HabitStorage 读取习惯目标失败: $e');
      return [];
    }
  }

  static Future<List<HabitGoalRuleRevision>> getRuleRevisions({
    String? habitUuid,
    bool includeDeleted = true,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final where = <String>[];
      final args = <Object?>[];
      if (habitUuid != null) {
        where.add('habit_uuid = ?');
        args.add(habitUuid);
      }
      if (!includeDeleted) {
        where.add('is_deleted = 0');
      }
      final maps = await db.query(
        tableRules,
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'effective_from_date ASC, created_at ASC',
      );
      return maps.map(HabitGoalRuleRevision.fromJson).toList();
    } catch (e) {
      debugPrint('⚠️ HabitStorage 读取习惯规则失败: $e');
      return [];
    }
  }

  static Future<List<HabitCheckIn>> getCheckIns({
    String? habitUuid,
    String? fromDate,
    String? toDate,
    bool includeDeleted = false,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final where = <String>[];
      final args = <Object?>[];
      if (habitUuid != null) {
        where.add('habit_uuid = ?');
        args.add(habitUuid);
      }
      if (!includeDeleted) {
        where.add('is_deleted = 0');
      }
      if (fromDate != null) {
        where.add('logical_date >= ?');
        args.add(fromDate);
      }
      if (toDate != null) {
        where.add('logical_date <= ?');
        args.add(toDate);
      }
      final maps = await db.query(
        tableCheckIns,
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'occurred_at DESC',
      );
      return maps.map(HabitCheckIn.fromJson).toList();
    } catch (e) {
      debugPrint('⚠️ HabitStorage 读取习惯打卡失败: $e');
      return [];
    }
  }

  static Future<List<HabitSleepCoachingPlan>> getSleepCoachingPlans({
    bool includeDeleted = false,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        tableSleepCoachingPlans,
        where: includeDeleted ? null : 'is_deleted = 0',
        orderBy: 'updated_at DESC',
      );
      return maps.map(HabitSleepCoachingPlan.fromJson).toList();
    } catch (e) {
      debugPrint('⚠️ HabitStorage 读取睡眠训练计划失败: $e');
      return [];
    }
  }

  // ── 写入 ─────────────────────────────────────────────

  static Future<void> saveHabitGoals(
    List<HabitGoal> items, {
    bool isSyncSource = false,
  }) async {
    if (items.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final existing = await _rowsById(db, tableGoals, items.map((e) => e.uuid));
    final batch = db.batch();
    var wroteAny = false;
    for (final item in items) {
      final data = item.toJson();
      final old = existing[item.uuid];
      if (old != null && !_hasSubstantialChange(old, data, goalChangeColumns)) {
        continue;
      }
      wroteAny = true;
      if (writeOplog && !isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': tableGoals,
          'target_uuid': item.uuid,
          'data_json': jsonEncode(data),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }
      batch.insert(
        tableGoals,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (wroteAny) await batch.commit(noResult: true);
  }

  static Future<void> saveRuleRevisions(
    List<HabitGoalRuleRevision> items, {
    bool isSyncSource = false,
  }) async {
    if (items.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final existing = await _rowsById(db, tableRules, items.map((e) => e.uuid));
    final batch = db.batch();
    var wroteAny = false;
    for (final item in items) {
      final data = item.toJson();
      final old = existing[item.uuid];
      if (old != null && !_hasSubstantialChange(old, data, ruleChangeColumns)) {
        continue;
      }
      wroteAny = true;
      if (writeOplog && !isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': tableRules,
          'target_uuid': item.uuid,
          'data_json': jsonEncode(data),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }
      batch.insert(
        tableRules,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (wroteAny) await batch.commit(noResult: true);
  }

  static Future<void> saveCheckIns(
    List<HabitCheckIn> items, {
    bool isSyncSource = false,
  }) async {
    if (items.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final keyedItems = <String, HabitCheckIn>{};
    final unkeyedItems = <HabitCheckIn>[];
    bool isNewer(HabitCheckIn incoming, HabitCheckIn current) {
      return incoming.updatedAt > current.updatedAt ||
          (incoming.updatedAt == current.updatedAt &&
              incoming.version > current.version) ||
          (incoming.updatedAt == current.updatedAt &&
              incoming.version == current.version &&
              incoming.uuid.compareTo(current.uuid) > 0);
    }

    for (final item in items) {
      final key = item.dedupeKey;
      if (key == null || key.isEmpty) {
        unkeyedItems.add(item);
        continue;
      }
      final current = keyedItems[key];
      if (current == null || isNewer(item, current)) keyedItems[key] = item;
    }
    final itemsToSave = [...unkeyedItems, ...keyedItems.values];
    final existing =
        await _rowsById(db, tableCheckIns, itemsToSave.map((e) => e.uuid));
    final dedupeKeys = itemsToSave
        .map((item) => item.dedupeKey)
        .whereType<String>()
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final existingByDedupe = <String, Map<String, dynamic>>{};
    if (dedupeKeys.isNotEmpty) {
      final placeholders = List.filled(dedupeKeys.length, '?').join(',');
      final rows = await db.query(
        tableCheckIns,
        where: 'dedupe_key IN ($placeholders)',
        whereArgs: dedupeKeys,
      );
      for (final row in rows) {
        final key = row['dedupe_key']?.toString();
        if (key != null && key.isNotEmpty) existingByDedupe[key] = row;
      }
    }
    final batch = db.batch();
    var wroteAny = false;
    for (final item in itemsToSave) {
      final data = item.toJson();
      final oldByDedupe =
          item.dedupeKey == null ? null : existingByDedupe[item.dedupeKey!];
      if (oldByDedupe != null && oldByDedupe['uuid'] != item.uuid) {
        final oldUpdatedAt =
            int.tryParse(oldByDedupe['updated_at']?.toString() ?? '') ?? 0;
        final oldVersion =
            int.tryParse(oldByDedupe['version']?.toString() ?? '') ?? 0;
        final incomingWins = item.updatedAt > oldUpdatedAt ||
            (item.updatedAt == oldUpdatedAt && item.version > oldVersion) ||
            (item.updatedAt == oldUpdatedAt &&
                item.version == oldVersion &&
                item.uuid.compareTo(oldByDedupe['uuid'].toString()) > 0);
        if (!incomingWins) continue;
        // 保留本地 canonical UUID，防止旧服务端返回重复事件时产生新身份。
        data['uuid'] = oldByDedupe['uuid'];
      }
      final old = existing[item.uuid] ?? oldByDedupe;
      if (old != null &&
          !_hasSubstantialChange(old, data, checkInChangeColumns)) {
        continue;
      }
      wroteAny = true;
      if (writeOplog && !isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': tableCheckIns,
          'target_uuid': data['uuid']?.toString() ?? item.uuid,
          'data_json': jsonEncode(data),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }
      batch.insert(
        tableCheckIns,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (wroteAny) await batch.commit(noResult: true);
  }

  static Future<void> saveSleepCoachingPlans(
    List<HabitSleepCoachingPlan> items, {
    bool isSyncSource = false,
  }) async {
    if (items.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final existing =
        await _rowsById(db, tableSleepCoachingPlans, items.map((e) => e.uuid));
    final batch = db.batch();
    var wroteAny = false;
    for (final item in items) {
      final data = item.toJson();
      final old = existing[item.uuid];
      if (old != null &&
          !_hasSubstantialChange(old, data, sleepCoachingPlanChangeColumns)) {
        continue;
      }
      wroteAny = true;
      if (writeOplog && !isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': tableSleepCoachingPlans,
          'target_uuid': item.uuid,
          'data_json': jsonEncode(data),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }
      batch.insert(
        tableSleepCoachingPlans,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (wroteAny) await batch.commit(noResult: true);
  }

  // ── 工具 ─────────────────────────────────────────────

  static Future<Map<String, Map<String, dynamic>>> _rowsById(
    Database db,
    String table,
    Iterable<String> ids,
  ) async {
    final idList = ids.toList();
    if (idList.isEmpty) return {};
    final placeholders = List.filled(idList.length, '?').join(',');
    final rows = await db.query(
      table,
      where: 'uuid IN ($placeholders)',
      whereArgs: idList,
    );
    return {for (final row in rows) row['uuid'].toString(): row};
  }

  static bool _hasSubstantialChange(
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
    List<String> columns,
  ) {
    for (final column in columns) {
      final oldValue = oldData[column];
      final newValue = newData[column];
      if (oldValue == newValue) continue;
      if (oldValue == null && newValue == null) continue;
      if (oldValue is num &&
          newValue is num &&
          oldValue.toDouble() == newValue.toDouble()) {
        continue;
      }
      return true;
    }
    return false;
  }
}
