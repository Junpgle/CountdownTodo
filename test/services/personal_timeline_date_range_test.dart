import 'package:countdown_todo/screens/personal_timeline_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Personal timeline date ranges', () {
    test('daily range includes the full fall-back date', () {
      final range = timelineDateRange(
        TimelineDimension.daily,
        DateTime(2026, 11, 1),
      );

      expect(range.start, DateTime(2026, 11, 1));
      expect(range.end, DateTime(2026, 11, 2));
      expect(range.end.difference(range.start), const Duration(hours: 25));
    });

    test(
      'weekly range starts and ends on local Monday across spring-forward',
      () {
        final range = timelineDateRange(
          TimelineDimension.weekly,
          DateTime(2026, 3, 8),
        );

        expect(range.start, DateTime(2026, 3, 2));
        expect(range.end, DateTime(2026, 3, 9));
        expect(range.end.difference(range.start), const Duration(hours: 167));
      },
    );
  });
}
