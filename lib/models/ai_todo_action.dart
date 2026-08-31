import '../utils/json_value_parser.dart';

enum AiTodoActionType {
  createTodo,
  createHabit,
  updateTodo,
  completeTodo,
  deleteTodo,
  createFixedSchedule,
  updateFixedSchedule,
  cancelFixedSchedule,
  deleteFixedSchedule,
  rescheduleTodo,
  bulkRescheduleTodo,
  categorizeTodo,
  planTodos,
  createPlanBlock,
  updatePlanBlock,
  deletePlanBlock,
  reschedulePlanBlocks,
  skipPlanBlock,
  startPlanBlockPomodoro,
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
  createTodoGroup,
  updateTodoGroup,
  deleteTodoGroup,
  createPomodoroTag,
  updatePomodoroTag,
  deletePomodoroTag,
  unknown,
}

class AiTodoAction {
  AiTodoAction({
    required this.type,
    this.todoId,
    this.planBlockId,
    this.scheduleId,
    this.title,
    this.remark,
    this.date,
    this.location,
    this.startTime,
    this.dueDate,
    this.timeMode,
    this.isAllDay = false,
    this.recurrence = 'none',
    this.recurrenceSeriesId,
    this.recurrenceScope = 'occurrence',
    this.customIntervalDays,
    this.recurrenceEndDate,
    this.groupId,
    this.reminderMinutes,
    this.reminderMinutesList = const [],
    this.durationMinutes,
    this.tagUuids = const [],
    this.icon,
    this.habitSourceType,
    this.habitPeriodType,
    this.targetValue,
    this.unit,
    this.targetTimeMinute,
    this.habitTimeComparison,
    this.timeToleranceMinutes,
    this.weekdaysMask,
    this.dayBoundaryMinute,
    this.quickValues = const [],
    this.habitReminderPolicy,
    this.habitDisplayMode,
    this.defaultFocusMinutes,
    this.sourceIds = const [],
    this.status,
    this.color,
    this.isSelected = true,
    this.isAdded = false,
    this.isIgnored = false,
    this.originalText,
    this.sourceTodoIds = const [],
    this.deleteSourceTodos = false,
    bool? hasRemark,
    bool? hasDate,
    bool? hasLocation,
    bool? hasStartTime,
    bool? hasDueDate,
    bool? hasTimeMode,
    bool? hasIsAllDay,
    bool? hasRecurrence,
    bool? hasCustomIntervalDays,
    bool? hasRecurrenceEndDate,
    bool? hasGroupId,
    bool? hasReminderMinutes,
    bool? hasReminderMinutesList,
    Map<String, dynamic>? metadata,
  })  : hasRemark = hasRemark ?? remark != null,
        hasStartTime = hasStartTime ?? startTime != null,
        hasDueDate = hasDueDate ?? dueDate != null,
        hasDate = hasDate ?? date != null,
        hasLocation = hasLocation ?? location != null,
        hasTimeMode = hasTimeMode ?? timeMode != null,
        hasIsAllDay = hasIsAllDay ?? isAllDay,
        hasRecurrence = hasRecurrence ?? recurrence != 'none',
        hasCustomIntervalDays =
            hasCustomIntervalDays ?? customIntervalDays != null,
        hasRecurrenceEndDate =
            hasRecurrenceEndDate ?? recurrenceEndDate != null,
        hasGroupId = hasGroupId ?? groupId != null,
        hasReminderMinutes = hasReminderMinutes ?? reminderMinutes != null,
        hasReminderMinutesList =
            hasReminderMinutesList ?? reminderMinutesList.isNotEmpty,
        metadata = metadata ?? {};

  AiTodoActionType type;
  String? todoId;
  String? planBlockId;
  String? scheduleId;
  String? title;
  String? remark;
  String? date;
  String? location;
  String? startTime;
  String? dueDate;
  String? timeMode;
  bool isAllDay;
  String recurrence;
  String? recurrenceSeriesId;

  /// `occurrence` 只操作指定期次；`future` 操作该期及之后的同系列期次。
  String recurrenceScope;
  int? customIntervalDays;
  String? recurrenceEndDate;
  String? groupId;
  int? reminderMinutes;
  List<int> reminderMinutesList;
  int? durationMinutes;
  List<String> tagUuids;
  String? icon;

  /// 习惯创建动作字段。它们只在 [AiTodoActionType.createHabit] 中生效。
  String? habitSourceType;
  String? habitPeriodType;
  double? targetValue;
  String? unit;
  int? targetTimeMinute;
  String? habitTimeComparison;
  int? timeToleranceMinutes;
  int? weekdaysMask;
  int? dayBoundaryMinute;
  List<int> quickValues;
  Map<String, dynamic>? habitReminderPolicy;
  String? habitDisplayMode;
  int? defaultFocusMinutes;
  List<String> sourceIds;

  String? status;
  String? color;
  bool isSelected;
  bool isAdded;
  bool isIgnored;
  String? originalText;
  List<String> sourceTodoIds;
  bool deleteSourceTodos;
  bool hasRemark;
  bool hasDate;
  bool hasLocation;
  bool hasStartTime;
  bool hasDueDate;
  bool hasTimeMode;
  bool hasIsAllDay;
  bool hasRecurrence;
  bool hasCustomIntervalDays;
  bool hasRecurrenceEndDate;
  bool hasGroupId;
  bool hasReminderMinutes;
  bool hasReminderMinutesList;
  Map<String, dynamic> metadata;

  bool get appliesToFutureOccurrences => recurrenceScope == 'future';

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

  bool get isHabitAction => type == AiTodoActionType.createHabit;

  bool get isTimeLogAction =>
      type == AiTodoActionType.createTimeLog ||
      type == AiTodoActionType.updateTimeLog ||
      type == AiTodoActionType.deleteTimeLog;

  bool get isPomodoroAction =>
      type == AiTodoActionType.startPomodoro ||
      type == AiTodoActionType.stopPomodoro ||
      type == AiTodoActionType.startPlanBlockPomodoro;

  bool get isPlanBlockAction =>
      type == AiTodoActionType.createPlanBlock ||
      type == AiTodoActionType.updatePlanBlock ||
      type == AiTodoActionType.deletePlanBlock ||
      type == AiTodoActionType.reschedulePlanBlocks ||
      type == AiTodoActionType.skipPlanBlock;

  bool get isFixedScheduleAction =>
      type == AiTodoActionType.createFixedSchedule ||
      type == AiTodoActionType.updateFixedSchedule ||
      type == AiTodoActionType.cancelFixedSchedule ||
      type == AiTodoActionType.deleteFixedSchedule;

  bool get isCountdownAction =>
      type == AiTodoActionType.createCountdown ||
      type == AiTodoActionType.updateCountdown ||
      type == AiTodoActionType.completeCountdown ||
      type == AiTodoActionType.deleteCountdown;

  bool get isPomodoroTagAction =>
      type == AiTodoActionType.createPomodoroTag ||
      type == AiTodoActionType.updatePomodoroTag ||
      type == AiTodoActionType.deletePomodoroTag;

  bool get isTodoGroupAction =>
      type == AiTodoActionType.createTodoGroup ||
      type == AiTodoActionType.updateTodoGroup ||
      type == AiTodoActionType.deleteTodoGroup;

  bool get mutatesExistingItem =>
      type == AiTodoActionType.updateTodo ||
      type == AiTodoActionType.completeTodo ||
      type == AiTodoActionType.deleteTodo ||
      type == AiTodoActionType.updateFixedSchedule ||
      type == AiTodoActionType.cancelFixedSchedule ||
      type == AiTodoActionType.deleteFixedSchedule ||
      type == AiTodoActionType.rescheduleTodo ||
      type == AiTodoActionType.bulkRescheduleTodo ||
      type == AiTodoActionType.categorizeTodo ||
      type == AiTodoActionType.updateTimeLog ||
      type == AiTodoActionType.deleteTimeLog ||
      type == AiTodoActionType.updateCountdown ||
      type == AiTodoActionType.completeCountdown ||
      type == AiTodoActionType.deleteCountdown ||
      type == AiTodoActionType.updateTodoGroup ||
      type == AiTodoActionType.deleteTodoGroup ||
      type == AiTodoActionType.updatePomodoroTag ||
      type == AiTodoActionType.deletePomodoroTag ||
      type == AiTodoActionType.updatePlanBlock ||
      type == AiTodoActionType.deletePlanBlock ||
      type == AiTodoActionType.reschedulePlanBlocks ||
      type == AiTodoActionType.skipPlanBlock;

  String get legacyType => createsTodo || isHabitAction ? 'create' : 'update';

  Map<String, dynamic> toJson() => {
        'actionType': type.name,
        'type': legacyType,
        'todoId': todoId,
        'planBlockId': planBlockId,
        'scheduleId': scheduleId,
        'title': title,
        'remark': remark,
        'date': date,
        'location': location,
        'startTime': startTime,
        'dueDate': dueDate,
        'timeMode': timeMode,
        'isAllDay': isAllDay,
        'recurrence': recurrence,
        'recurrenceSeriesId': recurrenceSeriesId,
        'recurrenceScope': recurrenceScope,
        'customIntervalDays': customIntervalDays,
        'recurrenceEndDate': recurrenceEndDate,
        'groupId': groupId,
        'reminderMinutes': reminderMinutes,
        'reminderMinutesList': reminderMinutesList,
        'durationMinutes': durationMinutes,
        'tagUuids': tagUuids,
        'icon': icon,
        'habitSourceType': habitSourceType,
        'habitPeriodType': habitPeriodType,
        'targetValue': targetValue,
        'unit': unit,
        'targetTimeMinute': targetTimeMinute,
        'habitTimeComparison': habitTimeComparison,
        'timeToleranceMinutes': timeToleranceMinutes,
        'weekdaysMask': weekdaysMask,
        'dayBoundaryMinute': dayBoundaryMinute,
        'quickValues': quickValues,
        'habitReminderPolicy': habitReminderPolicy,
        'habitDisplayMode': habitDisplayMode,
        'defaultFocusMinutes': defaultFocusMinutes,
        'sourceIds': sourceIds,
        'status': status,
        'color': color,
        'isSelected': isSelected,
        'isAdded': isAdded,
        'isIgnored': isIgnored,
        'originalText': originalText,
        'sourceTodoIds': sourceTodoIds,
        'deleteSourceTodos': deleteSourceTodos,
        'hasRemark': hasRemark,
        'hasDate': hasDate,
        'hasLocation': hasLocation,
        'hasStartTime': hasStartTime,
        'hasDueDate': hasDueDate,
        'hasTimeMode': hasTimeMode,
        'hasIsAllDay': hasIsAllDay,
        'hasRecurrence': hasRecurrence,
        'hasCustomIntervalDays': hasCustomIntervalDays,
        'hasRecurrenceEndDate': hasRecurrenceEndDate,
        'hasGroupId': hasGroupId,
        'hasReminderMinutes': hasReminderMinutes,
        'hasReminderMinutesList': hasReminderMinutesList,
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
      todoId:
          (json['todoId'] ?? json['todo_id'] ?? json['todoUuid'])?.toString(),
      planBlockId: (json['planBlockId'] ??
              json['plan_block_id'] ??
              json['blockId'] ??
              json['block_id'] ??
              (parsedType == AiTodoActionType.updatePlanBlock ||
                      parsedType == AiTodoActionType.deletePlanBlock ||
                      parsedType == AiTodoActionType.reschedulePlanBlocks ||
                      parsedType == AiTodoActionType.skipPlanBlock ||
                      parsedType == AiTodoActionType.startPlanBlockPomodoro
                  ? json['id']
                  : null))
          ?.toString(),
      scheduleId: (json['scheduleId'] ??
              json['schedule_id'] ??
              json['fixedScheduleId'] ??
              json['fixed_schedule_id'] ??
              (parsedType == AiTodoActionType.updateFixedSchedule ||
                      parsedType == AiTodoActionType.cancelFixedSchedule ||
                      parsedType == AiTodoActionType.deleteFixedSchedule
                  ? json['id']
                  : null))
          ?.toString(),
      title: (json['title'] ?? json['name'])?.toString(),
      remark: json['remark']?.toString(),
      date: json['date']?.toString(),
      location: json['location']?.toString(),
      startTime: json['startTime']?.toString(),
      dueDate: (json['dueDate'] ?? json['endTime'])?.toString(),
      timeMode: json['timeMode']?.toString(),
      isAllDay: json['isAllDay'] == true,
      recurrence: json['recurrence']?.toString() ?? 'none',
      recurrenceSeriesId: (json['recurrenceSeriesId'] ??
              json['recurrence_series_id'] ??
              json['seriesId'])
          ?.toString(),
      recurrenceScope: _parseRecurrenceScope(json['recurrenceScope']),
      customIntervalDays: _parseInt(json['customIntervalDays']),
      recurrenceEndDate: json['recurrenceEndDate']?.toString(),
      groupId: json['groupId']?.toString(),
      reminderMinutes: _parseInt(json['reminderMinutes']),
      reminderMinutesList: _parseIntList(
        json['reminderMinutesList'] ??
            (json['reminderMinutes'] is List
                ? json['reminderMinutes']
                : json['reminders']),
      ),
      durationMinutes: _parseInt(json['durationMinutes'] ?? json['minutes']),
      tagUuids: _parseStringList(json['tagUuids'] ?? json['tagIds']),
      icon: json['icon']?.toString(),
      habitSourceType:
          (json['sourceType'] ?? json['habitSourceType'] ?? json['source_type'])
              ?.toString(),
      habitPeriodType:
          (json['periodType'] ?? json['habitPeriodType'] ?? json['period_type'])
              ?.toString(),
      targetValue: _parseDouble(json['targetValue'] ?? json['target_value']),
      unit: (json['unit'] ?? json['habitUnit'])?.toString(),
      targetTimeMinute: _parseMinuteOfDay(json['targetTimeMinute'] ??
          json['target_time_minute'] ??
          json['targetTime'] ??
          json['target_time']),
      habitTimeComparison: (json['timeComparison'] ??
              json['habitTimeComparison'] ??
              json['time_comparison'])
          ?.toString(),
      timeToleranceMinutes: _parseInt(
        json['timeToleranceMinutes'] ?? json['time_tolerance_minutes'],
      ),
      weekdaysMask: _parseInt(json['weekdaysMask'] ?? json['weekdays_mask']),
      dayBoundaryMinute: _parseMinuteOfDay(
        json['dayBoundaryMinute'] ?? json['day_boundary_minute'],
      ),
      quickValues: _parseIntList(json['quickValues'] ?? json['quick_values']),
      habitReminderPolicy: _parseMap(
        json['reminderPolicy'] ??
            json['habitReminderPolicy'] ??
            json['reminder_policy'],
      ),
      habitDisplayMode: (json['displayMode'] ??
              json['habitDisplayMode'] ??
              json['display_mode'])
          ?.toString(),
      defaultFocusMinutes: _parseInt(
        json['defaultFocusMinutes'] ?? json['default_focus_minutes'],
      ),
      sourceIds: _parseStringList(
        json['sourceIds'] ??
            json['source_ids'] ??
            json['habitSourceIds'] ??
            json['habit_source_ids'] ??
            (json['sourceType'] == 'pomodoroTag' ? json['tagUuids'] : null),
      ),
      status: json['status']?.toString(),
      color: json['color']?.toString(),
      isSelected: json['isSelected'] != false,
      isAdded: json['isAdded'] == true,
      isIgnored: json['isIgnored'] == true,
      originalText: json['originalText']?.toString(),
      sourceTodoIds: _parseStringList(
        json['sourceTodoIds'] ?? json['sourceTodoId'] ?? json['todoIds'],
      ),
      deleteSourceTodos: json['deleteSourceTodos'] == true ||
          json['deleteSources'] == true ||
          json['deleteSource'] == true,
      hasRemark: _fieldWasProvided(json, 'remark', 'hasRemark'),
      hasDate: _fieldWasProvided(json, 'date', 'hasDate'),
      hasLocation: _fieldWasProvided(json, 'location', 'hasLocation'),
      hasStartTime: _fieldWasProvided(json, 'startTime', 'hasStartTime'),
      hasDueDate: _fieldWasProvidedAny(
        json,
        const ['dueDate', 'endTime'],
        'hasDueDate',
      ),
      hasTimeMode: _fieldWasProvided(json, 'timeMode', 'hasTimeMode'),
      hasIsAllDay: _fieldWasProvided(json, 'isAllDay', 'hasIsAllDay'),
      hasRecurrence: _fieldWasProvided(json, 'recurrence', 'hasRecurrence'),
      hasCustomIntervalDays: _fieldWasProvided(
        json,
        'customIntervalDays',
        'hasCustomIntervalDays',
      ),
      hasRecurrenceEndDate: _fieldWasProvided(
        json,
        'recurrenceEndDate',
        'hasRecurrenceEndDate',
      ),
      hasGroupId: _fieldWasProvided(json, 'groupId', 'hasGroupId'),
      hasReminderMinutes: _fieldWasProvided(
        json,
        'reminderMinutes',
        'hasReminderMinutes',
      ),
      hasReminderMinutesList: _fieldWasProvidedAny(
            json,
            const ['reminderMinutesList', 'reminders'],
            'hasReminderMinutesList',
          ) ||
          json['reminderMinutes'] is List,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : {},
    );
  }

  static AiTodoActionType _parseActionType(String? action, String? legacyType) {
    switch (action) {
      case 'create_todo':
        return AiTodoActionType.createTodo;
      case 'create_habit':
      case 'create_habit_goal':
      case 'habit_create':
        return AiTodoActionType.createHabit;
      case 'update_todo':
        return AiTodoActionType.updateTodo;
      case 'complete_todo':
        return AiTodoActionType.completeTodo;
      case 'delete_todo':
        return AiTodoActionType.deleteTodo;
      case 'create_schedule':
      case 'create_fixed_schedule':
        return AiTodoActionType.createFixedSchedule;
      case 'update_schedule':
      case 'update_fixed_schedule':
        return AiTodoActionType.updateFixedSchedule;
      case 'cancel_schedule':
      case 'cancel_fixed_schedule':
        return AiTodoActionType.cancelFixedSchedule;
      case 'delete_schedule':
      case 'delete_fixed_schedule':
        return AiTodoActionType.deleteFixedSchedule;
      case 'reschedule_todo':
        return AiTodoActionType.rescheduleTodo;
      case 'bulk_reschedule':
      case 'bulk_reschedule_todo':
        return AiTodoActionType.bulkRescheduleTodo;
      case 'categorize_todo':
        return AiTodoActionType.categorizeTodo;
      case 'plan_todos':
        return AiTodoActionType.planTodos;
      case 'create_plan_block':
      case 'create_todo_plan_block':
      case 'schedule_todo_block':
        return AiTodoActionType.createPlanBlock;
      case 'update_plan_block':
        return AiTodoActionType.updatePlanBlock;
      case 'delete_plan_block':
        return AiTodoActionType.deletePlanBlock;
      case 'reschedule_plan_blocks':
      case 'reschedule_plan_block':
        return AiTodoActionType.reschedulePlanBlocks;
      case 'skip_plan_block':
        return AiTodoActionType.skipPlanBlock;
      case 'start_plan_block_pomodoro':
        return AiTodoActionType.startPlanBlockPomodoro;
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
      case 'create_todo_group':
      case 'create_group':
      case 'create_category':
      case 'create_folder':
        return AiTodoActionType.createTodoGroup;
      case 'update_todo_group':
      case 'update_group':
      case 'update_category':
      case 'update_folder':
        return AiTodoActionType.updateTodoGroup;
      case 'delete_todo_group':
      case 'delete_group':
      case 'delete_category':
      case 'delete_folder':
        return AiTodoActionType.deleteTodoGroup;
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
    return JsonValueParser.toNullableInt(value);
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  static int? _parseMinuteOfDay(dynamic value) {
    final parsed = _parseInt(value);
    if (parsed != null) return parsed;
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(text);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  static Map<String, dynamic>? _parseMap(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static String _parseRecurrenceScope(dynamic value) {
    final scope = value?.toString();
    return scope == 'future' ? 'future' : 'occurrence';
  }

  static bool _fieldWasProvided(
    Map<String, dynamic> json,
    String key,
    String persistedFlag,
  ) {
    if (json[persistedFlag] is bool) return json[persistedFlag] as bool;
    return json.containsKey(key);
  }

  static bool _fieldWasProvidedAny(
    Map<String, dynamic> json,
    List<String> keys,
    String persistedFlag,
  ) {
    if (json[persistedFlag] is bool) return json[persistedFlag] as bool;
    return keys.any(json.containsKey);
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [value.toString()];
  }

  static List<int> _parseIntList(dynamic value) {
    if (value is List) {
      return value.map(_parseInt).whereType<int>().toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[,，\s]+'))
          .map(_parseInt)
          .whereType<int>()
          .toList();
    }
    return const [];
  }
}
