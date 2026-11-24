part of '../ai_todo_action_executor.dart';

final RegExp _habitMinuteListSeparatorPattern = RegExp(r'[,，\s]+');
final RegExp _habitMinuteOfDayPattern = RegExp(r'^(\d{1,2}):(\d{1,2})$');
final RegExp _habitTokenNormalizationPattern = RegExp(r'[\s_-]+');

/// 执行已经通过校验并由用户确认的习惯操作。
///
/// 习惯不是 TodoItem：这里通过 HabitRepository 创建、更新或软删除目标，
/// 规则更新保留历史版本；完成一次型习惯在仓库内按需绑定循环待办系列。
Future<List<HabitGoal>> _saveHabitActions({
  required String username,
  required List<AiTodoAction> actions,
  Future<void> Function()? onActionSaved,
}) async {
  final changed = <HabitGoal>[];
  final goals = await HabitRepository.getGoals();
  for (final action in actions) {
    if (!action.isHabitAction ||
        !action.isSelected ||
        action.isAdded ||
        action.isIgnored) {
      continue;
    }
    late final HabitGoal goal;
    switch (action.type) {
      case AiTodoActionType.createHabit:
        final draft = _buildHabitCreationDraft(action);
        if (draft == null) continue;
        goal = await HabitRepository.createGoal(
          name: draft.name,
          icon: draft.icon,
          sourceType: draft.sourceType,
          sourceIds: draft.sourceIds,
          rule: draft.rule,
          displayMode: draft.displayMode,
          defaultFocusMinutes: draft.defaultFocusMinutes,
          username: username,
        );
      case AiTodoActionType.updateHabit:
      case AiTodoActionType.deleteHabit:
        final habitUuid = action.habitUuid?.trim() ?? '';
        final matches = goals
            .where(
              (candidate) =>
                  candidate.uuid == habitUuid && !candidate.isDeleted,
            )
            .toList(growable: false);
        if (matches.length != 1) {
          throw StateError('待修改或删除的习惯已不存在，请重新查询后再试');
        }
        goal = matches.single;
        if (action.type == AiTodoActionType.updateHabit) {
          await _updateHabitFromAction(
            goal: goal,
            action: action,
            username: username,
          );
        } else {
          await HabitRepository.deleteGoal(goal);
        }
      default:
        continue;
    }
    action.isAdded = true;
    changed.add(goal);
    await onActionSaved?.call();
  }
  return changed;
}

bool _isValidHabitAction(AiTodoAction action) {
  switch (action.type) {
    case AiTodoActionType.createHabit:
      return _buildHabitCreationDraft(action) != null;
    case AiTodoActionType.updateHabit:
      final fields = action.metadata['habitUpdateFields'];
      return action.habitUuid?.trim().isNotEmpty == true &&
          fields is Map &&
          _isValidHabitUpdateFields(fields);
    case AiTodoActionType.deleteHabit:
      return action.habitUuid?.trim().isNotEmpty == true;
    default:
      return false;
  }
}

Future<void> _updateHabitFromAction({
  required HabitGoal goal,
  required AiTodoAction action,
  required String username,
}) async {
  final rawFields = action.metadata['habitUpdateFields'];
  if (rawFields is! Map || rawFields.isEmpty) {
    throw StateError('习惯修改草案没有可执行的字段');
  }
  final fields = Map<String, dynamic>.from(rawFields);
  if (!_isValidHabitUpdateFields(fields)) {
    throw StateError('习惯修改草案包含无效字段或取值');
  }
  var goalChanged = false;
  if (fields.containsKey('name')) {
    final value = fields['name']?.toString().trim() ?? '';
    if (value.isEmpty) throw StateError('习惯名称不能为空');
    goal.name = value;
    goalChanged = true;
  }
  if (fields.containsKey('icon')) {
    final value = fields['icon']?.toString().trim() ?? '';
    if (value.isEmpty) throw StateError('习惯图标不能为空');
    goal.icon = value;
    goalChanged = true;
  }
  if (fields.containsKey('displayMode')) {
    final value = _parseHabitDisplayMode(fields['displayMode']?.toString());
    if (value == null) throw StateError('习惯展示位置无效');
    goal.displayMode = value;
    goalChanged = true;
  }
  if (fields.containsKey('defaultFocusMinutes')) {
    final value = int.tryParse(fields['defaultFocusMinutes'].toString());
    if (value == null || value < 1 || value > 240) {
      throw StateError('默认专注时长必须为1至240分钟');
    }
    if (goal.sourceType != HabitSourceType.durationCheckIn &&
        goal.sourceType != HabitSourceType.pomodoroTag) {
      throw StateError('只有时长习惯可以修改默认专注时长');
    }
    goal.defaultFocusMinutes = value;
    goalChanged = true;
  }

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
  final updatesRule = ruleFields.any(fields.containsKey);
  final effectiveFromOption =
      fields['effectiveFromOption']?.toString() ?? 'today';
  if (!updatesRule) {
    if (!goalChanged) throw StateError('习惯修改草案没有可执行的字段');
    await HabitRepository.updateGoal(goal, username: username);
    return;
  }

  final rules = await HabitRepository.getRules(habitUuid: goal.uuid);
  final now = DateTime.now();
  final currentRule =
      HabitRuleResolver.effectiveRule(rules, now) ??
      (rules.where((rule) => !rule.isDeleted).toList()..sort(
            (a, b) => (a.effectiveFromDate ?? '').compareTo(
              b.effectiveFromDate ?? '',
            ),
          ))
          .lastOrNull;
  if (currentRule == null) throw StateError('没有找到该习惯当前生效的规则');
  final pendingDayBoundary = fields.containsKey('dayBoundaryMinute')
      ? _parseHabitMinute(fields['dayBoundaryMinute'])!
      : currentRule.dayBoundaryMinute;
  final todayKey = HabitRuleResolver.dayKey(
    HabitRuleResolver.logicalDateFor(now, pendingDayBoundary),
  );
  final hasFutureRule = rules.any((rule) {
    final effectiveFromDate = rule.effectiveFromDate;
    return !rule.isDeleted &&
        effectiveFromDate != null &&
        effectiveFromDate.compareTo(todayKey) > 0;
  });
  if (hasFutureRule && effectiveFromOption != 'all') {
    throw StateError('该习惯已有未来生效的规则版本；为避免改写预定规则，请先在习惯编辑页核对生效范围');
  }

  if (fields.containsKey('targetValue') &&
      goal.sourceType != HabitSourceType.quantityCheckIn) {
    throw StateError('只有数量型习惯可以修改targetValue');
  }
  if (fields.containsKey('durationMinutes') &&
      goal.sourceType != HabitSourceType.durationCheckIn &&
      goal.sourceType != HabitSourceType.pomodoroTag) {
    throw StateError('只有时长型习惯可以修改durationMinutes');
  }
  if (fields.containsKey('targetTimeMinute') &&
      goal.sourceType != HabitSourceType.timeCheckIn) {
    throw StateError('只有时间点习惯可以修改targetTimeMinute');
  }
  if (fields.containsKey('unit') &&
      goal.sourceType != HabitSourceType.quantityCheckIn &&
      goal.sourceType != HabitSourceType.durationCheckIn &&
      goal.sourceType != HabitSourceType.pomodoroTag) {
    throw StateError('该习惯类型不支持修改unit');
  }
  if (fields.containsKey('quickValues') &&
      goal.sourceType != HabitSourceType.quantityCheckIn) {
    throw StateError('只有数量型习惯可以修改quickValues');
  }
  if ((fields.containsKey('timeComparison') ||
          fields.containsKey('timeToleranceMinutes')) &&
      goal.sourceType != HabitSourceType.timeCheckIn) {
    throw StateError('只有时间点习惯可以修改时间比较规则');
  }

  final periodType = fields.containsKey('periodType')
      ? _parseHabitPeriodType(fields['periodType']?.toString())
      : currentRule.periodType;
  if (periodType == null) throw StateError('习惯周期无效');
  final targetValue = fields.containsKey('targetValue')
      ? _habitNumber(fields['targetValue'])
      : currentRule.targetValue;
  final durationMinutes = fields.containsKey('durationMinutes')
      ? _habitInteger(fields['durationMinutes'])
      : null;
  final updatedRule = HabitGoalRuleRevision(
    habitUuid: goal.uuid,
    periodType: periodType,
    weekdaysMask: fields.containsKey('weekdaysMask')
        ? _habitInteger(fields['weekdaysMask']) ?? currentRule.weekdaysMask
        : currentRule.weekdaysMask,
    customIntervalDays: fields.containsKey('customIntervalDays')
        ? _habitInteger(fields['customIntervalDays'])
        : currentRule.customIntervalDays,
    targetValue: durationMinutes != null
        ? (durationMinutes * 60).toDouble()
        : targetValue ?? currentRule.targetValue,
    unit: fields.containsKey('unit')
        ? fields['unit']?.toString() ?? ''
        : currentRule.unit,
    targetTimeMinute: fields.containsKey('targetTimeMinute')
        ? _parseHabitMinute(fields['targetTimeMinute'])
        : currentRule.targetTimeMinute,
    timeComparison: fields.containsKey('timeComparison')
        ? _parseHabitTimeComparison(fields['timeComparison']?.toString()) ??
              currentRule.timeComparison
        : currentRule.timeComparison,
    timeToleranceMinutes: fields.containsKey('timeToleranceMinutes')
        ? _habitInteger(fields['timeToleranceMinutes']) ??
              currentRule.timeToleranceMinutes
        : currentRule.timeToleranceMinutes,
    dayBoundaryMinute: fields.containsKey('dayBoundaryMinute')
        ? _parseHabitMinute(fields['dayBoundaryMinute']) ??
              currentRule.dayBoundaryMinute
        : currentRule.dayBoundaryMinute,
    quickValues: fields.containsKey('quickValues')
        ? action.quickValues
        : List<int>.from(currentRule.quickValues),
    reminderPolicy: fields.containsKey('reminderPolicy')
        ? _mergeHabitReminderPolicy(
            currentRule.reminderPolicy,
            action.habitReminderPolicy ?? const {},
          )
        : currentRule.reminderPolicy,
  );
  final currentLogicalDay = HabitRuleResolver.dayKey(
    HabitRuleResolver.logicalDateFor(
      DateTime.now(),
      updatedRule.dayBoundaryMinute,
    ),
  );
  final latestRule = rules.where((rule) => !rule.isDeleted).toList()
    ..sort(
      (a, b) =>
          (a.effectiveFromDate ?? '').compareTo(b.effectiveFromDate ?? ''),
    );
  final ruleUpdatePersistsGoalWithoutVersionBump =
      effectiveFromOption == 'all' ||
      (effectiveFromOption != 'nextPeriod' &&
          latestRule.isNotEmpty &&
          latestRule.last.effectiveFromDate == currentLogicalDay);
  if (goalChanged && ruleUpdatePersistsGoalWithoutVersionBump) {
    goal.markAsChanged();
  }
  await HabitRepository.updateRule(
    goal: goal,
    updatedRule: updatedRule,
    effectiveFromOption: effectiveFromOption,
    allRules: rules,
    fieldsToUpdate: {
      if (fields.containsKey('targetValue') ||
          fields.containsKey('durationMinutes'))
        'targetValue',
      for (final field in ruleFields)
        if (field != 'durationMinutes' && fields.containsKey(field)) field,
    },
    username: username,
  );
}

bool _isValidHabitUpdateFields(Map fields) {
  const allowedFields = {
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
    'effectiveFromOption',
  };
  if (fields.isEmpty ||
      fields.keys.any((key) => !allowedFields.contains(key))) {
    return false;
  }
  if (!fields.keys.any((key) => key != 'effectiveFromOption')) return false;
  if (fields.containsKey('name') &&
      fields['name']?.toString().trim().isNotEmpty != true) {
    return false;
  }
  if (fields.containsKey('icon') &&
      fields['icon']?.toString().trim().isNotEmpty != true) {
    return false;
  }
  if (fields.containsKey('displayMode') &&
      _parseHabitDisplayMode(fields['displayMode']?.toString()) == null) {
    return false;
  }
  final focusMinutes = _habitInteger(fields['defaultFocusMinutes']);
  if (fields.containsKey('defaultFocusMinutes') &&
      (focusMinutes == null || focusMinutes < 1 || focusMinutes > 240)) {
    return false;
  }
  final targetValue = _habitNumber(fields['targetValue']);
  if (fields.containsKey('targetValue') &&
      (targetValue == null || targetValue <= 0)) {
    return false;
  }
  if (fields.containsKey('unit') &&
      fields['unit']?.toString().trim().isNotEmpty != true) {
    return false;
  }
  final duration = _habitInteger(fields['durationMinutes']);
  if (fields.containsKey('durationMinutes') &&
      (duration == null || duration < 1)) {
    return false;
  }
  final targetMinute = _parseHabitMinute(fields['targetTimeMinute']);
  if (fields.containsKey('targetTimeMinute') &&
      (targetMinute == null || targetMinute < 0 || targetMinute >= 1440)) {
    return false;
  }
  if (fields.containsKey('timeComparison') &&
      _parseHabitTimeComparison(fields['timeComparison']?.toString()) == null) {
    return false;
  }
  final tolerance = _habitInteger(fields['timeToleranceMinutes']);
  if (fields.containsKey('timeToleranceMinutes') &&
      (tolerance == null || tolerance < 0)) {
    return false;
  }
  final periodType = fields.containsKey('periodType')
      ? _parseHabitPeriodType(fields['periodType']?.toString())
      : null;
  if (fields.containsKey('periodType') &&
      (fields['periodType']?.toString().trim().isNotEmpty != true ||
          periodType == null)) {
    return false;
  }
  final weekdaysMask = _habitInteger(fields['weekdaysMask']);
  if (fields.containsKey('weekdaysMask') &&
      (weekdaysMask == null || weekdaysMask < 1 || weekdaysMask > 127)) {
    return false;
  }
  final interval = _habitInteger(fields['customIntervalDays']);
  if (fields.containsKey('customIntervalDays') &&
      (interval == null || interval < 1)) {
    return false;
  }
  if (periodType == HabitPeriodType.custom &&
      (interval == null || interval < 1)) {
    return false;
  }
  if (periodType == HabitPeriodType.weekdays && weekdaysMask == null) {
    return false;
  }
  final dayBoundary = _parseHabitMinute(fields['dayBoundaryMinute']);
  if (fields.containsKey('dayBoundaryMinute') &&
      (dayBoundary == null || dayBoundary < 0 || dayBoundary >= 1440)) {
    return false;
  }
  if (fields.containsKey('quickValues')) {
    final values = fields['quickValues'];
    if (values is! List ||
        values.length > 4 ||
        values.any((value) => (_habitInteger(value) ?? 0) < 1)) {
      return false;
    }
  }
  if (fields.containsKey('reminderPolicy')) {
    final policy = fields['reminderPolicy'];
    if (policy is! Map) return false;
    final fixedTimes = policy['fixedTimes'] ?? policy['fixed_times'];
    if (fixedTimes != null &&
        (fixedTimes is! List ||
            fixedTimes.any((value) {
              final minute = _parseHabitMinute(value);
              return minute == null || minute < 0 || minute >= 1440;
            }))) {
      return false;
    }
    for (final key in const [
      'progressReminder',
      'progress_reminder',
      'nearEndReminder',
      'near_end_reminder',
      'dailySummaryReminder',
      'daily_summary_reminder',
    ]) {
      final value = policy[key];
      if (value != null &&
          value is! bool &&
          !const {
            'true',
            'false',
            'yes',
            'no',
            '1',
            '0',
          }.contains(value.toString().toLowerCase())) {
        return false;
      }
    }
  }
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
  if (fields.containsKey('effectiveFromOption') &&
      !ruleFields.any(fields.containsKey)) {
    return false;
  }
  final effectiveFromOption = fields['effectiveFromOption']?.toString();
  if (fields.containsKey('effectiveFromOption') &&
      !const {'today', 'nextPeriod', 'all'}.contains(effectiveFromOption)) {
    return false;
  }
  return true;
}

int? _habitInteger(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _habitNumber(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return parsed != null && parsed.isFinite ? parsed : null;
}

HabitReminderPolicy _mergeHabitReminderPolicy(
  HabitReminderPolicy current,
  Map<String, dynamic> update,
) => HabitReminderPolicy(
  fixedTimes: _habitPolicyHas(update, 'fixedTimes', 'fixed_times')
      ? _parseHabitMinuteList(update['fixedTimes'] ?? update['fixed_times'])
      : List<int>.from(current.fixedTimes),
  progressReminder:
      _habitPolicyHas(update, 'progressReminder', 'progress_reminder')
      ? _parseHabitBool(
          update['progressReminder'] ?? update['progress_reminder'],
        )
      : current.progressReminder,
  nearEndReminder:
      _habitPolicyHas(update, 'nearEndReminder', 'near_end_reminder')
      ? _parseHabitBool(
          update['nearEndReminder'] ?? update['near_end_reminder'],
        )
      : current.nearEndReminder,
  dailySummaryReminder:
      _habitPolicyHas(update, 'dailySummaryReminder', 'daily_summary_reminder')
      ? _parseHabitBool(
          update['dailySummaryReminder'] ?? update['daily_summary_reminder'],
        )
      : current.dailySummaryReminder,
);

bool _habitPolicyHas(
  Map<String, dynamic> policy,
  String camelCase,
  String snakeCase,
) => policy.containsKey(camelCase) || policy.containsKey(snakeCase);

_HabitCreationDraft? _buildHabitCreationDraft(AiTodoAction action) {
  final name = action.title?.trim();
  if (name == null || name.isEmpty) return null;

  final sourceType = _parseHabitSourceType(action);
  if (sourceType == null) return null;
  final periodType = _parseHabitPeriodType(action.habitPeriodType);
  if (periodType == null) return null;

  final weekdaysMask =
      action.weekdaysMask ??
      (periodType == HabitPeriodType.weekdays ? 31 : 127);
  if (weekdaysMask < 1 || weekdaysMask > 127) return null;
  final customIntervalDays = action.customIntervalDays;
  if (periodType == HabitPeriodType.custom &&
      (customIntervalDays == null || customIntervalDays < 1)) {
    return null;
  }

  final dayBoundaryMinute = action.dayBoundaryMinute ?? 0;
  if (dayBoundaryMinute < 0 || dayBoundaryMinute >= 1440) return null;

  var targetValue = 0.0;
  var unit = action.unit?.trim() ?? '';
  int? targetTimeMinute;
  var timeComparison = HabitTimeComparison.before;
  var defaultFocusMinutes = action.defaultFocusMinutes;
  final sourceIds = _cleanIds(
    sourceType == HabitSourceType.recurringTodo &&
            action.sourceIds.isEmpty &&
            action.recurrenceSeriesId?.trim().isNotEmpty == true
        ? [action.recurrenceSeriesId!]
        : action.sourceIds,
  );

  switch (sourceType) {
    case HabitSourceType.recurringTodo:
      targetValue = 1;
    case HabitSourceType.pomodoroTag:
      if (sourceIds.isEmpty) return null;
      final durationSeconds = _habitDurationSeconds(action);
      if (durationSeconds == null || durationSeconds < 1) return null;
      targetValue = durationSeconds.toDouble();
      unit = unit.isEmpty ? '分钟' : unit;
    case HabitSourceType.quantityCheckIn:
      final quantity = action.targetValue;
      if (quantity == null || !quantity.isFinite || quantity <= 0) {
        return null;
      }
      targetValue = quantity;
    case HabitSourceType.timeCheckIn:
      targetTimeMinute = action.targetTimeMinute;
      if (targetTimeMinute == null ||
          targetTimeMinute < 0 ||
          targetTimeMinute >= 1440) {
        return null;
      }
      timeComparison =
          _parseHabitTimeComparison(action.habitTimeComparison) ??
          HabitTimeComparison.before;
    case HabitSourceType.durationCheckIn:
      final durationSeconds = _habitDurationSeconds(action);
      if (durationSeconds == null || durationSeconds < 1) return null;
      targetValue = durationSeconds.toDouble();
      unit = unit.isEmpty ? '分钟' : unit;
  }

  if (sourceType != HabitSourceType.pomodoroTag &&
      sourceType != HabitSourceType.durationCheckIn) {
    defaultFocusMinutes = null;
  } else if (defaultFocusMinutes != null) {
    defaultFocusMinutes = defaultFocusMinutes.clamp(1, 240).toInt();
  }

  final tolerance = action.timeToleranceMinutes ?? 0;
  if (tolerance < 0) return null;
  final quickValues = action.quickValues
      .where((value) => value > 0)
      .take(4)
      .toList();
  final effectiveFromDate = _habitEffectiveFromDate(dayBoundaryMinute);
  final rule = HabitGoalRuleRevision(
    habitUuid: '',
    effectiveFromDate: effectiveFromDate,
    periodType: periodType,
    weekdaysMask: weekdaysMask,
    customIntervalDays: customIntervalDays,
    targetValue: targetValue,
    unit: unit,
    targetTimeMinute: targetTimeMinute,
    timeComparison: timeComparison,
    timeToleranceMinutes: tolerance,
    dayBoundaryMinute: dayBoundaryMinute,
    quickValues: quickValues,
    reminderPolicy: _parseHabitReminderPolicy(action),
  );

  return _HabitCreationDraft(
    name: name,
    icon: action.icon?.trim().isNotEmpty == true
        ? action.icon!.trim()
        : HabitRepository.defaultIconForName(name),
    sourceType: sourceType,
    sourceIds: sourceIds,
    rule: rule,
    displayMode:
        _parseHabitDisplayMode(action.habitDisplayMode) ??
        HabitDisplayMode.habitOnly,
    defaultFocusMinutes: defaultFocusMinutes,
  );
}

HabitSourceType? _parseHabitSourceType(AiTodoAction action) {
  final raw = action.habitSourceType?.trim();
  if (raw != null && raw.isNotEmpty) {
    final index = int.tryParse(raw);
    if (index != null && index >= 0 && index < HabitSourceType.values.length) {
      return HabitSourceType.values[index];
    }
    switch (_normalizeHabitToken(raw)) {
      case 'recurringtodo':
      case 'completion':
      case 'completioncheckin':
      case '完成型':
      case '完成一次':
      case '循环待办':
        return HabitSourceType.recurringTodo;
      case 'pomodorotag':
      case '专注标签':
        return HabitSourceType.pomodoroTag;
      case 'quantitycheckin':
      case 'quantity':
      case 'amount':
      case '数量型':
      case '数量':
        return HabitSourceType.quantityCheckIn;
      case 'timecheckin':
      case 'timepoint':
      case '时间点型':
      case '时间点':
        return HabitSourceType.timeCheckIn;
      case 'durationcheckin':
      case 'duration':
      case '时长型':
      case '时长':
        return HabitSourceType.durationCheckIn;
      default:
        return null;
    }
  }
  if (action.targetTimeMinute != null) return HabitSourceType.timeCheckIn;
  if (action.durationMinutes != null) return HabitSourceType.durationCheckIn;
  if (action.targetValue != null) return HabitSourceType.quantityCheckIn;
  return HabitSourceType.recurringTodo;
}

int? _habitDurationSeconds(AiTodoAction action) {
  final minutes = action.durationMinutes;
  if (minutes != null && minutes > 0) return minutes * 60;

  // 兼容模型把时长放进 targetValue 的写法，但只在单位明确时换算，
  // 避免把「30」误判成 30 秒还是 30 分钟。
  final value = action.targetValue;
  if (value == null || !value.isFinite || value <= 0) return null;
  final unit = action.unit?.trim().toLowerCase() ?? '';
  if (unit.contains('秒') || unit == 's' || unit.contains('sec')) {
    return value.round();
  }
  if (unit.contains('小时') || unit == 'h' || unit.contains('hour')) {
    return (value * 3600).round();
  }
  if (unit.contains('分钟') || unit == '分' || unit == 'min') {
    return (value * 60).round();
  }
  return null;
}

HabitPeriodType? _parseHabitPeriodType(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return HabitPeriodType.daily;
  final index = int.tryParse(value);
  if (index != null && index >= 0 && index < HabitPeriodType.values.length) {
    return HabitPeriodType.values[index];
  }
  switch (_normalizeHabitToken(value)) {
    case 'daily':
    case 'day':
    case '每天':
      return HabitPeriodType.daily;
    case 'weekly':
    case 'week':
    case '每周':
      return HabitPeriodType.weekly;
    case 'weekdays':
    case 'workdays':
    case '工作日':
    case '周一至周五':
      return HabitPeriodType.weekdays;
    case 'monthly':
    case 'month':
    case '每月':
      return HabitPeriodType.monthly;
    case 'custom':
    case 'customdays':
    case '自定义':
    case '每隔':
      return HabitPeriodType.custom;
    default:
      return null;
  }
}

HabitTimeComparison? _parseHabitTimeComparison(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final index = int.tryParse(value);
  if (index != null &&
      index >= 0 &&
      index < HabitTimeComparison.values.length) {
    return HabitTimeComparison.values[index];
  }
  switch (_normalizeHabitToken(value)) {
    case 'before':
    case '早于':
    case '之前':
      return HabitTimeComparison.before;
    case 'after':
    case '晚于':
    case '之后':
      return HabitTimeComparison.after;
    default:
      return null;
  }
}

HabitDisplayMode? _parseHabitDisplayMode(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final index = int.tryParse(value);
  if (index != null && index >= 0 && index < HabitDisplayMode.values.length) {
    return HabitDisplayMode.values[index];
  }
  switch (_normalizeHabitToken(value)) {
    case 'habitonly':
    case '仅习惯':
      return HabitDisplayMode.habitOnly;
    case 'todoonly':
    case '仅待办':
      return HabitDisplayMode.todoOnly;
    case 'both':
    case '两者':
      return HabitDisplayMode.both;
    default:
      return null;
  }
}

HabitReminderPolicy _parseHabitReminderPolicy(AiTodoAction action) {
  final raw = action.habitReminderPolicy;
  final fixedTimes = _parseHabitMinuteList(
    raw?['fixedTimes'] ?? raw?['fixed_times'],
  );
  return HabitReminderPolicy(
    fixedTimes: fixedTimes,
    progressReminder: _parseHabitBool(
      raw?['progressReminder'] ?? raw?['progress_reminder'],
    ),
    nearEndReminder: _parseHabitBool(
      raw?['nearEndReminder'] ?? raw?['near_end_reminder'],
    ),
    dailySummaryReminder: _parseHabitBool(
      raw?['dailySummaryReminder'] ?? raw?['daily_summary_reminder'],
    ),
  );
}

List<int> _parseHabitMinuteList(dynamic raw) {
  final values = raw is List
      ? raw
      : raw is String && raw.trim().isNotEmpty
      ? raw.split(_habitMinuteListSeparatorPattern)
      : const <dynamic>[];
  return values
      .map(_parseHabitMinute)
      .whereType<int>()
      .where((value) => value >= 0 && value < 1440)
      .toSet()
      .toList()
    ..sort();
}

int? _parseHabitMinute(dynamic raw) {
  final value = JsonValueParser.toNullableInt(raw);
  if (value != null) return value;
  final text = raw?.toString().trim();
  if (text == null) return null;
  final match = _habitMinuteOfDayPattern.firstMatch(text);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

bool _parseHabitBool(dynamic raw) {
  if (raw == true || raw == 1) return true;
  final value = raw?.toString().trim().toLowerCase();
  return value == 'true' || value == 'yes' || value == '1';
}

List<String> _cleanIds(Iterable<String> ids) {
  return ids
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
}

String _normalizeHabitToken(String value) {
  return value.toLowerCase().replaceAll(_habitTokenNormalizationPattern, '');
}

String _habitEffectiveFromDate(int dayBoundaryMinute) {
  final logicalDate = HabitRuleResolver.logicalDateFor(
    DateTime.now(),
    dayBoundaryMinute,
  );
  return HabitRuleResolver.dayKey(logicalDate);
}
