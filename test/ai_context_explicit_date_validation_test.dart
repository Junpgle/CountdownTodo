import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('impossible explicit date range does not inject a shifted period', () {
    final start = DateTime(2026, 7, 2, 9);
    final timeLogs = [
      TimeLogItem(
        id: 'july-log',
        title: '七月记录',
        startTime: start.millisecondsSinceEpoch,
        endTime: start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      ),
    ];

    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '分析2026-06-31至2026-07-05的效率',
      courses: const [],
      timeLogs: timeLogs,
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    );
    final summary = AiTodoContextBuilder.buildContextInjectionSummary(
      userMessage: '分析2026-06-31至2026-07-05的效率',
      courses: const [],
      timeLogs: timeLogs,
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    );

    expect(context, isNull);
    expect(summary, isNull);
  });

  test(
    'a reversed second explicit range does not inject only the first range',
    () {
      final start = DateTime(2026, 6, 10, 9);
      final timeLogs = [
        TimeLogItem(
          id: 'june-log',
          title: '六月记录',
          startTime: start.millisecondsSinceEpoch,
          endTime: start
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      ];

      const userMessage = '比较2026-06-01至2026-06-30和2026-07-10至2026-07-01的效率';
      final context = AiTodoContextBuilder.buildContextInjection(
        userMessage: userMessage,
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: DateTime(2026, 10, 2, 12),
      );
      final summary = AiTodoContextBuilder.buildContextInjectionSummary(
        userMessage: userMessage,
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: DateTime(2026, 10, 2, 12),
      );

      expect(context, isNull);
      expect(summary, isNull);
    },
  );

  test('two valid comparison ranges do not inject only the first range', () {
    final start = DateTime(2026, 6, 10, 9);
    final timeLogs = [
      TimeLogItem(
        id: 'june-log',
        title: '六月记录',
        startTime: start.millisecondsSinceEpoch,
        endTime: start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      ),
    ];
    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '比较2026-06-01至2026-06-30和2026-07-01至2026-07-31的效率',
      courses: const [],
      timeLogs: timeLogs,
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    );
    final summary = AiTodoContextBuilder.buildContextInjectionSummary(
      userMessage: '比较2026-06-01至2026-06-30和2026-07-01至2026-07-31的效率',
      courses: const [],
      timeLogs: timeLogs,
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    );

    expect(context, isNull);
    expect(summary, isNull);
  });

  test('impossible explicit single date does not fall back to recent logs', () {
    final start = DateTime(2026, 10, 1, 9);
    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '分析2026-06-31的效率',
      courses: const [],
      timeLogs: [
        TimeLogItem(
          id: 'recent-log',
          title: '近期记录',
          startTime: start.millisecondsSinceEpoch,
          endTime: start
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      ],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    );

    expect(context, isNull);
  });

  test('valid leap-day range still injects the requested records', () {
    final start = DateTime(2024, 2, 29, 9);
    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '分析2024-02-29至2024-03-01的效率',
      courses: const [],
      timeLogs: [
        TimeLogItem(
          id: 'leap-day-log',
          title: '闰日记录',
          startTime: start.millisecondsSinceEpoch,
          endTime: start
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      ],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    )!;

    expect(context, contains('自定义合计: 30分钟'));
    expect(context, contains('leap-day-log'));
  });
}
