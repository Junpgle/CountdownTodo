import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../storage_service.dart';
import 'conflict_visibility_service.dart';
import 'database_helper.dart';
import 'pomodoro_service.dart';

enum PlanDragKind { move, resizeStart, resizeEnd }

class PlanDragException implements Exception {
  const PlanDragException(this.message, {this.stale = false});
  final String message;

  /// Invalid identity/qualification can no longer be retried from this snapshot.
  final bool stale;
  @override
  String toString() => message;
}

class PlanDragTimes {
  const PlanDragTimes(this.start, this.end);
  final DateTime start, end;
  int get minutes => end.difference(start).inMinutes;
  bool matches(TodoPlanBlock block) =>
      start.millisecondsSinceEpoch == block.startTime &&
      end.millisecondsSinceEpoch == block.endTime;
}

/// All deltas are measured from pointer-down, not rounded frame by frame.
class PlanDragGeometry {
  static PlanDragTimes adjust({
    required DateTime date,
    required PlanDragTimes original,
    required double deltaMinutes,
    required int step,
    required PlanDragKind kind,
  }) {
    final first = DateTime(date.year, date.month, date.day);
    final last = DateTime(date.year, date.month, date.day + 1);
    if (step <= 0 ||
        !deltaMinutes.isFinite ||
        !original.end.isAfter(original.start) ||
        original.start.isBefore(first) ||
        original.end.isAfter(last)) {
      throw const PlanDragException('跨日或无效规划请在编辑器调整日期', stale: true);
    }
    final delta = (deltaMinutes / step).round() * step;
    if (delta == 0) return original;
    final duration = original.end.difference(original.start);
    DateTime clamp(DateTime value, DateTime lower, DateTime upper) =>
        value.isBefore(lower)
        ? lower
        : value.isAfter(upper)
        ? upper
        : value;
    switch (kind) {
      case PlanDragKind.move:
        final start = clamp(
          original.start.add(Duration(minutes: delta)),
          first,
          last.subtract(duration),
        );
        return PlanDragTimes(start, start.add(duration));
      case PlanDragKind.resizeStart:
        final upper = original.end.subtract(Duration(minutes: step));
        if (upper.isBefore(first)) return original;
        return PlanDragTimes(
          clamp(original.start.add(Duration(minutes: delta)), first, upper),
          original.end,
        );
      case PlanDragKind.resizeEnd:
        final lower = original.start.add(Duration(minutes: step));
        if (lower.isAfter(last)) return original;
        return PlanDragTimes(
          original.start,
          clamp(original.end.add(Duration(minutes: delta)), lower, last),
        );
    }
  }
}

/// Copies are returned to callers, so editing a preview cannot mutate a guard.
class PlanDragSnapshot {
  PlanDragSnapshot(this.username, DateTime date, TodoPlanBlock block)
    : date = DateTime(date.year, date.month, date.day),
      _json = jsonEncode(block.toJson());
  final String username;
  final DateTime date;
  final String _json;
  TodoPlanBlock get block => TodoPlanBlock.fromJson(jsonDecode(_json));
  bool matches(TodoPlanBlock block) => jsonEncode(block.toJson()) == _json;
}

class PlanDragChange {
  PlanDragChange(this.before, TodoPlanBlock after)
    : after = PlanDragSnapshot(before.username, before.date, after);
  final PlanDragSnapshot before, after;
}

/// Explicit timeline placement keeps its existing soft-conflict semantics.
/// No availability lookup, calendar read or preference write happens here.
class PlanDragService {
  PlanDragService({this.databaseOverride, this.clock});
  final Database? databaseOverride;
  final DateTime Function()? clock;
  bool _busy = false;
  DateTime get now => clock?.call() ?? DateTime.now();
  static bool canAdjust(TodoPlanBlock block, DateTime now) =>
      !block.isDeleted &&
      !block.id.startsWith('mapped_') &&
      (block.status == TodoPlanStatus.planned ||
          block.status == TodoPlanStatus.reminded ||
          block.status == TodoPlanStatus.delayed) &&
      block.endTime > now.millisecondsSinceEpoch &&
      block.endTime > block.startTime;

  PlanDragSnapshot capture(
    String username,
    DateTime date,
    TodoPlanBlock block,
  ) {
    if (!canAdjust(block, now)) {
      throw const PlanDragException('规划当前不能拖动，请查看最新安排', stale: true);
    }
    final snapshot = PlanDragSnapshot(username, date, block);
    _times(
      snapshot,
      PlanDragTimes(
        DateTime.fromMillisecondsSinceEpoch(block.startTime),
        DateTime.fromMillisecondsSinceEpoch(block.endTime),
      ),
    );
    return snapshot;
  }

  Future<void> _account(String username) async {
    if ((await StorageService.getLoginSession() ?? 'default') != username) {
      throw const PlanDragException('账号已切换，请重新打开规划', stale: true);
    }
  }

  void _times(PlanDragSnapshot expected, PlanDragTimes target) {
    final first = expected.date;
    final last = DateTime(first.year, first.month, first.day + 1);
    if (target.start.isBefore(first) ||
        target.end.isAfter(last) ||
        !target.end.isAfter(target.start) ||
        target.minutes < 1) {
      throw const PlanDragException('跨日或无效时段请在编辑器调整', stale: true);
    }
    if (!target.end.isAfter(now)) {
      throw const PlanDragException('原时段或目标时段已结束，请查看最新安排', stale: true);
    }
  }

  Future<TodoPlanBlock> _current(
    PlanDragSnapshot expected,
    DatabaseExecutor db,
  ) async {
    await _account(expected.username);
    final original = expected.block;
    final rows = await db.query(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: [original.id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const PlanDragException('规划已删除，请查看最新安排', stale: true);
    }
    final latest = TodoPlanBlock.fromJson(rows.single);
    if (!canAdjust(latest, now) || !expected.matches(latest)) {
      throw const PlanDragException('规划已变化，不能用旧操作覆盖；已保留最新安排', stale: true);
    }
    final todos = await db.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: [latest.todoId],
      limit: 1,
    );
    if (todos.isEmpty) {
      throw const PlanDragException('关联待办已失效', stale: true);
    }
    final todo = TodoItem.fromSql(todos.single)..id = latest.todoId;
    if (todo.isDone ||
        todo.isDeleted ||
        ConflictVisibilityService.blocksTodoPlanning(todo)) {
      throw const PlanDragException('待办已完成、删除或存在冲突，不能调整', stale: true);
    }
    final run = await PomodoroService.loadRunState();
    if (run?.phase == PomodoroPhase.focusing && run?.planBlockId == latest.id) {
      throw const PlanDragException('这条规划正在专注，请查看当前专注', stale: true);
    }
    await _account(expected.username);
    return latest;
  }

  Future<Database> _database(String username) async =>
      databaseOverride ??
      await DatabaseHelper.instance.databaseForUser(username);

  Future<void> validateUndo(PlanDragChange change) async {
    try {
      _times(change.after, _originalTimes(change));
      await _account(change.after.username);
      await _current(change.after, await _database(change.after.username));
    } on PlanDragException {
      rethrow;
    } catch (_) {
      throw const PlanDragException('读取最新规划失败，请重试撤销');
    }
  }

  PlanDragTimes _originalTimes(PlanDragChange change) => PlanDragTimes(
    DateTime.fromMillisecondsSinceEpoch(change.before.block.startTime),
    DateTime.fromMillisecondsSinceEpoch(change.before.block.endTime),
  );

  Future<T> _writeOnce<T>(Future<T> Function() operation) async {
    if (_busy) throw const PlanDragException('正在保存调整，请稍候');
    _busy = true;
    try {
      return await operation();
    } on PlanDragException {
      rethrow;
    } on StateError catch (error) {
      if (error.message.toString().contains('规划已被修改或删除')) {
        throw const PlanDragException('规划已变化，请查看最新安排', stale: true);
      }
      throw const PlanDragException('保存失败，请重试；没有更改规划');
    } catch (_) {
      throw const PlanDragException('保存失败，请重试；没有更改规划');
    } finally {
      _busy = false;
    }
  }

  Future<TodoPlanBlock> _write(
    PlanDragSnapshot expected,
    PlanDragTimes target, {
    required int minutes,
    required bool sync,
  }) async {
    _times(expected, target);
    await _account(expected.username);
    final old = expected.block;
    final draft = TodoPlanBlock.fromJson(old.toJson())
      ..startTime = target.start.millisecondsSinceEpoch
      ..endTime = target.end.millisecondsSinceEpoch
      ..plannedMinutes = minutes;
    return StorageService.savePlanBlockEdited(
      expected.username,
      draft,
      expectedVersion: old.version,
      expectedUpdatedAt: old.updatedAt,
      sync: sync,
      beforeWrite: (db) async {
        _times(expected, target);
        await _current(expected, db);
      },
    );
  }

  Future<PlanDragChange?> save(
    PlanDragSnapshot expected,
    PlanDragTimes target, {
    bool sync = true,
  }) => _writeOnce(() async {
    if (target.matches(expected.block)) {
      await _account(expected.username);
      await _current(expected, await _database(expected.username));
      return null;
    }
    final saved = await _write(
      expected,
      target,
      minutes: target.minutes,
      sync: sync,
    );
    return PlanDragChange(expected, saved);
  });

  Future<TodoPlanBlock> undo(PlanDragChange change, {bool sync = true}) =>
      _writeOnce(
        () => _write(
          change.after,
          _originalTimes(change),
          minutes: change.before.block.plannedMinutes,
          sync: sync,
        ),
      );
}
