part of '../time_log_screen.dart';

// ══════════════════════════════════════════════════════════
// 周视图静态网格 Painter
// ══════════════════════════════════════════════════════════
class _WeekGridPainter extends CustomPainter {
  final double hourH;
  final Color majorLineColor;
  final Color minorLineColor;
  static final Paint _gridPaint = Paint()..strokeWidth = 0.5;

  _WeekGridPainter({
    required this.hourH,
    required this.majorLineColor,
    required this.minorLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int hour = 0; hour <= 24; hour++) {
      final y = hour * hourH;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        _gridPaint..color = hour % 6 == 0 ? majorLineColor : minorLineColor,
      );
    }
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      _gridPaint..color = majorLineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _WeekGridPainter oldDelegate) =>
      oldDelegate.hourH != hourH ||
      oldDelegate.majorLineColor != majorLineColor ||
      oldDelegate.minorLineColor != minorLineColor;
}

// ══════════════════════════════════════════════════════════
// 周视图区块 Painter
// ══════════════════════════════════════════════════════════
class _WeekColBlockVisual {
  final Color color;
  final Color? secondaryColor;
  final String title;
  final double top;
  final double bottom;
  final double staggerDelay;
  final double staggerProgressScale;
  final int extraCount;

  const _WeekColBlockVisual({
    required this.color,
    this.secondaryColor,
    required this.title,
    required this.top,
    required this.bottom,
    required this.staggerDelay,
    required this.staggerProgressScale,
    this.extraCount = 0,
  });
}

@visibleForTesting
class ScheduleCluster {
  final List<TimeLogMappedSchedule> schedules;
  final int startTime;
  final int endTime;

  const ScheduleCluster({
    required this.schedules,
    required this.startTime,
    required this.endTime,
  });

  bool get isAggregated => schedules.length > 1;
  int get extraCount => schedules.length - 1;
  TimeLogMappedSchedule get primary => schedules.first;
}

@visibleForTesting
List<ScheduleCluster> clusterTimeLogSchedules(
  List<TimeLogMappedSchedule> schedules,
  int dayStartMs,
  int dayEndMs,
) {
  if (schedules.isEmpty) return const [];

  final valid =
      schedules
          .where((s) => s.endTime > dayStartMs && s.startTime < dayEndMs)
          .toList()
        ..sort((a, b) {
          final cmpStart = a.startTime.compareTo(b.startTime);
          if (cmpStart != 0) return cmpStart;
          final cmpEnd = a.endTime.compareTo(b.endTime);
          if (cmpEnd != 0) return cmpEnd;
          if (a.isCourse != b.isCourse) {
            return a.isCourse ? -1 : 1;
          }
          return a.id.compareTo(b.id);
        });

  if (valid.isEmpty) return const [];

  final List<ScheduleCluster> clusters = [];
  var currentGroup = <TimeLogMappedSchedule>[valid.first];
  var groupStart = max(valid.first.startTime, dayStartMs);
  var groupEnd = min(valid.first.endTime, dayEndMs);

  for (int i = 1; i < valid.length; i++) {
    final s = valid[i];
    final sStart = max(s.startTime, dayStartMs);
    final sEnd = min(s.endTime, dayEndMs);

    if (sStart < groupEnd) {
      currentGroup.add(s);
      if (sEnd > groupEnd) groupEnd = sEnd;
      if (sStart < groupStart) groupStart = sStart;
    } else {
      clusters.add(
        ScheduleCluster(
          schedules: currentGroup,
          startTime: groupStart,
          endTime: groupEnd,
        ),
      );
      currentGroup = [s];
      groupStart = sStart;
      groupEnd = sEnd;
    }
  }

  clusters.add(
    ScheduleCluster(
      schedules: currentGroup,
      startTime: groupStart,
      endTime: groupEnd,
    ),
  );

  return clusters;
}

@visibleForTesting
class WeekColPainter extends CustomPainter {
  final List<TimeLogItem> dayLogs;
  final List<PomodoroRecord> dayPoms;
  final List<TimeLogMappedSchedule> daySchedules;
  final List<PomodoroTag> tags;
  final int dayStartMs;
  final int dayEndMs;
  final bool isDark;
  final double hourH;
  final Animation<double> animation;
  final Color focusColor;
  final Color logColor;
  static final Paint _blockPaint = Paint();
  late final Map<String, int> _tagIndicesByUuid =
      _DayGridPainter._buildTagIndices(tags);
  late final List<ScheduleCluster> _scheduleClusters = clusterTimeLogSchedules(
    daySchedules,
    dayStartMs,
    dayEndMs,
  );
  int _staggerBlockIndex = 0;
  late final int _totalBlockCount =
      dayPoms.length + dayLogs.length + _scheduleClusters.length;

  double _staggerDelayFor(double top, double bottom) {
    if (bottom <= top + 1) return 0.0;
    final delay = _totalBlockCount > 0
        ? _staggerBlockIndex / _totalBlockCount
        : 0.0;
    _staggerBlockIndex++;
    return delay;
  }

  @visibleForTesting
  List<String> get scheduleBlockTitles =>
      _scheduleVisuals.map((v) => v.title).toList();

  @visibleForTesting
  List<int> get scheduleBlockExtraCounts =>
      _scheduleVisuals.map((v) => v.extraCount).toList();

  late final List<_WeekColBlockVisual> _scheduleVisuals = _scheduleClusters
      .map((cluster) {
        final primary = cluster.primary;
        final isCourse = primary.isCourse;
        final base = isCourse
            ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
            : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
        Color? secondaryBase;
        if (cluster.isAggregated) {
          final secondary = cluster.schedules[1];
          secondaryBase = secondary.isCourse
              ? (isDark ? const Color(0xFF64B5F6) : const Color(0xFF1E88E5))
              : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFFB8C00));
        }
        final top = (cluster.startTime - dayStartMs) / 3600000 * hourH;
        final bottom = (cluster.endTime - dayStartMs) / 3600000 * hourH;
        final staggerDelay = _staggerDelayFor(top, bottom);
        return _WeekColBlockVisual(
          color: base.withValues(alpha: isDark ? 0.35 : 0.30),
          secondaryColor: secondaryBase?.withValues(
            alpha: isDark ? 0.35 : 0.30,
          ),
          title: primary.title.trim().isNotEmpty
              ? primary.title.trim()
              : (isCourse ? '课程' : '日程'),
          top: top,
          bottom: bottom,
          staggerDelay: staggerDelay,
          staggerProgressScale: 1.0 / (1.0 - staggerDelay),
          extraCount: cluster.extraCount,
        );
      })
      .toList(growable: false);
  late final List<_WeekColBlockVisual> _pomodoroVisuals = dayPoms
      .map((pomodoro) {
        final tag = _matchingTag(pomodoro.tagUuids);
        final end =
            pomodoro.endTime ??
            (pomodoro.startTime + pomodoro.effectiveDuration * 1000);
        final rangeStart = max(pomodoro.startTime, dayStartMs);
        final rangeEnd = min(end, dayEndMs);
        final top = (rangeStart - dayStartMs) / 3600000 * hourH;
        final bottom = (rangeEnd - dayStartMs) / 3600000 * hourH;
        final staggerDelay = _staggerDelayFor(top, bottom);
        return _WeekColBlockVisual(
          color: tag == null
              ? focusColor.withValues(alpha: 0.45)
              : hexColor(tag.color, opacity: 0.45),
          title: tag?.name ?? '专注',
          top: top,
          bottom: bottom,
          staggerDelay: staggerDelay,
          staggerProgressScale: 1.0 / (1.0 - staggerDelay),
        );
      })
      .toList(growable: false);
  late final List<_WeekColBlockVisual> _logVisuals = dayLogs
      .map((log) {
        final tag = _matchingTag(log.tagUuids);
        final title = log.title.isNotEmpty ? log.title : '补录';
        final rangeStart = max(log.startTime, dayStartMs);
        final rangeEnd = min(log.endTime, dayEndMs);
        final top = (rangeStart - dayStartMs) / 3600000 * hourH;
        final bottom = (rangeEnd - dayStartMs) / 3600000 * hourH;
        final staggerDelay = _staggerDelayFor(top, bottom);
        return _WeekColBlockVisual(
          color: tag == null
              ? logColor.withValues(alpha: 0.45)
              : hexColor(tag.color, opacity: 0.45),
          title: tag != null && title == '补录' ? tag.name : title,
          top: top,
          bottom: bottom,
          staggerDelay: staggerDelay,
          staggerProgressScale: 1.0 / (1.0 - staggerDelay),
        );
      })
      .toList(growable: false);

  WeekColPainter({
    required this.dayLogs,
    this.dayPoms = const [],
    this.daySchedules = const [],
    required this.tags,
    required this.dayStartMs,
    required this.dayEndMs,
    required this.isDark,
    required this.hourH,
    required this.animation,
    required this.focusColor,
    required this.logColor,
  }) : super(repaint: animation);

  PomodoroTag? _matchingTag(List<String> tagUuids) {
    if (tagUuids.isEmpty) return null;
    int? firstIndex;
    for (final uuid in tagUuids) {
      final index = _tagIndicesByUuid[uuid];
      if (index != null && (firstIndex == null || index < firstIndex)) {
        firstIndex = index;
      }
    }
    return firstIndex == null ? null : tags[firstIndex];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final animationProgress = animation.value;
    TextPainter? titlePainter;
    TextPainter getTitlePainter() => titlePainter ??= TextPainter(
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );

    void block(
      _WeekColBlockVisual visual,
      bool isPom, {
      bool isSchedule = false,
    }) {
      final top = visual.top;
      final bot = visual.bottom;
      if (bot <= top + 1) return;

      final blockProgress =
          ((animationProgress - visual.staggerDelay) *
                  visual.staggerProgressScale)
              .clamp(0.0, 1.0);
      if (blockProgress <= 0.0) return;

      final animatedBot = top + (bot - top) * blockProgress;

      // 如果有重叠折叠项，先画底部叠牌阴影层，体现多张卡片折叠效果（参考周视图）
      if (visual.extraCount > 0) {
        final secColor = visual.secondaryColor ?? visual.color;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(4.5, top + 2.0, size.width, animatedBot + 2.0),
            const Radius.circular(3),
          ),
          _blockPaint
            ..color = secColor.withValues(
              alpha: (isSchedule ? 0.24 : 0.30) * blockProgress,
            ),
        );
      }

      // 左侧指示条
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, top + 0.5, 3, animatedBot - 0.5),
          const Radius.circular(2),
        ),
        _blockPaint
          ..color = visual.color.withValues(
            alpha: (isSchedule ? 0.75 : 0.9) * blockProgress,
          ),
      );

      // 主体卡片
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            3,
            top + 0.5,
            size.width - (visual.extraCount > 0 ? 2 : 1),
            animatedBot - 0.5,
          ),
          const Radius.circular(3),
        ),
        _blockPaint
          ..color = visual.color.withValues(
            alpha: (isSchedule ? 0.16 : (isPom ? 0.22 : 0.35)) * blockProgress,
          ),
      );

      final blockH = animatedBot - top;
      final blockW = size.width - 6;

      if (blockH >= 10 && blockW >= 8 && blockProgress > 0.5) {
        if (blockH >= 18) {
          final fontSize = (blockH * 0.22).clamp(7.5, blockW > 60 ? 11.0 : 9.0);
          final lineHeight = fontSize * 1.15;
          final availableH = visual.extraCount > 0 && blockH >= 28
              ? blockH - 12.0
              : blockH;
          final maxLines = max(1, ((availableH - 4) / lineHeight).floor());
          final tp = getTitlePainter()
            ..maxLines = maxLines
            ..text = TextSpan(
              text: visual.title,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.15,
                color: visual.color.withValues(alpha: 0.95 * blockProgress),
                fontWeight: FontWeight.w700,
              ),
            )
            ..layout(maxWidth: max(4.0, blockW - 4));
          final textTop = visual.extraCount > 0 && blockH >= 28
              ? top + 3.0
              : top + max(2.0, (blockH - tp.height) / 2);
          tp.paint(canvas, Offset(5, textTop));
        } else {
          final tp = getTitlePainter()
            ..maxLines = 1
            ..text = TextSpan(
              text: visual.title,
              style: TextStyle(
                fontSize: 7.0,
                color: visual.color.withValues(alpha: 0.85 * blockProgress),
                fontWeight: FontWeight.w700,
              ),
            )
            ..layout(maxWidth: max(2.0, blockH - 2));

          canvas.save();
          canvas.translate(5 + tp.height, top + 1);
          canvas.rotate(pi / 2);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
        }

        // 右下角 +N 角标（参考周视图）
        if (visual.extraCount > 0 && blockH >= 16) {
          final badgeTp = TextPainter(
            text: TextSpan(
              text: '+${visual.extraCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 7.5,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout();

          const badgePadH = 3.0;
          const badgePadV = 1.5;
          final badgeW = badgeTp.width + badgePadH * 2;
          final badgeH = badgeTp.height + badgePadV * 2;
          final badgeRight = size.width - 3.5;
          final badgeBottom = animatedBot - 2.5;
          final badgeLeft = badgeRight - badgeW;
          final badgeTop = badgeBottom - badgeH;

          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(badgeLeft, badgeTop, badgeW, badgeH),
              const Radius.circular(3.0),
            ),
            _blockPaint
              ..color = (isDark ? Colors.black : const Color(0xFF1E293B))
                  .withValues(alpha: 0.75 * blockProgress),
          );

          badgeTp.paint(
            canvas,
            Offset(badgeLeft + badgePadH, badgeTop + badgePadV),
          );
          badgeTp.dispose();
        }
      }
    }

    try {
      // 先画排程（课程 / 日程）
      for (var i = 0; i < _scheduleVisuals.length; i++) {
        final visual = _scheduleVisuals[i];
        block(visual, false, isSchedule: true);
      }

      // 画番茄钟（★ 传入 title）
      for (var i = 0; i < dayPoms.length; i++) {
        final visual = _pomodoroVisuals[i];
        block(visual, true);
      }

      // 画补录日志（★ 传入 title）
      for (var i = 0; i < dayLogs.length; i++) {
        final visual = _logVisuals[i];
        block(visual, false);
      }
    } finally {
      titlePainter?.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant WeekColPainter o) =>
      o.isDark != isDark ||
      o.hourH != hourH ||
      o.dayLogs != dayLogs ||
      o.dayPoms != dayPoms ||
      o.daySchedules != daySchedules ||
      o.tags != tags ||
      o.dayStartMs != dayStartMs ||
      o.dayEndMs != dayEndMs ||
      o.animation != animation ||
      o.focusColor != focusColor ||
      o.logColor != logColor;
}

typedef _WeekColPainter = WeekColPainter;
