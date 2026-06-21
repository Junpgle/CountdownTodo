import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models.dart';
import '../database_helper.dart';

typedef TimeLogMigrationSaver = Future<void> Function(
  String username,
  List<TimeLogItem> items, {
  bool sync,
});

class PomodoroStorage {
  const PomodoroStorage._();

  static const String _timeLogsKey = "user_time_logs";

  static Future<void> savePomodoroTags(
    String username,
    List<Map<String, dynamic>> tags,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("pomodoro_tags_$username", jsonEncode(tags));
  }

  static Future<void> saveTimeLogs(
    String username,
    List<TimeLogItem> items, {
    bool sync = true,
    required void Function(String username) requestSync,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final db = await DatabaseHelper.instance.database;
    final Map<String, TimeLogItem> dedupeMap = {};

    for (var item in items) {
      final existing = dedupeMap[item.id];
      if (existing == null ||
          item.version > existing.version ||
          (item.version == existing.version &&
              item.updatedAt > existing.updatedAt)) {
        dedupeMap[item.id] = item;
      }
    }

    final result = dedupeMap.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    final batch = db.batch();
    for (final item in result) {
      batch.insert(
        'time_logs',
        {
          'uuid': item.id,
          'title': item.title,
          'tag_uuids': jsonEncode(item.tagUuids),
          'start_time': item.startTime,
          'end_time': item.endTime,
          'remark': item.remark,
          'is_deleted': item.isDeleted ? 1 : 0,
          'version': item.version,
          'updated_at': item.updatedAt,
          'created_at': item.createdAt,
          'device_id': item.deviceId ?? '',
          'team_uuid': item.teamUuid ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (result.isNotEmpty) {
      await batch.commit(noResult: true);
    }

    await prefs.remove("${_timeLogsKey}_$username");
    await prefs.remove(_timeLogsKey);

    if (sync) requestSync(username);
  }

  static Future<List<TimeLogItem>> getTimeLogs(
    String username, {
    int? limit,
    required TimeLogMigrationSaver saveMigratedTimeLogs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final dbHelper = DatabaseHelper.instance;

    try {
      final String migrationKey = "migrated_timelogs_$username";
      final bool migrated = prefs.getBool(migrationKey) ?? false;

      if (!migrated) {
        List<String> legacyJsonList =
            prefs.getStringList("${_timeLogsKey}_$username") ?? [];
        if (legacyJsonList.isEmpty && username.isNotEmpty) {
          legacyJsonList = prefs.getStringList(_timeLogsKey) ?? [];
        }

        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 发现未迁移专注记录，正在执行迁移...");
          final legacyItems = <TimeLogItem>[];
          for (var e in legacyJsonList) {
            try {
              legacyItems.add(TimeLogItem.fromJson(jsonDecode(e)));
            } catch (_) {}
          }
          await saveMigratedTimeLogs(username, legacyItems, sync: false);
          await prefs.remove("${_timeLogsKey}_$username");
          await prefs.remove(_timeLogsKey);
          debugPrint("✅ 专注记录迁移完成并已物理清理。");
        }
        await prefs.setBool(migrationKey, true);
      } else {
        final db = await dbHelper.database;
        final countRows =
            await db.rawQuery('SELECT COUNT(*) as cnt FROM time_logs');
        final hasSqlRows = (countRows.first['cnt'] as int? ?? 0) > 0;
        final legacyJsonList =
            prefs.getStringList("${_timeLogsKey}_$username") ?? [];
        if (!hasSqlRows && legacyJsonList.isNotEmpty) {
          final legacyItems = <TimeLogItem>[];
          for (final e in legacyJsonList) {
            try {
              legacyItems.add(TimeLogItem.fromJson(jsonDecode(e)));
            } catch (_) {}
          }
          if (legacyItems.isNotEmpty) {
            await saveMigratedTimeLogs(username, legacyItems, sync: false);
            debugPrint("✅ 专注记录从 Prefs 修复回 SQL: ${legacyItems.length} 条");
          }
        }
      }

      final db = await dbHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'time_logs',
        where: 'is_deleted = 0',
        orderBy: 'start_time DESC',
        limit: limit,
      );

      return maps.map(_timeLogFromDbMap).toList();
    } catch (e) {
      debugPrint("⚠️ TimeLogs SQL 异常: $e");
      final list = prefs.getStringList("${_timeLogsKey}_$username") ?? [];
      return list.map((e) => TimeLogItem.fromJson(jsonDecode(e))).toList();
    }
  }

  static TimeLogItem _timeLogFromDbMap(Map<String, dynamic> m) {
    return TimeLogItem(
      id: (m['uuid'] ?? m['id'])?.toString(),
      title: (m['task_name'] ?? m['title'] ?? '').toString(),
      tagUuids: _decodeStringList(m['tag_uuids']),
      startTime: _parseNullableInt(m['start_time']) ?? 0,
      endTime: _parseNullableInt(m['end_time']) ?? 0,
      remark: (m['notes'] ?? m['remark'])?.toString(),
      version: _parseNullableInt(m['version']) ?? 1,
      updatedAt: _parseNullableInt(m['updated_at']) ??
          DateTime.now().millisecondsSinceEpoch,
      createdAt: _parseNullableInt(m['created_at']) ??
          DateTime.now().millisecondsSinceEpoch,
      isDeleted: (m['is_deleted'] == 1),
      deviceId: _emptyToNull(m['device_id']),
      teamUuid: _emptyToNull(m['team_uuid']),
    );
  }

  static List<String> _decodeStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return <String>[];
  }

  static int? _parseNullableInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  static String? _emptyToNull(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }
}
