import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/widgets/todo_group_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

Widget groupCard(TodoItem todo) => MaterialApp(
  home: Scaffold(
    body: TodoGroupWidget(
      group: TodoGroup(id: 'test-group', name: '工作'),
      groupTodos: [todo],
      isLight: false,
      teamRoles: const {},
      onToggle: _noop,
      onTodoToggle: _ignoreTodo,
      onTodoDropped: _ignoreId,
      onDelete: _noop,
      onTodoTap: _ignoreTodo,
      onTodoDelete: _ignoreTodo,
    ),
  ),
);

void _noop() {}
void _ignoreTodo(TodoItem todo) {}
void _ignoreId(String id) {}

void main() {
  testWidgets('unscheduled todos do not make their group look overdue', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final createdAt = DateTime.now()
        .subtract(const Duration(days: 2))
        .toUtc()
        .millisecondsSinceEpoch;
    final todo = TodoItem(
      id: 'unscheduled-old-todo',
      title: '尚未安排的任务',
      createdAt: createdAt,
    );

    await tester.pumpWidget(groupCard(todo));
    await tester.pumpAndSettle();

    final folderIcon = tester.widget<Icon>(find.byIcon(Icons.folder_rounded));
    expect(folderIcon.color, const Color(0xFF66BB6A));
  });

  testWidgets('date-only todos past their due day keep the overdue color', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final todo = TodoItem(
      id: 'overdue-date-only-todo',
      title: '已过截止日的任务',
      isAllDay: true,
      createdDate: DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
      ).toUtc().millisecondsSinceEpoch,
      dueDate: DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59),
    );

    await tester.pumpWidget(groupCard(todo));
    await tester.pumpAndSettle();

    final folderIcon = tester.widget<Icon>(find.byIcon(Icons.folder_rounded));
    expect(folderIcon.color, const Color(0xFFE57373));
  });
}
