import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/widgets/team_gantt_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('task bars keep calendar-day width across DST', (tester) async {
    const viewDays = 14;
    const timelineWidth = 800.0;
    final todo = TodoItem(
      id: 'dst-task',
      title: '夏令时任务',
      createdAt: DateTime(2026, 3, 8).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 3, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamGanttWidget(
            todos: [todo],
            viewDays: viewDays,
            now: DateTime(2026, 3, 8, 12),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byKey(const ValueKey('team-gantt-bar-dst-task'));
    expect(tester.getSize(bar).width, closeTo(timelineWidth / viewDays, 0.01));
  });
}
