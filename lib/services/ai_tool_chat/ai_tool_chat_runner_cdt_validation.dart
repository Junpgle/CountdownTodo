part of '../ai_tool_chat_runner.dart';

String? _validateCdtCreationAction(
  Map action, {
  Set<String>? knownTodoIds,
  Map<String, Set<String>>? knownReferenceIdsByDomain,
}) {
  final actionName = action['action']?.toString();
  final recordsField = switch (actionName) {
    'create_todo' => 'todos',
    'create_schedule' => 'schedules',
    'create_time_log' => 'logs',
    'create_countdown' => 'countdowns',
    'create_plan_block' => 'blocks',
    'create_habit' => 'habits',
    'split_todo' => 'todos',
    'merge_todos' => 'todo',
    'create_todo_group' => 'groups',
    'create_pomodoro_tag' => 'tags',
    _ => null,
  };
  if (recordsField == null) return null;
  final rawRecords = action[recordsField];
  final records = rawRecords is List
      ? rawRecords.whereType<Map>().toList(growable: false)
      : [action];
  if (records.isEmpty) return '$actionName 至少需要一条有效记录';

  for (final record in records) {
    final title = (record['title'] ?? record['name'])?.toString().trim();
    switch (actionName) {
      case 'create_todo':
        final groupIds =
            [
                  if (record['groupId'] != null) record['groupId'],
                  if (record['group_id'] != null) record['group_id'],
                ]
                .map((value) => value.toString().trim())
                .where((id) => id.isNotEmpty)
                .toSet();
        if (groupIds.length > 1) {
          return 'create_todo 的groupId与group_id不能互相冲突';
        }
        final groupId = groupIds.isEmpty ? null : groupIds.single;
        final knownGroupIds = knownReferenceIdsByDomain?['todo_groups'];
        if (groupId != null &&
            knownGroupIds != null &&
            !knownGroupIds.contains(groupId)) {
          return 'create_todo 引用了当前不存在的分类，请先查询并选择真实分类';
        }
        break;
      case 'split_todo':
        final sourceTodoId = [
          action['sourceTodoId'],
          action['todoId'],
          action['source_id'],
        ].any((value) => value?.toString().trim().isNotEmpty == true);
        if (!sourceTodoId) return 'split_todo必须提供sourceTodoId';
        final splitTodos = action['todos'];
        if (splitTodos is! List || splitTodos.isEmpty) {
          return 'split_todo必须包含至少一条拆分后的待办';
        }
        if (splitTodos.any(
          (todo) =>
              todo is! Map ||
              todo['title']?.toString().trim().isNotEmpty != true,
        )) {
          return 'split_todo中的每条新待办都必须包含非空标题';
        }
        break;
      case 'merge_todos':
        final mergedTodo = action['todo'];
        if (mergedTodo is! Map ||
            mergedTodo['title']?.toString().trim().isNotEmpty != true) {
          return 'merge_todos必须提供包含非空title的新todo对象';
        }
        break;
      case 'create_schedule':
        if (title == null || title.isEmpty) {
          return 'create_schedule 每项都必须包含日程标题';
        }
        final rawDate = record['date'];
        final rawStart = record['startTime'];
        final rawEnd = record['dueDate'] ?? record['endTime'];
        final date = _parseStrictLocalDateTime(rawDate);
        final start = _parseStrictLocalDateTime(rawStart);
        final end = _parseStrictLocalDateTime(rawEnd);
        if (rawDate != null &&
            rawDate.toString().trim().isNotEmpty &&
            date == null) {
          return 'create_schedule 的date必须是有效日期';
        }
        if (rawStart != null &&
            rawStart.toString().trim().isNotEmpty &&
            start == null) {
          return 'create_schedule 的startTime必须是有效本地时间';
        }
        if (date != null &&
            start != null &&
            (date.year != start.year ||
                date.month != start.month ||
                date.day != start.day)) {
          return 'create_schedule 的date必须与startTime属于同一天';
        }
        if ((date == null && start == null) ||
            (rawEnd != null &&
                rawEnd.toString().trim().isNotEmpty &&
                end == null) ||
            (end != null && (start == null || !end.isAfter(start)))) {
          return 'create_schedule 需要有效date或startTime；填写结束时间时也必须晚于开始时间';
        }
        break;
      case 'create_time_log':
        if (title == null || title.isEmpty) {
          return 'create_time_log 每项都必须包含专注内容标题';
        }
        final tagAliases = [
          if (record['tagUuids'] is List)
            (record['tagUuids'] as List)
                .whereType<String>()
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .toSet(),
          if (record['tagIds'] is List)
            (record['tagIds'] as List)
                .whereType<String>()
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .toSet(),
        ];
        if (tagAliases.length > 1 &&
            tagAliases
                .skip(1)
                .any((ids) => !_sameStringSet(tagAliases.first, ids))) {
          return 'create_time_log 的tagUuids与tagIds不能互相冲突';
        }
        final tagIds = tagAliases.isEmpty ? const <String>{} : tagAliases.first;
        final knownTagIds = knownReferenceIdsByDomain?['pomodoro_tags'];
        if (knownTagIds != null &&
            tagIds.any((id) => !knownTagIds.contains(id))) {
          return 'create_time_log 引用了当前不存在的番茄标签，请先查询并选择真实标签';
        }
        final rawStart = record['startTime'];
        final rawEnd = record['dueDate'] ?? record['endTime'];
        final start = _parseStrictLocalDateTime(rawStart);
        final end = _parseStrictLocalDateTime(rawEnd);
        final duration = _toPositiveInt(record['durationMinutes']);
        if (rawStart == null || start == null) {
          return 'create_time_log 每项都必须包含有效startTime';
        }
        if ((rawEnd != null && end == null) ||
            (end != null && !end.isAfter(start)) ||
            (rawEnd == null && duration == null)) {
          return 'create_time_log 每项都需要晚于开始时间的dueDate/endTime，或正数durationMinutes';
        }
        break;
      case 'create_countdown':
        if (title == null || title.isEmpty) {
          return 'create_countdown 每项都必须包含事件标题';
        }
        final rawTarget = record['dueDate'] ?? record['startTime'];
        if (rawTarget == null || _parseStrictLocalDateTime(rawTarget) == null) {
          return 'create_countdown 每项都必须包含有效dueDate';
        }
        break;
      case 'create_plan_block':
        final newTodoTitle = record['newTodoTitle']?.toString().trim() ?? '';
        final todoAliases =
            [
                  if (record['todoId'] != null) record['todoId'],
                  if (record['todo_id'] != null) record['todo_id'],
                  if (record['todoUuid'] != null) record['todoUuid'],
                ]
                .map((value) => value.toString().trim())
                .where((id) => id.isNotEmpty)
                .toSet();
        if (todoAliases.length > 1) {
          return 'create_plan_block 的待办ID字段不能互相冲突';
        }
        final todoId = todoAliases.isNotEmpty;
        final referencedTodoId = todoAliases.isEmpty ? null : todoAliases.first;
        if (referencedTodoId != null &&
            knownTodoIds != null &&
            !knownTodoIds.contains(referencedTodoId)) {
          return 'create_plan_block 引用了当前不存在的todoId，请先查询并选择真实待办';
        }
        if (newTodoTitle.isEmpty && !todoId) {
          return 'create_plan_block 每项都必须引用已有todoId或提供newTodoTitle';
        }
        if (newTodoTitle.isNotEmpty && todoId) {
          return '新规划事项使用newTodoTitle时不要同时填写todoId';
        }
        final rawStart = record['startTime'];
        final rawEnd = record['dueDate'] ?? record['endTime'];
        final start = _parseStrictLocalDateTime(rawStart);
        final end = _parseStrictLocalDateTime(rawEnd);
        final duration = _toPositiveInt(record['durationMinutes']);
        if (start == null ||
            (rawEnd != null && end == null) ||
            (end == null && duration == null) ||
            (end != null && !end.isAfter(start)) ||
            (end == null &&
                duration != null &&
                !start.add(Duration(minutes: duration)).isAfter(start))) {
          return 'create_plan_block 每项都需要有效startTime，以及晚于开始时间的dueDate或正数durationMinutes';
        }
        break;
      case 'create_habit':
        if (title == null || title.isEmpty) {
          return 'create_habit 每项都必须包含习惯名称';
        }
        final sourceType =
            (record['sourceType'] ??
                    record['habitSourceType'] ??
                    record['source_type'] ??
                    action['sourceType'] ??
                    action['habitSourceType'])
                ?.toString();
        const sourceTypes = {
          'quantityCheckIn',
          'timeCheckIn',
          'durationCheckIn',
          'pomodoroTag',
          'recurringTodo',
        };
        if (sourceType == null || !sourceTypes.contains(sourceType)) {
          return 'create_habit 每项都必须指定有效sourceType';
        }
        final periodType = (record['periodType'] ?? record['habitPeriodType'])
            ?.toString();
        const periodTypes = {
          'daily',
          'weekly',
          'weekdays',
          'monthly',
          'custom',
        };
        if (periodType == null || !periodTypes.contains(periodType)) {
          return 'create_habit 每项都必须指定有效periodType';
        }
        if (periodType == 'custom' &&
            _toPositiveInt(record['customIntervalDays']) == null) {
          return 'custom习惯必须包含正数customIntervalDays';
        }
        final sourceIdAliases = [
          for (final field in <String>[
            'sourceIds',
            'source_ids',
            'habitSourceIds',
            'habit_source_ids',
            if (sourceType == 'pomodoroTag') 'tagUuids',
            if (sourceType == 'pomodoroTag') 'tagIds',
          ])
            if (record[field] is List)
              (record[field] as List)
                  .whereType<String>()
                  .map((id) => id.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet(),
        ];
        if (sourceIdAliases.length > 1 &&
            sourceIdAliases
                .skip(1)
                .any((ids) => !_sameStringSet(sourceIdAliases.first, ids))) {
          return 'create_habit 的sourceIds字段不能互相冲突';
        }
        final sourceIds = sourceIdAliases.isEmpty
            ? const <String>{}
            : sourceIdAliases.first;
        if (sourceType == 'pomodoroTag') {
          final knownTagIds = knownReferenceIdsByDomain?['pomodoro_tags'];
          if (knownTagIds != null &&
              sourceIds.any((id) => !knownTagIds.contains(id))) {
            return 'create_habit 引用了当前不存在的番茄标签，请先查询并选择真实标签';
          }
        } else if (sourceType == 'recurringTodo' && sourceIds.isNotEmpty) {
          final knownSeriesIds =
              knownReferenceIdsByDomain?['recurring_todo_series'];
          if (knownSeriesIds != null &&
              sourceIds.any((id) => !knownSeriesIds.contains(id))) {
            return '完成型习惯引用的sourceIds必须是当前有效的循环待办系列';
          }
        }
        final rawWeekdaysMask =
            record['weekdaysMask'] ?? record['weekdays_mask'];
        final weekdaysMask = _toInt(rawWeekdaysMask);
        if (rawWeekdaysMask != null &&
            (weekdaysMask == null || weekdaysMask < 1 || weekdaysMask > 127)) {
          return 'weekdaysMask必须是1至127之间的有效掩码';
        }
        final rawDayBoundaryMinute =
            record['dayBoundaryMinute'] ?? record['day_boundary_minute'];
        final dayBoundaryMinute = _toInt(rawDayBoundaryMinute);
        if (rawDayBoundaryMinute != null &&
            (dayBoundaryMinute == null ||
                dayBoundaryMinute < 0 ||
                dayBoundaryMinute >= 1440)) {
          return 'dayBoundaryMinute必须是0至1439的分钟值';
        }
        final rawTolerance =
            record['timeToleranceMinutes'] ?? record['time_tolerance_minutes'];
        final tolerance = _toInt(rawTolerance);
        if (rawTolerance != null && (tolerance == null || tolerance < 0)) {
          return 'timeToleranceMinutes必须是非负整数';
        }
        final targetValue = _toPositiveDouble(record['targetValue']);
        switch (sourceType) {
          case 'quantityCheckIn':
            if (targetValue == null) return '数量习惯必须包含正数targetValue';
            if (record['unit']?.toString().trim().isNotEmpty != true &&
                record['habitUnit']?.toString().trim().isNotEmpty != true) {
              return '数量习惯必须包含unit';
            }
            break;
          case 'timeCheckIn':
            final targetMinute = _toInt(
              record['targetTimeMinute'] ?? record['targetTime'],
            );
            if (targetMinute == null ||
                targetMinute < 0 ||
                targetMinute >= 1440) {
              return '时间点习惯必须包含0至1439的targetTimeMinute';
            }
            break;
          case 'durationCheckIn':
            if (_toPositiveInt(record['durationMinutes']) == null) {
              return '时长习惯必须包含正数durationMinutes';
            }
            break;
          case 'pomodoroTag':
            if (sourceIds.isEmpty ||
                _toPositiveInt(record['durationMinutes']) == null) {
              return '番茄标签习惯必须引用真实sourceIds并包含正数durationMinutes';
            }
            break;
        }
        break;
      case 'create_todo_group':
        if (title == null || title.isEmpty) {
          return 'create_todo_group 每项都必须包含分类名称';
        }
        break;
      case 'create_pomodoro_tag':
        if (title == null || title.isEmpty) {
          return 'create_pomodoro_tag 每项都必须包含标签名称';
        }
        break;
    }
  }
  return null;
}

String? _validateCdtMutationAction(
  Map action, {
  required String requestText,
  Map<String, Set<String>>? knownReferenceIdsByDomain,
}) {
  final actionName = action['action']?.toString();
  final deletesSourceTodos = actionName == 'split_todo'
      ? action['deleteSource'] == true ||
            action['deleteSourceTodos'] == true ||
            action['deleteSources'] == true
      : actionName == 'merge_todos' &&
            (action['deleteSources'] == true ||
                action['deleteSourceTodos'] == true ||
                action['deleteSource'] == true);
  if (deletesSourceTodos &&
      !_explicitlyRequestsSourceTodoDeletion(requestText)) {
    return '只有用户明确要求删除拆分或合并前的源待办时，才能设置删除源待办';
  }

  const mutableFieldsByAction = <String, Set<String>>{
    'update_todo': {
      'title',
      'remark',
      'timeMode',
      'dueDate',
      'groupId',
      'reminderMinutes',
      'recurrence',
      'customIntervalDays',
      'recurrenceEndDate',
    },
    'categorize_todo': {'groupId'},
    'reschedule_todo': {'timeMode', 'dueDate'},
    'bulk_reschedule': {'timeMode', 'dueDate'},
    'update_schedule': {
      'title',
      'date',
      'startTime',
      'endTime',
      'location',
      'remark',
      'reminderMinutes',
      'recurrence',
      'customIntervalDays',
      'recurrenceEndDate',
    },
    'update_plan_block': {
      'title',
      'startTime',
      'dueDate',
      'endTime',
      'durationMinutes',
      'remark',
      'reminderMinutes',
    },
    'reschedule_plan_blocks': {
      'startTime',
      'dueDate',
      'endTime',
      'durationMinutes',
    },
    'update_time_log': {
      'title',
      'startTime',
      'dueDate',
      'endTime',
      'durationMinutes',
      'remark',
      'tagUuids',
      'tagIds',
    },
    'update_countdown': {'title', 'dueDate', 'startTime'},
    'update_todo_group': {'name', 'title'},
    'update_pomodoro_tag': {'name', 'title', 'color'},
  };
  final mutableFields = mutableFieldsByAction[actionName];
  if (mutableFields != null) {
    final rawUpdates = action['updates'] ?? action['blocks'];
    if (rawUpdates is! List || rawUpdates.isEmpty) {
      return '$actionName至少需要一条updates记录';
    }
    for (final rawUpdate in rawUpdates) {
      if (rawUpdate is! Map) return '$actionName的每项updates都必须是对象';
      if (!mutableFields.any(rawUpdate.containsKey)) {
        return '$actionName每项都必须包含至少一个要修改的字段';
      }
      if (actionName == 'update_todo' || actionName == 'categorize_todo') {
        for (final field in const ['groupId', 'group_id']) {
          if (rawUpdate.containsKey(field) &&
              rawUpdate[field] is String &&
              (rawUpdate[field] as String).trim().isEmpty) {
            return '$actionName的分类ID不能为空字符串；清除分类时请使用null';
          }
        }
        final groupIds = [
          if (rawUpdate['groupId'] != null)
            rawUpdate['groupId'].toString().trim(),
          if (rawUpdate['group_id'] != null)
            rawUpdate['group_id'].toString().trim(),
        ].where((id) => id.isNotEmpty).toSet();
        if (groupIds.length > 1) {
          return '$actionName的groupId与group_id不能互相冲突';
        }
        final groupId = groupIds.isEmpty ? null : groupIds.single;
        final knownGroupIds = knownReferenceIdsByDomain?['todo_groups'];
        if (groupId != null &&
            knownGroupIds != null &&
            !knownGroupIds.contains(groupId)) {
          return '$actionName引用了当前不存在的分类，请先查询并选择真实分类';
        }
      }
      if (actionName == 'update_time_log') {
        final tagAliases = [
          if (rawUpdate['tagUuids'] is List)
            (rawUpdate['tagUuids'] as List)
                .whereType<String>()
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .toSet(),
          if (rawUpdate['tagIds'] is List)
            (rawUpdate['tagIds'] as List)
                .whereType<String>()
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .toSet(),
        ];
        if (tagAliases.length > 1 &&
            tagAliases
                .skip(1)
                .any((ids) => !_sameStringSet(tagAliases.first, ids))) {
          return 'update_time_log的tagUuids与tagIds不能互相冲突';
        }
        final tagIds = tagAliases.isEmpty ? const <String>{} : tagAliases.first;
        final knownTagIds = knownReferenceIdsByDomain?['pomodoro_tags'];
        if (knownTagIds != null &&
            tagIds.any((id) => !knownTagIds.contains(id))) {
          return 'update_time_log引用了当前不存在的番茄标签，请先查询并选择真实标签';
        }
      }
    }
  }

  if (actionName != 'update_habit' && actionName != 'delete_habit') {
    return null;
  }
  final rawUpdates = action['updates'];
  if (rawUpdates is! List || rawUpdates.isEmpty) {
    return '$actionName至少需要一条updates记录';
  }
  for (final rawUpdate in rawUpdates) {
    if (rawUpdate is! Map) return '$actionName的每项updates都必须是对象';
    final title = rawUpdate['title']?.toString().trim() ?? '';
    if (title.isEmpty) {
      return '$actionName每项都必须提供习惯名称，供用户在确认卡中核对';
    }
  }
  if (actionName == 'delete_habit') return null;
  const mutableHabitFields = {
    'name',
    'icon',
    'displayMode',
    'defaultFocusMinutes',
    'targetValue',
    'unit',
    'durationMinutes',
    'targetTimeMinute',
    'timeComparison',
    'timeToleranceMinutes',
    'periodType',
    'weekdaysMask',
    'customIntervalDays',
    'dayBoundaryMinute',
    'quickValues',
    'reminderPolicy',
  };
  const ruleFields = {
    'targetValue',
    'unit',
    'durationMinutes',
    'targetTimeMinute',
    'timeComparison',
    'timeToleranceMinutes',
    'periodType',
    'weekdaysMask',
    'customIntervalDays',
    'dayBoundaryMinute',
    'quickValues',
    'reminderPolicy',
  };
  for (final rawUpdate in rawUpdates) {
    if (rawUpdate is! Map) return 'update_habit的每项updates都必须是对象';
    final update = Map<String, dynamic>.from(rawUpdate);
    if (!mutableHabitFields.any(update.containsKey)) {
      return 'update_habit必须至少提供一个要修改的习惯字段';
    }
    if (update.containsKey('name') &&
        update['name']?.toString().trim().isEmpty == true) {
      return '习惯名称不能为空';
    }
    if (update.containsKey('displayMode') &&
        !const {
          'habitOnly',
          'todoOnly',
          'both',
        }.contains(update['displayMode'])) {
      return 'displayMode必须是habitOnly、todoOnly或both';
    }
    if (update.containsKey('defaultFocusMinutes')) {
      final minutes = _toPositiveInt(update['defaultFocusMinutes']);
      if (minutes == null || minutes > 240) {
        return 'defaultFocusMinutes必须是1至240的正整数';
      }
    }
    if (update.containsKey('targetValue') &&
        _toPositiveDouble(update['targetValue']) == null) {
      return 'targetValue必须是正数';
    }
    if (update.containsKey('unit') &&
        update['unit']?.toString().trim().isEmpty == true) {
      return 'unit不能为空';
    }
    if (update.containsKey('durationMinutes') &&
        _toPositiveInt(update['durationMinutes']) == null) {
      return 'durationMinutes必须是正整数';
    }
    if (update.containsKey('targetTimeMinute')) {
      final minute = _toInt(update['targetTimeMinute']);
      if (minute == null || minute < 0 || minute >= 1440) {
        return 'targetTimeMinute必须是0至1439的分钟值';
      }
    }
    if (update.containsKey('timeComparison') &&
        !const {'before', 'after'}.contains(update['timeComparison'])) {
      return 'timeComparison必须是before或after';
    }
    if (update.containsKey('timeToleranceMinutes')) {
      final tolerance = _toInt(update['timeToleranceMinutes']);
      if (tolerance == null || tolerance < 0) {
        return 'timeToleranceMinutes必须是非负整数';
      }
    }
    if (update.containsKey('periodType') &&
        !const {
          'daily',
          'weekly',
          'weekdays',
          'monthly',
          'custom',
        }.contains(update['periodType'])) {
      return 'periodType不是支持的习惯周期';
    }
    if (update['periodType'] == 'custom' &&
        _toPositiveInt(update['customIntervalDays']) == null) {
      return 'custom周期必须包含正数customIntervalDays';
    }
    if (update.containsKey('customIntervalDays') &&
        _toPositiveInt(update['customIntervalDays']) == null) {
      return 'customIntervalDays必须是正整数';
    }
    if (update['periodType'] == 'weekdays' &&
        !update.containsKey('weekdaysMask')) {
      return 'periodType为weekdays时必须包含weekdaysMask';
    }
    if (update.containsKey('weekdaysMask')) {
      final mask = _toInt(update['weekdaysMask']);
      if (mask == null || mask < 1 || mask > 127) {
        return 'weekdaysMask必须是1至127之间的有效掩码';
      }
    }
    if (update.containsKey('dayBoundaryMinute')) {
      final minute = _toInt(update['dayBoundaryMinute']);
      if (minute == null || minute < 0 || minute >= 1440) {
        return 'dayBoundaryMinute必须是0至1439的分钟值';
      }
    }
    if (update.containsKey('quickValues')) {
      final values = update['quickValues'];
      if (values is! List ||
          values.length > 4 ||
          values.any((value) => _toPositiveInt(value) == null)) {
        return 'quickValues必须是最多4个正整数的数组';
      }
    }
    if (update.containsKey('reminderPolicy')) {
      final policy = update['reminderPolicy'];
      if (policy is! Map) return 'reminderPolicy必须是对象';
      final fixedTimes = policy['fixedTimes'] ?? policy['fixed_times'];
      if (fixedTimes != null &&
          (fixedTimes is! List ||
              fixedTimes.any((value) {
                final minute = _toInt(value);
                return minute == null || minute < 0 || minute >= 1440;
              }))) {
        return 'reminderPolicy.fixedTimes必须是0至1439的分钟数组';
      }
    }
    final effectiveFromOption = update['effectiveFromOption'];
    if (effectiveFromOption != null &&
        !const {'today', 'nextPeriod', 'all'}.contains(effectiveFromOption)) {
      return 'effectiveFromOption必须是today、nextPeriod或all';
    }
    if (effectiveFromOption == 'all' &&
        !RegExp(r'全部历史|所有历史|历史目标全部|所有周期目标').hasMatch(requestText)) {
      return '只有用户明确要求覆盖全部历史目标时才能使用effectiveFromOption=all';
    }
    if (effectiveFromOption == 'nextPeriod' &&
        !RegExp(r'下个周期|下一个周期|下一周期|下周|下个月|下月|下期').hasMatch(requestText)) {
      return '只有用户明确要求下个周期生效时才能使用effectiveFromOption=nextPeriod';
    }
    if (update.containsKey('sourceType') ||
        update.containsKey('habitSourceType') ||
        update.containsKey('sourceIds') ||
        update.containsKey('source_ids')) {
      return '不能通过update_habit更换习惯来源类型或来源';
    }
    if (update.containsKey('effectiveFromOption') &&
        !ruleFields.any(update.containsKey)) {
      return 'effectiveFromOption只能与习惯规则修改一起使用';
    }
  }
  return null;
}

bool _explicitlyRequestsSourceTodoDeletion(String requestText) {
  const sourceTodo = r'(?:原(?:有|来|始)?(?:的)?|旧(?:的)?|来源|源)(?:待办|任务|事项|项)';
  return RegExp(
    '(?:删除|删掉|移除|清除|去掉)[^。！？\\n]{0,4}$sourceTodo|'
    '$sourceTodo[^。！？\\n]{0,4}(?:删除|删掉|移除|清除|去掉)|'
    '不保留[^。！？\\n]{0,6}$sourceTodo',
  ).hasMatch(requestText);
}

String? _validateCdtActionReference(
  Map action, {
  Set<String>? knownTodoIds,
  Set<String>? knownHabitIds,
  Map<String, Set<String>>? knownReferenceIdsByDomain,
}) {
  final actionName = action['action']?.toString();
  final normalizedKnownTodoIds = knownTodoIds
      ?.map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final normalizedKnownHabitIds = knownHabitIds
      ?.map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final normalizedDomainIds = knownReferenceIdsByDomain?.map(
    (domain, ids) => MapEntry(
      domain,
      ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet(),
    ),
  );
  if (actionName == 'start_pomodoro') {
    final todoIds =
        [
              if (action['todoId'] != null) action['todoId'],
              if (action['todo_id'] != null) action['todo_id'],
            ]
            .map((value) => value.toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet();
    if (todoIds.length > 1) {
      return 'start_pomodoro的todoId与todo_id不能互相冲突';
    }
    final todoId = todoIds.isEmpty ? null : todoIds.single;
    if (todoId != null &&
        normalizedKnownTodoIds != null &&
        !normalizedKnownTodoIds.contains(todoId)) {
      return 'start_pomodoro引用了当前不存在的todoId，请先查询并选择真实待办';
    }
    final tagAliases = [
      if (action['tagUuids'] is List)
        (action['tagUuids'] as List)
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet(),
      if (action['tagIds'] is List)
        (action['tagIds'] as List)
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet(),
    ];
    if (tagAliases.length > 1 &&
        tagAliases
            .skip(1)
            .any((ids) => !_sameStringSet(tagAliases.first, ids))) {
      return 'start_pomodoro的tagUuids与tagIds不能互相冲突';
    }
    final tagIds = tagAliases.isEmpty ? const <String>{} : tagAliases.first;
    final knownTagIds = normalizedDomainIds?['pomodoro_tags'];
    if (knownTagIds != null && tagIds.any((id) => !knownTagIds.contains(id))) {
      return 'start_pomodoro引用了当前不存在的番茄标签，请先查询并选择真实标签';
    }
    return null;
  }
  if (actionName == 'merge_todos') {
    final suppliedSourceAliases = [
      if (action['sourceTodoIds'] is List)
        (action['sourceTodoIds'] as List)
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet(),
      if (action['todoIds'] is List)
        (action['todoIds'] as List)
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet(),
    ];
    if (suppliedSourceAliases.length > 1 &&
        (suppliedSourceAliases.first.length !=
                suppliedSourceAliases.last.length ||
            !suppliedSourceAliases.first.containsAll(
              suppliedSourceAliases.last,
            ))) {
      return 'merge_todos的sourceTodoIds与todoIds不能互相冲突';
    }
    final sourceIds = action['sourceTodoIds'] ?? action['todoIds'];
    if (sourceIds is! List) {
      return 'merge_todos必须包含sourceTodoIds数组';
    }
    final ids = sourceIds
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.length < 2) {
      return 'merge_todos必须引用至少两个本轮上下文中的真实待办ID';
    }
    if (normalizedKnownTodoIds != null &&
        ids.any((id) => !normalizedKnownTodoIds.contains(id))) {
      return 'merge_todos包含当前不存在的待办ID，请先查询并使用至少两个真实待办ID';
    }
    return null;
  }
  final referenceFields = switch (actionName) {
    'update_todo' ||
    'complete_todo' ||
    'skip_todo' ||
    'delete_todo' ||
    'reschedule_todo' ||
    'bulk_reschedule' ||
    'categorize_todo' => ['todoId', 'todo_id', 'todoUuid', 'id'],
    'split_todo' => ['sourceTodoId', 'source_id', 'todoId', 'todo_id', 'id'],
    'update_schedule' || 'cancel_schedule' || 'delete_schedule' => [
      'scheduleId',
      'schedule_id',
      'fixedScheduleId',
      'fixed_schedule_id',
      'id',
    ],
    'update_plan_block' ||
    'reschedule_plan_blocks' ||
    'delete_plan_block' ||
    'skip_plan_block' ||
    'start_plan_block_pomodoro' => [
      'planBlockId',
      'plan_block_id',
      'blockId',
      'block_id',
      'id',
    ],
    'update_time_log' || 'delete_time_log' => ['logId', 'todoId', 'id'],
    'update_countdown' ||
    'complete_countdown' ||
    'delete_countdown' => ['countdownId', 'todoId', 'id'],
    'update_todo_group' || 'delete_todo_group' => [
      'groupId',
      'categoryId',
      'folderId',
      'todoId',
      'id',
    ],
    'update_pomodoro_tag' || 'delete_pomodoro_tag' => ['tagId', 'todoId', 'id'],
    'update_habit' ||
    'delete_habit' => ['habitUuid', 'habit_uuid', 'habitId', 'habit_id', 'id'],
    _ => null,
  };
  if (referenceFields == null) return null;
  const actionsWithTodoReferences = {
    'update_todo',
    'complete_todo',
    'skip_todo',
    'delete_todo',
    'reschedule_todo',
    'bulk_reschedule',
    'categorize_todo',
    'split_todo',
  };
  final referenceDomain = switch (actionName) {
    'update_schedule' ||
    'cancel_schedule' ||
    'delete_schedule' => 'fixed_schedules',
    'update_plan_block' ||
    'reschedule_plan_blocks' ||
    'delete_plan_block' ||
    'skip_plan_block' ||
    'start_plan_block_pomodoro' => 'plan_blocks',
    'update_time_log' || 'delete_time_log' => 'time_logs',
    'update_countdown' ||
    'complete_countdown' ||
    'delete_countdown' => 'countdowns',
    'update_todo_group' || 'delete_todo_group' => 'todo_groups',
    'update_pomodoro_tag' || 'delete_pomodoro_tag' => 'pomodoro_tags',
    _ => null,
  };

  final rawRecords = action['updates'] ?? action['blocks'];
  final records = rawRecords is List
      ? rawRecords.whereType<Map>().toList(growable: false)
      : [action];
  if (records.isEmpty) return '$actionName 至少需要一条有效记录';
  for (final record in records) {
    final references = referenceFields
        .map((field) => record[field]?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
    if (references.isEmpty) {
      return '$actionName 每项都必须携带本轮上下文中的真实对象ID';
    }
    if (references.length > 1) {
      return '$actionName每项的对象ID别名互相冲突，请只提供一个真实ID';
    }
    final reference = references.single;
    if (actionsWithTodoReferences.contains(actionName) &&
        normalizedKnownTodoIds != null &&
        !normalizedKnownTodoIds.contains(reference)) {
      return '$actionName引用了当前不存在的待办ID，请先查询并使用真实待办ID';
    }
    if ((actionName == 'update_habit' || actionName == 'delete_habit') &&
        normalizedKnownHabitIds != null &&
        !normalizedKnownHabitIds.contains(reference)) {
      return '$actionName引用了当前不存在的习惯ID，请先查询并使用真实habitUuid';
    }
    final knownDomainIds = referenceDomain == null
        ? null
        : normalizedDomainIds?[referenceDomain];
    if (knownDomainIds != null && !knownDomainIds.contains(reference)) {
      return '$actionName引用了当前不存在的对象ID，请先查询并使用真实ID';
    }
  }
  return null;
}
