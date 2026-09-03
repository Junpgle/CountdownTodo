import 'package:countdown_todo/screens/course_month_view.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final event = DeviceCalendarEvent(
    id: 'meeting-1',
    calendarId: 'calendar-1',
    title: '项目例会',
    start: DateTime(2026, 9, 2, 9),
    end: DateTime(2026, 9, 2, 10),
    allDay: false,
  );

  for (final viewMode in [1, 2]) {
    testWidgets(
      '${viewMode == 1 ? '半月' : '月'}视图展示手机日程并响应点击',
      (tester) async {
        var tapped = false;
        final sourceKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 620,
                child: CourseMonthView(
                  selectedMonth: DateTime(2026, 9),
                  courseMap: const {},
                  todoMap: const {},
                  crossDayTodoMap: const {},
                  logMap: const {},
                  pomMap: const {},
                  deviceCalendarMap: {
                    '2026-09-02': [event]
                  },
                  pomodoroTags: const [],
                  activeDataViews: const {'deviceCalendar'},
                  onMonthChanged: (_) {},
                  onDayTapped: (_) {},
                  viewMode: viewMode,
                  currentWeekMonday: DateTime(2026, 8, 31),
                  deviceCalendarCardKeyBuilder: (event, date) => sourceKey,
                  onDeviceCalendarTap: (tappedEvent, key) {
                    tapped = tappedEvent.id == event.id && key == sourceKey;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('09:00 · 项目例会'), findsOneWidget);
        await tester.tap(find.text('09:00 · 项目例会'));
        expect(tapped, isTrue);
      },
    );
  }
}
