import 'package:countdown_todo/utils/calendar_date_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local day ranges end at the next midnight across DST', () {
    final range = CalendarDateMath.dayRange(DateTime(2026, 3, 8));

    expect(range.start, DateTime(2026, 3, 8));
    expect(range.endExclusive, DateTime(2026, 3, 9));
    expect(range.endExclusive.difference(range.start).inHours, 23);
  });

  test('local week ranges use Monday and next Monday across DST', () {
    final spring = CalendarDateMath.weekRange(DateTime(2026, 3, 8));
    final fall = CalendarDateMath.weekRange(DateTime(2026, 11, 1));

    expect(spring.start, DateTime(2026, 3, 2));
    expect(spring.endExclusive, DateTime(2026, 3, 9));
    expect(fall.start, DateTime(2026, 10, 26));
    expect(fall.endExclusive, DateTime(2026, 11, 2));
  });

  test(
    'inclusive local date iteration neither skips nor repeats DST dates',
    () {
      expect(
        CalendarDateMath.datesBetweenInclusive(
          DateTime(2026, 3, 7),
          DateTime(2026, 3, 9),
        ),
        [DateTime(2026, 3, 7), DateTime(2026, 3, 8), DateTime(2026, 3, 9)],
      );
      expect(
        CalendarDateMath.datesBetweenInclusive(
          DateTime(2026, 10, 31),
          DateTime(2026, 11, 2),
        ),
        [DateTime(2026, 10, 31), DateTime(2026, 11, 1), DateTime(2026, 11, 2)],
      );
    },
  );

  test('date-axis offsets keep equal local times aligned across DST', () {
    expect(
      CalendarDateMath.dayOffset(
        DateTime(2026, 3, 7, 12),
        DateTime(2026, 3, 8, 12),
      ),
      1,
    );
  });
}
