import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('efficiency context excludes paused time from pomodoro duration', () {
    final start = DateTime(2026, 9, 1, 9);
    final record = PomodoroRecord(
      uuid: 'paused-pomodoro',
      startTime: start.millisecondsSinceEpoch,
      endTime: start.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      plannedDuration: 300,
      actualDuration: 120,
      totalPauseSeconds: 180,
      pauseIntervals: [
        PauseInterval(
          startMs: start.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
          endMs: start.add(const Duration(minutes: 4)).millisecondsSinceEpoch,
        ),
      ],
    );

    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '分析2026-09-01的效率',
      courses: const [],
      timeLogs: const [],
      pomodoroRecords: [record],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    )!;

    expect(context, contains('2026-09-01合计: 2分钟'));
    expect(context, contains('其中补录: 0分钟，番茄钟: 2分钟'));
    expect(context, contains('本时段计入2分'));

    final recentContext = AiTodoContextBuilder.buildContextInjection(
      userMessage: '查看专注记录',
      courses: const [],
      timeLogs: const [],
      pomodoroRecords: [record],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    )!;
    expect(recentContext, contains(' 番茄钟 | 2分钟'));
  });

  test('legacy pomodoro uses effective duration without pause intervals', () {
    final start = DateTime(2026, 9, 1, 9);
    final record = PomodoroRecord(
      uuid: 'legacy-paused-pomodoro',
      startTime: start.millisecondsSinceEpoch,
      endTime: start.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      plannedDuration: 300,
      actualDuration: 120,
      totalPauseSeconds: 180,
    );

    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '分析2026-09-01的效率',
      courses: const [],
      timeLogs: const [],
      pomodoroRecords: [record],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    )!;

    expect(context, contains('2026-09-01合计: 2分钟'));
  });
}
