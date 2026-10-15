import 'package:countdown_todo/utils/calendar_date_math.dart';
import 'package:countdown_todo/utils/time_log_range_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splits a cross-day log by actual overlap across spring DST', () {
    final start = DateTime(2026, 3, 7, 23, 30).millisecondsSinceEpoch;
    final end = DateTime(2026, 3, 8, 4, 30).millisecondsSinceEpoch;
    final firstDay = CalendarDateMath.dayRange(DateTime(2026, 3, 7));
    final transitionDay = CalendarDateMath.dayRange(DateTime(2026, 3, 8));

    expect(
      TimeLogRangeMath.overlapMinutes(
        intervalStartMs: start,
        intervalEndMs: end,
        rangeStartMs: firstDay.start.millisecondsSinceEpoch,
        rangeEndMs: firstDay.endExclusive.millisecondsSinceEpoch,
      ),
      30,
    );
    expect(
      TimeLogRangeMath.overlapMinutes(
        intervalStartMs: start,
        intervalEndMs: end,
        rangeStartMs: transitionDay.start.millisecondsSinceEpoch,
        rangeEndMs: transitionDay.endExclusive.millisecondsSinceEpoch,
      ),
      210,
    );
  });
}
