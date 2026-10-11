import 'plan_availability.dart';

class PlanSplitQuery {
  const PlanSplitQuery(this.base, {this.days = 1, this.maximum = 45});
  final PlanAvailabilityQuery base;
  final int days, maximum;
  int get total => base.minutes;
  DateTime get endDate =>
      DateTime(base.date.year, base.date.month, base.date.day + days);
  PlanAvailabilityQuery day(int index, {int minutes = 15}) =>
      PlanAvailabilityQuery(
        username: base.username,
        todoId: base.todoId,
        date: DateTime(base.date.year, base.date.month, base.date.day + index),
        minutes: minutes,
        windowStart: base.windowStart,
        windowEnd: base.windowEnd,
        appOnly: base.appOnly,
        avoidWindows: base.avoidWindows,
        bufferBefore: base.bufferBefore,
        bufferAfter: base.bufferAfter,
        bufferOverride: base.bufferOverride,
        bufferDefaultsKey: base.bufferDefaultsKey,
        avoidanceOverride: base.avoidanceOverride,
        avoidanceDefaultsKey: base.avoidanceDefaultsKey,
      );
  PlanSplitQuery configure({
    PlanAvailabilityQuery? base,
    int? days,
    int? maximum,
  }) => PlanSplitQuery(
    base ?? this.base,
    days: days ?? this.days,
    maximum: maximum ?? this.maximum,
  );
  String? get invalidReason => days < 1 || days > 7
      ? '日期范围须为1–7天'
      : total < 30 || total > 720
      ? '分段总时长须为30–720分钟；较短任务请使用连续安排'
      : maximum < 15 || maximum > 120
      ? '单段上限须为15–120分钟'
      : null;
}

class PlanSplitSnapshot {
  const PlanSplitSnapshot(this.days);
  final List<PlanAvailabilitySnapshot> days;
  String get coverage => days.map((s) => s.coverage).toSet().join('；');
  bool get includesCalendar => days.any((s) => s.deviceCalendarIncluded);
}

class PlanSplitSelection {
  const PlanSplitSelection(this.query, this.slots, this.snapshot);
  final PlanSplitQuery query;
  final List<PlanTimeSlot> slots;
  final PlanSplitSnapshot snapshot;
}

class PlanSplitResult {
  const PlanSplitResult(this.groups, {this.message, this.incomplete = false});
  final List<List<PlanTimeSlot>> groups;
  final String? message;
  final bool incomplete;
}

/// Local draft payload. No occupancy snapshot or one-off relaxation survives exit.
class PlanSplitDraft {
  const PlanSplitDraft(this.query, this.slots, this.ids);
  final PlanSplitQuery query;
  final List<PlanTimeSlot> slots;
  final List<String> ids;
  Map<String, Object> toJson() => {
    'date': query.base.date.millisecondsSinceEpoch,
    'days': query.days,
    'maximum': query.maximum,
    'total': query.total,
    'windowStart': query.base.windowStart,
    'windowEnd': query.base.windowEnd,
    'segments': [
      for (var i = 0; i < slots.length; i++)
        {
          'id': ids[i],
          'start': slots[i].start.millisecondsSinceEpoch,
          'end': slots[i].end.millisecondsSinceEpoch,
        },
    ],
  };
  factory PlanSplitDraft.fromJson(Object? raw, String username, String todoId) {
    if (raw is! Map ||
        ![
          'date',
          'days',
          'maximum',
          'total',
          'windowStart',
          'windowEnd',
        ].every((k) => raw[k] is int) ||
        raw['segments'] is! List ||
        raw['date'] <= 0 ||
        raw['date'] > 8640000000000000) {
      throw const FormatException('分段草稿格式无效');
    }
    final q = PlanSplitQuery(
      PlanAvailabilityQuery(
        username: username,
        todoId: todoId,
        date: DateTime.fromMillisecondsSinceEpoch(raw['date']),
        minutes: raw['total'],
        windowStart: raw['windowStart'],
        windowEnd: raw['windowEnd'],
      ),
      days: raw['days'],
      maximum: raw['maximum'],
    );
    final slots = <PlanTimeSlot>[], ids = <String>[];
    for (final s in raw['segments']) {
      if (s is! Map ||
          s['id'] is! String ||
          (s['id'] as String).isEmpty ||
          s['start'] is! int ||
          s['end'] is! int ||
          s['start'] <= 0 ||
          s['end'] > 8640000000000000 ||
          s['end'] <= s['start']) {
        throw const FormatException('分段草稿时段无效');
      }
      ids.add(s['id']);
      slots.add(
        PlanTimeSlot(
          DateTime.fromMillisecondsSinceEpoch(s['start']),
          DateTime.fromMillisecondsSinceEpoch(s['end']),
        ),
      );
    }
    if (q.invalidReason != null ||
        q.base.windowStart < 0 ||
        q.base.windowEnd > 1440 ||
        q.base.windowEnd <= q.base.windowStart ||
        slots.length < 2 ||
        slots.length > 6 ||
        ids.toSet().length != ids.length ||
        slots.fold<int>(0, (n, s) => n + s.minutes) != q.total) {
      throw const FormatException('分段草稿内容无效');
    }
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      if (s.minutes < 15 ||
          s.minutes > q.maximum ||
          s.end.difference(s.start).inMilliseconds != s.minutes * 60000 ||
          s.start.isBefore(q.base.dayStart) ||
          !s.start.isBefore(q.endDate) ||
          s.end.isAfter(
            DateTime(s.start.year, s.start.month, s.start.day + 1),
          ) ||
          (i > 0 && s.start.isBefore(slots[i - 1].end))) {
        throw const FormatException('分段草稿时段无效');
      }
    }
    return PlanSplitDraft(q, List.unmodifiable(slots), List.unmodifiable(ids));
  }
}
