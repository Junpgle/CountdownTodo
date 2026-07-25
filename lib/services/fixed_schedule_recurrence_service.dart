import 'package:intl/intl.dart';

import '../models.dart';

class FixedScheduleRecurrenceLimitException implements Exception {
  const FixedScheduleRecurrenceLimitException(this.maxOccurrences);

  final int maxOccurrences;

  @override
  String toString() => '固定日程重复实例不能超过 $maxOccurrences 次';
}

/// 将固定日程重复规则物化为每个日期上的真实日程记录。
///
/// 物化后的每个实例都能独立参与冲突检测、今日展示、日历导出和团队同步，
/// 同时使用 [FixedScheduleItem.recurrenceSeriesId] 保持系列归属。
class FixedScheduleRecurrenceService {
  FixedScheduleRecurrenceService._();

  static const int maxOccurrences = 2000;

  /// 快速创建未指定截止日期时使用的可控物化窗口。
  /// 日/周类覆盖常见的 8 周安排，月重复覆盖 1 年，年重复覆盖 5 年。
  static DateTime defaultEndDate({
    required DateTime startDate,
    required RecurrenceType recurrence,
    int customIntervalDays = 1,
  }) {
    final start = _day(startDate);
    return switch (recurrence) {
      RecurrenceType.none => start,
      RecurrenceType.daily ||
      RecurrenceType.weekdays ||
      RecurrenceType.weekly =>
        start.add(const Duration(days: 56)),
      RecurrenceType.customDays => start.add(
          Duration(
            days: customIntervalDays * 8 > 56 ? customIntervalDays * 8 : 56,
          ),
        ),
      RecurrenceType.monthly => _addMonths(start, 12, start.day),
      RecurrenceType.yearly => _addYears(start, 5, start.month, start.day),
    };
  }

  static List<DateTime> occurrenceDates({
    required DateTime startDate,
    required DateTime endDate,
    required RecurrenceType recurrence,
    int customIntervalDays = 1,
  }) {
    final start = _day(startDate);
    final end = _day(endDate);
    if (end.isBefore(start) || recurrence == RecurrenceType.none) {
      return [start];
    }

    final result = <DateTime>[];
    var cursor = start;
    while (!cursor.isAfter(end) && result.length < maxOccurrences) {
      if (recurrence != RecurrenceType.weekdays || cursor.weekday <= 5) {
        result.add(cursor);
      }
      cursor = switch (recurrence) {
        RecurrenceType.daily ||
        RecurrenceType.weekdays =>
          cursor.add(const Duration(days: 1)),
        RecurrenceType.weekly => cursor.add(const Duration(days: 7)),
        RecurrenceType.monthly => _addMonths(cursor, 1, start.day),
        RecurrenceType.yearly => _addYears(cursor, 1, start.month, start.day),
        RecurrenceType.customDays => cursor.add(
            Duration(days: customIntervalDays.clamp(1, 3650).toInt()),
          ),
        RecurrenceType.none => end.add(const Duration(days: 1)),
      };
    }
    if (!cursor.isAfter(end)) {
      throw const FixedScheduleRecurrenceLimitException(maxOccurrences);
    }
    return result.isEmpty ? [start] : result;
  }

  static ({List<FixedScheduleItem> active, List<FixedScheduleItem> changes})
      rebuildSeries({
    required FixedScheduleItem template,
    required List<FixedScheduleItem> existingSeries,
    required RecurrenceType recurrence,
    required DateTime recurrenceEndDate,
    int customIntervalDays = 1,
  }) {
    final templateDate = DateTime.tryParse(template.date)?.toLocal();
    if (templateDate == null) {
      return (active: [template], changes: [template]);
    }

    final dates = occurrenceDates(
      startDate: templateDate,
      endDate: recurrenceEndDate,
      recurrence: recurrence,
      customIntervalDays: customIntervalDays,
    );
    final existingByDate = <String, FixedScheduleItem>{};
    final existingById = <String, FixedScheduleItem>{};
    for (final item in existingSeries.where((item) => !item.isDeleted)) {
      existingByDate.putIfAbsent(item.date, () => item);
      existingById[item.id] = item;
    }

    final isRepeating = recurrence != RecurrenceType.none;
    final seriesId = isRepeating
        ? (template.recurrenceSeriesId?.trim().isNotEmpty == true
            ? template.recurrenceSeriesId!
            : template.id)
        : null;
    final active = <FixedScheduleItem>[];
    final changes = <FixedScheduleItem>[];
    final usedExistingIds = <String>{};

    for (var index = 0; index < dates.length; index++) {
      final date = dates[index];
      final dateKey = _dateKey(date);
      final existing = existingByDate[dateKey] ??
          (index == 0 ? existingById[template.id] : null);
      final item = existing == null
          ? _newOccurrence(template, index == 0 ? template.id : null)
          : FixedScheduleItem.fromJson(existing.toJson());
      _applyTemplate(
        item,
        template: template,
        date: date,
        recurrence: recurrence,
        recurrenceSeriesId: seriesId,
        customIntervalDays: customIntervalDays,
      );
      if (existing != null) item.markAsChanged();
      if (existing != null) usedExistingIds.add(existing.id);
      active.add(item);
      changes.add(item);
    }

    for (final existing in existingSeries) {
      if (existing.isDeleted || usedExistingIds.contains(existing.id)) {
        continue;
      }
      final tombstone = FixedScheduleItem.fromJson(existing.toJson())
        ..isDeleted = true;
      tombstone.markAsChanged();
      changes.add(tombstone);
    }

    return (active: active, changes: changes);
  }

  static FixedScheduleItem _newOccurrence(
    FixedScheduleItem template,
    String? id,
  ) =>
      FixedScheduleItem(
        id: id,
        title: template.title,
        date: template.date,
        source: template.source,
      );

  static void _applyTemplate(
    FixedScheduleItem item, {
    required FixedScheduleItem template,
    required DateTime date,
    required RecurrenceType recurrence,
    required String? recurrenceSeriesId,
    required int customIntervalDays,
  }) {
    item
      ..title = template.title
      ..date = _dateKey(date)
      ..startTime = _moveTimeToDate(template.startTime, date)
      ..endTime = _moveTimeToDate(template.endTime, date)
      ..status = template.status
      ..source = template.source
      ..location = template.location
      ..remark = template.remark
      ..reminderMinutes = List<int>.from(template.reminderMinutes)
      ..timezone = template.timezone
      ..recurrence = recurrence
      ..customIntervalDays = recurrence == RecurrenceType.customDays
          ? customIntervalDays.clamp(1, 3650).toInt()
          : null
      ..recurrenceSeriesId = recurrenceSeriesId
      ..relatedTodoIds = List<String>.from(template.relatedTodoIds)
      ..externalSource = template.externalSource
      ..externalId = template.externalId
      ..teamUuid = template.teamUuid
      ..ownerUserId = template.ownerUserId
      ..deviceId = template.deviceId
      ..isDeleted = false;
  }

  static int? _moveTimeToDate(int? value, DateTime date) {
    if (value == null) return null;
    final source = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    return DateTime(
      date.year,
      date.month,
      date.day,
      source.hour,
      source.minute,
      source.second,
      source.millisecond,
      source.microsecond,
    ).millisecondsSinceEpoch;
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateKey(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);

  static DateTime _addMonths(DateTime value, int months, int preferredDay) {
    final monthIndex = value.year * 12 + value.month - 1 + months;
    final year = monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, preferredDay.clamp(1, lastDay).toInt());
  }

  static DateTime _addYears(
    DateTime value,
    int years,
    int preferredMonth,
    int preferredDay,
  ) {
    final year = value.year + years;
    final lastDay = DateTime(year, preferredMonth + 1, 0).day;
    return DateTime(
      year,
      preferredMonth,
      preferredDay.clamp(1, lastDay).toInt(),
    );
  }
}
