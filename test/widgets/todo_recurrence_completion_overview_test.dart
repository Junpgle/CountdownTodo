import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/widgets/todo_recurrence_completion_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 29, 12);

  TodoItem occurrence({
    required String id,
    required DateTime start,
    DateTime? due,
    bool isDone = false,
  }) =>
      TodoItem(
        id: id,
        title: '俯卧撑30个',
        isDone: isDone,
        recurrenceSeriesId: 'series-overview',
        createdDate: start.millisecondsSinceEpoch,
        dueDate: due,
      );

  List<TodoItem> buildOccurrences() => [
        occurrence(
          id: 'completed',
          start: DateTime(2026, 7, 27, 19),
          isDone: true,
        ),
        occurrence(
          id: 'overdue',
          start: DateTime(2026, 7, 28, 19),
          due: DateTime(2026, 7, 28, 22),
        ),
        occurrence(
          id: 'current',
          start: DateTime(2026, 7, 29, 8),
          due: DateTime(2026, 7, 29, 22),
        ),
        occurrence(
          id: 'future',
          start: DateTime(2026, 7, 30, 19),
        ),
      ];

  test('summary separates elapsed, overdue and future occurrences', () {
    final summary = TodoRecurrenceCompletionOverview.calculateSummary(
      occurrences: buildOccurrences(),
      now: now,
    );

    expect(summary.completedCount, 1);
    expect(summary.pendingCount, 1);
    expect(summary.overdueCount, 1);
    expect(summary.futureCount, 1);
    expect(summary.elapsedCount, 3);
    expect(summary.completionRate, closeTo(1 / 3, 0.001));
  });

  test('unsaved completion switch is reflected immediately', () {
    final summary = TodoRecurrenceCompletionOverview.calculateSummary(
      occurrences: buildOccurrences(),
      now: now,
      currentTodoId: 'current',
      currentIsDone: true,
    );

    expect(summary.completedCount, 2);
    expect(summary.pendingCount, 0);
    expect(summary.completionRate, closeTo(2 / 3, 0.001));
  });

  testWidgets('renders completion rate and all status totals', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: TodoRecurrenceCompletionOverview(
              occurrences: buildOccurrences(),
              now: now,
            ),
          ),
        ),
      ),
    );

    expect(find.text('完成情况总览'), findsOneWidget);
    expect(find.text('完成率 33%'), findsOneWidget);
    expect(find.text('已发生 3 期 · 当前共 4 期实例'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recurrence_metric_已完成')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('recurrence_completion_progress')),
          )
          .value,
      closeTo(1 / 3, 0.001),
    );
  });
}
