import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models.dart';
import '../database_helper.dart';
import 'storage_conflict_cleanup.dart';

typedef CountdownChangeChecker = bool Function(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
  List<String> fields,
);

typedef CountdownAuditRecorder = Future<void> Function(
  String table,
  String uuid,
  Map<String, dynamic> afterData,
  String? teamUuid,
  Map<String, dynamic>? existingData,
);

typedef CountdownMigrationSaver = Future<void> Function(
  String username,
  List<CountdownItem> items, {
  bool sync,
  bool isSyncSource,
});

class CountdownStorage {
  CountdownStorage._();

  static const String _countdownsKey = "user_countdowns";

  static Future<void> saveCountdowns(
    String username,
    List<CountdownItem> items, {
    bool sync = true,
    bool isSyncSource = false,
    required CountdownChangeChecker hasSubstantialChange,
    required CountdownAuditRecorder recordLocalAudit,
    required void Function(String username) requestSync,
    void Function()? onCommitted,
  }) async {
    final Map<String, CountdownItem> dedupeMap = {};
    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final dedupeList = dedupeMap.values.toList();

    // SQL 已是主存储，清理旧 Prefs 镜像，避免全量倒计时 JSON
    // 通过 shared_preferences MethodChannel 触发 Android OOM。
    unawaited(_clearCountdownPrefsMirror(username));

    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;

    Map<String, Map<String, dynamic>> existingItemsMap = {};
    if (!isSyncSource && dedupeList.isNotEmpty) {
      final uuids = dedupeList.map((e) => "'${e.id}'").join(',');
      final List<Map<String, dynamic>> existing =
          await db.rawQuery('SELECT * FROM countdowns WHERE uuid IN ($uuids)');
      for (var row in existing) {
        existingItemsMap[row['uuid']] = row;
      }
    }

    final batch = db.batch();
    for (var item in dedupeList) {
      bool hasChanged = true;
      final itemData = item.toJson();
      final oldData = existingItemsMap[item.id];
      if (oldData != null) {
        hasChanged = hasSubstantialChange(oldData, itemData, [
          'title',
          'target_time',
          'is_deleted',
          'is_completed',
          'team_uuid',
          'version',
          'updated_at'
        ]);
      }

      if (!isSyncSource && hasChanged) {
        unawaited(recordLocalAudit(
          'countdowns',
          item.id,
          itemData,
          item.teamUuid,
          oldData,
        ));

        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'countdowns',
          'target_uuid': item.id,
          'data_json': jsonEncode(itemData),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }

      if (hasChanged || oldData == null) {
        batch.insert(
          'countdowns',
          {
            'uuid': item.id,
            'team_uuid': item.teamUuid,
            'team_name': item.teamName,
            'creator_id': item.creatorId,
            'creator_name': item.creatorName,
            'title': item.title,
            'target_time': item.targetDate.millisecondsSinceEpoch,
            'is_deleted': item.isDeleted ? 1 : 0,
            'is_completed': item.isCompleted ? 1 : 0,
            'version': item.version,
            'updated_at': item.updatedAt,
            'created_at': item.createdAt,
            'has_conflict': item.hasConflict ? 1 : 0,
            'conflict_data': item.conflictData != null
                ? jsonEncode(item.conflictData)
                : null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    if (dedupeList.isNotEmpty) {
      await batch.commit(noResult: true);
      onCommitted?.call();
    }

    if (sync) requestSync(username);
  }

  static Future<List<CountdownItem>> getCountdowns(
    String username, {
    bool includeDeleted = false,
    required CountdownMigrationSaver saveMigratedCountdowns,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      await StorageConflictCleanup.clearGhostConflictFlags(db);

      final String migrationKey = "migrated_countdowns_$username";
      final bool alreadyMigrated = prefs.getBool(migrationKey) ?? false;

      final List<Map<String, dynamic>> sqliteCount =
          await db.rawQuery('SELECT COUNT(*) as cnt FROM countdowns');
      if (sqliteCount.first['cnt'] == 0) {
        List<String> legacyJsonList =
            prefs.getStringList("${_countdownsKey}_$username") ?? [];

        if (!alreadyMigrated && legacyJsonList.isEmpty && username.isNotEmpty) {
          final String markerKey = "${_countdownsKey}_${username}_migrated";
          if (!(prefs.getBool(markerKey) ?? false)) {
            legacyJsonList = prefs.getStringList(_countdownsKey) ?? [];
            if (legacyJsonList.isNotEmpty) {
              await prefs.setBool(markerKey, true);
            }
          }
        }

        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 自动迁移倒数日老数据至 SQLite...");
          final legacyData = legacyJsonList
              .map((e) => CountdownItem.fromJson(jsonDecode(e)))
              .toList();
          await saveMigratedCountdowns(
            username,
            legacyData,
            sync: false,
            isSyncSource: true,
          );
          await prefs.remove("${_countdownsKey}_$username");
          await prefs.remove(_countdownsKey);
          debugPrint("✅ 倒数日老数据迁移完成并已物理清理。");
        }
        if (legacyJsonList.isNotEmpty && alreadyMigrated) {
          debugPrint("✅ 倒数日从 Prefs 修复回 SQL: ${legacyJsonList.length} 条");
        }
        await prefs.setBool(migrationKey, true);
      } else if (alreadyMigrated) {
        await prefs.remove("${_countdownsKey}_$username");
        await prefs.remove(_countdownsKey);
      }

      final List<Map<String, dynamic>> maps = await db.query(
        'countdowns',
        where: includeDeleted ? null : 'is_deleted = 0',
      );

      if (maps.isNotEmpty) {
        if (maps.length > 50) {
          return await compute(_parseCountdownItemsIsolate, maps);
        }

        return maps.map(_countdownFromDbMap).toList();
      }
    } catch (e) {
      debugPrint("⚠️ Countdowns SQL 引擎异常: $e");
    }

    final list = prefs.getStringList("${_countdownsKey}_$username") ?? [];

    if (list.length > 50) {
      return await compute(_parseCountdownJsonItemsIsolate, list);
    }

    final result = <CountdownItem>[];
    for (var e in list) {
      try {
        result.add(CountdownItem.fromJson(jsonDecode(e)));
      } catch (_) {}
    }
    return result;
  }

  static Future<void> _clearCountdownPrefsMirror(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("${_countdownsKey}_$username");
    await prefs.remove(_countdownsKey);
  }

  static CountdownItem _countdownFromDbMap(Map<String, dynamic> m) {
    return CountdownItem(
      id: m['uuid'],
      title: m['title'] ?? '',
      targetDate: DateTime.fromMillisecondsSinceEpoch(m['target_time']),
      isDeleted: m['is_deleted'] == 1,
      isCompleted: m['is_completed'] == 1,
      version: m['version'] ?? 1,
      updatedAt: m['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
      createdAt: m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      teamUuid: m['team_uuid'],
      teamName: m['team_name'],
      creatorId: m['creator_id'],
      creatorName: m['creator_name'],
      hasConflict: m['has_conflict'] == 1,
      conflictData:
          m['conflict_data'] != null ? jsonDecode(m['conflict_data']) : null,
    );
  }

  static List<CountdownItem> _parseCountdownItemsIsolate(
      List<Map<String, dynamic>> maps) {
    return maps.map(_countdownFromDbMap).toList();
  }

  static List<CountdownItem> _parseCountdownJsonItemsIsolate(
      List<String> jsonList) {
    return jsonList
        .map((e) {
          try {
            return CountdownItem.fromJson(jsonDecode(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<CountdownItem>()
        .toList();
  }
}
