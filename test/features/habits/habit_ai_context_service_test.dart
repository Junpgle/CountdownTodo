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
