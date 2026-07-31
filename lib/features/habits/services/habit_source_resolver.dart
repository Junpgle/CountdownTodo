import 'package:flutter/foundation.dart';

import '../../../models.dart';
import '../../../services/database_helper.dart';
import '../../../services/pomodoro_service.dart';

/// 习惯数据源解析：从循环待办、专注记录读取原始数据。
///
/// 数据加载只做读取，不做任何写入或材料化副作用。
abstract final class HabitSourceResolver {
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
      final records = await PomodoroService.getRecordsInRange(
        DateTime(from.year, from.month, from.day),
        DateTime(to.year, to.month, to.day, 23, 59, 59),
      );
      if (tagUuids.isEmpty) return [];
      return records.where((r) {
        if (r.isDeleted || !r.isCompleted || r.hasConflict) return false;
        return r.tagUuids.any(tagUuids.contains);
      }).toList();
    } catch (e) {
      debugPrint('⚠️ HabitSourceResolver 读取专注记录失败: $e');
      return [];
    }
  }

  static DateTime? _todoLocalDay(TodoItem todo) {
    final ms = todo.createdDate ?? todo.createdAt;
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
