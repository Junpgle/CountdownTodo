import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/screens/plan_split_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats a same-day split with a compact end time', () {
    final start = DateTime(2026, 12, 4, 9, 15);
    final end = DateTime(2026, 12, 4, 10);

    expect(
      splitTimeLabel(PlanTimeSlot(start, end)),
      matches(RegExp(r'^12/4 09:15–10:00 · 45分钟 \(UTC[+-]\d{2}:\d{2}\)$')),
    );
  });

  test('includes the end date for a split that crosses midnight', () {
    final start = DateTime(2026, 12, 4, 23, 45);
    final end = DateTime(2026, 12, 5, 1, 15);

    expect(
      splitTimeLabel(PlanTimeSlot(start, end)),
      matches(RegExp(r'^12/4 23:45–12/5 01:15 · 90分钟 \(UTC[+-]\d{2}:\d{2}\)$')),
    );
  });
}
