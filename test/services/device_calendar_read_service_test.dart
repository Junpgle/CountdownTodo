import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
