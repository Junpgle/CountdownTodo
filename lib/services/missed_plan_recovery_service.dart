import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'plan_availability_repository.dart';
import 'plan_availability_service.dart';
import 'pomodoro_service.dart';

/// A read-only, account-scoped source snapshot. No parent relation is persisted.
class MissedPlanRecoveryContext {
  MissedPlanRecoveryContext({
    required this.username,
    required TodoPlanBlock source,
    required this.todo,
    required this.followups,
    required this.hasCurrentFocus,
  }) : source = TodoPlanBlock.fromJson(source.toJson()),
       sourceFingerprint = jsonEncode(source.toJson());

  final String username;
  final TodoPlanBlock source;
  final String sourceFingerprint;
  final TodoItem todo;
  final List<TodoPlanBlock> followups;
  final bool hasCurrentFocus;
  final Map<String, String> acknowledgedFollowups = {};

  void acknowledgeFollowups() {
    acknowledgedFollowups.addAll({
      for (final block in followups) block.id: jsonEncode(block.toJson()),
    });
  }

  int get minutes {
    if (source.plannedMinutes > 0 && source.plannedMinutes <= 1440) {
      return source.plannedMinutes;
    }
    final interval = (source.endTime - source.startTime) ~/ 60000;
    return interval > 0 && interval <= 1440 ? interval : 30;
  }

  List<String> get notices => [
    if (source.plannedMinutes <= 0 || source.plannedMinutes > 1440)
      '原计划时长无效，已使用区间时长或30分钟，请检查。',
    if (![0, 5, 10, 15, 30].contains(source.reminderMinutes) ||
        ![15, 20, 25, 30, 45, 60].contains(source.pomodoroMinutes) ||
        source.pomodoroRounds < 0 ||
        source.pomodoroRounds > 6)
      '原提醒或番茄配置不受支持，已使用默认值，请检查。',
  ];

  TodoPlanBlock draft(DateTime start) => TodoPlanBlock(
    todoId: source.todoId,
    titleSnapshot: todo.title,
    startTime: start.millisecondsSinceEpoch,
    endTime: start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
    plannedMinutes: minutes,
    remark: source.remark,
    reminderMinutes: [0, 5, 10, 15, 30].contains(source.reminderMinutes)
        ? source.reminderMinutes
        : 5,
    pomodoroMinutes: [15, 20, 25, 30, 45, 60].contains(source.pomodoroMinutes)
        ? source.pomodoroMinutes
        : 25,
    pomodoroRounds: source.pomodoroRounds >= 0 && source.pomodoroRounds <= 6
        ? source.pomodoroRounds
        : 0,
  );
}

class MissedPlanRecoveryException extends PlanAvailabilityException {
  const MissedPlanRecoveryException(super.message, {this.todo});
  final TodoItem? todo;
}

/// Only creates a fresh plan. Original history and execution identities remain
/// untouched. Source and displayed followups are checked in the write transaction.
class MissedPlanRecoveryService {
  const MissedPlanRecoveryService({
    this.databaseOverride,
    this.clock,
    this.availabilityOverride,
  });
  final Database? databaseOverride;
  final DateTime Function()? clock;
  final PlanAvailabilityRepository? availabilityOverride;
  DateTime get now => clock?.call() ?? DateTime.now();
  PlanAvailabilityRepository get availability =>
      availabilityOverride ??
      PlanAvailabilityRepository(
        databaseOverride: databaseOverride,
        clock: clock,
      );

  Future<void> _account(String username) async {
    if ((await StorageService.getLoginSession() ?? 'default') != username) {
      throw const MissedPlanRecoveryException('账号已切换，请重新打开重新安排');
    }
  }

  Future<MissedPlanRecoveryContext> read(
    String username,
    String sourceId, {
    DatabaseExecutor? executor,
    String? ignoreBlockId,
  }) async {
    await _account(username);
    final db =
        executor ??
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(username);
    final rows = await db.query(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: [sourceId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const MissedPlanRecoveryException('原规划不存在，请读取最新记录');
    }
    final source = TodoPlanBlock.fromJson(rows.single);
    if (source.isDeleted || source.status != TodoPlanStatus.missed) {
      throw const MissedPlanRecoveryException('原规划已修改、删除或不再漏做，请读取最新记录');
    }
    final todos = await db.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: [source.todoId],
      limit: 1,
    );
    if (todos.isEmpty) {
      throw const MissedPlanRecoveryException('关联待办不存在，请读取最新记录');
    }
    final todo = TodoItem.fromSql(todos.single)..id = source.todoId;
    if (todo.isDeleted || todo.isDone || todo.hasConflict) {
      throw MissedPlanRecoveryException('待办已完成、删除或存在冲突，不能重新安排', todo: todo);
    }
    final due = todo.dueDate?.toLocal();
    final deadline = due == null
        ? null
        : todo.isDateOnly
        ? DateTime(due.year, due.month, due.day + 1)
        : due;
    if (deadline != null && !deadline.isAfter(now)) {
      throw MissedPlanRecoveryException('待办截止已过，请先调整截止后再重新安排', todo: todo);
    }
    final related =
        (await db.query(
              'todo_plan_blocks',
              where: 'todo_uuid = ?',
              whereArgs: [source.todoId],
            ))
            .map(TodoPlanBlock.fromJson)
            .where((b) => !b.isDeleted && b.id != ignoreBlockId)
            .toList();
    final followups =
        related
            .where(
              (b) =>
                  PlanAvailabilityService.canReschedule(b) &&
                  b.endTime > now.millisecondsSinceEpoch,
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final run = await PomodoroService.loadRunState();
    final focusing =
        related.any((b) => b.status == TodoPlanStatus.focusing) ||
        (run != null &&
            run.phase == PomodoroPhase.focusing &&
            run.todoUuid == source.todoId &&
            (ignoreBlockId == null || run.planBlockId != ignoreBlockId));
    await _account(username);
    return MissedPlanRecoveryContext(
      username: username,
      source: source,
      todo: todo,
      followups: followups,
      hasCurrentFocus: focusing,
    );
  }

  Future<MissedPlanRecoveryContext> validate(
    MissedPlanRecoveryContext context, {
    DatabaseExecutor? executor,
    String? ignoreBlockId,
  }) async {
    final latest = await read(
      context.username,
      context.source.id,
      executor: executor,
      ignoreBlockId: ignoreBlockId,
    );
    if (latest.sourceFingerprint != context.sourceFingerprint) {
      throw const MissedPlanRecoveryException('原漏做规划已变化，请关闭后重新读取；当前输入已保留');
    }
    if (latest.hasCurrentFocus) {
      throw const MissedPlanRecoveryException('该待办正在专注，请先查看当前专注');
    }
    if (latest.followups.any(
      (b) => context.acknowledgedFollowups[b.id] != jsonEncode(b.toJson()),
    )) {
      throw const MissedPlanRecoveryException('出现新的或已变化的后续规划，请先查看最新安排');
    }
    return latest;
  }

  Future<TodoPlanBlock> save(
    MissedPlanRecoveryContext context,
    TodoPlanBlock input,
    PlanAvailabilitySelection? selection, {
    PlanAvailabilityQuery? manualQuery,
    int? expectedVersion,
    int? expectedUpdatedAt,
    TodoPlanStatus? newStatus,
    bool sync = true,
  }) async {
    if (input.todoId != context.source.todoId ||
        input.id == context.source.id) {
      throw const MissedPlanRecoveryException('重新安排必须新建并关联原待办实例');
    }
    await validate(
      context,
      ignoreBlockId: expectedVersion == null ? null : input.id,
    );
    final fresh = await read(
      context.username,
      context.source.id,
      ignoreBlockId: input.id,
    );
    final draft = TodoPlanBlock(
      id: input.id,
      todoId: context.source.todoId,
      titleSnapshot: fresh.todo.title,
      startTime: input.startTime,
      endTime: input.endTime,
      plannedMinutes: (input.endTime - input.startTime) ~/ 60000,
      remark: input.remark,
      reminderMinutes: input.reminderMinutes,
      pomodoroMinutes: input.pomodoroMinutes,
      pomodoroRounds: input.pomodoroRounds,
    );
    Future<void> guard(DatabaseExecutor db) async {
      final latest = await validate(
        context,
        executor: db,
        ignoreBlockId: input.id,
      );
      draft.titleSnapshot = latest.todo.title;
    }

    if (newStatus != null) {
      if (expectedVersion == null || newStatus != TodoPlanStatus.focusing) {
        throw const MissedPlanRecoveryException('重新安排状态无效');
      }
      return StorageService.savePlanBlockEdited(
        context.username,
        draft,
        expectedVersion: expectedVersion,
        expectedUpdatedAt: expectedUpdatedAt,
        newStatus: newStatus,
        sync: sync,
        beforeWrite: guard,
      );
    }
    if (selection == null) {
      final start = DateTime.fromMillisecondsSinceEpoch(draft.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(draft.endTime);
      final template = manualQuery;
      final query = PlanAvailabilityQuery(
        username: context.username,
        todoId: draft.todoId,
        date: start,
        minutes: draft.plannedMinutes,
        windowStart: 0,
        windowEnd: 1440,
        excludeBlockId: expectedVersion == null ? null : draft.id,
        appOnly: template?.appOnly ?? false,
        avoidWindows: template?.avoidWindows ?? const [],
      );
      selection = PlanAvailabilitySelection(
        query,
        PlanTimeSlot(start, end),
        await availability.read(query, forceRefresh: true),
      );
    }
    if (selection.query.username != context.username ||
        selection.query.todoId != context.source.todoId ||
        selection.query.excludeBlockId !=
            (expectedVersion == null ? null : draft.id)) {
      throw const MissedPlanRecoveryException('重新安排草稿已失效，请重新查找');
    }
    return availability.save(
      selection,
      draft,
      expectedVersion: expectedVersion,
      expectedUpdatedAt: expectedUpdatedAt,
      sync: sync,
      beforeWrite: guard,
    );
  }
}
