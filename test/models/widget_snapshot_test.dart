import 'package:countdown_todo/models/widget_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('widget todo expiry metadata survives a JSON round trip', () {
    const item = WidgetTodoItem(
      title: '每日打卡',
      timeText: '已逾期',
      priority: 3,
      visibleUntilMs: 1784995200000,
    );

    final restored = WidgetTodoItem.fromJson(item.toJson());

    expect(restored.visibleUntilMs, item.visibleUntilMs);
  });

  test('older widget todo snapshots decode without expiry metadata', () {
    final restored = WidgetTodoItem.fromJson({
      'title': '旧数据',
      'timeText': '',
      'priority': 0,
      'isDone': false,
    });

    expect(restored.visibleUntilMs, isNull);
  });

  test('recurrence series survives a widget snapshot JSON round trip', () {
    final snapshot = WidgetSnapshot(
      updatedAt: DateTime(2026, 7, 30, 9),
      recurrenceSeries: const [
        WidgetRecurrenceSeriesItem(
          seriesId: 'daily-water',
          title: '每日喝水',
          recurrenceType: 'daily',
          recurrenceText: '每天',
          anchorStartMs: 1785373200000,
          anchorDueMs: 1785420000000,
          completedCount: 12,
          elapsedCount: 13,
          occurrences: [
            WidgetRecurrenceOccurrenceItem(
              occurrenceId: 'water-0730',
              startAtMs: 1785373200000,
              dueAtMs: 1785420000000,
            ),
          ],
        ),
      ],
    );

    final restored = WidgetSnapshot.fromJson(snapshot.toJson());

    expect(restored.recurrenceSeries, hasLength(1));
    expect(restored.recurrenceSeries.single.seriesId, 'daily-water');
    expect(restored.recurrenceSeries.single.completedCount, 12);
    expect(
      restored.recurrenceSeries.single.occurrences.single.occurrenceId,
      'water-0730',
    );
  });

  test('older widget snapshots decode without recurrence catalog', () {
    final restored = WidgetSnapshot.fromJson({
      'updatedAt': '2026-07-30T09:00:00.000',
      'countdowns': <dynamic>[],
      'todos': <dynamic>[],
      'courses': <dynamic>[],
      'focus': <String, dynamic>{},
    });

    expect(restored.recurrenceSeries, isEmpty);
  });

  test('habit items survive a widget snapshot JSON round trip', () {
    final snapshot = WidgetSnapshot(
      updatedAt: DateTime(2026, 8, 1, 9),
      habits: const [
        WidgetHabitItem(
          habitId: 'water-habit',
          title: '喝水',
          icon: '💧',
          sourceType: 'quantityCheckIn',
          currentValue: 680,
          targetValue: 2000,
          unit: 'ml',
          goalMet: false,
          quickValues: [250, 500, 1000],
        ),
        WidgetHabitItem(
          habitId: 'run-habit',
          title: '跑步',
          sourceType: 'recurringTodo',
          goalMet: true,
        ),
      ],
    );

    final restored = WidgetSnapshot.fromJson(snapshot.toJson());

    expect(restored.habits, hasLength(2));
    final water = restored.habits.first;
    expect(water.habitId, 'water-habit');
    expect(water.currentValue, 680);
    expect(water.targetValue, 2000);
    expect(water.unit, 'ml');
    expect(water.goalMet, isFalse);
    expect(water.quickValues, [250.0, 500.0, 1000.0]);
    expect(restored.habits.last.goalMet, isTrue);
  });

  test('older widget snapshots decode with empty habits', () {
    final restored = WidgetSnapshot.fromJson({
      'updatedAt': '2026-07-30T09:00:00.000',
      'countdowns': <dynamic>[],
      'todos': <dynamic>[],
      'courses': <dynamic>[],
      'focus': <String, dynamic>{},
    });

    expect(restored.habits, isEmpty);
  });

  test('finance summary survives a widget snapshot JSON round trip', () {
    const summary = WidgetFinanceSummary(
      monthLabel: '2026年8月',
      incomeMinor: 120000,
      netExpenseMinor: 38650,
      balanceMinor: 81350,
      transactionCount: 12,
      latestTitle: '咖啡',
      latestAmountMinor: 2800,
      latestType: 'expense',
      latestDate: '2026-08-29',
    );
    final snapshot = WidgetSnapshot(
      updatedAt: DateTime(2026, 8, 29, 9),
      finance: summary,
    );

    final restored = WidgetSnapshot.fromJson(snapshot.toJson());

    expect(restored.finance.monthLabel, '2026年8月');
    expect(restored.finance.incomeMinor, 120000);
    expect(restored.finance.netExpenseMinor, 38650);
    expect(restored.finance.balanceMinor, 81350);
    expect(restored.finance.transactionCount, 12);
    expect(restored.finance.latestTitle, '咖啡');
    expect(
      restored.finance.toAndroidWidgetData(),
      containsPair('finance_latest_amount', '-¥28.00'),
    );
    expect(
      restored.finance.toAndroidWidgetData(),
      containsPair('finance_balance', '¥813.50'),
    );
  });

  test('older widget snapshots decode with an empty finance summary', () {
    final restored = WidgetSnapshot.fromJson({
      'updatedAt': '2026-07-30T09:00:00.000',
      'countdowns': <dynamic>[],
      'todos': <dynamic>[],
      'courses': <dynamic>[],
      'focus': <String, dynamic>{},
    });

    expect(restored.finance.hasData, isFalse);
    expect(restored.finance.transactionCount, 0);
  });
}
