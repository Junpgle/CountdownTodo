import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'plan_availability_preferences.dart';
import 'plan_availability_repository.dart';
import 'plan_availability_service.dart';
import 'pomodoro_service.dart';

class PlanConflictOverlap {
  const PlanConflictOverlap(this.source, this.start, this.end);
  final PlanBusyInterval source;
  final DateTime start, end;
}

class PlanConflictEntry {
  const PlanConflictEntry(this.block, this.todo, this.overlaps);
  final TodoPlanBlock block;
  final TodoItem? todo;
  final List<PlanConflictOverlap> overlaps;
  bool get canAdjust =>
      PlanAvailabilityService.canReschedule(block) &&
      todo != null &&
      !todo!.isDone &&
      !todo!.isDeleted &&
      !todo!.hasConflict;
}

class PlanConflictReviewResult {
  const PlanConflictReviewResult({
    required this.username,
    required this.start,
    required this.end,
    required this.entries,
    required this.coverage,
    this.unknownTimes = const [],
    this.appOnly = false,
  });
  final String username;
  final DateTime start, end;
  final List<PlanConflictEntry> entries;
  final String coverage;
  final List<String> unknownTimes;
  final bool appOnly;
  bool get complete => unknownTimes.isEmpty;
}

/// A captured existing identity. The editor must submit its last persisted
/// version as well, so a focus retry validates its own save rather than history.
class PlanConflictEditContext {
  PlanConflictEditContext(this.username, TodoPlanBlock block, this.todo)
    : block = TodoPlanBlock.fromJson(block.toJson());
  final String username;
  final TodoPlanBlock block;
  final TodoItem todo;
}

class PlanConflictReviewService {
  const PlanConflictReviewService({
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
      throw const PlanAvailabilityException('账号已切换，请重新打开规划冲突检查');
    }
  }

  Future<PlanConflictReviewResult> read(
    String username,
    DateTime date, {
    int days = 1,
    bool appOnly = false,
  }) async {
    final sources = await availability.readRange(
      username,
      date,
      days: days,
      appOnly: appOnly,
      forceRefresh: true,
    );
    return detect(sources, now: now, appOnly: appOnly);
  }

  /// Pure, half-open intersections. Each real plan appears once, regardless of
  /// source count or the number of dates it crosses in the selected range.
  static PlanConflictReviewResult detect(
    PlanAvailabilityRangeSnapshot data, {
    required DateTime now,
    bool appOnly = false,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final todos = {for (final todo in data.todos) todo.id: todo};
    final byId = {for (final block in data.blocks) block.id: block};
    final entries = <PlanConflictEntry>[];
    for (final block in byId.values) {
      if (!PlanAvailabilityService.occupies(block) ||
          block.endTime <= now.millisecondsSinceEpoch ||
          block.endTime <= block.startTime ||
          block.endTime <= data.start.millisecondsSinceEpoch ||
          block.startTime >= data.end.millisecondsSinceEpoch) {
        continue;
      }
      final overlaps = <PlanConflictOverlap>[];
      final seen = <String>{};
      for (final day in data.days) {
        if (day.date.isBefore(today)) continue;
        final dayEnd = DateTime(
          day.date.year,
          day.date.month,
          day.date.day + 1,
        );
        for (final source in day.busy) {
          if (source.source == PlanBusySource.planBlock &&
              source.id == block.id) {
            continue;
          }
          final startMs = [
            block.startTime,
            source.start.millisecondsSinceEpoch,
            day.date.millisecondsSinceEpoch,
            data.start.millisecondsSinceEpoch,
          ].reduce((a, b) => a > b ? a : b);
          final endMs = [
            block.endTime,
            source.end.millisecondsSinceEpoch,
            dayEnd.millisecondsSinceEpoch,
            data.end.millisecondsSinceEpoch,
          ].reduce((a, b) => a < b ? a : b);
          final key = '${source.source.name}:${source.id}:$startMs:$endMs';
          if (endMs > startMs && seen.add(key)) {
            overlaps.add(
              PlanConflictOverlap(
                source,
                DateTime.fromMillisecondsSinceEpoch(startMs),
                DateTime.fromMillisecondsSinceEpoch(endMs),
              ),
            );
          }
        }
      }
      if (overlaps.isNotEmpty) {
        overlaps.sort((a, b) => a.start.compareTo(b.start));
        entries.add(
          PlanConflictEntry(
            block,
            todos[block.todoId],
            List.unmodifiable(overlaps),
          ),
        );
      }
    }
    entries.sort((a, b) => a.block.startTime.compareTo(b.block.startTime));
    return PlanConflictReviewResult(
      username: data.username,
      start: data.start,
      end: data.end,
      entries: List.unmodifiable(entries),
      coverage: data.coverage,
      appOnly: appOnly,
      unknownTimes: List.unmodifiable({
        for (final day in data.days)
          if (!day.date.isBefore(today))
            for (final unknown in day.unknownTimes)
              '${day.date.month}月${day.date.day}日 · $unknown',
      }),
    );
  }

  Future<PlanConflictEditContext> prepareEdit(
    String username,
    String id, {
    DatabaseExecutor? executor,
    bool allowFocusStatus = false,
  }) async {
    await _account(username);
    final db =
        executor ??
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(username);
    final rows = await db.query(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw const PlanAvailabilityException('规划已不存在，请刷新列表');
    final block = TodoPlanBlock.fromJson(rows.single);
    if (block.isDeleted ||
        !(PlanAvailabilityService.canReschedule(block) ||
            (allowFocusStatus && block.status == TodoPlanStatus.focusing))) {
      throw const PlanAvailabilityException('规划状态已变化，当前不能改期；请查看最新记录');
    }
    if (!allowFocusStatus &&
        (block.endTime <= now.millisecondsSinceEpoch ||
            block.endTime <= block.startTime)) {
      throw const PlanAvailabilityException('规划已结束或时间无效，请查看最新记录');
    }
    final todoRows = await db.query(
      'todos',
      where: 'uuid = ?',
      whereArgs: [block.todoId],
      limit: 1,
    );
    if (todoRows.isEmpty) throw const PlanAvailabilityException('关联待办已失效');
    final todo = TodoItem.fromSql(todoRows.single)..id = block.todoId;
    if (todo.isDone || todo.isDeleted || todo.hasConflict) {
      throw const PlanAvailabilityException('关联待办已完成、删除或存在冲突，不能改期');
    }
    final due = todo.dueDate?.toLocal();
    final deadline = due == null
        ? null
        : todo.isDateOnly
        ? DateTime(due.year, due.month, due.day + 1)
        : due;
    if (!allowFocusStatus && deadline != null && !deadline.isAfter(now)) {
      throw const PlanAvailabilityException('待办截止已过，请先调整截止再改期');
    }
    final run = await PomodoroService.loadRunState();
    if (!allowFocusStatus &&
        run?.phase == PomodoroPhase.focusing &&
        run?.planBlockId == id) {
      throw const PlanAvailabilityException('这条规划正在专注，请查看当前专注');
    }
    await _account(username);
    return PlanConflictEditContext(username, block, todo);
  }

  Future<TodoPlanBlock> save(
    PlanConflictEditContext context,
    TodoPlanBlock input,
    PlanAvailabilitySelection? selection, {
    required TodoPlanBlock expectedBlock,
    PlanAvailabilityQuery? manualQuery,
    TodoPlanStatus? newStatus,
    bool sync = true,
  }) async {
    if (input.id != context.block.id ||
        input.todoId != context.block.todoId ||
        expectedBlock.id != context.block.id ||
        expectedBlock.todoId != context.block.todoId) {
      throw const PlanAvailabilityException('改期只能调整原规划，不能更换待办关联');
    }
    final statusOnly = newStatus == TodoPlanStatus.focusing;
    if (newStatus != null && !statusOnly) {
      throw const PlanAvailabilityException('改期状态无效');
    }
    final preferences = await PlanAvailabilityPreferences.load(
      context.username,
    );
    final avoidance = [
      for (final i in preferences.selectedIndices) preferences.options[i],
    ];
    String avoidanceKey(Iterable<PlanDailyTimeWindow> windows) {
      final keys =
          windows
              .map((window) => '${window.startMinutes}:${window.endMinutes}')
              .toList()
            ..sort();
      return keys.join(',');
    }

    final preferencesKey = avoidanceKey(avoidance);
    Future<void> guard(DatabaseExecutor db) async {
      final currentPreferences = await PlanAvailabilityPreferences.load(
        context.username,
      );
      if (avoidanceKey(
            currentPreferences.selectedIndices.map(
              (i) => currentPreferences.options[i],
            ),
          ) !=
          preferencesKey) {
        throw const PlanAvailabilityException('避让设置已变化，请重新查找；当前输入已保留');
      }
      final latest = await prepareEdit(
        context.username,
        context.block.id,
        executor: db,
        allowFocusStatus: statusOnly,
      );
      if (jsonEncode(latest.block.toJson()) !=
          jsonEncode(expectedBlock.toJson())) {
        throw const PlanAvailabilityException('原规划已变化，请关闭后重新读取；当前输入已保留');
      }
    }

    // Reconstruct from the persisted identity, accepting only editable fields.
    final draft = TodoPlanBlock.fromJson(expectedBlock.toJson())
      ..startTime = input.startTime
      ..endTime = input.endTime
      ..plannedMinutes = (input.endTime - input.startTime) ~/ 60000
      ..remark = input.remark
      ..reminderMinutes = input.reminderMinutes
      ..pomodoroMinutes = input.pomodoroMinutes
      ..pomodoroRounds = input.pomodoroRounds;
    if (statusOnly) {
      if (draft.startTime != expectedBlock.startTime ||
          draft.endTime != expectedBlock.endTime) {
        throw const PlanAvailabilityException('专注状态重试不能同时改动时间');
      }
      return StorageService.savePlanBlockEdited(
        context.username,
        draft,
        expectedVersion: expectedBlock.version,
        expectedUpdatedAt: expectedBlock.updatedAt,
        newStatus: newStatus,
        sync: sync,
        beforeWrite: guard,
      );
    }
    await _account(context.username);
    if (selection == null) {
      final start = DateTime.fromMillisecondsSinceEpoch(draft.startTime);
      final query = PlanAvailabilityQuery(
        username: context.username,
        todoId: context.todo.id,
        date: start,
        minutes: draft.plannedMinutes,
        excludeBlockId: draft.id,
        windowStart: 0,
        windowEnd: 1440,
        appOnly: manualQuery?.appOnly ?? false,
        avoidWindows: avoidance,
      );
      selection = PlanAvailabilitySelection(
        query,
        PlanTimeSlot(start, DateTime.fromMillisecondsSinceEpoch(draft.endTime)),
        await availability.read(query, forceRefresh: true),
      );
    }
    if (avoidanceKey(selection.query.avoidWindows) != preferencesKey) {
      throw const PlanAvailabilityException('避让设置已变化，请重新查找；当前输入已保留');
    }
    if (selection.query.username != context.username ||
        selection.query.todoId != context.todo.id ||
        selection.query.excludeBlockId != context.block.id) {
      throw const PlanAvailabilityException('改期草稿已失效，请重新查找');
    }
    return availability.save(
      selection,
      draft,
      expectedVersion: expectedBlock.version,
      expectedUpdatedAt: expectedBlock.updatedAt,
      sync: sync,
      beforeWrite: guard,
    );
  }
}
