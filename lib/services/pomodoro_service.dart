import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
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
  String? todoUuid;         // 关联 todos.uuid
  String? todoTitle;        // 冗余存储（便于离线显示）
  List<String> tagUuids;    // 通过 todo_tags 关联，本地缓存用
  int startTime;            // UTC ms
  int? endTime;             // UTC ms
  int plannedDuration;      // 计划专注时长（秒）
  int? actualDuration;      // 实际专注时长（秒）
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

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'todo_uuid': todoUuid,
        'todo_title': todoTitle,       // 后端暂不入库，仅本地用
        'tag_uuids': tagUuids,         // 本地缓存，上传时通过 todo_tags 单独处理
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
      todoTitle: j['todo_title']?.toString(),
      tagUuids: tags,
      startTime: _ms(j['start_time']),
      endTime: j['end_time'] != null ? _ms(j['end_time']) : null,
      plannedDuration: j['planned_duration'] as int? ?? 25 * 60,
      actualDuration: j['actual_duration'] as int?,
      status: _parseStatus(j['status']),
      deviceId: j['device_id']?.toString(),
      isDeleted: j['is_deleted'] == 1 || j['is_deleted'] == true,
      version: j['version'] as int? ?? 1,
      createdAt: _ms(j['created_at']),
      updatedAt: _ms(j['updated_at']),
    );
  }

  static String _statusStr(PomodoroRecordStatus s) {
    switch (s) {
      case PomodoroRecordStatus.completed:  return 'completed';
      case PomodoroRecordStatus.interrupted: return 'interrupted';
      case PomodoroRecordStatus.switched:   return 'switched';
    }
  }

  static PomodoroRecordStatus _parseStatus(dynamic v) {
    switch (v?.toString()) {
      case 'interrupted': return PomodoroRecordStatus.interrupted;
      case 'switched':    return PomodoroRecordStatus.switched;
      default:            return PomodoroRecordStatus.completed;
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

class PomodoroSettings {
  int focusMinutes;  // default_focus_duration / 60
  int breakMinutes;  // default_rest_duration  / 60
  int cycles;        // default_loop_count

  PomodoroSettings({
    this.focusMinutes = 25,
    this.breakMinutes = 5,
    this.cycles = 4,
  });

  Map<String, dynamic> toJson() => {
        'focusMinutes': focusMinutes,
        'breakMinutes': breakMinutes,
        'cycles': cycles,
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

    int toMinutes(dynamic v, int def) {
      final n = v as int? ?? def;
      // 若 > 60 认为是秒，转换为分钟
      return n > 60 ? n ~/ 60 : n;
    }

    return PomodoroSettings(
      focusMinutes: toMinutes(focusRaw, 25),
      breakMinutes: toMinutes(breakRaw, 5),
      cycles: cyclesRaw as int? ?? 4,
    );
  }
}

// ============================================================
// 番茄钟运行状态（防误杀持久化，仅本地存储）
// ============================================================

enum PomodoroPhase { idle, focusing, breaking, finished }

class PomodoroRunState {
  PomodoroPhase phase;
  int targetEndMs;    // 本阶段绝对结束时间戳（UTC ms）
  int currentCycle;
  int totalCycles;
  int focusSeconds;
  int breakSeconds;
  String? todoUuid;
  String? todoTitle;
  List<String> tagUuids;
  int sessionStartMs;
  int plannedFocusSeconds;

  PomodoroRunState({
    this.phase = PomodoroPhase.idle,
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
  }) : tagUuids = tagUuids ?? [];

  Map<String, dynamic> toJson() => {
        'phase': phase.index,
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
      };

  factory PomodoroRunState.fromJson(Map<String, dynamic> j) => PomodoroRunState(
        phase: PomodoroPhase.values[j['phase'] as int? ?? 0],
        targetEndMs: j['targetEndMs'] as int? ?? 0,
        currentCycle: j['currentCycle'] as int? ?? 1,
        totalCycles: j['totalCycles'] as int? ?? 4,
        focusSeconds: j['focusSeconds'] as int? ?? 25 * 60,
        breakSeconds: j['breakSeconds'] as int? ?? 5 * 60,
        todoUuid: j['todoUuid'] as String?,
        todoTitle: j['todoTitle'] as String?,
        tagUuids: (j['tagUuids'] as List?)?.map((e) => e.toString()).toList() ?? [],
        sessionStartMs: j['sessionStartMs'] as int? ?? 0,
        plannedFocusSeconds: j['plannedFocusSeconds'] as int?
            ?? j['actualFocusedSeconds'] as int?  // 旧字段兼容
            ?? 25 * 60,
      );
}

// ============================================================
// PomodoroService —— 核心服务
// ============================================================

class PomodoroService {
  static const _keySettings  = 'pomodoro_settings_v2';
  static const _keyRunState  = 'pomodoro_run_state';
  static const _keyTags      = 'pomodoro_tags_v2';
  static const _keyRecords   = 'pomodoro_records';   // 本地缓存记录列表

  // ── 设置 ─────────────────────────────────────────────────

  static Future<PomodoroSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keySettings);
    if (s == null) return PomodoroSettings();
    try { return PomodoroSettings.fromJson(jsonDecode(s)); }
    catch (_) { return PomodoroSettings(); }
  }

  static Future<void> saveSettings(PomodoroSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, jsonEncode(settings.toJson()));
    // 异步同步到云端（忽略失败）
    ApiService.syncPomodoroSettings(settings.toJson()).catchError((_) => false);
  }

  // ── 运行状态（防误杀）────────────────────────────────────

  static Future<PomodoroRunState?> loadRunState() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyRunState);
    if (s == null) return null;
    try { return PomodoroRunState.fromJson(jsonDecode(s)); }
    catch (_) { return null; }
  }

  static Future<void> saveRunState(PomodoroRunState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRunState, jsonEncode(state.toJson()));
  }

  static Future<void> clearRunState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRunState);
  }

  // ── 标签（本地 + 云端 Delta Sync）───────────────────────

  static Future<List<PomodoroTag>> getTags() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyTags);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => PomodoroTag.fromJson(e))
          .where((t) => !t.isDeleted)
          .toList();
    } catch (_) { return []; }
  }

  /// 保存标签（包含已删除的 tombstone，以便 Delta Sync 能删除云端）
  static Future<void> saveTags(List<PomodoroTag> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTags, jsonEncode(tags.map((t) => t.toJson()).toList()));
  }

  static Future<void> syncTagsToCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyTags);
    if (s == null) return;
    final allTags = (jsonDecode(s) as List)
        .map((e) => PomodoroTag.fromJson(e))
        .toList();
    if (allTags.isEmpty) return;
    await ApiService.syncPomodoroTags(allTags.map((t) => t.toJson()).toList());
    await prefs.setInt('pomodoro_last_tag_sync', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> syncTagsFromCloud() async {
    final remoteList = await ApiService.fetchPomodoroTags();
    if (remoteList.isEmpty) return;
    final remoteTags = remoteList
        .map((e) => PomodoroTag.fromJson(e as Map<String, dynamic>))
        .toList();
    // 读取所有本地标签（含已删除）
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyTags);
    final localAll = s == null ? <PomodoroTag>[]
        : (jsonDecode(s) as List).map((e) => PomodoroTag.fromJson(e)).toList();
    final Map<String, PomodoroTag> merged = {for (var t in localAll) t.uuid: t};
    for (final rt in remoteTags) {
      final ex = merged[rt.uuid];
      if (ex == null || rt.updatedAt > ex.updatedAt) merged[rt.uuid] = rt;
    }
    await saveTags(merged.values.toList());
  }

  // ── 专注记录（本地缓存 + 云端上传）─────────────────────

  static Future<List<PomodoroRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keyRecords);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => PomodoroRecord.fromJson(e))
          .where((r) => !r.isDeleted)
          .toList();
    } catch (_) { return []; }
  }

  static Future<void> _saveRecords(List<PomodoroRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRecords, jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  /// 添加一条专注记录并立即上传云端
  static Future<void> addRecord(PomodoroRecord record) async {
    final all = await getRecords();
    all.insert(0, record);
    await _saveRecords(all);
    // 后台上传（不阻塞 UI）
    ApiService.uploadPomodoroRecord(record.toJson()).catchError((_) => false);
  }

  /// 按时间范围查询
  static Future<List<PomodoroRecord>> getRecordsInRange(DateTime from, DateTime to) async {
    final all = await getRecords();
    final fromMs = from.millisecondsSinceEpoch;
    final toMs   = to.millisecondsSinceEpoch;
    return all.where((r) => r.startTime >= fromMs && r.startTime <= toMs).toList();
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

  // ── 兼容旧接口（Session → Record 别名）──────────────────

  static Future<List<PomodoroRecord>> getSessions() => getRecords();
  static Future<void> addSession(PomodoroRecord session) => addRecord(session);
  static Future<List<PomodoroRecord>> getSessionsInRange(DateTime from, DateTime to) =>
      getRecordsInRange(from, to);
  static int totalFocusSecondsFromSessions(List<PomodoroRecord> s) => totalFocusSeconds(s);

  /// 更新一条记录（修改标签 / 绑定任务等）
  static Future<void> updateRecord(PomodoroRecord updated) async {
    final all = await getRecords();
    final idx = all.indexWhere((r) => r.uuid == updated.uuid);
    if (idx != -1) {
      all[idx] = updated;
      await _saveRecords(all);
      ApiService.uploadPomodoroRecord(updated.toJson()).catchError((_) => false);
    }
  }

  /// 软删除一条记录
  static Future<void> deleteRecord(String uuid) async {
    final all = await getRecords();
    final idx = all.indexWhere((r) => r.uuid == uuid);
    if (idx != -1) {
      final deleted = PomodoroRecord(
        uuid: all[idx].uuid,
        todoUuid: all[idx].todoUuid,
        todoTitle: all[idx].todoTitle,
        tagUuids: all[idx].tagUuids,
        startTime: all[idx].startTime,
        endTime: all[idx].endTime,
        plannedDuration: all[idx].plannedDuration,
        actualDuration: all[idx].actualDuration,
        status: all[idx].status,
        deviceId: all[idx].deviceId,
        isDeleted: true,
        version: all[idx].version + 1,
        createdAt: all[idx].createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      all[idx] = deleted;
      await _saveRecords(all);
      ApiService.uploadPomodoroRecord(deleted.toJson()).catchError((_) => false);
    }
  }

  // 统计页面兼容别名
  static Future<void> updateSession(PomodoroRecord s) => updateRecord(s);
  static Future<void> deleteSession(String uuid) => deleteRecord(uuid);
}

