part of 'course_screens.dart';

class _IdentityIndexCache<T extends Object> {
  Object? _source;
  Map<T, int>? _indices;

  Map<T, int> indicesFor(Object source, Iterable<T> items) {
    if (identical(_source, source)) return _indices!;

    final indices = HashMap<T, int>.identity();
    var index = 0;
    for (final item in items) {
      if (!indices.containsKey(item)) indices[item] = index;
      index++;
    }

    _source = source;
    _indices = indices;
    return indices;
  }
}

class _PlanPomodoroProgressIndex {
  _PlanPomodoroProgressIndex(this.plans, this.records) {
    final allocation = PomodoroPlanFocusAllocator.allocateByBlock(
      blocks: plans,
      records: records,
    );
    _secondsByPlanId = {
      for (var index = 0; index < plans.length; index++)
        plans[index].id: allocation.secondsByRecordByBlock[index],
    };
    _recordsByUuid = {
      for (final record in records)
        if (!record.isDeleted) record.uuid: record,
    };
  }

  final List<TodoPlanBlock> plans;
  final List<PomodoroRecord> records;
  late final Map<String, Map<String, int>> _secondsByPlanId;
  late final Map<String, PomodoroRecord> _recordsByUuid;
  final _progressByPlan =
      HashMap<TodoPlanBlock, Map<String, dynamic>>.identity();

  Map<String, dynamic> progressFor(
    TodoPlanBlock plan,
  ) => _progressByPlan.putIfAbsent(plan, () {
    if (plan.isDeleted) {
      return {'completed': 0, 'total': 0, 'actualSeconds': 0, 'progress': 0.0};
    }

    final attributedSeconds = _secondsByPlanId[plan.id] ?? const {};
    if (attributedSeconds.isEmpty) {
      return {'completed': 0, 'total': 0, 'actualSeconds': 0, 'progress': 0.0};
    }

    var totalSeconds = 0;
    var completedSeconds = 0;
    var actualSeconds = 0;
    for (final entry in attributedSeconds.entries) {
      final record = _recordsByUuid[entry.key];
      if (record == null) continue;
      final effective = entry.value;
      actualSeconds += effective;
      final originalEffective = record.effectiveDuration > 0
          ? record.effectiveDuration
          : 0;
      final planned = record.plannedDuration > 0
          ? record.plannedDuration
          : originalEffective;
      var base = planned > 0 ? planned : 1;
      if (originalEffective > 0 && effective < originalEffective) {
        final proratedBase = (planned * effective / originalEffective).round();
        base = proratedBase > 0 ? proratedBase : 1;
      }
      totalSeconds += base;
      completedSeconds += effective.clamp(0, base);
    }
    final progress = totalSeconds > 0 ? completedSeconds / totalSeconds : 0.0;
    return {
      'completed': completedSeconds,
      'total': totalSeconds,
      'actualSeconds': actualSeconds,
      'progress': progress.clamp(0.0, 1.0),
      'recordCount': attributedSeconds.length,
    };
  });
}

TodoPlanStatus _planStatusForActualFocus(
  TodoPlanBlock plan,
  int actualFocusSeconds,
) {
  if ((plan.status == TodoPlanStatus.planned ||
          plan.status == TodoPlanStatus.focusing) &&
      plan.plannedMinutes > 0 &&
      actualFocusSeconds >= plan.plannedMinutes * 60 * 0.8) {
    return TodoPlanStatus.finished;
  }
  return plan.status;
}

class _PomodoroPlanAssociationLookup {
  _PomodoroPlanAssociationLookup(Iterable<TodoPlanBlock> plans) {
    for (final plan in plans) {
      if (plan.isDeleted) continue;
      if (plan.id.isNotEmpty) _planIds.add(plan.id);
      _explicitRecordUuids.addAll(plan.pomodoroRecordIds);
      if (plan.todoId.isNotEmpty) {
        _plansByTodoId.putIfAbsent(plan.todoId, () => []).add(plan);
      }
    }
  }

  final _planIds = <String>{};
  final _explicitRecordUuids = <String>{};
  final _plansByTodoId = <String, List<TodoPlanBlock>>{};

  bool isAssociated(PomodoroRecord record, int recordEnd) {
    if (record.isDeleted) return false;
    if (_explicitRecordUuids.contains(record.uuid)) return true;

    final planBlockId = record.planBlockId;
    if (planBlockId != null &&
        planBlockId.isNotEmpty &&
        _planIds.contains(planBlockId)) {
      return true;
    }

    final todoUuid = record.todoUuid;
    if (todoUuid == null || todoUuid.isEmpty) return false;
    for (final plan in _plansByTodoId[todoUuid] ?? const <TodoPlanBlock>[]) {
      if (record.startTime < plan.endTime && recordEnd > plan.startTime) {
        return true;
      }
    }
    return false;
  }
}

class _PomodoroPlanDayAssociationIndex {
  _PomodoroPlanDayAssociationIndex(this._plans) {
    for (var index = 0; index < _plans.length; index++) {
      final plan = _plans[index];
      if (plan.isDeleted) continue;
      for (final recordUuid in plan.pomodoroRecordIds) {
        _planIndicesByRecordUuid.putIfAbsent(recordUuid, () => []).add(index);
      }
      if (plan.id.isNotEmpty) {
        _planIndicesById.putIfAbsent(plan.id, () => []).add(index);
      }
      if (plan.todoId.isNotEmpty) {
        _planIndicesByTodoId.putIfAbsent(plan.todoId, () => []).add(index);
      }
    }
  }

  final List<TodoPlanBlock> _plans;
  final _planIndicesByRecordUuid = <String, List<int>>{};
  final _planIndicesById = <String, List<int>>{};
  final _planIndicesByTodoId = <String, List<int>>{};

  List<TodoPlanBlock> matchingPlans(PomodoroRecord record, int recordEnd) {
    if (record.isDeleted) return const <TodoPlanBlock>[];
    Set<int>? matchingIndices;
    void addMatches(List<int>? indices) {
      if (indices == null || indices.isEmpty) return;
      (matchingIndices ??= <int>{}).addAll(indices);
    }

    addMatches(_planIndicesByRecordUuid[record.uuid]);
    final planBlockId = record.planBlockId;
    if (planBlockId != null && planBlockId.isNotEmpty) {
      addMatches(_planIndicesById[planBlockId]);
    }
    final todoUuid = record.todoUuid;
    if (todoUuid != null && todoUuid.isNotEmpty) {
      for (final index in _planIndicesByTodoId[todoUuid] ?? const <int>[]) {
        final plan = _plans[index];
        if (record.startTime < plan.endTime && recordEnd > plan.startTime) {
          (matchingIndices ??= <int>{}).add(index);
        }
      }
    }
    final matches = matchingIndices;
    if (matches == null || matches.isEmpty) return const <TodoPlanBlock>[];

    final orderedIndices = matches.toList()..sort();
    return [for (final index in orderedIndices) _plans[index]];
  }
}

class _WeeklyGridLayerContext {
  const _WeeklyGridLayerContext({
    required this.cellWidth,
    required this.minuteHeight,
    required this.colorScheme,
    required this.isWideScreen,
    required this.isDark,
    required this.planIndices,
    required this.planPomodoroProgressIndex,
    required this.backgroundEventsPerDay,
    required this.foregroundEventsPerDay,
    required this.firstTagFor,
    required this.topInsetForBackgroundCard,
  });

  final double cellWidth;
  final double minuteHeight;
  final ColorScheme colorScheme;
  final bool isWideScreen;
  final bool isDark;
  final Map<TodoPlanBlock, int> planIndices;
  final _PlanPomodoroProgressIndex planPomodoroProgressIndex;
  final Map<int, List<_TimelineEvent>> backgroundEventsPerDay;
  final Map<int, List<_TimelineEvent>> foregroundEventsPerDay;
  final PomodoroTag? Function(Iterable<String> uuids) firstTagFor;
  final double Function(int weekday, double bgTop, double bgBottom)
  topInsetForBackgroundCard;
}

/// Paint pulse updates directly so the grid avoids rebuilding these lines
/// on each animation tick.
class _CurrentTimeRulePainter extends CustomPainter {
  _CurrentTimeRulePainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  static final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    _paint.color = color.withValues(alpha: 0.3 + 0.2 * animation.value);
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant _CurrentTimeRulePainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.color != color;
}

class _CurrentTimeMarkerPainter extends CustomPainter {
  _CurrentTimeMarkerPainter({required this.animation, required this.color})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  static final Paint _fillPaint = Paint();
  static final Paint _glowPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _dotPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _innerDotPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.95)
    ..style = PaintingStyle.fill;
  static final Paint _shadowPaint = BoxShadow(
    color: Colors.transparent,
    blurRadius: 6,
    spreadRadius: 1,
  ).toPaint();

  @override
  void paint(Canvas canvas, Size size) {
    final progress = animation.value;
    final centerY = size.height / 2;

    // 绘制横贯当天列的高亮时间线
    final lineRect = Rect.fromLTWH(5, centerY - 1.25, size.width - 5, 2.5);
    _shadowPaint.color = color.withValues(alpha: 0.45 * progress);
    canvas.drawRect(lineRect.inflate(1), _shadowPaint);
    _fillPaint.color = color.withValues(alpha: 0.8 + 0.2 * progress);
    canvas.drawRect(lineRect, _fillPaint);

    // 绘制当天时间线左侧的时间指示圆点（Time Dot）
    final dotCenter = Offset(5, centerY);
    _glowPaint.color = color.withValues(alpha: 0.35 * progress);
    canvas.drawCircle(dotCenter, 5.0 + 1.5 * progress, _glowPaint);

    _dotPaint.color = color;
    canvas.drawCircle(dotCenter, 3.5, _dotPaint);

    canvas.drawCircle(dotCenter, 1.2, _innerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _CurrentTimeMarkerPainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.color != color;
}
