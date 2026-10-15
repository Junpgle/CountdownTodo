import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/app_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _missionControl(TodoItem todo, DateTime now) => MaterialApp(
  home: Scaffold(
    body: MissionControl(
      todos: [todo],
      activeTab: 'active',
      clock: () => now,
      onTabChanged: (_) {},
      onTaskClick: (_) {},
    ),
  ),
);

Future<Color> _taskBorderColor(
  WidgetTester tester,
  TodoItem todo,
  DateTime now,
) async {
  await tester.pumpWidget(_missionControl(todo, now));
  final container = tester.widget<Container>(
    find
        .ancestor(of: find.text(todo.title), matching: find.byType(Container))
        .first,
  );
  final decoration = container.decoration! as BoxDecoration;
  return decoration.border!.top.color;
}

void main() {
  testWidgets('date-only task is not marked overdue in its final minute', (
    tester,
  ) async {
    final todo = TodoItem(
      id: 'today-date-only',
      title: '今天内完成',
      isAllDay: true,
      createdDate: DateTime(2026, 7, 20).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 20, 23, 59),
    );

    final border = await _taskBorderColor(
      tester,
      todo,
      DateTime(2026, 7, 20, 23, 59, 59, 500),
    );

    expect(border, Colors.white.withValues(alpha: 0.05));
  });

  testWidgets('date-only task becomes overdue after its due day ends', (
    tester,
  ) async {
    final todo = TodoItem(
      id: 'yesterday-date-only',
      title: '昨天截止',
      isAllDay: true,
      createdDate: DateTime(2026, 7, 20).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 7, 20, 23, 59),
    );

    final border = await _taskBorderColor(tester, todo, DateTime(2026, 7, 21));

    expect(border, Colors.red.withValues(alpha: 0.2));
  });
}
