import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/course_month_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cross-day todo spans the correct calendar dates across DST', (
    tester,
  ) async {
    final todo = TodoItem(
      title: '跨夏令时待办',
      createdAt: DateTime(2026, 3, 6).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 3, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseMonthView(
            selectedMonth: DateTime(2026, 3, 2),
            courseMap: const {},
            todoMap: const {},
            crossDayTodoMap: const {},
            logMap: const {},
            pomMap: const {},
            fixedScheduleMap: const {},
            deviceCalendarMap: const {},
            pomodoroTags: const [],
            activeDataViews: const {'todos'},
            onMonthChanged: (_) {},
            onDayTapped: (_) {},
            allTodos: [todo],
            viewMode: 1,
            currentWeekMonday: DateTime(2026, 3, 2),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final todoContainer = find.ancestor(
      of: find.text('跨夏令时待办'),
      matching: find.byType(Container),
    );
    expect(tester.getSize(todoContainer.first).width, greaterThan(250));
  });
}
