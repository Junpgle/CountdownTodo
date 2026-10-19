import 'package:countdown_todo/course_import/parsers/xmu_parser.dart';
import 'package:countdown_todo/course_import/parsers/xujc_parser.dart';
import 'package:countdown_todo/course_import/parsers/zfsoft_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final semesterStart = DateTime(2026, 3, 2);

  test('parses XMU course weeks and dates', () {
    const html = '''
<table><tbody><tr><td jc="1" xq="2" rowspan="1">
  <div class="arrage">
    <div>1-2周</div><div>计量经济学</div><div>康嫱</div><div>教室101</div>
  </div>
</td></tr></tbody></table>
''';

    final courses = XmuScheduleParser.parseHtml(html, semesterStart);

    expect(courses, hasLength(2));
    expect(courses.first.date, '2026-03-03');
    expect(courses.first.weekIndex, 1);
    expect(courses.first.startTime, 800);
    expect(courses.first.endTime, 845);
  });

  test('parses ZFSoft course titles, weeks, and periods', () {
    const html = '''
<table><tbody><tr><td id="3-1">
  <div class="timetable_con">
    <span class="title">【必修】高等数学★</span>
    <p>(1-2节) (1-4周)</p><p>教学楼101</p><p>张老师</p>
  </div>
</td></tr></tbody></table>
''';

    final courses = ZfSoftScheduleParser.parseHtml(html, semesterStart);

    expect(courses, hasLength(4));
    expect(courses.first.courseName, '高等数学');
    expect(courses.first.weekday, 3);
    expect(courses.first.weekIndex, 1);
    expect(courses.first.startTime, 800);
    expect(courses.first.endTime, 940);
  });

  test('parses Xujc recurring week rules', () {
    const html = '''
<table class="solid"><tbody><tr>
  <td>节次</td>
  <td rowspan="1"><div>课程A<br/>张老师<br/>教室A<br/>1-2周(每周)</div></td>
</tr></tbody></table>
''';

    final courses = XujcScheduleParser.parseHtml(html, semesterStart);

    expect(courses, hasLength(2));
    expect(courses.first.courseName, '课程A');
    expect(courses.first.weekday, 1);
    expect(courses.first.weekIndex, 1);
    expect(courses.first.date, '2026-03-02');
  });
}
