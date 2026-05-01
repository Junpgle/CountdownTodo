enum AiTodoActionType {
  createTodo,
  updateTodo,
  completeTodo,
  deleteTodo,
  rescheduleTodo,
  bulkRescheduleTodo,
  categorizeTodo,
  planTodos,
  splitTodo,
  mergeTodos,
  createTimeLog,
  updateTimeLog,
  deleteTimeLog,
  startPomodoro,
  stopPomodoro,
  createCountdown,
  updateCountdown,
  completeCountdown,
  deleteCountdown,
  createPomodoroTag,
  updatePomodoroTag,
  deletePomodoroTag,
  unknown,
}

class AiTodoAction {
  AiTodoAction({
    required this.type,
    this.todoId,
    this.title,
    this.remark,
    this.startTime,
    this.dueDate,
    this.isAllDay = false,
    this.recurrence = 'none',
    this.customIntervalDays,
    this.recurrenceEndDate,
    this.groupId,
    this.reminderMinutes,
    this.durationMinutes,
    this.tagUuids = const [],
    this.status,
    this.color,
    this.isSelected = true,
    this.isAdded = false,
    this.originalText,
    this.sourceTodoIds = const [],
    this.deleteSourceTodos = false,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  AiTodoActionType type;
  String? todoId;
  String? title;
  String? remark;
  String? startTime;
  String? dueDate;
  bool isAllDay;
  String recurrence;
  int? customIntervalDays;
  String? recurrenceEndDate;
  String? groupId;
  int? reminderMinutes;
  int? durationMinutes;
  List<String> tagUuids;
  String? status;
  String? color;
  bool isSelected;
  bool isAdded;
  String? originalText;
  List<String> sourceTodoIds;
  bool deleteSourceTodos;
  Map<String, dynamic> metadata;

  bool get createsTodo =>
      type == AiTodoActionType.createTodo ||
      type == AiTodoActionType.planTodos ||
      type == AiTodoActionType.splitTodo ||
      type == AiTodoActionType.mergeTodos;

  bool get isTodoAction =>
      createsTodo ||
      type == AiTodoActionType.updateTodo ||
      type == AiTodoActionType.completeTodo ||
      type == AiTodoActionType.deleteTodo ||
      type == AiTodoActionType.rescheduleTodo ||
      type == AiTodoActionType.bulkRescheduleTodo ||
      type == AiTodoActionType.categorizeTodo;

  bool get isTimeLogAction =>
      type == AiTodoActionType.createTimeLog ||
      type == AiTodoActionType.updateTimeLog ||
      type == AiTodoActionType.deleteTimeLog;

  bool get isPomodoroAction =>
      type == AiTodoActionType.startPomodoro ||
      type == AiTodoActionType.stopPomodoro;

  bool get isCountdownAction =>
      type == AiTodoActionType.createCountdown ||
      type == AiTodoActionType.updateCountdown ||
      type == AiTodoActionType.completeCountdown ||
      type == AiTodoActionType.deleteCountdown;

  bool get isPomodoroTagAction =>
      type == AiTodoActionType.createPomodoroTag ||
      type == AiTodoActionType.updatePomodoroTag ||
      type == AiTodoActionType.deletePomodoroTag;

  bool get mutatesExistingTodo =>
      type == AiTodoActionType.updateTodo ||
      type == AiTodoActionType.completeTodo ||
      type == AiTodoActionType.deleteTodo ||
      type == AiTodoActionType.rescheduleTodo ||
      type == AiTodoActionType.bulkRescheduleTodo ||
      type == AiTodoActionType.categorizeTodo ||
      type == AiTodoActionType.updateTimeLog ||
      type == AiTodoActionType.deleteTimeLog ||
      type == AiTodoActionType.updateCountdown ||
      type == AiTodoActionType.completeCountdown ||
      type == AiTodoActionType.deleteCountdown ||
      type == AiTodoActionType.updatePomodoroTag ||
      type == AiTodoActionType.deletePomodoroTag;

  String get legacyType => createsTodo ? 'create' : 'update';

  Map<String, dynamic> toJson() => {
        'actionType': type.name,
        'type': legacyType,
        'todoId': todoId,
        'title': title,
        'remark': remark,
        'startTime': startTime,
        'dueDate': dueDate,
        'isAllDay': isAllDay,
        'recurrence': recurrence,
        'customIntervalDays': customIntervalDays,
        'recurrenceEndDate': recurrenceEndDate,
        'groupId': groupId,
        'reminderMinutes': reminderMinutes,
        'durationMinutes': durationMinutes,
        'tagUuids': tagUuids,
        'status': status,
        'color': color,
        'isSelected': isSelected,
        'isAdded': isAdded,
        'originalText': originalText,
        'sourceTodoIds': sourceTodoIds,
        'deleteSourceTodos': deleteSourceTodos,
        'metadata': metadata,
      };

  factory AiTodoAction.fromJson(Map<String, dynamic> json) {
    final typeName = json['actionType']?.toString();
    final legacyType = json['type']?.toString();
    final actionName = json['action']?.toString();

    AiTodoActionType parsedType = AiTodoActionType.unknown;
    if (typeName != null) {
      parsedType = AiTodoActionType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => AiTodoActionType.unknown,
      );
    }
    if (parsedType == AiTodoActionType.unknown) {
      parsedType = _parseActionType(actionName, legacyType);
    }

    return AiTodoAction(
      type: parsedType,
      todoId: (json['todoId'] ?? json['logId'] ?? json['id'])?.toString(),
      title: json['title']?.toString(),
      remark: json['remark']?.toString(),
      startTime: json['startTime']?.toString(),
      dueDate: (json['dueDate'] ?? json['endTime'])?.toString(),
      isAllDay: json['isAllDay'] == true,
      recurrence: json['recurrence']?.toString() ?? 'none',
      customIntervalDays: _parseInt(json['customIntervalDays']),
      recurrenceEndDate: json['recurrenceEndDate']?.toString(),
      groupId: json['groupId']?.toString(),
      reminderMinutes: _parseInt(json['reminderMinutes']),
      durationMinutes: _parseInt(json['durationMinutes'] ?? json['minutes']),
      tagUuids: _parseStringList(json['tagUuids'] ?? json['tagIds']),
      status: json['status']?.toString(),
      color: json['color']?.toString(),
      isSelected: json['isSelected'] != false,
      isAdded: json['isAdded'] == true,
      originalText: json['originalText']?.toString(),
      sourceTodoIds: _parseStringList(
        json['sourceTodoIds'] ?? json['sourceTodoId'] ?? json['todoIds'],
      ),
      deleteSourceTodos: json['deleteSourceTodos'] == true ||
          json['deleteSources'] == true ||
          json['deleteSource'] == true,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : {},
    );
  }

  static AiTodoActionType _parseActionType(String? action, String? legacyType) {
    switch (action) {
      case 'create_todo':
        return AiTodoActionType.createTodo;
      case 'update_todo':
        return AiTodoActionType.updateTodo;
      case 'complete_todo':
        return AiTodoActionType.completeTodo;
      case 'delete_todo':
        return AiTodoActionType.deleteTodo;
      case 'reschedule_todo':
        return AiTodoActionType.rescheduleTodo;
      case 'bulk_reschedule':
      case 'bulk_reschedule_todo':
        return AiTodoActionType.bulkRescheduleTodo;
      case 'categorize_todo':
        return AiTodoActionType.categorizeTodo;
      case 'plan_todos':
        return AiTodoActionType.planTodos;
      case 'split_todo':
        return AiTodoActionType.splitTodo;
      case 'merge_todos':
        return AiTodoActionType.mergeTodos;
      case 'create_time_log':
        return AiTodoActionType.createTimeLog;
      case 'update_time_log':
        return AiTodoActionType.updateTimeLog;
      case 'delete_time_log':
        return AiTodoActionType.deleteTimeLog;
      case 'start_pomodoro':
        return AiTodoActionType.startPomodoro;
      case 'stop_pomodoro':
        return AiTodoActionType.stopPomodoro;
      case 'create_countdown':
        return AiTodoActionType.createCountdown;
      case 'update_countdown':
        return AiTodoActionType.updateCountdown;
      case 'complete_countdown':
        return AiTodoActionType.completeCountdown;
      case 'delete_countdown':
        return AiTodoActionType.deleteCountdown;
      case 'create_pomodoro_tag':
        return AiTodoActionType.createPomodoroTag;
      case 'update_pomodoro_tag':
        return AiTodoActionType.updatePomodoroTag;
      case 'delete_pomodoro_tag':
        return AiTodoActionType.deletePomodoroTag;
    }
    if (legacyType == 'create') return AiTodoActionType.createTodo;
    if (legacyType == 'update') return AiTodoActionType.categorizeTodo;
    return AiTodoActionType.unknown;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [value.toString()];
  }
}
