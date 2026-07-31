import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/widgets/todo_recurrence_occurrence_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<TodoItem> buildOccurrences() => List.generate(
        8,
        (index) => TodoItem(
          id: 'occurrence-$index',
          title: '第 ${index + 1} 期',
          createdDate: DateTime(2026, 7, 10 + index).millisecondsSinceEpoch,
          recurrenceSeriesId: 'series-picker',
          isDone: index < 3,
        ),
      );

  testWidgets('centers the current occurrence when the picker opens',
      (tester) async {
    final occurrences = buildOccurrences();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: TodoRecurrenceOccurrencePicker(
                occurrences: occurrences,
                currentTodoId: occurrences[5].id,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pickerCenter = tester.getCenter(
      find.byKey(const ValueKey('related_recurrence_scroll')),
    );
    final currentCenter = tester.getCenter(
      find.byKey(ValueKey('related_recurrence_${occurrences[5].id}')),
    );
    expect(currentCenter.dx, closeTo(pickerCenter.dx, 0.1));
  });

  testWidgets('selecting another occurrence updates the same picker in place',
      (tester) async {
    final occurrences = buildOccurrences();
    var currentTodoId = occurrences[4].id;
    var selectedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, setState) => TodoRecurrenceOccurrencePicker(
                  occurrences: occurrences,
                  currentTodoId: currentTodoId,
                  onSelected: (occurrence) {
                    selectedCount++;
                    setState(() => currentTodoId = occurrence.id);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('related_recurrence_${occurrences[5].id}')),
    );
    await tester.pumpAndSettle();

    expect(selectedCount, 1);
    expect(currentTodoId, occurrences[5].id);
    final pickerCenter = tester.getCenter(
      find.byKey(const ValueKey('related_recurrence_scroll')),
    );
    final currentCenter = tester.getCenter(
      find.byKey(ValueKey('related_recurrence_${occurrences[5].id}')),
    );
    expect(currentCenter.dx, closeTo(pickerCenter.dx, 0.1));
    expect(find.byType(TodoRecurrenceOccurrencePicker), findsOneWidget);
  });
}
