import 'package:flutter/foundation.dart';

import '../../../models.dart';
import '../../../services/database_helper.dart';
import '../../../services/pomodoro_service.dart';
import 'habit_rule_resolver.dart';

typedef HabitTagProgressPeriod = ({
  String habitUuid,
  List<String> tagUuids,
  DateTime logicalDate,
});

typedef HabitTagProgressSource = ({
  String habitUuid,
  List<String> tagUuids,
});

typedef HabitTodoProgressSource = ({
  String habitUuid,
  List<String> seriesIds,
});

/// 习惯数据源解析：从循环待办、专注记录读取原始数据。
///
/// 数据加载只做读取，不做任何写入或材料化副作用。
abstract final class HabitSourceResolver {
  /// 一次读取多个习惯系列的循环待办实例。
  /// 系列数超过单条 SQLite 参数上限时返回 null，由调用方沿用原读取路径。
  static Future<Map<String, List<TodoItem>>?> todosForHabitSources(
    Iterable<HabitTodoProgressSource> sources,
  ) async {
    final sourceList = sources.toList(growable: false);
    if (sourceList.isEmpty) return const {};
    final seriesIds = sourceList
        .expand((source) => source.seriesIds)
        .toSet()
        .toList(growable: false);
    if (seriesIds.length > 900) return null;

    final allTodos = await todosForSeries(seriesIds);
    final sourcesByHabit = <String, HabitTodoProgressSource>{};
    for (final source in sourceList) {
      sourcesByHabit[source.habitUuid] = source;
    }
    final habitUuidsBySeriesId = <String, Set<String>>{};
    final todosByHabit = <String, List<TodoItem>>{
      for (final habitUuid in sourcesByHabit.keys) habitUuid: <TodoItem>[],
    };
    for (final source in sourcesByHabit.values) {
      for (final seriesId in source.seriesIds) {
        (habitUuidsBySeriesId[seriesId] ??= <String>{}).add(source.habitUuid);
      }
    }
    // Keep database order while assigning each loaded todo to matching habits.
    for (final todo in allTodos) {
      final seriesId = todo.recurrenceSeriesId;
      if (seriesId == null) continue;
      for (final habitUuid
          in habitUuidsBySeriesId[seriesId] ?? const <String>{}) {
        todosByHabit[habitUuid]!.add(todo);
      }
    }
    return todosByHabit;
  }

  /// 加载一个或多个循环待办系列的全部实例（含已删除）。
  static Future<List<TodoItem>> todosForSeries(List<String> seriesIds) async {
    if (seriesIds.isEmpty) return [];
    try {
      final maps = await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        recurrenceSeriesIds: seriesIds.toSet(),
      );
      return maps.map(TodoItem.fromJson).toList();
    } catch (e) {
      debugPrint('⚠️ HabitSourceResolver 读取循环待办失败: $e');
      return [];
    }
  }

  /// 只读取指定本地日期内的循环待办，避免解码整个系列的历史记录。
  static Future<TodoItem?> todoForSeriesOnDate(
    List<String> seriesIds,
    DateTime localDate,
  ) async {
    if (seriesIds.isEmpty) return null;
    final day = DateTime(localDate.year, localDate.month, localDate.day);
    final startMs = day.millisecondsSinceEpoch;
    final endMs = DateTime(day.year, day.month, day.day + 1)
        .millisecondsSinceEpoch;
    try {
      final maps = await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        recurrenceSeriesIds: seriesIds.toSet(),
        where: '((t.created_date >= ? AND t.created_date < ?) OR '
            '(t.created_date IS NULL AND t.created_at >= ? AND t.created_at < ?))',
        whereArgs: [startMs, endMs, startMs, endMs],
      );
      return todoForDate(
        maps.map(TodoItem.fromJson).toList(growable: false),
        day,
      );
    } catch (e) {
      debugPrint('⚠️ HabitSourceResolver 按日期读取循环待办失败: $e');
      return null;
    }
  }

  /// 找到系列中归属指定本地日期的待办实例。
  ///
  /// 实例日期取业务开始时间（createdDate ?? createdAt）的本地日历日，
  /// 与循环待办材料的日期口径保持一致。
  static TodoItem? todoForDate(List<TodoItem> todos, DateTime localDate) {
    final target = DateTime(localDate.year, localDate.month, localDate.day);
    TodoItem? best;
    for (final todo in todos) {
      final day = _todoLocalDay(todo);
      if (day == null || !_sameDay(day, target)) continue;
      if (best == null) {
        best = todo;
      } else {
        // 同一日期存在多条时，优先未删除的。
        final bestDeleted = best.isDeleted;
        if (bestDeleted && !todo.isDeleted) {
          best = todo;
        }
      }
    }
    return best;
  }

  /// 为多日进度计算建立临时日期索引，避免逐日重复扫描系列实例。
  static HabitTodoIndex indexTodos(List<TodoItem> todos) =>
      HabitTodoIndex._(todos);

  /// 指定日期范围内是否完成。
  static bool isTodoDoneOn(
    List<TodoItem> todos,
    DateTime localDate,
  ) {
    final todo = todoForDate(todos, localDate);
    return todo != null && !todo.isDeleted && todo.isDone;
  }

  /// 加载绑定标签在时间范围内的有效专注记录。
  ///
  /// 默认只统计：已正常结束（completed）、未删除、无冲突的记录；
  /// 暂停时间通过 [PomodoroRecord.effectiveDuration] 排除。
  static Future<List<PomodoroRecord>> recordsForTags({
    required List<String> tagUuids,
    required DateTime from,
    required DateTime to,
  }) async {
    if (tagUuids.isEmpty) return [];
    try {
      final tagIds = tagUuids.toSet();
      final records = await PomodoroService.getRecordsInRange(
        DateTime(from.year, from.month, from.day),
        DateTime(to.year, to.month, to.day + 1),
      );
      return records.where((r) {
        if (r.isDeleted || !r.isCompleted || r.hasConflict) return false;
        return r.tagUuids.any(tagIds.contains);
      }).toList();
    } catch (e) {
      debugPrint('⚠️ HabitSourceResolver 读取专注记录失败: $e');
      return [];
    }
  }

  /// 按逻辑日期分组批量读取专注记录，再按标签筛回各习惯的数据。
  static Future<Map<String, List<PomodoroRecord>>> recordsForPeriods(
    Iterable<HabitTagProgressPeriod> periods,
  ) async {
    final byDate = <String, List<HabitTagProgressPeriod>>{};
    for (final period in periods) {
      if (period.tagUuids.isEmpty) continue;
      final day = DateTime(
        period.logicalDate.year,
        period.logicalDate.month,
        period.logicalDate.day,
      );
      byDate.putIfAbsent(HabitRuleResolver.dayKey(day), () => []).add((
        habitUuid: period.habitUuid,
        tagUuids: period.tagUuids,
        logicalDate: day,
      ));
    }
    if (byDate.isEmpty) return const {};

    if (byDate.length > 1) {
      final days = byDate.values.map((group) => group.first.logicalDate);
      final firstDay = days.reduce((a, b) => a.isBefore(b) ? a : b);
      final lastDay = days.reduce((a, b) => a.isAfter(b) ? a : b);
      if (HabitRuleResolver.calendarDayDifference(lastDay, firstDay) == 1) {
        final tagUuids = byDate.values
            .expand((group) => group)
            .expand((period) => period.tagUuids)
            .toSet()
            .toList(growable: false);
        final allRecords = await recordsForTags(
          tagUuids: tagUuids,
          from: HabitRuleResolver.addCalendarDays(firstDay, -1),
          to: HabitRuleResolver.addCalendarDays(lastDay, 1),
        );

        // Current logical dates differ by at most one day for day-boundary
        // rules. Fetch their overlapping three-day windows with one query.
        final groupDatesByRecordDay = <String, Set<String>>{};
        final recordsByGroupDate = <String, List<PomodoroRecord>>{
          for (final dateKey in byDate.keys) dateKey: <PomodoroRecord>[],
        };
        for (final entry in byDate.entries) {
          final day = entry.value.first.logicalDate;
          for (var offset = -1; offset <= 1; offset++) {
            final recordDay = HabitRuleResolver.addCalendarDays(day, offset);
            (groupDatesByRecordDay[HabitRuleResolver.dayKey(recordDay)] ??=
                    <String>{})
                .add(entry.key);
          }
        }
        for (final record in allRecords) {
          final localStart = DateTime.fromMillisecondsSinceEpoch(
            record.startTime,
          ).toLocal();
          final recordDayKey = HabitRuleResolver.dayKey(
            DateTime(localStart.year, localStart.month, localStart.day),
          );
          for (final groupDate
              in groupDatesByRecordDay[recordDayKey] ?? const <String>{}) {
            recordsByGroupDate[groupDate]!.add(record);
          }
        }

        final recordsByHabit = <String, List<PomodoroRecord>>{};
        for (final entry in byDate.entries) {
          recordsByHabit.addAll(
            _recordsByHabit(
              records: recordsByGroupDate[entry.key]!,
              sources: entry.value.map(
                (period) =>
                    (habitUuid: period.habitUuid, tagUuids: period.tagUuids),
              ),
            ),
          );
        }
        return recordsByHabit;
      }
    }

    final recordsByHabit = <String, List<PomodoroRecord>>{};
    for (final group in byDate.values) {
      final day = group.first.logicalDate;
      final tagUuids = group
          .expand((period) => period.tagUuids)
          .toSet()
          .toList(growable: false);
      final records = tagUuids.isEmpty
          ? const <PomodoroRecord>[]
          : await recordsForTags(
              tagUuids: tagUuids,
              from: HabitRuleResolver.addCalendarDays(day, -1),
              to: HabitRuleResolver.addCalendarDays(day, 1),
            );
      recordsByHabit.addAll(
        _recordsByHabit(
          records: records,
          sources: group.map(
            (period) =>
                (habitUuid: period.habitUuid, tagUuids: period.tagUuids),
          ),
        ),
      );
    }
    return recordsByHabit;
  }

  /// 为一组习惯的相同日期范围读取专注记录，并按标签拆分回各习惯。
  static Future<Map<String, List<PomodoroRecord>>> recordsForRange(
    Iterable<HabitTagProgressSource> sources, {
    required DateTime from,
    required DateTime to,
  }) async {
    final sourceList = sources
        .where((source) => source.tagUuids.isNotEmpty)
        .toList(growable: false);
    if (sourceList.isEmpty) return const {};
    final tagUuids = sourceList
        .expand((source) => source.tagUuids)
        .toSet()
        .toList(growable: false);
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    final records = await recordsForTags(
      tagUuids: tagUuids,
      from: HabitRuleResolver.addCalendarDays(fromDay, -1),
      to: HabitRuleResolver.addCalendarDays(toDay, 1),
    );
    return _recordsByHabit(records: records, sources: sourceList);
  }

  /// Group a shared, ordered record list without rescanning it for each habit.
  static Map<String, List<PomodoroRecord>> _recordsByHabit({
    required List<PomodoroRecord> records,
    required Iterable<HabitTagProgressSource> sources,
  }) {
    final sourcesByHabit = <String, HabitTagProgressSource>{};
    for (final source in sources) {
      sourcesByHabit[source.habitUuid] = source;
    }
    final recordsByHabit = <String, List<PomodoroRecord>>{
      for (final habitUuid in sourcesByHabit.keys)
        habitUuid: <PomodoroRecord>[],
    };
    final habitUuidsByTagUuid = <String, Set<String>>{};
    for (final source in sourcesByHabit.values) {
      for (final tagUuid in source.tagUuids) {
        (habitUuidsByTagUuid[tagUuid] ??= <String>{}).add(source.habitUuid);
      }
    }

    // The outer record loop preserves the source query's order per habit.
    final lastAddedRecordIndexByHabit = <String, int>{};
    for (var recordIndex = 0; recordIndex < records.length; recordIndex++) {
      final record = records[recordIndex];
      for (final tagUuid in record.tagUuids) {
        for (final habitUuid
            in habitUuidsByTagUuid[tagUuid] ?? const <String>{}) {
          if (lastAddedRecordIndexByHabit[habitUuid] == recordIndex) continue;
          recordsByHabit[habitUuid]!.add(record);
          lastAddedRecordIndexByHabit[habitUuid] = recordIndex;
        }
      }
    }
    return recordsByHabit;
  }

  static DateTime? _todoLocalDay(TodoItem todo) {
    final ms = todo.createdDate ?? todo.createdAt;
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class HabitTodoIndex {
  final Map<DateTime, TodoItem> _bestTodoByDay = {};
  final Map<DateTime, int> _completedCountByDay = {};

  HabitTodoIndex._(List<TodoItem> todos) {
    for (final todo in todos) {
      final day = HabitSourceResolver._todoLocalDay(todo);
      if (day == null) continue;
      final key = DateTime(day.year, day.month, day.day);
      final current = _bestTodoByDay[key];
      if (current == null || (current.isDeleted && !todo.isDeleted)) {
        _bestTodoByDay[key] = todo;
      }
      if (!todo.isDeleted && todo.isDone) {
        _completedCountByDay[key] = (_completedCountByDay[key] ?? 0) + 1;
      }
    }
  }

  bool isTodoDoneOn(DateTime localDate) {
    final day = DateTime(localDate.year, localDate.month, localDate.day);
    final todo = _bestTodoByDay[day];
    return todo != null && !todo.isDeleted && todo.isDone;
  }

  int completedCountInRange(DateTime start, DateTime end) {
    var day = DateTime(start.year, start.month, start.day);
    var count = 0;
    while (day.isBefore(end)) {
      count += _completedCountByDay[day] ?? 0;
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return count;
  }
}
