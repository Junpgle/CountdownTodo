import 'dart:async';

import '../models.dart';
import '../models/plan_availability.dart';
import '../storage_service.dart';
import '../utils/calendar_date_math.dart';
import 'plan_availability_repository.dart';
import 'plan_availability_service.dart';

enum OverdueRescheduleTarget { today, tomorrow, clear }

class OverdueTriageResult {
  final int modifiedCount;
  final OverdueRescheduleTarget target;
  final List<TodoItem> updatedTodos;

  const OverdueTriageResult({
    required this.modifiedCount,
    required this.target,
    required this.updatedTodos,
  });
}

class TodoOverdueTriageService {
  final DateTime Function() clock;
  final PlanAvailabilityRepository planRepository;

  const TodoOverdueTriageService({
    DateTime Function()? clock,
    PlanAvailabilityRepository? planRepository,
  }) : clock = clock ?? _systemClock,
       planRepository = planRepository ?? const PlanAvailabilityRepository();

  static DateTime _systemClock() => DateTime.now();

  /// 筛选出当前未完成、且已过截止日期的真实待办事项。
  /// 自动排除已删除、已完成项，以及特定的重复待办系列占位。
  List<TodoItem> filterOverdueTodos({
    required List<TodoItem> todos,
    Set<String> excludedRecurrenceSeriesIds = const {},
  }) {
    final now = clock();
    return todos.where((item) {
      if (item.isDeleted ||
          item.isDone ||
          item.isSkipped ||
          item.dueDate == null) {
        return false;
      }
      if (excludedRecurrenceSeriesIds.contains(item.recurrenceSeriesId)) {
        return false;
      }
      return item.isOverdueAt(now);
    }).toList();
  }

  /// 计算单条待办顺延后的目标截止时间与是否仅日期。
  ({DateTime? dueDate, bool isDateOnly}) computeRescheduledDueDate(
    TodoItem todo, {
    required OverdueRescheduleTarget target,
  }) {
    final now = clock();

    switch (target) {
      case OverdueRescheduleTarget.clear:
        return (dueDate: null, isDateOnly: false);

      case OverdueRescheduleTarget.today:
        if (todo.isDateOnly) {
          return (
            dueDate: DateTime(now.year, now.month, now.day, 23, 59),
            isDateOnly: true,
          );
        }
        final original = todo.dueDate ?? now;
        final candidate = DateTime(
          now.year,
          now.month,
          now.day,
          original.hour,
          original.minute,
        );
        // 如果今天对应的时刻已经过去，顺延到今日 23:59
        if (!candidate.isAfter(now)) {
          return (
            dueDate: DateTime(now.year, now.month, now.day, 23, 59),
            isDateOnly: false,
          );
        }
        return (dueDate: candidate, isDateOnly: false);

      case OverdueRescheduleTarget.tomorrow:
        final tomorrow = CalendarDateMath.addDays(now, 1);
        if (todo.isDateOnly) {
          return (
            dueDate: DateTime(
              tomorrow.year,
              tomorrow.month,
              tomorrow.day,
              23,
              59,
            ),
            isDateOnly: true,
          );
        }
        final original = todo.dueDate ?? now;
        return (
          dueDate: DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            original.hour,
            original.minute,
          ),
          isDateOnly: false,
        );
    }
  }

  /// 批量更新逾期待办的截止时间，返回修改数量与更新后的全量列表。
  Future<OverdueTriageResult> applyBatchReschedule({
    required String username,
    required List<TodoItem> todosToReschedule,
    required OverdueRescheduleTarget target,
    required List<TodoItem> allTodos,
  }) async {
    final targetIds = todosToReschedule.map((t) => t.id).toSet();
    if (targetIds.isEmpty) {
      return OverdueTriageResult(
        modifiedCount: 0,
        target: target,
        updatedTodos: allTodos,
      );
    }

    final updated = allTodos.map((todo) {
      if (!targetIds.contains(todo.id)) return todo;

      final res = computeRescheduledDueDate(todo, target: target);
      final normalized = TodoItem.normalizeTimeForWrite(
        selectedDate: res.dueDate,
        dueDate: res.dueDate,
        isDateOnly: res.isDateOnly,
      );

      todo.createdDate = normalized.start?.millisecondsSinceEpoch;
      todo.dueDate = normalized.due;
      todo.isAllDay = res.isDateOnly;
      todo.markAsChanged();
      return todo;
    }).toList();

    await StorageService.saveTodos(username, updated);

    return OverdueTriageResult(
      modifiedCount: targetIds.length,
      target: target,
      updatedTodos: updated,
    );
  }

  /// 为单条待办寻找最近的可用规划时段（优先今天，无可用时段且已晚时尝试明天）。
  Future<List<PlanTimeSlot>> findSmartSlots({
    required String username,
    required TodoItem todo,
    int minutes = 45,
  }) async {
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);

    final todayQuery = PlanAvailabilityQuery(
      username: username,
      todoId: todo.id,
      date: today,
      minutes: minutes,
      resultLimit: 3,
    );

    try {
      final todaySnapshot = await planRepository.read(todayQuery);
      final todayResult = PlanAvailabilityService.find(
        todayQuery,
        todaySnapshot,
        now: now,
      );

      if (todayResult.slots.isNotEmpty) {
        return todayResult.slots;
      }
    } catch (_) {
      // 容错降级
    }

    // 若今天无可用时段，尝试查找明天上午
    final tomorrow = today.add(const Duration(days: 1));
    final tomorrowQuery = PlanAvailabilityQuery(
      username: username,
      todoId: todo.id,
      date: tomorrow,
      minutes: minutes,
      resultLimit: 3,
    );

    try {
      final tomorrowSnapshot = await planRepository.read(tomorrowQuery);
      final tomorrowResult = PlanAvailabilityService.find(
        tomorrowQuery,
        tomorrowSnapshot,
        now: tomorrow,
      );
      return tomorrowResult.slots;
    } catch (_) {
      return const [];
    }
  }

  /// 将待办事项一键调度到指定的可用规划时段，并自动将待办截止时间对齐到规划结束时刻。
  Future<TodoPlanBlock> schedulePlanBlock({
    required String username,
    required TodoItem todo,
    required PlanTimeSlot slot,
    required List<TodoItem> allTodos,
  }) async {
    final block = TodoPlanBlock(
      todoId: todo.id,
      titleSnapshot: todo.title,
      startTime: slot.start.millisecondsSinceEpoch,
      endTime: slot.end.millisecondsSinceEpoch,
      plannedMinutes: slot.minutes,
      status: TodoPlanStatus.planned,
      source: TodoPlanSource.manual,
    );

    await StorageService.savePlanBlocks(username, [block]);

    // 更新待办的截止时间，避免继续停留在逾期列表中
    if (todo.dueDate == null || todo.dueDate!.isBefore(slot.end)) {
      final idx = allTodos.indexWhere((t) => t.id == todo.id);
      if (idx != -1) {
        final targetTodo = allTodos[idx];
        targetTodo.dueDate = slot.end;
        targetTodo.isAllDay = false;
        targetTodo.markAsChanged();
        await StorageService.saveTodos(username, allTodos);
      }
    }

    return block;
  }
}
