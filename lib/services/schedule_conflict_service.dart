import '../models.dart';

enum ScheduleConflictSeverity { hard, soft }

enum ScheduleEntityKind { fixedSchedule, course, planBlock }

class ScheduleConflict {
  const ScheduleConflict({
    required this.severity,
    required this.leftId,
    required this.leftTitle,
    required this.leftKind,
    required this.rightId,
    required this.rightTitle,
    required this.rightKind,
    required this.startTime,
    required this.endTime,
  });

  final ScheduleConflictSeverity severity;
  final String leftId;
  final String leftTitle;
  final ScheduleEntityKind leftKind;
  final String rightId;
  final String rightTitle;
  final ScheduleEntityKind rightKind;
  final int startTime;
  final int endTime;

  bool involves(String id) => leftId == id || rightId == id;

  String get message => severity == ScheduleConflictSeverity.hard
      ? '“$leftTitle”与“$rightTitle”时间重叠，需要确认真实安排。'
      : '“$leftTitle”与可调整规划“$rightTitle”重叠，建议移动规划块。';
}

/// 固定日程是硬约束，规划块是软约束；待办截止点不参与时段冲突。
class ScheduleConflictService {
  ScheduleConflictService._();

  static List<ScheduleConflict> detect({
    List<FixedScheduleItem> fixedSchedules = const [],
    List<CourseItem> courses = const [],
    List<TodoPlanBlock> planBlocks = const [],
  }) {
    final hardIntervals = <_ScheduleInterval>[
      ...fixedSchedules.where(_isActiveFixedSchedule).map(
            (item) => _ScheduleInterval(
              id: item.id,
              title: item.title,
              kind: ScheduleEntityKind.fixedSchedule,
              start: item.startTime!,
              end: item.endTime!,
            ),
          ),
      ...courses
          .where((course) => !course.isDeleted)
          .map(_courseInterval)
          .whereType<_ScheduleInterval>(),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final softIntervals = planBlocks
        .where(_isActivePlanBlock)
        .map(
          (block) => _ScheduleInterval(
            id: block.id,
            title: block.titleSnapshot?.trim().isNotEmpty == true
                ? block.titleSnapshot!.trim()
                : '未命名规划',
            kind: ScheduleEntityKind.planBlock,
            start: block.startTime,
            end: block.endTime,
          ),
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final conflicts = <ScheduleConflict>[];
    for (var i = 0; i < hardIntervals.length; i++) {
      final left = hardIntervals[i];
      for (var j = i + 1; j < hardIntervals.length; j++) {
        final right = hardIntervals[j];
        if (right.start >= left.end) break;
        if (_overlaps(left, right)) {
          conflicts.add(_buildConflict(
            ScheduleConflictSeverity.hard,
            left,
            right,
          ));
        }
      }

      for (final plan in softIntervals) {
        if (plan.start >= left.end) break;
        if (_overlaps(left, plan)) {
          conflicts.add(_buildConflict(
            ScheduleConflictSeverity.soft,
            left,
            plan,
          ));
        }
      }
    }
    return conflicts;
  }

  static bool _isActiveFixedSchedule(FixedScheduleItem item) =>
      !item.isDeleted &&
      item.status != FixedScheduleStatus.cancelled &&
      item.startTime != null &&
      item.endTime != null &&
      item.endTime! > item.startTime!;

  static bool _isActivePlanBlock(TodoPlanBlock block) =>
      !block.isDeleted &&
      block.endTime > block.startTime &&
      block.status != TodoPlanStatus.finished &&
      block.status != TodoPlanStatus.cancelled &&
      block.status != TodoPlanStatus.missed &&
      block.status != TodoPlanStatus.skipped;

  static _ScheduleInterval? _courseInterval(CourseItem course) {
    final date = DateTime.tryParse(course.date)?.toLocal();
    if (date == null ||
        !_validHhmm(course.startTime) ||
        !_validHhmm(course.endTime)) {
      return null;
    }
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      course.startTime ~/ 100,
      course.startTime % 100,
    ).millisecondsSinceEpoch;
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      course.endTime ~/ 100,
      course.endTime % 100,
    ).millisecondsSinceEpoch;
    if (end <= start) return null;
    return _ScheduleInterval(
      id: course.uuid,
      title: course.courseName,
      kind: ScheduleEntityKind.course,
      start: start,
      end: end,
    );
  }

  static ScheduleConflict _buildConflict(
    ScheduleConflictSeverity severity,
    _ScheduleInterval left,
    _ScheduleInterval right,
  ) {
    return ScheduleConflict(
      severity: severity,
      leftId: left.id,
      leftTitle: left.title,
      leftKind: left.kind,
      rightId: right.id,
      rightTitle: right.title,
      rightKind: right.kind,
      startTime: left.start > right.start ? left.start : right.start,
      endTime: left.end < right.end ? left.end : right.end,
    );
  }

  static bool _overlaps(_ScheduleInterval a, _ScheduleInterval b) =>
      a.start < b.end && b.start < a.end;

  static bool _validHhmm(int value) =>
      value >= 0 && value ~/ 100 < 24 && value % 100 < 60;
}

class _ScheduleInterval {
  const _ScheduleInterval({
    required this.id,
    required this.title,
    required this.kind,
    required this.start,
    required this.end,
  });

  final String id;
  final String title;
  final ScheduleEntityKind kind;
  final int start;
  final int end;
}
