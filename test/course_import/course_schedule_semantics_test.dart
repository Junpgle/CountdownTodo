import 'package:countdown_todo/course_import/course_schedule_semantics.dart';
import 'package:countdown_todo/course_import/course_import_preflight.dart';
import 'package:countdown_todo/course_import/parsers/xmu_parser.dart';
import 'package:countdown_todo/models.dart';
import 'package:flutter_test/flutter_test.dart';

CourseItem course({
  required String name,
  required String semesterId,
  required String date,
  required int startTime,
  required int endTime,
  int weekIndex = 1,
  int weekday = DateTime.monday,
  String roomName = 'A101',
}) => CourseItem(
  courseName: name,
  teacherName: '教师',
  date: date,
  weekday: weekday,
  startTime: startTime,
  endTime: endTime,
  weekIndex: weekIndex,
  roomName: roomName,
  semesterId: semesterId,
);

void main() {
  group('CourseScheduleSemantics', () {
    test('uses calendar dates for weeks across daylight-saving changes', () {
      expect(
        CourseScheduleSemantics.dateFor(
          semesterStart: DateTime(2026, 10, 26),
          weekIndex: 2,
          weekday: DateTime.monday,
        ),
        '2026-11-02',
      );
      expect(
        CourseScheduleSemantics.weekIndexForDate(
          DateTime(2026, 3, 2),
          DateTime(2026, 3, 9),
        ),
        2,
      );
    });

    test('rebases dates from the selected semester Monday', () {
      final imported = course(
        name: '高等数学',
        semesterId: 'source',
        date: '2099-01-01',
        startTime: 800,
        endTime: 945,
        weekIndex: 2,
        weekday: DateTime.wednesday,
      );

      final result = CourseScheduleSemantics.assignToSemester(
        [imported],
        semesterId: '2026-spring',
        semesterStart: DateTime(2026, 9, 2), // Wednesday
      ).single;

      expect(result.semesterId, '2026-spring');
      expect(result.date, '2026-09-09');
      expect(result.weekIndex, 2);
      expect(result.weekday, DateTime.wednesday);
      expect(result.uuid, isNot(imported.uuid));
    });

    test(
      'detects missing times and rebuilds the course identity after repair',
      () {
        final missing = course(
          name: '大学英语',
          semesterId: 'spring',
          date: '2026-09-07',
          startTime: 0,
          endTime: 0,
        );

        expect(CourseScheduleSemantics.hasUsableTime(missing), isFalse);

        final repaired = CourseScheduleSemantics.withTimeRange(
          missing,
          startTime: 1330,
          endTime: 1415,
        );

        expect(CourseScheduleSemantics.hasUsableTime(repaired), isTrue);
        expect(repaired.startTime, 1330);
        expect(repaired.endTime, 1415);
        expect(repaired.uuid, isNot(missing.uuid));
      },
    );

    test('rejects incomplete semester configuration before import', () {
      final valid = SemesterInfo(
        id: '2026-fall',
        name: '2026 秋季学期',
        startDate: DateTime(2026, 9, 7),
      );
      final missingStart = SemesterInfo(
        id: 'broken',
        name: '无效学期',
        startDate: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final invalidRange = SemesterInfo(
        id: 'broken-range',
        name: '日期颠倒',
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 9, 1),
      );

      expect(CourseImportPreflight.hasUsableSemester(valid), isTrue);
      expect(CourseImportPreflight.hasUsableSemester(missingStart), isFalse);
      expect(CourseImportPreflight.hasUsableSemester(invalidRange), isFalse);
    });

    test(
      'XMU parser accepts a single week and normalizes a non-Monday start',
      () {
        const html = '''
        <table>
          <tr>
            <td jc="1" xq="3">
              <div class="arrage">
                <div>1周</div><div>课程</div><div>教师</div><div>教室</div>
              </div>
            </td>
          </tr>
        </table>
      ''';

        final result = XmuScheduleParser.parseHtml(
          html,
          DateTime(2026, 9, 2), // Wednesday; week one starts on Aug 31.
        );

        expect(result, hasLength(1));
        expect(result.single.weekIndex, 1);
        expect(result.single.weekday, DateTime.wednesday);
        expect(result.single.date, '2026-09-02');
      },
    );

    test('only overlapping slots in the same semester conflict', () {
      final existing = course(
        name: '旧课程',
        semesterId: 'spring',
        date: '2026-09-07',
        startTime: 800,
        endTime: 945,
      );
      final replacement = course(
        name: '新课程',
        semesterId: 'spring',
        date: '2026-09-07',
        startTime: 900,
        endTime: 1000,
        roomName: 'B202',
      );
      final otherSemester = course(
        name: '其他学期',
        semesterId: 'autumn',
        date: '2026-09-07',
        startTime: 900,
        endTime: 1000,
      );

      expect(CourseScheduleSemantics.overlaps(existing, replacement), isTrue);
      expect(
        CourseScheduleSemantics.overlaps(existing, otherSemester),
        isFalse,
      );
    });

    test(
      'slot merge replaces a changed course instead of leaving a duplicate',
      () {
        final oldCourse = course(
          name: '旧课程',
          semesterId: 'spring',
          date: '2026-09-07',
          startTime: 800,
          endTime: 945,
        );
        final replacement = course(
          name: '新课程',
          semesterId: 'spring',
          date: '2026-09-07',
          startTime: 830,
          endTime: 1000,
          roomName: 'B202',
        );
        final otherSemester = course(
          name: '其他学期课程',
          semesterId: 'autumn',
          date: '2026-09-07',
          startTime: 800,
          endTime: 945,
        );

        final merged = CourseScheduleSemantics.mergeBySlot(
          [oldCourse, otherSemester],
          [replacement],
        );

        expect(merged, contains(replacement));
        expect(merged, isNot(contains(oldCourse)));
        expect(merged, contains(otherSemester));
      },
    );

    test('semester replacement preserves courses from other semesters', () {
      final spring = course(
        name: '春季课程',
        semesterId: 'spring',
        date: '2026-09-07',
        startTime: 800,
        endTime: 945,
      );
      final autumn = course(
        name: '秋季课程',
        semesterId: 'autumn',
        date: '2027-02-22',
        startTime: 800,
        endTime: 945,
      );
      final replacement = course(
        name: '春季新课程',
        semesterId: 'spring',
        date: '2026-09-07',
        startTime: 800,
        endTime: 945,
      );

      final result = CourseScheduleSemantics.replaceSemester(
        [spring, autumn],
        [replacement],
        semesterId: 'spring',
      );

      expect(result, contains(replacement));
      expect(result, isNot(contains(spring)));
      expect(result, contains(autumn));
    });
  });
}
