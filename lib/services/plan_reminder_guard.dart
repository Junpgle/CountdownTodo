import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'plan_todo_guard.dart';
import 'scheduled_reminder_registry.dart';

/// A scheduler may hold a stale plan snapshot. Check the latest stored status
/// when queued reminders are applied; only pending plan states can be alerted.
class PlanReminderGuard {
  static Future<List<Map<String, dynamic>>> filterSchedulablePlanReminders(
    List<Map<String, dynamic>> reminders, {
    Database? databaseOverride,
  }) async {
    bool isPlan(Map<String, dynamic> r) =>
        r['type'] == 'plan_block' &&
        ScheduledReminderRegistry.sourceOf(r) ==
            ScheduledReminderSources.reminderSchedule;
    String? planId(Map<String, dynamic> reminder) {
      final id = reminder['planBlockId']?.toString().trim();
      return id == null || id.isEmpty ? null : id;
    }

    final ids = reminders
        .where(isPlan)
        .map(planId)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return reminders.where((r) => !isPlan(r)).toList(growable: false);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final username = prefs.getString('current_login_user');
    final identity = await PlanTodoIdentity.capture(
      username == null || username.isEmpty ? 'default' : username,
    );
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(identity.username);
    final schedulable = <String>{};
    for (var start = 0; start < ids.length; start += 200) {
      final batch = ids.skip(start).take(200).toList();
      final rows = await db.query(
        'todo_plan_blocks',
        columns: ['uuid'],
        where:
            'uuid IN (${List.filled(batch.length, '?').join(',')}) AND '
            'COALESCE(is_deleted,0)=0 AND status IN (0,2,4)',
        whereArgs: batch,
      );
      schedulable.addAll(rows.map((r) => r['uuid'] as String));
    }
    await identity.check();
    return reminders
        .where((r) {
          if (!isPlan(r)) return true;
          final id = planId(r);
          return id != null && schedulable.contains(id);
        })
        .toList(growable: false);
  }
}
