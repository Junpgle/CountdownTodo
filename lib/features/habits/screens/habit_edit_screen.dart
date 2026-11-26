import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models.dart';
import '../../../services/pomodoro_service.dart';
import '../../../storage_service.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_drink_log_service.dart';
import '../services/habit_reminder_service.dart';
import '../services/habit_rule_resolver.dart';
import '../widgets/habit_adaptation_panel.dart';
import '../widgets/habit_emoji_picker_dialog.dart';
import '../widgets/habit_water_target_picker.dart';
import '../../../widgets/floating_glass_control.dart';
import '../../../utils/app_color_utils.dart';
import '../../../utils/app_dialogs.dart';

part 'parts/habit_edit_actions.dart';
part 'parts/habit_edit_creation_and_type_steps.dart';
part 'parts/habit_edit_target_step.dart';
part 'parts/habit_edit_reminder_and_models.dart';

const String _autoCreateRecurringSeries = '__auto_create_recurring__';

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
  List<TodoItem> _recurringTodos = [];
  String _selectedRecurringSeriesId = _autoCreateRecurringSeries;

  bool _reminderEnabled = false;
  final List<TimeOfDay> _fixedTimes = [];
  bool _progressReminder = false;
  bool _nearEndReminder = false;
  bool _dailySummaryReminder = false;

  /// 时长型：开始专注时的默认时长（分钟），为空使用专注设置默认值。
  int? _defaultFocusMinutes;

  /// 今日容量与规划块联动配置。
  bool _includeInPlanning = false;
  TimeOfDay _preferredStartTime = const TimeOfDay(hour: 20, minute: 0);
  int _plannedDurationMinutes = 25;
  List<String> _focusTagUuids = [];
  bool _autoCheckInOnFocus = true;

  /// 编辑模式：规则生效时间（'today' | 'nextPeriod' | 'all'）。
  String _effectiveFromOption = 'today';

  bool _saving = false;

  void _mutateState(VoidCallback fn) => setState(fn);

  /// 深度适配模板优先展示，普通模板保持原有相对顺序。
  List<_HabitTemplate> get _orderedTemplates {
    final adapted = <_HabitTemplate>[];
    final standard = <_HabitTemplate>[];
    for (final template in _templates) {
      final hasAdaptation =
          template.adaptationKind != null ||
          HabitAdaptationService.forDraft(
                sourceType: template.type,
                name: template.name,
              ) !=
              null ||
          HabitDrinkLogService.isDrinkChoiceName(template.name);
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
      final rule =
          allRules
              .where((r) => r.uuid == goal.currentRuleUuid && !r.isDeleted)
              .firstOrNull ??
          HabitRuleResolver.currentRule(
            allRules,
            HabitRuleResolver.defaultDayBoundaryMinute,
            null,
          );
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
          case HabitSourceType.durationCheckIn:
            _targetMinutes = (rule.targetValue / 60).round().clamp(60, 960);
          case HabitSourceType.recurringTodo:
            break;
        }
        _crossMidnightBoundary = rule.dayBoundaryMinute > 0;
        _reminderEnabled =
            rule.reminderPolicy.fixedTimes.isNotEmpty ||
            rule.reminderPolicy.progressReminder ||
            rule.reminderPolicy.nearEndReminder ||
            rule.reminderPolicy.dailySummaryReminder;
        _fixedTimes
          ..clear()
          ..addAll(fixedTimes);
        _progressReminder = rule.reminderPolicy.progressReminder;
        _nearEndReminder = rule.reminderPolicy.nearEndReminder;
        _dailySummaryReminder = rule.reminderPolicy.dailySummaryReminder;
        _includeInPlanning = rule.reminderPolicy.includeInPlanning;
        final preferredStart = rule.reminderPolicy.preferredStartMinute;
        if (preferredStart != null) {
          _preferredStartTime = TimeOfDay(
            hour: (preferredStart ~/ 60) % 24,
            minute: preferredStart % 60,
          );
        } else if (fixedTimes.isNotEmpty) {
          _preferredStartTime = fixedTimes.first;
        }
        _plannedDurationMinutes =
            (rule.reminderPolicy.plannedDurationMinutes ??
                    goal.defaultFocusMinutes ??
                    25)
                .clamp(5, 240);
        _focusTagUuids = List<String>.from(rule.reminderPolicy.focusTagUuids);
        _autoCheckInOnFocus = rule.reminderPolicy.autoCheckInOnFocus;
      });
    } catch (e) {
      // 加载失败不阻塞编辑；保存时仍会基于当前输入生成规则。
      debugPrint('⚠️ 编辑习惯加载规则失败: $e');
    }
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
        final rule =
            rules
                .where(
                  (candidate) =>
                      candidate.uuid == goal.currentRuleUuid &&
                      !candidate.isDeleted,
                )
                .firstOrNull ??
            HabitRuleResolver.currentRule(
              rules,
              HabitRuleResolver.defaultDayBoundaryMinute,
              null,
            );
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final useFloatingBottomBar = floatingBottomBarShouldFloat(context);
        final topBarHeight = floatingGlassTopBarHeight(context);
        final content = switch (_step) {
          0 => _buildCreationStep(),
          1 => _buildTypeStep(),
          2 => _buildTargetStep(),
          _ => _buildReminderStep(),
        };

        final formArea = AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            final slidePosition = Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(animation);
            return AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) {
                if (animation.value <= 0.001) {
                  return const SizedBox.shrink();
                }
                if (animation.value >= 0.999) {
                  return child!;
                }
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slidePosition, child: child),
                );
              },
            );
          },
          child: KeyedSubtree(key: ValueKey<int>(_step), child: content),
        );

        if (isWide) {
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: Text(widget.goal == null ? '新建习惯' : '编辑习惯'),
              centerTitle: false,
            ),
            body: FloatingGlassTopBarContentFade(
              topBarHeight: topBarHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: Padding(
                      padding: EdgeInsets.only(top: topBarHeight),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              '设置进度',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(child: _buildWideStepIndicator()),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              40,
                              topBarHeight + 24,
                              40,
                              24,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 600,
                                ),
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
            ),
          );
        }

        return Scaffold(
          extendBody: useFloatingBottomBar,
          extendBodyBehindAppBar: true,
          appBar: FloatingGlassAppBar(
            flexibleSpace: const FloatingGlassTopBarBackground(),
            title: Text(widget.goal == null ? '新建习惯' : '编辑习惯'),
            centerTitle: true,
          ),
          bottomNavigationBar: _buildBottomBar(isWide: false),
          body: FloatingGlassTopBarContentFade(
            topBarHeight: topBarHeight,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: topBarHeight),
                  child: _buildStepIndicator(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    child: formArea,
                  ),
                ),
              ],
            ),
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
                                color: colorScheme.primary.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: isDone
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: colorScheme.onPrimary,
                          )
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: isActive
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
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
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                '${current + 1} / ${steps.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
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
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final useFloating = !isWide && floatingBottomBarShouldFloat(context);

    final child = Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        useFloating
            ? 12
            : (isWide ? 12 : (bottomPadding > 0 ? bottomPadding : 12)),
      ),
      decoration: useFloating
          ? null
          : BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.8),
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
      child: Row(
        mainAxisSize: useFloating ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (_step > 0) ...[
            OutlinedButton.icon(
              onPressed: _saving ? null : () => setState(() => _step--),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('上一步'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (useFloating) const SizedBox(width: 12),
          ],
          if (!useFloating) const Spacer(),
          if (_step < lastStep)
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () {
                      final error = _validateStep(_step);
                      if (error != null) {
                        AppSnackBars.showSnackBar(
                          context,
                          SnackBar(
                            content: Text(error),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      setState(() => _step++);
                    },
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('下一步'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_saving ? '保存中…' : '完成'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );

    final control = FloatingGlassControl(
      height: useFloating ? null : 88,
      margin: useFloating
          ? const EdgeInsets.fromLTRB(16, 8, 16, 12)
          : EdgeInsets.zero,
      borderRadius: useFloating ? 28 : 0,
      mobilePortraitOnly: true,
      child: child,
    );

    return useFloating
        ? SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.centerRight,
              heightFactor: 1.0,
              child: control,
            ),
          )
        : control;
  }
}
