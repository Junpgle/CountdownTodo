import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/course_screens.dart';
import '../screens/pomodoro_screen.dart';
import '../services/pomodoro_service.dart';
import '../utils/app_image_filters.dart';
import '../utils/page_transitions.dart';
import '../utils/theme_color_tokens.dart';
import 'optional_liquid_glass_surface.dart';
import 'platform_backdrop_filter.dart';

// ============================================================
// 首页「最近专注」一体化液态毛玻璃卡片
// ============================================================
class PomodoroTodaySection extends StatefulWidget {
  final String username;
  final bool isLight;

  /// 每次自增时触发重新加载（由首页 resumed 回调驱动）
  final int refreshTrigger;

  /// 点击进入统计看板的回调
  final VoidCallback? onTap;

  const PomodoroTodaySection({
    super.key,
    required this.username,
    this.isLight = false,
    this.refreshTrigger = 0,
    this.onTap,
  });

  @override
  State<PomodoroTodaySection> createState() => _PomodoroTodaySectionState();
}

class _PomodoroTodaySectionState extends State<PomodoroTodaySection>
    with SingleTickerProviderStateMixin {
  final GlobalKey _cardKey = GlobalKey();
  List<PomodoroRecord> _records = [];
  final Map<String, GlobalKey> _recordCardKeys = {};
  bool _loading = true;
  bool _collapsed = false;
  bool _showAllRecords = false;
  bool _isToday = true;
  int _totalSeconds = 0;
  int _yesterdaySeconds = 0;
  int _completedCount = 0;
  int _maxDuration = 0;
  List<int> _hourlySeconds = List<int>.filled(24, 0);
  int _maxHourlySeconds = 0;
  int? _selectedHour;
  late AnimationController _chartAnimationController;
  final Map<(String?, String), DateFormat> _dateFormatters = {};

  /// 每日建议专注标准基准（2 小时 = 7200 秒，供环形进度条参考）
  static const int _dailyFocusTargetSeconds = 7200;

  DateFormat _cachedDateFormat(String pattern) {
    final locale = Intl.defaultLocale;
    return _dateFormatters.putIfAbsent((
      locale,
      pattern,
    ), () => DateFormat(pattern, locale));
  }

  @override
  void initState() {
    super.initState();
    _chartAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _loadData();
  }

  @override
  void didUpdateWidget(PomodoroTodaySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _chartAnimationController.dispose();
    super.dispose();
  }

  /// 只读本地数据（云端同步由首页统一负责）
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final todayRecords = await PomodoroService.getTodayRecords();
      final yesterdayRecords = await PomodoroService.getYesterdayRecords();
      if (!mounted) return;

      var yesterdaySeconds = 0;
      for (final r in yesterdayRecords) {
        yesterdaySeconds += r.effectiveDuration;
      }

      final bool isToday;
      final List<PomodoroRecord> records;
      if (todayRecords.isNotEmpty) {
        isToday = true;
        records = todayRecords;
      } else if (yesterdayRecords.isNotEmpty) {
        isToday = false;
        records = yesterdayRecords;
      } else {
        isToday = true;
        records = const [];
      }

      final DateTime targetDate;
      if (records.isNotEmpty) {
        final firstLocal = DateTime.fromMillisecondsSinceEpoch(
          records.first.startTime,
          isUtc: true,
        ).toLocal();
        targetDate = DateTime(
          firstLocal.year,
          firstLocal.month,
          firstLocal.day,
        );
      } else {
        targetDate = DateTime.now();
      }

      final hourlySeconds = List<int>.filled(24, 0);
      var totalSeconds = 0;
      var completedCount = 0;
      var maxDuration = 0;

      for (final record in records) {
        final duration = record.effectiveDuration;
        totalSeconds += duration;
        if (record.isCompleted) completedCount++;
        if (duration > maxDuration) maxDuration = duration;

        _distributeRecordToHours(
          record: record,
          targetDate: targetDate,
          hourlySeconds: hourlySeconds,
        );
      }

      final maxHourlySeconds = hourlySeconds.reduce(max);
      final activeRecordUuids = records.map((record) => record.uuid).toSet();
      _recordCardKeys.removeWhere(
        (uuid, _) => !activeRecordUuids.contains(uuid),
      );

      setState(() {
        _records = records;
        _isToday = isToday;
        _totalSeconds = totalSeconds;
        _yesterdaySeconds = yesterdaySeconds;
        _completedCount = completedCount;
        _maxDuration = maxDuration;
        _hourlySeconds = hourlySeconds;
        _maxHourlySeconds = maxHourlySeconds;
        _selectedHour = null;
        _loading = false;
      });

      _chartAnimationController.forward(from: 0.0);
    } catch (e, stack) {
      debugPrint('PomodoroTodaySection _loadData error: $e\n$stack');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 将单条专注记录的时长精确切分到当天的 24 个小时区间中（避免跨时段记录仅点亮开始时段）
  static void _distributeRecordToHours({
    required PomodoroRecord record,
    required DateTime targetDate,
    required List<int> hourlySeconds,
  }) {
    final duration = record.effectiveDuration;
    if (duration <= 0) return;

    final dayStart = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));
    final dayStartMs = dayStart.millisecondsSinceEpoch;
    final dayEndMs = dayEnd.millisecondsSinceEpoch;

    final sessionStartMs = record.startTime;
    final sessionEndMs =
        (record.endTime != null && record.endTime! > record.startTime)
        ? record.endTime!
        : record.startTime + duration * 1000;

    if (sessionEndMs <= sessionStartMs) {
      final startLocal = DateTime.fromMillisecondsSinceEpoch(sessionStartMs)
          .toLocal();
      if (startLocal.year == targetDate.year &&
          startLocal.month == targetDate.month &&
          startLocal.day == targetDate.day &&
          startLocal.hour >= 0 &&
          startLocal.hour < 24) {
        hourlySeconds[startLocal.hour] = min(
          3600,
          hourlySeconds[startLocal.hour] + duration,
        );
      }
      return;
    }

    final activeIntervals = <({int start, int end})>[];
    final pauses = record.pauseIntervals ?? const [];

    if (pauses.isEmpty) {
      activeIntervals.add((start: sessionStartMs, end: sessionEndMs));
    } else {
      var cursor = sessionStartMs;
      final sortedPauses = List<PauseInterval>.from(pauses)
        ..sort((a, b) => a.startMs.compareTo(b.startMs));

      for (final p in sortedPauses) {
        final pStart = p.startMs.clamp(sessionStartMs, sessionEndMs);
        final rawEnd = p.endMs ?? sessionEndMs;
        final pEnd = rawEnd.clamp(sessionStartMs, sessionEndMs);
        if (pStart > cursor) {
          activeIntervals.add((start: cursor, end: pStart));
        }
        if (pEnd > cursor) {
          cursor = pEnd;
        }
      }
      if (cursor < sessionEndMs) {
        activeIntervals.add((start: cursor, end: sessionEndMs));
      }
    }

    for (final interval in activeIntervals) {
      final validStartMs = max(interval.start, dayStartMs);
      final validEndMs = min(interval.end, dayEndMs);
      if (validEndMs <= validStartMs) continue;

      for (var h = 0; h < 24; h++) {
        final hStartMs = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          h,
        ).millisecondsSinceEpoch;
        final hEndMs = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          h + 1,
        ).millisecondsSinceEpoch;

        final overlapStart = max(validStartMs, hStartMs);
        final overlapEnd = min(validEndMs, hEndMs);
        if (overlapEnd > overlapStart) {
          final overlapSec = (overlapEnd - overlapStart) ~/ 1000;
          hourlySeconds[h] = min(3600, hourlySeconds[h] + overlapSec);
        }
      }
    }
  }

  GlobalKey _recordCardKeyFor(String recordUuid) =>
      _recordCardKeys.putIfAbsent(recordUuid, GlobalKey.new);

  Future<void> _openPomodoroWorkbench() async {
    await PageTransitions.pushFromRect(
      context: context,
      page: PomodoroScreen(username: widget.username, initialTab: 0),
      sourceKey: _cardKey,
      placeholderIcon: Icons.timer_rounded,
    );
    if (mounted) {
      _loadData();
    }
  }

  Widget _buildGlassCard({
    required double borderRadius,
    required Decoration fallbackDecoration,
    required Widget child,
    EdgeInsetsGeometry? padding,
    AlignmentGeometry? alignment,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final card = OptionalLiquidGlassCard(
      borderRadius: borderRadius,
      padding: padding,
      alignment: alignment,
      tint: colorScheme.primary.withValues(alpha: 0.16),
      isDark: isDark,
      fallbackDecoration: fallbackDecoration,
      child: child,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: PlatformBackdropFilter(
        filter: AppImageFilters.blur10,
        bypassWhenLiquidGlassEnabled: true,
        child: card,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final useLightHeader = isDark || widget.isLight;
    final headerTextColor = useLightHeader ? Colors.white : null;
    final headerSubColor = useLightHeader
        ? Colors.white.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 顶部区域标题栏 ──
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: widget.isLight
                            ? Colors.white.withValues(alpha: 0.15)
                            : colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.donut_large_rounded,
                        size: 20,
                        color: widget.isLight
                            ? Colors.white
                            : colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '最近专注',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: headerTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 今日 / 昨日 标签
              if (!_loading)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: useLightHeader
                        ? Colors.white.withValues(alpha: 0.2)
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isToday ? '今日' : '昨日',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: useLightHeader
                          ? Colors.white
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              const Spacer(),
              // 跳转统计看板箭头（与其他板块统一）
              if (widget.onTap != null)
                GestureDetector(
                  key: const ValueKey<String>('pomodoro-stats-btn'),
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: headerSubColor,
                    ),
                  ),
                ),
              // 折叠 / 展开切换（与其他板块统一）
              if (_records.isNotEmpty)
                GestureDetector(
                  key: const ValueKey<String>('pomodoro-toggle-collapse-btn'),
                  onTap: () => setState(() => _collapsed = !_collapsed),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _collapsed
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 20,
                      color: headerSubColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // ── 一体化液态毛玻璃卡片 ──
        Container(key: _cardKey, child: _buildUnifiedCard(colorScheme, isDark)),
      ],
    );
  }

  Widget _buildUnifiedCard(ColorScheme colorScheme, bool isDark) {
    final fallbackDecoration = BoxDecoration(
      color: widget.isLight
          ? (isDark
              ? colorScheme.surfaceContainerLow.withValues(alpha: 0.75)
              : colorScheme.surface.withValues(alpha: 0.92))
          : (isDark
                ? colorScheme.surfaceContainerLow.withValues(alpha: 0.7)
                : colorScheme.surface),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: widget.isLight ? 0.08 : (isDark ? 0.2 : 0.04),
          ),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(
        color: widget.isLight
            ? (isDark
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.6))
            : colorScheme.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.4),
      ),
    );

    return _buildGlassCard(
      borderRadius: 24,
      fallbackDecoration: fallbackDecoration,
      padding: const EdgeInsets.all(18),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
            )
          : _records.isEmpty
          ? _buildEmptyState(colorScheme, isDark)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 核心数据与环形概览
                _buildCoreMetrics(colorScheme, isDark),

                // 2. 详情内容（折叠时平滑隐藏）
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: _collapsed
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Divider(
                                height: 1,
                                thickness: 0.8,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : colorScheme.outlineVariant.withValues(
                                        alpha: 0.35,
                                      ),
                              ),
                            ),
                            // 24小时时段分布柱状图
                            _buildHourlyChart(colorScheme, isDark),

                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Divider(
                                height: 1,
                                thickness: 0.8,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : colorScheme.outlineVariant.withValues(
                                        alpha: 0.35,
                                      ),
                              ),
                            ),
                            // 专注明细列表
                            _buildRecordsList(colorScheme, isDark),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  // ==========================================
  // 核心数据与环形概览
  // ==========================================
  Widget _buildCoreMetrics(ColorScheme colorScheme, bool isDark) {
    return Row(
      children: [
        // 环形进度圈
        _buildFocusRing(colorScheme, isDark),
        const SizedBox(width: 16),
        // 核心数值与对比信息
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 时长数值 + 较昨日对比胶囊
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _buildDurationDisplay(colorScheme),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTrendBadge(colorScheme, isDark),
                ],
              ),
              const SizedBox(height: 8),
              // 指标胶囊排布
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildMetricChip(
                    icon: Icons.check_circle_outline_rounded,
                    label: '$_completedCount 次完成',
                    colorScheme: colorScheme,
                    isDark: isDark,
                  ),
                  _buildMetricChip(
                    icon: Icons.timelapse_rounded,
                    label:
                        '均次 ${formatDurationChinese(_records.isEmpty ? 0 : _totalSeconds ~/ _records.length)}',
                    colorScheme: colorScheme,
                    isDark: isDark,
                  ),
                  if (_maxDuration > 0)
                    _buildMetricChip(
                      icon: Icons.timer_outlined,
                      label: '最长 ${formatDurationChinese(_maxDuration)}',
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFocusRing(ColorScheme colorScheme, bool isDark) {
    final progress = _totalSeconds / _dailyFocusTargetSeconds;
    final primaryColor = colorScheme.primary;
    final tertiaryColor = colorScheme.tertiary;

    return SizedBox(
      width: 68,
      height: 68,
      child: AnimatedBuilder(
        animation: _chartAnimationController,
        builder: (context, _) {
          final animatedProgress = progress * _chartAnimationController.value;
          final percent = (animatedProgress * 100).toInt();

          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(68, 68),
                painter: _FocusRingPainter(
                  progress: animatedProgress,
                  trackColor: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : primaryColor.withValues(alpha: 0.12),
                  gradientColors: [
                    primaryColor.withValues(alpha: 0.8),
                    tertiaryColor,
                  ],
                  overflowColor: Colors.amber,
                  strokeWidth: 6.0,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    animatedProgress >= 1.0
                        ? Icons.check_rounded
                        : Icons.timer_rounded,
                    size: 18,
                    color: animatedProgress >= 1.0
                        ? (isDark ? Colors.greenAccent : colorScheme.cdtSuccess)
                        : primaryColor,
                  ),
                  Text(
                    animatedProgress >= 1.0 ? '100%+' : '$percent%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: animatedProgress >= 1.0
                          ? (isDark
                                ? Colors.greenAccent
                                : colorScheme.cdtSuccess)
                          : (isDark
                                ? Colors.white70
                                : colorScheme.onSurfaceVariant),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDurationDisplay(ColorScheme colorScheme) {
    if (_totalSeconds >= 3600) {
      final h = _totalSeconds ~/ 3600;
      final m = (_totalSeconds % 3600) ~/ 60;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$h',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
                letterSpacing: -0.5,
              ),
            ),
            TextSpan(
              text: ' 时 ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (m > 0) ...[
              TextSpan(
                text: '$m',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: ' 分',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    } else if (_totalSeconds >= 60) {
      final m = _totalSeconds ~/ 60;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$m',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
                letterSpacing: -0.5,
              ),
            ),
            TextSpan(
              text: ' 分钟',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    } else {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$_totalSeconds',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
                letterSpacing: -0.5,
              ),
            ),
            TextSpan(
              text: ' 秒',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildTrendBadge(ColorScheme colorScheme, bool isDark) {
    if (_isToday) {
      if (_yesterdaySeconds > 0) {
        final diff = _totalSeconds - _yesterdaySeconds;
        if (diff > 0) {
          final successColor = isDark
              ? Colors.greenAccent
              : colorScheme.cdtSuccess;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: successColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.trending_up_rounded, size: 13, color: successColor),
                const SizedBox(width: 3),
                Text(
                  '+${formatDurationCompact(diff)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: successColor,
                  ),
                ),
              ],
            ),
          );
        } else if (diff < 0) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.trending_down_rounded,
                  size: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Text(
                  '-${formatDurationCompact(-diff)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        } else {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '持平昨日',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          );
        }
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '今日专注',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        );
      }
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.secondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '昨日记录',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: colorScheme.secondary,
          ),
        ),
      );
    }
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isDark ? Colors.white70 : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 24小时分布时段柱状图
  // ==========================================
  Widget _buildHourlyChart(ColorScheme colorScheme, bool isDark) {
    final hourlySeconds = _hourlySeconds;
    final maxSeconds = _maxHourlySeconds;
    final primaryColor = colorScheme.primary;
    final currentHour = DateTime.now().hour;

    var peakHour = 0;
    if (maxSeconds > 0) {
      peakHour = hourlySeconds.indexOf(maxSeconds);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部说明与提示
        Row(
          children: [
            Text(
              '时段分布',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _selectedHour != null
                      ? Container(
                          key: ValueKey('sel_$_selectedHour'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '${_selectedHour!.toString().padLeft(2, '0')}:00 - ${((_selectedHour! + 1) % 24).toString().padLeft(2, '0')}:00 · ${formatDurationChinese(hourlySeconds[_selectedHour!])}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        )
                      : maxSeconds > 0
                      ? Container(
                          key: const ValueKey('peak_badge'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.trending_up_rounded,
                                size: 13,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '峰值 ${peakHour.toString().padLeft(2, '0')}:00 (${formatDurationCompact(maxSeconds)})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white70
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 24 小时柱状图
        SizedBox(
          height: 76,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (index) {
              final sec = hourlySeconds[index];
              final factor = maxSeconds == 0 ? 0.0 : sec / maxSeconds;
              final isCurrent = _isToday && index == currentHour;
              final isSelected = _selectedHour == index;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.2),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _selectedHour = (_selectedHour == index) ? null : index;
                      });
                    },
                    child: Column(
                      children: [
                        // 柱体与轨道
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.18)
                                  : isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : colorScheme.onSurface.withValues(
                                      alpha: 0.04,
                                    ),
                              borderRadius: BorderRadius.circular(4),
                              border: isSelected
                                  ? Border.all(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.6,
                                      ),
                                    )
                                  : null,
                            ),
                            alignment: Alignment.bottomCenter,
                            child: AnimatedBuilder(
                              animation: _chartAnimationController,
                              builder: (context, _) {
                                final animatedFactor =
                                    factor * _chartAnimationController.value;
                                if (animatedFactor <= 0) {
                                  return const SizedBox.shrink();
                                }
                                return FractionallySizedBox(
                                  heightFactor: max(animatedFactor, 0.08),
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: isSelected
                                            ? [
                                                colorScheme.tertiary,
                                                colorScheme.primary,
                                              ]
                                            : [
                                                primaryColor.withValues(
                                                  alpha: 0.6,
                                                ),
                                                primaryColor,
                                              ],
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: primaryColor.withValues(
                                                  alpha: 0.4,
                                                ),
                                                blurRadius: 4,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 当前小时提示点或空白
                        SizedBox(
                          height: 5,
                          child: Center(
                            child: isCurrent
                                ? Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // 时间刻度轴
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ChartTimeMark(label: '00:00'),
              _ChartTimeMark(label: '06:00'),
              _ChartTimeMark(label: '12:00'),
              _ChartTimeMark(label: '18:00'),
              _ChartTimeMark(label: '24:00'),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 番茄钟记录明细列表
  // ==========================================
  Widget _buildRecordsList(ColorScheme colorScheme, bool isDark) {
    final timeFormat = _cachedDateFormat('HH:mm');
    final displayRecords = _showAllRecords
        ? _records
        : _records.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '专注明细',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_records.length}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const Spacer(),
            if (widget.onTap != null)
              GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '完整看板',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...displayRecords.map(
          (r) => _buildRecordItem(r, timeFormat, colorScheme, isDark),
        ),
        if (_records.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _showAllRecords = !_showAllRecords);
                },
                icon: Icon(
                  _showAllRecords
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                ),
                label: Text(
                  _showAllRecords ? '收起明细' : '展开其余 ${_records.length - 3} 条明细',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecordItem(
    PomodoroRecord record,
    DateFormat timeFormat,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final startLocal = DateTime.fromMillisecondsSinceEpoch(
      record.startTime,
      isUtc: true,
    ).toLocal();
    final durationMin = record.effectiveDuration ~/ 60;
    final isCompleted = record.isCompleted;
    final statusColor = isCompleted
        ? (isDark ? Colors.greenAccent : colorScheme.cdtSuccess)
        : (isDark ? Colors.amber : colorScheme.cdtWarning);
    final hasPause = (record.totalPauseSeconds ?? 0) > 0;
    final cardKey = _recordCardKeyFor(record.uuid);

    return Padding(
      key: ValueKey(record.uuid),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            PageTransitions.pushFromRect(
              context: context,
              page: PomodoroDetailScreen(record: record, tags: const []),
              sourceKey: cardKey,
              sourceBorderRadius: const BorderRadius.all(Radius.circular(12)),
            );
          },
          child: Container(
            key: cardKey,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                // 状态圆形徽章
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCompleted ? Icons.check_rounded : Icons.timer_off_rounded,
                    size: 15,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 10),
                // 记录内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            timeFormat.format(startLocal),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            ' · $durationMin 分钟',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                          if (!isCompleted)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                '提前结束',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (record.todoTitle != null &&
                          record.todoTitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.check_box_outlined,
                              size: 11,
                              color: isDark
                                  ? Colors.white54
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                record.todoTitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white70
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // 暂停时长标签
                if (hasPause) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.orange : colorScheme.cdtWarning)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '暂停 ${formatDurationChinese(record.totalPauseSeconds ?? 0)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.orange : colorScheme.cdtWarning,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: isDark
                      ? Colors.white38
                      : colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 空状态展示
  // ==========================================
  Widget _buildEmptyState(ColorScheme colorScheme, bool isDark) {
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.hourglass_empty_rounded,
              size: 26,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '暂无专注记录',
            style: TextStyle(
              color: isDark ? Colors.white : colorScheme.onSurface,
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '保持心流，立即开启你的第一个番茄钟吧！',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: subColor,
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openPomodoroWorkbench,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('开启今日专注'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 专注环形进度 Painter
// ============================================================
class _FocusRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final List<Color> gradientColors;
  final Color? overflowColor;
  final double strokeWidth;

  _FocusRingPainter({
    required this.progress,
    required this.trackColor,
    required this.gradientColors,
    this.overflowColor,
    this.strokeWidth = 6.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 1. 底层轨道圆环
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0.001) return;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // 2. 基础进度弧线（最大 1.0）
    final baseProgress = progress.clamp(0.0, 1.0);
    final baseSweep = 2 * pi * baseProgress;

    final basePaint = Paint()
      ..shader = SweepGradient(colors: gradientColors).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-pi / 2);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawArc(rect, 0, baseSweep, false, basePaint);
    canvas.restore();

    // 3. 超额达成金色弧线（progress > 1.0）
    if (progress > 1.0 && overflowColor != null) {
      final overflowProgress = (progress - 1.0).clamp(0.0, 1.0);
      final overflowSweep = 2 * pi * overflowProgress;
      final overflowPaint = Paint()
        ..color = overflowColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-pi / 2);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawArc(rect, 0, overflowSweep, false, overflowPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.overflowColor != overflowColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

// ============================================================
// 柱状图时间刻度文本
// ============================================================
class _ChartTimeMark extends StatelessWidget {
  final String label;

  const _ChartTimeMark({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: isDark
            ? Colors.white.withValues(alpha: 0.4)
            : Theme.of(context).colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.6),
      ),
    );
  }
}
