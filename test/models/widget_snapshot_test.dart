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
}
