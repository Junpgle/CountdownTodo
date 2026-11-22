import 'package:countdown_todo/course_import/parsers/xidian_parser.dart';
import 'package:countdown_todo/course_import/parsers/xujc_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('XujcScheduleParser handles tables with 14+ period rows without RangeError', () {
    final rowHtml = List.generate(
      15,
      (index) =>
          '<tr><td>第${index + 1}节</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>',
    ).join();
    final html =
        '<table class="data small solid"><tbody>$rowHtml</tbody></table>';

    final courses = XujcScheduleParser.parseHtml(html, DateTime(2026, 9, 1));
    expect(courses, isEmpty);
  });

  test(
    'XidianScheduleParser supports TZID parameters and RFC 5545 folded lines',
    () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'SUMMARY:算法导论\r\n'
          ' 进阶 @ 新区B\r\n'
          ' -101\r\n'
          'LOCATION:新区B-101\r\n'
          'DTSTART;TZID=Asia/Shanghai:20260901T083000\r\n'
          'DTEND;TZID=Asia/Shanghai:20260901T101000\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';

      final courses = XidianScheduleParser.parseIcs(ics, DateTime(2026, 8, 31));
      expect(courses, hasLength(1));
      expect(courses.single.courseName, '算法导论进阶');
      expect(courses.single.roomName, '新区B-101');
      expect(courses.single.startTime, 830);
      expect(courses.single.endTime, 1010);
    },
  );
}
