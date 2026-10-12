import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'plan_todo_guard.dart';
import 'scheduled_reminder_registry.dart';

/// A scheduler may have collected a plan before the user cancelled it. Check
/// the latest stored status when the queued reminders are actually applied.
class PlanReminderGuard {
  static Future<List<Map<String, dynamic>>> filterCancelled(
    List<Map<String, dynamic>> reminders, {
    Database? databaseOverride,
  }) async {
    bool isPlan(Map<String, dynamic> r) =>
        r['type'] == 'plan_block' &&
        ScheduledReminderRegistry.sourceOf(r) ==
            ScheduledReminderSources.reminderSchedule;
    final ids = reminders
        .where(isPlan)
        .map((r) => r['planBlockId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return reminders;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final username = prefs.getString('current_login_user');
    final identity = await PlanTodoIdentity.capture(
      username == null || username.isEmpty ? 'default' : username,
    );
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(identity.username);
    final excluded = <String>{};
    for (var start = 0; start < ids.length; start += 200) {
      final batch = ids.skip(start).take(200).toList();
      final rows = await db.query(
        'todo_plan_blocks',
        columns: ['uuid'],
        where:
            'uuid IN (${List.filled(batch.length, '?').join(',')}) AND (COALESCE(is_deleted,0)<>0 OR status IN (1,3,7))',
        whereArgs: batch,
      );
      excluded.addAll(rows.map((r) => r['uuid'] as String));
    }
    await identity.check();
    return reminders
        .where(
          (r) => !isPlan(r) || !excluded.contains(r['planBlockId']?.toString()),
        )
        .toList();
  }
}
