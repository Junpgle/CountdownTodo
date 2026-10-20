import '../models.dart';
import 'todo_recurrence_series_edit_service.dart';

class TodoRecurrenceRestorePreview {
  const TodoRecurrenceRestorePreview({
    required this.recordCount,
    required this.occurrenceCount,
    required this.completedCount,
    required this.skippedCount,
    required this.firstDate,
    required this.lastDate,
  });

  final int recordCount;
  final int occurrenceCount;
  final int completedCount;
  final int skippedCount;
  final DateTime firstDate;
  final DateTime lastDate;
}

class TodoRecurrenceRestorePlan {
  const TodoRecurrenceRestorePlan({
    required this.seriesId,
    required this.expectedMemberIds,
    required this.baselines,
    required this.restoredItems,
    required this.preview,
  });

  final String seriesId;
  final Set<String> expectedMemberIds;
  final Map<String, TodoItem> baselines;
  final List<TodoItem> restoredItems;
  final TodoRecurrenceRestorePreview preview;
}

/// Builds a safe, all-or-nothing restore for a recurring series in the trash.
abstract final class TodoRecurrenceRestoreService {
  static TodoRecurrenceRestorePlan? tryPlan({
    required Iterable<TodoItem> todos,
    required String seriesId,
    Set<String>? activeGroupIds,
  }) {
    final normalizedSeriesId = seriesId.trim();
    if (normalizedSeriesId.isEmpty) return null;

    final members = todos
        .where(
          (todo) => TodoRecurrenceSeriesEditService.belongsToSeries(
            todo,
            normalizedSeriesId,
          ),
        )
        .toList(growable: false);
    if (members.length < 2 || members.any((todo) => !todo.isDeleted)) {
      return null;
    }

    final ruleOwners = members
        .where((todo) => todo.recurrence != RecurrenceType.none)
        .toList(growable: false);
    if (ruleOwners.length != 1) return null;

    final datesByDay = <String, DateTime>{};
    final completedDays = <String>{};
    final skippedDays = <String>{};
    for (final todo in members) {
      if (todo.isDone && todo.isSkipped) return null;
      final date = _localDate(todo);
      final dayKey = _dayKey(date);
      datesByDay.putIfAbsent(dayKey, () => date);
      if (todo.isDone) completedDays.add(dayKey);
      if (todo.isSkipped) skippedDays.add(dayKey);
    }
    if (datesByDay.length < 2) return null;
    final dates = datesByDay.values.toList()..sort();

    final baselines = <String, TodoItem>{};
    final restoredItems = <TodoItem>[];
    for (final member in members) {
      final baseline = TodoItem.fromJson(member.toJson());
      baselines[member.id] = baseline;

      final restored = TodoItem.fromJson(member.toJson())..isDeleted = false;
      final groupId = restored.groupId;
      if (activeGroupIds != null &&
          groupId != null &&
          groupId.isNotEmpty &&
          !activeGroupIds.contains(groupId)) {
        restored.groupId = null;
      }
      restored.markAsChanged();
      restoredItems.add(restored);
    }

    return TodoRecurrenceRestorePlan(
      seriesId: normalizedSeriesId,
      expectedMemberIds: members.map((todo) => todo.id).toSet(),
      baselines: baselines,
      restoredItems: restoredItems,
      preview: TodoRecurrenceRestorePreview(
        recordCount: members.length,
        occurrenceCount: datesByDay.length,
        completedCount: completedDays.length,
        skippedCount: skippedDays.length,
        firstDate: dates.first,
        lastDate: dates.last,
      ),
    );
  }

  static DateTime _localDate(TodoItem todo) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';
}
