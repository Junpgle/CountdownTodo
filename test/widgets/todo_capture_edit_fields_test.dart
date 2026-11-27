import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/recognized_todo_adapter.dart';
import 'package:countdown_todo/widgets/todo_capture_edit_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecognizedTodoAdapter helpers', () {
    test(
      'parseNullableInt handles num, numeric strings, and invalid input',
      () {
        expect(RecognizedTodoAdapter.parseNullableInt(15), 15);
        expect(RecognizedTodoAdapter.parseNullableInt(15.9), 15);
        expect(RecognizedTodoAdapter.parseNullableInt('42'), 42);
        expect(RecognizedTodoAdapter.parseNullableInt('abc'), isNull);
        expect(RecognizedTodoAdapter.parseNullableInt(null), isNull);
      },
    );

    test(
      'parseTimeSemantics resolves all-day, explicit modes, and fallbacks',
      () {
        final start = DateTime(2026, 11, 25, 9, 0);
        final end = DateTime(2026, 11, 25, 10, 0);

        expect(
          RecognizedTodoAdapter.parseTimeSemantics(
            'deadline',
            isAllDay: true,
            startTime: start,
            endTime: end,
          ),
          ParsedTimeSemantics.dateOnly,
        );
        expect(
          RecognizedTodoAdapter.parseTimeSemantics(
            ' range ',
            isAllDay: false,
            startTime: null,
            endTime: null,
          ),
          ParsedTimeSemantics.range,
        );
        expect(
          RecognizedTodoAdapter.parseTimeSemantics(
            'deadline',
            isAllDay: false,
            startTime: null,
            endTime: null,
          ),
          ParsedTimeSemantics.deadline,
        );
        expect(
          RecognizedTodoAdapter.parseTimeSemantics(
            'dateOnly',
            isAllDay: false,
            startTime: null,
            endTime: null,
          ),
          ParsedTimeSemantics.dateOnly,
        );
        expect(
          RecognizedTodoAdapter.parseTimeSemantics(
            'unscheduled',
            isAllDay: false,
            startTime: start,
            endTime: end,
          ),
          ParsedTimeSemantics.unscheduled,
        );
        expect(
          RecognizedTodoAdapter.parseTimeSemantics(
            null,
            isAllDay: false,
            startTime: start,
            endTime: end,
          ),
          ParsedTimeSemantics.range,
        );
        expect(
          RecognizedTodoAdapter.parseTimeSemantics(
            null,
            isAllDay: false,
            startTime: start,
            endTime: null,
          ),
          ParsedTimeSemantics.unscheduled,
        );
      },
    );
  });

  group('Todo capture edit widgets', () {
    testWidgets('TodoAllDayScheduleFields toggles all-day and legacy range', (
      tester,
    ) async {
      bool isAllDay = false;
      DateTime createdAt = DateTime(2026, 11, 25, 14, 30);
      DateTime? dueDate = DateTime(2026, 11, 25, 18, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TodoAllDayScheduleFields(
                  isAllDay: isAllDay,
                  createdAt: createdAt,
                  dueDate: dueDate,
                  showTrailingIcons: true,
                  onChanged: (nextAllDay, nextCreatedAt, nextDueDate) {
                    setState(() {
                      isAllDay = nextAllDay;
                      createdAt = nextCreatedAt;
                      dueDate = nextDueDate;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.textContaining('2026-11-25 18:00 前完成'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(isAllDay, isTrue);
      expect(createdAt, DateTime(2026, 11, 25));
      expect(dueDate, DateTime(2026, 11, 25, 23, 59));
      expect(find.text('完成日期: 2026-11-25'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(isAllDay, isFalse);
      expect(dueDate, isNull);
      expect(find.text('设置截止时间（当前未安排）'), findsOneWidget);
    });

    testWidgets(
      'TodoRecurrencePickerFields shows custom days and end date on selection',
      (tester) async {
        RecurrenceType recurrence = RecurrenceType.none;
        final customDaysCtrl = TextEditingController();
        addTearDown(customDaysCtrl.dispose);
        int? customDays;
        DateTime? endDate;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return TodoRecurrencePickerFields(
                    recurrence: recurrence,
                    customDaysController: customDaysCtrl,
                    recurrenceEndDate: endDate,
                    showPrefixIcon: true,
                    onRecurrenceChanged: (val) =>
                        setState(() => recurrence = val),
                    onCustomDaysChanged: (val) => customDays = val,
                    onRecurrenceEndDateChanged: (val) =>
                        setState(() => endDate = val),
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('间隔天数'), findsNothing);
        expect(find.text('重复结束日期 (可选)'), findsNothing);

        await tester.tap(find.byType(DropdownButtonFormField<RecurrenceType>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('间隔几天').last);
        await tester.pumpAndSettle();

        expect(recurrence, RecurrenceType.customDays);
        expect(find.text('间隔天数'), findsOneWidget);
        expect(find.text('重复结束日期 (可选)'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '3');
        expect(customDays, 3);
      },
    );

    testWidgets('TodoReminderLeadTimeDropdown invokes onChanged', (
      tester,
    ) async {
      int leadTime = 5;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TodoReminderLeadTimeDropdown(
                  value: leadTime,
                  onChanged: (val) => setState(() => leadTime = val),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提前 30 分钟').last);
      await tester.pumpAndSettle();

      expect(leadTime, 30);
    });
  });
}
