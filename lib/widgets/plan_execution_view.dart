import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../screens/course_screens.dart';
import '../services/pomodoro_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/page_transitions.dart';
import 'optional_liquid_glass_surface.dart';

final Map<(String?, String), DateFormat> _planExecutionDateFormats = {};

DateFormat _planExecutionDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _planExecutionDateFormats.putIfAbsent((
    locale,
    pattern,
  ), () => DateFormat(pattern, locale));
}

/// Presentation only: actual records keep their identity and never become
/// draggable plans or change the plan's linked focus duration.
class PlanExecutionEntry {
  const PlanExecutionEntry.focus(this.record) : log = null;
  const PlanExecutionEntry.log(this.log) : record = null;
  final PomodoroRecord? record;
  final TimeLogItem? log;
  bool get isFocus => record != null;
  String get id => record?.uuid ?? log!.id;
  String get kind => isFocus ? '专注' : '时间日志';
  String get title => (record?.todoTitle?.isNotEmpty == true)
      ? record!.todoTitle!
      : (isFocus
            ? (record!.todoUuid?.isNotEmpty == true ? '专注记录' : '未绑定待办的专注')
            : (log!.title.isNotEmpty ? log!.title : '未命名时间日志'));
  int get start => record?.startTime ?? log!.startTime;
  int get end => record != null
      ? record!.endTime ?? start + record!.effectiveDuration * 1000
      : log!.endTime;
  IconData get icon =>
      isFocus ? Icons.timer_outlined : Icons.edit_calendar_outlined;
  Color color(BuildContext context) => isFocus
      ? Theme.of(context).colorScheme.tertiary
      : Theme.of(context).colorScheme.secondary;

  static int timelineLaneCount(Iterable<PlanExecutionEntry> entries) {
    final hasFocus = entries.any((entry) => entry.isFocus);
    final hasLogs = entries.any((entry) => !entry.isFocus);
    return 1 + (hasFocus ? 1 : 0) + (hasLogs ? 1 : 0);
  }

  static List<PlanExecutionEntry> forDay(
    DateTime day,
    List<PomodoroRecord> records,
    List<TimeLogItem> logs,
  ) {
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end = DateTime(
      day.year,
      day.month,
      day.day + 1,
    ).millisecondsSinceEpoch;
    return [
        ...records.where((r) => !r.isDeleted).map(PlanExecutionEntry.focus),
        ...logs.where((l) => !l.isDeleted).map(PlanExecutionEntry.log),
      ].where((e) => e.end > e.start && e.start < end && e.end > start).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  String get timeLabel {
    final startDate = DateTime.fromMillisecondsSinceEpoch(start);
    final endDate = DateTime.fromMillisecondsSinceEpoch(end);
    final format = DateUtils.isSameDay(startDate, endDate)
        ? 'HH:mm'
        : 'MM-dd HH:mm';
    final dateFormat = _planExecutionDateFormat(format);
    return '${dateFormat.format(startDate)}–${dateFormat.format(endDate)}';
  }

  void openDetail(
    BuildContext context,
    List<PomodoroTag> tags, {
    GlobalKey? sourceKey,
  }) {
    final detail = isFocus
        ? PomodoroDetailScreen(record: record!, tags: tags)
        : TimeLogDetailScreen(log: log!, tags: tags);
    if (sourceKey == null) {
      Navigator.of(context)
          .push(PageTransitions.material(builder: (_) => detail));
      return;
    }

    PageTransitions.pushFromRect(
      context: context,
      page: detail,
      sourceKey: sourceKey,
      sourceColor: color(context).withValues(alpha: 0.24),
      placeholderIcon: icon,
      sourceBorderRadius: BorderRadius.zero,
    );
  }
}

class PlanExecutionSummary extends StatelessWidget {
  const PlanExecutionSummary({
    super.key,
    required this.date,
    required this.records,
    required this.logs,
    required this.tags,
  });
  final DateTime date;
  final List<PomodoroRecord> records;
  final List<TimeLogItem> logs;
  final List<PomodoroTag> tags;

  Future<void> _showRecords(
    BuildContext context,
    List<PlanExecutionEntry> entries,
  ) async {
    final dateFormat = _planExecutionDateFormat('M月d日');
    ModalRoute<dynamic>? sheetRoute;
    final selected = await showAppModalBottomSheet<PlanExecutionEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 680),
      useGlassSheet: false,
      builder: (sheetContext) {
        sheetRoute = ModalRoute.of(sheetContext);
        return SafeArea(
          child: OptionalLiquidGlassSheet(
            fallbackDecoration: BoxDecoration(
              color: Theme.of(sheetContext).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${dateFormat.format(date)} · 实际记录',
                            style: Theme.of(sheetContext).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final focus = entry.record;
                        final duration = focus != null
                            ? '有效专注 ${focus.effectiveDuration ~/ 60} 分钟'
                            : '记录时长 ${(entry.end - entry.start) ~/ 60000} 分钟';
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            key: ValueKey(
                              'plan-execution-list-${entry.kind}-${entry.id}',
                            ),
                            leading: Icon(
                              entry.icon,
                              color: entry.color(context),
                            ),
                            title: Text('${entry.kind} · ${entry.title}'),
                            subtitle: Text('${entry.timeLabel}\n$duration'),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(sheetContext, entry),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    await sheetRoute?.completed;
    if (context.mounted && selected != null) selected.openDetail(context, tags);
  }

  @override
  Widget build(BuildContext context) {
    final entries = PlanExecutionEntry.forDay(date, records, logs);
    final colors = Theme.of(context).colorScheme;
    Widget legend(String label, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 7, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          legend('规划', colors.primary),
          legend('专注', colors.tertiary),
          legend('日志', colors.secondary),
          TextButton.icon(
            key: const ValueKey('plan-execution-list'),
            onPressed: entries.isEmpty
                ? null
                : () => _showRecords(context, entries),
            style: ButtonStyle(
              backgroundBuilder: (context, states, child) =>
                  child ?? const SizedBox.shrink(),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.disabled)
                    ? colors.surfaceContainerLow.withValues(alpha: 0.5)
                    : colors.secondaryContainer;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.disabled)
                    ? colors.onSurface.withValues(alpha: 0.38)
                    : colors.onSecondaryContainer;
              }),
              overlayColor: WidgetStatePropertyAll(
                colors.primary.withValues(alpha: 0.12),
              ),
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelSmall,
              ),
              minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
              visualDensity: VisualDensity.compact,
              shape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
            ),
            icon: const Icon(Icons.view_list_outlined, size: 14),
            label: const Text('时间轴记录'),
          ),
        ],
      ),
    );
  }
}

/// Plans and present execution kinds share the hour across separate lanes.
/// The full list remains available for short or overlapping records.
class PlanExecutionTimelineLayer extends StatefulWidget {
  const PlanExecutionTimelineLayer({
    super.key,
    required this.date,
    required this.entries,
    required this.tags,
    required this.hourHeight,
    this.onRecordInteraction,
  });
  final DateTime date;
  final List<PlanExecutionEntry> entries;
  final List<PomodoroTag> tags;
  final double hourHeight;
  final VoidCallback? onRecordInteraction;

  @override
  State<PlanExecutionTimelineLayer> createState() =>
      _PlanExecutionTimelineLayerState();
}

class _PlanExecutionTimelineLayerState
    extends State<PlanExecutionTimelineLayer> {
  final Map<String, GlobalKey> _segmentSourceKeys = {};

  GlobalKey _sourceKeyFor(PlanExecutionEntry entry, int hour) {
    final identity = '${entry.kind}:${entry.id}:$hour';
    return _segmentSourceKeys.putIfAbsent(identity, () => GlobalKey());
  }

  @override
  void didUpdateWidget(covariant PlanExecutionTimelineLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.date, widget.date)) {
      _segmentSourceKeys.clear();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final day = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
      );
      final nextDay = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day + 1,
      );
      final hasFocus = widget.entries.any((entry) => entry.isFocus);
      final laneCount = PlanExecutionEntry.timelineLaneCount(widget.entries);
      final laneHeight = widget.hourHeight / laneCount;
      final segments = <Widget>[];
      for (final entry in widget.entries) {
        final start = DateTime.fromMillisecondsSinceEpoch(entry.start);
        final end = DateTime.fromMillisecondsSinceEpoch(entry.end);
        final clippedStart = start.isBefore(day) ? day : start;
        final clippedEnd = end.isAfter(nextDay) ? nextDay : end;
        final lastHour = clippedEnd == nextDay ? 23 : clippedEnd.hour;
        for (var hour = clippedStart.hour; hour <= lastHour; hour++) {
          final rowStart = DateTime(
            widget.date.year,
            widget.date.month,
            widget.date.day,
            hour,
          );
          final rowEnd = DateTime(
            widget.date.year,
            widget.date.month,
            widget.date.day,
            hour + 1,
          );
          final from = clippedStart.isAfter(rowStart) ? clippedStart : rowStart;
          final to = clippedEnd.isBefore(rowEnd) ? clippedEnd : rowEnd;
          if (!to.isAfter(from)) continue;
          final left =
              constraints.maxWidth *
              from.difference(rowStart).inMilliseconds /
              3600000;
          final width =
              constraints.maxWidth *
              to.difference(from).inMilliseconds /
              3600000;
          final laneIndex = entry.isFocus || !hasFocus ? 1 : 2;
          final color = entry.color(context);
          final sourceKey = _sourceKeyFor(entry, hour);
          segments.add(
            Positioned(
              top: hour * widget.hourHeight + laneIndex * laneHeight + 0.5,
              left: left + 1,
              width: max(1, width - 2),
              height: max(1, laneHeight - 1),
              child: Tooltip(
                message: '${entry.kind} · ${entry.title}\n${entry.timeLabel}',
                child: GestureDetector(
                  key: ValueKey(
                    'plan-execution-${entry.kind}-${entry.id}-$hour',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onRecordInteraction?.call();
                    entry.openDetail(
                      context,
                      widget.tags,
                      sourceKey: sourceKey,
                    );
                  },
                  onPanStart: (_) => widget.onRecordInteraction?.call(),
                  onPanUpdate: (_) {},
                  onPanEnd: (_) => widget.onRecordInteraction?.call(),
                  child: Container(
                    key: sourceKey,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.24),
                      border: Border(left: BorderSide(color: color, width: 2)),
                    ),
                    child:
                        laneHeight < 11 ||
                            width < 72 ||
                            !from.isAtSameMomentAs(clippedStart)
                        ? null
                        : ClipRect(
                            child: Center(
                              child: Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: min(9.0, laneHeight * 0.68),
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
        }
      }
      return Stack(children: segments);
    },
  );
}
