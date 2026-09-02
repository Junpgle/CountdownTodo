import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('countdown_todo/device_calendar_read');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceCalendarReadService.debugIsSupportedOverride = true;
    DeviceCalendarReadService.clearSessionReadCacheForTesting();
  });

  tearDown(() {
    DeviceCalendarReadService.debugIsSupportedOverride = null;
    DeviceCalendarReadService.clearSessionReadCacheForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('DeviceCalendarEvent presentation mapping', () {
    test('keeps provider data as a read-only presentation record', () {
      final start = DateTime(2026, 9, 2, 9);
      final end = DateTime(2026, 9, 2, 10, 30);

      final event = DeviceCalendarEvent.fromPlatformMap({
        'id': 'event_1',
        'calendarId': 'calendar_1',
        'title': ' 项目例会 ',
        'startMs': start.millisecondsSinceEpoch,
        'endMs': end.millisecondsSinceEpoch,
        'allDay': false,
        'location': ' 会议室 A ',
        'color': 0xff123456,
      });

      expect(event.id, 'event_1');
      expect(event.calendarId, 'calendar_1');
      expect(event.title, '项目例会');
      expect(event.start, start);
      expect(event.end, end);
      expect(event.location, '会议室 A');
      expect(event.colorValue, 0xff123456);
    });

    test('normalizes malformed provider ranges without creating a local item',
        () {
      final start = DateTime(2026, 9, 2, 9);
      final event = DeviceCalendarEvent.fromPlatformMap({
        'id': 'event_2',
        'calendarId': 'calendar_1',
        'title': '   ',
        'startMs': start.millisecondsSinceEpoch,
        'endMs': start.millisecondsSinceEpoch,
        'allDay': true,
        'color': 0,
      });

      expect(event.title, '未命名日程');
      expect(event.end, start.add(const Duration(minutes: 1)));
      expect(event.allDay, isTrue);
      expect(event.colorValue, isNull);
    });

    test('uses half-open ranges when deciding whether to display an event', () {
      final event = DeviceCalendarEvent(
        id: 'event_3',
        calendarId: 'calendar_1',
        title: '午餐',
        start: DateTime(2026, 9, 2, 12),
        end: DateTime(2026, 9, 2, 13),
        allDay: false,
      );

      expect(
        event.overlaps(DateTime(2026, 9, 2, 13), DateTime(2026, 9, 2, 14)),
        isFalse,
      );
      expect(
        event.overlaps(DateTime(2026, 9, 2, 12, 30), DateTime(2026, 9, 2, 14)),
        isTrue,
      );
    });
  });

  test('reuses a foreground range instead of querying the calendar again',
      () async {
    var providerReads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkPermission') return true;
      if (call.method == 'readEvents') {
        providerReads++;
        return [
          {
            'id': 'provider-event',
            'calendarId': 'calendar',
            'title': '日程',
            'startMs': DateTime(2026, 9, 2, 9).millisecondsSinceEpoch,
            'endMs': DateTime(2026, 9, 2, 10).millisecondsSinceEpoch,
            'allDay': false,
          },
        ];
      }
      return null;
    });
    await DeviceCalendarReadService.setEnabled(true);
    final start = DateTime(2026, 8, 31);
    final end = start.add(const Duration(days: 7));

    await DeviceCalendarReadService.readEvents(start: start, end: end);
    await DeviceCalendarReadService.readEvents(
      start: start.add(const Duration(days: 2)),
      end: start.add(const Duration(days: 4)),
    );

    expect(providerReads, 1);
  });
}
