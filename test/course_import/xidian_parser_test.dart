import 'package:countdown_todo/course_import/parsers/xidian_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses ICS course dates and times', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:课程 @ 教室
LOCATION:教室
DTSTART:20260303T090000
DTEND:20260303T104000
END:VEVENT
END:VCALENDAR
''';

    final courses = XidianScheduleParser.parseIcs(ics, DateTime(2026, 3, 2));

    expect(courses, hasLength(1));
    expect(courses.single.date, '2026-03-03');
    expect(courses.single.weekday, DateTime.tuesday);
    expect(courses.single.startTime, 900);
    expect(courses.single.endTime, 1040);
  });
}
