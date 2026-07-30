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
}
