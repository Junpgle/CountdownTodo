import 'package:countdown_todo/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('yesterday and tomorrow queries follow local calendar dates at DST', () {
    final service = SearchService.instance;

    expect(
      service.parseDateQueryForTest('昨天', now: DateTime(2026, 3, 9, 0, 30)),
      DateTime(2026, 3, 8),
    );
    expect(
      service.parseDateQueryForTest('明天', now: DateTime(2026, 3, 7, 23, 30)),
      DateTime(2026, 3, 8),
    );
  });

  test('search range ends at the next local midnight on fall-back day', () {
    final range = SearchService.dateRangeForSearch(DateTime(2026, 11, 1));

    expect(range.start, DateTime(2026, 11, 1));
    expect(range.end, DateTime(2026, 11, 2));
    expect(range.end.difference(range.start), const Duration(hours: 25));
  });
}
