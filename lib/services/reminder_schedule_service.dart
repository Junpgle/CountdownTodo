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
///       32001 ~ 32999  →  特殊待办提醒（快递/外卖/餐饮）
///   - 每次调用 scheduleAll 都覆盖上一次的完整列表（幂等）
///   - 只注册未来 7 天内的提醒，超出部分在下次 App 启动时补注册
class ReminderScheduleService {
  static const int _todoBaseId = 30001;
  static const int _courseBaseId = 31001;
  static const int _specialTodoBaseId = 32001;

  // 提前多少分钟提醒
  static const int _todoAdvanceMinutes = 5;
  static const int _courseAdvanceMinutes = 10;

  /// 检测待办类型
  static String _detectTodoType(String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('快递') ||
        lowerTitle.contains('取件') ||
        lowerTitle.contains('顺丰') ||
        lowerTitle.contains('京东') ||
        lowerTitle.contains('菜鸟') ||
        lowerTitle.contains('中通') ||
        lowerTitle.contains('圆通') ||
        lowerTitle.contains('韵达') ||
        lowerTitle.contains('申通')) {
      return 'delivery';
    } else if (lowerTitle.contains('奶茶') ||
        lowerTitle.contains('咖啡') ||
        lowerTitle.contains('古茗') ||
        lowerTitle.contains('茶百道') ||
        lowerTitle.contains('蜜雪冰城') ||
        lowerTitle.contains('瑞幸') ||
        lowerTitle.contains('星巴克') ||
        lowerTitle.contains('库迪') ||
        lowerTitle.contains('coco') ||
        lowerTitle.contains('一点点')) {
      return 'cafe';
    } else if (lowerTitle.contains('取餐') ||
        lowerTitle.contains('外卖') ||
        lowerTitle.contains('肯德基') ||
        lowerTitle.contains('麦当劳') ||
        lowerTitle.contains('KFC')) {
      return 'food';
    } else if (lowerTitle.contains('海底捞') ||
        lowerTitle.contains('太二') ||
        lowerTitle.contains('外婆家') ||
        lowerTitle.contains('西贝') ||
        lowerTitle.contains('必胜客') ||
        lowerTitle.contains('堂食') ||
        lowerTitle.contains('餐饮')) {
      return 'restaurant';
    }
    return 'default';
  }

  /// 获取特殊待办的类型标签
  static String _getSpecialTodoLabel(String todoType) {
    switch (todoType) {
      case 'delivery':
        return '📦 取件';
      case 'cafe':
        return '☕ 取餐';
      case 'food':
        return '🥡 取餐';
      case 'restaurant':
        return '🍽️ 堂食';
      default:
        return '待办';
    }
  }

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

    // ── 待办提醒（普通 + 特殊）──────────────────────────────────────────
    for (int i = 0; i < todos.length && i < 999; i++) {
      final t = todos[i];
      if (t.isDeleted || t.isDone) continue;

      final todoType = _detectTodoType(t.title);
      final isSpecialTodo = todoType != 'default';

      // 有 dueDate 的具体时间待办
      if (t.dueDate != null) {
        final dueDateLocal = t.dueDate!.toLocal();
        // 只处理今天的待办
        if (!_isSameDay(dueDateLocal, now)) continue;

        // 获取开始时间
        DateTime? startTime;
        final startMs = t.createdDate;
        if (startMs != null && startMs > 0) {
          startTime = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true)
              .toLocal();
        }

        if (isSpecialTodo) {
          // 特殊待办：在开始时间触发提醒
          final triggerTime = startTime ?? dueDateLocal;
          final triggerAt =
              triggerTime.subtract(Duration(minutes: _todoAdvanceMinutes));

          if (triggerAt.isAfter(now) && triggerAt.isBefore(limit)) {
            final label = _getSpecialTodoLabel(todoType);
            final timeStr = '${_hm(triggerTime)} - ${_hm(dueDateLocal)}';
            reminders.add({
              'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
              'title': '$label ${t.title}',
              'text': t.remark?.isNotEmpty == true
                  ? '${t.remark!} · $timeStr'
                  : timeStr,
              'notifId': _specialTodoBaseId + i,
              'todoType': todoType,
            });
          }
        } else {
          // 普通待办：有开始时间的在开始前提醒
          if (startTime != null) {
            final triggerAt =
                startTime.subtract(Duration(minutes: _todoAdvanceMinutes));
            if (triggerAt.isAfter(now) && triggerAt.isBefore(limit)) {
              reminders.add({
                'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
                'title': '⏰ ${t.title}',
                'text': t.remark?.isNotEmpty == true
                    ? t.remark!
                    : '即将开始 · ${_hm(startTime)}',
                'notifId': _todoBaseId + i,
              });
            }
          }
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
        final year = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final day = int.parse(dateParts[2]);
        final hour = c.startTime ~/ 100;
        final minute = c.startTime % 100;
        final courseStart = DateTime(year, month, day, hour, minute);
        final triggerAt =
            courseStart.subtract(Duration(minutes: _courseAdvanceMinutes));
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

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _hm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
