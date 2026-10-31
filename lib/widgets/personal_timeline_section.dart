import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/personal_timeline_screen.dart';
import '../services/timeline_service.dart';
import '../utils/app_image_filters.dart';
import '../utils/page_transitions.dart';
import '../utils/theme_color_tokens.dart';
import '../utils/time_utils.dart';
import 'optional_liquid_glass_surface.dart';
import 'platform_backdrop_filter.dart';

// ============================================================
// 首页「个人时间轴」微型时光流液态毛玻璃卡片
// ============================================================
class PersonalTimelineSection extends StatefulWidget {
  final String username;
  final bool isLight;
  final int refreshTrigger;
  final VoidCallback? onTap;

  const PersonalTimelineSection({
    super.key,
    required this.username,
    this.isLight = false,
    this.refreshTrigger = 0,
    this.onTap,
  });

  @override
  State<PersonalTimelineSection> createState() =>
      _PersonalTimelineSectionState();
}

class _PersonalTimelineSectionState extends State<PersonalTimelineSection> {
  List<TimelineEvent> _events = [];
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _collapsed = false;
  int _loadRequest = 0;
  final GlobalKey _cardKey = GlobalKey();

  static final RegExp _emojiRegExp = RegExp(
    r'[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]',
    unicode: true,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(PersonalTimelineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final accountChanged = oldWidget.username != widget.username;
    if (oldWidget.refreshTrigger != widget.refreshTrigger || accountChanged) {
      _loadData(clearExisting: accountChanged);
    }
  }

  Future<void> _loadData({bool clearExisting = false}) async {
    if (!mounted) return;
    final request = ++_loadRequest;
    final username = widget.username;
    if (!_hasLoaded || clearExisting) {
      setState(() {
        _isLoading = true;
        if (clearExisting) {
          _events = [];
          _hasLoaded = false;
        }
      });
    }

    try {
      final now = DateTime.now();
      final events = await TimelineService.instance.getEventsForDay(
        username,
        now,
      );
      if (!mounted || request != _loadRequest || username != widget.username) {
        return;
      }

      setState(() {
        _events = events;
        _isLoading = false;
        _hasLoaded = true;
      });
    } catch (e, stack) {
      debugPrint('PersonalTimelineSection _loadData error: $e\n$stack');
      if (mounted && request == _loadRequest && username == widget.username) {
        setState(() {
          _isLoading = false;
          _hasLoaded = true;
        });
      }
    }
  }

  Future<void> _openTodayReport() {
    if (widget.onTap != null) {
      widget.onTap!();
      return Future.value();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return PageTransitions.pushFromRect(
      context: context,
      page: PersonalTimelineScreen(username: widget.username),
      sourceKey: _cardKey,
      sourceColor: colorScheme.brightness == Brightness.dark
          ? colorScheme.surface
          : Colors.white,
      placeholderIcon: Icons.timeline_rounded,
      sourceBorderRadius: BorderRadius.circular(24),
    ).then((_) {
      if (mounted) _loadData();
    });
  }

  String _cleanSubtitle(String? input) {
    if (input == null || input.isEmpty) return '';
    final cleaned = input.replaceAll(_emojiRegExp, '').trim();
    return cleaned.isEmpty ? input.trim() : cleaned;
  }

  ({String badge, IconData icon, Color color, String content}) _resolveEvent(
    TimelineEvent event,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final rawText = (event.subtitle?.trim().isNotEmpty == true)
        ? event.subtitle!
        : event.title;
    final content = _cleanSubtitle(rawText);

    switch (event.type) {
      case TimelineEventType.todoCompleted:
        return (
          badge: '完成待办',
          icon: Icons.check_circle_outline_rounded,
          color: isDark ? Colors.greenAccent : colorScheme.cdtSuccess,
          content: content.isEmpty ? '完成了一项待办' : content,
        );
      case TimelineEventType.todoCreated:
        return (
          badge: '新增待办',
          icon: Icons.add_task_rounded,
          color: colorScheme.primary,
          content: content.isEmpty ? '新增了一项待办' : content,
        );
      case TimelineEventType.habitCheckIn:
        return (
          badge: '习惯打卡',
          icon: Icons.self_improvement_rounded,
          color: colorScheme.tertiary,
          content: content.isEmpty ? '完成一次习惯打卡' : content,
        );
      case TimelineEventType.pomodoroEnd:
        return (
          badge: '专注收获',
          icon: Icons.timer_rounded,
          color: isDark ? Colors.amberAccent : Colors.orange,
          content: content.isEmpty ? '完成一次专注' : content,
        );
      case TimelineEventType.pomodoroStart:
        return (
          badge: '开启专注',
          icon: Icons.play_circle_outline_rounded,
          color: isDark
              ? Colors.amberAccent.withValues(alpha: 0.8)
              : Colors.orange.withValues(alpha: 0.8),
          content: content.isEmpty ? '开启专注时段' : content,
        );
      case TimelineEventType.financeTransaction:
        final fType = event.extraData?['finance_type']?.toString();
        final isIncome = fType == 'income';
        return (
          badge: isIncome ? '账单收入' : '日常记账',
          icon: Icons.account_balance_wallet_outlined,
          color: isIncome
              ? (isDark ? Colors.greenAccent : colorScheme.cdtSuccess)
              : (isDark ? Colors.tealAccent : Colors.teal),
          content: content.isEmpty ? '记了一笔账' : content,
        );
      case TimelineEventType.courseStart:
        return (
          badge: '步入课堂',
          icon: Icons.school_outlined,
          color: Colors.indigoAccent,
          content: content.isEmpty ? '准时进入课堂' : content,
        );
      case TimelineEventType.timeLog:
        return (
          badge: '记录投入',
          icon: Icons.timelapse_rounded,
          color: colorScheme.primary,
          content: content.isEmpty ? '记录一段实际投入' : content,
        );
      case TimelineEventType.planBlock:
        return (
          badge: '任务规划',
          icon: Icons.event_note_rounded,
          color: Colors.deepPurpleAccent,
          content: content.isEmpty ? '进入预定规划时段' : content,
        );
      case TimelineEventType.searchQuery:
        return (
          badge: '知识检索',
          icon: Icons.search_rounded,
          color: isDark ? Colors.lightBlueAccent : Colors.blue,
          content: content.isEmpty ? '知识检索' : content,
        );
      case TimelineEventType.countdownCreated:
      case TimelineEventType.countdownCompleted:
      case TimelineEventType.countdownEdited:
        return (
          badge: '倒计时',
          icon: Icons.timer_outlined,
          color: colorScheme.error,
          content: content.isEmpty ? '倒计时事项' : content,
        );
      default:
        return (
          badge: '生活轨迹',
          icon: Icons.radio_button_checked_rounded,
          color: colorScheme.primary,
          content: content.isEmpty ? '记录一段生活轨迹' : content,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final useLightHeader = isDark || widget.isLight;
    final headerTextColor = useLightHeader ? Colors.white : null;
    final headerSubColor = useLightHeader
        ? Colors.white.withValues(alpha: 0.7)
        : colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 标题栏（与其他板块统一交互与无边框风格） ──
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: useLightHeader
                      ? Colors.white.withValues(alpha: 0.15)
                      : colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.timeline_rounded,
                  size: 20,
                  color: useLightHeader ? Colors.white : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '个人时间轴',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: headerTextColor,
                ),
              ),
              const SizedBox(width: 8),
              if (_events.isNotEmpty)
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
                    '${_events.length} 项足迹',
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
              // 跳转完整时间轴报告
              GestureDetector(
                key: const ValueKey<String>('timeline-open-screen-btn'),
                onTap: _openTodayReport,
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
              // 折叠 / 展开切换
              if (_events.isNotEmpty)
                GestureDetector(
                  key: const ValueKey<String>('timeline-toggle-collapse-btn'),
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

        // ── 一体化时光流液态毛玻璃卡片 ──
        Container(key: _cardKey, child: _buildUnifiedCard(colorScheme, isDark)),
      ],
    );
  }

  Widget _buildGlassCard({
    required double borderRadius,
    required BoxDecoration fallbackDecoration,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return PlatformBackdropFilter(
      filter: AppImageFilters.blur10,
      bypassWhenLiquidGlassEnabled: true,
      child: OptionalLiquidGlassCard(
        padding: padding,
        borderRadius: borderRadius,
        fallbackDecoration: fallbackDecoration,
        tint: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        isDark: Theme.of(context).brightness == Brightness.dark,
        child: child,
      ),
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
      child: (_isLoading && !_hasLoaded)
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
            )
          : _events.isEmpty
          ? _buildEmptyState(colorScheme, isDark)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 顶部全天轨迹跨度概览
                _buildHeaderStrip(colorScheme, isDark),

                // 2. 真实时间流节点（折叠时平滑收起）
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: _collapsed
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
                            // 垂直微型时光流
                            _buildTimelineStream(colorScheme, isDark),
                            // 底部进入完整报告按钮
                            _buildBottomAction(colorScheme, isDark),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  // ==========================================
  // 顶部全天轨迹跨度概览
  // ==========================================
  Widget _buildHeaderStrip(ColorScheme colorScheme, bool isDark) {
    final firstTime = _events.first.timestamp;
    final latestTime = _events.last.timestamp;

    final String spanLabel;
    if (firstTime.hour == latestTime.hour &&
        firstTime.minute == latestTime.minute) {
      spanLabel = '记录于 ${AppTimeFormats.clock(latestTime)}';
    } else {
      spanLabel =
          '活跃时段 ${AppTimeFormats.clock(firstTime)} - ${AppTimeFormats.clock(latestTime)}';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _openTodayReport,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(Icons.route_rounded, size: 15, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              '今日 ${_events.length} 项足迹',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 3.5,
              height: 3.5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white38 : colorScheme.outlineVariant,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                spanLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white60 : colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: isDark ? Colors.white38 : colorScheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 垂直微型时光流（展示最近发生的 3~4 条事件）
  // ==========================================
  Widget _buildTimelineStream(ColorScheme colorScheme, bool isDark) {
    // 倒序取最近的 4 条事件（最新在上）
    final displayEvents = _events.reversed.take(4).toList();

    return Column(
      children: [
        for (var i = 0; i < displayEvents.length; i++)
          _buildTimelineItem(
            event: displayEvents[i],
            isFirst: i == 0,
            isLast: i == displayEvents.length - 1,
            colorScheme: colorScheme,
            isDark: isDark,
          ),
      ],
    );
  }

  Widget _buildTimelineItem({
    required TimelineEvent event,
    required bool isFirst,
    required bool isLast,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    final details = _resolveEvent(event, colorScheme, isDark);
    final nodeColor = details.color;
    final timeStr = AppTimeFormats.clock(event.timestamp);
    final isSingle = isFirst && isLast;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧竖向时间轴线 + 发光节点圆点
          SizedBox(
            width: 20,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!isSingle)
                  Positioned(
                    top: isFirst ? 8 : 0,
                    bottom: isLast ? null : 0,
                    height: isLast ? 8 : null,
                    child: Container(
                      width: 1.5,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : colorScheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                Positioned(
                  top: 4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: nodeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: nodeColor.withValues(alpha: 0.35),
                          blurRadius: 4,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧内容卡片（支持点击进入详情）
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 2 : 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _openTodayReport,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: isDark
                                  ? Colors.white70
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: nodeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: nodeColor.withValues(alpha: 0.25),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              details.badge,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: nodeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        details.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 底部进入完整时间轴入口
  // ==========================================
  Widget _buildBottomAction(ColorScheme colorScheme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openTodayReport,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _events.length > 4
                    ? '查看今日全部 ${_events.length} 项足迹'
                    : '查看完整时光报告',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 13,
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 空状态展示
  // ==========================================
  Widget _buildEmptyState(ColorScheme colorScheme, bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _openTodayReport,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                size: 24,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '今日暂无时光轨迹',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '完成待办、习惯打卡或记录账单后，将在此刻画今日生活脉络',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
