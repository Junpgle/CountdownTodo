import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/features/habits/services/habit_ai_context_service.dart';

void main() {
  group('HabitAiContextService date range', () {
    final now = DateTime(2026, 10, 1, 12);

    test('uses an explicit date instead of today', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026-09-20习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, contains('2026-09-20'));
      expect(summary, isNot(contains('2026-10-01')));
    });

    test('resolves yesterday to the prior day', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看昨天的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, contains('2026-09-30'));
      expect(summary, isNot(contains('2026-10-01')));
    });

    test('resolves older-day aliases and uses them in follow-ups', () {
      final testNow = DateTime(2026, 10, 3, 12);
      for (final (period, expectedDate) in [
        ('大前天', '2026-09-30'),
        ('大前日', '2026-09-30'),
        ('前天', '2026-10-01'),
        ('前日', '2026-10-01'),
        ('昨天', '2026-10-02'),
        ('昨日', '2026-10-02'),
      ]) {
        final direct = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '查看$period的习惯进度',
          goals: const [],
          now: testNow,
        );
        final followUp = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '那$period呢？',
          previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
          conversationContext: '习惯进度',
          goals: const [],
          now: testNow,
        );

        expect(direct, contains(expectedDate), reason: period);
        expect(followUp, contains(expectedDate), reason: period);
      }
    });

    test('resolves rolling month requests as a date range', () {
      for (final period in [
        '过去6个月',
        '过去六个月',
        '最近六个月',
        '近6个月',
        '过去半年',
        '最近半年',
        '近半年',
      ]) {
        final summary = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '查看$period的习惯进度',
          goals: const [],
          now: DateTime(2026, 10, 3, 12),
        );

        expect(summary, contains('2026-04-03 至 2026-10-03'), reason: period);
      }
    });

    test('resolves rolling year aliases and keeps them in follow-ups', () {
      final testNow = DateTime(2026, 10, 3, 12);
      for (final period in [
        '最近一年',
        '最近1年',
        '过去一年',
        '过去1年',
        '近一年',
        '近1年',
        '最近12个月',
        '过去12个月',
        '近12个月',
      ]) {
        final direct = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '查看$period的习惯进度',
          goals: const [],
          now: testNow,
        );
        final followUp = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '那$period呢？',
          previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
          conversationContext: '习惯进度',
          goals: const [],
          now: testNow,
        );

        expect(direct, contains('2025-10-03 至 2026-10-03'), reason: period);
        expect(followUp, contains('2025-10-03 至 2026-10-03'), reason: period);
      }

      final leapYearRange =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看最近一年的习惯进度',
            goals: const [],
            now: DateTime(2024, 2, 29, 12),
          );
      final comparison = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '比较最近一年和去年习惯进度',
        goals: const [],
        now: testNow,
      );

      expect(leapYearRange, contains('2023-02-28 至 2024-02-29'));
      expect(comparison, isNull);
    });

    test('resolves the second previous month in direct and follow-up queries', () {
      final testNow = DateTime(2026, 10, 3, 12);
      for (final period in ['上上个月', '上上月']) {
        final direct = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '查看$period的习惯进度',
          goals: const [],
          now: testNow,
        );
        final followUp = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '那$period呢？',
          previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
          conversationContext: '习惯进度',
          goals: const [],
          now: testNow,
        );

        expect(direct, contains('2026-08-01 至 2026-08-31'), reason: period);
        expect(followUp, contains('2026-08-01 至 2026-08-31'), reason: period);
      }
    });

    test('resolves quarter ranges and rejects quarter comparisons', () {
      final testNow = DateTime(2026, 10, 3, 12);
      for (final (period, expectedRange) in [
        ('上上季度', '2026-04-01 至 2026-06-30'),
        ('上上个季度', '2026-04-01 至 2026-06-30'),
        ('上季度', '2026-07-01 至 2026-09-30'),
        ('上一季度', '2026-07-01 至 2026-09-30'),
        ('上一个季度', '2026-07-01 至 2026-09-30'),
        ('本季度', '2026-10-01 至 2026-10-03'),
        ('当前季度', '2026-10-01 至 2026-10-03'),
        ('这季度', '2026-10-01 至 2026-10-03'),
      ]) {
        final direct = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '查看$period的习惯进度',
          goals: const [],
          now: testNow,
        );
        final followUp = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '那$period呢？',
          previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
          conversationContext: '习惯进度',
          goals: const [],
          now: testNow,
        );

        expect(direct, contains(expectedRange), reason: period);
        expect(followUp, contains(expectedRange), reason: period);
      }

      final explicitQuarter =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看2025年第三季度的习惯进度',
            goals: const [],
            now: testNow,
          );
      final previousYearQuarter =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看前一年第三季度的习惯进度',
            goals: const [],
            now: testNow,
          );
      final beforePreviousYearQuarter =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看前年第三季度的习惯进度',
            goals: const [],
            now: testNow,
          );
      final comparison = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '比较上季度和本季度的习惯完成率',
        goals: const [],
        now: testNow,
      );

      expect(explicitQuarter, contains('2025-07-01 至 2025-09-30'));
      expect(previousYearQuarter, contains('2025-07-01 至 2025-09-30'));
      expect(beforePreviousYearQuarter, contains('2024-07-01 至 2024-09-30'));
      expect(comparison, isNull);
    });

    test('clamps rolling month starts to the target month length', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看过去6个月的习惯进度',
        goals: const [],
        now: DateTime(2026, 10, 31, 12),
      );

      expect(summary, contains('2026-04-30 至 2026-10-31'));
    });

    test('recent day follow-up overrides the previous explicit range', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '那最近七天呢？',
        previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
        conversationContext: '习惯进度',
        goals: const [],
        now: DateTime(2026, 10, 3, 12),
      );

      expect(summary, contains('2026-09-27 至 2026-10-03'));
    });

    test('recent day follow-up keeps the previous rolling range', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '那进度怎么样呢？',
        previousUserMessage: '分析最近七天的习惯进度',
        conversationContext: '习惯进度',
        goals: const [],
        now: DateTime(2026, 10, 3, 12),
      );

      expect(summary, contains('2026-09-27 至 2026-10-03'));
    });

    test('resolves week aliases and uses them in follow-ups', () {
      final testNow = DateTime(2026, 10, 3, 12);
      for (final (period, expectedRange) in [
        ('本周', '2026-09-28 至 2026-10-03'),
        ('本星期', '2026-09-28 至 2026-10-03'),
        ('本礼拜', '2026-09-28 至 2026-10-03'),
        ('这周', '2026-09-28 至 2026-10-03'),
        ('这星期', '2026-09-28 至 2026-10-03'),
        ('这礼拜', '2026-09-28 至 2026-10-03'),
        ('上周', '2026-09-21 至 2026-09-27'),
        ('上个周', '2026-09-21 至 2026-09-27'),
        ('上星期', '2026-09-21 至 2026-09-27'),
        ('上个星期', '2026-09-21 至 2026-09-27'),
        ('上礼拜', '2026-09-21 至 2026-09-27'),
        ('上个礼拜', '2026-09-21 至 2026-09-27'),
        ('上上周', '2026-09-14 至 2026-09-20'),
        ('上上个周', '2026-09-14 至 2026-09-20'),
        ('上上星期', '2026-09-14 至 2026-09-20'),
        ('上上个星期', '2026-09-14 至 2026-09-20'),
        ('上上礼拜', '2026-09-14 至 2026-09-20'),
        ('上上个礼拜', '2026-09-14 至 2026-09-20'),
      ]) {
        final direct = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '查看$period习惯进度',
          goals: const [],
          now: testNow,
        );
        final followUp = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '那$period呢？',
          previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
          conversationContext: '习惯进度',
          goals: const [],
          now: testNow,
        );

        expect(direct, contains(expectedRange), reason: period);
        expect(followUp, contains(expectedRange), reason: period);
      }
    });

    test('resolves recent-day aliases and treats them as follow-up ranges', () {
      final testNow = DateTime(2026, 10, 3, 12);
      for (final period in [
        '最近7天',
        '最近七天',
        '过去7天',
        '过去七天',
        '近7天',
        '近七天',
        '最近一周',
        '过去一周',
        '近一周',
      ]) {
        final direct = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '查看$period的习惯进度',
          goals: const [],
          now: testNow,
        );
        final followUp = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '那$period呢？',
          previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
          conversationContext: '习惯进度',
          goals: const [],
          now: testNow,
        );

        expect(direct, contains('2026-09-27 至 2026-10-03'), reason: period);
        expect(followUp, contains('2026-09-27 至 2026-10-03'), reason: period);
      }
    });

    test('resolves the second previous week instead of the previous week', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看上上周的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, contains('2026-09-14 至 2026-09-20'));
    });

    test('resolves previous calendar years and dates', () {
      final previousYear =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看去年习惯进度',
            goals: const [],
            now: now,
          );
      final previousYearDate =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看去年9月1日习惯进度',
            goals: const [],
            now: now,
          );
      final previousYearMonth =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看前一年9月的习惯进度',
            goals: const [],
            now: now,
          );
      final previousYearMonthFollowUp =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '那前一年9月呢？',
            previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
            conversationContext: '习惯进度',
            goals: const [],
            now: now,
          );
      final beforePreviousYear =
          HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看前年习惯进度',
            goals: const [],
            now: now,
          );

      expect(previousYear, contains('2025-01-01 至 2025-12-31'));
      expect(previousYearDate, contains('2025-09-01'));
      expect(
        previousYearMonth,
        contains('2025-09-01 至 2025-09-30'),
      );
      expect(
        previousYearMonthFollowUp,
        contains('2025-09-01 至 2025-09-30'),
      );
      expect(beforePreviousYear, contains('2024-01-01 至 2024-12-31'));
    });

    test('does not silently select one period from a relative comparison', () {
      for (final prompt in [
        '比较最近7天和上周的习惯进度',
        '比较最近7天和最近30天的习惯进度',
        '比较上个月和本周的习惯进度',
        '比较上上周和上周的习惯进度',
        '比较去年和今年的习惯进度',
      ]) {
        final summary = HabitAiContextService.buildContextInjectionSummary(
          userMessage: prompt,
          goals: const [],
          now: now,
        );

        expect(summary, isNull, reason: prompt);
      }
    });

    test('rolling month follow-up overrides the previous explicit range', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '那最近六个月呢？',
        previousUserMessage: '查看2026-06-01至2026-06-30的习惯进度',
        conversationContext: '习惯进度',
        goals: const [],
        now: DateTime(2026, 10, 3, 12),
      );

      expect(summary, contains('2026-04-03 至 2026-10-03'));
    });

    test(
      'does not inject a fallback range for an invalid rolling month count',
      () {
        for (final period in ['过去0个月', '过去37个月', '过去三十七个月']) {
          final summary = HabitAiContextService.buildContextInjectionSummary(
            userMessage: '查看$period的习惯进度',
            goals: const [],
            now: now,
          );

          expect(summary, isNull, reason: period);
        }
      },
    );

    test('does not inject today for an invalid explicit date', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026-02-30习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });

    test(
      'does not collapse a range with an impossible end date to its start',
      () {
        final summary = HabitAiContextService.buildContextInjectionSummary(
          userMessage: '查看2026-06-01至2026-06-31习惯进度',
          goals: const [],
          now: now,
        );

        expect(summary, isNull);
      },
    );

    test('does not collapse a reversed date range to its start', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026-06-30至2026-06-01习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });

    test('does not inject only the first of two rolling month ranges', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '比较过去三个月和过去六个月的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });

    test('does not inject only the first of two comparison date ranges', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '比较2026-06-01至2026-06-30和2026-07-01至2026-07-31的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });

    test('keeps a single valid explicit date range', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026-06-01至2026-07-05的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, contains('2026-06-01 至 2026-07-05'));
    });

    test('supports Chinese explicit date ranges across months', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026年6月1日至2026年7月5日的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, contains('2026-06-01 至 2026-07-05'));
    });

    test('supports Chinese numeral dates across months', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026年六月一日至2026年七月五日的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, contains('2026-06-01 至 2026-07-05'));
    });

    test('uses a single Chinese numeral date instead of its whole month', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026年六月一日的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, contains('2026-06-01'));
      expect(summary, isNot(contains('2026-06-30')));
    });

    test('rejects an impossible Chinese numeral date range', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026年六月一日至2026年六月三十一日的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });

    test('does not collapse an invalid Chinese date range to its start', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026年6月1日至2026年6月31日的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });

    test('does not collapse a reversed Chinese date range to its start', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026年6月30日至2026年6月1日的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });

    test('does not inject only the first of two Chinese comparison ranges', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '比较2026年6月1日至2026年6月30日和2026年7月1日至2026年7月31日的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });

    test('uses a single Chinese explicit date instead of its whole month', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '查看2026年6月1日的习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, contains('2026-06-01'));
      expect(summary, isNot(contains('2026-06-30')));
    });

    test('does not reuse an invalid range from the previous message', () {
      final summary = HabitAiContextService.buildContextInjectionSummary(
        userMessage: '习惯进度如何？',
        previousUserMessage: '查看2026-06-01至2026-06-31习惯进度',
        goals: const [],
        now: now,
      );

      expect(summary, isNull);
    });
  });
}
