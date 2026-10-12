import 'package:countdown_todo/utils/calendar_date_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local day ranges end at the next midnight across DST', () {
    final range = CalendarDateMath.dayRange(DateTime(2026, 3, 8));

    expect(range.start, DateTime(2026, 3, 8));
    expect(range.endExclusive, DateTime(2026, 3, 9));
    expect(range.endExclusive.difference(range.start).inHours, 23);
  });

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
