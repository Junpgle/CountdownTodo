/// Calendar arithmetic for local dates. A day here means the next calendar
/// date, not a fixed 24-hour duration across daylight-saving transitions.
abstract final class CalendarDateMath {
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

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
}
