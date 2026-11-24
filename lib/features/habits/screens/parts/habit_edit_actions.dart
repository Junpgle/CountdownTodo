part of '../habit_edit_screen.dart';

extension _HabitEditActions on _HabitEditScreenState {
  // ── 模板应用 ────────────────────────────────────────
  void _applyTemplate(_HabitTemplate template) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: template.type,
      name: template.name,
    );
    _mutateState(() {
      _creationMode = _HabitCreationMode.template;
      _selectedTemplateName = template.name;
      _nameController.text = template.name;
      _icon = template.icon;
      _sourceType = template.type;
      _periodType = HabitPeriodType.daily;
      _weekdaysMask = 127;
      _crossMidnightBoundary = template.crossMidnight;
      _timeTargetCustomized = false;
      _selectedTagUuids.clear();
      _selectedRecurringSeriesId = _autoCreateRecurringSeries;
      _reminderEnabled = false;
      _fixedTimes.clear();
      _progressReminder = false;
      _nearEndReminder = false;
      _dailySummaryReminder = false;
      _toleranceMinutes = 0;
      _defaultFocusMinutes = null;
      _includeInPlanning = false;
      _preferredStartTime = const TimeOfDay(hour: 20, minute: 0);
      _plannedDurationMinutes = 25;
      _focusTagUuids.clear();
      _autoCheckInOnFocus = true;
      if (template.adaptationKind == HabitAdaptationKind.hydration) {
        // 饮水适合少量多次；默认提供 3 个分散时段，用户仍可在下一步修改。
        _reminderEnabled = true;
        _fixedTimes
          ..clear()
          ..addAll(const [
            TimeOfDay(hour: 8, minute: 0),
            TimeOfDay(hour: 14, minute: 0),
            TimeOfDay(hour: 20, minute: 0),
          ]);
        _progressReminder = true;
        _nearEndReminder = false;
        _dailySummaryReminder = false;
      }
      if (template.adaptationKind == HabitAdaptationKind.pushUp) {
        // 俯卧撑按力量训练安排默认训练日，避免把同一肌群强行设为每天。
        _periodType = HabitPeriodType.weekdays;
        _weekdaysMask = (1 << 0) | (1 << 2) | (1 << 4);
      }
      if (template.adaptationKind == HabitAdaptationKind.running) {
        // 跑步默认安排隔天训练，给初学者留出恢复时间。
        _periodType = HabitPeriodType.weekdays;
        _weekdaysMask = (1 << 0) | (1 << 2) | (1 << 4);
      }
      if (template.adaptationKind == HabitAdaptationKind.reading) {
        // 阅读默认以一个 25 分钟专注块起步，目标时长仍可单独调整。
        _defaultFocusMinutes = 25;
      }
      if (template.adaptationKind == HabitAdaptationKind.learning) {
        // 学习默认用 25 分钟专注块，结束后做一次主动回忆。
        _defaultFocusMinutes = 25;
      }
      if (template.adaptationKind == HabitAdaptationKind.meditation) {
        // 冥想从短时、可持续的 10 分钟开始。
        _defaultFocusMinutes = 10;
      }
      if (adaptation?.kind == HabitAdaptationKind.earlyWake ||
          adaptation?.kind == HabitAdaptationKind.earlySleep) {
        // 时间点型默认保留 15 分钟宽容窗口，并开启目标前提醒。
        _reminderEnabled = true;
        _nearEndReminder = true;
        _toleranceMinutes = 15;
        if (adaptation?.kind == HabitAdaptationKind.earlySleep) {
          _crossMidnightBoundary = true;
        }
      }
      switch (template.type) {
        case HabitSourceType.quantityCheckIn:
          _targetController.text = template.targetValue.round().toString();
          _unitController.text = template.unit;
          _quickValuesText = template.quickValues.join(',');
          _quickValuesController.text = _quickValuesText;
        case HabitSourceType.pomodoroTag:
          _targetMinutes = (template.targetValue / 60).round();
        case HabitSourceType.timeCheckIn:
          _targetTime = TimeOfDay(
            hour: (template.targetTimeMinute ~/ 60) % 24,
            minute: template.targetTimeMinute % 60,
          );
        case HabitSourceType.durationCheckIn:
          _targetMinutes = (template.targetValue / 60).round();
        case HabitSourceType.recurringTodo:
          break;
      }
    });
    _applySleepPairSuggestionIfNeeded();
  }

  void _startCustomCreation() {
    _mutateState(() {
      _creationMode = _HabitCreationMode.custom;
      _selectedTemplateName = null;
      _nameController.clear();
      _icon = '🎯';
      _sourceType = HabitSourceType.quantityCheckIn;
      _displayMode = HabitDisplayMode.habitOnly;
      _periodType = HabitPeriodType.daily;
      _weekdaysMask = 127;
      _customIntervalDays = 2;
      _targetController.clear();
      _unitController.clear();
      _quickValuesText = '';
      _quickValuesController.clear();
      _targetMinutes = 30;
      _targetTime = const TimeOfDay(hour: 7, minute: 0);
      _timeTargetCustomized = false;
      _timeComparison = HabitTimeComparison.before;
      _toleranceMinutes = 0;
      _crossMidnightBoundary = false;
      _selectedTagUuids.clear();
      _selectedRecurringSeriesId = _autoCreateRecurringSeries;
      _reminderEnabled = false;
      _fixedTimes.clear();
      _progressReminder = false;
      _nearEndReminder = false;
      _dailySummaryReminder = false;
      _includeInPlanning = false;
      _preferredStartTime = const TimeOfDay(hour: 20, minute: 0);
      _plannedDurationMinutes = 25;
      _focusTagUuids.clear();
      _autoCheckInOnFocus = true;
    });
  }

  void _handleNameChanged(String value) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: value,
    );
    _mutateState(() {
      if (!_timeTargetCustomized &&
          (adaptation?.kind == HabitAdaptationKind.earlyWake ||
              adaptation?.kind == HabitAdaptationKind.earlySleep)) {
        final isEarlySleep = adaptation?.kind == HabitAdaptationKind.earlySleep;
        _targetTime = isEarlySleep
            ? const TimeOfDay(hour: 23, minute: 30)
            : const TimeOfDay(hour: 7, minute: 0);
        _timeComparison = HabitTimeComparison.before;
        _toleranceMinutes = 15;
        _crossMidnightBoundary = isEarlySleep;
        _reminderEnabled = true;
        _nearEndReminder = true;
      }
    });
    _applySleepPairSuggestionIfNeeded();
  }

  HabitSleepPairSuggestion? _sleepPairSuggestionFor(
    HabitAdaptation? adaptation,
  ) {
    if (!_sleepPairAnchorsLoaded || adaptation == null) return null;
    final anchor = switch (adaptation.kind) {
      HabitAdaptationKind.earlyWake => _existingEarlySleep,
      HabitAdaptationKind.earlySleep => _existingEarlyWake,
      HabitAdaptationKind.hydration => null,
      HabitAdaptationKind.pushUp => null,
      HabitAdaptationKind.running => null,
      HabitAdaptationKind.reading => null,
      HabitAdaptationKind.learning => null,
      HabitAdaptationKind.vocabulary => null,
      HabitAdaptationKind.meditation => null,
      HabitAdaptationKind.sleepDuration => null,
      HabitAdaptationKind.quitSugaryDrinks => null,
    };
    if (anchor == null) return null;
    return HabitAdaptationService.pairSuggestionFor(
      sourceKind: anchor.kind,
      sourceName: anchor.name,
      sourceMinute: anchor.targetMinute,
    );
  }

  void _applySleepPairSuggestionIfNeeded() {
    if (widget.goal != null ||
        _sourceType != HabitSourceType.timeCheckIn ||
        _timeTargetCustomized) {
      return;
    }
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    final suggestion = _sleepPairSuggestionFor(adaptation);
    if (suggestion == null) return;
    _mutateState(() {
      _targetTime = TimeOfDay(
        hour: (suggestion.recommendedMinute ~/ 60) % 24,
        minute: suggestion.recommendedMinute % 60,
      );
      _timeComparison = HabitTimeComparison.before;
      _toleranceMinutes = 15;
      _crossMidnightBoundary =
          suggestion.targetKind == HabitAdaptationKind.earlySleep;
      _reminderEnabled = true;
      _nearEndReminder = true;
    });
  }

  // ── 校验 ────────────────────────────────────────────
  /// 校验当前步骤，返回错误文案（null 表示通过）。
  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (widget.goal == null && _creationMode == null) {
          return '请先选择一个模板，或进入手动自定义';
        }
        if (widget.goal == null &&
            _creationMode == _HabitCreationMode.template &&
            _selectedTemplateName == null) {
          return '请从模板列表中选择一个模板';
        }
        if (_nameController.text.trim().isEmpty) return '请填写习惯名称';
      case 1:
        if (_periodType == HabitPeriodType.weekdays && _weekdaysMask == 0) {
          return '请至少选择一天';
        }
      case 2:
        switch (_sourceType) {
          case HabitSourceType.quantityCheckIn:
            final target = double.tryParse(_targetController.text.trim());
            if (target == null || target <= 0) return '请填写有效的目标数量';
          case HabitSourceType.pomodoroTag:
            if (_targetMinutes <= 0) return '请填写有效的目标时长';
            if (_selectedTagUuids.isEmpty) return '请至少绑定一个专注标签';
          case HabitSourceType.timeCheckIn:
          case HabitSourceType.recurringTodo:
            break;
          case HabitSourceType.durationCheckIn:
            if (_targetMinutes <= 0) return '请填写有效的目标时长';
        }
    }
    return null;
  }

  String? _validate() {
    for (int i = 0; i < 4; i++) {
      final error = _validateStep(i);
      if (error != null) return error;
    }
    return null;
  }

  HabitGoalRuleRevision _buildRule() {
    final unit = _unitController.text.trim();
    final quickValues = _quickValuesText
        .split(RegExp(r'[,，\s]+'))
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .where((e) => e > 0)
        .take(4)
        .toList();

    double targetValue = 1;
    switch (_sourceType) {
      case HabitSourceType.quantityCheckIn:
        targetValue = double.tryParse(_targetController.text.trim()) ?? 1;
      case HabitSourceType.pomodoroTag:
        targetValue = (_targetMinutes * 60).toDouble();
      case HabitSourceType.timeCheckIn:
        break;
      case HabitSourceType.durationCheckIn:
        targetValue = (_targetMinutes * 60).toDouble();
      case HabitSourceType.recurringTodo:
        break;
    }

    final fixedTimes = _reminderEnabled
        ? _fixedTimes.map((t) => t.hour * 60 + t.minute).toList()
        : const <int>[];

    return HabitGoalRuleRevision(
      habitUuid: widget.goal?.uuid ?? '',
      periodType: _periodType,
      weekdaysMask: _weekdaysMask,
      customIntervalDays: _periodType == HabitPeriodType.custom
          ? _customIntervalDays
          : null,
      targetValue: targetValue,
      unit: _sourceType == HabitSourceType.quantityCheckIn
          ? unit
          : _sourceType == HabitSourceType.durationCheckIn
          ? '小时'
          : '',
      targetTimeMinute: _sourceType == HabitSourceType.timeCheckIn
          ? _targetTime.hour * 60 + _targetTime.minute
          : null,
      timeComparison: _timeComparison,
      timeToleranceMinutes: _toleranceMinutes,
      dayBoundaryMinute:
          (_sourceType == HabitSourceType.timeCheckIn &&
                  _crossMidnightBoundary) ||
              (_sourceType == HabitSourceType.durationCheckIn &&
                  HabitAdaptationService.forDraft(
                        sourceType: _sourceType,
                        name: _nameController.text,
                      )?.kind ==
                      HabitAdaptationKind.sleepDuration)
          ? 4 * 60
          : 0,
      quickValues: _sourceType == HabitSourceType.quantityCheckIn
          ? quickValues
          : const [],
      reminderPolicy: HabitReminderPolicy(
        fixedTimes: fixedTimes,
        progressReminder: _progressReminder,
        nearEndReminder: _nearEndReminder,
        dailySummaryReminder: _dailySummaryReminder,
        includeInPlanning: _includeInPlanning,
        preferredStartMinute: _includeInPlanning
            ? _preferredStartTime.hour * 60 + _preferredStartTime.minute
            : null,
        plannedDurationMinutes: _includeInPlanning
            ? _plannedDurationMinutes
            : null,
        focusTagUuids: _sourceType == HabitSourceType.pomodoroTag
            ? const []
            : List<String>.from(_focusTagUuids),
        autoCheckInOnFocus: _autoCheckInOnFocus,
      ),
    );
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      AppSnackBars.showSnackBar(context, SnackBar(content: Text(error)));
      return;
    }
    _mutateState(() => _saving = true);
    try {
      final username = (await StorageService.getLoginSession() ?? '').trim();
      final rule = _buildRule();
      final goal = widget.goal;
      var recurringSourceIds =
          _selectedRecurringSeriesId == _autoCreateRecurringSeries
          ? const <String>[]
          : <String>[_selectedRecurringSeriesId];
      if (goal == null) {
        await HabitRepository.createGoal(
          name: _nameController.text.trim(),
          icon: _icon,
          sourceType: _sourceType,
          sourceIds: _sourceType == HabitSourceType.recurringTodo
              ? recurringSourceIds
              : _sourceType == HabitSourceType.pomodoroTag
              ? _selectedTagUuids
              : const <String>[],
          rule: rule,
          displayMode: HabitDisplayMode.habitOnly,
          defaultFocusMinutes: _sourceType == HabitSourceType.pomodoroTag
              ? _defaultFocusMinutes
              : (_includeInPlanning
                    ? _plannedDurationMinutes
                    : _defaultFocusMinutes),
          username: username,
        );
      } else {
        goal.name = _nameController.text.trim();
        goal.icon = _icon;
        goal.displayMode = _displayMode;
        // 时长型：同步绑定标签与默认专注时长。
        if (goal.sourceType == HabitSourceType.pomodoroTag) {
          goal.sourceIds = List.from(_selectedTagUuids);
          goal.defaultFocusMinutes = _defaultFocusMinutes;
        } else if (goal.sourceType == HabitSourceType.durationCheckIn) {
          goal.sourceIds = [];
          goal.defaultFocusMinutes = _includeInPlanning
              ? _plannedDurationMinutes
              : _defaultFocusMinutes;
        } else {
          goal.sourceIds = [];
          goal.defaultFocusMinutes = _includeInPlanning
              ? _plannedDurationMinutes
              : _defaultFocusMinutes;
        }
        final allRules = await HabitRepository.getRules(habitUuid: goal.uuid);
        await HabitRepository.updateGoal(goal, username: username);
        await HabitRepository.updateRule(
          goal: goal,
          updatedRule: rule,
          effectiveFromOption: _effectiveFromOption,
          allRules: allRules,
          username: username,
        );
      }
      // 规则或提醒策略可能变化：重排习惯提醒。
      unawaited(HabitReminderService.rescheduleAll());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) _mutateState(() => _saving = false);
    }
  }

  void _selectRecurringTodo(String seriesId) {
    if (seriesId == _autoCreateRecurringSeries) {
      _mutateState(() => _selectedRecurringSeriesId = seriesId);
      return;
    }
    final todo = _recurringTodos
        .where((item) => (item.recurrenceSeriesId ?? item.id) == seriesId)
        .firstOrNull;
    _mutateState(() {
      _selectedRecurringSeriesId = seriesId;
      _sourceType = HabitSourceType.recurringTodo;
      _displayMode = HabitDisplayMode.habitOnly;
      if (todo != null) {
        _nameController.text = todo.title;
        _icon = HabitRepository.defaultIconForName(todo.title);
        _applyRecurrenceFromTodo(todo);
      }
    });
  }

  void _applyRecurrenceFromTodo(TodoItem todo) {
    switch (todo.recurrence) {
      case RecurrenceType.weekly:
        _periodType = HabitPeriodType.weekly;
      case RecurrenceType.monthly:
        _periodType = HabitPeriodType.monthly;
      case RecurrenceType.weekdays:
        _periodType = HabitPeriodType.weekdays;
        _weekdaysMask = 31;
      case RecurrenceType.customDays:
        _periodType = HabitPeriodType.custom;
        _customIntervalDays = (todo.customIntervalDays ?? 2).clamp(1, 365);
      case RecurrenceType.daily:
      case RecurrenceType.yearly:
      case RecurrenceType.none:
        _periodType = HabitPeriodType.daily;
    }
  }
}
