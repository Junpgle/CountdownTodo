import 'package:countdown_todo/services/island_slot_provider.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/utils/calendar_date_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('focus totals stop at local midnight across spring DST', () {
    final records = [
      PomodoroRecord(
        uuid: 'yesterday',
        startTime: DateTime(2026, 3, 7, 23, 45).millisecondsSinceEpoch,
        plannedDuration: 1500,
        actualDuration: 1500,
      ),
      PomodoroRecord(
        uuid: 'today',
        startTime: DateTime(2026, 3, 8, 23, 30).millisecondsSinceEpoch,
        plannedDuration: 600,
        actualDuration: 600,
      ),
      PomodoroRecord(
        uuid: 'tomorrow',
        startTime: DateTime(2026, 3, 9, 0, 15).millisecondsSinceEpoch,
        plannedDuration: 300,
        actualDuration: 300,
      ),
    ];
    final yesterday = CalendarDateMath.dayRange(DateTime(2026, 3, 7));
    final today = CalendarDateMath.dayRange(DateTime(2026, 3, 8));

    expect(
      IslandSlotProvider.completedFocusSecondsInRange(
        records,
        yesterday.start,
        yesterday.endExclusive,
      ),
      1500,
    );
    expect(
      IslandSlotProvider.completedFocusSecondsInRange(
        records,
        today.start,
        today.endExclusive,
      ),
      600,
    );
  });
}
