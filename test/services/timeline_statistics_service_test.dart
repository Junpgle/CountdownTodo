import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/services/timeline_statistics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 7, 19);
  final end = start.add(const Duration(days: 1));

  test('combines pomodoro and time-log focus with pause and tag details', () {
    final record = PomodoroRecord(
      uuid: 'record-1',
      startTime: start.add(const Duration(hours: 8)).millisecondsSinceEpoch,
      plannedDuration: 30 * 60,
      actualDuration: 25 * 60,
      tagUuids: ['study'],
      totalPauseSeconds: 5 * 60,
      pauseIntervals: [
        PauseInterval(
          startMs: start
              .add(const Duration(hours: 8, minutes: 10))
              .millisecondsSinceEpoch,
          endMs: start
              .add(const Duration(hours: 8, minutes: 15))
              .millisecondsSinceEpoch,
        ),
      ],
    );
    final log = TimeLogItem(
      title: '阅读',
      tagUuids: ['study'],
      startTime: start.add(const Duration(hours: 10)).millisecondsSinceEpoch,
      endTime: start.add(const Duration(hours: 11)).millisecondsSinceEpoch,
    );

    final result = TimelineStatisticsService.calculate(
      start: start,
      end: end,
      pomodoroRecords: [record],
      timeLogs: [log],
      planBlocks: const [],
      todos: const [],
      tags: [PomodoroTag(uuid: 'study', name: '学习')],
    );

    expect(result.pomodoroFocusSeconds, 25 * 60);
    expect(result.timeLogSeconds, 60 * 60);
    expect(result.totalFocusSeconds, 85 * 60);
    expect(result.focusSessionCount, 2);
    expect(result.pauseSeconds, 5 * 60);
    expect(result.pauseCount, 1);
    expect(result.topFocusTags.single.key, '学习');
    expect(result.topFocusTags.single.value, 85 * 60);
  });

  test('uses linked records for plan achievement without double counting', () {
    final blockStart = start.add(const Duration(hours: 14));
    final block = TodoPlanBlock(
      id: 'block-1',
      todoId: 'todo-1',
      startTime: blockStart.millisecondsSinceEpoch,
      endTime: blockStart.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      plannedMinutes: 60,
      actualFocusSeconds: 20 * 60,
    );
    final record = PomodoroRecord(
      uuid: 'record-1',
      todoUuid: 'todo-1',
      planBlockId: 'block-1',
      startTime: blockStart.millisecondsSinceEpoch,
      endTime:
          blockStart.add(const Duration(minutes: 50)).millisecondsSinceEpoch,
      plannedDuration: 50 * 60,
      actualDuration: 50 * 60,
    );

    final result = TimelineStatisticsService.calculate(
      start: start,
      end: end,
      pomodoroRecords: [record],
      timeLogs: const [],
      planBlocks: [block],
      todos: const [],
      tags: const [],
    );

    expect(result.planActualSeconds, 50 * 60);
    expect(result.planBlockCount, 1);
    expect(result.planCompletedCount, 1);
    expect(result.planAchievementRate, closeTo(5 / 6, 0.001));
  });

  test('counts completed recurrence occurrences by their series identity', () {
    final recurring = TodoItem(
      title: '每日复盘',
      isDone: true,
      recurrenceSeriesId: 'series-1',
      createdDate: start.add(const Duration(hours: 20)).millisecondsSinceEpoch,
      updatedAt: start.add(const Duration(hours: 20)).millisecondsSinceEpoch,
    );
    final oneOff = TodoItem(
      title: '一次性任务',
      isDone: true,
      updatedAt: start.add(const Duration(hours: 21)).millisecondsSinceEpoch,
    );

    final result = TimelineStatisticsService.calculate(
      start: start,
      end: end,
      pomodoroRecords: const [],
      timeLogs: const [],
      planBlocks: const [],
      todos: [recurring, oneOff],
      tags: const [],
      now: end,
    );

    expect(result.recurringCompletedCount, 1);
  });

  test('recurrence rate excludes an in-progress occurrence from failures', () {
    TodoItem occurrence(
      int day, {
      required bool isDone,
      int dueHour = 22,
    }) {
      return TodoItem(
        id: 'habit-$day',
        title: '每日阅读',
        isDone: isDone,
        recurrence: day == 19 ? RecurrenceType.daily : RecurrenceType.none,
        recurrenceSeriesId: 'reading-habit',
        createdDate: DateTime(2026, 7, day, 8).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, day, dueHour),
      );
    }

    final result = TimelineStatisticsService.calculate(
      start: DateTime(2026, 7, 17),
      end: DateTime(2026, 7, 20),
      pomodoroRecords: const [],
      timeLogs: const [],
      planBlocks: const [],
      todos: [
        occurrence(17, isDone: true),
        occurrence(18, isDone: false),
        occurrence(19, isDone: false),
      ],
      tags: const [],
      now: DateTime(2026, 7, 19, 10),
    );

    expect(result.recurrenceSeriesCount, 1);
    expect(result.recurringScheduledCount, 3);
    expect(result.recurringCompletedCount, 1);
    expect(result.recurringMissedCount, 1);
    expect(result.recurringPendingCount, 1);
    expect(result.recurringCompletionRate, 0.5);
    expect(result.recurrenceSeries.single.longestStreak, 1);
    expect(result.recurrenceSeries.single.endingStreak, 0);
  });

  test('recurrence statistics deduplicate a series day and track streaks', () {
    TodoItem occurrence(
      String id,
      int day, {
      required bool isDone,
      RecurrenceType recurrence = RecurrenceType.none,
    }) {
      return TodoItem(
        id: id,
        title: '背单词',
        isDone: isDone,
        recurrence: recurrence,
        recurrenceSeriesId: 'vocabulary-habit',
        createdDate: DateTime(2026, 7, day, 7).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, day, 8),
      );
    }

    final result = TimelineStatisticsService.calculate(
      start: DateTime(2026, 7, 17),
      end: DateTime(2026, 7, 20),
      pomodoroRecords: const [],
      timeLogs: const [],
      planBlocks: const [],
      todos: [
        occurrence('day-17', 17, isDone: true),
        occurrence('day-18-old', 18, isDone: false),
        occurrence('day-18-done', 18, isDone: true),
        occurrence(
          'day-19',
          19,
          isDone: true,
          recurrence: RecurrenceType.daily,
        ),
      ],
      tags: const [],
      now: DateTime(2026, 7, 20),
    );

    final habit = result.recurrenceSeries.single;
    expect(habit.scheduledCount, 3);
    expect(habit.completedCount, 3);
    expect(habit.missedCount, 0);
    expect(habit.longestStreak, 3);
    expect(habit.endingStreak, 3);
    expect(result.bestRecurrenceSeries?.title, '背单词');
  });
}
