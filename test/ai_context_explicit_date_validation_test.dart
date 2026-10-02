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

  test('selected custom range overrides dates in the prompt for context', () {
    final customStart = DateTime(2026, 7, 1);
    final customEnd = DateTime(2026, 7, 31);
    final now = DateTime(2026, 10, 2, 12);
    final selectedRange = AiTodoContextBuilder.resolveCustomInjectionDateRange(
      customStart: customStart,
      customEnd: customEnd,
      now: now,
    )!;
    final contextQuery = AiTodoContextBuilder.buildContextQueryText(
      userMessage: '分析2026-06-01至2026-06-30的效率',
      customStart: customStart,
      customEnd: customEnd,
      now: now,
    );
    final juneStart = DateTime(2026, 6, 15, 9);
    final julyStart = DateTime(2026, 7, 15, 9);
    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: contextQuery,
      courses: const [],
      timeLogs: [
        TimeLogItem(
          id: 'june-log',
          title: '六月记录',
          startTime: juneStart.millisecondsSinceEpoch,
          endTime: juneStart
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'july-log',
          title: '七月记录',
          startTime: julyStart.millisecondsSinceEpoch,
          endTime: julyStart
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      ],
      conflicts: const [],
      teams: const [],
      focusRecordPriorityRange: selectedRange,
      now: now,
    );

    expect(context, contains('2026-07-01 00:00 至 2026-08-01 00:00'));
    expect(context, contains('july-log'));
    expect(context, isNot(contains('june-log')));
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
