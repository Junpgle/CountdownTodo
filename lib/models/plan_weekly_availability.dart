import 'dart:convert';

/// Wall-clock minutes. Midnight at the end of a day is represented by 1440.
class PlanWeeklyWindow {
  const PlanWeeklyWindow(this.start, this.end);
  final int start, end;
  String get label => '${time(start)}–${time(end)}';
  static String time(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

class PlanWeeklyRules {
  PlanWeeklyRules({
    required this.enabled,
    required List<List<PlanWeeklyWindow>> days,
  }) : days = List.unmodifiable(
         days.map((d) => List<PlanWeeklyWindow>.unmodifiable(_normalize(d))),
       ) {
    if (days.length != 7) throw const FormatException('每周规则必须包含七天');
  }
  factory PlanWeeklyRules.initial() => PlanWeeklyRules(
    enabled: false,
    days: List.generate(7, (_) => [const PlanWeeklyWindow(0, 1440)]),
  );
  final bool enabled;
  final List<List<PlanWeeklyWindow>> days;
  static const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static List<PlanWeeklyWindow> _normalize(List<PlanWeeklyWindow> input) {
    if (input.length > 4 ||
        input.any((w) => w.start < 0 || w.end > 1440 || w.start >= w.end)) {
      throw const FormatException('每天最多四段，结束须晚于开始');
    }
    final sorted = List<PlanWeeklyWindow>.of(input)
      ..sort((a, b) => a.start.compareTo(b.start));
    final merged = <PlanWeeklyWindow>[];
    for (final w in sorted) {
      if (merged.isEmpty || w.start > merged.last.end) {
        merged.add(w);
      } else if (w.end > merged.last.end) {
        merged[merged.length - 1] = PlanWeeklyWindow(merged.last.start, w.end);
      }
    }
    return merged;
  }

  PlanWeeklyRules copy({bool? enabled, List<List<PlanWeeklyWindow>>? days}) =>
      PlanWeeklyRules(
        enabled: enabled ?? this.enabled,
        days: days ?? this.days,
      );
  String summary(int weekday) {
    final windows = days[weekday - 1];
    if (windows.isEmpty) return '不推荐';
    if (windows.length == 1 &&
        windows.first.start == 0 &&
        windows.first.end == 1440) {
      return '全天';
    }
    return windows.map((w) => w.label).join('  ');
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'enabled': enabled,
    'days': [
      for (final d in days)
        [
          for (final w in d) [w.start, w.end],
        ],
    ],
  };
  String get fingerprint => jsonEncode(toJson());
  factory PlanWeeklyRules.fromJson(Object? json) {
    if (json is! Map ||
        json.length != 3 ||
        json['version'] is! int ||
        json['version'] != 1 ||
        json['enabled'] is! bool ||
        json['days'] is! List ||
        (json['days'] as List).length != 7) {
      throw const FormatException('每周可安排时间格式无效');
    }
    final days = <List<PlanWeeklyWindow>>[];
    for (final d in json['days']) {
      if (d is! List || d.length > 4) throw const FormatException('每天最多四段');
      final windows = <PlanWeeklyWindow>[];
      for (final w in d) {
        if (w is! List || w.length != 2 || w[0] is! int || w[1] is! int) {
          throw const FormatException('每周时段格式无效');
        }
        windows.add(PlanWeeklyWindow(w[0], w[1]));
      }
      days.add(windows);
    }
    return PlanWeeklyRules(enabled: json['enabled'], days: days);
  }

  /// Reject nonexistent and ambiguous local boundaries instead of silently
  /// normalizing a DST transition. Offset candidates cover local transitions,
  /// including non-hour folds, without depending on a timezone database.
  static DateTime boundary(DateTime day, int minute) {
    final wall = DateTime.utc(
      day.year,
      day.month,
      day.day,
      minute ~/ 60,
      minute % 60,
    );
    final local = DateTime(
      day.year,
      day.month,
      day.day,
      minute ~/ 60,
      minute % 60,
    );
    final offsets = <int>{};
    for (var hours = -48; hours <= 48; hours += 6) {
      offsets.add(local.add(Duration(hours: hours)).timeZoneOffset.inMinutes);
    }
    final matches = <DateTime>[];
    for (final offset in offsets) {
      final candidate = wall.subtract(Duration(minutes: offset)).toLocal();
      if (candidate.year == wall.year &&
          candidate.month == wall.month &&
          candidate.day == wall.day &&
          candidate.hour == wall.hour &&
          candidate.minute == wall.minute) {
        matches.add(candidate);
      }
    }
    if (matches.length != 1) {
      throw const FormatException('每周时间边界处于夏令时缺失或重复时段，请调整规则');
    }
    return matches.single;
  }
}

/// Null on a query means manual/legacy calculation. Recommendations capture a
/// whole immutable policy, including an explicit one-query exemption.
class PlanWeeklyContext {
  const PlanWeeklyContext(this.rules, {this.ignored = false});
  final PlanWeeklyRules? rules;
  final bool ignored;
  bool get active => !ignored && (rules?.enabled ?? false);
  String? get fingerprint => rules?.fingerprint;
}
