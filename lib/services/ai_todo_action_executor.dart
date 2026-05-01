import '../models.dart';
import '../models/ai_todo_action.dart';

class AiTodoActionExecutionResult {
  const AiTodoActionExecutionResult({
    required this.newTodos,
    required this.updatedTodos,
  });

  final List<TodoItem> newTodos;
  final List<TodoItem> updatedTodos;

  bool get hasChanges => newTodos.isNotEmpty || updatedTodos.isNotEmpty;
}

class AiTodoActionExecutor {
  static AiTodoActionExecutionResult execute({
    required List<AiTodoAction> actions,
    required List<Map<String, dynamic>> existingTodos,
    Map<String, int> categoryReminderDefaults = const {},
    DateTime? now,
  }) {
    final newTodos = <TodoItem>[];
    final updatedTodos = <TodoItem>[];
    final selectedActions =
        actions.where((action) => action.isSelected && !action.isAdded);
    final createdAtFallback = now ?? DateTime.now();

    for (final action in selectedActions) {
      if (action.mutatesExistingTodo) {
        final updated = _buildUpdatedTodo(action, existingTodos);
        if (updated != null) {
          updatedTodos.add(updated);
          action.isAdded = true;
        }
        continue;
      }

      final created = _buildNewTodo(
        action,
        categoryReminderDefaults,
        createdAtFallback,
      );
      newTodos.add(created);
      action.isAdded = true;
    }

    return AiTodoActionExecutionResult(
      newTodos: newTodos,
      updatedTodos: updatedTodos,
    );
  }

  static TodoItem? _buildUpdatedTodo(
    AiTodoAction action,
    List<Map<String, dynamic>> existingTodos,
  ) {
    final id = action.todoId;
    if (id == null) return null;

    final gId = action.groupId;
    final existingMatch = existingTodos.where((t) => t['id'] == id).toList();
    if (existingMatch.isEmpty) {
      final now = DateTime.now();
      final startTime = action.startTime != null ? DateTime.tryParse(action.startTime!) : null;
      final dueDate = action.dueDate != null ? DateTime.tryParse(action.dueDate!) : null;
      final recurrenceEndDate = action.recurrenceEndDate != null ? DateTime.tryParse(action.recurrenceEndDate!) : null;
      final recurrence = RecurrenceType.values.firstWhere(
        (e) => e.name == action.recurrence,
        orElse: () => RecurrenceType.none,
      );
      return TodoItem(
        id: id,
        title: action.title ?? '',
        groupId: (gId == null || gId.isEmpty) ? null : gId,
        isDone: action.type == AiTodoActionType.completeTodo,
        isDeleted: action.type == AiTodoActionType.deleteTodo,
        remark: action.remark,
        dueDate: dueDate,
        createdDate: startTime?.millisecondsSinceEpoch ?? now.millisecondsSinceEpoch,
        recurrence: recurrence,
        customIntervalDays: action.customIntervalDays,
        recurrenceEndDate: recurrenceEndDate,
        isAllDay: action.isAllDay,
        reminderMinutes: action.reminderMinutes,
        originalText: action.originalText,
      )..markAsChanged();
    }

    final existing = existingMatch.first;
    final existingGroupId = existing['groupId']?.toString();
    final nextGroupId = action.type == AiTodoActionType.categorizeTodo
        ? ((gId == null || gId.isEmpty) ? null : gId)
        : ((gId != null && gId.isNotEmpty) ? gId : existingGroupId);

    final existingStartTime = existing['startTime'] != null
        ? DateTime.tryParse(existing['startTime'].toString())
        : null;
    final existingDueDate = existing['endTime'] != null
        ? DateTime.tryParse(existing['endTime'].toString())
        : null;
    final nextStartTime = action.startTime != null
        ? DateTime.tryParse(action.startTime!)
        : existingStartTime;
    final nextDueDate = action.dueDate != null
        ? DateTime.tryParse(action.dueDate!)
        : existingDueDate;

    return TodoItem(
      id: id,
      title: action.title ?? existing['title'] ?? '',
      groupId: nextGroupId,
      isDone: action.type == AiTodoActionType.completeTodo
          ? true
          : existing['isDone'] ?? false,
      isDeleted: action.type == AiTodoActionType.deleteTodo
          ? true
          : existing['isDeleted'] ?? false,
      remark: action.remark ?? existing['remark'],
      dueDate: nextDueDate,
      createdDate: nextStartTime?.millisecondsSinceEpoch,
      recurrence: _parseRecurrence(action.recurrence, existing),
      customIntervalDays: action.customIntervalDays ??
          _parseNullableInt(
            existing['customIntervalDays'] ?? existing['custom_interval_days'],
          ),
      recurrenceEndDate: action.recurrenceEndDate != null
          ? DateTime.tryParse(action.recurrenceEndDate!)
          : _parseExistingDate(
              existing['recurrenceEndDate'] ?? existing['recurrence_end_date'],
            ),
      isAllDay: action.isAllDay || existing['isAllDay'] == true,
      reminderMinutes:
          action.reminderMinutes ?? existing['reminderMinutes'] as int?,
    )..markAsChanged();
  }

  static TodoItem _buildNewTodo(
    AiTodoAction action,
    Map<String, int> categoryReminderDefaults,
    DateTime now,
  ) {
    final startTime =
        action.startTime != null ? DateTime.tryParse(action.startTime!) : null;
    final dueDate =
        action.dueDate != null ? DateTime.tryParse(action.dueDate!) : null;
    final recurrenceEndDate = action.recurrenceEndDate != null
        ? DateTime.tryParse(action.recurrenceEndDate!)
        : null;
    final recurrence = RecurrenceType.values.firstWhere(
      (e) => e.name == action.recurrence,
      orElse: () => RecurrenceType.none,
    );
    final gId = action.groupId;

    return TodoItem(
      title: action.title ?? '未命名待办',
      remark: _buildRemark(action),
      dueDate: dueDate,
      createdDate:
          startTime?.millisecondsSinceEpoch ?? now.millisecondsSinceEpoch,
      recurrence: recurrence,
      customIntervalDays: action.customIntervalDays,
      recurrenceEndDate: recurrenceEndDate,
      originalText: action.originalText,
      groupId: (gId == null || gId.isEmpty) ? null : gId,
      isAllDay: action.isAllDay,
      reminderMinutes: action.reminderMinutes ??
          (gId != null ? categoryReminderDefaults[gId] : null),
    );
  }

  static String? _buildRemark(AiTodoAction action) {
    final sourcePrefix = action.sourceTodoIds.isEmpty
        ? null
        : '来源待办: ${action.sourceTodoIds.join(', ')}';
    if (sourcePrefix == null) return action.remark;
    if (action.remark == null || action.remark!.isEmpty) return sourcePrefix;
    return '${action.remark}\n$sourcePrefix';
  }

  static RecurrenceType _parseRecurrence(
    String recurrence,
    Map<String, dynamic> existing,
  ) {
    if (recurrence != 'none') {
      return RecurrenceType.values.firstWhere(
        (e) => e.name == recurrence,
        orElse: () => RecurrenceType.none,
      );
    }

    final existingRecurrence = existing['recurrence'];
    if (existingRecurrence is int &&
        existingRecurrence >= 0 &&
        existingRecurrence < RecurrenceType.values.length) {
      return RecurrenceType.values[existingRecurrence];
    }
    return RecurrenceType.values.firstWhere(
      (e) => e.name == existingRecurrence?.toString(),
      orElse: () => RecurrenceType.none,
    );
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseExistingDate(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.tryParse(value.toString());
  }

  static List<TodoItem> mergeTodoUpdates(
    List<TodoItem> base,
    List<TodoItem> inserted,
    List<TodoItem> updated,
  ) {
    final result = List<TodoItem>.from(base)..addAll(inserted);
    for (final update in updated) {
      final idx = result.indexWhere((todo) => todo.id == update.id);
      if (idx == -1) {
        result.add(update);
      } else {
        result[idx] = _mergeTodo(result[idx], update);
      }
    }
    return result;
  }

  static TodoItem _mergeTodo(TodoItem existing, TodoItem update) {
    return TodoItem(
      id: existing.id,
      title: update.title.isNotEmpty ? update.title : existing.title,
      isDone: update.isDone,
      isDeleted: update.isDeleted,
      version: existing.version,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      createdAt: existing.createdAt,
      createdDate: update.createdDate ?? existing.createdDate,
      recurrence: update.recurrence,
      customIntervalDays: update.customIntervalDays,
      recurrenceEndDate: update.recurrenceEndDate,
      dueDate: update.dueDate,
      remark: update.remark ?? existing.remark,
      imagePath: existing.imagePath,
      originalText: update.originalText ?? existing.originalText,
      groupId: update.groupId,
      reminderMinutes: update.reminderMinutes,
      teamUuid: existing.teamUuid,
      creatorId: existing.creatorId,
      creatorName: existing.creatorName,
      teamName: existing.teamName,
      collabType: existing.collabType,
      hasConflict: existing.hasConflict,
      serverVersionData: existing.serverVersionData,
      isAllDay: update.isAllDay,
      categoryId: existing.categoryId,
    )..markAsChanged();
  }
}
