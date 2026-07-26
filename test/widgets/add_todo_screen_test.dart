import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/add_todo_screen.dart';
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
}
