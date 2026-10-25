import '../models.dart';
import 'todo_recurrence_date_service.dart';
import 'todo_recurrence_series_edit_service.dart';

enum TodoRecurrenceDeleteScope { occurrence, future, series }

class TodoRecurrenceDeletePreview {
  const TodoRecurrenceDeletePreview({
    required this.occurrenceCount,
    required this.recordCount,
    required this.completedCount,
    required this.skippedCount,
  });

  final int occurrenceCount;
  final int recordCount;
  final int completedCount;
  final int skippedCount;
}

class TodoRecurrenceDeletePlan {
  const TodoRecurrenceDeletePlan({
    required this.seriesId,
    required this.scope,
    required this.expectedActiveMemberIds,
    required this.baselines,
    required this.affectedIds,
    required this.revivalBarrierIds,
    required this.changedItems,
    required this.preview,
  });

  final String seriesId;
  final TodoRecurrenceDeleteScope scope;
  final Set<String> expectedActiveMemberIds;
  final Map<String, TodoItem> baselines;
  final Set<String> affectedIds;

  /// Includes already-deleted duplicates for the affected logical periods.
  /// They must not be revived by the in-memory recurrence dedupe repair.
  final Set<String> revivalBarrierIds;
  final List<TodoItem> changedItems;
  final TodoRecurrenceDeletePreview preview;
}

/// Builds and previews a soft-delete operation for a recurring todo series.
/// Persistence and optimistic concurrency checks are owned by StorageService.
abstract final class TodoRecurrenceDeleteService {
  static bool isRecurring(TodoItem todo) =>
      TodoRecurrenceSeriesEditService.seriesIdFor(todo) != null;

  static TodoRecurrenceDeletePreview preview({
    required Iterable<TodoItem> todos,
    required String todoId,
    required TodoRecurrenceDeleteScope scope,
  }) => _build(
    todos: todos,
    todoId: todoId,
    scope: scope,
    requireSuccessor: false,
  ).preview;

  static TodoRecurrenceDeletePlan plan({
    required Iterable<TodoItem> todos,
    required String todoId,
    required TodoRecurrenceDeleteScope scope,
  }) => _build(todos: todos, todoId: todoId, scope: scope);

  static TodoRecurrenceDeletePlan _build({
    required Iterable<TodoItem> todos,
    required String todoId,
    required TodoRecurrenceDeleteScope scope,
    bool requireSuccessor = true,
  }) {
    final snapshot = todos.toList(growable: false);
    final selected = snapshot.where((todo) => todo.id == todoId).firstOrNull;
    if (selected == null || selected.isDeleted) {
      throw StateError('待办已不存在或已移入回收站，请重新载入');
    }
    final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(selected);
    if (seriesId == null) throw StateError('这不是重复待办');

    final allMembers = snapshot
        .where(
          (todo) =>
              TodoRecurrenceSeriesEditService.belongsToSeries(todo, seriesId),
        )
        .toList();
    final activeMembers = allMembers.where((todo) => !todo.isDeleted).toList()
      ..sort(_compareOccurrences);
    if (!activeMembers.any((todo) => todo.id == selected.id)) {
      throw StateError('当前期次已变化，请重新载入');
    }

    final targetDay = _dateOnly(selected);
    final affected = switch (scope) {
      TodoRecurrenceDeleteScope.occurrence =>
        activeMembers.where((todo) => _dateOnly(todo) == targetDay).toList(),
      TodoRecurrenceDeleteScope.future =>
        activeMembers
            .where((todo) => !_dateOnly(todo).isBefore(targetDay))
            .toList(),
      TodoRecurrenceDeleteScope.series => activeMembers,
    };
    if (affected.isEmpty) throw StateError('没有可移入回收站的期次');
    final retainedBeforeTarget = scope == TodoRecurrenceDeleteScope.future
        ? activeMembers
              .where((todo) => _dateOnly(todo).isBefore(targetDay))
              .toList()
        : const <TodoItem>[];

    final affectedDays = affected.map(_dayKey).toSet();
    final revivalBarrierIds = allMembers
        .where((todo) => affectedDays.contains(_dayKey(todo)))
        .map((todo) => todo.id)
        .toSet();
    final completedDays = affected
        .where((todo) => todo.isDone)
        .map(_dayKey)
        .toSet();
    final skippedDays = affected
        .where((todo) => todo.isSkipped)
        .map(_dayKey)
        .toSet();
    final preview = TodoRecurrenceDeletePreview(
      occurrenceCount: affectedDays.length,
      recordCount: affected.length,
      completedCount: completedDays.length,
      skippedCount: skippedDays.length,
    );

    final baselines = <String, TodoItem>{
      for (final todo in activeMembers) todo.id: todo.detachedCopy(),
    };
    final updates = <String, TodoItem>{};
    TodoItem edit(String id) => updates.putIfAbsent(
      id,
      () => activeMembers.firstWhere((todo) => todo.id == id).detachedCopy(),
    );

    final ruleOwners = activeMembers
        .where((todo) => todo.recurrence != RecurrenceType.none)
        .toList();
    final activeRule = ruleOwners.isEmpty ? null : ruleOwners.last;

    for (final occurrence in affected) {
      final changed = edit(occurrence.id)..isDeleted = true;
      if (scope == TodoRecurrenceDeleteScope.occurrence ||
          (scope == TodoRecurrenceDeleteScope.future &&
              retainedBeforeTarget.isNotEmpty)) {
        if (changed.recurrence != RecurrenceType.none) {
          changed.recurrence = RecurrenceType.none;
        }
      }
    }

    switch (scope) {
      case TodoRecurrenceDeleteScope.occurrence:
        if (activeRule != null) {
          for (final owner in ruleOwners) {
            if (owner.id != activeRule.id) {
              edit(owner.id).recurrence = RecurrenceType.none;
            }
          }
          if (affected.any((todo) => todo.id == activeRule.id)) {
            final successor = activeMembers
                .where((todo) => _dateOnly(todo).isAfter(targetDay))
                .firstOrNull;
            if (successor != null) {
              _transferRule(from: activeRule, to: edit(successor.id));
            } else if (requireSuccessor && _hasNextOccurrence(activeRule)) {
              throw StateError('后续期次尚未生成，请刷新列表后重试');
            }
          }
        }
        break;
      case TodoRecurrenceDeleteScope.future:
        final retained = retainedBeforeTarget;
        if (retained.isNotEmpty && activeRule != null) {
          for (final owner in ruleOwners) {
            edit(owner.id).recurrence = RecurrenceType.none;
          }
          final carrier = edit(retained.last.id);
          _transferRule(from: activeRule, to: carrier);
          final retainedDay = _dateOnly(retained.last);
          final existingEnd = activeRule.recurrenceEndDate;
          carrier.recurrenceEndDate =
              existingEnd != null &&
                  _dateOnlyEpoch(existingEnd).isBefore(retainedDay)
              ? existingEnd
              : retainedDay;
        }
        break;
      case TodoRecurrenceDeleteScope.series:
        // Keep the rule on its soft-deleted row so restoring that row can
        // resume the original series. Deleted rows are never active roots.
        break;
    }

    for (final item in updates.values) {
      item.markAsChanged();
    }

    return TodoRecurrenceDeletePlan(
      seriesId: seriesId,
      scope: scope,
      expectedActiveMemberIds: activeMembers.map((todo) => todo.id).toSet(),
      baselines: baselines,
      affectedIds: affected.map((todo) => todo.id).toSet(),
      revivalBarrierIds: revivalBarrierIds,
      changedItems: updates.values.toList(growable: false),
      preview: preview,
    );
  }

  static void _transferRule({required TodoItem from, required TodoItem to}) {
    to
      ..recurrence = from.recurrence
      ..customIntervalDays = from.customIntervalDays
      ..recurrenceEndDate = from.recurrenceEndDate;
  }

  static bool _hasNextOccurrence(TodoItem rule) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      rule.createdDate ?? rule.createdAt,
      isUtc: true,
    ).toLocal();
    final next = TodoRecurrenceDateService.nextDate(start, rule);
    if (next == null) return false;
    final end = rule.recurrenceEndDate;
    if (end == null) return true;
    return !_dateOnlyEpoch(end)
        .isBefore(DateTime(next.year, next.month, next.day));
  }

  static int _compareOccurrences(TodoItem left, TodoItem right) {
    final dateCompare = _dateOnly(left).compareTo(_dateOnly(right));
    if (dateCompare != 0) return dateCompare;
    return left.id.compareTo(right.id);
  }

  static DateTime _dateOnly(TodoItem todo) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _dateOnlyEpoch(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static String _dayKey(TodoItem todo) {
    final date = _dateOnly(todo);
    return '${date.year}-${date.month}-${date.day}';
  }
}
