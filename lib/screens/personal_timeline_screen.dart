import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'dart:ui' as ui;
import 'dart:math' as math;

import '../utils/app_dialogs.dart';
import '../models.dart';
import '../services/browser_file_service.dart';
import '../services/file_open_service.dart';
import '../services/timeline_service.dart';
import '../services/pomodoro_service.dart';
import '../storage_service.dart';
import '../services/course_service.dart';
import '../services/medal_recommendation_service.dart';
import '../services/timeline_ml_service.dart';
import '../services/timeline_statistics_service.dart';
import '../utils/app_platform.dart';
import '../utils/app_scroll_behavior.dart';
import '../utils/page_transitions.dart';
import '../widgets/floating_bottom_bar.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import '../features/finance/models/finance_models.dart';
import '../features/finance/screens/finance_entry_screen.dart';
import '../features/finance/screens/finance_home_screen.dart';
import '../features/finance/services/finance_repository.dart';
import '../features/finance/services/finance_storage.dart';
import '../features/habits/repositories/habit_repository.dart';
import 'medal_wall_page.dart';
import '../utils/calendar_date_math.dart';

part 'personal_timeline/personal_timeline_data.dart';
part 'personal_timeline/personal_timeline_poster.dart';
part 'personal_timeline/personal_timeline_chrome_and_overview.dart';
part 'personal_timeline/personal_timeline_summary_and_finance.dart';
part 'personal_timeline/personal_timeline_insights_and_painters.dart';

const MethodChannel _nativeChannel = MethodChannel(
  'com.math_quiz.junpgle.com.math_quiz_app/notifications',
);

enum TimelineDimension { daily, weekly, monthly, yearly }

enum _TimelinePosterAction { share, save }

typedef _FinanceCardMetrics = ({
  Map<String, FinanceCategory> categoryByUuid,
  List<MapEntry<String, int>> topCategories,
  int maxCategory,
  int spendingDays,
  MapEntry<String, int>? peakDay,
  int expenseCount,
  int incomeCount,
  int refundCount,
});

@visibleForTesting
({DateTime start, DateTime end}) timelineDateRange(
  TimelineDimension dimension,
  DateTime date,
) {
  final day = AppTimeFormats.dayStart(date);
  return switch (dimension) {
    TimelineDimension.daily => (
      start: day,
      end: AppTimeFormats.localDayStartOffset(day, 1),
    ),
    TimelineDimension.weekly => _weeklyRange(day),
    TimelineDimension.monthly => (
      start: DateTime(day.year, day.month, 1),
      end: DateTime(day.year, day.month + 1, 1),
    ),
    TimelineDimension.yearly => (
      start: DateTime(day.year, 1, 1),
      end: DateTime(day.year + 1, 1, 1),
    ),
  };
}

({DateTime start, DateTime end}) _weeklyRange(DateTime day) {
  final start = AppTimeFormats.localDayStartOffset(day, -(day.weekday - 1));
  return (start: start, end: AppTimeFormats.localDayStartOffset(start, 7));
}

class PersonalTimelineScreen extends StatefulWidget {
  final String username;
  final TimelineDimension initialDimension;
  final DateTime? initialDate;

  const PersonalTimelineScreen({
    super.key,
    required this.username,
    this.initialDimension = TimelineDimension.daily,
    this.initialDate,
  });

  @override
  State<PersonalTimelineScreen> createState() => _PersonalTimelineScreenState();
}

class _PersonalTimelineScreenState extends State<PersonalTimelineScreen> {
  TimelineDimension _dimension = TimelineDimension.daily;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isExportingPoster = false;
  bool _isLoadingAllTimeMedals = false;
  int _loadGeneration = 0;
  Timer? _financeOccurrenceRefreshTimer;
  late final ScrollController _timelineScrollController;
  final ValueNotifier<double> _timelineTitleProgress = ValueNotifier<double>(
    0.0,
  );

  // Data points
  List<TimelineEvent> _events = [];
  TimelineSummary? _summary;
  int _totalFocusMinutes = 0;
  String? _topAppCategory;
  int _completedCount = 0;
  int _totalCount = 0;
  int _screenTimeSeconds = 0;
  int _productiveScreenSeconds = 0;
  int _distractionScreenSeconds = 0;
  int _deadlineSprintCount = 0;
  int _earlyCompletionCount = 0;
  int _courseCount = 0;
  int _maxDailyCourseCount = 0;
  List<MapEntry<String, int>> _topScreenApps = [];
  int _pomodoroFocusSeconds = 0;
  int _timeLogSeconds = 0;
  int _pomodoroCount = 0;
  int _timeLogCount = 0;
  int _pauseSeconds = 0;
  int _pauseCount = 0;
  int _plannedMinutes = 0;
  int _planActualSeconds = 0;
  int _planBlockCount = 0;
  int _planCompletedCount = 0;
  int _planMissedCount = 0;
  int _planSkippedCount = 0;
  int _recurringCompletedCount = 0;
  int _recurringScheduledCount = 0;
  int _recurringMissedCount = 0;
  int _recurringSkippedCount = 0;
  int _recurringPendingCount = 0;
  List<TimelineRecurrenceSeriesStatistics> _recurrenceSeries = [];
  TimelineRecurrenceSeriesStatistics? _bestRecurrenceSeries;
  int _recurringLongestStreak = 0;
  List<MapEntry<String, int>> _topFocusTags = [];

  // Finance data is loaded separately from the timeline summary so an older
  // database without the finance tables can never hide the rest of the page.
  FinanceSummary _financeSummary = const FinanceSummary();
  _FinanceCardMetrics _financeCardMetrics = (
    categoryByUuid: const {},
    topCategories: const [],
    maxCategory: 1,
    spendingDays: 0,
    peakDay: null,
    expenseCount: 0,
    incomeCount: 0,
    refundCount: 0,
  );

  // ML Medal Recommendation System
  TimelineSummary? _allTimeSummary;
  MedalRecommendation? _allTimeRecommendation;
  MedalRecommendation? _medalRecommendation; // Range-specific
  List<MedalProgress> _earnedThisSession = [];
  MedalRecommendation? _allTimeMedalIndexSource;
  Map<String, MedalProgress> _allTimeMedalProgressById = const {};

  // ML Timeline Insights
  List<TimelineMLInsight> _mlInsights = [];

  @override
  void initState() {
    super.initState();
    _dimension = widget.initialDimension;
    _selectedDate = widget.initialDate ?? DateTime.now();
    _timelineScrollController = ScrollController()
      ..addListener(_handleTimelineScroll);
    FinanceStorage.revision.addListener(_onFinanceChanged);
    _loadData();
  }

  @override
  void dispose() {
    FinanceStorage.revision.removeListener(_onFinanceChanged);
    _financeOccurrenceRefreshTimer?.cancel();
    _timelineScrollController.dispose();
    _timelineTitleProgress.dispose();
    super.dispose();
  }

  void _onFinanceChanged() {
    if (mounted) _loadData();
  }

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isWide = MediaQuery.sizeOf(context).width > 900;
    final topPadding = MediaQuery.paddingOf(context).top;
    final topBarHeight = floatingGlassTopBarHeight(context);
    final bottomContentPadding = floatingBottomNavigationContentPaddingFor(
      context,
    );
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: FloatingBottomNavigationBar(
        mobilePortraitOnly: false,
        items: const [
          FloatingBottomNavigationItem(icon: Icons.today_outlined, label: '日'),
          FloatingBottomNavigationItem(
            icon: Icons.date_range_outlined,
            label: '周',
          ),
          FloatingBottomNavigationItem(
            icon: Icons.calendar_month_outlined,
            label: '月',
          ),
          FloatingBottomNavigationItem(
            icon: Icons.event_note_outlined,
            label: '年',
          ),
        ],
        selectedIndex: _dimension.index,
        onTabSelected: (index) {
          setState(() => _dimension = TimelineDimension.values[index]);
          _loadData();
        },
      ),
      body: Stack(
        children: [
          RepaintBoundary(child: _buildBackground(colorScheme)),
          OptionalLiquidGlassScrollOptimizer(
            child: CustomScrollView(
              controller: _timelineScrollController,
              physics: const AppFluidScrollPhysics(),
              slivers: [
                _buildAppBar(context),
                SliverToBoxAdapter(child: _buildGreeting(colorScheme)),
                SliverToBoxAdapter(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Animated Content Area
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 600),
                            switchInCurve: Curves.easeOutQuart,
                            switchOutCurve: Curves.easeInQuart,
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                                  final slidePosition = Tween<Offset>(
                                    begin: const Offset(0, 0.02),
                                    end: Offset.zero,
                                  ).animate(animation);
                                  return AnimatedBuilder(
                                    animation: animation,
                                    child: child,
                                    builder: (context, child) {
                                      if (animation.value >= 0.999) {
                                        return child!;
                                      }
                                      return FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: slidePosition,
                                          child: child,
                                        ),
                                      );
                                    },
                                  );
                                },
                            child: _isLoading
                                ? _buildSkeleton(colorScheme)
                                : Column(
                                    key: ValueKey(
                                      'content_${_dimension}_${_selectedDate.millisecondsSinceEpoch}',
                                    ),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildStatsOverview(colorScheme, isWide),
                                      const SizedBox(height: 40),
                                      if (isWide)
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Left Side: Main Content
                                            Expanded(
                                              flex: 2,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _buildSectionTitle(
                                                    '概览回顾',
                                                    Icons.insights_rounded,
                                                    colorScheme,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  _buildRangeSummary(
                                                    colorScheme,
                                                    isWide,
                                                  ),
                                                  _buildOverviewInsightPanels(
                                                    colorScheme,
                                                    isWide,
                                                  ),
                                                  if (_mlInsights
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 36),
                                                    _buildSectionTitle(
                                                      'AI 深度洞察',
                                                      Icons
                                                          .auto_awesome_rounded,
                                                      colorScheme,
                                                    ),
                                                    const SizedBox(height: 16),
                                                    _buildMLInsightsSection(
                                                      colorScheme,
                                                    ),
                                                  ],
                                                  _buildMedalWall(
                                                    colorScheme,
                                                    isWide,
                                                  ),
                                                  if (_dimension ==
                                                      TimelineDimension
                                                          .daily) ...[
                                                    const SizedBox(height: 40),
                                                    _buildSectionTitle(
                                                      '时光足迹',
                                                      Icons
                                                          .auto_stories_outlined,
                                                      colorScheme,
                                                    ),
                                                    const SizedBox(height: 16),
                                                    _buildTimelineFlow(
                                                      colorScheme,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 48),
                                            // Right Side: Sidebar
                                            SizedBox(
                                              width: 320,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _buildSectionTitle(
                                                    '数据深度洞察',
                                                    Icons.analytics_outlined,
                                                    colorScheme,
                                                  ),
                                                  const SizedBox(height: 20),
                                                  _buildSideHighlights(
                                                    colorScheme,
                                                  ),
                                                  const SizedBox(height: 40),
                                                  _buildSectionTitle(
                                                    '感悟与思考',
                                                    Icons.edit_note_rounded,
                                                    colorScheme,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  _buildReflection(colorScheme),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      else ...[
                                        // Mobile Layout (Existing)
                                        _buildSectionTitle(
                                          _dimension == TimelineDimension.daily
                                              ? '概览回顾'
                                              : '阶段回顾',
                                          Icons.insights_rounded,
                                          colorScheme,
                                        ),
                                        const SizedBox(height: 16),
                                        _buildRangeSummary(colorScheme, isWide),
                                        _buildOverviewInsightPanels(
                                          colorScheme,
                                          isWide,
                                        ),
                                        if (_mlInsights.isNotEmpty) ...[
                                          const SizedBox(height: 36),
                                          _buildSectionTitle(
                                            'AI 深度洞察',
                                            Icons.auto_awesome_rounded,
                                            colorScheme,
                                          ),
                                          const SizedBox(height: 16),
                                          _buildMLInsightsSection(colorScheme),
                                        ],
                                        _buildMedalWall(colorScheme, isWide),
                                        if (_dimension ==
                                            TimelineDimension.daily) ...[
                                          const SizedBox(height: 40),
                                          _buildSectionTitle(
                                            '时光足迹',
                                            Icons.auto_stories_outlined,
                                            colorScheme,
                                          ),
                                          const SizedBox(height: 16),
                                          _buildTimelineFlow(colorScheme),
                                        ],
                                        const SizedBox(height: 40),
                                        _buildSectionTitle(
                                          '数据深度洞察',
                                          Icons.analytics_outlined,
                                          colorScheme,
                                        ),
                                        const SizedBox(height: 16),
                                        _buildSideHighlights(colorScheme),
                                        const SizedBox(height: 40),
                                        _buildSectionTitle(
                                          '感悟与思考',
                                          Icons.edit_note_rounded,
                                          colorScheme,
                                        ),
                                        const SizedBox(height: 16),
                                        _buildReflection(colorScheme),
                                      ],
                                      SizedBox(height: bottomContentPadding),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (topBarHeight > 0.0)
            _buildTimelineTopFadeCap(colorScheme, topBarHeight),
          // The foreground AppBar is deliberately above the mask: its title
          // and actions must stay crisp while only the scrolling body fades.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topBarHeight,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: floatingGlassTopBarSystemOverlayStyle(context),
              child: Padding(
                padding: EdgeInsets.only(top: topPadding),
                child: SizedBox(
                  height: kToolbarHeight,
                  child: _buildTimelineToolbar(colorScheme),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
