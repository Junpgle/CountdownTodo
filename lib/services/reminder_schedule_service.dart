import 'package:flutter/foundation.dart';
import '../models.dart';
import '../services/course_service.dart';
import 'notification_service.dart';

/// 保活提醒调度服务
///
/// 职责：把待办 / 课程的提醒时间转成精确 Alarm 注册到系统，
/// 即使 App 被杀后也能在正确时刻弹出通知。
///
/// 设计原则：
///   - notifId 区间约定（防冲突）：
///       30001 ~ 30999  →  待办提醒
///       31001 ~ 31999  →  课程提醒
///   - 每次调用 scheduleAll 都覆盖上一次的完整列表（幂等）
///   - 只注册未来 7 天内的提醒，超出部分在下次 App 启动时补注册
class ReminderScheduleService {
  static const int _todoBaseId   = 30001;
  static const int _courseBaseId = 31001;

  // 提前多少分钟提醒
  static const int _todoAdvanceMinutes   = 5;
  static const int _courseAdvanceMinutes = 10;

  /// 根据最新的待办 + 课程列表，重新调度所有未来提醒。
  /// 在以下时机调用：
  ///   1. App 启动完成
  ///   2. 用户新增 / 修改 / 删除待办或课程
  ///   3. 同步完成后
  static Future<void> scheduleAll({
    required List<TodoItem> todos,
    required List<CourseItem> courses,
  }) async {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 7));
    final reminders = <Map<String, dynamic>>[];

    // ── 待办提醒 ──────────────────────────────────────────────────
    for (int i = 0; i < todos.length && i < 999; i++) {
      final t = todos[i];
      if (t.isDeleted || t.isDone) continue;

      // 有 createdDate（开始时间）的具体时间待办
      final startMs = t.createdDate;
      if (startMs != null && startMs > 0) {
        final startLocal = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
        final triggerAt = startLocal.subtract(Duration(minutes: _todoAdvanceMinutes));
        if (triggerAt.isAfter(now) && triggerAt.isBefore(limit)) {
          reminders.add({
            'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
            'title': '⏰ ${t.title}',
            'text': t.remark?.isNotEmpty == true
                ? t.remark!
                : '即将开始 · ${_hm(startLocal)}',
            'notifId': _todoBaseId + i,
          });
        }
      }
    }

    // ── 课程提醒 ──────────────────────────────────────────────────
    for (int i = 0; i < courses.length && i < 999; i++) {
      final c = courses[i];
      // 课程 date 是 yyyy-MM-dd，startTime 是 800/1000 等整数
      try {
        final dateParts = c.date.split('-');
        if (dateParts.length != 3) continue;
        final year  = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final day   = int.parse(dateParts[2]);
        final hour   = c.startTime ~/ 100;
        final minute = c.startTime % 100;
        final courseStart = DateTime(year, month, day, hour, minute);
        final triggerAt = courseStart.subtract(Duration(minutes: _courseAdvanceMinutes));
        if (triggerAt.isAfter(now) && triggerAt.isBefore(limit)) {
          reminders.add({
            'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
            'title': '📚 ${c.courseName}',
            'text': '${_hm(courseStart)} · ${c.roomName}',
            'notifId': _courseBaseId + i,
          });
        }
      } catch (e) {
        debugPrint('[ReminderSchedule] 课程解析出错: $e');
      }
    }

    if (reminders.isEmpty) {
      debugPrint('[ReminderSchedule] 无未来提醒，跳过注册');
      return;
    }

    debugPrint('[ReminderSchedule] 注册 ${reminders.length} 个提醒');
    await NotificationService.scheduleReminders(reminders);
  }

  static String _hm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
