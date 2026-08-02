import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/habit_adaptation_service.dart';

/// 领域化建议面板：可用于新建/编辑页和习惯详情页。
class HabitAdaptationPanel extends StatelessWidget {
  final HabitAdaptation adaptation;
  final double? currentValue;
  final double? targetValue;
  final ValueChanged<int>? onTargetSelected;
  final bool showTargetSuggestions;

  const HabitAdaptationPanel({
    super.key,
    required this.adaptation,
    this.currentValue,
    this.targetValue,
    this.onTargetSelected,
    this.showTargetSuggestions = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final adaptationIcon = switch (adaptation.kind) {
      HabitAdaptationKind.hydration => Icons.water_drop_rounded,
      HabitAdaptationKind.earlyWake => Icons.wb_sunny_rounded,
      HabitAdaptationKind.earlySleep => Icons.bedtime_rounded,
    };
    final progress =
        currentValue != null && targetValue != null && targetValue! > 0
            ? (currentValue! / targetValue!).clamp(0.0, 1.0)
            : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(adaptationIcon, color: colorScheme.tertiary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  adaptation.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              IconButton(
                tooltip: '查看参考文献',
                visualDensity: VisualDensity.compact,
                onPressed: () => showHabitCitations(context, adaptation),
                icon: Icon(Icons.menu_book_outlined,
                    size: 19, color: colorScheme.onTertiaryContainer),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            adaptation.headline,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            adaptation.explanation,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: colorScheme.onTertiaryContainer.withValues(alpha: 0.85),
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: colorScheme.onTertiaryContainer
                          .withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(colorScheme.tertiary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_amount(currentValue!)} / ${_amount(targetValue!)} ml',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ],
          if (showTargetSuggestions && onTargetSelected != null) ...[
            const SizedBox(height: 12),
            Text(
              adaptation.targetSuggestionTitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: adaptation.targetSuggestions.map((suggestion) {
                final selected = targetValue == suggestion.value;
                return ChoiceChip(
                  selected: selected,
                  label: Text(
                    '${suggestion.label} '
                    '${suggestion.displayValue ?? '${suggestion.value} ${adaptation.targetUnit}'}',
                  ),
                  onSelected: (_) => onTargetSelected!(suggestion.value),
                  selectedColor: colorScheme.tertiary,
                  labelStyle: TextStyle(
                    color: selected
                        ? colorScheme.onTertiary
                        : colorScheme.onTertiaryContainer,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            adaptation.safetyNote,
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: colorScheme.onTertiaryContainer.withValues(alpha: 0.75),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showHabitCitations(context, adaptation),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('查看参考文献'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onTertiaryContainer,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _amount(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }
}

/// 早起 / 早睡的时间关系提示。
///
/// 目标时间不是医学上的统一标准，这里只根据 7–9 小时的常用成人睡眠
/// 建议做反推，帮助用户发现目标时间是否会压缩睡眠。
class HabitSleepTimingGuide extends StatelessWidget {
  final HabitAdaptation adaptation;
  final int targetMinute;
  final ValueChanged<int>? onTargetChanged;

  const HabitSleepTimingGuide({
    super.key,
    required this.adaptation,
    required this.targetMinute,
    this.onTargetChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWake = adaptation.kind == HabitAdaptationKind.earlyWake;
    final counterpartMinute =
        isWake ? targetMinute - 8 * 60 : targetMinute + 8 * 60;
    final counterpartLabel = isWake ? '建议入睡' : '建议起床';
    final counterpartRange = isWake
        ? '${_formatMinute(targetMinute - 9 * 60)}–'
            '${_formatMinute(targetMinute - 7 * 60)}'
        : '${_formatMinute(targetMinute + 7 * 60)}–'
            '${_formatMinute(targetMinute + 9 * 60)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bedtime_outlined,
                  size: 19, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '睡眠时间反推',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '7–9 小时',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          HabitSleepClock(
            goalMinute: targetMinute,
            goalLabel: isWake ? '目标起床' : '目标入睡',
            counterpartMinute: counterpartMinute,
            counterpartLabel: counterpartLabel,
            counterpartRangeLabel: counterpartRange,
            goalIsSleep: !isWake,
            onTargetChanged: onTargetChanged,
          ),
          const SizedBox(height: 10),
          if (onTargetChanged != null)
            Text(
              '拖动目标时针调整小时，拖动分针调整分钟；起床标记会随睡眠时长同步反推。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          if (onTargetChanged != null) const SizedBox(height: 6),
          Text(
            '目标时间只是可持续作息的锚点；尽量让入睡和起床时间每天保持相近，周末也不要大幅漂移。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMinute(int minute) {
    final normalized = minute % (24 * 60);
    final safe = normalized < 0 ? normalized + 24 * 60 : normalized;
    final hour = safe ~/ 60;
    final min = safe % 60;
    return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }
}

/// 新建配对目标时，展示已有早睡 / 早起目标反推出的建议。
class HabitSleepPairSuggestionCard extends StatelessWidget {
  final HabitSleepPairSuggestion suggestion;
  final int currentTargetMinute;
  final ValueChanged<int> onApply;

  const HabitSleepPairSuggestionCard({
    super.key,
    required this.suggestion,
    required this.currentTargetMinute,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final targetLabel =
        suggestion.targetKind == HabitAdaptationKind.earlyWake ? '早起' : '早睡';
    final sourceLabel =
        suggestion.sourceKind == HabitAdaptationKind.earlyWake ? '早起' : '早睡';
    final applied = currentTargetMinute == suggestion.recommendedMinute;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_alt_rounded,
                  size: 19, color: colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '根据已有目标自动反推',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (applied)
                Icon(Icons.check_circle_rounded,
                    size: 18, color: colorScheme.onSecondaryContainer),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '已有「${suggestion.sourceName}」$sourceLabel目标 '
            '${_formatMinute(suggestion.sourceMinute)}：'
            '建议将「$targetLabel」设置为 ${_formatMinute(suggestion.recommendedMinute)}。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '按 7–9 小时睡眠反推的建议区间：'
            '${_formatMinute(suggestion.rangeStartMinute)}–'
            '${_formatMinute(suggestion.rangeEndMinute)}。默认先采用 8 小时，可手动修改。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: colorScheme.onSecondaryContainer.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed:
                  applied ? null : () => onApply(suggestion.recommendedMinute),
              icon: Icon(
                applied ? Icons.check_rounded : Icons.auto_awesome_rounded,
                size: 16,
              ),
              label: Text(applied ? '已应用建议' : '应用 8 小时建议'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMinute(int minute) {
    final normalized = minute % (24 * 60);
    final safe = normalized < 0 ? normalized + 24 * 60 : normalized;
    final hour = safe ~/ 60;
    final min = safe % 60;
    return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }
}

/// 一个可交互的大时钟：目标时间使用时针 / 分针，另一端使用彩色标记。
///
/// 目标时间只保存一个时间点；拖动另一端的起床 / 入睡标记时，会按 8 小时
/// 反推目标时间，避免引入第二个不落库的目标字段。
class HabitSleepClock extends StatefulWidget {
  final int goalMinute;
  final String goalLabel;
  final int counterpartMinute;
  final String counterpartLabel;
  final String? counterpartRangeLabel;
  final bool goalIsSleep;
  final ValueChanged<int>? onTargetChanged;

  const HabitSleepClock({
    super.key,
    required this.goalMinute,
    required this.goalLabel,
    required this.counterpartMinute,
    required this.counterpartLabel,
    required this.counterpartRangeLabel,
    required this.goalIsSleep,
    this.onTargetChanged,
  });

  @override
  State<HabitSleepClock> createState() => _HabitSleepClockState();
}

enum _SleepClockDragMode { hour, minute, counterpart }

class _HabitSleepClockState extends State<HabitSleepClock> {
  _SleepClockDragMode? _dragMode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final goalText = _formatMinute(widget.goalMinute);
    final counterpartText = _formatMinute(widget.counterpartMinute);
    return Column(
      children: [
        Semantics(
          container: true,
          label: '${widget.goalLabel} $goalText，'
              '${widget.counterpartLabel} $counterpartText'
              '${widget.counterpartRangeLabel == null ? '' : '，建议窗口 ${widget.counterpartRangeLabel}'}',
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 320,
                maxHeight: 320,
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: widget.onTargetChanged == null
                          ? null
                          : (details) =>
                              _startDrag(details.localPosition, size),
                      onPanUpdate: widget.onTargetChanged == null
                          ? null
                          : (details) =>
                              _updateDrag(details.localPosition, size),
                      onPanEnd: widget.onTargetChanged == null
                          ? null
                          : (_) => setState(() => _dragMode = null),
                      onPanCancel: widget.onTargetChanged == null
                          ? null
                          : () => setState(() => _dragMode = null),
                      child: CustomPaint(
                        painter: _SleepScheduleClockPainter(
                          goalMinute: widget.goalMinute,
                          counterpartMinute: widget.counterpartMinute,
                          goalIsSleep: widget.goalIsSleep,
                          activeMode: _dragMode,
                          colorScheme: colorScheme,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 5,
          children: [
            _SleepClockLegend(
              color: colorScheme.primary,
              label: '${widget.goalLabel} $goalText',
              colorScheme: colorScheme,
            ),
            _SleepClockLegend(
              color: colorScheme.tertiary,
              label: '${widget.counterpartLabel} $counterpartText',
              colorScheme: colorScheme,
            ),
          ],
        ),
        if (widget.counterpartRangeLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            '建议窗口 ${widget.counterpartRangeLabel}',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  void _startDrag(Offset position, Size size) {
    final geometry = _SleepClockGeometry.fromSize(size);
    final points = <_SleepClockDragMode, Offset>{
      _SleepClockDragMode.hour:
          geometry.handTip(widget.goalMinute, geometry.hourHandLength),
      _SleepClockDragMode.minute: geometry.minuteHandTip(widget.goalMinute),
      _SleepClockDragMode.counterpart:
          geometry.timeMarker(widget.counterpartMinute),
    };
    final nearest = points.entries.reduce(
      (a, b) => (position - a.value).distance <= (position - b.value).distance
          ? a
          : b,
    );
    if ((position - nearest.value).distance > geometry.hitRadius) return;
    setState(() => _dragMode = nearest.key);
  }

  void _updateDrag(Offset position, Size size) {
    final mode = _dragMode;
    if (mode == null || widget.onTargetChanged == null) return;
    final angle = _SleepClockGeometry.angleFromTop(
      position,
      _SleepClockGeometry.fromSize(size).center,
    );
    final next = switch (mode) {
      _SleepClockDragMode.hour => _targetFromHour(angle),
      _SleepClockDragMode.minute => _targetFromMinute(angle),
      _SleepClockDragMode.counterpart => _targetFromCounterpart(angle),
    };
    widget.onTargetChanged!(next);
  }

  int _targetFromHour(double angle) {
    final dialHour = (angle / (2 * math.pi) * 12).round() % 12;
    final currentHour = (widget.goalMinute ~/ 60) % 24;
    int nextHour;
    if (widget.goalIsSleep && dialHour == 0) {
      nextHour = 0;
    } else if (widget.goalIsSleep && dialHour >= 10) {
      nextHour = dialHour + 12;
    } else if (widget.goalIsSleep && currentHour >= 18 && dialHour >= 5) {
      nextHour = dialHour + 12;
    } else {
      nextHour = dialHour;
    }
    return nextHour * 60 + widget.goalMinute % 60;
  }

  int _targetFromMinute(double angle) {
    final minute = (angle / (2 * math.pi) * 60).round() % 60;
    final current = widget.goalMinute;
    final currentHour = (current ~/ 60) * 60;
    final candidates = [
      currentHour - 60 + minute,
      currentHour + minute,
      currentHour + 60 + minute,
    ];
    final nearest = candidates.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );
    return _normalizeMinute(nearest);
  }

  int _targetFromCounterpart(double angle) {
    final twelveHourMinute =
        (angle / (2 * math.pi) * 12 * 60).round() % (12 * 60);
    final current = widget.counterpartMinute;
    final candidates = [twelveHourMinute, twelveHourMinute + 12 * 60];
    final nextCounterpart = candidates.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );
    return widget.goalIsSleep
        ? _normalizeMinute(nextCounterpart - 8 * 60)
        : _normalizeMinute(nextCounterpart + 8 * 60);
  }

  String _formatMinute(int minute) {
    final safe = _normalizeMinute(minute);
    return '${(safe ~/ 60).toString().padLeft(2, '0')}:${(safe % 60).toString().padLeft(2, '0')}';
  }

  int _normalizeMinute(int minute) {
    final normalized = minute % (24 * 60);
    return normalized < 0 ? normalized + 24 * 60 : normalized;
  }
}

class _SleepClockLegend extends StatelessWidget {
  final Color color;
  final String label;
  final ColorScheme colorScheme;

  const _SleepClockLegend({
    required this.color,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _SleepClockGeometry {
  final Offset center;
  final double radius;

  const _SleepClockGeometry(this.center, this.radius);

  double get hourHandLength => radius * 0.47;
  double get minuteHandLength => radius * 0.7;
  double get hitRadius => math.max(28, radius * 0.18);

  factory _SleepClockGeometry.fromSize(Size size) {
    return _SleepClockGeometry(
      Offset(size.width / 2, size.height / 2),
      math.min(size.width, size.height) / 2 - 14,
    );
  }

  Offset handTip(int minute, double length) {
    return _pointAt(_hourAngle(minute), length);
  }

  Offset minuteHandTip(int minute) {
    return _pointAt(_minuteAngle(minute), minuteHandLength);
  }

  Offset timeMarker(int minute) {
    return _pointAt(_timeAngle(minute), radius * 0.88);
  }

  Offset _pointAt(double angle, double length) {
    return Offset(
      center.dx + math.cos(angle) * length,
      center.dy + math.sin(angle) * length,
    );
  }

  double _hourAngle(int minute) {
    final normalized = _normalizeMinute(minute);
    final hour = (normalized ~/ 60) % 12 + (normalized % 60) / 60;
    return hour * math.pi / 6 - math.pi / 2;
  }

  double _minuteAngle(int minute) {
    return (minute % 60) * math.pi / 30 - math.pi / 2;
  }

  double _timeAngle(int minute) {
    final twelveHourMinute = _normalizeMinute(minute) % (12 * 60);
    return twelveHourMinute * math.pi / (6 * 60) - math.pi / 2;
  }

  static double angleFromTop(Offset position, Offset center) {
    var angle = math.atan2(position.dy - center.dy, position.dx - center.dx) +
        math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    return angle;
  }

  static int _normalizeMinute(int minute) {
    final normalized = minute % (24 * 60);
    return normalized < 0 ? normalized + 24 * 60 : normalized;
  }
}

class _SleepScheduleClockPainter extends CustomPainter {
  final int goalMinute;
  final int counterpartMinute;
  final bool goalIsSleep;
  final _SleepClockDragMode? activeMode;
  final ColorScheme colorScheme;

  const _SleepScheduleClockPainter({
    required this.goalMinute,
    required this.counterpartMinute,
    required this.goalIsSleep,
    required this.activeMode,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _SleepClockGeometry.fromSize(size);
    final center = geometry.center;
    final radius = geometry.radius;
    final primary = colorScheme.primary;
    final secondary = colorScheme.tertiary;
    final face = Paint()..color = colorScheme.surfaceContainerHighest;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = colorScheme.outlineVariant;
    canvas.drawCircle(center, radius, face);
    canvas.drawCircle(center, radius, outline);

    _drawSleepArc(canvas, geometry, primary, secondary);
    _drawTicksAndLabels(canvas, geometry);
    _drawCounterpartMarker(canvas, geometry, secondary);
    _drawTargetHands(canvas, geometry, primary);
  }

  void _drawSleepArc(
    Canvas canvas,
    _SleepClockGeometry geometry,
    Color primary,
    Color secondary,
  ) {
    final startMinute = goalIsSleep ? goalMinute : counterpartMinute;
    final endMinute = goalIsSleep ? counterpartMinute : goalMinute;
    final start = _SleepClockGeometry.angleFromTop(
            geometry.timeMarker(startMinute), geometry.center) -
        math.pi / 2;
    final end = _SleepClockGeometry.angleFromTop(
            geometry.timeMarker(endMinute), geometry.center) -
        math.pi / 2;
    var sweep = end - start;
    if (sweep < 0) sweep += 2 * math.pi;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = secondary.withValues(alpha: 0.35);
    final rect =
        Rect.fromCircle(center: geometry.center, radius: geometry.radius - 7);
    canvas.drawArc(rect, start, sweep, false, arc);
  }

  void _drawTicksAndLabels(Canvas canvas, _SleepClockGeometry geometry) {
    for (var index = 0; index < 60; index++) {
      final angle = index * math.pi / 30 - math.pi / 2;
      final major = index % 5 == 0;
      final outer = geometry.radius - 4;
      final inner = geometry.radius - (major ? 16 : 10);
      final tick = Paint()
        ..color =
            major ? colorScheme.onSurfaceVariant : colorScheme.outlineVariant
        ..strokeWidth = major ? 2 : 1
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(
          geometry.center.dx + math.cos(angle) * inner,
          geometry.center.dy + math.sin(angle) * inner,
        ),
        Offset(
          geometry.center.dx + math.cos(angle) * outer,
          geometry.center.dy + math.sin(angle) * outer,
        ),
        tick,
      );
      if (major) {
        final number = index ~/ 5 == 0 ? '12' : '${index ~/ 5}';
        final textPainter = TextPainter(
          text: TextSpan(
            text: number,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelRadius = geometry.radius - 31;
        final labelCenter = Offset(
          geometry.center.dx + math.cos(angle) * labelRadius,
          geometry.center.dy + math.sin(angle) * labelRadius,
        );
        textPainter.paint(
          canvas,
          labelCenter - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }
  }

  void _drawCounterpartMarker(
    Canvas canvas,
    _SleepClockGeometry geometry,
    Color color,
  ) {
    final marker = geometry.timeMarker(counterpartMinute);
    final markerPaint = Paint()..color = color;
    canvas.drawCircle(marker,
        activeMode == _SleepClockDragMode.counterpart ? 14 : 11, markerPaint);
    canvas.drawCircle(
      marker,
      4,
      Paint()..color = colorScheme.onTertiary,
    );
  }

  void _drawTargetHands(
    Canvas canvas,
    _SleepClockGeometry geometry,
    Color color,
  ) {
    final hourTip = geometry.handTip(goalMinute, geometry.hourHandLength);
    final minuteTip = geometry.minuteHandTip(goalMinute);
    _drawHand(canvas, geometry.center, hourTip, color, 6,
        activeMode == _SleepClockDragMode.hour);
    _drawHand(canvas, geometry.center, minuteTip, color, 3.5,
        activeMode == _SleepClockDragMode.minute);
    canvas.drawCircle(geometry.center, 7, Paint()..color = color);
    canvas.drawCircle(
      geometry.center,
      3,
      Paint()..color = colorScheme.onPrimary,
    );
  }

  void _drawHand(
    Canvas canvas,
    Offset center,
    Offset tip,
    Color color,
    double strokeWidth,
    bool active,
  ) {
    final hand = Paint()
      ..color = active ? color : color.withValues(alpha: 0.9)
      ..strokeWidth = active ? strokeWidth + 2 : strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, tip, hand);
  }

  @override
  bool shouldRepaint(covariant _SleepScheduleClockPainter oldDelegate) {
    return oldDelegate.goalMinute != goalMinute ||
        oldDelegate.counterpartMinute != counterpartMinute ||
        oldDelegate.goalIsSleep != goalIsSleep ||
        oldDelegate.activeMode != activeMode ||
        oldDelegate.colorScheme != colorScheme;
  }
}

Future<void> showHabitCitations(
  BuildContext context,
  HabitAdaptation adaptation,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.menu_book_outlined,
              color: Theme.of(dialogContext).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('参考文献')),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: adaptation.citations
                .map((citation) => _CitationTile(citation: citation))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _CitationTile extends StatelessWidget {
  final HabitCitation citation;

  const _CitationTile({required this.citation});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(citation.url);
    if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开参考文献链接')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(citation.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(citation.publisher,
                style: TextStyle(
                    fontSize: 11.5, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 7),
            Text(citation.takeaway,
                style: TextStyle(
                    fontSize: 12, height: 1.45, color: colorScheme.onSurface)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _open(context),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('打开原文'),
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
