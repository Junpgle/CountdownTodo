import '../models.dart';
import 'todo_recurrence_series_edit_service.dart';

class TodoTrashMultiRestorePreview {
  const TodoTrashMultiRestorePreview({
    required this.recordCount,
    required this.seriesCount,
    required this.completedCount,
    required this.skippedCount,
    required this.firstDate,
    required this.lastDate,
  });

  final int recordCount;
  final int seriesCount;
  final int completedCount;
  final int skippedCount;
  final DateTime firstDate;
  final DateTime lastDate;
}

class TodoTrashMultiRestorePlan {
  const TodoTrashMultiRestorePlan({
    required this.selectedTodoIds,
    required this.baselines,
    required this.restoredItems,
    required this.revivalBarrierIds,
    required this.preview,
  });

  final Set<String> selectedTodoIds;
  final Map<String, TodoItem> baselines;
  final List<TodoItem> restoredItems;
  final Set<String> revivalBarrierIds;
  final TodoTrashMultiRestorePreview preview;
}

/// Builds an exact, all-or-nothing restore plan for selected trash records.
abstract final class TodoTrashMultiRestoreService {
  static TodoTrashMultiRestorePlan? tryPlan({
    required Iterable<TodoItem> todos,
    required Iterable<String> selectedTodoIds,
    Set<String>? activeGroupIds,
  }) {
    final requestedIds = selectedTodoIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (requestedIds.isEmpty) return null;

    final todosById = <String, TodoItem>{};
    for (final todo in todos) {
      todosById.putIfAbsent(todo.id, () => todo);
    }
    if (requestedIds.any((id) => !todosById.containsKey(id))) return null;

    final selected = requestedIds.map((id) => todosById[id]!).toList()
      ..sort((left, right) {
        final dateComparison = _localDate(left).compareTo(_localDate(right));
        return dateComparison != 0
            ? dateComparison
            : left.id.compareTo(right.id);
      });
    if (selected.any((todo) => !todo.isDeleted)) return null;
    if (selected.any((todo) => todo.isDone && todo.isSkipped)) return null;

    final baselines = <String, TodoItem>{};
    final restoredItems = <TodoItem>[];
    final seriesIds = <String>{};
    final revivalBarrierIds = <String>{};
    for (final todo in selected) {
      final baseline = TodoItem.fromJson(todo.toJson());
      baselines[todo.id] = baseline;

      final restored = TodoItem.fromJson(baseline.toJson())..isDeleted = false;
      final groupId = restored.groupId;
      if (activeGroupIds != null &&
          groupId != null &&
          groupId.isNotEmpty &&
          !activeGroupIds.contains(groupId)) {
        restored.groupId = null;
      }
      restored.markAsChanged();
      restoredItems.add(restored);

      final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(todo);
      if (seriesId != null) {
        seriesIds.add(seriesId);
        revivalBarrierIds.add(todo.id);
      }
    }

    final dates = selected.map(_localDate).toList()..sort();
    return TodoTrashMultiRestorePlan(
      selectedTodoIds: requestedIds,
      baselines: baselines,
      restoredItems: restoredItems,
      revivalBarrierIds: revivalBarrierIds,
      preview: TodoTrashMultiRestorePreview(
        recordCount: selected.length,
        seriesCount: seriesIds.length,
        completedCount: selected.where((todo) => todo.isDone).length,
        skippedCount: selected.where((todo) => todo.isSkipped).length,
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
}
