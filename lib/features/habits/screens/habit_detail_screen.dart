import 'package:flutter/material.dart';

import '../../../models.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_progress_calculator.dart';
import '../services/habit_rule_resolver.dart';
import '../services/habit_source_resolver.dart';
import '../services/habit_streak_service.dart';
import '../widgets/habit_card.dart';
import '../widgets/habit_checkin_editor.dart';
import '../widgets/habit_format.dart';
import '../widgets/habit_adaptation_panel.dart';
import '../widgets/habit_time_point_chart.dart';
import '../widgets/habit_water_progress_card.dart';
import '../../../screens/pomodoro_screen.dart';
import '../../../services/pomodoro_control_service.dart';
import '../../../services/pomodoro_service.dart';
import '../../../storage_service.dart';
import '../../../utils/page_transitions.dart';
import 'habit_edit_screen.dart';
import 'habit_history_screen.dart';
import '../services/habit_sleep_log_migration_service.dart';
import '../services/habit_sleep_duration_service.dart';

/// 习惯详情：今日进度 + 今日打卡记录 + 目标信息 + 管理操作。
///
/// 有变更时 pop(true)，由调用方触发刷新。
class HabitDetailScreen extends StatefulWidget {
  final HabitGoal goal;
  final String username;

  const HabitDetailScreen({
    super.key,
    required this.goal,
    this.username = '',
  });

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  late HabitGoal _goal;
  final GlobalKey _detailCardKey = GlobalKey();
  final GlobalKey _menuActionKey = GlobalKey();
  List<HabitGoalRuleRevision> _rules = [];
  HabitProgress? _todayProgress;
  HabitStreakSummary? _summary;
  List<HabitCheckIn> _todayCheckIns = [];
  List<PomodoroRecord> _todayFocusRecords = [];
  List<HabitDayProgress> _timeTrend = [];
  int _timeTrendRangeDays = 7;
  HabitTimeLogImportPreview? _timeLogImportPreview;
  HabitTimeLogImportPart? _timeLogImportPart;
  bool _loading = true;

  bool get _isSleepDuration =>
      HabitSleepDurationService.isSleepDurationGoal(_goal);

  String get _displayPeriodLabel => _isSleepDuration ? '前一晚' : '今日';

  @override
  void initState() {
    super.initState();
    _goal = widget.goal;
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    if (HabitSleepDurationService.isSleepDurationGoal(_goal)) {
      await HabitSleepDurationService.syncAll();
    }
    final rules = await HabitRepository.getRules(habitUuid: _goal.uuid);
    final today = DateTime.now();
    final displayDate =
        HabitSleepDurationService.displayLogicalDateFor(_goal, today);
    final progress = rules.isEmpty
        ? null
        : await HabitProgressCalculator.computePeriod(
            habit: _goal,
            rules: rules,
            logicalDate: displayDate,
          );
    final summary = rules.isEmpty
        ? null
        : await HabitStreakService.summarize(habit: _goal, rules: rules);
    final checkIns = progress?.checkIns ?? const <HabitCheckIn>[];
    final todayDate = DateTime(today.year, today.month, today.day);
    final timeTrend =
        _goal.sourceType == HabitSourceType.timeCheckIn && rules.isNotEmpty
            ? await HabitProgressCalculator.computeRange(
                habit: _goal,
                rules: rules,
                from: todayDate.subtract(const Duration(days: 29)),
                to: todayDate,
              )
            : const <HabitDayProgress>[];
    // 时长型：今日专注记录（按绑定标签过滤）。
    final focusRecords = _goal.sourceType == HabitSourceType.pomodoroTag
        ? await HabitSourceResolver.recordsForTags(
            tagUuids: _goal.sourceIds,
            from: DateTime(today.year, today.month, today.day),
            to: DateTime(today.year, today.month, today.day)
                .add(const Duration(days: 1)),
          )
        : const <PomodoroRecord>[];

    if (mounted) {
      setState(() {
        _rules = rules;
        _todayProgress = progress;
        _summary = summary;
        _todayCheckIns = checkIns;
        _todayFocusRecords = focusRecords;
        _timeTrend = timeTrend;
        _loading = false;
      });
    }
    _loadTimeLogImportPreview();
  }

  Future<void> _loadTimeLogImportPreview() async {
    final adaptation = HabitAdaptationService.forHabit(_goal);
    final part = switch (adaptation?.kind) {
      HabitAdaptationKind.earlySleep => HabitTimeLogImportPart.bedtime,
      HabitAdaptationKind.earlyWake => HabitTimeLogImportPart.wakeTime,
      _ => null,
    };
    if (part == null) {
      if (mounted) {
        setState(() {
          _timeLogImportPreview = null;
          _timeLogImportPart = null;
        });
      }
      return;
    }
    try {
      final results = await Future.wait<dynamic>([
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getTags(),
      ]);
      final tags = results[1] as List<PomodoroTag>;
      final preview = await HabitSleepLogMigrationService.buildImportPreview(
        goal: _goal,
        logs: results[0] as List<TimeLogItem>,
        tagNames: {for (final tag in tags) tag.uuid: tag.name},
        part: part,
      );
      if (!mounted) return;
      setState(() {
        _timeLogImportPreview = preview;
        _timeLogImportPart = part;
      });
    } catch (_) {
      // 导入入口属于增强体验，读取失败不影响习惯详情的正常展示。
    }
  }

  HabitGoalRuleRevision get _rule {
    final rule = HabitRuleResolver.effectiveRule(
      _rules,
      HabitSleepDurationService.displayLogicalDateFor(_goal, DateTime.now()),
    );
    return rule ??
        HabitGoalRuleRevision(
          habitUuid: _goal.uuid,
          effectiveFromDate: '',
          periodType: HabitPeriodType.daily,
        );
  }

  Future<void> _editHabit() async {
    final changed = await PageTransitions.pushFromRect(
      context: context,
      page: HabitEditScreen(goal: _goal),
      sourceKey: _menuActionKey,
      sourceBorderRadius: BorderRadius.circular(20),
    );
    if (changed == true && mounted) {
      _loadData();
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openHistory({GlobalKey? sourceKey}) async {
    await PageTransitions.pushFromRect(
      context: context,
      page: HabitHistoryScreen(goal: _goal, username: widget.username),
      sourceKey: sourceKey ?? _menuActionKey,
      sourceBorderRadius: BorderRadius.circular(16),
    );
    if (mounted) _loadData();
  }

  Future<void> _toggleArchive() async {
    await HabitRepository.setArchived(_goal, !_goal.isArchived);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _deleteHabit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除习惯'),
        content: Text('确定删除「${_goal.name}」吗？历史记录将保留但不再展示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await HabitRepository.deleteGoal(_goal);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_goal.name),
        centerTitle: false,
        actions: [
          PopupMenuButton<String>(
            key: _menuActionKey,
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _editHabit();
                case 'history':
                  _openHistory();
                case 'archive':
                  _toggleArchive();
                case 'delete':
                  _deleteHabit();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑习惯')),
              const PopupMenuItem(value: 'history', child: Text('历史记录')),
              PopupMenuItem(
                value: 'archive',
                child: Text(_goal.isArchived ? '取消归档' : '归档习惯'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('删除习惯')),
            ],
          ),
        ],
      ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final maxWidth = isWide ? 1200.0 : 840.0;
        final horizontalPadding = isWide ? 28.0 : 16.0;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                32,
              ),
              children: [
                _buildHeader(colorScheme),
                const SizedBox(height: 16),
                isWide
                    ? _buildWideSections(colorScheme)
                    : _buildNarrowSections(colorScheme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNarrowSections(ColorScheme colorScheme) {
    final children = <Widget>[];

    void addSection(Widget section, {double gap = 20}) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: gap));
      }
      children.add(section);
    }

    if (_timeLogImportPreview?.hasPendingLogs == true) {
      addSection(_buildTimeLogImportSection(colorScheme), gap: 0);
    }
    if (_todayProgress != null) {
      addSection(_buildTodayCard(colorScheme), gap: 0);
    }
    if (HabitAdaptationService.forHabit(_goal) != null) {
      addSection(_buildAdaptationSection(colorScheme), gap: 16);
    }
    if (_todayCheckIns.isNotEmpty) {
      addSection(_buildRecordSection(colorScheme));
    }
    if (_todayFocusRecords.isNotEmpty) {
      addSection(_buildFocusRecordSection(colorScheme));
    }
    if (_goal.sourceType == HabitSourceType.timeCheckIn &&
        (_summary != null || _timeTrend.isNotEmpty)) {
      addSection(_buildTimePointSection(colorScheme));
    }
    addSection(_buildRuleSection(colorScheme));
    if (_summary != null && _goal.sourceType != HabitSourceType.timeCheckIn) {
      addSection(
        (_goal.sourceType == HabitSourceType.pomodoroTag ||
                _goal.sourceType == HabitSourceType.durationCheckIn)
            ? _buildDurationSummarySection(colorScheme)
            : _buildSummarySection(colorScheme),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildWideSections(ColorScheme colorScheme) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: _buildSectionColumn(_buildPrimarySections(colorScheme)),
          ),
          const SizedBox(width: 24),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 2,
            child: _buildSectionColumn(_buildInsightSections(colorScheme)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionColumn(List<Widget> sections) {
    if (sections.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var index = 0; index < sections.length; index++) {
      if (index > 0) children.add(const SizedBox(height: 20));
      children.add(sections[index]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Widget> _buildPrimarySections(ColorScheme colorScheme) {
    return [
      if (_timeLogImportPreview?.hasPendingLogs == true)
        _buildTimeLogImportSection(colorScheme),
      if (_todayProgress != null) _buildTodayCard(colorScheme),
      if (HabitAdaptationService.forHabit(_goal) != null)
        _buildAdaptationSection(colorScheme),
      if (_todayCheckIns.isNotEmpty) _buildRecordSection(colorScheme),
      if (_todayFocusRecords.isNotEmpty) _buildFocusRecordSection(colorScheme),
    ];
  }

  Widget _buildTimeLogImportSection(ColorScheme colorScheme) {
    final preview = _timeLogImportPreview!;
    final isBedtime = _timeLogImportPart == HabitTimeLogImportPart.bedtime;
    final habitLabel = isBedtime ? '早睡' : '早起';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.history_rounded, color: colorScheme.onSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现历史睡眠日志',
                  style: TextStyle(
                    color: colorScheme.onSecondaryContainer,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '有 ${preview.pendingLogs.length} 条记录可以导入到这个$habitLabel习惯的历史打卡中。',
                  style: TextStyle(
                    color: colorScheme.onSecondaryContainer
                        .withValues(alpha: 0.78),
                    fontSize: 12.5,
                  ),
                ),
                if (preview.alreadyImportedCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '已导入 ${preview.alreadyImportedCount} 条，重复导入不会新增记录。',
                    style: TextStyle(
                      color: colorScheme.onSecondaryContainer
                          .withValues(alpha: 0.68),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: _openTimeLogImport,
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTimeLogImport() async {
    final preview = _timeLogImportPreview;
    final part = _timeLogImportPart;
    if (preview == null || part == null || !preview.hasPendingLogs) return;
    final isBedtime = part == HabitTimeLogImportPart.bedtime;
    final habitLabel = isBedtime ? '早睡' : '早起';
    final colorScheme = Theme.of(context).colorScheme;
    var timeSelection = HabitSleepLogTimeSelection.startTime;
    var sleepKind = HabitSleepLogKind.fullSleep;
    final options = await showDialog<HabitSleepLogMigrationOptions>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final selectedPending =
              isBedtime && sleepKind == HabitSleepLogKind.nap
                  ? preview.pendingLogs
                      .where((log) => !preview.gridOnlyLogIds.contains(log.id))
                      .toList(growable: false)
                  : preview.pendingLogs;
          final previewLogs = selectedPending.take(6).toList(growable: false);
          final selectedOptions = HabitSleepLogMigrationOptions(
            timeSelection: timeSelection,
            kind: sleepKind,
          );
          return AlertDialog(
            title: Text('导入$habitLabel时间日志'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '将把 ${selectedPending.length} 条记录作为“$habitLabel”的历史打卡导入。原时间日志不会修改，历史记录中会保留原来的日期和${isBedtime ? '入睡' : '起床'}时间。',
                  ),
                  if (isBedtime && preview.gridOnlyLogIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '记录类型',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('整段睡眠'),
                          selected: sleepKind == HabitSleepLogKind.fullSleep,
                          onSelected: (_) => setDialogState(
                            () => sleepKind = HabitSleepLogKind.fullSleep,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('小睡'),
                          selected: sleepKind == HabitSleepLogKind.nap,
                          onSelected: (_) => setDialogState(
                            () => sleepKind = HabitSleepLogKind.nap,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      sleepKind == HabitSleepLogKind.fullSleep
                          ? '短时间格仅作为入睡时间标记。'
                          : '短时间格会被视为小睡，不导入早睡。',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '时间点取法',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('取开始时间'),
                          selected: timeSelection ==
                              HabitSleepLogTimeSelection.startTime,
                          onSelected: (_) => setDialogState(
                            () => timeSelection =
                                HabitSleepLogTimeSelection.startTime,
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('取平均时间'),
                          selected: timeSelection ==
                              HabitSleepLogTimeSelection.midpoint,
                          onSelected: (_) => setDialogState(
                            () => timeSelection =
                                HabitSleepLogTimeSelection.midpoint,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  ...previewLogs.map((log) {
                    final eventTime = DateTime.fromMillisecondsSinceEpoch(
                      isBedtime ? log.startTime : log.endTime,
                    ).toLocal();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            isBedtime
                                ? Icons.nightlight_round
                                : Icons.wb_twilight_rounded,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            '${eventTime.year}-${eventTime.month.toString().padLeft(2, '0')}-'
                            '${eventTime.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          const Spacer(),
                          Text(
                            HabitText.timeOfDay(eventTime),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (selectedPending.length > previewLogs.length) ...[
                    const SizedBox(height: 4),
                    Text(
                      '还有 ${selectedPending.length - previewLogs.length} 条记录未展开',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '这些记录会标记为“导入”，不会伪造新的连续打卡。历史页会展示它们；既有目标规则和历史统计不会被自动改写。',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: selectedPending.isEmpty
                    ? null
                    : () => Navigator.of(dialogContext).pop(selectedOptions),
                icon: const Icon(Icons.file_download_outlined),
                label: Text('导入 ${selectedPending.length} 条'),
              ),
            ],
          );
        },
      ),
    );
    if (options == null || !mounted) return;

    final selectedPending = isBedtime && options.kind == HabitSleepLogKind.nap
        ? preview.pendingLogs
            .where((log) => !preview.gridOnlyLogIds.contains(log.id))
            .toList(growable: false)
        : preview.pendingLogs;
    if (selectedPending.isEmpty) return;
    final effectivePreview = HabitTimeLogImportPreview(
      candidateLogs: preview.candidateLogs,
      pendingLogs: selectedPending,
      alreadyImportedCount:
          preview.candidateLogs.length - selectedPending.length,
      gridOnlyLogIds: preview.gridOnlyLogIds,
    );

    try {
      final imported = await HabitSleepLogMigrationService.importTimeLogs(
        goal: _goal,
        rule: _rule,
        preview: effectivePreview,
        part: part,
        options: options,
      );
      await HabitSleepDurationService.syncAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $imported 条$habitLabel历史打卡')),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  List<Widget> _buildInsightSections(ColorScheme colorScheme) {
    return [
      if (_goal.sourceType == HabitSourceType.timeCheckIn &&
          (_summary != null || _timeTrend.isNotEmpty))
        _buildTimePointSection(colorScheme),
      _buildRuleSection(colorScheme),
      if (_summary != null && _goal.sourceType != HabitSourceType.timeCheckIn)
        (_goal.sourceType == HabitSourceType.pomodoroTag ||
                _goal.sourceType == HabitSourceType.durationCheckIn)
            ? _buildDurationSummarySection(colorScheme)
            : _buildSummarySection(colorScheme),
    ];
  }

  // ── 时间点型：打卡趋势、实际时间与统计 ─────────────────
  Widget _buildTimePointSection(ColorScheme colorScheme) {
    final visibleTrend = _timeTrend.length <= _timeTrendRangeDays
        ? _timeTrend
        : _timeTrend.sublist(_timeTrend.length - _timeTrendRangeDays);
    final recordedDays = visibleTrend
        .where((day) => day.progress.firstRecordAt != null)
        .toList(growable: false);
    final recentRecordedDays = recordedDays.reversed.take(7);
    final summary = _summary;
    final chartData = visibleTrend.map((day) {
      final rule =
          HabitRuleResolver.effectiveRule(_rules, day.logicalDate) ?? _rule;
      return HabitTimePointChartData(
        date: day.logicalDate,
        actualTime: day.progress.firstRecordAt,
        onTime: day.progress.goalMet,
        targetTimeMinute: rule.targetTimeMinute,
        dayBoundaryMinute: rule.dayBoundaryMinute > 0
            ? rule.dayBoundaryMinute
            : HabitRuleResolver.defaultDayBoundaryMinute,
      );
    }).toList(growable: false);
    final hasTargetTime =
        chartData.any((point) => point.targetTimeMinute != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '近 $_timeTrendRangeDays 天打卡趋势',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _openHistory(sourceKey: _detailCardKey),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 天')),
              ButtonSegment(value: 30, label: Text('30 天')),
            ],
            selected: {_timeTrendRangeDays},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(fontSize: 12),
            ),
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                setState(() => _timeTrendRangeDays = selection.first);
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_timeTrend.isEmpty)
                Text(
                  '暂无可展示的趋势数据',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                HabitTimePointChart(
                  data: chartData,
                  rangeDays: _timeTrendRangeDays,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _trendLegend(
                      colorScheme.tertiary,
                      '达标',
                      colorScheme,
                    ),
                    _trendLegend(
                      colorScheme.error,
                      '未达标',
                      colorScheme,
                    ),
                    _trendLegend(
                      colorScheme.surfaceContainerHighest,
                      '未打卡',
                      colorScheme,
                    ),
                    if (hasTargetTime)
                      _trendLegend(
                        colorScheme.primary,
                        '目标时间',
                        colorScheme,
                        dashed: true,
                      ),
                  ],
                ),
              ],
              if (recordedDays.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(color: colorScheme.outlineVariant),
                const SizedBox(height: 4),
                Text(
                  '最近打卡时间',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                ...recentRecordedDays.map(
                  (day) => _buildTimeTrendDayRow(day, colorScheme),
                ),
              ],
            ],
          ),
        ),
        if (summary != null) ...[
          const SizedBox(height: 10),
          _buildTimePointStats(summary, colorScheme),
        ],
      ],
    );
  }

  Widget _trendLegend(
    Color color,
    String label,
    ColorScheme colorScheme, {
    bool dashed = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 8,
          child: CustomPaint(
            painter: _TrendLegendPainter(color: color, dashed: dashed),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeTrendDayRow(
    HabitDayProgress day,
    ColorScheme colorScheme,
  ) {
    final actual = day.progress.firstRecordAt!;
    final rule =
        HabitRuleResolver.effectiveRule(_rules, day.logicalDate) ?? _rule;
    final statusColor =
        day.progress.goalMet ? colorScheme.tertiary : colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              _shortDate(day.logicalDate),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(Icons.schedule_rounded, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(
            HabitText.timeOfDay(actual),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            HabitText.timePointStatus(rule, day.progress),
            style: TextStyle(
              fontSize: 11.5,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePointStats(
    HabitStreakSummary summary,
    ColorScheme colorScheme,
  ) {
    final averageTime = summary.averageTimeMinute == null
        ? '—'
        : HabitText.targetTime(summary.averageTimeMinute!.round());
    final onTimeRate =
        summary.onTimeRate == null ? '—' : _percent(summary.onTimeRate!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '时间点统计',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCell('平均时间', averageTime)),
              Expanded(child: _statCell('准时率', onTimeRate)),
              Expanded(
                child: _statCell('当前连续', '${summary.currentStreak} 天'),
              ),
              Expanded(
                child: _statCell('最长连续', '${summary.longestStreak} 天'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statCell('完成率 7', _percent(summary.rate7))),
              Expanded(child: _statCell('完成率 30', _percent(summary.rate30))),
              Expanded(
                child: _statCell(
                  '已完成',
                  '${summary.completedCount}/${summary.plannedCount}',
                ),
              ),
              Expanded(child: _statCell('逾期', '${summary.overdueCount}')),
            ],
          ),
          if (summary.weakestWeekday != null) ...[
            const SizedBox(height: 10),
            Text(
              '最容易中断：${_weekdayLabel(summary.weakestWeekday!)}',
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortDate(DateTime date) => '${date.month}/${date.day}';

  String _weekdayLabel(int weekday) {
    const labels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekday >= 0 && weekday < labels.length ? labels[weekday] : '—';
  }

  // ── 头部：图标 + 连续 ────────────────────────────────
  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _goal.icon.isNotEmpty ? _goal.icon : '🎯',
            style: const TextStyle(fontSize: 30),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _goal.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                HabitText.periodLabel(_rule),
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_summary != null && _summary!.currentStreak > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_rounded,
                    size: 16, color: colorScheme.tertiary),
                const SizedBox(width: 4),
                Text(
                  '连续 ${_summary!.currentStreak}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 今日进度卡 ──────────────────────────────────────
  Widget _buildTodayCard(ColorScheme colorScheme) {
    final progress = _todayProgress!;
    final isHydration = HabitAdaptationService.forHabit(_goal)?.kind ==
        HabitAdaptationKind.hydration;
    final dayProgress = HabitDayProgress(
      habit: _goal,
      logicalDate: HabitSleepDurationService.displayLogicalDateFor(
        _goal,
        DateTime.now(),
      ),
      status: progress.dayStatus,
      progress: progress,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitCard(
          goal: _goal,
          rule: _rule,
          dayProgress: dayProgress,
          username: widget.username,
          onChanged: _loadData,
          onStartFocus: (_) => _startFocus(),
          animationKey: _detailCardKey,
          onViewRecords: () => _openHistory(sourceKey: _detailCardKey),
        ),
        if (isHydration)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: HabitWaterProgressCard(
              currentValue: progress.currentValue,
              targetValue: progress.targetValue,
              unit: _rule.unit.isEmpty ? 'ml' : _rule.unit,
              recordCount: progress.recordCount,
            ),
          ),
        if (_goal.sourceType == HabitSourceType.quantityCheckIn ||
            _goal.sourceType == HabitSourceType.timeCheckIn)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openHistory(sourceKey: _detailCardKey),
                    icon: const Icon(Icons.history_rounded, size: 16),
                    label: const Text('历史记录'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addBackfill,
                    icon:
                        const Icon(Icons.add_circle_outline_rounded, size: 16),
                    label: const Text('补录'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 今日专注记录（时长型）────────────────────────────
  Widget _buildFocusRecordSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '今日专注（${_todayFocusRecords.length}）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _openHistory(sourceKey: _detailCardKey),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._todayFocusRecords.map(
          (record) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        HabitText.formatDuration(
                            record.actualDuration ?? record.plannedDuration),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (record.note?.isNotEmpty == true)
                        Text(
                          record.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  HabitText.timeOfDay(
                    DateTime.fromMillisecondsSinceEpoch(record.startTime)
                        .toLocal(),
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 今日记录列表 ────────────────────────────────────
  Widget _buildRecordSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$_displayPeriodLabel记录（${_todayCheckIns.length}）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _openHistory(sourceKey: _detailCardKey),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final checkIn in _todayCheckIns)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _goal.sourceType == HabitSourceType.timeCheckIn
                      ? Icons.schedule_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _recordMainText(checkIn),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (checkIn.note?.isNotEmpty == true)
                        Text(
                          checkIn.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  HabitText.timeOfDay(
                      DateTime.fromMillisecondsSinceEpoch(checkIn.occurredAt)
                          .toLocal()),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (checkIn.source != HabitCheckInSource.skip)
                  IconButton(
                    tooltip: '编辑记录',
                    onPressed: () => _editRecord(checkIn),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                IconButton(
                  tooltip: '删除记录',
                  onPressed: () => _deleteRecord(checkIn),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAdaptationSection(ColorScheme colorScheme) {
    final adaptation = HabitAdaptationService.forHabit(_goal);
    if (adaptation == null) return const SizedBox.shrink();
    final isSleepAdaptation =
        adaptation.kind == HabitAdaptationKind.earlyWake ||
            adaptation.kind == HabitAdaptationKind.earlySleep;
    final isPushUpAdaptation = adaptation.kind == HabitAdaptationKind.pushUp;
    final isRunningAdaptation = adaptation.kind == HabitAdaptationKind.running;
    final isReadingAdaptation = adaptation.kind == HabitAdaptationKind.reading;
    final isLearningAdaptation =
        adaptation.kind == HabitAdaptationKind.learning;
    final isVocabularyAdaptation =
        adaptation.kind == HabitAdaptationKind.vocabulary;
    final isMeditationAdaptation =
        adaptation.kind == HabitAdaptationKind.meditation;
    final isSleepDurationAdaptation =
        adaptation.kind == HabitAdaptationKind.sleepDuration;
    final isFocusDurationAdaptation =
        isReadingAdaptation || isLearningAdaptation || isMeditationAdaptation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitAdaptationPanel(
          adaptation: adaptation,
          currentValue: isSleepAdaptation
              ? null
              : isSleepDurationAdaptation
                  ? _todayProgress == null
                      ? null
                      : _todayProgress!.currentValue / 3600
                  : isFocusDurationAdaptation
                      ? _todayProgress == null
                          ? null
                          : _todayProgress!.currentValue / 60
                      : _todayProgress?.currentValue,
          targetValue: isSleepAdaptation
              ? null
              : isSleepDurationAdaptation
                  ? _rule.targetValue / 3600
                  : isFocusDurationAdaptation
                      ? _rule.targetValue / 60
                      : _rule.targetValue,
          targetUnitOverride: isSleepDurationAdaptation
              ? '小时'
              : _rule.unit.isEmpty
                  ? null
                  : _rule.unit,
        ),
        if (isSleepAdaptation) ...[
          const SizedBox(height: 12),
          HabitSleepTimingGuide(
            adaptation: adaptation,
            targetMinute: _rule.targetTimeMinute ?? 0,
          ),
        ],
        if (isPushUpAdaptation) ...[
          const SizedBox(height: 12),
          HabitPushUpGuide(
            targetValue: _rule.targetValue.round(),
            periodType: _rule.periodType,
          ),
        ],
        if (isRunningAdaptation) ...[
          const SizedBox(height: 12),
          HabitRunningGuide(
            targetValue: _rule.targetValue.round(),
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
            unit: _rule.unit,
          ),
        ],
        if (isReadingAdaptation) ...[
          const SizedBox(height: 12),
          HabitReadingGuide(
            targetMinutes: (_rule.targetValue / 60).round(),
            defaultFocusMinutes: _goal.defaultFocusMinutes,
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
          ),
        ],
        if (isLearningAdaptation) ...[
          const SizedBox(height: 12),
          HabitLearningGuide(
            targetMinutes: (_rule.targetValue / 60).round(),
            defaultFocusMinutes: _goal.defaultFocusMinutes,
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
          ),
        ],
        if (isVocabularyAdaptation) ...[
          const SizedBox(height: 12),
          HabitVocabularyGuide(
            targetValue: _rule.targetValue.round(),
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
            unit: _rule.unit,
          ),
        ],
        if (isMeditationAdaptation) ...[
          const SizedBox(height: 12),
          HabitMeditationGuide(
            targetMinutes: (_rule.targetValue / 60).round(),
            periodType: _rule.periodType,
            weekdaysMask: _rule.weekdaysMask,
          ),
        ],
        if (isSleepDurationAdaptation) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '数据来源：配对“早睡”和“早起”打卡节点自动计算。自动记录可在历史页编辑，编辑后将保留你的手动修正。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _recordMainText(HabitCheckIn checkIn) {
    if (_goal.sourceType == HabitSourceType.timeCheckIn) {
      return '打卡 ${HabitText.timeOfDay(DateTime.fromMillisecondsSinceEpoch(checkIn.occurredAt).toLocal())}';
    }
    final value = checkIn.value;
    if (_goal.sourceType == HabitSourceType.durationCheckIn) {
      final label = HabitAdaptationService.forHabit(_goal)?.kind ==
              HabitAdaptationKind.sleepDuration
          ? '睡眠'
          : '时长';
      return '$label ${HabitText.formatDuration(value.round())}';
    }
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
    final unit = _rule.unit;
    return '记录 $text${unit.isNotEmpty ? ' $unit' : ''}';
  }

  Future<void> _editRecord(HabitCheckIn? checkIn) async {
    if (checkIn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_displayPeriodLabel还没有记录')),
      );
      return;
    }
    final rule = _rules.firstWhere(
      (candidate) => candidate.uuid == checkIn.ruleRevisionUuid,
      orElse: () => _rule,
    );
    final edited = await showHabitCheckInEditor(
      context: context,
      goal: _goal,
      rule: rule,
      checkIn: checkIn,
    );
    if (edited == null || !mounted) return;
    await HabitRepository.updateCheckIn(edited);
    _loadData();
  }

  Future<void> _deleteRecord(HabitCheckIn checkIn) async {
    await HabitRepository.deleteCheckIn(checkIn);
    if (mounted) _loadData();
  }

  /// 补录：选择任意日期时间新增一条打卡。
  Future<void> _addBackfill() async {
    final now = DateTime.now();
    var date = now;
    var time = TimeOfDay.fromDateTime(now);
    // 局部 controller：对话框每次打开都是空值，避免残留上一次输入。
    final valueController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('补录打卡'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded),
                title: Text(
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}',
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: now.subtract(const Duration(days: 90)),
                    lastDate: now,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      date = DateTime(picked.year, picked.month, picked.day,
                          time.hour, time.minute);
                    });
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(
                  '时间：${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}',
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (picked != null) {
                    setDialogState(() {
                      time = picked;
                      date = DateTime(date.year, date.month, date.day,
                          picked.hour, picked.minute);
                    });
                  }
                },
              ),
              if (_goal.sourceType == HabitSourceType.quantityCheckIn ||
                  _goal.sourceType == HabitSourceType.durationCheckIn) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: valueController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _goal.sourceType ==
                            HabitSourceType.durationCheckIn
                        ? '睡眠时长（小时）'
                        : '数量${_rule.unit.isNotEmpty ? '（${_rule.unit}）' : ''}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('补录'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      valueController.dispose();
      return;
    }

    double value = 0;
    if (_goal.sourceType == HabitSourceType.quantityCheckIn ||
        _goal.sourceType == HabitSourceType.durationCheckIn) {
      final parsed = double.tryParse(valueController.text.trim());
      valueController.dispose();
      if (parsed == null || parsed <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入有效的数量')),
        );
        return;
      }
      value = _goal.sourceType == HabitSourceType.durationCheckIn
          ? parsed * 3600
          : parsed;
    } else {
      valueController.dispose();
    }
    await HabitRepository.addCheckIn(
      goal: _goal,
      rule: _rule,
      localOccurredAt: date,
      value: value,
    );
    _loadData();
  }

  /// 时长型：启动专注并跳转番茄钟，默认时长为习惯设置的默认时长。
  Future<void> _startFocus() async {
    final goal = _goal;
    final tagUuids = goal.sourceType == HabitSourceType.pomodoroTag
        ? goal.sourceIds
        : const <String>[];
    final running = await PomodoroService.loadRunState();
    if (running != null &&
        (running.phase == PomodoroPhase.focusing ||
            running.phase == PomodoroPhase.breaking)) {
      if (!mounted) return;
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => PomodoroScreen(username: widget.username),
        ),
      );
      return;
    }
    try {
      final settings = await PomodoroService.getSettings();
      await PomodoroControlService.startFocus(
        settings: settings,
        tagUuids: tagUuids,
        durationMinutes: goal.defaultFocusMinutes,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        PageTransitions.material(
          builder: (_) => PomodoroScreen(username: widget.username),
        ),
      );
      if (mounted) _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动专注失败: $e')),
      );
    }
  }

  // ── 目标信息 ────────────────────────────────────────
  Widget _buildRuleSection(ColorScheme colorScheme) {
    final rule = _rule;
    final items = <(String, String)>[
      ('周期', HabitText.periodLabel(rule)),
      ('类型', HabitText.sourceTypeLabel(_goal.sourceType)),
    ];
    switch (_goal.sourceType) {
      case HabitSourceType.recurringTodo:
        break;
      case HabitSourceType.pomodoroTag:
        items.add(('目标', '${(rule.targetValue / 60).round()} 分钟 / 周期'));
      case HabitSourceType.durationCheckIn:
        items.add(
            ('目标', '${(rule.targetValue / 3600).toStringAsFixed(1)} 小时 / 晚'));
      case HabitSourceType.quantityCheckIn:
        final target = rule.targetValue;
        final text = target == target.roundToDouble()
            ? target.round().toString()
            : target.toString();
        items.add(('目标', '$text ${rule.unit}'));
        if (rule.quickValues.isNotEmpty) {
          items.add(('快捷', rule.quickValues.join('、')));
        }
      case HabitSourceType.timeCheckIn:
        items.add(('目标', HabitText.targetTime(rule.targetTimeMinute)));
        items.add((
          '条件',
          '${rule.timeComparison == HabitTimeComparison.before ? '早于' : '晚于'} '
              '${HabitText.targetTime(rule.targetTimeMinute)}'
              '${rule.timeToleranceMinutes > 0 ? '（±${rule.timeToleranceMinutes} 分钟）' : ''}',
        ));
        if (rule.dayBoundaryMinute > 0) {
          items.add(
              ('日期分界', HabitText.dayBoundaryLabel(rule.dayBoundaryMinute)));
        }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '目标信息',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final (label, value) in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 统计 ────────────────────────────────────────────
  Widget _buildDurationSummarySection(ColorScheme colorScheme) {
    final summary = _summary!;
    final unit = _periodUnit();
    final isSleepDuration = HabitAdaptationService.forHabit(_goal)?.kind ==
        HabitAdaptationKind.sleepDuration;
    final averageDuration = summary.averageDuration == null
        ? '—'
        : HabitText.formatDuration(summary.averageDuration!.round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '时长统计（近 30 周期）',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statCell(
                      isSleepDuration ? '平均睡眠' : '平均时长/$unit',
                      averageDuration,
                    ),
                  ),
                  Expanded(
                    child: _statCell(
                      '当前连续',
                      '${summary.currentStreak} $unit',
                    ),
                  ),
                  Expanded(
                    child: _statCell(
                      '最长连续',
                      '${summary.longestStreak} $unit',
                    ),
                  ),
                  Expanded(
                    child: _statCell('完成率 7', _percent(summary.rate7)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _statCell('完成率 30', _percent(summary.rate30)),
                  ),
                  Expanded(
                    child: _statCell(
                      '已完成',
                      '${summary.completedCount}/${summary.plannedCount}',
                    ),
                  ),
                  Expanded(
                    child: _statCell('逾期', '${summary.overdueCount}'),
                  ),
                  Expanded(
                    child: _statCell(
                      '目标',
                      isSleepDuration
                          ? HabitText.formatDuration(_rule.targetValue.round())
                          : '${(_rule.targetValue / 60).round()} 分钟',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: summary.rate30.clamp(0.0, 1.0),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(colorScheme.tertiary),
                  ),
                ),
              ),
              if (summary.weakestWeekday != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '最容易中断：${_weekdayLabel(summary.weakestWeekday!)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummarySection(ColorScheme colorScheme) {
    final summary = _summary!;
    final unit = _periodUnit();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '近 30 周期统计',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statCell('最长连续', '${summary.longestStreak} $unit'),
                  ),
                  Expanded(
                    child: _statCell('完成率 7', _percent(summary.rate7)),
                  ),
                  Expanded(
                    child: _statCell('完成率 30', _percent(summary.rate30)),
                  ),
                  Expanded(
                    child: _statCell(
                      '计划',
                      '${summary.completedCount}/${summary.plannedCount}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: summary.rate30.clamp(0.0, 1.0),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(colorScheme.tertiary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCell(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _periodUnit() {
    switch (_rule.periodType) {
      case HabitPeriodType.weekly:
        return '周';
      case HabitPeriodType.monthly:
        return '月';
      default:
        return '天';
    }
  }

  String _percent(double value) => '${(value * 100).round()}%';
}

class _TrendLegendPainter extends CustomPainter {
  final Color color;
  final bool dashed;

  const _TrendLegendPainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = dashed ? PaintingStyle.stroke : PaintingStyle.fill;
    if (dashed) {
      canvas.drawLine(
        Offset.zero.translate(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLegendPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dashed != dashed;
  }
}
