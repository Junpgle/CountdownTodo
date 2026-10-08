import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../screens/course_screens.dart';
import '../services/pomodoro_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/page_transitions.dart';
import 'optional_liquid_glass_surface.dart';

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
    return '${DateFormat(format).format(startDate)}–${DateFormat(format).format(endDate)}';
  }

  void openDetail(BuildContext context, List<PomodoroTag> tags) {
    Navigator.of(context).push(
      PageTransitions.material(
        builder: (_) => isFocus
            ? PomodoroDetailScreen(record: record!, tags: tags)
            : TimeLogDetailScreen(log: log!, tags: tags),
      ),
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
                            '${DateFormat('M月d日').format(date)} · 实际记录',
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
          legend(
            '专注 ${entries.where((e) => e.isFocus).length} 条',
            colors.tertiary,
          ),
          legend(
            '时间日志 ${entries.where((e) => !e.isFocus).length} 条',
            colors.secondary,
          ),
          TextButton.icon(
            key: const ValueKey('plan-execution-list'),
            onPressed: entries.isEmpty
                ? null
                : () => _showRecords(context, entries),
            icon: const Icon(Icons.view_list_outlined, size: 16),
            label: const Text('查看记录'),
          ),
        ],
      ),
    );
  }
}

/// Three vertical lanes per hour: plans, focus and manually logged time.
/// The full list remains available for short or overlapping records.
class PlanExecutionTimelineLayer extends StatelessWidget {
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final day = DateTime(date.year, date.month, date.day);
      final nextDay = DateTime(date.year, date.month, date.day + 1);
      final segments = <Widget>[];
      for (final entry in entries) {
        final start = DateTime.fromMillisecondsSinceEpoch(entry.start);
        final end = DateTime.fromMillisecondsSinceEpoch(entry.end);
        final clippedStart = start.isBefore(day) ? day : start;
        final clippedEnd = end.isAfter(nextDay) ? nextDay : end;
        final lastHour = clippedEnd == nextDay ? 23 : clippedEnd.hour;
        for (var hour = clippedStart.hour; hour <= lastHour; hour++) {
          final rowStart = DateTime(date.year, date.month, date.day, hour);
          final rowEnd = DateTime(date.year, date.month, date.day, hour + 1);
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
          final color = entry.color(context);
          segments.add(
            Positioned(
              top:
                  hour * hourHeight + (entry.isFocus ? 0.5 : 0.75) * hourHeight,
              left: left + 1,
              width: max(1, width - 2),
              height: max(1, hourHeight / 4 - 1),
              child: Tooltip(
                message: '${entry.kind} · ${entry.title}\n${entry.timeLabel}',
                child: GestureDetector(
                  key: ValueKey(
                    'plan-execution-${entry.kind}-${entry.id}-$hour',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    onRecordInteraction?.call();
                    entry.openDetail(context, tags);
                  },
                  onPanStart: (_) => onRecordInteraction?.call(),
                  onPanUpdate: (_) {},
                  onPanEnd: (_) => onRecordInteraction?.call(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.24),
                      border: Border(left: BorderSide(color: color, width: 2)),
                    ),
                    child: hourHeight < 64
                        ? null
                        : ClipRect(
                            child: Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(fontSize: 8, color: color),
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
