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

  test('selected custom range overrides Chinese dates in the prompt', () {
    final customStart = DateTime(2026, 7, 1);
    final customEnd = DateTime(2026, 7, 31);
    final contextQuery = AiTodoContextBuilder.buildContextQueryText(
      userMessage: '分析2026年6月1日至2026年6月30日的效率',
      customStart: customStart,
      customEnd: customEnd,
      now: DateTime(2026, 10, 2, 12),
    );

    expect(contextQuery, contains('自定义注入范围 2026-07-01 至 2026-07-31'));
    expect(contextQuery, isNot(contains('2026年6月')));

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
      now: DateTime(2026, 10, 2, 12),
    );

    expect(context, contains('july-log'));
    expect(context, isNot(contains('june-log')));
  });

  test('Chinese numeral date range selects the full focus period', () {
    final juneStart = DateTime(2026, 6, 15, 9);
    final julyStart = DateTime(2026, 7, 3, 9);
    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '分析2026年六月一日至2026年七月五日的效率',
      courses: const [],
      timeLogs: [
        TimeLogItem(
          id: 'june-log',
          title: '六月专注',
          startTime: juneStart.millisecondsSinceEpoch,
          endTime: juneStart
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'july-log',
          title: '七月专注',
          startTime: julyStart.millisecondsSinceEpoch,
          endTime: julyStart
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      ],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    );

    expect(context, contains('2026-06-01 00:00 至 2026-07-06 00:00'));
    expect(context, contains('june-log'));
    expect(context, contains('july-log'));
  });

  test('selected custom range overrides Chinese numeral dates', () {
    final query = AiTodoContextBuilder.buildContextQueryText(
      userMessage: '分析2026年六月一日至2026年六月三十日的效率',
      customStart: DateTime(2026, 7, 1),
      customEnd: DateTime(2026, 7, 31),
      now: DateTime(2026, 10, 2, 12),
    );

    expect(query, contains('自定义注入范围 2026-07-01 至 2026-07-31'));
    expect(query, isNot(contains('六月')));
  });

  test('invalid or reversed Chinese numeral ranges do not inject fallback', () {
    for (final userMessage in [
      '分析2026年六月一日至2026年六月三十一日的效率',
      '分析2026年七月五日至2026年六月一日的效率',
    ]) {
      final context = AiTodoContextBuilder.buildContextInjection(
        userMessage: userMessage,
        courses: const [],
        timeLogs: const [],
        conflicts: const [],
        teams: const [],
        now: DateTime(2026, 10, 2, 12),
      );
      final summary = AiTodoContextBuilder.buildContextInjectionSummary(
        userMessage: userMessage,
        courses: const [],
        timeLogs: const [],
        conflicts: const [],
        teams: const [],
        now: DateTime(2026, 10, 2, 12),
      );

      expect(context, isNull, reason: userMessage);
      expect(summary, isNull, reason: userMessage);
    }
  });

  test('selected custom range overrides month periods in the prompt', () {
    final customStart = DateTime(2026, 8, 1);
    final customEnd = DateTime(2026, 8, 31);
    final contextQuery = AiTodoContextBuilder.buildContextQueryText(
      userMessage: '比较2026年6月和2026年7月的效率',
      customStart: customStart,
      customEnd: customEnd,
      now: DateTime(2026, 10, 2, 12),
    );
    final augustStart = DateTime(2026, 8, 15, 9);
    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: contextQuery,
      courses: const [],
      timeLogs: [
        for (final month in [6, 7])
          TimeLogItem(
            id: 'month-$month-log',
            title: '$month 月记录',
            startTime: DateTime(2026, month, 15, 9).millisecondsSinceEpoch,
            endTime: DateTime(2026, month, 15, 9, 30).millisecondsSinceEpoch,
          ),
        TimeLogItem(
          id: 'august-log',
          title: '八月记录',
          startTime: augustStart.millisecondsSinceEpoch,
          endTime: augustStart
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      ],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    );

    expect(contextQuery, contains('自定义注入范围 2026-08-01 至 2026-08-31'));
    expect(contextQuery, isNot(contains('2026年6月')));
    expect(contextQuery, isNot(contains('2026年7月')));
    expect(context, contains('august-log'));
    expect(context, isNot(contains('month-6-log')));
    expect(context, isNot(contains('month-7-log')));
  });

  test('Chinese explicit date ranges include both endpoints', () {
    final juneStart = DateTime(2026, 6, 15, 9);
    final juneEnd = DateTime(2026, 6, 30, 23, 30);
    final julyStart = DateTime(2026, 7, 1, 9);
    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '分析2026年6月1日至2026年6月30日的效率',
      courses: const [],
      timeLogs: [
        TimeLogItem(
          id: 'june-mid-month',
          title: '六月中旬记录',
          startTime: juneStart.millisecondsSinceEpoch,
          endTime: juneStart
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'june-end-boundary',
          title: '六月末记录',
          startTime: juneEnd.millisecondsSinceEpoch,
          endTime: juneEnd
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'july-record',
          title: '七月记录',
          startTime: julyStart.millisecondsSinceEpoch,
          endTime: julyStart
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      ],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 10, 2, 12),
    );

    expect(context, contains('2026-06-01 00:00 至 2026-07-01 00:00'));
    expect(context, contains('june-mid-month'));
    expect(context, contains('june-end-boundary'));
    expect(context, isNot(contains('july-record')));
  });

  test(
    'invalid or reversed Chinese date ranges do not inject fallback data',
    () {
      final start = DateTime(2026, 7, 2, 9);
      final timeLogs = [
        TimeLogItem(
          id: 'july-log',
          title: '七月记录',
          startTime: start.millisecondsSinceEpoch,
          endTime: start
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
      ];

      for (final userMessage in [
        '分析2026年6月31日至2026年7月5日的效率',
        '分析2026年7月5日至2026年6月30日的效率',
      ]) {
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

        expect(context, isNull, reason: userMessage);
        expect(summary, isNull, reason: userMessage);
      }
    },
  );

  test(
    'comparison of explicit Chinese months does not inject only one month',
    () {
      final juneStart = DateTime(2026, 6, 15, 9);
      final julyStart = DateTime(2026, 7, 15, 9);
      final timeLogs = [
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
      ];

      for (final userMessage in [
        '比较2026年6月和2026年7月的效率',
        '比较上个月和本月的效率',
        '比较2026-06-01至2026-06-30和2026年7月的效率',
      ]) {
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

        expect(context, isNull, reason: userMessage);
        expect(summary, isNull, reason: userMessage);
      }
    },
  );

  test('relative six-month focus query covers a rolling six-month period', () {
    final aprilStart = DateTime(2026, 4, 2, 9);
    final octoberStart = DateTime(2026, 10, 2, 22);
    for (final userMessage in ['分析过去6个月的效率', '分析过去六个月的效率']) {
      final context = AiTodoContextBuilder.buildContextInjection(
        userMessage: userMessage,
        courses: const [],
        timeLogs: [
          TimeLogItem(
            id: 'before-six-month-window',
            title: '范围外记录',
            startTime: DateTime(2026, 4, 1, 23).millisecondsSinceEpoch,
            endTime: DateTime(2026, 4, 2).millisecondsSinceEpoch,
          ),
          TimeLogItem(
            id: 'six-month-boundary',
            title: '六个月起点记录',
            startTime: aprilStart.millisecondsSinceEpoch,
            endTime: aprilStart
                .add(const Duration(minutes: 30))
                .millisecondsSinceEpoch,
          ),
          TimeLogItem(
            id: 'today-record',
            title: '今日记录',
            startTime: octoberStart.millisecondsSinceEpoch,
            endTime: octoberStart
                .add(const Duration(minutes: 30))
                .millisecondsSinceEpoch,
          ),
          TimeLogItem(
            id: 'tomorrow-record',
            title: '明日记录',
            startTime: DateTime(2026, 10, 3, 9).millisecondsSinceEpoch,
            endTime: DateTime(2026, 10, 3, 9, 30).millisecondsSinceEpoch,
          ),
        ],
        conflicts: const [],
        teams: const [],
        now: DateTime(2026, 10, 2, 12),
      );

      expect(
        context,
        contains('最近6个月范围: 2026-04-02 00:00 至 2026-10-03 00:00'),
        reason: userMessage,
      );
      expect(context, contains('six-month-boundary'), reason: userMessage);
      expect(context, contains('today-record'), reason: userMessage);
      expect(
        context,
        isNot(contains('before-six-month-window')),
        reason: userMessage,
      );
      expect(context, isNot(contains('tomorrow-record')), reason: userMessage);
    }
  });

  test('rolling month period clamps to the last day of a shorter month', () {
    final februaryEnd = DateTime(2026, 2, 28, 9);
    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: '分析最近6个月的效率',
      courses: const [],
      timeLogs: [
        TimeLogItem(
          id: 'february-boundary',
          title: '二月末记录',
          startTime: februaryEnd.millisecondsSinceEpoch,
          endTime: februaryEnd
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        ),
        TimeLogItem(
          id: 'before-clamped-period',
          title: '范围外记录',
          startTime: DateTime(2026, 2, 27, 23).millisecondsSinceEpoch,
          endTime: DateTime(2026, 2, 28).millisecondsSinceEpoch,
        ),
      ],
      conflicts: const [],
      teams: const [],
      now: DateTime(2026, 8, 31, 12),
    );

    expect(context, contains('最近6个月范围: 2026-02-28 00:00 至 2026-09-01 00:00'));
    expect(context, contains('february-boundary'));
    expect(context, isNot(contains('before-clamped-period')));
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
