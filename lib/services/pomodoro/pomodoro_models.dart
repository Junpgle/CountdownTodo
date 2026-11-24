part of '../pomodoro_service.dart';

// ============================================================
// 番茄钟数据模型（对齐数据库 pomodoro_tags 表）
// ============================================================

class PomodoroTag {
  String uuid;
  String name;
  String color;
  bool isDeleted;
  bool isArchived;
  int version;
  int createdAt; // UTC ms
  int updatedAt; // UTC ms
  bool hasConflict;
  Map<String, dynamic>? conflictData;

  PomodoroTag({
    String? uuid,
    required this.name,
    this.color = '#607D8B',
    this.isDeleted = false,
    this.isArchived = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.hasConflict = false,
    this.conflictData,
  }) : uuid = uuid ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 序列化：供 API 上传和本地存储使用
  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'color': color,
    'is_deleted': isDeleted ? 1 : 0,
    'is_archived': isArchived ? 1 : 0,
    'version': version,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'has_conflict': hasConflict ? 1 : 0,
    'conflict_data': conflictData != null ? jsonEncode(conflictData) : null,
  };

  factory PomodoroTag.fromJson(Map<String, dynamic> j) => PomodoroTag(
    uuid: j['uuid']?.toString() ?? const Uuid().v4(),
    name: j['name']?.toString() ?? '',
    color: j['color']?.toString() ?? '#607D8B',
    isDeleted: j['is_deleted'] == 1 || j['is_deleted'] == true,
    isArchived: j['is_archived'] == 1 || j['is_archived'] == true,
    version: JsonValueParser.toInt(j['version'], fallback: 1),
    createdAt: _ms(j['created_at']),
    updatedAt: _ms(j['updated_at']),
    hasConflict: j['has_conflict'] == 1 || j['has_conflict'] == true,
    conflictData: _mapOrJson(j['conflict_data']),
  );

  static Map<String, dynamic>? _mapOrJson(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
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

// ============================================================
// 暂停区间模型
// ============================================================

class PauseInterval {
  int startMs;
  int? endMs;

  PauseInterval({required this.startMs, this.endMs});

  Map<String, dynamic> toJson() => {
    'startMs': startMs,
    if (endMs != null) 'endMs': endMs,
  };

  factory PauseInterval.fromJson(Map<String, dynamic> j) {
    return PauseInterval(
      startMs: JsonValueParser.toInt(j['startMs']),
      endMs: JsonValueParser.toNullableInt(j['endMs']),
    );
  }

  int get durationMs =>
      (endMs ?? DateTime.now().millisecondsSinceEpoch) - startMs;

  int get durationSeconds => (durationMs / 1000).round();

  bool get isOngoing => endMs == null;
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
  String? planBlockId; // 🚀 新增：关联规划块 ID
  String? note; // 专注备注
  int? totalPauseSeconds; // 总暂停时长（秒）
  List<PauseInterval>? pauseIntervals; // 暂停区间列表
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;
  bool hasConflict;
  Map<String, dynamic>? conflictData;

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
    this.planBlockId,
    this.note,
    this.totalPauseSeconds,
    this.pauseIntervals,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.hasConflict = false,
    this.conflictData,
  }) : uuid = uuid ?? const Uuid().v4(),
       tagUuids = tagUuids ?? [],
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 从运行状态创建记录，统一映射字段，避免各调用点重复
  factory PomodoroRecord.fromRunState({
    required PomodoroRunState state,
    required PomodoroRecordStatus status,
    required int endMs,
    int? actualDuration,
    String? deviceId,
  }) {
    var accumulatedMs = state.accumulatedMs;
    final pauseIntervals = state.pauseIntervals
        .map(
          (interval) =>
              PauseInterval(startMs: interval.startMs, endMs: interval.endMs),
        )
        .toList();

    if (state.isPaused) {
      final pauseStartMs = state.pausedAtMs > 0
          ? state.pausedAtMs
          : state.pauseStartMs > 0
          ? state.pauseStartMs
          : pauseIntervals.isNotEmpty
          ? pauseIntervals.last.startMs
          : 0;
      if (pauseStartMs > 0) {
        final pauseDuration = endMs - pauseStartMs;
        if (pauseDuration > 0) {
          accumulatedMs += pauseDuration;
        }
        if (pauseIntervals.isNotEmpty && pauseIntervals.last.isOngoing) {
          pauseIntervals.last.endMs = endMs;
        } else {
          pauseIntervals.add(
            PauseInterval(startMs: pauseStartMs, endMs: endMs),
          );
        }
      }
    }

    final computedFromState = PomodoroRunState.computeActualSeconds(
      state.sessionStartMs,
      accumulatedMs,
      endMs: endMs,
    );
    final computedActual =
        actualDuration != null &&
            (!state.isPaused || actualDuration <= computedFromState)
        ? actualDuration
        : computedFromState;
    final intervalPauseSeconds = pauseIntervals.fold<int>(
      0,
      (sum, interval) => sum + interval.durationSeconds,
    );
    final accumulatedPauseSeconds = (accumulatedMs / 1000).round();
    final totalPauseSeconds = accumulatedPauseSeconds > intervalPauseSeconds
        ? accumulatedPauseSeconds
        : intervalPauseSeconds;
    return PomodoroRecord(
      uuid: state.sessionUuid,
      todoUuid: state.todoUuid,
      todoTitle: state.todoTitle,
      tagUuids: List.from(state.tagUuids),
      startTime: state.sessionStartMs,
      endTime: endMs,
      plannedDuration: state.plannedFocusSeconds,
      actualDuration: computedActual,
      status: status,
      deviceId: deviceId,
      planBlockId: state.planBlockId,
      note: state.note,
      totalPauseSeconds: totalPauseSeconds,
      pauseIntervals: pauseIntervals,
    );
  }

  /// 实际有效的专注秒数（优先用 actualDuration）
  int get effectiveDuration => actualDuration ?? plannedDuration;

  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

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
      'plan_block_id': planBlockId,
      'note': note,
      'total_pause_seconds': totalPauseSeconds,
      'pause_intervals': pauseIntervals != null
          ? jsonEncode(pauseIntervals!.map((e) => e.toJson()).toList())
          : null,
      'is_deleted': isDeleted ? 1 : 0,
      'version': version,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'has_conflict': hasConflict ? 1 : 0,
      'conflict_data': conflictData != null ? jsonEncode(conflictData) : null,
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
      plannedDuration: JsonValueParser.toInt(
        j['planned_duration'],
        fallback: 25 * 60,
      ),
      actualDuration: JsonValueParser.toNullableInt(j['actual_duration']),
      status: _parseStatus(j['status']),
      deviceId: j['device_id']?.toString(),
      planBlockId: (j['plan_block_id'] ?? j['planBlockId'])?.toString(),
      note: j['note']?.toString(),
      totalPauseSeconds: JsonValueParser.toNullableInt(
        j['total_pause_seconds'],
      ),
      pauseIntervals: _parseRecordPauseIntervals(j['pause_intervals']),
      isDeleted: j['is_deleted'] == 1 || j['is_deleted'] == true,
      version: JsonValueParser.toInt(j['version'], fallback: 1),
      createdAt: _ms(j['created_at']),
      updatedAt: _ms(j['updated_at']),
      hasConflict: j['has_conflict'] == 1 || j['has_conflict'] == true,
      conflictData: PomodoroTag._mapOrJson(j['conflict_data']),
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

  static List<PauseInterval>? _parseRecordPauseIntervals(dynamic raw) {
    if (raw == null) return null;
    List<dynamic>? list;
    if (raw is List) {
      list = raw;
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) list = decoded;
      } catch (_) {}
    }
    if (list == null) return null;
    return list
        .whereType<Map>()
        .map((e) => PauseInterval.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

typedef PomodoroLegacyPlanBlockMatcher = bool Function(
  PomodoroRecord record,
  TodoPlanBlock block,
);

/// Attributes Pomodoro focus time to planned blocks without counting a focus
/// interval or a paused interval more than once.
class PomodoroPlanFocusAllocator {
  static List<int> linkedSecondsByBlock({
    required List<TodoPlanBlock> blocks,
    required List<PomodoroRecord> records,
    PomodoroLegacyPlanBlockMatcher? legacyBlockMatcher,
  }) => allocateByBlock(
    blocks: blocks,
    records: records,
    legacyBlockMatcher: legacyBlockMatcher,
  ).linkedSecondsByBlock;

  static PomodoroPlanFocusAllocation allocateByBlock({
    required List<TodoPlanBlock> blocks,
    required List<PomodoroRecord> records,
    PomodoroLegacyPlanBlockMatcher? legacyBlockMatcher,
  }) {
    if (blocks.isEmpty) {
      return const PomodoroPlanFocusAllocation(
        linkedSecondsByBlock: <int>[],
        secondsByRecordByBlock: <Map<String, int>>[],
        hasRecordCandidatesByBlock: <bool>[],
      );
    }

    final blocksById = <String, List<int>>{};
    final blocksByTodoId = <String, List<int>>{};
    final explicitBlocksByRecordId = <String, Set<int>>{};
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      if (block.isDeleted) continue;
      blocksById.putIfAbsent(block.uuid, () => []).add(blockIndex);
      blocksByTodoId.putIfAbsent(block.todoId, () => []).add(blockIndex);
      for (final recordId in block.pomodoroRecordIds) {
        explicitBlocksByRecordId
            .putIfAbsent(recordId, () => <int>{})
            .add(blockIndex);
      }
    }

    final secondsByRecordByBlock = [
      for (var index = 0; index < blocks.length; index++) <String, int>{},
    ];
    final hasRecordCandidatesByBlock = List<bool>.filled(blocks.length, false);
    for (final record in records) {
      if (record.isDeleted) continue;

      final planBlockId = record.planBlockId;
      final directlyLinked = planBlockId == null
          ? null
          : blocksById[planBlockId];
      if (directlyLinked != null && directlyLinked.isNotEmpty) {
        hasRecordCandidatesByBlock[directlyLinked.first] = true;
        _addAttributedSeconds(
          secondsByRecordByBlock[directlyLinked.first],
          record.uuid,
          max(0, record.effectiveDuration),
        );
        continue;
      }

      final explicitlyLinked = explicitBlocksByRecordId[record.uuid];
      if (explicitlyLinked != null && explicitlyLinked.isNotEmpty) {
        for (final blockIndex in explicitlyLinked) {
          hasRecordCandidatesByBlock[blockIndex] = true;
        }
        _attributeRecordToBlocks(
          record: record,
          candidateIndexes: explicitlyLinked.toList(),
          blocks: blocks,
          secondsByRecordByBlock: secondsByRecordByBlock,
          isExplicitLink: true,
        );
        continue;
      }

      if (planBlockId?.isNotEmpty == true) continue;
      final candidateBlocks = legacyBlockMatcher == null
          ? (record.todoUuid == null ? null : blocksByTodoId[record.todoUuid])
          : [
              for (var index = 0; index < blocks.length; index++)
                if (!blocks[index].isDeleted &&
                    legacyBlockMatcher(record, blocks[index]))
                  index,
            ];
      if (candidateBlocks == null || candidateBlocks.isEmpty) continue;

      for (final blockIndex in candidateBlocks) {
        if (_recordOverlapsBlock(record, blocks[blockIndex])) {
          hasRecordCandidatesByBlock[blockIndex] = true;
        }
      }
      _attributeRecordToBlocks(
        record: record,
        candidateIndexes: candidateBlocks,
        blocks: blocks,
        secondsByRecordByBlock: secondsByRecordByBlock,
        isExplicitLink: false,
      );
    }
    final linkedSecondsByBlock = [
      for (final recordSeconds in secondsByRecordByBlock)
        recordSeconds.values.fold<int>(0, (sum, seconds) => sum + seconds),
    ];
    return PomodoroPlanFocusAllocation(
      linkedSecondsByBlock: linkedSecondsByBlock,
      secondsByRecordByBlock: secondsByRecordByBlock,
      hasRecordCandidatesByBlock: hasRecordCandidatesByBlock,
    );
  }

  static List<int> actualSecondsByBlock({
    required List<TodoPlanBlock> blocks,
    required List<PomodoroRecord> records,
    PomodoroLegacyPlanBlockMatcher? legacyBlockMatcher,
  }) {
    final allocation = allocateByBlock(
      blocks: blocks,
      records: records,
      legacyBlockMatcher: legacyBlockMatcher,
    );
    return [
      for (var i = 0; i < blocks.length; i++)
        allocation.hasRecordCandidatesByBlock[i]
            ? allocation.linkedSecondsByBlock[i]
            : max(0, blocks[i].actualFocusSeconds),
    ];
  }

  static bool _recordOverlapsBlock(PomodoroRecord record, TodoPlanBlock block) {
    final recordEnd =
        record.endTime ??
        record.startTime + max(0, record.effectiveDuration) * 1000;
    return record.startTime < block.endTime && recordEnd > block.startTime;
  }

  static void _attributeRecordToBlocks({
    required PomodoroRecord record,
    required List<int> candidateIndexes,
    required List<TodoPlanBlock> blocks,
    required List<Map<String, int>> secondsByRecordByBlock,
    required bool isExplicitLink,
  }) {
    final candidates = candidateIndexes.toSet().toList()
      ..sort((a, b) {
        final startTime = blocks[a].startTime.compareTo(blocks[b].startTime);
        return startTime != 0 ? startTime : a.compareTo(b);
      });
    if (candidates.isEmpty) return;
    if (isExplicitLink && candidates.length == 1) {
      _addAttributedSeconds(
        secondsByRecordByBlock[candidates.single],
        record.uuid,
        max(0, record.effectiveDuration),
      );
      return;
    }

    var remainingMs = max(0, record.effectiveDuration) * 1000;
    if (remainingMs == 0) return;

    final activeIntervals = _activeIntervalsForRecord(record);
    final claimedIntervals = <_PomodoroFocusInterval>[];
    final allocatedMsByBlock = <int, int>{};

    for (final blockIndex in candidates) {
      if (remainingMs <= 0) break;
      final block = blocks[blockIndex];
      var blockAllocatedMs = 0;
      for (final activeInterval in activeIntervals) {
        if (remainingMs <= 0) break;
        final overlapStart = max(activeInterval.startMs, block.startTime);
        final overlapEnd = min(activeInterval.endMs, block.endTime);
        if (overlapEnd <= overlapStart) continue;

        final unclaimed = _subtractClaimedIntervals(
          _PomodoroFocusInterval(startMs: overlapStart, endMs: overlapEnd),
          claimedIntervals,
        );
        for (final interval in unclaimed) {
          if (remainingMs <= 0) break;
          final takeMs = min(interval.durationMs, remainingMs);
          if (takeMs <= 0) continue;
          claimedIntervals.add(
            _PomodoroFocusInterval(
              startMs: interval.startMs,
              endMs: interval.startMs + takeMs,
            ),
          );
          blockAllocatedMs += takeMs;
          remainingMs -= takeMs;
        }
      }
      if (blockAllocatedMs > 0) {
        allocatedMsByBlock[blockIndex] = blockAllocatedMs;
      }
    }

    for (final entry in allocatedMsByBlock.entries) {
      _addAttributedSeconds(
        secondsByRecordByBlock[entry.key],
        record.uuid,
        entry.value ~/ 1000,
      );
    }

    // Explicit links are authoritative even when old records lack usable
    // timestamps. Keep their duration on one block instead of dropping it.
    if (isExplicitLink && allocatedMsByBlock.isEmpty) {
      _addAttributedSeconds(
        secondsByRecordByBlock[candidates.first],
        record.uuid,
        max(0, record.effectiveDuration),
      );
    }
  }

  static void _addAttributedSeconds(
    Map<String, int> recordSeconds,
    String recordUuid,
    int seconds,
  ) {
    if (seconds <= 0) return;
    recordSeconds[recordUuid] = (recordSeconds[recordUuid] ?? 0) + seconds;
  }

  static List<_PomodoroFocusInterval> _activeIntervalsForRecord(
    PomodoroRecord record,
  ) {
    final recordEnd =
        record.endTime ??
        record.startTime + max(0, record.effectiveDuration) * 1000;
    if (recordEnd <= record.startTime) {
      return const <_PomodoroFocusInterval>[];
    }

    final pauses = <_PomodoroFocusInterval>[];
    for (final pause in record.pauseIntervals ?? const <PauseInterval>[]) {
      final pauseStart = max(record.startTime, pause.startMs);
      final pauseEnd = min(recordEnd, pause.endMs ?? recordEnd);
      if (pauseEnd > pauseStart) {
        pauses.add(
          _PomodoroFocusInterval(startMs: pauseStart, endMs: pauseEnd),
        );
      }
    }
    pauses.sort((a, b) => a.startMs.compareTo(b.startMs));

    final mergedPauses = <_PomodoroFocusInterval>[];
    for (final pause in pauses) {
      if (mergedPauses.isEmpty || pause.startMs > mergedPauses.last.endMs) {
        mergedPauses.add(pause);
      } else if (pause.endMs > mergedPauses.last.endMs) {
        mergedPauses.last.endMs = pause.endMs;
      }
    }

    final active = <_PomodoroFocusInterval>[];
    var cursor = record.startTime;
    for (final pause in mergedPauses) {
      if (pause.startMs > cursor) {
        active.add(
          _PomodoroFocusInterval(startMs: cursor, endMs: pause.startMs),
        );
      }
      cursor = max(cursor, pause.endMs);
    }
    if (cursor < recordEnd) {
      active.add(_PomodoroFocusInterval(startMs: cursor, endMs: recordEnd));
    }
    return active;
  }

  static List<_PomodoroFocusInterval> _subtractClaimedIntervals(
    _PomodoroFocusInterval source,
    List<_PomodoroFocusInterval> claimedIntervals,
  ) {
    if (claimedIntervals.isEmpty) return [source];
    final sortedClaims = [...claimedIntervals]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final result = <_PomodoroFocusInterval>[];
    var cursor = source.startMs;
    for (final claimed in sortedClaims) {
      if (claimed.endMs <= cursor) continue;
      if (claimed.startMs >= source.endMs) break;
      if (claimed.startMs > cursor) {
        result.add(
          _PomodoroFocusInterval(
            startMs: cursor,
            endMs: min(claimed.startMs, source.endMs),
          ),
        );
      }
      cursor = max(cursor, claimed.endMs);
      if (cursor >= source.endMs) break;
    }
    if (cursor < source.endMs) {
      result.add(_PomodoroFocusInterval(startMs: cursor, endMs: source.endMs));
    }
    return result;
  }
}

class PomodoroPlanFocusAllocation {
  const PomodoroPlanFocusAllocation({
    required this.linkedSecondsByBlock,
    required this.secondsByRecordByBlock,
    required this.hasRecordCandidatesByBlock,
  });

  final List<int> linkedSecondsByBlock;
  final List<Map<String, int>> secondsByRecordByBlock;
  final List<bool> hasRecordCandidatesByBlock;
}

class _PomodoroFocusInterval {
  _PomodoroFocusInterval({required this.startMs, required this.endMs});

  final int startMs;
  int endMs;

  int get durationMs => endMs - startMs;
}

/// Lightweight fields used to build long-range statistics without decoding
/// every historical record into a full [PomodoroRecord].
class PomodoroSessionSummary {
  final int startTime;
  final int effectiveDuration;
  final bool isCompleted;
  final List<String> tagUuids;

  const PomodoroSessionSummary({
    required this.startTime,
    required this.effectiveDuration,
    required this.isCompleted,
    required this.tagUuids,
  });

  factory PomodoroSessionSummary.fromDatabaseMap(
    Map<String, dynamic> values, {
    bool includeTagUuids = true,
  }) {
    final rawTags = values['tag_uuids'];
    List<String> tagUuids = const [];
    if (!includeTagUuids) {
      tagUuids = const [];
    } else if (rawTags is List) {
      tagUuids = rawTags.map((value) => value.toString()).toList();
    } else if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) {
          tagUuids = decoded.map((value) => value.toString()).toList();
        }
      } catch (_) {}
    }

    final status = values['status']?.toString();
    final actualDuration = JsonValueParser.toNullableInt(
      values['actual_duration'],
    );
    return PomodoroSessionSummary(
      startTime: JsonValueParser.toInt(values['start_time'], fallback: 0),
      effectiveDuration:
          actualDuration ??
          JsonValueParser.toInt(values['planned_duration'], fallback: 25 * 60),
      isCompleted: status != 'interrupted' && status != 'switched',
      tagUuids: tagUuids,
    );
  }

  factory PomodoroSessionSummary.fromRecord(
    PomodoroRecord record, {
    bool includeTagUuids = true,
  }) => PomodoroSessionSummary(
    startTime: record.startTime,
    effectiveDuration: record.effectiveDuration,
    isCompleted: record.isCompleted,
    tagUuids: includeTagUuids ? record.tagUuids : const [],
  );
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
  bool strictFreeFocus; // 严格自由专注：通过手机翻转控制计时
  bool doNotDisturbDuringFocus; // 专注期间抑制 CountdownTodo 的其他提醒

  PomodoroSettings({
    this.focusMinutes = 25,
    this.breakMinutes = 5,
    this.cycles = 4,
    this.mode = TimerMode.countdown,
    this.strictFreeFocus = false,
    this.doNotDisturbDuringFocus = false,
  });

  Map<String, dynamic> toJson() => {
    'focusMinutes': focusMinutes,
    'breakMinutes': breakMinutes,
    'cycles': cycles,
    'mode': mode.index,
    'strictFreeFocus': strictFreeFocus,
    'doNotDisturbDuringFocus': doNotDisturbDuringFocus,
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
    final modeIdx = JsonValueParser.toInt(j['mode']);
    final strictFreeFocus =
        j['strictFreeFocus'] == true ||
        j['strict_free_focus'] == true ||
        j['strictMode'] == true;
    final doNotDisturbDuringFocus =
        j['doNotDisturbDuringFocus'] == true ||
        j['do_not_disturb_during_focus'] == true ||
        j['do_not_disturb'] == true;

    int toMinutes(dynamic v, int def) {
      final n = JsonValueParser.toInt(v, fallback: def);
      // 若 >= 60 认为是秒，转换为分钟；恰好 60 秒也应是 1 分钟。
      return n >= 60 ? n ~/ 60 : n;
    }

    return PomodoroSettings(
      focusMinutes: toMinutes(focusRaw, 25),
      breakMinutes: toMinutes(breakRaw, 5),
      cycles: JsonValueParser.toInt(cyclesRaw, fallback: 4),
      mode: TimerMode
          .values[modeIdx.clamp(0, TimerMode.values.length - 1).toInt()],
      strictFreeFocus: strictFreeFocus,
      doNotDisturbDuringFocus: doNotDisturbDuringFocus,
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
  List<String> tagNames;
  int sessionStartMs;
  int plannedFocusSeconds;
  TimerMode mode;
  bool strictFreeFocus;
  bool strictWaitingForFlip;
  bool doNotDisturbDuringFocus;
  // 🚀 暂停状态持久化
  bool isPaused;
  int pausedAtMs;
  int accumulatedMs;
  int pauseStartMs;
  List<PauseInterval> pauseIntervals; // 暂停区间列表
  String? planBlockId; // 🚀 新增：关联规划块 ID
  String? habitUuid; // 🚀 新增：关联习惯 UUID
  int? challengeTaskId; // 🚀 新增：关联30天挑战任务 ID
  String? note; // 专注备注

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
    List<String>? tagNames,
    this.sessionStartMs = 0,
    this.plannedFocusSeconds = 25 * 60,
    this.mode = TimerMode.countdown,
    this.strictFreeFocus = false,
    this.strictWaitingForFlip = false,
    this.doNotDisturbDuringFocus = false,
    this.isPaused = false,
    this.pausedAtMs = 0,
    this.accumulatedMs = 0,
    this.pauseStartMs = 0,
    List<PauseInterval>? pauseIntervals,
    this.planBlockId,
    this.habitUuid,
    this.challengeTaskId,
    this.note,
  }) : sessionUuid = sessionUuid ?? const Uuid().v4(),
       tagUuids = tagUuids ?? [],
       tagNames = tagNames ?? [],
       pauseIntervals = pauseIntervals ?? [];

  /// 计算实际专注秒数（扣除暂停累计时间）
  /// [endMs] 默认为当前时间，可传入自定义结束时间
  static int computeActualSeconds(
    int sessionStartMs,
    int accumulatedMs, {
    int? endMs,
  }) {
    final end = endMs ?? DateTime.now().millisecondsSinceEpoch;
    return (((end - sessionStartMs) - accumulatedMs) / 1000).round().clamp(
      0,
      24 * 3600,
    );
  }

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
    'tagNames': tagNames,
    'sessionStartMs': sessionStartMs,
    'plannedFocusSeconds': plannedFocusSeconds,
    'mode': mode.index,
    'isCountUp': mode == TimerMode.countUp,
    'strictFreeFocus': strictFreeFocus,
    'strictWaitingForFlip': strictWaitingForFlip,
    'doNotDisturbDuringFocus': doNotDisturbDuringFocus,
    'isPaused': isPaused,
    'paused_at_ms': pausedAtMs,
    'accumulated_ms': accumulatedMs,
    'pause_start_ms': pauseStartMs,
    'pause_intervals': pauseIntervals,
    'plan_block_id': planBlockId,
    if (habitUuid != null) 'habit_uuid': habitUuid,
    if (challengeTaskId != null) 'challenge_task_id': challengeTaskId,
    'note': note,
  };

  factory PomodoroRunState.fromJson(Map<String, dynamic> j) {
    final focusSecs = JsonValueParser.toInt(
      j['focusSeconds'],
      fallback: 25 * 60,
    );
    final modeIdx = JsonValueParser.toInt(
      j['mode'],
      fallback: j['isCountUp'] == true || focusSecs == 0 ? 1 : 0,
    );
    final phaseIdx = JsonValueParser.toInt(j['phase'])
        .clamp(0, PomodoroPhase.values.length - 1)
        .toInt();

    return PomodoroRunState(
      phase: PomodoroPhase.values[phaseIdx],
      sessionUuid: j['sessionUuid']?.toString() ?? const Uuid().v4(),
      targetEndMs: JsonValueParser.toInt(j['targetEndMs']),
      currentCycle: JsonValueParser.toInt(j['currentCycle'], fallback: 1),
      totalCycles: JsonValueParser.toInt(j['totalCycles'], fallback: 4),
      focusSeconds: focusSecs,
      breakSeconds: JsonValueParser.toInt(j['breakSeconds'], fallback: 5 * 60),
      todoUuid: j['todoUuid']?.toString(),
      todoTitle: j['todoTitle']?.toString(),
      tagUuids:
          (j['tagUuids'] as List?)?.map((e) => e.toString()).toList() ?? [],
      tagNames:
          (j['tagNames'] as List?)?.map((e) => e.toString()).toList() ?? [],
      sessionStartMs: JsonValueParser.toInt(j['sessionStartMs']),
      plannedFocusSeconds:
          JsonValueParser.toNullableInt(j['plannedFocusSeconds']) ??
          JsonValueParser.toNullableInt(j['actualFocusedSeconds']) ??
          focusSecs,
      mode: TimerMode
          .values[modeIdx.clamp(0, TimerMode.values.length - 1).toInt()],
      strictFreeFocus:
          j['strictFreeFocus'] == true ||
          j['strict_free_focus'] == true ||
          j['strictMode'] == true,
      strictWaitingForFlip:
          j['strictWaitingForFlip'] == true ||
          j['strict_waiting_for_flip'] == true,
      doNotDisturbDuringFocus:
          j['doNotDisturbDuringFocus'] == true ||
          j['do_not_disturb_during_focus'] == true ||
          j['do_not_disturb'] == true,
      isPaused:
          j['is_paused'] == 1 ||
          j['is_paused'] == true ||
          j['isPaused'] == 1 ||
          j['isPaused'] == true,
      pausedAtMs: JsonValueParser.toInt(j['paused_at_ms'] ?? j['pausedAtMs']),
      accumulatedMs: JsonValueParser.toInt(
        j['accumulated_ms'] ?? j['accumulatedMs'],
      ),
      pauseStartMs: JsonValueParser.toInt(
        j['pause_start_ms'] ?? j['pauseStartMs'],
      ),
      pauseIntervals: _parsePauseIntervals(j['pause_intervals']),
      planBlockId: (j['plan_block_id'] ?? j['planBlockId'])?.toString(),
      habitUuid: (j['habit_uuid'] ?? j['habitUuid'])?.toString(),
      challengeTaskId: JsonValueParser.toNullableInt(
        j['challenge_task_id'] ?? j['challengeTaskId'],
      ),
      note: j['note']?.toString(),
    );
  }

  static List<PauseInterval> _parsePauseIntervals(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => PauseInterval.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return _parsePauseIntervals(decoded);
      } catch (_) {}
    }
    return [];
  }
}

/// 今日全站专注人均统计
class PomodoroCommunityStats {
  final int avgSeconds;
  final int totalSeconds;
  final int activeUsers;

  const PomodoroCommunityStats({
    required this.avgSeconds,
    required this.totalSeconds,
    required this.activeUsers,
  });

  static PomodoroCommunityStats? tryParse(Map<String, dynamic> json) {
    final hasData = json['has_data'] == true;
    final avgSeconds = _toInt(json['avg_seconds']);
    final totalSeconds = _toInt(json['total_seconds']);
    final activeUsers = _toInt(json['active_users']);
    if (!hasData || avgSeconds <= 0 || activeUsers <= 0) {
      return null;
    }
    return PomodoroCommunityStats(
      avgSeconds: avgSeconds,
      totalSeconds: totalSeconds,
      activeUsers: activeUsers,
    );
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
