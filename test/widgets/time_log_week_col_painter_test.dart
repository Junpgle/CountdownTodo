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
    expect(painter.scheduleBlockExtraCounts, [0, 0, 0, 0]);
  });

  test('clusterTimeLogSchedules and WeekColPainter aggregate overlapping schedules with +N badge', () {
    final dayStart = DateTime(2026, 11, 3, 0, 0).millisecondsSinceEpoch;
    final dayEnd = DateTime(2026, 11, 3, 24, 0).millisecondsSinceEpoch;
    final controller = AlwaysStoppedAnimation(1.0);

    final schedules = [
      TimeLogMappedSchedule(
        id: 'course-makeup',
        title: '算法设计与分析补课',
        startTime: DateTime(2026, 11, 3, 10, 30).millisecondsSinceEpoch,
        endTime: DateTime(2026, 11, 3, 12, 0).millisecondsSinceEpoch,
        isCourse: true,
      ),
      TimeLogMappedSchedule(
        id: 'schedule-regular',
        title: '算法设计与分析',
        startTime: DateTime(2026, 11, 3, 10, 30).millisecondsSinceEpoch,
        endTime: DateTime(2026, 11, 3, 12, 0).millisecondsSinceEpoch,
        isCourse: false,
      ),
      TimeLogMappedSchedule(
        id: 'course-afternoon',
        title: '计算机网络',
        startTime: DateTime(2026, 11, 3, 14, 0).millisecondsSinceEpoch,
        endTime: DateTime(2026, 11, 3, 15, 30).millisecondsSinceEpoch,
        isCourse: true,
      ),
    ];

    final clusters = clusterTimeLogSchedules(schedules, dayStart, dayEnd);
    expect(clusters.length, 2);
    expect(clusters[0].isAggregated, isTrue);
    expect(clusters[0].extraCount, 1);
    expect(clusters[0].primary.title, '算法设计与分析补课');
    expect(clusters[1].isAggregated, isFalse);
    expect(clusters[1].extraCount, 0);
    expect(clusters[1].primary.title, '计算机网络');

    final painter = WeekColPainter(
      dayLogs: const [],
      dayPoms: const [],
      daySchedules: schedules,
      tags: const [],
      dayStartMs: dayStart,
      dayEndMs: dayEnd,
      isDark: false,
      hourH: 30.0,
      animation: controller,
      focusColor: Colors.blue,
      logColor: Colors.green,
    );

    expect(painter.scheduleBlockTitles, ['算法设计与分析补课', '计算机网络']);
    expect(painter.scheduleBlockExtraCounts, [1, 0]);
  });

  testWidgets(
    'WeekColPainter paints stacked cards and +N badge on narrow portrait column without error',
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
            title: '算法设计与分析补课',
            startTime: DateTime(2026, 11, 2, 10, 30).millisecondsSinceEpoch,
            endTime: DateTime(2026, 11, 2, 12, 0).millisecondsSinceEpoch,
            isCourse: true,
          ),
          TimeLogMappedSchedule(
            id: 'schedule-1',
            title: '算法设计与分析',
            startTime: DateTime(2026, 11, 2, 10, 30).millisecondsSinceEpoch,
            endTime: DateTime(2026, 11, 2, 12, 0).millisecondsSinceEpoch,
            isCourse: false,
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

  testWidgets('tapping aggregated cluster forwards all overlapping schedules', (
    tester,
  ) async {
    final dayStart = DateTime(2026, 11, 3, 0, 0).millisecondsSinceEpoch;
    final dayEnd = DateTime(2026, 11, 3, 24, 0).millisecondsSinceEpoch;

    final schedules = [
      TimeLogMappedSchedule(
        id: 'course-1',
        title: '算法设计与分析补课',
        startTime: DateTime(2026, 11, 3, 10, 30).millisecondsSinceEpoch,
        endTime: DateTime(2026, 11, 3, 12, 0).millisecondsSinceEpoch,
        isCourse: true,
      ),
      TimeLogMappedSchedule(
        id: 'schedule-1',
        title: '算法设计与分析',
        startTime: DateTime(2026, 11, 3, 10, 30).millisecondsSinceEpoch,
        endTime: DateTime(2026, 11, 3, 12, 0).millisecondsSinceEpoch,
        isCourse: false,
      ),
    ];

    List<TimeLogMappedSchedule>? tappedSchedules;
    final clusters = clusterTimeLogSchedules(schedules, dayStart, dayEnd);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ...clusters.map((cluster) {
                return Positioned(
                  top: 100,
                  left: 0,
                  width: 50,
                  height: 60,
                  child: GestureDetector(
                    key: const ValueKey('cluster-hitbox'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (cluster.isAggregated) {
                        tappedSchedules = cluster.schedules;
                      }
                    },
                    child: const SizedBox.expand(),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('cluster-hitbox')));
    await tester.pumpAndSettle();

    expect(tappedSchedules, isNotNull);
    expect(tappedSchedules!.length, 2);
    expect(tappedSchedules![0].title, '算法设计与分析补课');
    expect(tappedSchedules![1].title, '算法设计与分析');
  });
}
