import '../models.dart';

/// A display group for fixed schedules related to a todo.
///
/// Repeating occurrences are grouped by series and title. Keeping title in the
/// key prevents a one-off title edit from making the summary claim that every
/// occurrence has the same name.
class FixedScheduleTodoRelationGroup {
  const FixedScheduleTodoRelationGroup({
    required this.key,
    required this.title,
    required this.items,
    required this.summaryItem,
    this.seriesId,
  });

  final String key;
  final String title;
  final List<FixedScheduleItem> items;
  final FixedScheduleItem summaryItem;
  final String? seriesId;

  bool get isSeries => seriesId != null && items.length > 1;
}

/// Filters and groups reverse fixed-schedule links for the todo detail view.
class FixedScheduleTodoRelationService {
  static List<FixedScheduleTodoRelationGroup> groupForTodo({
    required TodoItem todo,
    required Iterable<FixedScheduleItem> schedules,
    DateTime? now,
  }) {
    final currentTime = (now ?? DateTime.now()).toLocal();
    final todoTeam = _normalizeTeamId(todo.teamUuid);
    final grouped = <String, List<FixedScheduleItem>>{};
    final titles = <String, String>{};
    final seriesIds = <String, String?>{};

    for (final item in schedules) {
      if (item.isDeleted || !item.relatedTodoIds.contains(todo.id)) continue;
      if (_normalizeTeamId(item.teamUuid) != todoTeam) continue;

      final seriesId = item.recurrenceSeriesId?.trim();
      final normalizedSeriesId = seriesId == null || seriesId.isEmpty
          ? null
          : seriesId;
      final title = item.title.trim();
      final key = normalizedSeriesId == null
          ? 'item:${item.id}'
          : 'series:${normalizedSeriesId.length}:$normalizedSeriesId:${title.length}:$title';
      grouped.putIfAbsent(key, () => <FixedScheduleItem>[]).add(item);
      titles[key] = title;
      seriesIds[key] = normalizedSeriesId;
    }

    final result = <FixedScheduleTodoRelationGroup>[];
    for (final entry in grouped.entries) {
      final items = entry.value
        ..sort((a, b) => _compareOccurrences(a, b, currentTime));
      result.add(
        FixedScheduleTodoRelationGroup(
          key: entry.key,
          title: titles[entry.key] ?? items.first.title,
          items: List.unmodifiable(items),
          summaryItem: items.first,
          seriesId: seriesIds[entry.key],
        ),
      );
    }
    result.sort(
      (a, b) => _compareOccurrences(a.summaryItem, b.summaryItem, currentTime),
    );
    return List.unmodifiable(result);
  }

  static String? _normalizeTeamId(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static int _compareOccurrences(
    FixedScheduleItem a,
    FixedScheduleItem b,
    DateTime now,
  ) {
    final priorityA = _priority(a, now);
    final priorityB = _priority(b, now);
    if (priorityA != priorityB) return priorityA.compareTo(priorityB);

    final dateA = _dateTime(a);
    final dateB = _dateTime(b);
    final chronological = dateA.compareTo(dateB);
    if (priorityA >= 3 && chronological != 0) return -chronological;
    if (chronological != 0) return chronological;
    return a.id.compareTo(b.id);
  }

  /// Lower values are preferred for the compact series summary.
  static int _priority(FixedScheduleItem item, DateTime now) {
    switch (item.phaseAt(now)) {
      case FixedSchedulePhase.ongoing:
        return 0;
      case FixedSchedulePhase.upcoming:
        return 1;
      case FixedSchedulePhase.timeTbd:
        final today = DateTime(now.year, now.month, now.day);
        return _dateTime(item).isBefore(today) ? 3 : 2;
      case FixedSchedulePhase.ended:
        return 3;
      case FixedSchedulePhase.cancelled:
        return 4;
    }
  }

  static DateTime _dateTime(FixedScheduleItem item) {
    final start = item.startTime;
    if (start != null) {
      return DateTime.fromMillisecondsSinceEpoch(start).toLocal();
    }
    final parsed = DateTime.tryParse(item.date)?.toLocal();
    return parsed == null
        ? DateTime.fromMillisecondsSinceEpoch(item.createdAt).toLocal()
        : DateTime(parsed.year, parsed.month, parsed.day);
  }
}
