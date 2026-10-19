import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../models/plan_weekly_availability.dart';
import '../models/plan_split.dart';
import 'database_helper.dart';
import 'plan_todo_guard.dart';

/// Only user-entered fields. Availability snapshots and approvals never persist.
class PlanDraftFields {
  const PlanDraftFields({
    required this.todoId,
    required this.title,
    required this.start,
    required this.end,
    required this.remark,
    required this.reminder,
    required this.pomodoro,
    required this.rounds,
    required this.origin,
    required this.offsetMinutes,
    this.split,
    this.scheduleOrigin = 'legacy',
    this.weeklyKey,
    this.weeklyIgnored = false,
  });
  final String scheduleOrigin;
  final String? weeklyKey;
  final bool weeklyIgnored;
  final PlanSplitDraft? split;
  final String todoId, title, remark, origin;
  final int start, end, reminder, pomodoro, rounds, offsetMinutes;

  Map<String, Object> toJson() => {
    'todo': todoId,
    'title': title,
    'start': start,
    'end': end,
    'remark': remark,
    'reminder': reminder,
    'pomodoro': pomodoro,
    'rounds': rounds,
    'origin': origin,
    'offset': offsetMinutes,
    if (split != null) 'split': split!.toJson(),
    if (scheduleOrigin != 'legacy') 'scheduleOrigin': scheduleOrigin,
    'weeklyKey': ?weeklyKey,
    if (weeklyIgnored) 'weeklyIgnored': true,
  };
  String get fingerprint => jsonEncode(toJson());

  factory PlanDraftFields.fromJson(Object? value) {
    if (value is! Map ||
        ![
          'todo',
          'title',
          'remark',
          'origin',
        ].every((k) => value[k] is String) ||
        ![
          'start',
          'end',
          'reminder',
          'pomodoro',
          'rounds',
          'offset',
        ].every((k) => value[k] is int)) {
      throw const FormatException('草稿字段格式无效');
    }
    if ((value.containsKey('scheduleOrigin') &&
            ![
              'manual',
              'recommended',
              'legacy',
            ].contains(value['scheduleOrigin'])) ||
        (value.containsKey('weeklyIgnored') &&
            value['weeklyIgnored'] is! bool) ||
        (value.containsKey('weeklyKey') &&
            (value['weeklyKey'] is! String ||
                (value['weeklyKey'] as String).length > 8192))) {
      throw const FormatException('草稿推荐来源无效');
    }
    if (value['weeklyKey'] != null) {
      PlanWeeklyRules.fromJson(jsonDecode(value['weeklyKey']));
    }
    final f = PlanDraftFields(
      scheduleOrigin: value['scheduleOrigin'] ?? 'legacy',
      weeklyKey: value['weeklyKey'],
      weeklyIgnored: value['weeklyIgnored'] ?? false,
      todoId: value['todo'],
      title: value['title'],
      start: value['start'],
      end: value['end'],
      remark: value['remark'],
      reminder: value['reminder'],
      pomodoro: value['pomodoro'],
      rounds: value['rounds'],
      origin: value['origin'],
      offsetMinutes: value['offset'],
      split: value.containsKey('split')
          ? PlanSplitDraft.fromJson(value['split'], '', value['todo'])
          : null,
    );
    if (f.todoId.trim().isEmpty ||
        f.title.trim().isEmpty ||
        f.start <= 0 ||
        f.end <= f.start ||
        f.end > 8640000000000000 ||
        ![0, 5, 10, 15, 30].contains(f.reminder) ||
        ![15, 20, 25, 30, 45, 60].contains(f.pomodoro) ||
        f.rounds < 0 ||
        f.rounds > 6 ||
        f.offsetMinutes.abs() > 1440 ||
        !['timeline', 'todo', 'backlog', 'reuse'].contains(f.origin)) {
      throw const FormatException('草稿内容无效');
    }
    if (f.split != null &&
        (f.split!.slots.first.start.millisecondsSinceEpoch != f.start ||
            f.split!.slots.first.end.millisecondsSinceEpoch != f.end)) {
      throw const FormatException('分段草稿摘要不一致');
    }
    return f;
  }
}

class PlanEditorDraft {
  const PlanEditorDraft(
    this.id,
    this.targetId,
    this.revision,
    this.updatedAt,
    this.fields,
  );
  final String id, targetId;
  final int revision, updatedAt;
  final PlanDraftFields fields;
}

class PlanDraftSummary {
  const PlanDraftSummary(
    this.id,
    this.revision,
    this.title,
    this.start,
    this.end,
    this.updatedAt,
    this.readable, {
    this.parts = 1,
    this.total = 0,
    this.lastEnd = 0,
  });
  final String id, title;
  final int revision, start, end, updatedAt;
  final bool readable;
  final int parts, total, lastEnd;
}

class PlanDraftResume {
  const PlanDraftResume(this.draft, this.todo, this.backlog, this.saved);
  final PlanEditorDraft draft;
  final TodoItem? todo;
  final PlanBacklogSaveContext? backlog;
  final TodoPlanBlock? saved;
}

/// Local table: no oplogs, notifications, refresh of business domains or sync.
class PlanEditorDraftRepository {
  PlanEditorDraftRepository({this.database, this.clock});
  static const table = 'local_plan_editor_drafts';
  static const capacity = 5;
  static const maxPayloadBytes = 256 * 1024;
  final Database? database;
  final DateTime Function()? clock;

  Future<Database> _db(PlanTodoIdentity identity) async {
    await identity.check();
    return database ??
        await DatabaseHelper.instance.databaseForUser(identity.username);
  }

  Future<List<PlanDraftSummary>> list(
    PlanTodoIdentity identity, {
    String? todoId,
  }) async {
    final db = await _db(identity);
    final rows = await db.query(
      table,
      columns: [
        'uuid',
        'target_uuid',
        'revision',
        'title',
        'start_time',
        'end_time',
        'updated_at',
        'format_version',
        'todo_uuid',
        'form_json',
      ],
      where: 'member_id=?${todoId == null ? '' : ' AND todo_uuid=?'}',
      whereArgs: [identity.userId, ?todoId],
      orderBy: 'updated_at DESC, uuid ASC',
      limit: capacity,
    );
    await identity.check();
    return rows
        .map(
          (r) => PlanDraftSummary(
            r['uuid'] is String ? r['uuid'] as String : '',
            r['revision'] is int ? r['revision'] as int : 0,
            r['title'] is String ? r['title'] as String : '无法读取的草稿',
            r['start_time'] is int ? r['start_time'] as int : 0,
            r['end_time'] is int ? r['end_time'] as int : 0,
            r['updated_at'] is int ? r['updated_at'] as int : 0,
            _isReadableRow(r),
            parts: _splitSummary(r)?.slots.length ?? 1,
            total: _splitSummary(r)?.query.total ?? 0,
            lastEnd:
                _splitSummary(r)?.slots.last.end.millisecondsSinceEpoch ?? 0,
          ),
        )
        .toList();
  }

  PlanSplitDraft? _splitSummary(Map<String, Object?> row) {
    try {
      return PlanDraftFields.fromJson(jsonDecode(row['form_json'] as String))
          .split;
    } catch (_) {
      return null;
    }
  }

  bool _isReadableRow(Map<String, Object?> row) {
    try {
      if (![1, 2].contains(row['format_version']) ||
          row['uuid'] is! String ||
          row['target_uuid'] is! String ||
          (row['target_uuid'] as String).isEmpty ||
          row['revision'] is! int ||
          (row['revision'] as int) < 1 ||
          row['todo_uuid'] is! String ||
          row['title'] is! String ||
          row['start_time'] is! int ||
          row['end_time'] is! int ||
          row['updated_at'] is! int ||
          row['form_json'] is! String) {
        return false;
      }
      final fields = PlanDraftFields.fromJson(
        jsonDecode(row['form_json'] as String),
      );
      return row['format_version'] == (fields.split == null ? 1 : 2) &&
          (fields.split == null ||
              fields.split!.ids.first == row['target_uuid']) &&
          row['todo_uuid'] == fields.todoId &&
          row['title'] == fields.title &&
          row['start_time'] == fields.start &&
          row['end_time'] == fields.end;
    } catch (_) {
      return false;
    }
  }

  Future<PlanEditorDraft> read(PlanTodoIdentity identity, String id) async {
    final db = await _db(identity);
    final rows = await db.query(
      table,
      where: 'uuid=? AND member_id=?',
      whereArgs: [id, identity.userId],
      limit: 1,
    );
    await identity.check();
    if (rows.isEmpty) throw StateError('草稿已删除或不属于当前成员');
    final r = rows.single;
    try {
      if (r['uuid'] is! String ||
          r['target_uuid'] is! String ||
          r['revision'] is! int ||
          r['updated_at'] is! int ||
          r['todo_uuid'] is! String ||
          r['title'] is! String ||
          r['start_time'] is! int ||
          r['end_time'] is! int ||
          r['form_json'] is! String ||
          ![1, 2].contains(r['format_version'])) {
        throw const FormatException();
      }
      final fields = PlanDraftFields.fromJson(
        jsonDecode(r['form_json'] as String),
      );
      if (r['format_version'] != (fields.split == null ? 1 : 2) ||
          (fields.split != null &&
              fields.split!.ids.first != r['target_uuid']) ||
          r['todo_uuid'] != fields.todoId ||
          r['title'] != fields.title ||
          r['start_time'] != fields.start ||
          r['end_time'] != fields.end ||
          (r['revision'] as int) < 1 ||
          (r['target_uuid'] as String).isEmpty) {
        throw const FormatException();
      }
      return PlanEditorDraft(
        r['uuid'] as String,
        r['target_uuid'] as String,
        r['revision'] as int,
        r['updated_at'] as int,
        fields,
      );
    } on FormatException {
      throw StateError('草稿无法读取，可返回草稿列表删除；其他草稿不受影响');
    }
  }

  Future<PlanEditorDraft> keep(
    PlanTodoIdentity identity,
    PlanDraftFields fields, {
    PlanEditorDraft? previous,
    required String targetId,
  }) async {
    PlanDraftFields.fromJson(fields.toJson());
    final raw = jsonEncode(fields.toJson());
    if (utf8.encode(raw).length > maxPayloadBytes) {
      throw StateError('草稿内容过大，尚未保留；请先复制备注后缩短内容');
    }
    if ((fields.split != null && fields.split!.ids.first != targetId) ||
        targetId.isEmpty ||
        (previous != null && previous.targetId != targetId)) {
      throw StateError('草稿目标已变化，请重新打开');
    }
    final db = await _db(identity);
    return db.transaction((txn) async {
      await identity.check();
      final id = previous?.id ?? const Uuid().v4();
      final revision = (previous?.revision ?? 0) + 1;
      final now = (clock?.call() ?? DateTime.now()).millisecondsSinceEpoch;
      final data = <String, Object>{
        'uuid': id,
        'member_id': identity.userId,
        'target_uuid': targetId,
        'revision': revision,
        'format_version': fields.split == null ? 1 : 2,
        'todo_uuid': fields.todoId,
        'title': fields.title,
        'start_time': fields.start,
        'end_time': fields.end,
        'updated_at': now,
        'form_json': raw,
      };
      if (previous == null) {
        final count = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT COUNT(*) FROM $table WHERE member_id=?', [
            identity.userId,
          ]),
        )!;
        if (count >= capacity) throw StateError('草稿已满5份，请到规划草稿中管理后再保留');
        await txn.insert(table, data);
      } else {
        final changed = await txn.update(
          table,
          data,
          where: 'uuid=? AND member_id=? AND revision=?',
          whereArgs: [id, identity.userId, previous.revision],
        );
        if (changed != 1) throw StateError('草稿已在其他页面更新或删除，请重新读取');
      }
      await identity.check();
      return PlanEditorDraft(id, targetId, revision, now, fields);
    });
  }

  Future<void> delete(
    PlanTodoIdentity identity,
    String id,
    int revision,
  ) async {
    final db = await _db(identity);
    await db.transaction((txn) async {
      await identity.check();
      final changed = await txn.delete(
        table,
        where: 'uuid=? AND member_id=? AND revision=?',
        whereArgs: [id, identity.userId, revision],
      );
      if (changed != 1) throw StateError('草稿已变化，请刷新后重试');
      await identity.check();
    });
  }

  Future<TodoPlanBlock?> target(
    PlanTodoIdentity identity,
    PlanEditorDraft draft,
  ) async {
    final db = await _db(identity);
    final f = draft.fields;
    final ids = f.split?.ids ?? [draft.targetId];
    final rowsById = <String, Map<String, Object?>>{};
    const queryChunkSize = 500;
    for (var start = 0; start < ids.length; start += queryChunkSize) {
      final end = start + queryChunkSize < ids.length
          ? start + queryChunkSize
          : ids.length;
      final chunk = ids.sublist(start, end);
      final rows = await db.query(
        'todo_plan_blocks',
        where: 'uuid IN (${List.filled(chunk.length, '?').join(', ')})',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final id = row['uuid']?.toString();
        if (id != null) rowsById.putIfAbsent(id, () => row);
      }
    }

    final saved = <TodoPlanBlock>[];
    for (var i = 0; i < ids.length; i++) {
      await identity.check();
      final row = rowsById[ids[i]];
      if (row == null) continue;
      final b = TodoPlanBlock.fromJson(row);
      final start = f.split?.slots[i].start.millisecondsSinceEpoch ?? f.start;
      final end = f.split?.slots[i].end.millisecondsSinceEpoch ?? f.end;
      if (row['has_conflict'] == 1 ||
          b.isDeleted ||
          b.todoId != f.todoId ||
          b.startTime != start ||
          b.endTime != end ||
          (b.remark ?? '') != f.remark ||
          b.reminderMinutes != f.reminder ||
          b.pomodoroMinutes != f.pomodoro ||
          b.pomodoroRounds != f.rounds) {
        throw StateError('这份草稿对应的规划已变化或删除，请查看最新安排');
      }
      saved.add(b);
    }
    if (saved.isNotEmpty && saved.length != ids.length) {
      throw StateError('部分分段目标已存在，请核对已有安排，未新增任何分段');
    }
    return saved.firstOrNull;
  }

  Future<PlanDraftResume> prepare(
    PlanTodoIdentity identity,
    String id,
    int revision,
  ) async {
    final draft = await read(identity, id);
    if (draft.revision != revision) throw StateError('草稿已更新，请刷新列表');
    final saved = await target(identity, draft);
    if (saved != null) return PlanDraftResume(draft, null, null, saved);
    final db = await _db(identity);
    await PlanTodoGuard.validate(db, identity, draft.fields.todoId);
    final todo = await PlanTodoGuard.read(db, identity, draft.fields.todoId);
    final backlog = draft.fields.origin == 'backlog'
        ? PlanBacklogSaveContext(
            identity,
            todo.id,
            await PlanTodoGuard.arrangements(
              db,
              todo.id,
              clock?.call() ?? DateTime.now(),
            ),
          )
        : null;
    await validateRevision(db, identity, draft);
    return PlanDraftResume(draft, todo, backlog, null);
  }

  Future<void> validateRevision(
    DatabaseExecutor executor,
    PlanTodoIdentity identity,
    PlanEditorDraft draft,
  ) async {
    await identity.check();
    final rows = await executor.query(
      table,
      columns: ['revision', 'target_uuid'],
      where: 'uuid=? AND member_id=?',
      whereArgs: [draft.id, identity.userId],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.single['revision'] != draft.revision ||
        rows.single['target_uuid'] != draft.targetId) {
      throw StateError('草稿已在其他页面更新或删除，请重新读取后保存');
    }
    await identity.check();
  }
}
