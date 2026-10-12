/// Calendar arithmetic for local dates. A day here means the next calendar
/// date, not a fixed 24-hour duration across daylight-saving transitions.
abstract final class CalendarDateMath {
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static ({DateTime start, DateTime endExclusive}) dayRange(DateTime value) {
    final start = dateOnly(value);
    return (start: start, endExclusive: addDays(start, 1));
  }

  static DateTime addDays(DateTime value, int days) => DateTime(
        value.year,
        value.month,
        value.day + days,
        value.hour,
        value.minute,
        value.second,
        value.millisecond,
        value.microsecond,
      );

  static int daysBetween(DateTime start, DateTime end) =>
      DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays;

  /// Returns a date-axis offset where every local calendar date has equal
  /// width, including dates around daylight-saving transitions.
  static double dayOffset(DateTime start, DateTime end) {
    int microsecondsWithinDay(DateTime value) =>
        (((value.hour * 60 + value.minute) * 60 + value.second) *
                Duration.microsecondsPerSecond) +
            value.millisecond * Duration.microsecondsPerMillisecond +
            value.microsecond;

    return daysBetween(start, end) +
        (microsecondsWithinDay(end) - microsecondsWithinDay(start)) /
            const Duration(days: 1).inMicroseconds;
  }
}
