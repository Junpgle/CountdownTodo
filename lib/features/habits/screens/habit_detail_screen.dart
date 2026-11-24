import '../../../widgets/floating_glass_control.dart';

import 'package:flutter/material.dart';

import '../../../models.dart';
import '../models/habit_checkin.dart';
import '../models/habit_goal.dart';
import '../models/habit_goal_rule.dart';
import '../models/habit_progress.dart';
import '../repositories/habit_repository.dart';
import '../services/habit_adaptation_service.dart';
import '../services/habit_day_loader.dart';
import '../services/habit_drink_log_service.dart';
import '../services/habit_progress_calculator.dart';
import '../services/habit_rule_resolver.dart';
import '../services/habit_source_resolver.dart';
import '../services/habit_streak_service.dart';
import '../widgets/habit_card.dart';
import '../widgets/habit_checkin_editor.dart';
import '../widgets/habit_emoji_text.dart';
import '../widgets/habit_format.dart';
import '../widgets/habit_adaptation_panel.dart';
import '../widgets/habit_time_point_chart.dart';
import '../widgets/habit_water_progress_card.dart';
import '../widgets/habit_sleep_coaching_card.dart';
import '../../../storage_service.dart';
import '../../../services/pomodoro_service.dart';
import '../../../utils/page_transitions.dart';
import 'habit_edit_screen.dart';
import 'habit_history_screen.dart';
import '../services/habit_sleep_log_migration_service.dart';
import '../services/habit_sleep_duration_service.dart';
import '../services/habit_focus_launcher.dart';
import '../services/habit_sleep_coaching_service.dart';
import '../services/habit_freeze_service.dart';
import '../../../utils/app_dialogs.dart';

part 'parts/habit_detail_actions.dart';
part 'parts/habit_detail_insights_and_header.dart';
part 'parts/habit_detail_sections.dart';

/// 习惯详情：今日进度 + 今日打卡记录 + 目标信息 + 管理操作。
///
/// 有变更时 pop(true)，由调用方触发刷新。
class HabitDetailScreen extends StatefulWidget {
  final HabitGoal goal;
  final String username;

  const HabitDetailScreen({super.key, required this.goal, this.username = ''});

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
  int _freezeBalance = 0;
  HabitTimeLogImportPreview? _timeLogImportPreview;
  HabitTimeLogImportPart? _timeLogImportPart;
  HabitSleepCoachingSnapshot? _sleepCoachingSnapshot;
  HabitDrinkStats? _drinkStats;
  bool _loading = true;

  bool get _isSleepDuration =>
      HabitSleepDurationService.isSleepDurationGoal(_goal);

  String get _displayPeriodLabel => _isSleepDuration ? '前一晚' : '今日';

  Future<String> _accountUsername() async {
    final explicit = widget.username.trim();
    if (explicit.isNotEmpty) return explicit;
    return (await StorageService.getLoginSession())?.trim() ?? '';
  }

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _goal = widget.goal;
    _loadData(showLoadingIndicator: true);
  }

  Future<void> _loadData({bool showLoadingIndicator = false}) async {
    if (!mounted) return;
    if (showLoadingIndicator || _todayProgress == null) {
      setState(() => _loading = true);
    }
    if (HabitSleepDurationService.isSleepDurationGoal(_goal)) {
      await HabitSleepDurationService.syncAll();
    }
    final adaptation = HabitAdaptationService.forHabit(_goal);
    final isSleepGoal =
        adaptation?.kind == HabitAdaptationKind.earlySleep ||
        adaptation?.kind == HabitAdaptationKind.earlyWake ||
        adaptation?.kind == HabitAdaptationKind.sleepDuration;
    final username = isSleepGoal ? await _accountUsername() : '';
    if (isSleepGoal && username.isNotEmpty) {
      try {
        await StorageService.syncData(
          username,
          syncTodos: false,
          syncCountdowns: false,
          syncScreenTime: false,
          syncTimeLogs: false,
          syncPomodoro: false,
          syncPlanBlocks: false,
          syncFixedSchedules: false,
          syncHabits: true,
        );
      } catch (_) {
        // 详情页仍可使用本地快照离线展示。
      }
    }
    final coachingFuture = isSleepGoal
        ? HabitSleepCoachingService.load(username)
        : Future<HabitSleepCoachingSnapshot?>.value(null);
    final rulesFuture = HabitRepository.getRules(habitUuid: _goal.uuid);
    final initialResults = await Future.wait([coachingFuture, rulesFuture]);
    final sleepCoachingSnapshot =
        initialResults[0] as HabitSleepCoachingSnapshot?;
    final rules = initialResults[1] as List<HabitGoalRuleRevision>;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final displayDate = HabitDayLoader.progressLogicalDateFor(
      goal: _goal,
      rules: rules,
      date: today,
    );

    // 并行拉取进度、连续概览、趋势分析与免扣卡，避免串行读库阻塞页面渲染。
    final progressFuture = rules.isEmpty
        ? Future<HabitProgress?>.value(null)
        : HabitProgressCalculator.computePeriod(
            habit: _goal,
            rules: rules,
            logicalDate: displayDate,
          );
    final summaryFuture = rules.isEmpty
        ? Future<HabitStreakSummary?>.value(null)
        : HabitStreakService.summarize(habit: _goal, rules: rules);
    final timeTrendFuture =
        _goal.sourceType == HabitSourceType.timeCheckIn && rules.isNotEmpty
        ? HabitProgressCalculator.computeRange(
            habit: _goal,
            rules: rules,
            from: HabitRuleResolver.addCalendarDays(todayDate, -29),
            to: todayDate,
          )
        : Future<List<HabitDayProgress>>.value(const <HabitDayProgress>[]);
    final focusRecordsFuture = _goal.sourceType == HabitSourceType.pomodoroTag
        ? HabitSourceResolver.recordsForTags(
            tagUuids: _goal.sourceIds,
            from: todayDate,
            to: HabitRuleResolver.addCalendarDays(todayDate, 1),
          )
        : Future<List<PomodoroRecord>>.value(const <PomodoroRecord>[]);
    final freezeBalanceFuture = HabitFreezeService.getAvailableCards(
      _goal.uuid,
    );
    final isDrinkGoal = HabitDrinkLogService.isDrinkChoiceHabit(_goal);
    final allDrinkCheckInsFuture = isDrinkGoal
        ? HabitRepository.getCheckIns(habitUuid: _goal.uuid)
        : Future<List<HabitCheckIn>>.value(const <HabitCheckIn>[]);

    final results = await Future.wait([
      progressFuture,
      summaryFuture,
      timeTrendFuture,
      focusRecordsFuture,
      freezeBalanceFuture,
      allDrinkCheckInsFuture,
    ]);

    final progress = results[0] as HabitProgress?;
    final summary = results[1] as HabitStreakSummary?;
    final timeTrend = results[2] as List<HabitDayProgress>;
    final focusRecords = results[3] as List<PomodoroRecord>;
    var freezeBalance = results[4] as int;
    final allDrinkCheckIns = results[5] as List<HabitCheckIn>;
    final drinkStats = isDrinkGoal
        ? HabitDrinkLogService.summarizeDrinkLogs(
            goal: _goal,
            allCheckIns: allDrinkCheckIns,
            referenceDate: displayDate,
          )
        : null;
    final checkIns = progress?.checkIns ?? const <HabitCheckIn>[];

    if (summary != null && summary.currentStreak > 0) {
      final awarded = await HabitFreezeService.checkAndAwardCards(
        habit: _goal,
        currentStreak: summary.currentStreak,
      );
      if (awarded > 0) {
        freezeBalance = await HabitFreezeService.getAvailableCards(_goal.uuid);
      }
    }

    if (mounted) {
      setState(() {
        _rules = rules;
        _todayProgress = progress;
        _summary = summary;
        _todayCheckIns = checkIns;
        _todayFocusRecords = focusRecords;
        _timeTrend = timeTrend;
        _freezeBalance = freezeBalance;
        _sleepCoachingSnapshot = sleepCoachingSnapshot;
        _drinkStats = drinkStats;
        _loading = false;
      });
    }
    _loadTimeLogImportPreview();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
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
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _buildBody(colorScheme, topBarHeight),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, double topPadding) {
    if (_loading && _todayProgress == null) {
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
                topPadding + 16,
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
}
