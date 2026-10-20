import '../models.dart';
import '../models/todo_editor_save_result.dart';
import '../storage_service.dart';

/// Saves an explicit todo editor submission against the rows the editor read.
///
/// Storage performs the baseline check inside the same SQLite transaction as
/// the todo and oplog writes. If a later storage side effect throws, read-back
/// distinguishes a committed edit from a failed transaction.
class TodoEditorSaveService {
  const TodoEditorSaveService._();

  static Future<TodoEditorSaveResult> save({
    required String username,
    required List<TodoItem> changedTodos,
    required Map<String, TodoItem> baselines,
    Map<String, Set<String>>? expectedSeriesMembership,
  }) async {
    if (changedTodos.isEmpty) return const TodoEditorSaveResult();
    try {
      await StorageService.saveTodos(
        username,
        changedTodos,
        expectedTodoBaselines: baselines,
        expectedSeriesMembership: expectedSeriesMembership,
      );
      return const TodoEditorSaveResult();
    } catch (error) {
      try {
        if (await isCommitted(username, changedTodos)) {
          return TodoEditorSaveResult(warnings: ['待办已保存；后续提醒或共享数据更新失败：$error']);
        }
      } catch (_) {
        // Keep the original write error. The editor retains its input and a
        // retry will be guarded by the transaction's original baseline.
      }
      rethrow;
    }
  }

  static Future<bool> isCommitted(
    String username,
    List<TodoItem> expectedTodos,
  ) async {
    final stored = await StorageService.getTodos(
      username,
      includeDeleted: true,
    );
    final byId = {for (final todo in stored) todo.id: todo};
    return expectedTodos.every((expected) {
      final actual = byId[expected.id];
      return actual != null && _sameEditorSnapshot(expected, actual);
    });
  }

  static Future<void> saveGroups({
    required String username,
    required List<TodoGroup> changedGroups,
    required Map<String, TodoGroup> baselines,
  }) => StorageService.saveTodoGroups(
    username,
    changedGroups,
    expectedGroupBaselines: baselines,
  );

  static bool _sameEditorSnapshot(TodoItem expected, TodoItem actual) =>
      expected.id == actual.id &&
      expected.title == actual.title &&
      expected.isDone == actual.isDone &&
      expected.isSkipped == actual.isSkipped &&
      expected.isSkippedSyncPending == actual.isSkippedSyncPending &&
      expected.isDeleted == actual.isDeleted &&
      expected.version == actual.version &&
      expected.updatedAt == actual.updatedAt &&
      expected.createdAt == actual.createdAt &&
      expected.createdDate == actual.createdDate &&
      expected.dueDate?.millisecondsSinceEpoch ==
          actual.dueDate?.millisecondsSinceEpoch &&
      expected.recurrence == actual.recurrence &&
      expected.recurrenceSeriesId == actual.recurrenceSeriesId &&
      expected.customIntervalDays == actual.customIntervalDays &&
      expected.recurrenceEndDate?.millisecondsSinceEpoch ==
          actual.recurrenceEndDate?.millisecondsSinceEpoch &&
      expected.remark == actual.remark &&
      expected.imagePath == actual.imagePath &&
      expected.originalText == actual.originalText &&
      expected.groupId == actual.groupId &&
      expected.reminderMinutes == actual.reminderMinutes &&
      expected.teamUuid == actual.teamUuid &&
      expected.teamName == actual.teamName &&
      expected.creatorId == actual.creatorId &&
      expected.creatorName == actual.creatorName &&
      expected.collabType == actual.collabType &&
      expected.isDateOnly == actual.isDateOnly &&
      expected.categoryId == actual.categoryId;
}
