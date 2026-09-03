import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/add_todo_screen.dart';
import 'package:countdown_todo/screens/todo_confirm_screen.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tip_shown_coach_add_todo': true,
    });
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
  });

  tearDown(ApiService.clearBaseUrlOverride);

  testWidgets('待办和日程共享输入页，切换日程不会导航到新页面', (tester) async {
    FixedScheduleItem? savedSchedule;
    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          todoGroups: [TodoGroup(name: '收集箱')],
          onTodoAdded: (_) {},
          onFixedScheduleAdded: (item) async => savedSchedule = item,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '团队会议');
    await tester.tap(find.text('日程'));
    await tester.pump();

    expect(find.byType(AddTodoScreen), findsOneWidget);
    expect(find.text('团队会议'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixed-schedule-date')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fixed-schedule-start-time')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fixed-schedule-end-time')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('fixed-schedule-time-tbd')),
        matching: find.byKey(const ValueKey('fixed-schedule-date')),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('fixed-schedule-end-time-tbd')),
        matching: find.byKey(const ValueKey('fixed-schedule-end-time')),
      ),
      findsOneWidget,
    );
    expect(find.text('结束时间待定'), findsNothing);
    expect(find.text('某天内完成'), findsNothing);

    await tester.tap(find.text('完成'));
    await tester.pump();

    expect(savedSchedule, isNotNull);
    expect(savedSchedule!.title, '团队会议');
    expect(savedSchedule!.startTime, isNotNull);
    expect(savedSchedule!.endTime, isNotNull);
    expect(savedSchedule!.source, FixedScheduleSource.manual);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('固定日程入口直接打开日程标签', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          initialMode: AddTodoInitialMode.fixedSchedule,
          onTodoAdded: (_) {},
          onFixedScheduleAdded: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('要记录什么日程？'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixed-schedule-date')), findsOneWidget);
    expect(find.text('某天内完成'), findsNothing);
  });

  testWidgets('空闲输入页不会持续调度加载动画帧', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          todoGroups: [TodoGroup(name: '收集箱')],
          onTodoAdded: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('AI确认页按固定日程保存地点且不捏造结束时间', (tester) async {
    FixedScheduleItem? savedSchedule;
    await tester.pumpWidget(
      MaterialApp(
        home: TodoConfirmScreen(
          llmResults: const [
            {
              'itemKind': 'fixedSchedule',
              'title': '客户同步',
              'location': '第一会议室',
              'remark': '带合同',
              'isAllDay': false,
              'startTime': '2026-08-03 10:00',
              'endTime': null,
              'timeMode': 'range',
              'recurrence': 'none',
              'reminderMinutes': 15,
            },
          ],
          onFixedScheduleAdded: (item) async => savedSchedule = item,
          onConfirm: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('日程 1/1'), findsOneWidget);
    expect(find.textContaining('结束待定'), findsOneWidget);
    await tester.tap(find.text('确认并添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存为固定日程'));
    await tester.pumpAndSettle();

    expect(savedSchedule, isNotNull);
    expect(savedSchedule!.location, '第一会议室');
    expect(savedSchedule!.remark, '带合同');
    expect(savedSchedule!.endTime, isNull);
    expect(savedSchedule!.reminderMinutes, [15]);
  });
}
