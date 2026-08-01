import 'package:flutter/material.dart';

import '../../../services/pomodoro_service.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_rule_resolver.dart';

/// 新建 / 编辑习惯。
///
/// 流程：模板（基本信息）→ 类型（含周期）→ 目标 → 提醒。
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
  HabitTimeComparison _timeComparison = HabitTimeComparison.before;
  int _toleranceMinutes = 0;
  bool _crossMidnightBoundary = false;

  // 时长型：绑定专注标签（可多选，sourceIds 存标签 UUID）。
  List<PomodoroTag> _tags = [];
  List<String> _selectedTagUuids = [];

  bool _reminderEnabled = false;
  final List<TimeOfDay> _fixedTimes = [];
  bool _progressReminder = false;
  bool _nearEndReminder = false;
  bool _dailySummaryReminder = false;

  /// 时长型：开始专注时的默认时长（分钟），为空使用专注设置默认值。
  int? _defaultFocusMinutes;

  bool _saving = false;

  static const _icons = [
    '🎯',
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
        targetValue: 2000, unit: 'ml', quickValues: [250, 500]),
    _HabitTemplate('早起', '🌅', HabitSourceType.timeCheckIn,
        targetTimeMinute: 7 * 60),
    _HabitTemplate('早睡', '🌙', HabitSourceType.timeCheckIn,
        targetTimeMinute: 23 * 60 + 30, crossMidnight: true),
    _HabitTemplate('俯卧撑', '💪', HabitSourceType.quantityCheckIn,
        targetValue: 50, unit: '个', quickValues: [10, 20]),
    _HabitTemplate('阅读', '📖', HabitSourceType.pomodoroTag,
        targetValue: 30 * 60),
    _HabitTemplate('运动', '🏃', HabitSourceType.pomodoroTag,
        targetValue: 30 * 60),
    _HabitTemplate('学习', '📚', HabitSourceType.pomodoroTag,
        targetValue: 60 * 60),
    _HabitTemplate('冥想', '🧘', HabitSourceType.pomodoroTag,
        targetValue: 10 * 60),
    _HabitTemplate('维生素', '💊', HabitSourceType.quantityCheckIn,
        targetValue: 1, unit: '粒', quickValues: [1]),
    _HabitTemplate('整理', '🧹', HabitSourceType.quantityCheckIn,
        targetValue: 1, unit: '次', quickValues: [1]),
    _HabitTemplate('单词', '🔤', HabitSourceType.quantityCheckIn,
        targetValue: 30, unit: '个', quickValues: [10, 20]),
    _HabitTemplate('跑步', '🏃', HabitSourceType.quantityCheckIn,
        targetValue: 3, unit: '公里', quickValues: [1, 2]),
  ];

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
      _defaultFocusMinutes = goal.defaultFocusMinutes;
      _step = 1;
      _loadRuleForEdit(goal);
    }
    _loadTags();
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
    setState(() {
      _nameController.text = template.name;
      _icon = template.icon;
      _sourceType = template.type;
      _periodType = HabitPeriodType.daily;
      _weekdaysMask = 127;
      _crossMidnightBoundary = template.crossMidnight;
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
  }

  // ── 校验 ────────────────────────────────────────────
  /// 校验当前步骤，返回错误文案（null 表示通过）。
  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_nameController.text.trim().isEmpty) {
          return '请填写习惯名称';
        }
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
    for (int i = 0; i < 3; i++) {
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
      if (goal == null) {
        await HabitRepository.createGoal(
          name: _nameController.text.trim(),
          icon: _icon,
          sourceType: _sourceType,
          sourceIds: _selectedTagUuids,
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
        }
        final allRules = await HabitRepository.getRules(habitUuid: goal.uuid);
        await HabitRepository.updateGoal(goal);
        await HabitRepository.updateRule(
          goal: goal,
          updatedRule: rule,
          effectiveFromOption: 'today',
          allRules: allRules,
        );
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.goal == null ? '新建习惯' : '编辑习惯'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                0 => _buildTemplateStep(),
                1 => _buildTypeStep(),
                2 => _buildTargetStep(),
                _ => _buildReminderStep(),
              },
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ── 步骤指示器 ──────────────────────────────────────
  Widget _buildStepIndicator() {
    const labels = ['模板', '类型', '目标', '提醒'];
    final colorScheme = Theme.of(context).colorScheme;
    final isEdit = widget.goal != null;
    final steps = isEdit ? ['类型', '目标', '提醒'] : labels;
    final current = isEdit ? _step - 1 : _step;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i <= current
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i <= current
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: i < current
                      ? Icon(Icons.check_rounded,
                          size: 16, color: colorScheme.onPrimary)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i <= current
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        i == current ? FontWeight.w700 : FontWeight.w400,
                    color: i <= current
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final isEdit = widget.goal != null;
    final lastStep = isEdit ? 2 : 3;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            if (_step > (isEdit ? 1 : 0))
              OutlinedButton(
                onPressed: _saving ? null : () => setState(() => _step--),
                child: const Text('上一步'),
              ),
            const Spacer(),
            if (_step < lastStep)
              FilledButton(
                onPressed: _saving
                    ? null
                    : () {
                        final error = _validateStep(_step);
                        if (error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error)),
                          );
                          return;
                        }
                        setState(() => _step++);
                      },
                child: const Text('下一步'),
              )
            else
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_saving ? '保存中…' : '保存'),
              ),
          ],
        ),
      ),
    );
  }

  // ── 第 1 步：模板 ────────────────────────────────────
  Widget _buildTemplateStep() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '习惯名称',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                maxLength: 20,
                decoration: const InputDecoration(
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
        const SizedBox(height: 20),
        Text(
          '或选择一个模板',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        // 固定宽度网格，避免宽屏下被拉伸成奇怪的横向卡片。
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _templates
                .map(
                  (t) => SizedBox(
                    width: 104,
                    child: InkWell(
                      onTap: () => _applyTemplate(t),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 76,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(t.icon, style: const TextStyle(fontSize: 24)),
                            const SizedBox(height: 6),
                            Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
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

  // ── 第 2 步：类型 ────────────────────────────────────
  Widget _buildTypeStep() {
    final isEdit = widget.goal != null;

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
      ],
    );
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
      HabitSourceType.quantityCheckIn => ('数量型', '记录累计数量，如喝水 2000ml'),
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
          onTap: enabled ? () => setState(() => _sourceType = type) : null,
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
                    '完成型习惯：每天在待办中完成一次即可。创建后将自动生成循环待办。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '首页展示位置',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                _displayModeChip(
                    HabitDisplayMode.habitOnly, '仅习惯', '只在家页习惯卡片展示'),
                _displayModeChip(
                    HabitDisplayMode.todoOnly, '仅待办', '只按普通循环待办展示'),
                _displayModeChip(HabitDisplayMode.both, '同时展示', '习惯与待办都显示'),
              ],
            ),
          HabitSourceType.pomodoroTag => _buildDurationTarget(colorScheme),
          HabitSourceType.quantityCheckIn => _buildQuantityTarget(colorScheme),
          HabitSourceType.timeCheckIn => _buildTimeTarget(colorScheme),
        },
      ],
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
          children: [25, 30, 45, 50, 60].map((minutes) {
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

  Widget _buildQuantityTarget(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  Widget _buildTimeTarget(ColorScheme colorScheme) {
    final timeText = '${_targetTime.hour.toString().padLeft(2, '0')}:'
        '${_targetTime.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '目标时间',
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
                  setState(() => _targetTime = picked);
                }
              },
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(timeText),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '达标条件',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: Text('早于 $timeText'),
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

  // ── 第 4 步：提醒 ────────────────────────────────────
  Widget _buildReminderStep() {
    final colorScheme = Theme.of(context).colorScheme;
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
              // TODO(PR4): 提醒调度与推送，当前仅保存配置。
              '提醒推送将在后续版本上线，当前仅保存配置。',
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

class _HabitTemplate {
  final String name;
  final String icon;
  final HabitSourceType type;
  final double targetValue;
  final String unit;
  final List<int> quickValues;
  final int targetTimeMinute;
  final bool crossMidnight;

  const _HabitTemplate(
    this.name,
    this.icon,
    this.type, {
    this.targetValue = 0,
    this.unit = '',
    this.quickValues = const [],
    this.targetTimeMinute = 0,
    this.crossMidnight = false,
  });
}
