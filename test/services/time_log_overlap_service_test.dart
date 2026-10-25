import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/services/time_log_overlap_service.dart';
import 'package:flutter_test/flutter_test.dart';

int at(int hour, int minute, {int day = 19}) =>
    DateTime(2026, 10, day, hour, minute).millisecondsSinceEpoch;

TimeLogItem log(
  String id,
  int start,
  int end, {
  String title = '日志',
  bool deleted = false,
}) => TimeLogItem(
  id: id,
  title: title,
  startTime: start,
  endTime: end,
  isDeleted: deleted,
);

PomodoroRecord pomodoro(
  String id,
  int start,
  int? end, {
  List<PauseInterval>? pauses,
  bool deleted = false,
  String? title,
}) => PomodoroRecord(
  uuid: id,
  startTime: start,
  endTime: end,
  plannedDuration: 25 * 60,
  actualDuration: 25 * 60,
  pauseIntervals: pauses,
  isDeleted: deleted,
  todoTitle: title,
);

void main() {
  group('TimeLogOverlapService.find', () {
    test('uses half-open intervals, so adjacent records do not overlap', () {
      final result = TimeLogOverlapService.find(
        startTime: at(10, 0),
        endTime: at(11, 0),
        timeLogs: [
          log('before', at(9, 0), at(10, 0)),
          log('after', at(11, 0), at(12, 0)),
        ],
        pomodoros: const [],
      );

      expect(result, isEmpty);
    });

    test(
      'reports manual logs and completed Pomodoro overlaps in start order',
      () {
        final result = TimeLogOverlapService.find(
          startTime: at(10, 0),
          endTime: at(10, 30),
          timeLogs: [
            log('later', at(10, 20), at(10, 40), title: '后一个'),
            log('earlier', at(9, 50), at(10, 10), title: '前一个'),
          ],
          pomodoros: [pomodoro('pom', at(10, 5), at(10, 25), title: '复习')],
          nowMilliseconds: at(12, 0),
        );

        expect(result.map((item) => item.id), ['earlier', 'pom', 'later']);
        expect(result.map((item) => item.overlapMilliseconds), [
          const Duration(minutes: 10).inMilliseconds,
          const Duration(minutes: 20).inMilliseconds,
          const Duration(minutes: 10).inMilliseconds,
        ]);
        expect(result[0].overlapIntervals.single.startTime, at(10, 0));
        expect(result[0].overlapIntervals.single.endTime, at(10, 10));
        expect(result[1].source, TimeLogOverlapSource.pomodoro);
        expect(result[1].title, '复习');
        expect(result[1].overlapIntervals.single.startTime, at(10, 5));
        expect(result[1].overlapIntervals.single.endTime, at(10, 25));
        expect(result[2].overlapIntervals.single.startTime, at(10, 20));
        expect(result[2].overlapIntervals.single.endTime, at(10, 30));
      },
    );

    test('excludes the edited log, deleted and invalid logs, and unfinished Pomodoros', () {
      final result = TimeLogOverlapService.find(
        startTime: at(10, 0),
        endTime: at(10, 30),
        timeLogs: [
          log('self', at(10, 0), at(10, 30)),
          log('deleted', at(10, 0), at(10, 30), deleted: true),
          log('invalid', at(10, 30), at(10, 0)),
        ],
        pomodoros: [
          pomodoro('unfinished', at(10, 0), null),
          pomodoro('future', at(10, 0), at(10, 30)),
          pomodoro('deleted-pom', at(10, 0), at(10, 30), deleted: true),
        ],
        excludingTimeLogId: 'self',
        nowMilliseconds: at(10, 20),
      );

      expect(result, isEmpty);
    });

    test('does not warn inside a Pomodoro pause and counts active overlap around it', () {
      final session = pomodoro(
        'pom',
        at(9, 0),
        at(10, 0),
        title: '专注任务',
        pauses: [
          PauseInterval(startMs: at(9, 20), endMs: at(9, 35)),
          PauseInterval(startMs: at(9, 30), endMs: at(9, 40)),
        ],
      );

      final pauseOnly = TimeLogOverlapService.find(
        startTime: at(9, 22),
        endTime: at(9, 30),
        timeLogs: const [],
        pomodoros: [session],
        nowMilliseconds: at(11, 0),
      );
      final aroundPause = TimeLogOverlapService.find(
        startTime: at(9, 15),
        endTime: at(9, 45),
        timeLogs: const [],
        pomodoros: [session],
        nowMilliseconds: at(11, 0),
      );

      expect(pauseOnly, isEmpty);
      expect(
        aroundPause.single.overlapMilliseconds,
        const Duration(minutes: 10).inMilliseconds,
      );
      expect(aroundPause.single.overlapIntervals, hasLength(2));
      expect(aroundPause.single.overlapIntervals[0].startTime, at(9, 15));
      expect(aroundPause.single.overlapIntervals[0].endTime, at(9, 20));
      expect(aroundPause.single.overlapIntervals[1].startTime, at(9, 40));
      expect(aroundPause.single.overlapIntervals[1].endTime, at(9, 45));
    });

    test('handles intervals crossing midnight and sub-minute overlaps', () {
      final result = TimeLogOverlapService.find(
        startTime: at(23, 55),
        endTime: at(0, 10, day: 20),
        timeLogs: [
          log('cross-day', at(23, 59), at(0, 2, day: 20)),
          log('tiny', at(0, 9, day: 20), at(0, 9, day: 20) + 30_000),
        ],
        pomodoros: const [],
      );

      expect(result.map((item) => item.id), ['cross-day', 'tiny']);
      expect(result.last.overlapMilliseconds, 30_000);
      expect(result.first.overlapIntervals.single.startTime, at(23, 59));
      expect(result.first.overlapIntervals.single.endTime, at(0, 2, day: 20));
      expect(result.last.overlapIntervals.single.startTime, at(0, 9, day: 20));
      expect(
        result.last.overlapIntervals.single.endTime,
        at(0, 9, day: 20) + 30_000,
      );
    });

    test('returns no matches for an invalid requested interval', () {
      expect(
        TimeLogOverlapService.find(
          startTime: at(10, 0),
          endTime: at(10, 0),
          timeLogs: [log('existing', at(9, 0), at(11, 0))],
          pomodoros: const [],
        ),
        isEmpty,
      );
    });
  });
}
