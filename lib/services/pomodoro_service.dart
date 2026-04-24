import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:CountDownTodo/services/database_helper.dart';
import '../storage_service.dart';
import 'api_service.dart';

// ============================================================
// 番茄钟数据模型（对齐数据库 pomodoro_tags 表）
// ============================================================

class PomodoroTag {
  String uuid;
  String name;
  String color;
  bool isDeleted;
  int version;
  int createdAt; // UTC ms
  int updatedAt; // UTC ms

  PomodoroTag({
    String? uuid,
    required this.name,
    this.color = '#607D8B',
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
  })  : uuid = uuid ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 序列化：供 API 上传和本地存储使用
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'name': name,
        'color': color,
        'is_deleted': isDeleted ? 1 : 0,
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory PomodoroTag.fromJson(Map<String, dynamic> j) => PomodoroTag(
        uuid: j['uuid']?.toString() ?? const Uuid().v4(),
        name: j['name']?.toString() ?? '',
        color: j['color']?.toString() ?? '#607D8B',
        isDeleted: j['is_deleted'] == 1 || j['is_deleted'] == true,
        version: j['version'] as int? ?? 1,
        createdAt: _ms(j['created_at']),
        updatedAt: _ms(j['updated_at']),
      );

  static int _ms(dynamic v) {
    if (v == null) return DateTime.now().millisecondsSinceEpoch;
    if (v is int) return v;
    if (v is double) return v.toInt();
    final n = int.tryParse(v.toString().trim());
    if (n != null) return n;
    return DateTime.now().millisecondsSinceEpoch;
  }
}

// ============================================================
// 番茄钟专注记录（对齐数据库 pomodoro_records 表）
// ============================================================

/// status 对应数据库 CHECK 约束的三个值
enum PomodoroRecordStatus { completed, interrupted, switched }

class PomodoroRecord {
  String uuid;
  String? todoUuid; // 关联 todos.uuid
  String? todoTitle; // 冗余存储（便于离线显示）
  List<String> tagUuids; // 通过 todo_tags 关联，本地缓存用
  int startTime; // UTC ms
  int? endTime; // UTC ms
  int plannedDuration; // 计划专注时长（秒）
  int? actualDuration; // 实际专注时长（秒）
  PomodoroRecordStatus status;
  String? deviceId;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;

  PomodoroRecord({
    String? uuid,
    this.todoUuid,
    this.todoTitle,
    List<String>? tagUuids,
    required this.startTime,
    this.endTime,
    required this.plannedDuration,
    this.actualDuration,
    this.status = PomodoroRecordStatus.completed,
    this.deviceId,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
  })  : uuid = uuid ?? const Uuid().v4(),
        tagUuids = tagUuids ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 实际有效的专注秒数（优先用 actualDuration）
  int get effectiveDuration => actualDuration ?? plannedDuration;

  /// 是否已完成（status == completed）
  bool get isCompleted => status == PomodoroRecordStatus.completed;

  Map<String, dynamic> toJson() {
    // 空字符串的 todoUuid 视为无绑定任务，传 null 给后端
    final cleanTodoUuid = (todoUuid?.isNotEmpty == true) ? todoUuid : null;
    return {
      'uuid': uuid,
      'todo_uuid': cleanTodoUuid,
      'todo_title': todoTitle,
      'tag_uuids': tagUuids,
      'start_time': startTime,
      'end_time': endTime,
      'planned_duration': plannedDuration,
      'actual_duration': actualDuration,
      'status': _statusStr(status),
      'device_id': deviceId,
      'is_deleted': isDeleted ? 1 : 0,
      'version': version,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory PomodoroRecord.fromJson(Map<String, dynamic> j) {
    // 兼容后端返回（无 todo_title / tag_uuids）
    List<String> tags = [];
    final rawTags = j['tag_uuids'];
    if (rawTags is List) {
      tags = rawTags.map((e) => e.toString()).toList();
    } else if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final d = jsonDecode(rawTags);
        if (d is List) tags = d.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    return PomodoroRecord(
      uuid: j['uuid']?.toString() ?? const Uuid().v4(),
      todoUuid: j['todo_uuid']?.toString(),
      // 后端 JOIN todos 返回 todo_title，本地存储也用 todo_title
      todoTitle: (j['todo_title'] ?? j['todoTitle'])?.toString(),
      tagUuids: tags,
      startTime: _ms(j['start_time']),
      endTime: j['end_time'] != null ? _ms(j['end_time']) : null,
      plannedDuration: (j['planned_duration'] as num?)?.toInt() ?? 25 * 60,
      actualDuration: (j['actual_duration'] as num?)?.toInt(),
      status: _parseStatus(j['status']),
      deviceId: j['device_id']?.toString(),
      isDeleted: j['is_deleted'] == 1 || j['is_deleted'] == true,
      version: (j['version'] as num?)?.toInt() ?? 1,
      createdAt: _ms(j['created_at']),
      updatedAt: _ms(j['updated_at']),
    );
  }

  static String _statusStr(PomodoroRecordStatus s) {
    switch (s) {
      case PomodoroRecordStatus.completed:
        return 'completed';
      case PomodoroRecordStatus.interrupted:
        return 'interrupted';
      case PomodoroRecordStatus.switched:
        return 'switched';
    }
  }

  static PomodoroRecordStatus _parseStatus(dynamic v) {
    switch (v?.toString()) {
      case 'interrupted':
        return PomodoroRecordStatus.interrupted;
      case 'switched':
        return PomodoroRecordStatus.switched;
      default:
        return PomodoroRecordStatus.completed;
    }
  }

  static int _ms(dynamic v) {
    if (v == null) return DateTime.now().millisecondsSinceEpoch;
    if (v is int) return v;
    if (v is double) return v.toInt();
    final n = int.tryParse(v.toString().trim());
    if (n != null) return n;
    return DateTime.now().millisecondsSinceEpoch;
  }
}

// ── 向后兼容别名 ──────────────────────────────────────────
typedef PomodoroSession = PomodoroRecord;

// ============================================================
// 番茄钟设置（对齐数据库 pomodoro_settings 表）
// ============================================================

enum TimerMode { countdown, countUp }

class PomodoroSettings {
  int focusMinutes; // default_focus_duration / 60
  int breakMinutes; // default_rest_duration  / 60
  int cycles; // default_loop_count
  TimerMode mode; // 🚀 新增：倒计时或正计时模式

  PomodoroSettings({
    this.focusMinutes = 25,
    this.breakMinutes = 5,
    this.cycles = 4,
    this.mode = TimerMode.countdown,
  });

  Map<String, dynamic> toJson() => {
        'focusMinutes': focusMinutes,
        'breakMinutes': breakMinutes,
        'cycles': cycles,
        'mode': mode.index,
        // 后端字段（秒）
        'default_focus_duration': focusMinutes * 60,
        'default_rest_duration': breakMinutes * 60,
        'default_loop_count': cycles,
      };

  factory PomodoroSettings.fromJson(Map<String, dynamic> j) {
    // 兼容本地存储（分钟）和后端（秒）两种格式
    final focusRaw = j['focusMinutes'] ?? j['default_focus_duration'];
    final breakRaw = j['breakMinutes'] ?? j['default_rest_duration'];
    final cyclesRaw = j['cycles'] ?? j['default_loop_count'];
    final modeIdx = j['mode'] as int? ?? 0;

    int toMinutes(dynamic v, int def) {
      final n = v as int? ?? def;
      // 若 > 60 认为是秒，转换为分钟
      return n > 60 ? n ~/ 60 : n;
    }

    return PomodoroSettings(
      focusMinutes: toMinutes(focusRaw, 25),
      breakMinutes: toMinutes(breakRaw, 5),
      cycles: cyclesRaw as int? ?? 4,
      mode: TimerMode.values[modeIdx.clamp(0, TimerMode.values.length - 1)],
    );
  }
}

// ============================================================
// 番茄钟运行状态（防误杀持久化，仅本地存储）
// ============================================================

enum PomodoroPhase { idle, focusing, breaking, finished, remoteWatching }

class PomodoroRunState {
  PomodoroPhase phase;
  String sessionUuid; // 🚀 新增：记录当前正在运行的番茄钟 UUID
  int targetEndMs; // 本阶段绝对结束时间戳（UTC ms）
  int currentCycle;
  int totalCycles;
  int focusSeconds;
  int breakSeconds;
  String? todoUuid;
  String? todoTitle;
  List<String> tagUuids;
  int sessionStartMs;
  int plannedFocusSeconds;
  TimerMode mode;
  // 🚀 暂停状态持久化
  bool isPaused;
  int pausedAtMs;
  int accumulatedMs;
  int pauseStartMs;

  PomodoroRunState({
    this.phase = PomodoroPhase.idle,
    String? sessionUuid,
    this.targetEndMs = 0,
    this.currentCycle = 1,
    this.totalCycles = 4,
    this.focusSeconds = 25 * 60,
    this.breakSeconds = 5 * 60,
    this.todoUuid,
    this.todoTitle,
    List<String>? tagUuids,
    this.sessionStartMs = 0,
    this.plannedFocusSeconds = 25 * 60,
    this.mode = TimerMode.countdown,
    this.isPaused = false,
    this.pausedAtMs = 0,
    this.accumulatedMs = 0,
    this.pauseStartMs = 0,
  })  : sessionUuid = sessionUuid ?? const Uuid().v4(),
        tagUuids = tagUuids ?? [];

  Map<String, dynamic> toJson() => {
        'phase': phase.index,
        'sessionUuid': sessionUuid,
        'targetEndMs': targetEndMs,
        'currentCycle': currentCycle,
        'totalCycles': totalCycles,
        'focusSeconds': focusSeconds,
        'breakSeconds': breakSeconds,
        'todoUuid': todoUuid,
        'todoTitle': todoTitle,
        'tagUuids': tagUuids,
        'sessionStartMs': sessionStartMs,
        'plannedFocusSeconds': plannedFocusSeconds,
        'mode': mode.index,
        'isCountUp': mode == TimerMode.countUp,
        'isPaused': isPaused,
        'pausedAtMs': pausedAtMs,
        'accumulatedMs': accumulatedMs,
        'pauseStartMs': pauseStartMs,
      };

  factory PomodoroRunState.fromJson(Map<String, dynamic> j) {
    final focusSecs = j['focusSeconds'] as int? ?? 25 * 60;
    final modeIdx =
        j['mode'] as int? ?? (j['isCountUp'] == true || focusSecs == 0 ? 1 : 0);

    return PomodoroRunState(
      phase: PomodoroPhase.values[j['phase'] as int? ?? 0],
      sessionUuid: j['sessionUuid']?.toString() ?? const Uuid().v4(),
      targetEndMs: j['targetEndMs'] as int? ?? 0,
      currentCycle: j['currentCycle'] as int? ?? 1,
      totalCycles: j['totalCycles'] as int? ?? 4,
      focusSeconds: focusSecs,
      breakSeconds: j['breakSeconds'] as int? ?? 5 * 60,
      todoUuid: j['todoUuid'] as String?,
      todoTitle: j['todoTitle'] as String?,
      tagUuids:
          (j['tagUuids'] as List?)?.map((e) => e.toString()).toList() ?? [],
      sessionStartMs: j['sessionStartMs'] as int? ?? 0,
      plannedFocusSeconds: j['plannedFocusSeconds'] as int? ??
          j['actualFocusedSeconds'] as int? ??
          focusSecs,
      mode: TimerMode.values[modeIdx.clamp(0, TimerMode.values.length - 1)],
      isPaused: j['isPaused'] as bool? ?? false,
      pausedAtMs: j['pausedAtMs'] as int? ?? 0,
      accumulatedMs: j['accumulatedMs'] as int? ?? 0,
      pauseStartMs: j['pauseStartMs'] as int? ?? 0,
    );
  }
}

// ============================================================
// PomodoroService —— 核心服务
// ============================================================

class PomodoroService {
  static const _keySettings = 'pomodoro_settings_v2';
  static const _keyRunState = 'pomodoro_run_state';
  static const _keyTags = 'pomodoro_tags_v2';
  static const _keyRecords = 'pomodoro_records'; // 本地缓存记录列表

  // ── 流控（用于 UI 实时响应状态变更，替代轮询） ──────────
  static final _runStateCtrl = StreamController<PomodoroRunState?>.broadcast();
  static Stream<PomodoroRunState?> get onRunStateChanged =>
      _runStateCtrl.stream;

  static void dispose() {
    if (!_runStateCtrl.isClosed) _runStateCtrl.close();
  }

  // ── 私有助手：获取隔离的存储 Key ──────────────────────────
  static Future<String> _getScopedKey(String baseKey) async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString('current_user'); // 必须与 StorageService.KEY_CURRENT_USER 一致
    if (username == null || username.isEmpty) return baseKey;
    return "${baseKey}_$username";
  }

  // ── 设置 ─────────────────────────────────────────────────

  static Future<PomodoroSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keySettings);
    String? s = prefs.getString(scopedKey);
    
    // 迁移检查
    if (s == null) {
      final String? username = prefs.getString('current_user');
      if (username != null && username.isNotEmpty) {
        final markerKey = "${_keySettings}_${username}_migrated";
        if (!(prefs.getBool(markerKey) ?? false)) {
          s = prefs.getString(_keySettings);
          if (s != null) {
            await prefs.setString(scopedKey, s);
            await prefs.setBool(markerKey, true);
          }
        }
      }
    }

    if (s == null) return PomodoroSettings();
    try {
      return PomodoroSettings.fromJson(jsonDecode(s));
    } catch (_) {
      return PomodoroSettings();
    }
  }

  static Future<void> saveSettings(PomodoroSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keySettings);
    await prefs.setString(scopedKey, jsonEncode(settings.toJson()));
    // 异步同步到云端（忽略失败）
    ApiService.syncPomodoroSettings(settings.toJson()).catchError((_) => false);
  }

  // ── 运行状态（防误杀）────────────────────────────────────

  static Future<PomodoroRunState?> loadRunState() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyRunState);
    final s = prefs.getString(scopedKey);
    if (s == null) return null;
    try {
      return PomodoroRunState.fromJson(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRunState(PomodoroRunState state) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyRunState);
    await prefs.setString(scopedKey, jsonEncode(state.toJson()));
    _runStateCtrl.add(state); // 🚀 发送变更信号
  }

  static Future<void> clearRunState() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyRunState);
    await prefs.remove(scopedKey);
    _runStateCtrl.add(null); // 🚀 发送清除信号
  }

  // ── 标签（本地 + 云端 Delta Sync）───────────────────────

  static Future<List<PomodoroTag>> getTags() async {
    // 1. 优先 SQL
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query('pomodoro_tags', where: 'is_deleted = 0');
      if (maps.isNotEmpty) {
        return maps.map((m) => PomodoroTag.fromJson(m)).toList();
      }
    } catch (e) {
      debugPrint("⚠️ Tag SQL 读取异常: $e");
    }

    // 2. 迁移逻辑
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyTags);
    final migrationKey = "tags_migration_done_$scopedKey";
    
    if (!(prefs.getBool(migrationKey) ?? false)) {
      String? s = prefs.getString(scopedKey);
      if (s == null) {
        final username = prefs.getString('current_user');
        if (username != null) s = prefs.getString(_keyTags);
      }

      if (s != null) {
        debugPrint("🚀 [Tags] 正在执行 Prefs -> SQL 迁移...");
        try {
          final List<dynamic> decoded = jsonDecode(s);
          final legacyTags = decoded.map((e) => PomodoroTag.fromJson(e)).toList();
          if (legacyTags.isNotEmpty) {
            await _saveTagsToSql(legacyTags);
          }
          await prefs.setBool(migrationKey, true);
          return legacyTags.where((t) => !t.isDeleted).toList();
        } catch (_) {}
      }
    }

    return [];
  }

  static Future<void> _saveTagsToSql(List<PomodoroTag> tags) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (var t in tags) {
      batch.insert('pomodoro_tags', {
        'uuid': t.uuid,
        'name': t.name,
        'color': t.color,
        'is_deleted': t.isDeleted ? 1 : 0,
        'version': t.version,
        'created_at': t.createdAt,
        'updated_at': t.updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 保存标签（自动检测丢失的项并转化为墓碑，防止云端同步时复活）
  static Future<void> saveTags(List<PomodoroTag> tagsToSave, {bool isSyncSource = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyTags);
    
    // 1. 获取全量（包含已删除）用于 Tombstone 处理
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('pomodoro_tags');
    final List<PomodoroTag> allLocal = maps.map((m) => PomodoroTag.fromJson(m)).toList();

    // 将本次要保存的活动标签存入 Map
    final Map<String, PomodoroTag> newMap = {
      for (var t in tagsToSave) t.uuid: t
    };

    // 遍历本地全量历史数据，找回被“硬删除”的项和原有的墓碑
    for (var old in allLocal) {
      if (!newMap.containsKey(old.uuid)) {
        if (!old.isDeleted) {
          old.isDeleted = true;
          old.updatedAt = DateTime.now().millisecondsSinceEpoch;
          old.version += 1;
        }
        newMap[old.uuid] = old;
      }
    }

    final finalTags = newMap.values.toList();
    // 2. 写入 SQL & OpLog
    final batch = db.batch();
    for (var t in finalTags) {
      if (!isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'pomodoro_tags',
          'target_uuid': t.uuid,
          'data_json': jsonEncode(t.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0
        });
      }
      batch.insert('pomodoro_tags', {
        'uuid': t.uuid,
        'name': t.name,
        'color': t.color,
        'is_deleted': t.isDeleted ? 1 : 0,
        'version': t.version,
        'created_at': t.createdAt,
        'updated_at': t.updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);

    // 3. 补齐 Prefs 备份
    await prefs.setString(
        scopedKey, jsonEncode(finalTags.map((t) => t.toJson()).toList()));
  }

  /// 软删除一个标签（打上 tombstone 标记），以便同步时告诉云端删除
  static Future<void> deleteTag(String uuid) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('pomodoro_tags', where: 'uuid = ?', whereArgs: [uuid]);
    
    if (maps.isNotEmpty) {
      final tag = PomodoroTag.fromJson(maps.first);
      if (!tag.isDeleted) {
        tag.isDeleted = true;
        tag.updatedAt = DateTime.now().millisecondsSinceEpoch;
        tag.version += 1;
        
        final batch = db.batch();
        // 记录 OpLog
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'pomodoro_tags',
          'target_uuid': tag.uuid,
          'data_json': jsonEncode(tag.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0
        });
        // 更新 SQL
        batch.update('pomodoro_tags', {
          'is_deleted': 1,
          'updated_at': tag.updatedAt,
          'version': tag.version
        }, where: 'uuid = ?', whereArgs: [uuid]);
        await batch.commit(noResult: true);

        // 更新 Prefs 备份
        final activeTags = await getTags();
        await saveTags(activeTags, isSyncSource: true);

        // 立即触发同步
        final username = await SharedPreferences.getInstance().then((p) => p.getString('current_user') ?? '');
        if (username.isNotEmpty) {
          StorageService.syncData(username);
        }
      }
    }
  }

  static Future<void> syncTagsToCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyTags);
    final s = prefs.getString(scopedKey);
    if (s == null) return;
    final allTags =
        (jsonDecode(s) as List).map((e) => PomodoroTag.fromJson(e)).toList();
    if (allTags.isEmpty) return;
    await ApiService.syncPomodoroTags(allTags.map((t) => t.toJson()).toList());
    final lastSyncKey = await _getScopedKey('pomodoro_last_tag_sync');
    await prefs.setInt(
        lastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> syncTagsFromCloud() async {
    final remoteList = await ApiService.fetchPomodoroTags();
    if (remoteList.isEmpty) return;
    final remoteTags = remoteList
        .map((e) => PomodoroTag.fromJson(e as Map<String, dynamic>))
        .toList();
    // 读取所有本地标签（含已删除）
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyTags);
    // 优先读当前账号隔离 key，兼容回退旧全局 key
    final s = prefs.getString(scopedKey) ?? prefs.getString(_keyTags);
    final localAll = s == null
        ? <PomodoroTag>[]
        : (jsonDecode(s) as List).map((e) => PomodoroTag.fromJson(e)).toList();
    final Map<String, PomodoroTag> merged = {for (var t in localAll) t.uuid: t};
    for (final rt in remoteTags) {
      final ex = merged[rt.uuid];
      if (ex == null || rt.updatedAt > ex.updatedAt) merged[rt.uuid] = rt;
    }
    await saveTags(merged.values.toList());
  }

  // ── 专注记录（本地缓存 + 云端上传）─────────────────────

  /// 读取有效记录（不含已删除）
  static Future<List<PomodoroRecord>> getRecords() async {
    final all = await _getAllRecordsRaw();
    return all.where((r) => !r.isDeleted).toList();
  }

  static Future<void> _saveRecordsToSql(List<PomodoroRecord> records) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (var r in records) {
      batch.insert('pomodoro_records', {
        'uuid': r.uuid,
        'todo_uuid': r.todoUuid,
        'todo_title': r.todoTitle,
        'tag_uuids': jsonEncode(r.tagUuids),
        'start_time': r.startTime,
        'end_time': r.endTime,
        'planned_duration': r.plannedDuration,
        'actual_duration': r.actualDuration,
        'status': _statusStr(r.status),
        'device_id': r.deviceId,
        'is_deleted': r.isDeleted ? 1 : 0,
        'version': r.version,
        'created_at': r.createdAt,
        'updated_at': r.updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _saveRecords(List<PomodoroRecord> records) async {
    // 🚀 双轨存储：优先 SQL
    await _saveRecordsToSql(records);
    
    // 保持 Prefs 缓存作为备份
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyRecords);
    await prefs.setString(
        scopedKey, jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  /// 添加一条专注记录，本地保存后立即尝试上传云端
  static Future<void> addRecord(PomodoroRecord record, {bool isSyncSource = false}) async {
    // 1. 写入 SQLite & OpLog
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    
    if (!isSyncSource) {
      batch.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'pomodoro_records',
        'target_uuid': record.uuid,
        'data_json': jsonEncode(record.toJson()),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_synced': 0
      });
    }

    batch.insert('pomodoro_records', {
      'uuid': record.uuid,
      'todo_uuid': record.todoUuid,
      'todo_title': record.todoTitle,
      'tag_uuids': jsonEncode(record.tagUuids),
      'start_time': record.startTime,
      'end_time': record.endTime,
      'planned_duration': record.plannedDuration,
      'actual_duration': record.actualDuration,
      'status': _statusStr(record.status),
      'device_id': record.deviceId,
      'is_deleted': record.isDeleted ? 1 : 0,
      'version': record.version,
      'created_at': record.createdAt,
      'updated_at': record.updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    
    await batch.commit(noResult: true);

    // 2. 补齐备份缓存
    final all = await _getAllRecordsRaw();
    final idx = all.indexWhere((r) => r.uuid == record.uuid);
    if (idx >= 0) {
      all[idx] = record;
    } else {
      all.insert(0, record);
    }
    
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyRecords);
    await prefs.setString(scopedKey, jsonEncode(all.map((r) => r.toJson()).toList()));

    debugPrint('[PomodoroService] addRecord OK (SQL+Cache), uuid=${record.uuid}');

    // 3. 立即尝试同步
    if (!isSyncSource) {
      final username = prefs.getString('current_user') ?? '';
      if (username.isNotEmpty) {
        StorageService.syncData(username);
      }
    }
  }

  /// 按时间范围查询（仅有效）
  static Future<List<PomodoroRecord>> getRecordsInRange(
      DateTime from, DateTime to) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'pomodoro_records',
        where: 'is_deleted = 0 AND start_time >= ? AND start_time <= ?',
        whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
        orderBy: 'start_time DESC'
      );
      if (maps.isNotEmpty) {
        return maps.map((m) => PomodoroRecord.fromJson(m)).toList();
      }
    } catch (e) {
      debugPrint("⚠️ Pomodoro SQL 范围查询异常: $e");
    }

    // 逃生通道：Dart 内存过滤
    final all = await getRecords();
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    return all
        .where((r) => r.startTime >= fromMs && r.startTime <= toMs)
        .toList();
  }

  // ── 统计工具 ─────────────────────────────────────────────

  /// 总专注时长（秒），使用 effectiveDuration
  static int totalFocusSeconds(List<PomodoroRecord> records) =>
      records.fold(0, (sum, r) => sum + r.effectiveDuration);

  /// 按标签统计专注时长（秒）
  static Map<String, int> focusByTag(List<PomodoroRecord> records) {
    final Map<String, int> result = {};
    for (final r in records) {
      for (final uuid in r.tagUuids) {
        result[uuid] = (result[uuid] ?? 0) + r.effectiveDuration;
      }
      if (r.tagUuids.isEmpty) {
        result['__none__'] = (result['__none__'] ?? 0) + r.effectiveDuration;
      }
    }
    return result;
  }

  /// 格式化时长
  static String formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0分钟';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0 && m > 0) return '$h小时$m分';
    if (h > 0) return '$h小时';
    return '$m分钟';
  }

  // ── 增量同步：从云端拉取并合并到本地 ────────────────────────

  /// 从云端增量拉取专注记录（LWW 合并），返回是否有新增/变更
  static Future<bool> syncRecordsFromCloud({int? fromMs}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 获取上次拉取的时间戳，默认从 0 开始
      final lastDownloadKey = await _getScopedKey(_keyLastRecordDownload);
      int lastDownload = prefs.getInt(lastDownloadKey) ?? 0;
      if (lastDownload > 0) {
        lastDownload -= 3600 * 1000; // 往前推 1 小时
      }

      final recordsRaw = await ApiService.fetchPomodoroSessions(
        fromMs: lastDownload,
      );
      if (recordsRaw.isEmpty) return false;

      final remoteRecords = recordsRaw
          .map((e) => PomodoroRecord.fromJson(e as Map<String, dynamic>))
          .toList();

      // 读取本地全量（含已删除 tombstone）
      final scopedKey = await _getScopedKey(_keyRecords);
      final s = prefs.getString(scopedKey) ?? prefs.getString(_keyRecords);
      final localAll = s == null
          ? <PomodoroRecord>[]
          : (jsonDecode(s) as List)
              .map((e) => PomodoroRecord.fromJson(e))
              .toList();

      final Map<String, PomodoroRecord> merged = {
        for (var r in localAll) r.uuid: r
      };
      bool hasChange = false;

      for (final rr in remoteRecords) {
        final ex = merged[rr.uuid];
        if (ex == null) {
          // 本地没有 → 直接用云端
          merged[rr.uuid] = rr;
          hasChange = true;
        } else {
          // 合并策略：
          // 1. 云端更新时间更新 → 采用云端数据为主
          // 2. 任何情况下：若云端有 tagUuids/todoTitle 而本地没有 → 补全（修复旧记录标签丢失）
          final cloudNewer = rr.updatedAt > ex.updatedAt;
          final needPatch = (rr.tagUuids.isNotEmpty && ex.tagUuids.isEmpty) ||
              (rr.todoTitle?.isNotEmpty == true && ex.todoTitle == null);
          if (cloudNewer || needPatch) {
            merged[rr.uuid] = PomodoroRecord(
              uuid: rr.uuid,
              todoUuid: rr.todoUuid ?? ex.todoUuid,
              todoTitle: (rr.todoTitle?.isNotEmpty == true)
                  ? rr.todoTitle
                  : ex.todoTitle,
              tagUuids: rr.tagUuids.isNotEmpty ? rr.tagUuids : ex.tagUuids,
              startTime: cloudNewer ? rr.startTime : ex.startTime,
              endTime: cloudNewer ? rr.endTime : ex.endTime,
              plannedDuration:
                  cloudNewer ? rr.plannedDuration : ex.plannedDuration,
              actualDuration:
                  cloudNewer ? rr.actualDuration : ex.actualDuration,
              status: cloudNewer ? rr.status : ex.status,
              deviceId: rr.deviceId ?? ex.deviceId,
              isDeleted: cloudNewer ? rr.isDeleted : ex.isDeleted,
              version: cloudNewer ? rr.version : ex.version,
              createdAt: ex.createdAt,
              updatedAt: cloudNewer ? rr.updatedAt : ex.updatedAt,
            );
            hasChange = true;
          }
        }
      }

      if (hasChange) {
        await prefs.setString(
          scopedKey,
          jsonEncode(merged.values.map((r) => r.toJson()).toList()),
        );
      }

      // 更新最后拉取时间戳为当前服务器时间（或是本地当前时间，取决于业务场景）
      // 这里用本次拉取到的最新记录的 updatedAt 作为下次请求的起点
      int latestTs = 0;
      for (final r in remoteRecords) {
        if (r.updatedAt > latestTs) latestTs = r.updatedAt;
      }
      if (latestTs > 0) {
        final lastDownloadKey = await _getScopedKey(_keyLastRecordDownload);
        await prefs.setInt(lastDownloadKey, latestTs);
      }

      return hasChange;
    } catch (e) {
      debugPrint('[PomodoroService] syncRecordsFromCloud error: $e');
      return false;
    }
  }

  static const _keyLastRecordUpload = 'pomodoro_last_record_upload';
  static const _keyLastRecordDownload = 'pomodoro_last_record_download';

  static Future<void> syncRecordsToCloud() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUploadKey = await _getScopedKey(_keyLastRecordUpload);
      final lastUpload = prefs.getInt(lastUploadKey) ?? 0;
      final all = await _getAllRecordsRaw();
      if (all.isEmpty) return;
      final dirty = all.where((r) => r.updatedAt > lastUpload).toList();
      if (dirty.isEmpty) return;
      final ok = await ApiService.uploadPomodoroRecords(
          dirty.map((r) => r.toJson()).toList());
      if (ok) {
        await prefs.setInt(
            lastUploadKey, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('[PomodoroService] syncRecordsToCloud error: $e');
    }
  }

  /// 读取全量（含已删除）内部方法 —— 包含自动迁移逻辑
  static Future<List<PomodoroRecord>> _getAllRecordsRaw() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('pomodoro_records', orderBy: 'start_time DESC');
    
    if (maps.isNotEmpty) {
      return maps.map((m) => PomodoroRecord.fromJson(m)).toList();
    }

    // 🚀 核心迁移：如果 SQL 为空，尝试从 Prefs 迁移
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = await _getScopedKey(_keyRecords);
    final migrationKey = "pomo_migration_done_$scopedKey";
    
    if (!(prefs.getBool(migrationKey) ?? false)) {
      String? s = prefs.getString(scopedKey);
      // 兜底旧全局 Key
      if (s == null) {
        final username = prefs.getString('current_user');
        if (username != null) s = prefs.getString(_keyRecords);
      }

      if (s != null) {
        debugPrint("🚀 [Pomodoro] 正在执行 Prefs -> SQL 增量迁移...");
        try {
          final List<dynamic> decoded = jsonDecode(s);
          final legacyRecords = decoded.map((e) => PomodoroRecord.fromJson(e)).toList();
          if (legacyRecords.isNotEmpty) {
            await _saveRecordsToSql(legacyRecords);
            debugPrint("✅ [Pomodoro] 成功迁移 ${legacyRecords.length} 条记录至 SQL");
          }
          await prefs.setBool(migrationKey, true);
          return legacyRecords;
        } catch (e) {
          debugPrint("❌ [Pomodoro] 迁移失败: $e");
        }
      }
    }

    return [];
  }

  /// 今日专注记录（本地，不含已删除）
  static Future<List<PomodoroRecord>> getTodayRecords() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return getRecordsInRange(start, end);
  }

  /// 昨日专注记录（本地，不含已删除）
  static Future<List<PomodoroRecord>> getYesterdayRecords() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    final end = start.add(const Duration(days: 1));
    return getRecordsInRange(start, end);
  }

  /// 最近专注：今日有则返回今日，否则返回昨日；同时返回是哪天
  static Future<({List<PomodoroRecord> records, bool isToday})>
      getRecentRecords() async {
    final today = await getTodayRecords();
    if (today.isNotEmpty) return (records: today, isToday: true);
    final yesterday = await getYesterdayRecords();
    return (records: yesterday, isToday: false);
  }

  static Future<List<PomodoroRecord>> getSessions() => getRecords();
  static Future<void> addSession(PomodoroRecord session) => addRecord(session);
  static Future<List<PomodoroRecord>> getSessionsInRange(
          DateTime from, DateTime to) =>
      getRecordsInRange(from, to);
  static int totalFocusSecondsFromSessions(List<PomodoroRecord> s) =>
      totalFocusSeconds(s);

  /// 更新一条记录（修改标签 / 绑定任务等）
  /// 先本地保存（立即返回），云端上传在后台异步进行
  static Future<void> updateRecord(PomodoroRecord updated) async {
    final all = await _getAllRecordsRaw();
    final idx = all.indexWhere((r) => r.uuid == updated.uuid);
    if (idx != -1) {
      all[idx] = updated;
      await _saveRecords(all); // 本地保存完成，立即返回
      // 后台异步上传，不阻塞调用方
      ApiService.uploadPomodoroRecord(updated.toJson())
          .catchError((_) => false);
    }
  }

  /// 软删除一条记录
  static Future<void> deleteRecord(String uuid) async {
    final all = await _getAllRecordsRaw();
    final idx = all.indexWhere((r) => r.uuid == uuid);
    if (idx != -1) {
      final old = all[idx];
      all[idx] = PomodoroRecord(
        uuid: old.uuid,
        todoUuid: old.todoUuid,
        todoTitle: old.todoTitle,
        tagUuids: old.tagUuids,
        startTime: old.startTime,
        endTime: old.endTime,
        plannedDuration: old.plannedDuration,
        actualDuration: old.actualDuration,
        status: old.status,
        deviceId: old.deviceId,
        isDeleted: true,
        version: old.version + 1,
        createdAt: old.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveRecords(all);
      ApiService.uploadPomodoroRecord(all[idx].toJson())
          .catchError((_) => false);
    }
  }

  // 统计页面兼容别名
  static Future<void> updateSession(PomodoroRecord s) => updateRecord(s);
  static Future<void> deleteSession(String uuid) => deleteRecord(uuid);

  static String _statusStr(PomodoroRecordStatus s) {
    switch (s) {
      case PomodoroRecordStatus.completed:
        return 'completed';
      case PomodoroRecordStatus.interrupted:
        return 'interrupted';
      case PomodoroRecordStatus.switched:
        return 'switched';
    }
  }
}
