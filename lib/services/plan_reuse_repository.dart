import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import 'database_helper.dart';
import 'plan_todo_guard.dart';
import 'conflict_visibility_service.dart';

/// Settings only: never carries the source plan's mutable execution metadata.
class PlanReuseSettings {
  const PlanReuseSettings({
    required this.minutes,
    required this.remark,
    required this.reminder,
    required this.pomodoro,
    required this.rounds,
  });
  final int minutes, reminder, pomodoro, rounds;
  final String remark;
}

class PlanReuseSeed {
  const PlanReuseSeed(this.identity, this.settings, this.start, this.todo);
  final PlanTodoIdentity identity;
  final PlanReuseSettings settings;
  final DateTime start;
  final TodoItem? todo;
  DateTime get end => start.add(Duration(minutes: settings.minutes));
}

class PlanReuseRepository {
  const PlanReuseRepository({this.database, this.clock});
  final Database? database;
  final DateTime Function()? clock;
  Future<Database> _db(PlanTodoIdentity identity) async {
    await identity.check();
    return database ??
        await DatabaseHelper.instance.databaseForUser(identity.username);
  }

  Future<PlanReuseSeed> read(String username, String id) async {
    final identity = await PlanTodoIdentity.capture(username);
    if (id.trim().isEmpty || id.startsWith('mapped_')) {
      throw const PlanAvailabilityException('此记录不是可复用的真实规划');
    }
    final db = await _db(identity);
    final seed = await db.transaction((txn) async {
      // Missing columns/read errors must surface, never become default settings.
      final columns = (await txn.rawQuery(
        'PRAGMA table_info(todo_plan_blocks)',
      )).map((r) => r['name']).toSet();
      final rows = await txn.query(
        'todo_plan_blocks',
        columns: [
          'uuid',
          'todo_uuid',
          'start_time',
          'end_time',
          'status',
          'source',
          'is_deleted',
          'remark',
          'reminder_minutes',
          'pomodoro_minutes',
          'pomodoro_rounds',
          if (columns.contains('has_conflict')) 'has_conflict',
        ],
        where: 'uuid=?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['is_deleted'] == 1) {
        throw const PlanAvailabilityException('原规划已删除或不存在，请刷新后重试');
      }
      final row = rows.single;
      if (row['has_conflict'] != null && row['has_conflict'] != 0) {
        throw const PlanAvailabilityException('原规划存在同步冲突，请先核对');
      }
      final start = row['start_time'], end = row['end_time'];
      final status = row['status'],
          source = row['source'],
          todoId = row['todo_uuid'];
      if (start is! int ||
          end is! int ||
          start <= 0 ||
          end <= start ||
          end > 8640000000000000 ||
          status is! int ||
          status < 0 ||
          status >= TodoPlanStatus.values.length ||
          source is! int ||
          source < 0 ||
          source >= TodoPlanSource.values.length ||
          source == TodoPlanSource.calendar.index ||
          todoId is! String ||
          todoId.trim().isEmpty ||
          (row['is_deleted'] != null && row['is_deleted'] != 0)) {
        throw const PlanAvailabilityException('原规划内容无效，请先核对');
      }
      final milliseconds = end - start;
      if (milliseconds % 60000 != 0 || milliseconds > 1440 * 60000) {
        throw const PlanAvailabilityException('仅支持复用1–1440整分钟的规划，请手动新建');
      }
      final reminder = row['reminder_minutes'],
          pomodoro = row['pomodoro_minutes'];
      final rounds = row['pomodoro_rounds'], remark = row['remark'];
      if (reminder is! int ||
          ![0, 5, 10, 15, 30].contains(reminder) ||
          pomodoro is! int ||
          ![15, 20, 25, 30, 45, 60].contains(pomodoro) ||
          rounds is! int ||
          rounds < 0 ||
          rounds > 6 ||
          (remark != null && remark is! String)) {
        throw const PlanAvailabilityException('原规划的番茄或提醒设置暂不支持复用，请手动新建');
      }
      final todoRows = await PlanTodoGuard.projectedRows(txn, identity, todoId);
      TodoItem? todo;
      if (todoRows.isNotEmpty) {
        final candidate = TodoItem.fromSql({
          ...todoRows.single,
          'is_completed': todoRows.single['member_completed'],
        })..id = todoId;
        if (!candidate.isDone &&
            !candidate.isDeleted &&
            !ConflictVisibilityService.blocksTodoPlanning(candidate) &&
            candidate.title.trim().isNotEmpty) {
          todo = candidate;
        }
      }
      final now = clock?.call() ?? DateTime.now();
      final original = DateTime.fromMillisecondsSinceEpoch(start);
      final today = DateTime(now.year, now.month, now.day);
      final sourceDay = DateTime(original.year, original.month, original.day);
      final day = sourceDay.isBefore(today) ? today : sourceDay;
      var tentative = DateTime(
        day.year,
        day.month,
        day.day,
        original.hour,
        original.minute,
      );
      final minutes = milliseconds ~/ 60000;
      if (tentative
          .add(Duration(minutes: minutes))
          .isAfter(DateTime(day.year, day.month, day.day + 1))) {
        tentative = day;
      }
      return PlanReuseSeed(
        identity,
        PlanReuseSettings(
          minutes: minutes,
          remark: remark as String? ?? '',
          reminder: reminder,
          pomodoro: pomodoro,
          rounds: rounds,
        ),
        tentative,
        todo,
      );
    });
    await identity.check();
    return seed;
  }

  /// Resolve an uncertain previous commit using the same target UUID.
  Future<TodoPlanBlock?> savedTarget(
    PlanTodoIdentity identity,
    TodoPlanBlock draft,
  ) async {
    final db = await _db(identity);
    final rows = await db.query(
      'todo_plan_blocks',
      where: 'uuid=?',
      whereArgs: [draft.id],
      limit: 1,
    );
    await identity.check();
    if (rows.isEmpty) return null;
    final row = rows.single;
    if (row['has_conflict'] == 1 ||
        row['is_deleted'] != 0 ||
        row['todo_uuid'] != draft.todoId ||
        row['start_time'] != draft.startTime ||
        row['end_time'] != draft.endTime ||
        row['status'] != TodoPlanStatus.planned.index ||
        row['source'] != TodoPlanSource.manual.index ||
        row['planned_minutes'] != draft.plannedMinutes ||
        row['title_snapshot'] != draft.titleSnapshot ||
        (row['remark'] ?? '') != (draft.remark ?? '') ||
        row['reminder_minutes'] != draft.reminderMinutes ||
        row['pomodoro_minutes'] != draft.pomodoroMinutes ||
        row['pomodoro_rounds'] != draft.pomodoroRounds) {
      throw const PlanAvailabilityException('目标规划已存在但内容已变化，请核对已有安排；未重复新建');
    }
    return TodoPlanBlock.fromJson(row);
  }
}
