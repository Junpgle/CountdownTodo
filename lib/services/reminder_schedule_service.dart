import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../features/finance/services/finance_automation_service.dart';
import '../storage_service.dart';
import 'course_service.dart';
import 'item_semantics_service.dart';
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
///       34001 ~ 41999  →  固定日程提醒（每个日程最多 8 个）
///       52001 ~ 59999  →  周期账单提醒
///   - 每次调用 scheduleAll 都覆盖上一次的完整列表（幂等）
///   - 只注册未来 7 天内的提醒，超出部分在下次 App 启动时补注册
class ReminderScheduleService {
  static const int _todoBaseId = 30001;
  static const int _courseBaseId = 31001;
  static const int _specialTodoBaseId = 32001;
  static const int _planBlockBaseId = 33001;
  static const int _fixedScheduleBaseId = 34001;
  static const int _fixedScheduleReminderStride = 8;

  // 提前多少分钟提醒
  static const int _todoAdvanceMinutes = 5;

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

  static int _lastScheduleTime = 0;
  static const int _debounceMs = 2000;

  /// 根据最新的待办 + 课程列表，重新调度所有未来提醒。
  static Future<void> scheduleAll({
    required List<TodoItem> todos,
    required List<CourseItem> courses,
    bool force = false,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && (nowMs - _lastScheduleTime < _debounceMs)) {
      return;
    }
    _lastScheduleTime = nowMs;

    final now = DateTime.now();
    final limit = now.add(const Duration(days: 7));
    final reminders = <Map<String, dynamic>>[];

    // ── 获取当前用户 ────────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final username =
        prefs.getString(StorageService.keyCurrentUser) ?? 'default';

    final fixedSchedules = await StorageService.getFixedSchedules(username);

    // ── 记账自动化 ──────────────────────────────────────────────────
    // 自动生成当前已到期周期账单，并把未来 7 天的账单加入同一套系统提醒。
    try {
      await FinanceAutomationService.reconcileCurrentPeriod(now: now);
      reminders.addAll(
        await FinanceAutomationService.buildRecurringReminders(
          now: now,
          limit: limit,
        ),
      );
    } catch (_) {
      // 记账自动化是可选能力，数据库异常不应阻断待办和课程提醒。
    }

    // ── 待办提醒（普通 + 特殊）──────────────────────────────────────────
    for (int i = 0; i < todos.length && i < 999; i++) {
      final t = todos[i];
      if (t.isDeleted || t.isDone) continue;

      final todoType = ItemSemanticsService.specialTodoTypeForTitle(t.title);
      final isSpecialTodo = todoType != 'default';

      // 确定参考时间点（优先开始时间，其次截止时间）
      DateTime? refTime;
      if (t.createdDate != null && t.createdDate! > 0) {
        refTime =
            DateTime.fromMillisecondsSinceEpoch(t.createdDate!, isUtc: true)
                .toLocal();
      } else if (t.dueDate != null) {
        refTime = t.dueDate!.toLocal();
      }

      if (refTime == null) continue;

      // 提醒提前量
      final advance = t.reminderMinutes ?? _todoAdvanceMinutes;
      final triggerAt = refTime.subtract(Duration(minutes: advance));

      // 检查是否在调度窗口内 (未来 7 天)
      if (shouldSchedulePreStart(
        startAt: refTime,
        triggerAt: triggerAt,
        now: now,
        limit: limit,
      )) {
        if (isSpecialTodo) {
          final label = _getSpecialTodoLabel(todoType);
          // 如果有时间段，显示范围，否则只显示参考时间
          String timeStr = _hm(refTime);
          if (t.dueDate != null && t.createdDate != null) {
            final end = t.dueDate!.toLocal();
            timeStr = '${_hm(refTime)} - ${_hm(end)}';
          }

          reminders.add({
            'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
            'startAtMs': refTime.toUtc().millisecondsSinceEpoch,
            'title': '$label ${t.title}',
            'text': t.remark?.isNotEmpty == true
                ? '${t.remark!} · $timeStr'
                : timeStr,
            'notifId': _specialTodoBaseId + i,
            'type': 'special_todo',
            'todoId': t.id,
            'todoType': todoType,
            'timeStr': timeStr,
            'analysisImagePath': t.imagePath,
            'originalText': t.originalText,
          });
        } else {
          // 普通待办
          String text = t.remark?.isNotEmpty == true ? t.remark! : '即将开始';
          if (t.dueDate != null && t.createdDate != null) {
            final end = t.dueDate!.toLocal();
            text += ' · ${_hm(refTime)} - ${_hm(end)}';
          } else {
            text += ' · ${_hm(refTime)}';
          }

          reminders.add({
            'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
            'startAtMs': refTime.toUtc().millisecondsSinceEpoch,
            'title': '⏰ ${t.title}',
            'text': text,
            'notifId': _todoBaseId + i,
            'type': 'upcoming_todo',
            'todoId': t.id,
            'timeStr': t.dueDate != null && t.createdDate != null
                ? '${_hm(refTime)} - ${_hm(t.dueDate!.toLocal())}'
                : _hm(refTime),
            'analysisImagePath': t.imagePath,
            'originalText': t.originalText,
          });
        }
      }
    }

    // ── 课程提醒 ──────────────────────────────────────────────────
    final courseAdvanceMinutes =
        await StorageService.getCourseReminderMinutes();
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
            courseStart.subtract(Duration(minutes: courseAdvanceMinutes));
        if (shouldSchedulePreStart(
          startAt: courseStart,
          triggerAt: triggerAt,
          now: now,
          limit: limit,
        )) {
          reminders.add({
            'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
            'startAtMs': courseStart.toUtc().millisecondsSinceEpoch,
            'courseStartMs': courseStart.toUtc().millisecondsSinceEpoch,
            'courseEndMs':
                DateTime(year, month, day, c.endTime ~/ 100, c.endTime % 100)
                    .toUtc()
                    .millisecondsSinceEpoch,
            'title': '📚 ${c.courseName}',
            'text': '${_hm(courseStart)} · ${c.roomName}',
            'notifId': _courseBaseId + i,
            'type': 'course',
            'courseId': c.uuid,
            'courseName': c.courseName,
            'room': c.roomName,
            'timeStr':
                '${_hm(courseStart)} - ${_hm(DateTime(year, month, day, c.endTime ~/ 100, c.endTime % 100))}',
            'teacher': c.teacherName,
          });
        }
      } catch (e) {
        // debugPrint('[ReminderSchedule] 课程解析出错: $e');
      }
    }

    reminders.addAll(buildFixedScheduleReminders(
      fixedSchedules: fixedSchedules,
      now: now,
      limit: limit,
    ));

    // ── 规划块提醒 ──────────────────────────────────────────────────
    final planBlocks = await StorageService.getPlanBlocks(username);
    final remindedBlocks = <TodoPlanBlock>[];
    for (int i = 0; i < planBlocks.length && i < 999; i++) {
      final pb = planBlocks[i];
      if (pb.isDeleted ||
          pb.status == TodoPlanStatus.finished ||
          pb.status == TodoPlanStatus.cancelled ||
          pb.status == TodoPlanStatus.skipped) {
        continue;
      }

      final startTime = DateTime.fromMillisecondsSinceEpoch(pb.startTime);
      final advance = pb.reminderMinutes;
      if (advance <= 0) {
        continue;
      }
      final triggerAt = startTime.subtract(Duration(minutes: advance));

      if ((pb.status == TodoPlanStatus.planned ||
              pb.status == TodoPlanStatus.reminded) &&
          !triggerAt.isAfter(now) &&
          startTime.isAfter(now) &&
          pb.status != TodoPlanStatus.reminded) {
        pb.status = TodoPlanStatus.reminded;
        pb.markAsChanged();
        remindedBlocks.add(pb);
      }

      if (shouldSchedulePreStart(
        startAt: startTime,
        triggerAt: triggerAt,
        now: now,
        limit: limit,
      )) {
        reminders.add({
          'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
          'startAtMs': startTime.toUtc().millisecondsSinceEpoch,
          'title': '📅 计划: ${pb.titleSnapshot ?? "未命名任务"}',
          'text':
              '${_hm(startTime)} - ${_hm(DateTime.fromMillisecondsSinceEpoch(pb.endTime))}${pb.remark != null ? " · ${pb.remark}" : ""}',
          'notifId': _planBlockBaseId + i,
          'type': 'plan_block',
          'timeStr':
              '${_hm(startTime)} - ${_hm(DateTime.fromMillisecondsSinceEpoch(pb.endTime))}',
          'planBlockId': pb.uuid,
          'todoId': pb.todoId,
        });
      }
    }

    if (remindedBlocks.isNotEmpty) {
      await StorageService.savePlanBlocks(username, remindedBlocks);
    }

    await NotificationService.scheduleReminders(
      reminders,
      forceReschedule: force,
    );
  }

  static Future<void> scheduleFromStorage(
    String username, {
    bool force = false,
  }) async {
    final results = await Future.wait<dynamic>([
      StorageService.getTodos(username),
      CourseService.getAllCourses(username),
    ]);
    await scheduleAll(
      todos: results[0] as List<TodoItem>,
      courses: results[1] as List<CourseItem>,
      force: force,
    );
  }

  /// 供修改周期账单或模板后的页面立即刷新系统提醒。
  static Future<void> scheduleCurrentUser({bool force = true}) async {
    final username = await StorageService.getLoginSession();
    if (username == null || username.isEmpty) return;
    await scheduleFromStorage(username, force: force);
  }

  static List<Map<String, dynamic>> buildFixedScheduleReminders({
    required List<FixedScheduleItem> fixedSchedules,
    required DateTime now,
    required DateTime limit,
  }) {
    final reminders = <Map<String, dynamic>>[];
    for (var index = 0; index < fixedSchedules.length && index < 999; index++) {
      final item = fixedSchedules[index];
      if (item.isDeleted ||
          item.status == FixedScheduleStatus.cancelled ||
          item.status == FixedScheduleStatus.finished ||
          item.startTime == null) {
        continue;
      }
      final start =
          DateTime.fromMillisecondsSinceEpoch(item.startTime!).toLocal();
      final advances = item.reminderMinutes
          .where((minutes) => minutes >= 0)
          .toSet()
          .toList()
        ..sort((left, right) => right.compareTo(left));
      final timeText = item.endTime == null
          ? '${_hm(start)} · 结束时间待定'
          : '${_hm(start)} - ${_hm(DateTime.fromMillisecondsSinceEpoch(item.endTime!).toLocal())}';
      final detailParts = [
        if (item.location?.trim().isNotEmpty == true) item.location!.trim(),
        if (item.remark?.trim().isNotEmpty == true) item.remark!.trim(),
        timeText,
      ];
      for (var reminderIndex = 0;
          reminderIndex < advances.length &&
              reminderIndex < _fixedScheduleReminderStride;
          reminderIndex++) {
        final advance = advances[reminderIndex];
        final triggerAt = start.subtract(Duration(minutes: advance));
        if (!shouldSchedulePreStart(
          startAt: start,
          triggerAt: triggerAt,
          now: now,
          limit: limit,
        )) {
          continue;
        }
        reminders.add({
          'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
          'startAtMs': start.toUtc().millisecondsSinceEpoch,
          'title': '📌 ${item.title}',
          'text': detailParts.join(' · '),
          'notifId': _fixedScheduleBaseId +
              index * _fixedScheduleReminderStride +
              reminderIndex,
          'type': 'fixed_schedule',
          'fixedScheduleId': item.id,
          'timeStr': timeText,
        });
      }
    }
    return reminders;
  }

  static String _hm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// 提前提醒时间已过但事项尚未开始时仍应保留，供灵动岛立即补发。
  static bool shouldSchedulePreStart({
    required DateTime startAt,
    required DateTime triggerAt,
    required DateTime now,
    required DateTime limit,
  }) =>
      startAt.isAfter(now) &&
      triggerAt.isBefore(limit) &&
      !triggerAt.isAfter(startAt);
}
