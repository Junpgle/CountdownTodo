import 'package:countdown_todo/course_import/parsers/hfut_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses repeated HFUT HTML course cards', () {
    const html = '''
<div class="columns unit"></div>
<div class="columns weekday">
  <div class="card-view common-card" style="top:0px;height:60px">
    <div class="card-content"><p>高等数学<br/>主楼101 (张老师) (1-16周) 1(1)</p></div><button></button>
  </div>
  <div class="card-view common-card" style="top:60px;height:60px">
    <div class="card-content"><p>大学英语<br/>外语楼202 (李老师) (1-16周) 2(2)</p></div><button></button>
  </div>
</div>
''';

    final courses = HfutScheduleParser.parse(html);
    final mathCourses = courses
        .where((course) => course.courseName == '高等数学')
        .toList();
    final englishCourses = courses
        .where((course) => course.courseName == '大学英语')
        .toList();

    expect(mathCourses, hasLength(16));
    expect(englishCourses, hasLength(16));
    expect(mathCourses.first.weekday, 1);
    expect(mathCourses.first.weekIndex, 1);
    expect(mathCourses.first.startTime, 800);
    expect(englishCourses.first.startTime, 900);
  });

  test('parses repeated EAMS5 TaskActivity records', () {
    const input = '''
actTeacherName.push("张老师");
new TaskActivity("张老师", 0, "高等数学", 0, "原教室", "011000000000000000000");
room = { name: "教室101" }; activities[2][1] = 1;
actTeacherName.push('李老师');
new TaskActivity("李老师", 0, "大学英语", 0, "原教室", "011000000000000000000");
room = { name: "教室202" }; activities[3][2] = 1;
''';

    final courses = HfutScheduleParser.parse(input);
    final mathCourses = courses
        .where((course) => course.courseName == '高等数学')
        .toList();
    final englishCourses = courses
        .where((course) => course.courseName == '大学英语')
        .toList();

    expect(mathCourses, hasLength(2));
    expect(englishCourses, hasLength(2));
    expect(mathCourses.first.teacherName, '张老师');
    expect(mathCourses.first.roomName, '教室101');
    expect(englishCourses.first.teacherName, '李老师');
    expect(englishCourses.first.weekday, 3);
  });
}
