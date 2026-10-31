import 'dart:math' as math;

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
  static final DateFormat _hourMinuteFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasOverlap = overlaps.isNotEmpty;
    final viewport = MediaQuery.sizeOf(context);
    final contentWidth = math.max(0.0, math.min(viewport.width - 128, 640.0));
    final maxHeight = viewport.height * 0.7;
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
        width: contentWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '本次补录时段：${_timeFormat.format(start)} → ${_timeFormat.format(end)}',
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
                    _OverlapItem(
                      overlap: overlap,
                      candidateStart: start,
                      candidateEnd: end,
                      colors: colors,
                    ),
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
  const _OverlapItem({
    required this.overlap,
    required this.candidateStart,
    required this.candidateEnd,
    required this.colors,
  });

  final TimeLogOverlap overlap;
  final DateTime candidateStart;
  final DateTime candidateEnd;
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
          const SizedBox(height: 8),
          _OverlapTimeline(
            candidateStart: candidateStart,
            candidateEnd: candidateEnd,
            overlap: overlap,
            colors: colors,
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

class _OverlapTimeline extends StatelessWidget {
  const _OverlapTimeline({
    required this.candidateStart,
    required this.candidateEnd,
    required this.overlap,
    required this.colors,
  });

  final DateTime candidateStart;
  final DateTime candidateEnd;
  final TimeLogOverlap overlap;
  final ColorScheme colors;

  String _formatRange(int startTime, int endTime) =>
      '${TimeLogSaveConfirmationDialog._timeFormat.format(DateTime.fromMillisecondsSinceEpoch(startTime))} → '
      '${TimeLogSaveConfirmationDialog._timeFormat.format(DateTime.fromMillisecondsSinceEpoch(endTime))}';

  Widget _buildAxisLabel(
    int timestamp, {
    required bool isEnd,
    required bool crossesDate,
    required String dateFormat,
    required Color color,
  }) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final style = TextStyle(color: color, fontSize: 10);
    if (!crossesDate) {
      return Text(
        TimeLogSaveConfirmationDialog._hourMinuteFormat.format(dateTime),
        style: style,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat(dateFormat.split(' ').first).format(dateTime),
          style: style,
        ),
        Text(
          TimeLogSaveConfirmationDialog._hourMinuteFormat.format(dateTime),
          style: style,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidateStartMs = candidateStart.millisecondsSinceEpoch;
    final candidateEndMs = candidateEnd.millisecondsSinceEpoch;
    final axisStart = math.min(candidateStartMs, overlap.startTime);
    final axisEnd = math.max(candidateEndMs, overlap.endTime);
    final axisStartDate = DateTime.fromMillisecondsSinceEpoch(axisStart);
    final axisEndDate = DateTime.fromMillisecondsSinceEpoch(axisEnd);
    final crossesDate =
        axisStartDate.year != axisEndDate.year ||
        axisStartDate.month != axisEndDate.month ||
        axisStartDate.day != axisEndDate.day;
    final axisDateFormat = axisStartDate.year == axisEndDate.year
        ? 'MM-dd HH:mm'
        : 'yyyy-MM-dd HH:mm';
    final candidateRange = _formatRange(candidateStartMs, candidateEndMs);
    final recordRange = _formatRange(overlap.startTime, overlap.endTime);
    final exactOverlap = overlap.overlapIntervals
        .map((interval) => _formatRange(interval.startTime, interval.endTime))
        .join('；');
    final semanticsLabel =
        '时间轴。本次补录：$candidateRange。${overlap.sourceLabel}：$recordRange。'
        '红色部分为实际重叠：$exactOverlap。番茄暂停时段不计入重叠。';

    return Semantics(
      key: ValueKey('overlap-timeline-${overlap.id}'),
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TimelineTrack(
              label: '补录',
              axisStart: axisStart,
              axisEnd: axisEnd,
              rangeStart: candidateStartMs,
              rangeEnd: candidateEndMs,
              overlapIntervals: overlap.overlapIntervals,
              rangeColor: colors.primary,
              colors: colors,
            ),
            const SizedBox(height: 4),
            _TimelineTrack(
              label: '记录',
              axisStart: axisStart,
              axisEnd: axisEnd,
              rangeStart: overlap.startTime,
              rangeEnd: overlap.endTime,
              overlapIntervals: overlap.overlapIntervals,
              rangeColor: colors.outlineVariant,
              colors: colors,
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                const SizedBox(width: 42),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAxisLabel(
                        axisStart,
                        isEnd: false,
                        crossesDate: crossesDate,
                        dateFormat: axisDateFormat,
                        color: colors.onSurfaceVariant,
                      ),
                      _buildAxisLabel(
                        axisEnd,
                        isEnd: true,
                        crossesDate: crossesDate,
                        dateFormat: axisDateFormat,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    '重叠点',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  child: _TimelineTimeMarkers(
                    axisStart: axisStart,
                    axisEnd: axisEnd,
                    intervals: overlap.overlapIntervals,
                    crossesDate: crossesDate,
                    dateFormat: axisDateFormat,
                    colors: colors,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _TimelineLegendItem(
                  color: colors.primary,
                  label: '本次补录',
                  colors: colors,
                ),
                _TimelineLegendItem(
                  color: colors.outlineVariant,
                  label: '已有记录',
                  colors: colors,
                ),
                _TimelineLegendItem(
                  color: colors.error,
                  label: '实际重叠',
                  colors: colors,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '本次重叠：$exactOverlap',
              style: TextStyle(
                color: colors.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (overlap.source == TimeLogOverlapSource.pomodoro)
              Text(
                '红色只标注实际专注，暂停时段不计入。',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTimeMarkers extends StatelessWidget {
  const _TimelineTimeMarkers({
    required this.axisStart,
    required this.axisEnd,
    required this.intervals,
    required this.crossesDate,
    required this.dateFormat,
    required this.colors,
  });

  final int axisStart;
  final int axisEnd;
  final List<TimeLogOverlapInterval> intervals;
  final bool crossesDate;
  final String dateFormat;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final timestamps =
        intervals
            .expand((interval) => [interval.startTime, interval.endTime])
            .where(
              (timestamp) => timestamp != axisStart && timestamp != axisEnd,
            )
            .toSet()
            .toList()
          ..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = crossesDate
            ? (dateFormat.startsWith('yyyy') ? 88.0 : 52.0)
            : 42.0;
        final rowHeight = crossesDate ? 26.0 : 14.0;
        final width = constraints.maxWidth;
        final duration = axisEnd - axisStart;
        if (timestamps.isEmpty || width <= 0 || duration <= 0) {
          return const SizedBox.shrink();
        }

        final laneEnds = <double>[];
        final markers = <({int timestamp, double left, int lane})>[];
        for (final timestamp in timestamps) {
          final center =
              ((timestamp - axisStart) / duration).clamp(0.0, 1.0) * width;
          final left = (center - labelWidth / 2)
              .clamp(0.0, math.max(0.0, width - labelWidth))
              .toDouble();
          var lane = laneEnds.indexWhere((end) => left >= end + 2);
          if (lane < 0) {
            lane = laneEnds.length;
            laneEnds.add(left + labelWidth);
          } else {
            laneEnds[lane] = left + labelWidth;
          }
          markers.add((timestamp: timestamp, left: left, lane: lane));
        }

        return SizedBox(
          height: laneEnds.length * rowHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final marker in markers)
                Positioned(
                  left: marker.left,
                  top: marker.lane * rowHeight,
                  width: labelWidth,
                  child: _TimelineMarkerLabel(
                    timestamp: marker.timestamp,
                    crossesDate: crossesDate,
                    dateFormat: dateFormat,
                    colors: colors,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineMarkerLabel extends StatelessWidget {
  const _TimelineMarkerLabel({
    required this.timestamp,
    required this.crossesDate,
    required this.dateFormat,
    required this.colors,
  });

  final int timestamp;
  final bool crossesDate;
  final String dateFormat;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final style = TextStyle(
      color: colors.onSurface,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 1,
    );
    if (!crossesDate) {
      return Text(
        TimeLogSaveConfirmationDialog._hourMinuteFormat.format(dateTime),
        textAlign: TextAlign.center,
        style: style,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat(dateFormat.split(' ').first).format(dateTime),
          textAlign: TextAlign.center,
          style: style,
        ),
        Text(
          TimeLogSaveConfirmationDialog._hourMinuteFormat.format(dateTime),
          textAlign: TextAlign.center,
          style: style,
        ),
      ],
    );
  }
}

class _TimelineTrack extends StatelessWidget {
  const _TimelineTrack({
    required this.label,
    required this.axisStart,
    required this.axisEnd,
    required this.rangeStart,
    required this.rangeEnd,
    required this.overlapIntervals,
    required this.rangeColor,
    required this.colors,
  });

  final String label;
  final int axisStart;
  final int axisEnd;
  final int rangeStart;
  final int rangeEnd;
  final List<TimeLogOverlapInterval> overlapIntervals;
  final Color rangeColor;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 42,
        child: Text(
          label,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Expanded(
        child: SizedBox(
          height: 14,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _TimelineTrackPainter(
                axisStart: axisStart,
                axisEnd: axisEnd,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                overlapIntervals: overlapIntervals,
                rangeColor: rangeColor,
                trackColor: colors.surfaceContainerHighest,
                overlapColor: colors.error,
                markerColor: colors.onSurface,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _TimelineTrackPainter extends CustomPainter {
  const _TimelineTrackPainter({
    required this.axisStart,
    required this.axisEnd,
    required this.rangeStart,
    required this.rangeEnd,
    required this.overlapIntervals,
    required this.rangeColor,
    required this.trackColor,
    required this.overlapColor,
    required this.markerColor,
  });

  final int axisStart;
  final int axisEnd;
  final int rangeStart;
  final int rangeEnd;
  final List<TimeLogOverlapInterval> overlapIntervals;
  final Color rangeColor;
  final Color trackColor;
  final Color overlapColor;
  final Color markerColor;

  static final Paint _backgroundPaint = Paint();
  static final Paint _intervalPaint = Paint();
  static final Paint _markerPaint = Paint()..strokeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 10.0;
    final top = (size.height - barHeight) / 2;
    final radius = Radius.circular(barHeight / 2);
    _backgroundPaint.color = trackColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width, barHeight),
        radius,
      ),
      _backgroundPaint,
    );

    final duration = axisEnd - axisStart;
    if (duration <= 0 || size.width <= 0) return;
    double xFor(int timestamp) =>
        ((timestamp - axisStart) / duration).clamp(0.0, 1.0) * size.width;

    void drawInterval(int start, int end, Color color) {
      final left = xFor(start);
      final right = xFor(end);
      if (right <= left) return;
      _intervalPaint.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, right - left, barHeight),
          radius,
        ),
        _intervalPaint,
      );
    }

    drawInterval(rangeStart, rangeEnd, rangeColor);
    for (final interval in overlapIntervals) {
      drawInterval(interval.startTime, interval.endTime, overlapColor);
    }
    _markerPaint.color = markerColor;
    for (final interval in overlapIntervals) {
      for (final timestamp in [interval.startTime, interval.endTime]) {
        final x = xFor(timestamp);
        canvas.drawLine(
          Offset(x, top - 2),
          Offset(x, top + barHeight + 2),
          _markerPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineTrackPainter oldDelegate) =>
      oldDelegate.axisStart != axisStart ||
      oldDelegate.axisEnd != axisEnd ||
      oldDelegate.rangeStart != rangeStart ||
      oldDelegate.rangeEnd != rangeEnd ||
      oldDelegate.overlapIntervals != overlapIntervals ||
      oldDelegate.rangeColor != rangeColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.overlapColor != overlapColor ||
      oldDelegate.markerColor != markerColor;
}

class _TimelineLegendItem extends StatelessWidget {
  const _TimelineLegendItem({
    required this.color,
    required this.label,
    required this.colors,
  });

  final Color color;
  final String label;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 10),
      ),
    ],
  );
}
