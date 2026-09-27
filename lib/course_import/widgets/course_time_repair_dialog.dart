import 'package:flutter/material.dart';

import '../../models.dart';
import '../course_schedule_semantics.dart';

/// Lets the user repair courses for which a source export did not contain a
/// usable time range.  Courses with the same identity and weekday share one
/// repaired range across all of their imported weeks.
class CourseTimeRepairDialog extends StatefulWidget {
  const CourseTimeRepairDialog({
    super.key,
    required this.courses,
  });

  final List<CourseItem> courses;

  static Future<List<CourseItem>?> show(
    BuildContext context,
    List<CourseItem> courses,
  ) {
    return showDialog<List<CourseItem>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CourseTimeRepairDialog(courses: courses),
    );
  }

  @override
  State<CourseTimeRepairDialog> createState() => _CourseTimeRepairDialogState();
}

class _CourseTimeRepairDialogState extends State<CourseTimeRepairDialog> {
  static const _weekdayNames = [
    '',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  static const _defaultTimeRanges = [
    [800, 845],
    [855, 940],
    [955, 1040],
    [1050, 1135],
    [1145, 1230],
    [1330, 1415],
    [1425, 1510],
    [1525, 1610],
    [1620, 1705],
    [1715, 1800],
    [1900, 1945],
    [1950, 2035],
    [2040, 2125],
  ];

  late final List<_TimeRepairGroup> _groups;
  late final int _missingCount;
  String? _error;

  @override
  void initState() {
    super.initState();
    final groupsByKey = <String, _TimeRepairGroup>{};
    var missingCount = 0;

    for (var index = 0; index < widget.courses.length; index++) {
      final course = widget.courses[index];
      if (CourseScheduleSemantics.hasUsableTime(course)) continue;

      missingCount++;
      final key = _groupKey(course);
      final group = groupsByKey.putIfAbsent(
        key,
        () => _TimeRepairGroup(key: key, sample: course),
      );
      group.courseIndexes.add(index);
    }

    _groups = groupsByKey.values.toList();
    _missingCount = missingCount;

    for (var index = 0; index < _groups.length; index++) {
      final group = _groups[index];
      CourseItem? knownTimeCourse;
      for (final course in widget.courses) {
        if (_groupKey(course) == group.key &&
            CourseScheduleSemantics.hasUsableTime(course)) {
          knownTimeCourse = course;
          break;
        }
      }

      final range = knownTimeCourse == null
          ? _defaultTimeRanges[index % _defaultTimeRanges.length]
          : [knownTimeCourse.startTime, knownTimeCourse.endTime];
      group.start = _fromHhmm(range[0]);
      group.end = _fromHhmm(range[1]);
    }
  }

  static String _groupKey(CourseItem course) {
    return [
      course.semesterId,
      course.courseName,
      course.teacherName,
      course.roomName,
      course.weekday,
      course.lessonType ?? '',
    ].join('\u0000');
  }

  static TimeOfDay _fromHhmm(int value) {
    return TimeOfDay(hour: value ~/ 100, minute: value % 100);
  }

  static int _toHhmm(TimeOfDay value) => value.hour * 100 + value.minute;

  static int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

  static String _formatTime(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime(
    _TimeRepairGroup group, {
    required bool isStart,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? group.start : group.end,
      helpText: isStart ? '设置开始时间' : '设置结束时间',
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        group.start = picked;
      } else {
        group.end = picked;
      }
      _error = null;
    });
  }

  void _confirm() {
    final invalidGroup = _groups.where((group) {
      return _minutes(group.end) <= _minutes(group.start);
    }).firstOrNull;
    if (invalidGroup != null) {
      setState(() => _error = '结束时间必须晚于开始时间');
      return;
    }

    final repaired = List<CourseItem>.of(widget.courses);
    for (final group in _groups) {
      final startTime = _toHhmm(group.start);
      final endTime = _toHhmm(group.end);
      for (final index in group.courseIndexes) {
        repaired[index] = CourseScheduleSemantics.withTimeRange(
          repaired[index],
          startTime: startTime,
          endTime: endTime,
        );
      }
    }
    Navigator.pop(context, repaired);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.schedule_outlined),
          SizedBox(width: 10),
          Text('补全课程时间'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '检测到 $_missingCount 节课程缺少有效时间。相同课程在不同周次会共用下面的时间设置。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  final sample = group.sample;
                  final weekday = sample.weekday >= 1 && sample.weekday <= 7
                      ? _weekdayNames[sample.weekday]
                      : '星期未知';
                  final weeks = group.courseIndexes
                      .map((courseIndex) =>
                          widget.courses[courseIndex].weekIndex)
                      .toSet()
                      .toList()
                    ..sort();
                  final weekText = weeks.length > 8
                      ? '第${weeks.first}-${weeks.last}周等'
                      : '第${weeks.join('、')}周';

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sample.courseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$weekday · $weekText · ${sample.roomName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _timeButton(
                                  label: _formatTime(group.start),
                                  onPressed: () =>
                                      _pickTime(group, isStart: true),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text('至'),
                              ),
                              Expanded(
                                child: _timeButton(
                                  label: _formatTime(group.end),
                                  onPressed: () =>
                                      _pickTime(group, isStart: false),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消导入'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('确认并导入'),
        ),
      ],
    );
  }

  Widget _timeButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 38),
      ),
      child: Text(label),
    );
  }
}

class _TimeRepairGroup {
  _TimeRepairGroup({
    required this.key,
    required this.sample,
  });

  final String key;
  final CourseItem sample;
  final List<int> courseIndexes = [];
  late TimeOfDay start;
  late TimeOfDay end;
}
