import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../models/plan_availability.dart';

abstract final class FixedSchedulePreparationGuard {
  static Future<void> validate(
    DatabaseExecutor executor,
    FixedSchedulePreparationContext context,
    String todoId, {
    required DateTime now,
  }) async {
    final rows = await executor.query(
      'fixed_schedules',
      where: 'uuid = ? AND is_deleted = 0',
      whereArgs: [context.scheduleId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const PlanAvailabilityException('固定日程已删除，请重新查找准备时间');
    }
    final schedule = FixedScheduleItem.fromJson(
      Map<String, dynamic>.from(rows.single),
    );
    if (schedule.startTime != context.startTime ||
        schedule.status != FixedScheduleStatus.scheduled ||
        schedule.isDeleted ||
        schedule.phaseAt(now) != FixedSchedulePhase.upcoming ||
        !schedule.relatedTodoIds.contains(todoId)) {
      throw const PlanAvailabilityException('固定日程或待办关联已变化，请重新查找准备时间');
    }
  }
}
