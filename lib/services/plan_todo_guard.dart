import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import 'pomodoro_service.dart';

/// Identity travels with a read/draft, including the independent team member.
class PlanTodoIdentity {
  const PlanTodoIdentity(this.username, this.userId);
  final String username;
  final int userId;
  static Future<PlanTodoIdentity> capture(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final identity = PlanTodoIdentity(
      username,
      prefs.getInt('current_user_id') ?? 0,
    );
    await identity.check();
    return identity;
  }

  Future<void> check() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if ((prefs.getString('current_login_user') ?? 'default') != username ||
        (prefs.getInt('current_user_id') ?? 0) != userId) {
      throw const PlanAvailabilityException('账号或成员身份已切换，请重新打开页面');
    }
  }
}

class PlanTodoGuard {
  static String completionSql(String t, String c) =>
      'CASE WHEN $t.collab_type = 1 AND $c.is_completed IS NOT NULL '
      'THEN $c.is_completed ELSE $t.is_completed END';

  static Future<TodoItem> read(
    DatabaseExecutor db,
    PlanTodoIdentity identity,
    String todoId, {
    bool requireEligible = true,
  }) async {
    await identity.check();
    final rows = await db.rawQuery(
      '''SELECT t.*,
      ${completionSql('t', 'c')} AS member_completed FROM todos t
      LEFT JOIN todo_completions c ON c.todo_uuid=t.uuid AND c.user_id=?
      WHERE t.uuid=? LIMIT 1''',
      [identity.userId, todoId],
    );
    if (rows.isEmpty) throw const PlanAvailabilityException('待办已删除或不存在');
    final row = {
      ...rows.single,
      'is_completed': rows.single['member_completed'],
    };
    final todo = TodoItem.fromSql(row)..id = todoId;
    if (requireEligible && (todo.isDeleted || todo.isDone)) {
      throw const PlanAvailabilityException('待办已完成或失效，请选择未完成的待办');
    }
    if (requireEligible &&
        (todo.hasConflict ||
            todo.id.trim().isEmpty ||
            todo.title.trim().isEmpty)) {
      throw const PlanAvailabilityException('待办存在同步冲突或内容无效，请查看待办');
    }
    await identity.check();
    return todo;
  }

  /// Read raw scoped state: corrupt state is an error, never an idle fallback.
  static Future<PomodoroRunState?> runState(PlanTodoIdentity identity) async {
    await identity.check();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pomodoro_run_state_${identity.username}');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> ||
          json['phase'] is! int ||
          (json['phase'] as int) < 0 ||
          (json['phase'] as int) >= PomodoroPhase.values.length ||
          (json['todoUuid'] != null && json['todoUuid'] is! String) ||
          (json['plan_block_id'] != null && json['plan_block_id'] is! String)) {
        throw const FormatException('Invalid focus identity');
      }
      return PomodoroRunState.fromJson(json);
    } catch (_) {
      throw const PlanAvailabilityException('专注状态无法读取，请先检查专注工作台');
    }
  }

  static Future<Set<String>> focusIds(
    DatabaseExecutor db,
    PlanTodoIdentity identity, {
    bool tolerateAmbiguous = false,
  }) async {
    final run = await runState(identity);
    if (run == null || run.phase != PomodoroPhase.focusing) return {};
    final ids = <String>{if (run.todoUuid?.isNotEmpty == true) run.todoUuid!};
    if (run.planBlockId?.isNotEmpty == true) {
      final rows = await db.query(
        'todo_plan_blocks',
        columns: ['todo_uuid'],
        where: 'uuid=? AND COALESCE(is_deleted,0)=0',
        whereArgs: [run.planBlockId],
      );
      if (rows.isEmpty || rows.single['todo_uuid'] == null) {
        if (tolerateAmbiguous && ids.isNotEmpty) return ids;
        throw const PlanAvailabilityException('专注绑定无法确认，请先检查专注工作台');
      }
      ids.add(rows.single['todo_uuid'] as String);
    }
    if (ids.length > 1 && !tolerateAmbiguous) {
      throw const PlanAvailabilityException('专注绑定不一致，请先检查专注工作台');
    }
    return ids;
  }

  static Future<void> validate(
    DatabaseExecutor db,
    PlanTodoIdentity identity,
    String todoId,
  ) async {
    await read(db, identity, todoId);
    final bad = await db.rawQuery(
      """SELECT uuid FROM todo_plan_blocks WHERE todo_uuid=?
      AND COALESCE(is_deleted,0)=0 AND (status IS NULL OR status NOT IN (0,1,2,3,4,5,6,7)
      OR typeof(start_time)<>'integer' OR typeof(end_time)<>'integer' OR start_time<=0
      OR end_time>8640000000000000 OR end_time<=start_time) LIMIT 1""",
      [todoId],
    );
    if (bad.isNotEmpty) {
      throw const PlanAvailabilityException('安排需检查，请先查看待办关联规划');
    }
    if ((await focusIds(db, identity)).contains(todoId)) {
      throw const PlanAvailabilityException('此待办正在专注或已暂停，请先查看当前专注');
    }
  }

  static Future<void> validateBacklog(
    DatabaseExecutor db,
    PlanBacklogSaveContext context,
    String expected,
    DateTime start,
    DateTime now,
  ) async {
    await validate(db, context.identity, context.todoId);
    final todo = await read(db, context.identity, context.todoId);
    final day = DateTime(start.year, start.month, start.day);
    if (day.isBefore(DateTime(now.year, now.month, now.day)) ||
        (todo.dueDate != null && todo.dueDate!.isBefore(day))) {
      throw const PlanAvailabilityException('目标日期或待办截止已变化，请查看待办');
    }
    if (await arrangements(db, context.todoId, now) != expected) {
      throw const PlanAvailabilityException('已有安排再次变化，请重试保存并确认追加');
    }
    await context.identity.check();
  }

  static Future<String> arrangements(
    DatabaseExecutor db,
    String todoId,
    DateTime now,
  ) async {
    final rows = await db.rawQuery(
      '''SELECT uuid,version,updated_at,start_time,end_time,status
      FROM todo_plan_blocks WHERE todo_uuid=? AND COALESCE(is_deleted,0)=0
      AND (status NOT IN (0,1,2,3,4,5,6,7) OR status IS NULL OR
           start_time IS NULL OR end_time IS NULL OR end_time<=start_time OR
           (status IN (0,2,4,5) AND end_time>?)) ORDER BY uuid''',
      [todoId, now.millisecondsSinceEpoch],
    );
    return jsonEncode(rows);
  }
}

class PlanBacklogSaveContext {
  const PlanBacklogSaveContext(this.identity, this.todoId, this.arrangements);
  final PlanTodoIdentity identity;
  final String todoId;
  final String arrangements;
}
