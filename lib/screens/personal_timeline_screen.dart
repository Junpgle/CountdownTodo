import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../models.dart';
import '../services/timeline_service.dart';
import '../services/pomodoro_service.dart';
import '../storage_service.dart';
import '../services/course_service.dart';

enum TimelineDimension { daily, weekly, monthly, yearly }

class PersonalTimelineScreen extends StatefulWidget {
  final String username;
  const PersonalTimelineScreen({super.key, required this.username});

  @override
  State<PersonalTimelineScreen> createState() => _PersonalTimelineScreenState();
}

class _PersonalTimelineScreenState extends State<PersonalTimelineScreen> with SingleTickerProviderStateMixin {
  TimelineDimension _dimension = TimelineDimension.daily;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  late AnimationController _animationController;

  // Data points
  List<TimelineEvent> _events = [];
  TimelineSummary? _summary;
  int _totalFocusMinutes = 0;
  String? _topAppCategory;
  int _completedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    DateTime start;
    DateTime end;

    final day = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day);

    switch (_dimension) {
      case TimelineDimension.daily:
        start = day;
        end = day.add(const Duration(days: 1));
        break;
      case TimelineDimension.weekly:
        start = day.subtract(Duration(days: day.weekday - 1));
        end = start.add(const Duration(days: 7));
        break;
      case TimelineDimension.monthly:
        start = DateTime(day.year, day.month, 1);
        end = DateTime(day.year, day.month + 1, 1);
        break;
      case TimelineDimension.yearly:
        start = DateTime(day.year, 1, 1);
        end = DateTime(day.year + 1, 1, 1);
        break;
    }

    try {
      // 1. Get Timeline Summary for Range
      final summary = await TimelineService.instance.getSummaryForRange(
          widget.username, start, end);

      // 2. Get detailed events for Daily only (too many for others)
      if (_dimension == TimelineDimension.daily) {
        _events =
        await TimelineService.instance.getEventsForDay(widget.username, day);
      } else {
        _events = []; // Or maybe fetch "Major" events
      }

      // 3. Get Focus Time
      final records = await PomodoroService.getRecordsInRange(start, end);
      int totalSecs = records.fold(0, (sum, r) => sum + r.effectiveDuration);

      // 4. Get Top Category (Simplified)
      final screenStats = await StorageService.getScreenTimeHistory();
      Map<String, int> catUsage = {};

      // Iterate through days in range
      DateTime cursor = start;
      while (cursor.isBefore(end)) {
        final dateStr = DateFormat('yyyy-MM-dd').format(cursor);
        final stats = screenStats[dateStr] ?? [];
        for (var item in stats) {
          String cat = item['category'] ?? '其他';
          catUsage[cat] =
              (catUsage[cat] ?? 0) + (item['duration'] as int? ?? 0);
        }
        cursor = cursor.add(const Duration(days: 1));
      }

      String? topCat;
      if (catUsage.isNotEmpty) {
        topCat = catUsage.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
      }

      if (mounted) {
        setState(() {
          _summary = summary;
          _totalFocusMinutes = totalSecs ~/ 60;

          // Smart Top Category: Prioritize task-based subject if app category is generic
          String? displayCat = topCat;
          if (displayCat == null || displayCat == '其他') {
            if (summary.subjectDistribution.entries.isNotEmpty) {
              final topSub = summary.subjectDistribution.entries
                  .reduce((a, b) => a.value > b.value ? a : b)
                  .key;
              if (topSub != '其他') {
                displayCat = topSub;
              }
            }
          }
          _topAppCategory = displayCat ?? '学习';
          _completedCount =
              summary.todoCompletedCount + summary.countdownCompletedCount;
          _isLoading = false;
        });
        _animationController.forward(from: 0.0);
      }
    } catch (e) {
      debugPrint('Error loading insight data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isWide = MediaQuery
        .of(context)
        .size
        .width > 900;

    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(colorScheme),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(context, colorScheme),
              SliverToBoxAdapter(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),

                        // Animated Content Area
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600),
                          switchInCurve: Curves.easeOutQuart,
                          switchOutCurve: Curves.easeInQuart,
                          transitionBuilder: (Widget child, Animation<
                              double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.02),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _isLoading
                              ? _buildSkeleton(colorScheme)
                              : Column(
                            key: ValueKey('content_${_dimension}_${_selectedDate
                                .millisecondsSinceEpoch}'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatsOverview(colorScheme, isWide),
                              const SizedBox(height: 40),
                              if (isWide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Left Side: Main Content
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment
                                            .start,
                                        children: [
                                          _buildSectionTitle('概览回顾',
                                              Icons.insights_rounded,
                                              colorScheme),
                                          const SizedBox(height: 16),
                                          _buildRangeSummary(
                                              colorScheme, isWide),
                                          if (_dimension ==
                                              TimelineDimension.daily) ...[
                                            const SizedBox(height: 40),
                                            _buildSectionTitle('时光足迹',
                                                Icons.auto_stories_outlined,
                                                colorScheme),
                                            const SizedBox(height: 16),
                                            _buildTimelineFlow(colorScheme),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 48),
                                    // Right Side: Sidebar
                                    SizedBox(
                                      width: 320,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment
                                            .start,
                                        children: [
                                          _buildSectionTitle('数据深度洞察',
                                              Icons.analytics_outlined,
                                              colorScheme),
                                          const SizedBox(height: 20),
                                          _buildSideHighlights(colorScheme),
                                          const SizedBox(height: 40),
                                          _buildSectionTitle('感悟与思考',
                                              Icons.edit_note_rounded,
                                              colorScheme),
                                          const SizedBox(height: 16),
                                          _buildReflection(colorScheme),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              else
                                ...[
                                  // Mobile Layout (Existing)
                                  if (_dimension ==
                                      TimelineDimension.daily) ...[
                                    _buildSectionTitle(
                                        '时光足迹', Icons.auto_stories_outlined,
                                        colorScheme),
                                    const SizedBox(height: 16),
                                    _buildTimelineFlow(colorScheme),
                                  ] else
                                    ...[
                                      _buildSectionTitle(
                                          '阶段回顾', Icons.insights_rounded,
                                          colorScheme),
                                      const SizedBox(height: 16),
                                      _buildRangeSummary(colorScheme, isWide),
                                    ],
                                  const SizedBox(height: 40),
                                  _buildSectionTitle(
                                      '感悟与思考', Icons.edit_note_rounded,
                                      colorScheme),
                                  const SizedBox(height: 16),
                                  _buildReflection(colorScheme),
                                ],
                              const SizedBox(height: 60),
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
        ],
      ),
    );
  }

  Widget _buildSkeleton(ColorScheme cs) {
    return Column(
      key: const ValueKey('skeleton'),
      children: [
        Container(
          height: 110,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(32),
          ),
        ),
        const SizedBox(height: 40),
        ...List.generate(3, (i) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                height: 90,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildBackground(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surface,
            cs.primaryContainer.withValues(alpha: 0.08),
            cs.secondaryContainer.withValues(alpha: 0.04),
            cs.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(bottom: 100,
              left: -100,
              child: _buildBlob(cs.secondary.withValues(alpha: 0.03), 400)),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent)),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme cs) {
    return SliverAppBar(
      expandedHeight: 220,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            // Subtle Pattern or Illustration (Fixed)
            Positioned(
              right: -60,
              top: -40,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.12),
                      cs.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            _buildGreeting(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildGreeting(ColorScheme cs) {
    String label;
    String sub;
    switch (_dimension) {
      case TimelineDimension.daily:
        label = DateFormat('yyyy年MM月dd日').format(_selectedDate);
        sub = DateFormat('EEEE', 'zh_CN').format(_selectedDate);
        break;
      case TimelineDimension.weekly:
        final start = _selectedDate.subtract(
            Duration(days: _selectedDate.weekday - 1));
        final end = start.add(const Duration(days: 6));
        label =
        '${DateFormat('MM/dd').format(start)} - ${DateFormat('MM/dd').format(
            end)}';
        sub = '本周回顾';
        break;
      case TimelineDimension.monthly:
        label = DateFormat('yyyy年MM月').format(_selectedDate);
        sub = '月度总结';
        break;
      case TimelineDimension.yearly:
        label = '${_selectedDate.year}年';
        sub = '年度回顾';
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(sub, style: TextStyle(fontSize: 14,
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Serif')),
                if (_dimension != TimelineDimension.daily) ...[
                  const SizedBox(height: 4),
                  Text(
                    _getDateRangeString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _buildDimensionToggle(cs),
                const SizedBox(height: 12),
                Text(
                  _getMotivationText(),
                  style: TextStyle(fontSize: 12,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildNavButton(Icons.chevron_left_rounded, () => _navigate(-1)),
              const SizedBox(width: 8),
              _buildNavButton(Icons.chevron_right_rounded, () => _navigate(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap) {
    final cs = Theme
        .of(context)
        .colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      ),
    );
  }

  void _navigate(int direction) {
    setState(() {
      switch (_dimension) {
        case TimelineDimension.daily:
          _selectedDate = _selectedDate.add(Duration(days: direction));
          break;
        case TimelineDimension.weekly:
          _selectedDate = _selectedDate.add(Duration(days: direction * 7));
          break;
        case TimelineDimension.monthly:
          _selectedDate =
              DateTime(_selectedDate.year, _selectedDate.month + direction, 1);
          break;
        case TimelineDimension.yearly:
          _selectedDate = DateTime(_selectedDate.year + direction, 1, 1);
          break;
      }
    });
    _loadData();
  }

  Widget _buildDimensionToggle(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: TimelineDimension.values.map((d) {
          final isSelected = _dimension == d;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _dimension = d);
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? cs.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected ? [BoxShadow(color: Colors.black
                      .withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                  ] : null,
                ),
                child: Center(
                  child: Text(
                    _getDimensionName(d),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight
                          .normal,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getDimensionName(TimelineDimension d) {
    switch (d) {
      case TimelineDimension.daily:
        return '日';
      case TimelineDimension.weekly:
        return '周';
      case TimelineDimension.monthly:
        return '月';
      case TimelineDimension.yearly:
        return '年';
    }
  }

  Widget _buildDateRangeIndicator(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_rounded, size: 14,
              color: cs.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Text(
            _getDateRangeString(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.primary.withValues(alpha: 0.8),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _getDateRangeString() {
    if (_summary != null && _summary!.actualStartTime != null &&
        _summary!.actualEndTime != null) {
      return '${DateFormat('yyyy.MM.dd').format(
          _summary!.actualStartTime!)} - ${DateFormat('yyyy.MM.dd').format(
          _summary!.actualEndTime!)}';
    }

    DateTime start;
    DateTime end;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day);

    switch (_dimension) {
      case TimelineDimension.daily:
        return DateFormat('yyyy.MM.dd').format(day);
      case TimelineDimension.weekly:
        start = day.subtract(Duration(days: day.weekday - 1));
        end = start.add(const Duration(days: 6));
        final displayEnd = end.isAfter(today) ? today : end;
        return '${DateFormat('yyyy.MM.dd').format(start)} - ${DateFormat(
            'yyyy.MM.dd').format(displayEnd)}';
      case TimelineDimension.monthly:
        start = DateTime(day.year, day.month, 1);
        end = DateTime(day.year, day.month + 1, 0);
        final displayEnd = end.isAfter(today) ? today : end;
        return '${DateFormat('yyyy.MM.dd').format(start)} - ${DateFormat(
            'yyyy.MM.dd').format(displayEnd)}';
      case TimelineDimension.yearly:
        start = DateTime(day.year, 1, 1);
        end = DateTime(day.year, 12, 31);
        final displayEnd = end.isAfter(today) ? today : end;
        return '${DateFormat('yyyy.MM.dd').format(start)} - ${DateFormat(
            'yyyy.MM.dd').format(displayEnd)}';
    }
  }

  Widget _buildStatsOverview(ColorScheme cs, bool isWide) {
    final summary = _summary;
    if (summary == null) return const SizedBox();

    int hours = _totalFocusMinutes ~/ 60;
    int mins = _totalFocusMinutes % 60;
    String focusTimeStr = hours > 0 ? '$hours 小时 $mins 分钟' : '$mins 分钟';
    String topSub = summary.topSubject;
    int subRatio = 0;
    if (summary.subjectDistribution.containsKey(topSub)) {
      double total = summary.subjectDistribution.values.fold(0.0, (a, b) => a + b);
      if (total > 0) subRatio = ((summary.subjectDistribution[topSub]! / total) * 100).toInt();
    }
    
    final overarchingText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('你本阶段累计专注 $focusTimeStr，完成 $_completedCount 个任务。',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 4),
        Text('${summary.peakHour}:00 是你的黄金产出时刻，${topSub != '全能型' ? topSub : '各项事务'} 占据了你 ${subRatio > 0 ? subRatio : (summary.homeworkRatio*100).toInt()}% 的精力。',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 24),
      ],
    );

    Widget statsGrid;
    if (isWide) {
      statsGrid = Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: cs.surfaceContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                  alpha: cs.brightness == Brightness.dark ? 0.2 : 0.03),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
                '专注', '$_totalFocusMinutes', 'min', Icons.spa_outlined,
                cs.primary, cs),
            _buildStatItem(
                '达成', '$_completedCount', '项', Icons.task_alt_rounded,
                cs.secondary, cs),
            _buildStatItem('知识', '${_summary?.searchCount ?? 0}', '次检索',
                Icons.travel_explore_rounded, Colors.indigo, cs),
            _buildStatItem('深度', '${_summary?.deepWorkCount ?? 0}', '次心流',
                Icons.psychology_outlined, Colors.purple, cs),
            _buildStatItem('冲刺', '${_summary?.examPrepCount ?? 0}', '次备考',
                Icons.auto_graph_rounded, Colors.redAccent, cs),
            _buildStatItem(
                '偏好', _topAppCategory ?? '学习', '', Icons.category_outlined,
                Colors.orange, cs),
          ],
        ),
      );
    } else {
      statsGrid = Container(
        padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: cs.brightness == Brightness.dark ? 0.2 : 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                  '专注', '$_totalFocusMinutes', 'min', Icons.spa_outlined,
                  cs.primary, cs),
              _buildStatItem(
                  '达成', '$_completedCount', '项', Icons.task_alt_rounded,
                  cs.secondary, cs),
              _buildStatItem('知识', '${_summary?.searchCount ?? 0}', '次检索',
                  Icons.travel_explore_rounded, Colors.indigo, cs),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                  '深度', '${_summary?.deepWorkCount ?? 0}', '次心流',
                  Icons.psychology_outlined, Colors.purple, cs),
              _buildStatItem(
                  '冲刺', '${_summary?.examPrepCount ?? 0}', '次备考',
                  Icons.auto_graph_rounded, Colors.redAccent, cs),
              _buildStatItem('偏好', _topAppCategory ?? '学习', '', Icons.category_outlined,
                  Colors.orange, cs),
            ],
          ),
        ],
      ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        overarchingText,
        statsGrid,
      ],
    );
  }

  Widget _buildStatItem(String label, String value, String unit, IconData icon,
      Color color, ColorScheme cs) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
              if (unit.isNotEmpty) Text(' $unit', style: TextStyle(fontSize: 10,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
            ],
          ),
          Text(label, style: TextStyle(
              fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineFlow(ColorScheme cs) {
    if (_events.isEmpty) return _buildEmptyState(cs);
    return Column(
        children: _events.map((e) => _buildJournalEntry(e, cs)).toList());
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          '这段时间静悄悄的，\n休息也是为了更好地出发。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildJournalEntry(TimelineEvent event, ColorScheme cs) {
    final timeStr = DateFormat('HH:mm').format(event.timestamp);
    final isImportant = event.type == TimelineEventType.pomodoroEnd ||
        event.type == TimelineEventType.todoCompleted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timeStr, style: TextStyle(fontSize: 12,
              fontFamily: 'monospace',
              color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatEventTitle(event), style: TextStyle(fontSize: 15,
                    fontWeight: isImportant ? FontWeight.w600 : FontWeight
                        .normal,
                    color: cs.onSurface)),
                if (event.subtitle != null) Text(event.subtitle!,
                    style: TextStyle(fontSize: 13,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

    Widget _buildRangeSummary(ColorScheme cs, bool isWide) {
      if (_summary == null) return _buildEmptyState(cs);

      final List<Widget> cards = [
        _buildTrendCard(
          '专注产出',
          '${(_summary!.pomodoroCount)} 次专注',
          '平均每轮 ${_summary!.avgPomodoroMinutes.toStringAsFixed(0)} 分钟',
          Icons.timer_rounded,
          cs.primary,
          cs,
          trend: _summary!.dailyTrend,
          extraItems: _summary!.topFocusSessions.length > 1 ? _summary!
              .topFocusSessions
              .skip(1)
              .take(4)
              .toList()
              .asMap()
              .entries
              .map((e) {
            final session = e.value;
            final dur = session['actual_duration'] as int;
            return _buildRankItem(
                e.key + 2, session['todo_title'] as String? ?? '无题',
                '${dur ~/ 60}m', cs);
          }).toList() : null,
        ),
        _buildStatCard(
          '最长单次专注',
          '${_summary!.longestPomodoroMinutes} 分钟',
          _summary!.longestPomodoroTitle != null ? '专注「${_summary!
              .longestPomodoroTitle}」' : '挑战自我极限',
          Icons.workspace_premium_rounded,
          Colors.amber,
          cs,
          extraItems: _summary!.topFocusSessions.length > 1 ? _summary!
              .topFocusSessions
              .skip(1)
              .take(4)
              .toList()
              .asMap()
              .entries
              .map((e) {
            final session = e.value;
            final dur = session['actual_duration'] as int;
            return _buildRankItem(
                e.key + 2, session['todo_title'] as String? ?? '无题',
                '${dur ~/ 60}m', cs);
          }).toList() : null,
        ),
        _buildStatCard(
          '专注质量',
          '中断率 ${(_summary!.interruptionRate * 100).toStringAsFixed(1)}%',
          '${_summary!.interruptionCount} 次被打断或放弃',
          Icons.shield_moon_rounded,
          Colors.indigo,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            _buildRankItem(0, '深度心流', '${_summary!.deepWorkCount}次', cs),
            _buildRankItem(0, '平均时长', '${_summary!.avgPomodoroMinutes.toStringAsFixed(0)}m', cs),
          ],
        ),
        _buildStatCard(
          '任务执行力',
          '${_summary!.earlyCompletionCount} 项提前完成',
          '逾期任务: ${_summary!.overdueCount} 项',
          Icons.done_all_rounded,
          Colors.green,
          cs,
        ),
        _buildTrendCard(
          '深度工作',
          '${_summary!.deepWorkCount} 次',
          '单次专注超过 45 分钟',
          Icons.bolt_rounded,
          Colors.amber,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            _buildMiniBarChart(
                _summary!.hourlyDistribution.map((v) => v.toDouble()).toList(),
                cs.primary, cs),
          ],
        ),
        if (_summary!.examPrepCount > 0)
          _buildStatCard(
            '备考冲刺波',
            '${_summary!.examPrepCount} 次备考',
            '检测到高强度考试准备',
            Icons.auto_graph_rounded,
            Colors.redAccent,
            cs,
            extraItems: [
              const SizedBox(height: 8),
              ..._summary!.examSubjectDist.entries.take(5).map((e) {
                final maxVal = _summary!.examSubjectDist.values.isNotEmpty 
                    ? _summary!.examSubjectDist.values.reduce(math.max).toDouble() 
                    : 1.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                          Text('${e.value}次', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: maxVal > 0 ? e.value / maxVal : 0,
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                          color: Colors.redAccent,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        _buildStatCard(
          '知识探索',
          '${_summary!.searchCount} 次检索',
          _summary!.topSearchQuery != null ? '最常搜索: ${_summary!
              .topSearchQuery}' : '探索未知的边界',
          Icons.travel_explore_rounded,
          Colors.teal,
          cs,
          extraItems: _summary!.topSearchQueries.take(5).toList().asMap().entries.map((e) {
            final q = e.value;
            return _buildRankItem(e.key + 1, q['query'] as String? ?? '', '${q['freq']}x', cs);
          }).toList(),
        ),
        _buildStatCard(
          '任务构成',
          _summary!.homeworkRatio > 0.4 ? '作业攻坚型' : (_summary!.examRatio >
              0.2 ? '备考冲刺型' : '全面均衡型'),
          '自动识别学习风格',
          Icons.donut_large_rounded,
          Colors.blueGrey,
          cs,
          extraItems: [
            const SizedBox(height: 12),
            SizedBox(
              height: 40, width: 40,
              child: CustomPaint(
                painter: _DonutPainter(
                    [
                      MapEntry('HW', _summary!.homeworkRatio),
                      MapEntry('EX', _summary!.examRatio),
                      MapEntry('OT',
                          (1.0 - _summary!.homeworkRatio - _summary!.examRatio)
                              .clamp(0.0, 1.0)),
                    ],
                    [cs.primary, cs.secondary, cs.outlineVariant]
                ),
              ),
            ),
          ],
        ),
      ];

      final int colCount = isWide ? (MediaQuery
          .of(context)
          .size
          .width > 1200 ? 4 : 3) : 2;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(colCount, (colIndex) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: colIndex == 0 ? 0 : 6,
                right: colIndex == colCount - 1 ? 0 : 6,
              ),
              child: Column(
                children: [
                  for (int i = colIndex; i < cards.length; i += colCount)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: cards[i],
                    ),
                ],
              ),
            ),
          );
        }),
      );
    }

    Widget _buildMiniBarChart(List<double> data, Color color, ColorScheme cs) {
      if (data.isEmpty) return const SizedBox();
      final max = data.reduce((a, b) => a > b ? a : b);
      if (max == 0) return const SizedBox();

      return SizedBox(
          height: 24,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.map((v) =>
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.5),
                    child: Container(
                      height: (v / max) * 24,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                )).toList(),
          )
      );
    }

    Widget _buildTrendCard(String title, String content, String subtitle,
        IconData icon, Color color, ColorScheme cs,
        {List<double>? trend, List<Widget>? extraItems}) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 12),
            if (trend != null && trend.length >= 2) ...[
              SizedBox(
                height: 30,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SparklinePainter(
                      trend, color.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(content, style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 10,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (extraItems != null && extraItems.isNotEmpty) ...[
              const Divider(height: 16, thickness: 0.5),
              ...extraItems,
            ],
          ],
        ),
      );
    }

    Widget _buildStatCard(String title, String content, String subtitle,
        IconData icon, Color color, ColorScheme cs,
        {List<Widget>? extraItems}) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 12),
            Text(content, style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 10,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (extraItems != null && extraItems.isNotEmpty) ...[
              const Divider(height: 16, thickness: 0.5),
              ...extraItems,
            ],
          ],
        ),
      );
    }

    Widget _buildRankItem(int rank, String label, String value,
        ColorScheme cs) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            if (rank > 0) ...[
              Container(
                width: 12,
                height: 12,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('$rank', style: TextStyle(fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurfaceVariant)),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(label,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            Text(value, style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
          ],
        ),
      );
    }
    Widget _buildSideHighlights(ColorScheme cs) {
      if (_summary == null) return const SizedBox();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
              '学习图谱', Icons.auto_awesome_mosaic_rounded, cs),
          const SizedBox(height: 20),
          _buildSubjectDonutChart(cs),
          const SizedBox(height: 40),
          _buildSectionHeader('产出节拍', Icons.query_stats_rounded, cs),
          const SizedBox(height: 20),
          _buildHourlyRhythm(cs),
        ],
      );
    }

    Widget _buildSubjectDonutChart(ColorScheme cs) {
      final dist = _summary!.subjectDistribution;
      if (dist.isEmpty) {
        return Container(
          height: 160,
          alignment: Alignment.center,
          child: Text('暂无分类数据', style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
        );
      }

      final sorted = dist.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final List<Color> palette = [
        cs.primary,
        cs.secondary,
        cs.tertiary,
        cs.errorContainer,
        Colors.orangeAccent,
        Colors.tealAccent,
        Colors.indigoAccent,
        cs.outline,
      ];

      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 140,
              child: Stack(
                children: [
                  Center(
                    child: CustomPaint(
                      size: const Size(120, 120),
                      painter: _DonutPainter(sorted, palette),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(_summary!.pomodoroCount)}',
                          style: const TextStyle(fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1),
                        ),
                        Text(
                          '总项',
                          style: TextStyle(fontSize: 10, color: cs
                              .onSurfaceVariant, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: List.generate(sorted.length, (i) {
                final e = sorted[i];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette[i % palette.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${e.key} ${(e.value * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      );
    }

    Widget _buildHourlyRhythm(ColorScheme cs) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withValues(alpha: 0.1),
              cs.secondary.withValues(alpha: 0.1)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 28),
            const SizedBox(height: 12),
            Text('${_getPeriodName()}黄金活跃期', style: TextStyle(fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _buildHourlyChart(
                _summary!.hourlyDistribution, _summary!.peakHour, cs),
            const SizedBox(height: 16),
            Text('${_summary!.peakHour}:00 为巅峰时刻', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
            const SizedBox(height: 8),
            Text('在此期间你的效率最高\n建议安排最具挑战的任务',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    height: 1.4)),
          ],
        ),
      );
    }

    Widget _buildHourlyChart(List<int> distribution, int peakHour,
        ColorScheme cs) {
      if (distribution.isEmpty) return const SizedBox(height: 60);

      final int maxVal = distribution.reduce((a, b) => a > b ? a : b);
      if (maxVal == 0) return const SizedBox(height: 60);

      return SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(24, (i) {
            final h = distribution[i];
            final bool isPeak = i == peakHour;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  height: (h / maxVal) * 60,
                  decoration: BoxDecoration(
                    color: isPeak ? cs.primary : cs.primary.withValues(
                        alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }),
        ),
      );
    }

    Widget _buildSectionHeader(String title, IconData icon, ColorScheme cs) {
      return Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      );
    }
    String _getPeriodName() {
      switch (_dimension) {
        case TimelineDimension.daily:
          return '今日';
        case TimelineDimension.weekly:
          return '本周';
        case TimelineDimension.monthly:
          return '本月';
        case TimelineDimension.yearly:
          return '今年';
      }
      return '';
    }

    Widget _buildReflection(ColorScheme cs) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(Icons.format_quote_rounded,
                color: cs.primary.withValues(alpha: 0.3), size: 40),
            const SizedBox(height: 16),
            Text(
              _getReflectionText(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.8,
                fontFamily: 'Serif',
                color: cs.onSurface.withValues(alpha: 0.8),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),
            Text('— 时光记录员', style: TextStyle(fontSize: 12,
                color: cs.primary.withValues(alpha: 0.5),
                letterSpacing: 2)),
          ],
        ),
      );
    }

    String _formatEventTitle(TimelineEvent event) {
      final int seed = event.id.hashCode;
      final String sub = (event.subtitle ?? '').toLowerCase();

      String pick(List<String> options) => options[seed % options.length];

      // Keyword detection
      final bool isHomework = sub.contains('作业') || sub.contains('练习') ||
          sub.contains('刷题');
      final bool isExam = sub.contains('考试') || sub.contains('测验') ||
          sub.contains('考证') || sub.contains('竞赛');
      final bool isReview = sub.contains('复习') || sub.contains('总结') ||
          sub.contains('整理') || sub.contains('笔记');
      final bool isReading = sub.contains('阅读') || sub.contains('看书') ||
          sub.contains('读书') || sub.contains('文献');

      switch (event.type) {
        case TimelineEventType.pomodoroStart:
          if (isHomework) return pick([
            '开启作业攻坚模式',
            '开始在题海中远航',
            '正在消灭今日作业',
            '笔尖下的专注力',
            '让作业也变成享受'
          ]);
          if (isExam) return pick([
            '进入考前冲刺状态',
            '模拟实战，严阵以待',
            '为了那个目标，出发',
            '正在构建知识盔甲',
            '考场如战场，此刻亮剑'
          ]);
          if (isReview) return pick([
            '温故而知新',
            '梳理凌乱的思想',
            '搭建知识的脚手架',
            '让记忆变得更深邃',
            '正在进行深度总结'
          ]);
          if (isReading) return pick([
            '潜入书香的世界',
            '跨越时空的对话',
            '在文字间寻找答案',
            '静心享受阅读时光',
            '开启心灵的洗礼'
          ]);
          return pick([
            '开启了专注之旅',
            '让世界安静下来',
            '潜入思考的深处',
            '专注于当下的美好',
            '启动高效引擎',
            '此刻，唯有专注',
            '与目标同行',
            '听，是专注的声音',
            '开始雕琢时光',
            '进入心流频道'
          ]);

        case TimelineEventType.pomodoroEnd:
          if (isHomework) return pick([
            '搞定了！离完成又近一步',
            '笔耕不辍，收获满满',
            '又攻克了一道难题',
            '让作业见证你的成长',
            '今日份作业能量注入完毕'
          ]);
          if (isExam) return pick([
            '离梦想的终点更近了',
            '多一分专注，多一分底气',
            '胜算在一点点积攒',
            '你的努力，必有回响',
            '为了那张完美的答卷'
          ]);
          if (isReview) return pick([
            '知识点已经刻入脑海',
            '思想变得更加清晰',
            '又完成了一次查漏补缺',
            '梳理，是为了更好的出发',
            '收获了成长的复利'
          ]);
          if (isReading) return pick([
            '收获了文字的芬芳',
            '拓宽了生命的维度',
            '与作者共鸣的瞬间',
            '知识的种子正在发芽',
            '精神世界又丰盈了一些'
          ]);
          return pick([
            '收获了专注的果实',
            '完成了一次深呼吸',
            '时光不负苦心人',
            '专注画上圆满句号',
            '又一次战胜了分心',
            '内心的充盈感',
            '让努力被看见',
            '合上专注的篇章',
            '达成一次深度连接',
            '汗水凝结成光'
          ]);

        case TimelineEventType.todoCreated:
          return pick([
            '播种了一个新希望',
            '建立了奋斗的目标',
            '写下未来的约定',
            '开启新任务的挑战',
            '清单上的新成员',
            '勾勒成长的蓝图',
            '给未来一个交代',
            '新的旅程由此开始',
            '记录下这一刻的灵感',
            '待办项+1'
          ]);

        case TimelineEventType.todoCompleted:
          if (isHomework) return pick([
            '彻底消灭了这项作业',
            '作业清单-1，快乐值+1',
            '笔尖圆满收官',
            '让成就感在纸面跳跃',
            '搞定，今晚可以睡个好觉'
          ]);
          if (isExam) return pick([
            '这是一次漂亮的突围',
            '又翻过了一座大山',
            '离证书/高分又近了',
            '为这场博弈画上句号',
            '你是自己的冠军'
          ]);
          return pick([
            '达成了一个小目标',
            '划掉了一个烦恼',
            '离梦想又近了一步',
            '又一个目标被征服',
            '完美的句点',
            '成就感满满',
            '坚持终有回响',
            '实力证明了自己',
            '完成，是最好的奖励',
            '给努力一个回馈'
          ]);

        case TimelineEventType.courseStart:
          return pick([
            '步入知识的殿堂',
            '与智慧有个约会',
            '课堂，是成长的阶梯',
            '吸收新知识的养分',
            '聆听思想的碰撞',
            '在学海中起航',
            '开启学术模式',
            '知识点正在加载',
            '拓宽认知的边界',
            '在课堂遇见更好的自己'
          ]);
        case TimelineEventType.searchQuery:
          return '探索：${event.subtitle}';
        default:
          return event.title;
      }
    }

    String _getReflectionText() {
      final int seed = _selectedDate.day + _selectedDate.month +
          _selectedDate.year + _dimension.index;
      String pick(List<String> options) => options[seed % options.length];

      if (_totalFocusMinutes == 0) {
        return pick([
          "有时候，静谧的休息也是一种力量。\n在无声的岁月里，\n愿你正温柔地积蓄着光芒。",
          "暂时的停歇，是为了跳得更高。\n给自己一点温柔，\n明天又是全新的开始。",
          "今天的留白，是为了画出更美的未来。\n好好休息，也是一种自律。",
          "允许自己偶尔的‘无所事事’，\n在忙碌的世界里，\n找回那份宁静的初衷。",
          "晚风微凉，生活很长。\n愿你今晚有个好梦，\n积攒满格的勇气。",
          "不去追赶时间，让时间来拥抱你。\n今天的寂静，是成长的呼吸。",
          "慢下来，听听内心的声音。\n不焦虑，不盲从，\n在节奏中寻找平衡。",
          "生活不只有冲刺，还有漫步。\n愿你在休息中，\n发现平凡日子里的光。",
          "累了就停下，这并不代表放弃。\n在独处的时光里，\n你是自由且完整的。",
          "收起行囊，在港湾里泊靠。\n愿明日的阳光，\n能照进你充满力量的梦。"
        ]);
      }

      if (_dimension == TimelineDimension.daily) {
        return pick([
          "专注的灵魂最动人，\n你与目标同行的身影，\n是今日最美的风景。",
          "哪怕只是微小的进步，\n也值得被温柔以待。\n每一分钟的努力，\n都在折射未来的光。",
          "今日的汗水，\n会化作明日的星辰。\n感谢你如此坚定地走在路上。",
          "世界喧嚣，你自清欢。\n在这一份专注里，\n你找到了自己的宇宙。",
          "每一个番茄钟的滴答声，\n都是梦想在敲门。\n你离未来，又近了一些。",
          "你是时间的雕刻师，\n用专注打磨着平凡的日常。\n今日的收获，沉甸甸且珍贵。",
          "不积跬步，无以至千里。\n你走的每一步，\n都有其不可替代的意义。",
          "愿这一份充实，\n能化作今晚香甜的睡眠。\n你值得所有的赞美。",
          "在这段旅程中，\n你既是行者，也是光。\n照亮了属于自己的坚持。",
          "完成比完美更重要，\n而你今天做得如此出色。\n请继续保持这份热爱。"
        ]);
      }

      return pick([
        "这一阶段的奔波与坚持，\n终将汇成成长的河流。\n感谢那个从不轻言放弃的自己。",
        "月盈月亏，岁月流转，\n你的足迹清晰而坚定。\n愿接下来的日子，能遇见更好的风景。",
        "年岁序展，光阴如梭，\n这一段的努力，\n已写就最动人的篇章。",
        "回头望去，那是你亲手耕耘出的绿洲。\n在这段时间里，\n你证明了自己的韧性。",
        "每一次攀登都值得铭记，\n每一个高度都是新的起点。\n愿你心怀热望，步履不停。",
        "时光不会遗忘每一滴汗水，\n空间会记住每一次专注。\n这一份总结，是你最好的勋章。",
        "在变幻的世界里，\n守住了一份不变的坚持。\n你比想象中更加强大。",
        "愿这段时间的沉淀，\n能化作你厚积薄发的底气。\n未来已来，不惧挑战。",
        "每一次总结，都是为了更好的出发。\n整理好心情，\n去迎接下一场山海。",
        "你的努力，藏在每一个被勾掉的待办里。\n它们聚沙成塔，\n终将铸就你的不凡。"
      ]);
    }

    String _getMotivationText() {
      final int seed = _selectedDate.day + _selectedDate.month +
          _selectedDate.year;
      String pick(List<String> options) => options[seed % options.length];

      return pick([
        "专注当下，便是对未来最好的期许。",
        "点滴积累，终将汇成璀璨星河。",
        "坚持的每一天，都在定义全新的你。",
        "岁月的厚重，藏在每一个奋斗的瞬间。",
        "不焦虑未来，不沉溺过去，只深耕现在。",
        "每一个伟大的成就，都源于一次小小的专注。",
        "向着光生长，哪怕缓慢，也要坚定。",
        "愿你心如明镜，在专注中见众生，见自己。",
        "时间对每个人都是公平的，专注让它更有价值。",
        "既然选择了远方，便只顾风雨兼程。",
        "在这一秒，做最好的自己。",
        "平凡的日常里，也藏着不凡的英雄梦想。"
      ]);
    }
  }

  class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, double>> data;
  final List<Color> palette;

  _DonutPainter(this.data, this.palette);

  @override
  void paint(Canvas canvas, Size size) {
  final center = Offset(size.width / 2, size.height / 2);
  final radius = size.width / 2;
  final strokeWidth = radius * 0.35;
  final paint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = strokeWidth
  ..strokeCap = StrokeCap.round;

  double startAngle = -3.14159 / 2;
  for (int i = 0; i < data.length; i++) {
  final sweepAngle = data[i].value * 2 * 3.14159;
  paint.color = palette[i % palette.length];

  // Draw arc with slight gap
  canvas.drawArc(
  Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
  startAngle + 0.05,
  sweepAngle - 0.1,
  false,
  paint,
  );
  startAngle += sweepAngle;
  }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
  }

  class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
  if (data.length < 2) return;

  final paint = Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2.5
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

  final path = Path();
  final double maxVal = data.reduce((a, b) => a > b ? a : b);
  final double minVal = data.reduce((a, b) => a < b ? a : b);
  final double range = (maxVal - minVal).clamp(1.0, double.infinity);

  final double stepX = size.width / (data.length - 1);

  for (int i = 0; i < data.length; i++) {
  final x = i * stepX;
  final y = size.height - ((data[i] - minVal) / range * size.height);
  if (i == 0) {
  path.moveTo(x, y);
  } else {
  path.lineTo(x, y);
  }
  }

  canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
  }