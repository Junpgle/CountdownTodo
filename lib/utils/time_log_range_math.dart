abstract final class TimeLogRangeMath {
  static int overlapMinutes({
    required int intervalStartMs,
    required int intervalEndMs,
    required int rangeStartMs,
    required int rangeEndMs,
  }) {
    final startMs = intervalStartMs > rangeStartMs
        ? intervalStartMs
        : rangeStartMs;
    final endMs = intervalEndMs < rangeEndMs ? intervalEndMs : rangeEndMs;
    if (endMs <= startMs) return 0;
    return (endMs - startMs) ~/ const Duration(minutes: 1).inMilliseconds;
  }
}
