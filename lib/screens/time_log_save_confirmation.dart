import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/time_log_overlap_service.dart';
import '../utils/app_dialogs.dart';

Future<bool?> showTimeLogSaveConfirmation({
  required BuildContext context,
  required DateTime start,
  required DateTime end,
  required List<TimeLogOverlap> overlaps,
  required bool isFuture,
  required bool isEditing,
}) => showAppDialog<bool>(
  context: context,
  builder: (_) => TimeLogSaveConfirmationDialog(
    start: start,
    end: end,
    overlaps: overlaps,
    isFuture: isFuture,
    isEditing: isEditing,
  ),
);

class TimeLogSaveConfirmationDialog extends StatelessWidget {
  const TimeLogSaveConfirmationDialog({
    super.key,
    required this.start,
    required this.end,
    required this.overlaps,
    required this.isFuture,
    required this.isEditing,
  });

  final DateTime start;
  final DateTime end;
  final List<TimeLogOverlap> overlaps;
  final bool isFuture;
  final bool isEditing;

  static final DateFormat _timeFormat = DateFormat('MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasOverlap = overlaps.isNotEmpty;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.48;
    final title = hasOverlap
        ? '发现时间重叠'
        : isEditing
        ? '确认保存未来时间'
        : '确认补录未来时间';

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            hasOverlap ? Icons.warning_amber_rounded : Icons.schedule_rounded,
            color: hasOverlap ? colors.error : colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_timeFormat.format(start)} → ${_timeFormat.format(end)}',
                ),
                if (isFuture) ...[
                  const SizedBox(height: 12),
                  Text(
                    '结束时间晚于当前时间，确认仍要${isEditing ? '保存这条时间日志' : '补录这段时间'}吗？',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
                if (hasOverlap) ...[
                  const SizedBox(height: 12),
                  Text(
                    '以下记录与本次补录重叠，保存后复盘会分别累计这些记录。',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  for (final overlap in overlaps.take(4))
                    _OverlapItem(overlap: overlap, colors: colors),
                  if (overlaps.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '另有 ${overlaps.length - 4} 条重叠记录',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('返回修改'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('仍然保存'),
        ),
      ],
    );
  }
}

class _OverlapItem extends StatelessWidget {
  const _OverlapItem({required this.overlap, required this.colors});

  final TimeLogOverlap overlap;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.fromMillisecondsSinceEpoch(overlap.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(overlap.endTime);
    final timeRange =
        '${TimeLogSaveConfirmationDialog._timeFormat.format(start)} → '
        '${TimeLogSaveConfirmationDialog._timeFormat.format(end)}';
    final title = overlap.title.trim().isEmpty
        ? overlap.sourceLabel
        : overlap.title;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                overlap.source == TimeLogOverlapSource.pomodoro
                    ? Icons.timer_outlined
                    : Icons.edit_calendar_outlined,
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                overlap.sourceLabel,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _formatOverlap(overlap.overlapMilliseconds),
                style: TextStyle(
                  color: colors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            timeRange,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatOverlap(int milliseconds) {
    final minutes =
        (milliseconds + Duration.millisecondsPerMinute - 1) ~/
        Duration.millisecondsPerMinute;
    if (minutes < 1) return '少于 1 分钟';
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$hours 小时'
        : '$hours 小时 $remainingMinutes 分钟';
  }
}
