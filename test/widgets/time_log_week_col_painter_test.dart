import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/time_log_screen.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WeekColPainter formats course and schedule titles without redundant prefix', () {
    final dayStart = DateTime(2026, 11, 2, 0, 0).millisecondsSinceEpoch;
    final dayEnd = DateTime(2026, 11, 2, 24, 0).millisecondsSinceEpoch;
    final controller = AlwaysStoppedAnimation(1.0);

    final painter = WeekColPainter(
      dayLogs: const [],
      dayPoms: const [],
      daySchedules: [
        TimeLogMappedSchedule(
          id: 'course-1',
          title: '计算机组成原理',
          startTime: DateTime(2026, 11, 2, 8, 30).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 2, 10, 0).millisecondsSinceEpoch,
          isCourse: true,
        ),
        TimeLogMappedSchedule(
          id: 'course-2',
          title: '',
          startTime: DateTime(2026, 11, 2, 10, 30).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 2, 12, 0).millisecondsSinceEpoch,
          isCourse: true,
        ),
        TimeLogMappedSchedule(
          id: 'schedule-1',
          title: '组会汇报',
          startTime: DateTime(2026, 11, 2, 14, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 2, 15, 30).millisecondsSinceEpoch,
          isCourse: false,
        ),
        TimeLogMappedSchedule(
          id: 'schedule-2',
          title: '   ',
          startTime: DateTime(2026, 11, 2, 16, 0).millisecondsSinceEpoch,
          endTime: DateTime(2026, 11, 2, 17, 0).millisecondsSinceEpoch,
          isCourse: false,
        ),
      ],
      tags: const [],
      dayStartMs: dayStart,
      dayEndMs: dayEnd,
      isDark: false,
      hourH: 32.0,
      animation: controller,
      focusColor: Colors.blue,
      logColor: Colors.green,
    );

    expect(painter.scheduleBlockTitles, ['计算机组成原理', '课程', '组会汇报', '日程']);
  });

  testWidgets(
    'WeekColPainter paints multi-line wrapped text on narrow portrait column without error',
    (tester) async {
      final dayStart = DateTime(2026, 11, 2, 0, 0).millisecondsSinceEpoch;
      final dayEnd = DateTime(2026, 11, 2, 24, 0).millisecondsSinceEpoch;
      final controller = AlwaysStoppedAnimation(1.0);

      final painter = WeekColPainter(
        dayLogs: [
          TimeLogItem(
            id: 'log-1',
            title: '超长标题复习编译原理与语法分析自动换行',
            startTime: DateTime(2026, 11, 2, 19, 0).millisecondsSinceEpoch,
            endTime: DateTime(2026, 11, 2, 21, 0).millisecondsSinceEpoch,
            tagUuids: const [],
            createdAt: dayStart,
          ),
        ],
        dayPoms: [
          PomodoroRecord(
            uuid: 'pom-1',
            startTime: DateTime(2026, 11, 2, 10, 0).millisecondsSinceEpoch,
            endTime: DateTime(2026, 11, 2, 10, 15).millisecondsSinceEpoch,
            plannedDuration: 900,
            actualDuration: 900,
          ),
        ],
        daySchedules: [
          TimeLogMappedSchedule(
            id: 'course-1',
            title: '计算机组成原理',
            startTime: DateTime(2026, 11, 2, 8, 30).millisecondsSinceEpoch,
            endTime: DateTime(2026, 11, 2, 10, 0).millisecondsSinceEpoch,
            isCourse: true,
          ),
        ],
        tags: const [],
        dayStartMs: dayStart,
        dayEndMs: dayEnd,
        isDark: false,
        hourH: 30.0,
        animation: controller,
        focusColor: Colors.teal,
        logColor: Colors.orange,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CustomPaint(
                size: const Size(40.0, 720.0), // 窄屏竖屏 40px 列宽
                painter: painter,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    },
  );
}
