import 'package:countdown_todo/utils/calendar_date_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
