import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/home_agenda_repository.dart';
import '../services/plan_review_repository.dart';
import 'floating_glass_control.dart';
import 'optional_liquid_glass_surface.dart';
import 'plan_day_overview.dart' show planOverviewDuration;
import 'platform_backdrop_filter.dart';

final Map<(String?, String), DateFormat> _homeAgendaDateFormats = {};

DateFormat _homeAgendaDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _homeAgendaDateFormats.putIfAbsent(
    (locale, pattern),
    () => DateFormat(pattern, locale),
  );
}

/// The single homepage surface. Source-specific actions live in the host.
class HomeAgendaCard extends StatefulWidget {
  const HomeAgendaCard({
    super.key,
    required this.snapshot,
    required this.collapsed,
    required this.loading,
    required this.enabled,
    required this.retryEnabled,
    required this.showPlans,
    required this.duration,
    required this.onCollapse,
    required this.onStats,
    required this.onAll,
    required this.onTomorrow,
    required this.onAdd,
    required this.onItem,
    required this.onRetry,
    required this.planActions,
    this.expandedPlanId,
    this.chartKey,
    this.error,
    this.extra,
    this.isLight = false,
    this.isForeground = true,
  });
  final HomeAgendaSnapshot? snapshot;
  final bool
      collapsed,
      loading,
      enabled,
      showPlans,
      retryEnabled,
      isLight,
      isForeground;
  final Duration duration;
  final VoidCallback onCollapse;
  final void Function([GlobalKey? sourceKey])? onAll,
      onTomorrow,
      onAdd,
      onStats;
  final void Function(HomeAgendaItem item, [GlobalKey? sourceKey]) onItem;
  final void Function(HomeAgendaSource?) onRetry;
  final Widget Function(PlanTodayRow row, [GlobalKey? cardKey]) planActions;
  final String? expandedPlanId, error;
  final Key? chartKey;
  final Widget? extra;
  @override
  State<HomeAgendaCard> createState() => _HomeAgendaCardState();
}

class _HomeAgendaCardState extends State<HomeAgendaCard> {
  bool _ended = false, _attention = false, _allDay = false;
  final _itemKeys = <String, GlobalKey>{};
  final _overviewKey = GlobalKey(debugLabel: 'agenda_overview_card');
  final _allButtonKey = GlobalKey(debugLabel: 'agenda_all_button');
  final _tomorrowButtonKey = GlobalKey(debugLabel: 'agenda_tomorrow_button');
  final _addButtonKey = GlobalKey(debugLabel: 'agenda_add_button');
  final _chartButtonKey = GlobalKey(debugLabel: 'agenda_chart_button');

  GlobalKey _keyForItem(String id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'agenda_item_$id'));

  @override
  void didUpdateWidget(covariant HomeAgendaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      _itemKeys.removeWhere((_, key) => key.currentContext == null);
    }
    if (oldWidget.snapshot?.identity.username !=
            widget.snapshot?.identity.username ||
        oldWidget.snapshot?.identity.userId !=
            widget.snapshot?.identity.userId ||
        oldWidget.snapshot?.day != widget.snapshot?.day) {
      _ended = _attention = _allDay = false;
    }
  }

  ColorScheme get colors => Theme.of(context).colorScheme;
  TextTheme get text => Theme.of(context).textTheme;
  Widget _label(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
    child: Text(
      label,
      style: text.labelMedium?.copyWith(
        color: widget.isLight
            ? Colors.white.withValues(alpha: 0.85)
            : colors.onSurfaceVariant,
      ),
    ),
  );

  Widget _row(HomeAgendaItem item, {bool quiet = false}) {
    final current = item.isCurrent(widget.snapshot!.instant);
    final attention = item.needsAttention(widget.snapshot!.instant);
    final crossDay = !DateUtils.isSameDay(item.start, item.end);
    final format = _homeAgendaDateFormat(
      crossDay ? 'MM-dd\nHH:mm' : 'HH:mm',
    );
    final plan = item.plan;
    final expanded = plan != null && widget.expandedPlanId == plan.entry.id;
    final endLabel = item.fixed?.isEndTimeTbd == true
        ? '待定'
        : format.format(item.end);

    final Color accent = attention
        ? colors.error
        : current
        ? colors.primary
        : (item.course != null
              ? colors.primary
              : item.fixed != null
              ? (colors.brightness == Brightness.dark
                    ? colors.secondary
                    : colors.primary)
              : item.calendar != null
              ? colors.tertiary
              : colors.primary);

    final cardKey = _keyForItem(item.id);
    return OptionalLiquidGlassCard(
      key: cardKey,
      margin: const EdgeInsets.only(bottom: 6),
      borderRadius: 14,
      tint: accent.withValues(alpha: current ? 0.22 : 0.12),
      fallbackDecoration: BoxDecoration(
        color: current
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : colors.surface.withValues(
                alpha: widget.isLight ? 0.95 : (quiet ? 0.5 : 0.72),
              ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current
              ? colors.primary.withValues(alpha: 0.45)
              : (attention
                    ? colors.error.withValues(alpha: 0.35)
                    : colors.outlineVariant.withValues(
                        alpha: widget.isLight ? 0.15 : 0.25,
                      )),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: plan == null
              ? ValueKey('agenda-row-${item.id}')
              : ValueKey('plan-today-row-${plan.entry.id}'),
          onTap: widget.enabled ? () => widget.onItem(item, cardKey) : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 3.5,
                      height: 36,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(
                      width: crossDay ? 56 : 48,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.allDay ? '全天' : format.format(item.start),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: current
                                  ? colors.primary
                                  : (quiet
                                        ? colors.onSurfaceVariant
                                        : colors.onSurface),
                              height: 1.2,
                            ),
                          ),
                          if (!item.allDay)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                endLabel,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colors.onSurfaceVariant,
                                  height: 1.1,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: quiet
                                        ? colors.onSurfaceVariant
                                        : colors.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.sourceLabel,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item.detail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (current || attention || item.completed) ...[
                            const SizedBox(height: 2),
                            Text(
                              attention
                                  ? (plan!.status == 6 ? '漏做' : '已结束待确认')
                                  : item.completed
                                  ? '已完成'
                                  : item.isFocusing
                                  ? '正在专注'
                                  : '时段进行中${item.fixed?.isEndTimeTbd == true ? ' · 结束待定' : ''}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: attention
                                    ? colors.error
                                    : current
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      plan != null
                          ? (expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded)
                          : Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                if (plan != null)
                  AnimatedSize(
                    duration: widget.duration,
                    alignment: Alignment.topCenter,
                    child: expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: widget.planActions(plan, cardKey),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _firstUpcomingVisibleId(HomeAgendaSnapshot? data) {
    if (data == null) return null;
    final instant = data.instant;
    for (final item in data.visible) {
      if (item.isUpcoming(instant)) return item.id;
    }
    return null;
  }

  Widget _expandButton({
    required String label,
    required bool expanded,
    required VoidCallback onTap,
    required String key,
    bool alert = false,
  }) => OptionalLiquidGlassCard(
    margin: const EdgeInsets.only(bottom: 6),
    borderRadius: 12,
    tint: (alert ? colors.error : colors.primary).withValues(alpha: 0.12),
    fallbackDecoration: BoxDecoration(
      color: alert
          ? colors.errorContainer.withValues(alpha: 0.3)
          : colors.surface.withValues(alpha: widget.isLight ? 0.78 : 0.48),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: alert
            ? colors.error.withValues(alpha: 0.3)
            : colors.outlineVariant.withValues(alpha: 0.15),
      ),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                alert
                    ? Icons.warning_amber_rounded
                    : (expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded),
                size: 17,
                color: alert ? colors.error : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: alert
                        ? colors.onErrorContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                expanded ? '收起' : '展开',
                style: TextStyle(
                  fontSize: 11,
                  color: alert
                      ? colors.onErrorContainer
                      : colors.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _expandedBodySurface(Widget child) {
    final light = widget.isLight;
    final fallbackDecoration = BoxDecoration(
      color: light ? Colors.white.withValues(alpha: 0.15) : colors.surface,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: light ? 0.1 : 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(
        color: light
            ? Colors.white.withValues(alpha: 0.2)
            : Theme.of(context).dividerColor.withValues(alpha: 0.5),
      ),
    );
    if (!widget.isForeground) {
      return Container(
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(12),
        decoration: fallbackDecoration,
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: PlatformBackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        bypassWhenLiquidGlassEnabled: true,
        child: OptionalLiquidGlassCard(
          padding: const EdgeInsets.all(12),
          borderRadius: 24,
          highContrast: true,
          tint: (light ? colors.scrim : colors.primary).withValues(alpha: 0.16),
          isDark: light || colors.brightness == Brightness.dark,
          fallbackDecoration: fallbackDecoration,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.snapshot;
    final bodyActionStyle = widget.isLight
        ? TextButton.styleFrom(foregroundColor: Colors.white)
        : null;
    final next = data?.upcoming.firstOrNull;
    final nextUpcomingId = _firstUpcomingVisibleId(data);
    final current = data?.currentCount ?? 0,
        upcoming = data?.upcomingCount ?? 0;
    final subtitle = widget.collapsed && next != null
        ? '接下来 ${_homeAgendaDateFormat('HH:mm').format(next.start)} · ${next.title}'
        : data == null
        ? (widget.error == null ? '正在读取今日安排…' : '今日安排暂不可用')
        : (current > 0 || upcoming > 0
              ? '时段进行中 $current · 接下来 $upcoming'
              : (data.total > 0 ? '今日定时安排已结束' : '今天暂无安排'));
    final overview = data?.plans?.card.overview;
    final Color? textColor = widget.isLight ? Colors.white : null;
    final Color iconColor = widget.isLight ? Colors.white70 : colors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 统一板块标题栏 (完全与 SectionHeader 和待办清单对齐) ──
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: widget.onCollapse,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '今日安排',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: textColor,
                                ),
                          ),
                        ),
                      ),
                      if (widget.collapsed && subtitle.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: widget.isLight
                                  ? Colors.white70
                                  : colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.loading)
                const SizedBox(
                  key: ValueKey('plan-today-updating'),
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (widget.showPlans)
                SizedBox(
                  key: widget.chartKey ?? _chartButtonKey,
                  child: IconButton(
                    constraints: const BoxConstraints.tightFor(
                      width: floatingGlassStandardControlSize,
                      height: floatingGlassStandardControlSize,
                    ),
                    visualDensity: VisualDensity.standard,
                    style: floatingGlassPlainIconButtonStyle(),
                    tooltip: '规划统计',
                    onPressed: widget.enabled
                        ? () => widget.onStats?.call(
                            widget.chartKey is GlobalKey
                                ? widget.chartKey as GlobalKey
                                : _chartButtonKey,
                          )
                        : null,
                    icon: Icon(
                      Icons.insights_outlined,
                      size: 20,
                      color: iconColor,
                    ),
                  ),
                ),
              SizedBox(
                key: _addButtonKey,
                child: IconButton(
                  key: const ValueKey('agenda-add'),
                  constraints: const BoxConstraints.tightFor(
                    width: floatingGlassStandardControlSize,
                    height: floatingGlassStandardControlSize,
                  ),
                  visualDensity: VisualDensity.standard,
                  style: floatingGlassPlainIconButtonStyle(),
                  tooltip: '新增日程或安排待办',
                  onPressed: widget.enabled
                      ? () => widget.onAdd?.call(_addButtonKey)
                      : null,
                  icon: Icon(
                    Icons.add_circle_outline_rounded,
                    size: 20,
                    color: iconColor,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('plan-today-collapse'),
                constraints: const BoxConstraints.tightFor(
                  width: floatingGlassStandardControlSize,
                  height: floatingGlassStandardControlSize,
                ),
                visualDensity: VisualDensity.standard,
                style: floatingGlassPlainIconButtonStyle(),
                tooltip: widget.collapsed ? '展开今日安排' : '收起今日安排',
                onPressed: widget.onCollapse,
                icon: Icon(
                  widget.collapsed
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  size: 20,
                  color: iconColor,
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: widget.duration,
          alignment: Alignment.topCenter,
          child: widget.collapsed
              ? const SizedBox.shrink()
              : _expandedBodySurface(
                  Theme(
                    data: Theme.of(context).copyWith(
                      textButtonTheme: TextButtonThemeData(
                        style:
                            TextButton.styleFrom(
                              foregroundColor: colors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ).copyWith(
                              backgroundBuilder: (c, s, child) =>
                                  child ?? const SizedBox.shrink(),
                              side: const WidgetStatePropertyAll(
                                BorderSide.none,
                              ),
                            ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (overview != null)
                          OptionalLiquidGlassCard(
                            key: _overviewKey,
                            margin: const EdgeInsets.only(bottom: 6),
                            borderRadius: 12,
                            tint: colors.primary.withValues(alpha: 0.12),
                            fallbackDecoration: BoxDecoration(
                              color: colors.surface.withValues(
                                alpha: widget.isLight ? 0.85 : 0.55,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colors.primary.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: widget.enabled
                                    ? () => widget.onStats?.call(_overviewKey)
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compact =
                                          constraints.maxWidth < 280 ||
                                          MediaQuery.textScalerOf(context)
                                                  .scale(1) >
                                              1.3;
                                      return Row(
                                        children: [
                                          Icon(
                                            Icons.timelapse_rounded,
                                            size: 16,
                                            color: colors.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: compact
                                                ? Text(
                                                    '规划概览',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: colors.primary,
                                                    ),
                                                  )
                                                : Wrap(
                                                    spacing: 16,
                                                    runSpacing: 4,
                                                    children: [
                                                      Text(
                                                        '规划 ${planOverviewDuration(overview.plan('seconds'))}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              colors.onSurface,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                      Text(
                                                        '有效专注 ${planOverviewDuration(overview.actual('seconds'))}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: colors.primary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (widget.error != null) ...[
                          Text(
                            '今日安排读取失败：${widget.error}',
                            style: text.bodySmall?.copyWith(
                              color: widget.isLight
                                  ? colors.errorContainer
                                  : colors.error,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: const ValueKey('agenda-retry'),
                              onPressed: widget.retryEnabled
                                  ? () => widget.onRetry(null)
                                  : null,
                              style: bodyActionStyle,
                              child: const Text('重试'),
                            ),
                          ),
                        ],
                        if (data != null) ...[
                          for (final entry in data.errors.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${entry.key.label}读取失败',
                                      style: text.bodySmall?.copyWith(
                                        color: widget.isLight
                                            ? colors.errorContainer
                                            : colors.error,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    key: ValueKey(
                                      'agenda-retry-${entry.key.name}',
                                    ),
                                    onPressed: widget.retryEnabled
                                        ? () => widget.onRetry(entry.key)
                                        : null,
                                    style: bodyActionStyle,
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            ),
                          if (data.allDay.isNotEmpty) ...[
                            _expandButton(
                              label: '全天 ${data.allDay.length} 项',
                              expanded: _allDay,
                              onTap: () => setState(() => _allDay = !_allDay),
                              key: 'agenda-all-day',
                            ),
                            if (_allDay) ...data.allDay.take(5).map(_row),
                          ],
                          if (data.attentionCount > 0) ...[
                            _expandButton(
                              label:
                                  '需处理 ${data.attentionCount} · ${data.attention.first.title}',
                              expanded: _attention,
                              onTap: () =>
                                  setState(() => _attention = !_attention),
                              key: 'agenda-attention',
                              alert: true,
                            ),
                            if (_attention) _row(data.attention.first),
                            if (_attention && data.attentionCount > 1)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: widget.enabled
                                      ? widget.onAll
                                      : null,
                                  style: bodyActionStyle,
                                  child: Text(
                                    '查看其余 ${data.attentionCount - 1} 项',
                                  ),
                                ),
                              ),
                          ],
                          if (data.endedCount > 0) ...[
                            _expandButton(
                              label: '已结束 / 已完成 ${data.endedCount} 项',
                              expanded: _ended,
                              onTap: () => setState(() => _ended = !_ended),
                              key: 'agenda-ended',
                            ),
                            if (_ended)
                              ...data.ended
                                  .take(5)
                                  .map((i) => _row(i, quiet: true)),
                            if (_ended && data.endedCount > 5)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: widget.enabled
                                      ? widget.onAll
                                      : null,
                                  style: bodyActionStyle,
                                  child: const Text('查看全部已结束安排'),
                                ),
                              ),
                          ],
                          for (final item in data.visible) ...[
                            if (item.id == nextUpcomingId) _label('接下来'),
                            _row(item),
                          ],
                          if (data.hiddenCurrent > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: widget.enabled ? widget.onAll : null,
                                style: bodyActionStyle,
                                child: Text('另有 ${data.hiddenCurrent} 项同时进行'),
                              ),
                            ),
                          if (data.total == 0 && data.errors.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 20,
                                horizontal: 4,
                              ),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.event_available_outlined,
                                      size: 32,
                                      color: widget.isLight
                                          ? Colors.white.withValues(alpha: 0.72)
                                          : colors.onSurfaceVariant.withValues(
                                              alpha: 0.5,
                                            ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '今天暂无安排，留一点时间给自己',
                                      style: text.bodyMedium?.copyWith(
                                        color: widget.isLight
                                            ? Colors.white
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (data.total > 0 &&
                              data.visible.isEmpty &&
                              data.attentionCount == 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 4,
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 15,
                                      color: widget.isLight
                                          ? Colors.white.withValues(alpha: 0.8)
                                          : colors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      data.allDay.isNotEmpty
                                          ? '今日暂无后续定时安排'
                                          : '今日定时安排已结束',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: widget.isLight
                                            ? Colors.white.withValues(
                                                alpha: 0.85,
                                              )
                                            : colors.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ] else if (widget.error == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                '正在读取今日安排…',
                                style: text.bodyMedium?.copyWith(
                                  color: widget.isLight
                                      ? Colors.white
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        if (widget.extra != null) widget.extra!,
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              SizedBox(
                                key: _allButtonKey,
                                child: TextButton.icon(
                                  key: const ValueKey('agenda-all'),
                                  onPressed: widget.enabled
                                      ? () => widget.onAll?.call(_allButtonKey)
                                      : null,
                                  style: bodyActionStyle,
                                  label: const Text('全部安排'),
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 16,
                                  ),
                                ),
                              ),
                              if (data != null && current == 0 && upcoming == 0)
                                SizedBox(
                                  key: _tomorrowButtonKey,
                                  child: TextButton.icon(
                                    onPressed: widget.enabled
                                        ? () => widget.onTomorrow?.call(
                                            _tomorrowButtonKey,
                                          )
                                        : null,
                                    style: bodyActionStyle,
                                    icon: const Icon(
                                      Icons.wb_sunny_outlined,
                                      size: 15,
                                    ),
                                    label: const Text('明日安排'),
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
      ],
    );
  }
}
