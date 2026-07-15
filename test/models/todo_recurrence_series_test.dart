import 'package:flutter_test/flutter_test.dart';
import 'package:CountDownTodo/models.dart';

void main() {
  test('TodoItem preserves recurrence series id through JSON', () {
    final todo = TodoItem(
      title: '每日复习',
      recurrence: RecurrenceType.daily,
      recurrenceSeriesId: 'series-123',
    );

    final restored = TodoItem.fromJson(todo.toJson());

    expect(restored.recurrenceSeriesId, 'series-123');
    expect(restored.recurrence, RecurrenceType.daily);
  });

  test('TodoItem accepts camelCase recurrence series id', () {
    final restored = TodoItem.fromJson({
      'uuid': '550e8400-e29b-41d4-a716-446655440000',
      'content': '每日复习',
      'recurrence': RecurrenceType.daily.index,
      'recurrenceSeriesId': 'series-camel-case',
    });

    expect(restored.recurrenceSeriesId, 'series-camel-case');
  });
}
