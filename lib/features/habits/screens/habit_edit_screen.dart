import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../models.dart';
import '../../../services/pomodoro_service.dart';
import '../../../storage_service.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_reminder_service.dart';
import '../services/habit_rule_resolver.dart';
import '../widgets/habit_adaptation_panel.dart';
import '../widgets/habit_water_target_picker.dart';

/// 新建 / 编辑习惯。
///
/// 新建流程：模板 / 自定义 → 类型与周期 → 目标 → 提醒。
/// 编辑模式下类型不可修改。保存成功后 pop(true)。
class HabitEditScreen extends StatefulWidget {
  /// 为空表示新建；否则编辑该习惯。
  final HabitGoal? goal;

  const HabitEditScreen({super.key, this.goal});

  @override
  State<HabitEditScreen> createState() => _HabitEditScreenState();
}

class _HabitEditScreenState extends State<HabitEditScreen> {
  int _step = 0;

  _HabitCreationMode? _creationMode;
  String? _selectedTemplateName;

  final _nameController = TextEditingController();
  String _icon = '🎯';
  HabitSourceType _sourceType = HabitSourceType.quantityCheckIn;
  HabitDisplayMode _displayMode = HabitDisplayMode.habitOnly;
  HabitPeriodType _periodType = HabitPeriodType.daily;
  int _weekdaysMask = 127;
  int _customIntervalDays = 2;

  final _targetController = TextEditingController();
  final _unitController = TextEditingController();
  final _quickValuesController = TextEditingController();
  String _quickValuesText = '';
  int _targetMinutes = 30;
  TimeOfDay _targetTime = const TimeOfDay(hour: 7, minute: 0);
  bool _timeTargetCustomized = false;
  _SleepPairAnchor? _existingEarlyWake;
  _SleepPairAnchor? _existingEarlySleep;
  bool _sleepPairAnchorsLoaded = false;
  HabitTimeComparison _timeComparison = HabitTimeComparison.before;
  int _toleranceMinutes = 0;
  bool _crossMidnightBoundary = false;

  // 时长型：绑定专注标签（可多选，sourceIds 存标签 UUID）。
  List<PomodoroTag> _tags = [];
  List<String> _selectedTagUuids = [];

  // 完成型：绑定循环待办系列；未选择时由保存流程自动创建。
  static const _autoCreateRecurringSeries = '__auto_create_recurring__';
  List<TodoItem> _recurringTodos = [];
  String _selectedRecurringSeriesId = _autoCreateRecurringSeries;

  bool _reminderEnabled = false;
  final List<TimeOfDay> _fixedTimes = [];
  bool _progressReminder = false;
  bool _nearEndReminder = false;
  bool _dailySummaryReminder = false;

  /// 时长型：开始专注时的默认时长（分钟），为空使用专注设置默认值。
  int? _defaultFocusMinutes;

  /// 编辑模式：规则生效时间（'today' | 'nextPeriod' | 'all'）。
  String _effectiveFromOption = 'today';

  bool _saving = false;

  static const _icons = [
    '🎯',
    '✅',
    '💧',
    '🌅',
    '🌙',
    '💪',
    '📖',
    '🏃',
    '📚',
    '🧘',
    '💊',
    '🧹',
    '🔤',
    '🍎',
    '🦷',
    '🌿',
    '🥗',
    '🏊',
    '🚶',
    '✍️',
    '🎹',
  ];

  static const _templates = <_HabitTemplate>[
    _HabitTemplate('喝水', '💧', HabitSourceType.quantityCheckIn,
        targetValue: 1600,
        unit: 'ml',
        quickValues: [200, 300, 500],
        adaptationKind: HabitAdaptationKind.hydration),
    _HabitTemplate('早起', '🌅', HabitSourceType.timeCheckIn,
        targetTimeMinute: 7 * 60,
        adaptationKind: HabitAdaptationKind.earlyWake),
    _HabitTemplate('早睡', '🌙', HabitSourceType.timeCheckIn,
        targetTimeMinute: 23 * 60 + 30,
        crossMidnight: true,
        adaptationKind: HabitAdaptationKind.earlySleep),
    _HabitTemplate('每日签到', '✅', HabitSourceType.recurringTodo),
    _HabitTemplate('俯卧撑', '💪', HabitSourceType.quantityCheckIn,
        targetValue: 24,
        unit: '个',
        quickValues: [8, 12, 16],
        adaptationKind: HabitAdaptationKind.pushUp),
    _HabitTemplate('阅读', '📖', HabitSourceType.pomodoroTag,
        targetValue: 30 * 60, adaptationKind: HabitAdaptationKind.reading),
    _HabitTemplate('运动', '🏃', HabitSourceType.pomodoroTag,
        targetValue: 30 * 60),
    _HabitTemplate('学习', '📚', HabitSourceType.pomodoroTag,
        targetValue: 45 * 60, adaptationKind: HabitAdaptationKind.learning),
    _HabitTemplate('冥想', '🧘', HabitSourceType.pomodoroTag,
        targetValue: 10 * 60, adaptationKind: HabitAdaptationKind.meditation),
    _HabitTemplate('维生素', '💊', HabitSourceType.quantityCheckIn,
        targetValue: 1, unit: '粒', quickValues: [1]),
    _HabitTemplate('整理', '🧹', HabitSourceType.quantityCheckIn,
        targetValue: 1, unit: '次', quickValues: [1]),
    _HabitTemplate('单词', '🔤', HabitSourceType.quantityCheckIn,
        targetValue: 30,
        unit: '个',
        quickValues: [10, 20, 30],
        adaptationKind: HabitAdaptationKind.vocabulary),
    _HabitTemplate('跑步', '🏃', HabitSourceType.quantityCheckIn,
        targetValue: 30,
        unit: '分钟',
        quickValues: [20, 30, 45],
        adaptationKind: HabitAdaptationKind.running),
  ];

  /// 深度适配模板优先展示，普通模板保持原有相对顺序。
  List<_HabitTemplate> get _orderedTemplates {
    final adapted = <_HabitTemplate>[];
    final standard = <_HabitTemplate>[];
    for (final template in _templates) {
      final hasAdaptation = template.adaptationKind != null ||
          HabitAdaptationService.forDraft(
                sourceType: template.type,
                name: template.name,
              ) !=
              null;
      (hasAdaptation ? adapted : standard).add(template);
    }
    return [...adapted, ...standard];
  }

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    if (goal != null) {
      _nameController.text = goal.name;
      _icon = goal.icon.isNotEmpty ? goal.icon : '🎯';
      _sourceType = goal.sourceType;
      _displayMode = goal.displayMode;
      _selectedTagUuids = List.from(goal.sourceIds);
      if (_sourceType == HabitSourceType.recurringTodo &&
          goal.sourceIds.isNotEmpty) {
        _selectedRecurringSeriesId = goal.sourceIds.first;
      }
      _defaultFocusMinutes = goal.defaultFocusMinutes;
      _creationMode = _HabitCreationMode.custom;
      _timeTargetCustomized = true;
      _step = 0;
      _loadRuleForEdit(goal);
    }
    _loadTags();
    _loadRecurringTodos();
    _loadSleepPairAnchors();
  }

  /// 编辑模式：加载当前生效的规则并回填所有规则级字段，
  /// 避免保存时把原有规则配置重置为默认值。
  Future<void> _loadRuleForEdit(HabitGoal goal) async {
    try {
      final allRules = await HabitRepository.getRules(habitUuid: goal.uuid);
      final rule = allRules
              .where((r) => r.uuid == goal.currentRuleUuid && !r.isDeleted)
              .firstOrNull ??
          HabitRuleResolver.currentRule(
              allRules, HabitRuleResolver.defaultDayBoundaryMinute, null);
      if (rule == null || !mounted) return;

      final fixedTimes = rule.reminderPolicy.fixedTimes
          .map((m) => TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60))
          .toList();

      setState(() {
        _periodType = rule.periodType;
        _weekdaysMask = rule.weekdaysMask;
        _customIntervalDays = rule.customIntervalDays ?? 2;
        switch (goal.sourceType) {
          case HabitSourceType.quantityCheckIn:
            _targetController.text = _formatTargetValue(rule.targetValue);
            _unitController.text = rule.unit;
            _quickValuesText = rule.quickValues.join(',');
            _quickValuesController.text = _quickValuesText;
          case HabitSourceType.pomodoroTag:
            _targetMinutes = (rule.targetValue / 60).round().clamp(5, 240);
          case HabitSourceType.timeCheckIn:
            final m = rule.targetTimeMinute;
            if (m != null) {
              _targetTime = TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
            }
            _timeComparison = rule.timeComparison;
            _toleranceMinutes = rule.timeToleranceMinutes;
          case HabitSourceType.recurringTodo:
            break;
        }
        _crossMidnightBoundary = rule.dayBoundaryMinute > 0;
        _reminderEnabled = rule.reminderPolicy.fixedTimes.isNotEmpty ||
            rule.reminderPolicy.progressReminder ||
            rule.reminderPolicy.nearEndReminder ||
            rule.reminderPolicy.dailySummaryReminder;
        _fixedTimes
          ..clear()
          ..addAll(fixedTimes);
        _progressReminder = rule.reminderPolicy.progressReminder;
        _nearEndReminder = rule.reminderPolicy.nearEndReminder;
        _dailySummaryReminder = rule.reminderPolicy.dailySummaryReminder;
      });
    } catch (e) {
      // 加载失败不阻塞编辑；保存时仍会基于当前输入生成规则。
      debugPrint('⚠️ 编辑习惯加载规则失败: $e');
    }
  }

  static String _formatTargetValue(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  Future<void> _loadTags() async {
    final tags = await PomodoroService.getTags();
    if (!mounted) return;
    setState(() {
      _tags = tags.where((t) => !t.isDeleted && !t.isArchived).toList();
    });
  }

  Future<void> _loadRecurringTodos() async {
    try {
      final username = await StorageService.getLoginSession() ?? '';
      final todos = await StorageService.getTodos(username);
      final seenSeries = <String>{};
      final candidates = <TodoItem>[];
      for (final todo in todos) {
        if (todo.isDeleted || todo.recurrence == RecurrenceType.none) {
          continue;
        }
        final seriesId = todo.recurrenceSeriesId ?? todo.id;
        if (!seenSeries.add(seriesId)) continue;
        candidates.add(todo);
      }
      candidates.sort((a, b) => a.title.compareTo(b.title));
      if (!mounted) return;
      setState(() => _recurringTodos = candidates);
    } catch (_) {
      // 读取待办失败不阻塞习惯编辑，保存时仍可自动创建循环待办。
    }
  }

  Future<void> _loadSleepPairAnchors() async {
    if (widget.goal != null) return;
    try {
      final goals = await HabitRepository.getActiveGoals();
      _SleepPairAnchor? earlyWake;
      _SleepPairAnchor? earlySleep;
      for (final goal in goals) {
        if (goal.sourceType != HabitSourceType.timeCheckIn) continue;
        final adaptation = HabitAdaptationService.forHabit(goal);
        if (adaptation?.kind != HabitAdaptationKind.earlyWake &&
            adaptation?.kind != HabitAdaptationKind.earlySleep) {
          continue;
        }
        final rules = await HabitRepository.getRules(habitUuid: goal.uuid);
        final rule = rules
                .where((candidate) =>
                    candidate.uuid == goal.currentRuleUuid &&
                    !candidate.isDeleted)
                .firstOrNull ??
            HabitRuleResolver.currentRule(
                rules, HabitRuleResolver.defaultDayBoundaryMinute, null);
        final targetMinute = rule?.targetTimeMinute;
        if (targetMinute == null) continue;
        final anchor = _SleepPairAnchor(
          name: goal.name,
          kind: adaptation!.kind,
          targetMinute: targetMinute,
          updatedAt: rule!.updatedAt > goal.updatedAt
              ? rule.updatedAt
              : goal.updatedAt,
        );
        if (anchor.kind == HabitAdaptationKind.earlyWake &&
            (earlyWake == null || anchor.updatedAt > earlyWake.updatedAt)) {
          earlyWake = anchor;
        }
        if (anchor.kind == HabitAdaptationKind.earlySleep &&
            (earlySleep == null || anchor.updatedAt > earlySleep.updatedAt)) {
          earlySleep = anchor;
        }
      }
      if (!mounted) return;
      setState(() {
        _existingEarlyWake = earlyWake;
        _existingEarlySleep = earlySleep;
        _sleepPairAnchorsLoaded = true;
      });
      _applySleepPairSuggestionIfNeeded();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sleepPairAnchorsLoaded = true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    _quickValuesController.dispose();
    super.dispose();
  }

  // ── 模板应用 ────────────────────────────────────────
  void _applyTemplate(_HabitTemplate template) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: template.type,
      name: template.name,
    );
    setState(() {
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
        case HabitSourceType.recurringTodo:
          break;
      }
    });
    _applySleepPairSuggestionIfNeeded();
  }

  void _startCustomCreation() {
    setState(() {
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
    });
  }

  void _handleNameChanged(String value) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: value,
    );
    setState(() {
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
    setState(() {
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
      customIntervalDays:
          _periodType == HabitPeriodType.custom ? _customIntervalDays : null,
      targetValue: targetValue,
      unit: _sourceType == HabitSourceType.quantityCheckIn ? unit : '',
      targetTimeMinute: _sourceType == HabitSourceType.timeCheckIn
          ? _targetTime.hour * 60 + _targetTime.minute
          : null,
      timeComparison: _timeComparison,
      timeToleranceMinutes: _toleranceMinutes,
      dayBoundaryMinute:
          _sourceType == HabitSourceType.timeCheckIn && _crossMidnightBoundary
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
      ),
    );
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final rule = _buildRule();
      final goal = widget.goal;
      var recurringSourceIds =
          _selectedRecurringSeriesId == _autoCreateRecurringSeries
              ? (goal?.sourceType == HabitSourceType.recurringTodo
                  ? List<String>.from(goal!.sourceIds)
                  : const <String>[])
              : <String>[_selectedRecurringSeriesId];
      if (goal != null &&
          goal.sourceType == HabitSourceType.recurringTodo &&
          recurringSourceIds.isEmpty) {
        final username = await StorageService.getLoginSession() ?? '';
        final seriesId = await HabitRepository.createRecurringTodoBinding(
          name: _nameController.text.trim(),
          rule: rule,
          username: username,
        );
        recurringSourceIds = [seriesId];
      }
      if (goal == null) {
        await HabitRepository.createGoal(
          name: _nameController.text.trim(),
          icon: _icon,
          sourceType: _sourceType,
          sourceIds: _sourceType == HabitSourceType.recurringTodo
              ? recurringSourceIds
              : _selectedTagUuids,
          rule: rule,
          displayMode: _displayMode,
          defaultFocusMinutes: _sourceType == HabitSourceType.pomodoroTag
              ? _defaultFocusMinutes
              : null,
        );
      } else {
        goal.name = _nameController.text.trim();
        goal.icon = _icon;
        goal.displayMode = _displayMode;
        // 时长型：同步绑定标签与默认专注时长。
        if (goal.sourceType == HabitSourceType.pomodoroTag) {
          goal.sourceIds = List.from(_selectedTagUuids);
          goal.defaultFocusMinutes = _defaultFocusMinutes;
        } else if (goal.sourceType == HabitSourceType.recurringTodo &&
            recurringSourceIds.isNotEmpty) {
          goal.sourceIds = recurringSourceIds;
        }
        final allRules = await HabitRepository.getRules(habitUuid: goal.uuid);
        await HabitRepository.updateGoal(goal);
        await HabitRepository.updateRule(
          goal: goal,
          updatedRule: rule,
          effectiveFromOption: _effectiveFromOption,
          allRules: allRules,
        );
      }
      // 规则或提醒策略可能变化：重排习惯提醒。
      unawaited(HabitReminderService.rescheduleAll());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final content = switch (_step) {
          0 => _buildCreationStep(),
          1 => _buildTypeStep(),
          2 => _buildTargetStep(),
          _ => _buildReminderStep(),
        };

        final formArea = AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.05, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_step),
            child: content,
          ),
        );

        if (isWide) {
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.goal == null ? '新建习惯' : '编辑习惯'),
              centerTitle: false,
            ),
            body: Row(
              children: [
                SizedBox(
                  width: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          '设置进度',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(child: _buildWideStepIndicator()),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 600),
                              child: formArea,
                            ),
                          ),
                        ),
                      ),
                      _buildBottomBar(isWide: true),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.goal == null ? '新建习惯' : '编辑习惯'),
            centerTitle: true,
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  _buildStepIndicator(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      child: formArea,
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomBar(isWide: false),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 宽屏纵向步骤指示器 ──────────────────────────────────────
  Widget _buildWideStepIndicator() {
    final labels = widget.goal == null
        ? const ['模板 / 自定义', '类型与周期', '目标设定', '习惯提醒']
        : const ['基本信息', '类型与周期', '目标设定', '习惯提醒'];
    final colorScheme = Theme.of(context).colorScheme;
    final steps = labels;
    final current = _step;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: steps.length,
      itemBuilder: (context, i) {
        final isActive = i == current;
        final isDone = i < current;
        return Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDone || isActive
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                    child: isDone
                        ? Icon(Icons.check_rounded,
                            size: 18, color: colorScheme.onPrimary)
                        : Text('${i + 1}',
                            style: TextStyle(
                                color: isActive
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold)),
                  ),
                  if (i < steps.length - 1)
                    Container(
                      width: 2,
                      height: 32,
                      margin: const EdgeInsets.only(top: 8),
                      color: isDone
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      color: isActive || isDone
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 窄屏步骤指示器 (现代进度条) ──────────────────────────────────────
  Widget _buildStepIndicator() {
    final labels = widget.goal == null
        ? const ['模板 / 自定义', '类型与周期', '目标', '提醒']
        : const ['基本信息', '类型与周期', '目标', '提醒'];
    final colorScheme = Theme.of(context).colorScheme;
    final steps = labels;
    final current = _step;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
            bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                steps[current],
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface),
              ),
              Text(
                '${current + 1} / ${steps.length}',
                style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(steps.length, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < steps.length - 1 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: i <= current
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar({required bool isWide}) {
    final colorScheme = Theme.of(context).colorScheme;
    final lastStep = 3;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
              isWide ? 12 : (bottomPadding > 0 ? bottomPadding : 12)),
          decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.8),
              border: Border(
                  top: BorderSide(
                      color:
                          colorScheme.outlineVariant.withValues(alpha: 0.3))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                )
              ]),
          child: Row(
            children: [
              if (_step > 0)
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => setState(() => _step--),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('上一步'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                )
              else
                const SizedBox(width: 0),
              const Spacer(),
              if (_step < lastStep)
                FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          final error = _validateStep(_step);
                          if (error != null) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(error),
                                behavior: SnackBarBehavior.floating));
                            return;
                          }
                          setState(() => _step++);
                        },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('下一步'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(_saving ? '保存中…' : '完成'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 第 1 步：模板 / 手动自定义 ─────────────────────────
  Widget _buildCreationStep() {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.goal != null) {
      return _buildIdentityEditor(
        colorScheme,
        title: '基本信息',
        subtitle: '编辑习惯名称和图标；习惯类型保持不变。',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '从哪里开始？',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '先确定习惯的起点，下一步再设置类型、周期和目标。',
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _creationModeCard(
          mode: _HabitCreationMode.template,
          title: '从模板创建',
          subtitle: '直接获得合适的类型、目标和快捷操作，再按需调整。',
          icon: Icons.auto_awesome_rounded,
        ),
        _creationModeCard(
          mode: _HabitCreationMode.custom,
          title: '手动自定义',
          subtitle: '从空白开始，自己决定习惯名称、类型、周期和目标。',
          icon: Icons.tune_rounded,
        ),
        if (_creationMode != null) ...[
          const SizedBox(height: 20),
          if (_creationMode == _HabitCreationMode.template)
            _buildTemplatePicker(colorScheme),
          const SizedBox(height: 16),
          _buildIdentityEditor(
            colorScheme,
            title: _creationMode == _HabitCreationMode.template
                ? '确认基本信息'
                : '自定义基本信息',
            subtitle: _creationMode == _HabitCreationMode.template
                ? '模板已经填好默认值，名称和图标仍可修改。'
                : '给习惯起一个清楚的名字，之后再选择类型与周期。',
          ),
        ],
      ],
    );
  }

  Widget _creationModeCard({
    required _HabitCreationMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _creationMode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            if (selected) return;
            if (mode == _HabitCreationMode.custom) {
              _startCustomCreation();
            } else {
              setState(() {
                _creationMode = mode;
                _selectedTemplateName = null;
              });
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    selected ? colorScheme.primary : colorScheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 24,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                          )),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.chevron_right_rounded,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTemplatePicker(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '选择一个模板',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (_selectedTemplateName != null)
              Text(
                '已选：$_selectedTemplateName',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _orderedTemplates.map((template) {
              final isSelected = _selectedTemplateName == template.name;
              return SizedBox(
                width: 104,
                child: Material(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => _applyTemplate(template),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 82,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant
                                  .withValues(alpha: 0.55),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(template.icon,
                              style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 5),
                          Text(
                            template.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityEditor(
    ColorScheme colorScheme, {
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                maxLength: 20,
                onChanged: _handleNameChanged,
                decoration: const InputDecoration(
                  labelText: '习惯名称',
                  hintText: '如：喝水、早起、阅读',
                  border: OutlineInputBorder(),
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _buildIconPicker(),
          ],
        ),
        if (widget.goal != null &&
            _sourceType == HabitSourceType.recurringTodo &&
            _selectedRecurringSeriesId != _autoCreateRecurringSeries) ...[
          const SizedBox(height: 8),
          Text(
            '已从关联循环待办带入名称和图标，可按需修改。',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (widget.goal == null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _creationMode == _HabitCreationMode.template
                ? _startCustomCreation
                : () => setState(() {
                      _creationMode = _HabitCreationMode.template;
                      _selectedTemplateName = null;
                    }),
            icon: Icon(_creationMode == _HabitCreationMode.template
                ? Icons.tune_rounded
                : Icons.auto_awesome_rounded),
            label: Text(_creationMode == _HabitCreationMode.template
                ? '改为手动自定义'
                : '改为从模板创建'),
          ),
        ],
      ],
    );
  }

  Widget _buildIconPicker() {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _showIconDialog(),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Text(_icon, style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  Future<void> _showIconDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择图标'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _icons
              .map(
                (icon) => InkWell(
                  onTap: () => Navigator.pop(context, icon),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(icon, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      setState(() => _icon = selected);
    }
  }

  // ── 第 1 步：类型与周期 ───────────────────────────────
  Widget _buildTypeStep() {
    final isEdit = widget.goal != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '习惯类型',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (isEdit)
          _typeCard(
            _sourceType,
            selected: true,
            enabled: false,
          )
        else ...[
          _typeCard(HabitSourceType.recurringTodo,
              selected: _sourceType == HabitSourceType.recurringTodo),
          _typeCard(HabitSourceType.pomodoroTag,
              selected: _sourceType == HabitSourceType.pomodoroTag),
          _typeCard(HabitSourceType.quantityCheckIn,
              selected: _sourceType == HabitSourceType.quantityCheckIn),
          _typeCard(HabitSourceType.timeCheckIn,
              selected: _sourceType == HabitSourceType.timeCheckIn),
        ],
        const SizedBox(height: 20),
        _buildPeriodSection(),
        if (_sourceType == HabitSourceType.recurringTodo) ...[
          const SizedBox(height: 20),
          _buildRecurringTodoBinding(colorScheme),
          const SizedBox(height: 16),
          _buildDisplayModeSection(colorScheme),
        ],
      ],
    );
  }

  void _selectRecurringTodo(String seriesId) {
    if (seriesId == _autoCreateRecurringSeries) {
      setState(() => _selectedRecurringSeriesId = seriesId);
      return;
    }
    final todo = _recurringTodos
        .where((item) => (item.recurrenceSeriesId ?? item.id) == seriesId)
        .firstOrNull;
    setState(() {
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

  Widget _typeCard(
    HabitSourceType type, {
    bool selected = false,
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final (String title, String desc) = switch (type) {
      HabitSourceType.recurringTodo => ('完成型', '每天完成一次，如打卡签到'),
      HabitSourceType.pomodoroTag => ('时长型', '累计专注时长，如阅读 30 分钟'),
      HabitSourceType.quantityCheckIn => ('数量型', '记录累计数量，如饮水量、步数或次数'),
      HabitSourceType.timeCheckIn => ('时间点型', '记录发生时间，如 7 点前起床'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: enabled && selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled
              ? () {
                  setState(() {
                    _sourceType = type;
                    if (type != HabitSourceType.recurringTodo) {
                      _selectedRecurringSeriesId = _autoCreateRecurringSeries;
                    }
                  });
                  _applySleepPairSuggestionIfNeeded();
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled && selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  enabled && selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: enabled && selected
                      ? colorScheme.primary
                      : colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '执行周期',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _periodChip(HabitPeriodType.daily, '每天'),
            _periodChip(HabitPeriodType.weekdays, '工作日'),
            _periodChip(HabitPeriodType.weekly, '每周'),
            _periodChip(HabitPeriodType.monthly, '每月'),
            _periodChip(HabitPeriodType.custom, '自定义'),
          ],
        ),
        if (_periodType == HabitPeriodType.weekdays) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (int i = 0; i < 7; i++)
                ChoiceChip(
                  label: Text('周${'一二三四五六日'[i]}'),
                  selected: (_weekdaysMask & (1 << i)) != 0,
                  onSelected: (on) => setState(() {
                    if (on) {
                      _weekdaysMask |= (1 << i);
                    } else {
                      _weekdaysMask &= ~(1 << i);
                    }
                  }),
                ),
            ],
          ),
        ],
        if (_periodType == HabitPeriodType.custom) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '每 ',
                style: TextStyle(color: colorScheme.onSurface),
              ),
              SizedBox(
                width: 64,
                child: TextFormField(
                  keyboardType: TextInputType.number,
                  initialValue: '$_customIntervalDays',
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) _customIntervalDays = n;
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Text(
                ' 天',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _periodChip(HabitPeriodType type, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _periodType == type,
      onSelected: (_) => setState(() => _periodType = type),
    );
  }

  // ── 第 3 步：目标 ────────────────────────────────────
  Widget _buildTargetStep() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '目标设置',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        switch (_sourceType) {
          HabitSourceType.recurringTodo => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '完成型习惯：每天在待办中完成一次即可。提醒由关联的循环待办触发。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          HabitSourceType.pomodoroTag => _buildDurationTarget(colorScheme),
          HabitSourceType.quantityCheckIn => _buildQuantityTarget(colorScheme),
          HabitSourceType.timeCheckIn => _buildTimeTarget(colorScheme),
        },
        if (widget.goal != null) ...[
          const SizedBox(height: 20),
          Text(
            '规则生效时间',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _effectiveFromChip('today', '从今天开始', '关闭旧规则，新规则从今天生效'),
          _effectiveFromChip(
              'nextPeriod', '从下一个周期开始', '如每周习惯从下周一、每月习惯从下月 1 号开始'),
          _effectiveFromChip('all', '应用到全部历史', '覆盖所有历史版本的目标值（不改变历史打卡记录）'),
        ],
      ],
    );
  }

  Widget _effectiveFromChip(String option, String title, String subtitle) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _effectiveFromOption == option;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _effectiveFromOption = option),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    selected ? colorScheme.primary : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? colorScheme.primary : colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _displayModeChip(
    HabitDisplayMode mode,
    String title,
    String subtitle,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _displayMode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _displayMode = mode),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    selected ? colorScheme.primary : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? colorScheme.primary : colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDurationTarget(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind == HabitAdaptationKind.reading) {
      return _buildReadingTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.learning) {
      return _buildLearningTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.meditation) {
      return _buildMeditationTarget(colorScheme, adaptation);
    }
    return _buildGenericDurationTarget(colorScheme);
  }

  Widget _buildGenericDurationTarget(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '目标时长',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '$_targetMinutes 分钟',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: _targetMinutes.toDouble(),
          min: 5,
          max: 240,
          divisions: 47,
          label: '$_targetMinutes 分钟',
          onChanged: (v) => setState(() => _targetMinutes = v.round()),
        ),
        const SizedBox(height: 18),
        Text(
          '开始专注时的默认时长',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [5, 10, 15, 20, 25, 30, 45, 50, 60].map((minutes) {
            final selected = _defaultFocusMinutes == minutes;
            return ChoiceChip(
              label: Text('$minutes 分钟'),
              selected: selected,
              onSelected: (_) => setState(() => _defaultFocusMinutes = minutes),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          '绑定专注标签（可多选）',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (_tags.isEmpty)
          Text(
            '暂无标签，可先在专注页创建标签后再回来绑定',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) {
              final selected = _selectedTagUuids.contains(tag.uuid);
              return FilterChip(
                avatar: _TagColorDot(color: _parseTagColor(tag.color)),
                label: Text(tag.name),
                selected: selected,
                onSelected: (on) => setState(() {
                  if (on) {
                    _selectedTagUuids.add(tag.uuid);
                  } else {
                    _selectedTagUuids.remove(tag.uuid);
                  }
                }),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        Text(
          '使用番茄钟专注时选择对应的习惯标签，时长将自动累计。',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Color _parseTagColor(String hex) {
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? const Color(0xFF607D8B) : Color(parsed);
  }

  Widget _buildReadingTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    final targetMinutes = _targetMinutes > 0 ? _targetMinutes : 30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: targetMinutes.toDouble(),
          targetUnitOverride: '分钟',
          onTargetSelected: _applyReadingTarget,
        ),
        const SizedBox(height: 14),
        HabitReadingGuide(
          targetMinutes: targetMinutes,
          defaultFocusMinutes: _defaultFocusMinutes,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
        ),
        const SizedBox(height: 14),
        _buildGenericDurationTarget(colorScheme),
      ],
    );
  }

  Widget _buildLearningTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    final targetMinutes = _targetMinutes > 0 ? _targetMinutes : 45;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: targetMinutes.toDouble(),
          targetUnitOverride: '分钟',
          onTargetSelected: _applyLearningTarget,
        ),
        const SizedBox(height: 14),
        HabitLearningGuide(
          targetMinutes: targetMinutes,
          defaultFocusMinutes: _defaultFocusMinutes,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
        ),
        const SizedBox(height: 14),
        _buildGenericDurationTarget(colorScheme),
      ],
    );
  }

  Widget _buildMeditationTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    final targetMinutes = _targetMinutes > 0 ? _targetMinutes : 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: targetMinutes.toDouble(),
          targetUnitOverride: '分钟',
          onTargetSelected: _applyMeditationTarget,
        ),
        const SizedBox(height: 14),
        HabitMeditationGuide(
          targetMinutes: targetMinutes,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
        ),
        const SizedBox(height: 14),
        _buildGenericDurationTarget(colorScheme),
      ],
    );
  }

  Widget _buildQuantityTarget(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind == HabitAdaptationKind.pushUp) {
      return _buildPushUpTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.running) {
      return _buildRunningTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.hydration) {
      return _buildHydrationTarget(colorScheme, adaptation);
    }
    if (adaptation?.kind == HabitAdaptationKind.vocabulary) {
      return _buildVocabularyTarget(colorScheme, adaptation);
    }
    final parsedTarget = double.tryParse(_targetController.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (adaptation != null) ...[
          HabitAdaptationPanel(
            adaptation: adaptation,
            targetValue: parsedTarget,
            onTargetSelected: _applyAdaptationTarget,
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '目标数量',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: '单位（如 ml、个）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '快捷增加（逗号分隔，最多 4 个）',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _quickValuesController,
          onChanged: (v) => _quickValuesText = v,
          decoration: const InputDecoration(
            hintText: '如：250,500',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildHydrationTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    _ensureHydrationDefaults(adaptation);
    final value =
        (int.tryParse(_targetController.text.trim()) ?? 1600).clamp(500, 4000);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          showTargetSuggestions: false,
        ),
        const SizedBox(height: 14),
        HabitWaterTargetPicker(
          value: value,
          onChanged: _applyAdaptationTarget,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '快捷打卡会使用 200 / 300 / 500 ml，方便按杯量快速记录。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVocabularyTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    _ensureVocabularyDefaults(adaptation);
    final parsedTarget = int.tryParse(_targetController.text.trim()) ?? 30;
    final unit = _unitController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: parsedTarget.toDouble(),
          targetUnitOverride: unit,
          onTargetSelected: _applyAdaptationTarget,
        ),
        const SizedBox(height: 14),
        HabitVocabularyGuide(
          targetValue: parsedTarget,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
          unit: unit,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _periodType == HabitPeriodType.weekly
                      ? '每周单词目标'
                      : '每日单词目标',
                  suffixText: unit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: '单位',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '快捷增加（逗号分隔，最多 4 个）',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _quickValuesController,
          onChanged: (v) => _quickValuesText = v,
          decoration: const InputDecoration(
            hintText: '如：10,20,30',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPushUpTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    _ensurePushUpDefaults(adaptation);
    final parsedTarget = int.tryParse(_targetController.text.trim()) ?? 24;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: parsedTarget.toDouble(),
          onTargetSelected: _applyAdaptationTarget,
        ),
        const SizedBox(height: 14),
        HabitPushUpGuide(
          targetValue: parsedTarget,
          periodType: _periodType,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '每次训练目标',
                  suffixText: '个',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: '单位',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '快捷增加（逗号分隔，最多 4 个）',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _quickValuesController,
          onChanged: (v) => _quickValuesText = v,
          decoration: const InputDecoration(
            hintText: '如：8,12,16',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildRunningTarget(
    ColorScheme colorScheme,
    HabitAdaptation? adaptation,
  ) {
    if (adaptation == null) return const SizedBox.shrink();
    _ensureRunningDefaults(adaptation);
    final parsedTarget = int.tryParse(_targetController.text.trim()) ?? 30;
    final unit = _unitController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          targetValue: parsedTarget.toDouble(),
          targetUnitOverride: unit,
          onTargetSelected: _applyAdaptationTarget,
        ),
        const SizedBox(height: 14),
        HabitRunningGuide(
          targetValue: parsedTarget,
          periodType: _periodType,
          weekdaysMask: _weekdaysMask,
          unit: unit,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _periodType == HabitPeriodType.weekly
                      ? '每周运动量'
                      : '每次跑步目标',
                  suffixText: unit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: '单位（建议分钟）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '快捷增加（逗号分隔，最多 4 个）',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _quickValuesController,
          onChanged: (v) => _quickValuesText = v,
          decoration: const InputDecoration(
            hintText: '如：20,30,45',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  void _ensureHydrationDefaults(HabitAdaptation adaptation) {
    if (_targetController.text.trim().isEmpty) {
      _targetController.text = '1600';
    }
    if (_unitController.text.trim().isEmpty) {
      _unitController.text = 'ml';
    }
    if (_quickValuesController.text.trim().isEmpty) {
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    }
  }

  void _ensurePushUpDefaults(HabitAdaptation adaptation) {
    if (_targetController.text.trim().isEmpty) {
      _targetController.text = '24';
    }
    if (_unitController.text.trim().isEmpty) {
      _unitController.text = adaptation.targetUnit;
    }
    if (_quickValuesController.text.trim().isEmpty) {
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    }
  }

  void _ensureRunningDefaults(HabitAdaptation adaptation) {
    if (_targetController.text.trim().isEmpty) {
      _targetController.text = '30';
    }
    if (_unitController.text.trim().isEmpty) {
      _unitController.text = adaptation.targetUnit;
    }
    if (_quickValuesController.text.trim().isEmpty) {
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    }
  }

  void _ensureVocabularyDefaults(HabitAdaptation adaptation) {
    if (_targetController.text.trim().isEmpty) {
      _targetController.text = '30';
    }
    if (_unitController.text.trim().isEmpty) {
      _unitController.text = adaptation.targetUnit;
    }
    if (_quickValuesController.text.trim().isEmpty) {
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    }
  }

  void _applyAdaptationTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation == null) return;
    setState(() {
      _targetController.text = target.toString();
      _unitController.text = adaptation.targetUnit;
      _quickValuesText = adaptation.suggestedQuickValues.join(',');
      _quickValuesController.text = _quickValuesText;
    });
  }

  void _applyReadingTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind != HabitAdaptationKind.reading) return;
    setState(() {
      _targetMinutes = target;
      if (_defaultFocusMinutes == null || _defaultFocusMinutes! > target) {
        _defaultFocusMinutes = target >= 25 ? 25 : target;
      }
    });
  }

  void _applyLearningTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind != HabitAdaptationKind.learning) return;
    setState(() {
      _targetMinutes = target;
      if (_defaultFocusMinutes == null || _defaultFocusMinutes! > target) {
        _defaultFocusMinutes = target >= 25 ? 25 : target;
      }
    });
  }

  void _applyMeditationTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation?.kind != HabitAdaptationKind.meditation) return;
    setState(() {
      _targetMinutes = target;
      if (_defaultFocusMinutes == null || _defaultFocusMinutes! > target) {
        _defaultFocusMinutes = target >= 10 ? 10 : target;
      }
    });
  }

  void _applyTimeAdaptationTarget(int target) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    if (adaptation == null) return;
    setState(() {
      _targetTime = TimeOfDay(hour: (target ~/ 60) % 24, minute: target % 60);
      _timeTargetCustomized = true;
      _timeComparison = HabitTimeComparison.before;
      if (adaptation.kind == HabitAdaptationKind.earlySleep) {
        _crossMidnightBoundary = true;
      }
    });
  }

  void _applyTimePairSuggestion(int target) {
    setState(() {
      _targetTime = TimeOfDay(hour: (target ~/ 60) % 24, minute: target % 60);
      _timeTargetCustomized = true;
      _timeComparison = HabitTimeComparison.before;
      _toleranceMinutes = 15;
      final adaptation = HabitAdaptationService.forDraft(
        sourceType: _sourceType,
        name: _nameController.text,
      );
      _crossMidnightBoundary =
          adaptation?.kind == HabitAdaptationKind.earlySleep;
      _reminderEnabled = true;
      _nearEndReminder = true;
    });
  }

  Widget _buildTimeTarget(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    final isSleepAdaptation =
        adaptation?.kind == HabitAdaptationKind.earlyWake ||
            adaptation?.kind == HabitAdaptationKind.earlySleep;
    final pairSuggestion =
        widget.goal == null ? _sleepPairSuggestionFor(adaptation) : null;
    final timeText = '${_targetTime.hour.toString().padLeft(2, '0')}:'
        '${_targetTime.minute.toString().padLeft(2, '0')}';
    final beforeLabel = isSleepAdaptation ? '不晚于 $timeText' : '早于 $timeText';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (adaptation != null && isSleepAdaptation) ...[
          HabitAdaptationPanel(
            adaptation: adaptation,
            targetValue:
                (_targetTime.hour * 60 + _targetTime.minute).toDouble(),
            onTargetSelected: _applyTimeAdaptationTarget,
          ),
          const SizedBox(height: 14),
          if (pairSuggestion != null) ...[
            HabitSleepPairSuggestionCard(
              suggestion: pairSuggestion,
              currentTargetMinute: _targetTime.hour * 60 + _targetTime.minute,
              onApply: _applyTimePairSuggestion,
            ),
            const SizedBox(height: 14),
          ],
          HabitSleepTimingGuide(
            adaptation: adaptation,
            targetMinute: _targetTime.hour * 60 + _targetTime.minute,
            onTargetChanged: _applyTimeAdaptationTarget,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                adaptation?.kind == HabitAdaptationKind.earlyWake
                    ? '目标起床时间'
                    : adaptation?.kind == HabitAdaptationKind.earlySleep
                        ? '目标入睡时间'
                        : '目标时间',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _targetTime,
                );
                if (picked != null && mounted) {
                  setState(() {
                    _targetTime = picked;
                    _timeTargetCustomized = true;
                    if (adaptation?.kind == HabitAdaptationKind.earlySleep) {
                      _crossMidnightBoundary = true;
                    }
                  });
                }
              },
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(timeText),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          isSleepAdaptation ? '达标条件（建议使用截止时间）' : '达标条件',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: Text(beforeLabel),
              selected: _timeComparison == HabitTimeComparison.before,
              onSelected: (_) =>
                  setState(() => _timeComparison = HabitTimeComparison.before),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('晚于 $timeText'),
              selected: _timeComparison == HabitTimeComparison.after,
              onSelected: (_) =>
                  setState(() => _timeComparison = HabitTimeComparison.after),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '允许偏差',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextFormField(
                keyboardType: TextInputType.number,
                initialValue: '$_toleranceMinutes',
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n >= 0) _toleranceMinutes = n;
                },
                decoration: const InputDecoration(
                  suffixText: '分钟',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (isSleepAdaptation) ...[
          const SizedBox(height: 8),
          Text(
            '建议先从 15 分钟宽容窗口开始，避免把偶尔的晚睡或晚起直接判定为失败。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [0, 15, 30].map((minutes) {
              return ChoiceChip(
                label: Text('$minutes 分钟'),
                selected: _toleranceMinutes == minutes,
                onSelected: (_) => setState(() => _toleranceMinutes = minutes),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('跨午夜习惯（04:00 前算当天）'),
          subtitle: const Text('如早睡：晚上 11 点半打卡，次日 4 点前仍算当天'),
          value: _crossMidnightBoundary,
          onChanged: (v) => setState(() => _crossMidnightBoundary = v),
        ),
      ],
    );
  }

  Widget _buildRecurringTodoBinding(ColorScheme colorScheme) {
    final selectedExists = _recurringTodos.any(
      (todo) =>
          (todo.recurrenceSeriesId ?? todo.id) == _selectedRecurringSeriesId,
    );
    final selectedValue = selectedExists
        ? _selectedRecurringSeriesId
        : _autoCreateRecurringSeries;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联循环待办',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '完成型的进度和提醒都来自这条循环待办。',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(selectedValue),
            initialValue: selectedValue,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: _autoCreateRecurringSeries,
                child: Text('自动创建新的循环待办'),
              ),
              ..._recurringTodos.map((todo) {
                final seriesId = todo.recurrenceSeriesId ?? todo.id;
                return DropdownMenuItem(
                  value: seriesId,
                  child: Text(
                    todo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (value) {
              if (value == null) return;
              _selectRecurringTodo(value);
            },
          ),
          if (selectedValue == _autoCreateRecurringSeries) ...[
            const SizedBox(height: 6),
            Text(
              _recurringTodos.isEmpty
                  ? '未找到可用的循环待办，保存后会自动创建并绑定。'
                  : '未选择已有待办，保存后会自动创建并绑定。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDisplayModeSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '首页展示位置',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _displayModeChip(HabitDisplayMode.habitOnly, '仅习惯', '只在首页习惯卡片展示'),
        _displayModeChip(HabitDisplayMode.todoOnly, '仅待办', '只按普通循环待办展示'),
        _displayModeChip(HabitDisplayMode.both, '同时展示', '习惯与待办都显示'),
      ],
    );
  }

  // ── 第 4 步：提醒 ────────────────────────────────────
  Widget _buildReminderStep() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_sourceType == HabitSourceType.timeCheckIn) {
      return _buildTimePointReminderStep(colorScheme);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用提醒'),
          value: _reminderEnabled,
          onChanged: (v) => setState(() => _reminderEnabled = v),
        ),
        if (_reminderEnabled) ...[
          Text(
            '固定时间提醒',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final time in _fixedTimes)
                InputChip(
                  label: Text(
                    '${time.hour.toString().padLeft(2, '0')}:'
                    '${time.minute.toString().padLeft(2, '0')}',
                  ),
                  onDeleted: () => setState(() => _fixedTimes.remove(time)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: const Text('添加'),
                onPressed: () async {
                  if (_fixedTimes.length >= 3) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('最多添加 3 个提醒时间')),
                    );
                    return;
                  }
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 20, minute: 0),
                  );
                  if (picked != null && mounted) {
                    setState(() => _fixedTimes.add(picked));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('进度提醒'),
            subtitle: const Text('完成 50% / 100% 时提醒'),
            value: _progressReminder,
            onChanged: (v) => setState(() => _progressReminder = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('临近结束提醒'),
            subtitle: const Text('周期快结束时提醒未完成'),
            value: _nearEndReminder,
            onChanged: (v) => setState(() => _nearEndReminder = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('当日汇总'),
            subtitle: const Text('每晚汇总当天习惯完成情况'),
            value: _dailySummaryReminder,
            onChanged: (v) => setState(() => _dailySummaryReminder = v),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '提醒设置会保存，并在保存后重新安排通知。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTimePointReminderStep(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forDraft(
      sourceType: _sourceType,
      name: _nameController.text,
    );
    final title = adaptation?.kind == HabitAdaptationKind.earlySleep
        ? '启用早睡提醒'
        : adaptation?.kind == HabitAdaptationKind.earlyWake
            ? '启用早起提醒'
            : '启用目标提醒';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: const Text('目标前 30 分钟和 5 分钟各提醒一次'),
          value: _nearEndReminder,
          onChanged: (v) => setState(() {
            _reminderEnabled = v;
            _nearEndReminder = v;
          }),
        ),
        if (_reminderEnabled)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '提醒会围绕目标时间安排，不需要额外添加固定时间。${adaptation?.kind == HabitAdaptationKind.earlySleep ? '早睡习惯还会按跨午夜规则归属到前一天。' : ''}',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('当日汇总'),
          subtitle: const Text('每晚汇总当天习惯完成情况'),
          value: _dailySummaryReminder,
          onChanged: (v) => setState(() => _dailySummaryReminder = v),
        ),
        Text(
          '提醒是辅助，不代表需要为了赶上目标而牺牲睡眠时长。',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TagColorDot extends StatelessWidget {
  final Color color;

  const _TagColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SleepPairAnchor {
  final String name;
  final HabitAdaptationKind kind;
  final int targetMinute;
  final int updatedAt;

  const _SleepPairAnchor({
    required this.name,
    required this.kind,
    required this.targetMinute,
    required this.updatedAt,
  });
}

enum _HabitCreationMode { template, custom }

class _HabitTemplate {
  final String name;
  final String icon;
  final HabitSourceType type;
  final double targetValue;
  final String unit;
  final List<int> quickValues;
  final int targetTimeMinute;
  final bool crossMidnight;
  final HabitAdaptationKind? adaptationKind;

  const _HabitTemplate(
    this.name,
    this.icon,
    this.type, {
    this.targetValue = 0,
    this.unit = '',
    this.quickValues = const [],
    this.targetTimeMinute = 0,
    this.crossMidnight = false,
    this.adaptationKind,
  });
}
