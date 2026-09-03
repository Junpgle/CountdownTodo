import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/widgets/course_section_widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('countdown_todo/device_calendar_read');

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'home-calendar-test',
    });
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    DeviceCalendarReadService.clearSessionReadCacheForTesting();
    await DeviceCalendarReadService.setEnabled(true);
  });

  tearDown(() {
    DeviceCalendarReadService.debugIsSupportedOverride = null;
    DeviceCalendarReadService.clearSessionReadCacheForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'today schedule displays a device-calendar event and opens shared detail',
      (tester) async {
    final now = DateTime.now();
    final start = now.add(const Duration(minutes: 5));
    final end = start.add(const Duration(minutes: 30));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkPermission') return true;
      if (call.method == 'readEvents') {
        return [
          {
            'id': 'home-device-event',
            'calendarId': 'device-calendar',
            'title': '首页手机日程',
            'startMs': start.millisecondsSinceEpoch,
            'endMs': end.millisecondsSinceEpoch,
            'allDay': false,
            'location': '会议室',
          },
        ];
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseSectionWidget(
            dashboardCourseData: const {
              'title': '暂无课表',
              'courses': <dynamic>[],
            },
            username: 'home-calendar-test',
            todos: const [],
            isLight: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日日程'), findsOneWidget);
    expect(find.text('首页手机日程'), findsOneWidget);
    expect(find.text('手机日历'), findsOneWidget);

    await tester.tap(find.text('首页手机日程'));
    await tester.pumpAndSettle();

    expect(find.text('日程详情'), findsOneWidget);
    expect(find.text('手机日历 · 只读'), findsOneWidget);
    expect(find.text('会议室'), findsOneWidget);
  });
}
