import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('device calendar detail uses the shared schedule detail surface',
      (tester) async {
    final event = DeviceCalendarEvent(
      id: 'event-1',
      calendarId: 'calendar-1',
      title: '产品评审',
      start: DateTime(2026, 9, 2, 9),
      end: DateTime(2026, 9, 2, 10, 30),
      allDay: false,
      location: '会议室 A',
    );

    await tester.pumpWidget(MaterialApp(
      home: DeviceCalendarEventDetailScreen(event: event),
    ));

    expect(find.text('日程详情'), findsOneWidget);
    expect(find.text('产品评审'), findsOneWidget);
    expect(find.text('手机日历 · 只读'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('10:30'), findsOneWidget);
    expect(find.text('会议室 A'), findsOneWidget);
    expect(find.text('此日程不会写入、导入为待办或参与同步。'), findsOneWidget);
  });

  testWidgets('all-day detail displays the inclusive final day',
      (tester) async {
    final event = DeviceCalendarEvent(
      id: 'event-2',
      calendarId: 'calendar-1',
      title: '假期',
      start: DateTime(2026, 9, 2),
      end: DateTime(2026, 9, 4),
      allDay: true,
    );

    await tester.pumpWidget(MaterialApp(
      home: DeviceCalendarEventDetailScreen(event: event),
    ));

    expect(find.text('2026年9月2日 – 2026年9月3日'), findsOneWidget);
    expect(find.text('全天'), findsNWidgets(2));
  });
}
