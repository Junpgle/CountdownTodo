import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import 'conflict_visibility_service.dart';
import '../models/plan_availability.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'plan_todo_guard.dart';

String _canonical(Map<String, Object?> value) => jsonEncode({
  for (final key in value.keys.toList()..sort()) key: value[key],
});

class PlanManualCompletionRequest {
  PlanManualCompletionRequest._(
    this._owner,
    this.identity,
    this._row,
    this._todo,
    this._focus,
  );
  final PlanManualCompletionService _owner;
  final PlanTodoIdentity identity;
  final Map<String, Object?> _row;
  final String _todo, _focus;
  TodoPlanBlock get block =>
      TodoPlanBlock.fromJson(Map<String, dynamic>.from(_row));
  Future<PlanManualCompletionReceipt>? _flight;
}

class PlanManualCompletionReceipt {
  PlanManualCompletionReceipt._(
    this.service,
    this.request,
    this._after,
    this.completedAt,
  );
  final PlanManualCompletionService service;
  final PlanManualCompletionRequest request;
  final Map<String, Object?> _after;
  final DateTime completedAt;
  DateTime get expiresAt => completedAt.add(const Duration(seconds: 10));
  String get id => request.block.id;
  PlanTodoIdentity get identity => request.identity;
  bool _invalid = false, _used = false;
  Future<TodoPlanBlock>? _undoFlight;
  bool get canUndo =>
      !_invalid &&
      !_used &&
      !service.now.isBefore(completedAt) &&
      service.now.isBefore(expiresAt);
  void invalidate() => _invalid = true;
}

/// Explicit historical status changes only. No focus fabrication or todo writes.
class PlanManualCompletionService {
  PlanManualCompletionService({
    this.databaseOverride,
    this.clock,
    this.onQuery,
  });
  final Database? databaseOverride;
  final DateTime Function()? clock;
  final void Function(String sql, int rows)? onQuery;
  DateTime get now => clock?.call() ?? DateTime.now();

  static bool supports(TodoPlanBlock block, DateTime now) =>
      !block.id.startsWith('mapped_') &&
      !block.isDeleted &&
      block.startTime > 0 &&
      block.endTime > block.startTime &&
      block.endTime <= now.millisecondsSinceEpoch &&
      {
        TodoPlanStatus.planned,
        TodoPlanStatus.reminded,
        TodoPlanStatus.delayed,
        TodoPlanStatus.missed,
      }.contains(block.status);

  Future<Database> _database(PlanTodoIdentity identity) async {
    await identity.check();
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('migration_marker_${identity.username}_v4') ?? false) &&
        ((prefs.getStringList('user_todos_${identity.username}') ?? [])
                .isNotEmpty ||
            (prefs.getStringList('user_todos') ?? []).isNotEmpty)) {
      throw const PlanAvailabilityException('历史存储尚未初始化，请返回首页加载后重试');
    }
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(identity.username);
    final legacy = ['pomodoro_records_${identity.username}', 'pomodoro_records']
        .any((key) {
          final raw = prefs.getString(key)?.trim();
          return raw != null && raw.isNotEmpty && raw != '[]';
        });
    if (legacy &&
        (Sqflite.firstIntValue(
                  await db.rawQuery('SELECT COUNT(*) FROM pomodoro_records'),
                ) ??
                0) ==
            0) {
      throw const PlanAvailabilityException('历史专注尚未初始化，请先打开专注页后重试');
    }
    return db;
  }

  Future<Map<String, Object?>> _row(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'todo_plan_blocks',
      where: 'uuid=?',
      whereArgs: [id],
      limit: 2,
    );
    if (rows.length != 1) {
      throw const PlanAvailabilityException('规划已删除或不存在，请重新查看');
    }
    final row = rows.single;
    final start = row['start_time'],
        end = row['end_time'],
        status = row['status'];
    if (id.trim().isEmpty ||
        id.startsWith('mapped_') ||
        row['is_deleted'] != 0 ||
        row['has_conflict'] == 1 ||
        start is! int ||
        end is! int ||
        start <= 0 ||
        end <= start ||
        end > 8640000000000000 ||
        status is! int ||
        status < 0 ||
        status >= TodoPlanStatus.values.length ||
        row['version'] is! int ||
        (row['version'] as int) < 1 ||
        row['updated_at'] is! int ||
        row['source'] is! int ||
        (row['source'] as int) < 0 ||
        (row['source'] as int) > 2 ||
        (row['todo_uuid']?.toString().trim().isEmpty ?? true)) {
      throw const PlanAvailabilityException('规划数据无效或存在冲突，请先核对');
    }
    return Map.unmodifiable(row);
  }

  Future<String> _todo(
    DatabaseExecutor db,
    PlanTodoIdentity identity,
    TodoPlanBlock block,
  ) async {
    final rows = await PlanTodoGuard.projectedRows(db, identity, block.todoId);
    if (rows.length != 1) throw const PlanAvailabilityException('关联待办已删除或不存在');
    final todo = TodoItem.fromSql({
      ...rows.single,
      'is_completed': rows.single['member_completed'],
    })..id = block.todoId;
    if (todo.isDeleted ||
        ConflictVisibilityService.blocksTodoPlanning(todo) ||
        todo.title.trim().isEmpty) {
      throw const PlanAvailabilityException('关联待办已失效或存在冲突，请先核对');
    }
    if ((todo.teamUuid?.trim() ?? '').isNotEmpty || todo.collabType != 0) {
      throw const PlanAvailabilityException('团队规划暂不支持手动确认完成');
    }
    if ((await PlanTodoGuard.focusIds(db, identity)).contains(todo.id)) {
      throw const PlanAvailabilityException('此待办正在专注或已暂停，请先查看专注状态');
    }
    // Remote or inconsistent persisted focus markers cannot be treated as idle.
    final focusing = await db.query(
      'todo_plan_blocks',
      columns: ['uuid'],
      where: 'todo_uuid=? AND COALESCE(is_deleted,0)=0 AND status=5',
      whereArgs: [todo.id],
      limit: 1,
    );
    if (focusing.isNotEmpty) {
      throw const PlanAvailabilityException('关联规划仍处于专注状态，请先核对');
    }
    return _canonical(rows.single);
  }

  Future<String> _focus(DatabaseExecutor db, TodoPlanBlock block) async {
    final hasConflict = (await db.rawQuery(
      'PRAGMA table_info(pomodoro_records)',
    )).any((r) => r['name'] == 'has_conflict');
    final sink = _DigestSink();
    final hash = sha256.startChunkedConversion(sink);
    var cursor = -1;
    try {
      while (true) {
        // Includes tombstones and explicit/legacy bindings, plus same-task
        // overlapping candidates. Unrelated history never becomes Dart models.
        final sql =
            '''SELECT id,uuid,todo_uuid,plan_block_id,start_time,end_time,
          planned_duration,actual_duration,status,total_pause_seconds,pause_intervals,
          version,updated_at,is_deleted${hasConflict ? ',has_conflict' : ''} FROM pomodoro_records
          WHERE id>? AND (plan_block_id=? OR
            (LENGTH(COALESCE(uuid,''))>0 AND instr(',' || ? || ',', ',' || uuid || ',')>0) OR
            (todo_uuid=? AND (typeof(start_time)<>'integer' OR
              (start_time<? AND (end_time IS NULL OR typeof(end_time)<>'integer' OR end_time>?)))))
          ORDER BY id LIMIT 200''';
        final rows = await db.rawQuery(sql, [
          cursor,
          block.id,
          block.pomodoroRecordIds.join(','),
          block.todoId,
          block.endTime,
          block.startTime,
        ]);
        onQuery?.call(sql, rows.length);
        for (final row in rows) {
          hash.add(utf8.encode('${_canonical(row)}\n'));
        }
        if (rows.length < 200) break;
        cursor = rows.last['id'] as int;
      }
    } finally {
      hash.close();
    }
    return sink.digest.toString();
  }

  Future<PlanManualCompletionRequest> prepare(
    String username,
    String id, {
    TodoPlanBlock? expected,
  }) async {
    final identity = await PlanTodoIdentity.capture(username);
    final db = await _database(identity);
    final request = await db.transaction((tx) async {
      final row = await _row(tx, id);
      final block = TodoPlanBlock.fromJson(Map<String, dynamic>.from(row));
      if (!supports(block, now)) {
        throw const PlanAvailabilityException('仅可确认已结束且尚未完成的规划');
      }
      if (expected != null &&
          _canonical(expected.toDbJson()) != _canonical(block.toDbJson())) {
        throw const PlanAvailabilityException('规划已变化，请关闭后重新读取；当前输入已保留');
      }
      final todo = await _todo(tx, identity, block);
      final focus = await _focus(tx, block);
      await identity.check();
      return PlanManualCompletionRequest._(this, identity, row, todo, focus);
    });
    await identity.check();
    return request;
  }

  Future<void> _guard(
    DatabaseExecutor tx,
    PlanManualCompletionRequest request,
    Map<String, Object?> expected,
  ) async {
    await request.identity.check();
    final row = await _row(tx, request.block.id);
    if (_canonical(row) != _canonical(expected) ||
        await _todo(tx, request.identity, request.block) != request._todo ||
        await _focus(tx, request.block) != request._focus) {
      throw const PlanAvailabilityException('规划或投入已变化，请重新查看');
    }
    await request.identity.check();
  }

  Future<Map<String, Object?>> _write(
    DatabaseExecutor tx,
    Map<String, Object?> before,
    TodoPlanStatus status,
  ) async {
    final version = (before['version'] as int) + 1;
    final updated = max(
      now.millisecondsSinceEpoch,
      (before['updated_at'] as int) + 1,
    );
    final changed = await tx.update(
      'todo_plan_blocks',
      {'status': status.index, 'version': version, 'updated_at': updated},
      where:
          'uuid=? AND version=? AND updated_at=? AND status=? AND is_deleted=0',
      whereArgs: [
        before['uuid'],
        before['version'],
        before['updated_at'],
        before['status'],
      ],
    );
    if (changed != 1) throw const PlanAvailabilityException('规划已变化，请重新查看');
    final after = {
      ...before,
      'status': status.index,
      'version': version,
      'updated_at': updated,
    };
    final data = TodoPlanBlock.fromJson(Map<String, dynamic>.from(after))
        .toDbJson();
    await tx.insert('op_logs', {
      'op_type': 'UPSERT',
      'target_table': 'todo_plan_blocks',
      'target_uuid': before['uuid'],
      'data_json': jsonEncode(data),
      'timestamp': updated,
      'is_synced': 0,
      'sync_error': '',
    });
    return Map.unmodifiable(after);
  }

  void _publish(String username, bool sync) {
    if (sync) StorageService.requestSync(username);
    StorageService.triggerRefresh({DataRefreshDomain.planBlocks});
  }

  Future<PlanManualCompletionReceipt> confirm(
    PlanManualCompletionRequest request, {
    bool sync = true,
  }) async {
    if (request._owner != this) {
      throw const PlanAvailabilityException('确认来源已变化，请重新打开');
    }
    await request.identity.check();
    return request._flight ??= _confirm(request, sync).catchError((
      Object e,
      StackTrace st,
    ) {
      request._flight = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<PlanManualCompletionReceipt> _confirm(
    PlanManualCompletionRequest request,
    bool sync,
  ) async {
    final db = await _database(request.identity);
    final after = await db.transaction((tx) async {
      await _guard(tx, request, request._row);
      if (!supports(request.block, now)) {
        throw const PlanAvailabilityException('规划资格已变化，请重新查看');
      }
      final after = await _write(tx, request._row, TodoPlanStatus.finished);
      await request.identity.check();
      return after;
    });
    final receipt = PlanManualCompletionReceipt._(this, request, after, now);
    // Local receipt exists before best-effort sync dispatch; sync never changes
    // whether this SQLite transaction actually committed.
    try {
      _publish(request.identity.username, sync);
    } catch (_) {
      /* oplog retained */
    }
    return receipt;
  }

  Future<void> verifyUnchanged(PlanManualCompletionReceipt receipt) async {
    final db = await _database(receipt.identity);
    await db.transaction((tx) => _guard(tx, receipt.request, receipt._after));
  }

  Future<void> ensureCompleted(PlanManualCompletionReceipt receipt) async {
    final db = await _database(receipt.identity);
    final row = await _row(db, receipt.id);
    if (_canonical(row) != _canonical(receipt._after)) {
      throw const PlanAvailabilityException('规划已变化，请重新查看');
    }
    await receipt.identity.check();
  }

  Future<TodoPlanBlock> undo(
    PlanManualCompletionReceipt receipt, {
    bool sync = true,
  }) {
    if (receipt.service != this || !receipt.canUndo) {
      return Future.error(const PlanAvailabilityException('撤销已失效，请重新查看规划'));
    }
    return receipt._undoFlight ??= _undo(receipt, sync).catchError((
      Object e,
      StackTrace st,
    ) {
      receipt._undoFlight = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<TodoPlanBlock> _undo(
    PlanManualCompletionReceipt receipt,
    bool sync,
  ) async {
    final request = receipt.request;
    final db = await _database(request.identity);
    final after = await db.transaction((tx) async {
      if (!receipt.canUndo) {
        throw const PlanAvailabilityException('撤销已失效，请重新查看规划');
      }
      await _guard(tx, request, receipt._after);
      if (!receipt.canUndo) {
        throw const PlanAvailabilityException('撤销已失效，请重新查看规划');
      }
      final row = await _write(tx, receipt._after, request.block.status);
      await request.identity.check();
      return row;
    });
    receipt._used = true;
    try {
      _publish(request.identity.username, sync);
    } catch (_) {
      /* oplog retained */
    }
    return TodoPlanBlock.fromJson(Map<String, dynamic>.from(after));
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;
  @override
  void add(Digest value) => digest = value;
  @override
  void close() {}
}
