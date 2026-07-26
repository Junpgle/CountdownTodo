import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/macos_pomodoro_status_bar_service_io.dart';
import 'package:countdown_todo/services/ongoing_activity_service.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/services/pomodoro_sync_service.dart';
import 'package:countdown_todo/services/reminder_schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OngoingActivityService', () {
    final now = DateTime(2026, 7, 15, 10, 30);

    test('课程优先于同时进行的计划块和待办', () {
      final todo = TodoItem(
        id: 'todo-1',
        title: '写方案',
        createdDate: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 12),
      );
      final plan = TodoPlanBlock(
        id: 'plan-1',
        todoId: 'todo-2',
        titleSnapshot: '整理资料',
        startTime: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
      );
      final course = CourseItem(
        uuid: 'course-1',
        courseName: '高等数学',
        teacherName: '教师',
        date: '2026-07-15',
        weekday: 3,
        startTime: 1000,
        endTime: 1140,
        weekIndex: 1,
        roomName: 'A101',
      );

      final result = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: [plan],
        courses: [course],
        now: now,
      );

      expect(result.activity?.kind, OngoingActivityKind.course);
      expect(result.activity?.title, '高等数学');
      expect(result.activity?.subtitle, 'A101');
      expect(result.activity?.detail, '教师');
    });

    test('活动计划块会替代其关联待办，避免重复展示', () {
      final todo = TodoItem(
        id: 'todo-1',
        title: '写方案',
        createdDate: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 12),
      );
      final plan = TodoPlanBlock(
        id: 'plan-1',
        todoId: todo.id,
        startTime: DateTime(2026, 7, 15, 10, 15).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
      );

      final result = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: [plan],
        courses: const [],
        now: now,
      );

      expect(result.activity?.kind, OngoingActivityKind.planBlock);
      expect(result.activity?.title, '写方案');
    });

    test('固定日程作为硬约束优先于同时进行的规划块', () {
      final fixedSchedule = FixedScheduleItem(
        id: 'exam-1',
        title: '高数考试',
        date: '2026-07-15',
        startTime: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 12).millisecondsSinceEpoch,
        location: 'A101',
      );
      final plan = TodoPlanBlock(
        id: 'plan-1',
        todoId: 'todo-1',
        titleSnapshot: '复习',
        startTime: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
      );

      final result = OngoingActivityService.resolve(
        todos: const [],
        planBlocks: [plan],
        courses: const [],
        fixedSchedules: [fixedSchedule],
        now: now,
      );

      expect(result.activity?.kind, OngoingActivityKind.fixedSchedule);
      expect(result.activity?.title, '高数考试');
      expect(result.activity?.subtitle, 'A101');
    });

    test('结束时间待定的固定日程在当天可进入进行中状态', () {
      final fixedSchedule = FixedScheduleItem(
        id: 'open-ended-1',
        title: '公开讲座',
        date: '2026-07-15',
        startTime: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
      );

      final result = OngoingActivityService.resolve(
        todos: const [],
        planBlocks: const [],
        courses: const [],
        fixedSchedules: [fixedSchedule],
        now: now,
      );

      expect(result.activity?.kind, OngoingActivityKind.fixedSchedule);
      expect(result.activity?.detail, '结束时间待定');
      expect(result.nextBoundary, DateTime(2026, 7, 16));
    });

    test('忽略跨日执行时段，并返回下一处时间边界', () {
      final crossDay = TodoItem(
        title: '跨日任务',
        createdDate: DateTime(2026, 7, 14, 22).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 11),
      );
      final future = TodoItem(
        title: '下午会议',
        createdDate: DateTime(2026, 7, 15, 14).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 15),
      );

      final result = OngoingActivityService.resolve(
        todos: [crossDay, future],
        planBlocks: const [],
        courses: const [],
        now: now,
      );

      expect(result.activity, isNull);
      expect(result.nextActivity?.title, '下午会议');
      expect(result.nextActivity?.kind, OngoingActivityKind.todo);
      expect(result.nextBoundary, DateTime(2026, 7, 15, 14));
    });

    test('待办和规划会携带分组及关联目标', () {
      final todo = TodoItem(
        id: 'todo-grouped',
        title: '整理周报',
        groupId: 'group-work',
        createdDate: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 12),
      );
      final group = TodoGroup(id: 'group-work', name: '工作');

      final result = OngoingActivityService.resolve(
        todos: [todo],
        todoGroups: [group],
        planBlocks: const [],
        courses: const [],
        now: now,
      );

      expect(result.nextActivity?.relatedTodoId, todo.id);
      expect(result.nextActivity?.groupName, '工作');
    });

    test('忽略跨日计划块', () {
      final plan = TodoPlanBlock(
        todoId: 'todo-1',
        titleSnapshot: '夜间长任务',
        startTime: DateTime(2026, 7, 14, 23).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
      );

      final result = OngoingActivityService.resolve(
        todos: const [],
        planBlocks: [plan],
        courses: const [],
        now: now,
      );

      expect(result.activity, isNull);
      expect(result.nextBoundary, isNull);
    });

    test('新截止待办不会被当成正在进行，但会成为下一项', () {
      final due = DateTime(2026, 7, 15, 12);
      final todo = TodoItem(
        title: '中午前交材料',
        createdDate: due.millisecondsSinceEpoch,
        dueDate: due,
      );

      final result = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: const [],
        courses: const [],
        now: now,
      );

      expect(result.activity, isNull);
      expect(result.nextActivity?.kind, OngoingActivityKind.todo);
      expect(result.nextActivity?.title, '中午前交材料');
      expect(result.nextActivity?.startMs, due.millisecondsSinceEpoch);
      expect(result.nextActivity?.endMs, due.millisecondsSinceEpoch);
      expect(result.nextBoundary, due);
    });

    test('日期待办使用当天结束时刻参与下一项选择', () {
      final todo = TodoItem(
        title: '提交周报',
        isAllDay: true,
        createdDate: DateTime(2026, 7, 15).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 23, 59),
      );

      final result = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: const [],
        courses: const [],
        now: now,
      );

      expect(result.activity, isNull);
      expect(result.nextActivity?.kind, OngoingActivityKind.todo);
      expect(result.nextActivity?.title, '提交周报');
      expect(
        result.nextActivity?.startMs,
        DateTime(2026, 7, 15, 23, 59).millisecondsSinceEpoch,
      );
    });

    test('下一固定日程会与课程和待办按开始时间统一排序', () {
      final fixedSchedule = FixedScheduleItem(
        id: 'meeting-1',
        title: '项目例会',
        date: '2026-07-15',
        startTime: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 12).millisecondsSinceEpoch,
      );
      final deadline = DateTime(2026, 7, 15, 11, 30);
      final todo = TodoItem(
        title: '发送材料',
        createdDate: deadline.millisecondsSinceEpoch,
        dueDate: deadline,
      );

      final result = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: const [],
        courses: const [],
        fixedSchedules: [fixedSchedule],
        now: now,
      );

      expect(result.activity, isNull);
      expect(result.nextActivity?.kind, OngoingActivityKind.fixedSchedule);
      expect(result.nextActivity?.title, '项目例会');
    });

    test('今日待办汇总只包含当天未完成事项并按时间排序', () {
      final group = TodoGroup(id: 'work', name: '工作');
      final overdue = TodoItem(
        id: 'overdue',
        title: '回复邮件',
        groupId: group.id,
        createdDate: DateTime(2026, 7, 15, 9).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 9),
      );
      final allDay = TodoItem(
        id: 'all-day',
        title: '提交周报',
        isAllDay: true,
        createdDate: DateTime(2026, 7, 15).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 23, 59),
      );
      final done = TodoItem(
        title: '已完成事项',
        isDone: true,
        dueDate: DateTime(2026, 7, 15, 12),
      );
      final tomorrow = TodoItem(
        title: '明日事项',
        dueDate: DateTime(2026, 7, 16, 9),
      );

      final result = OngoingActivityService.resolve(
        todos: [allDay, tomorrow, done, overdue],
        todoGroups: [group],
        planBlocks: const [],
        courses: const [],
        now: now,
      );

      expect(result.nextActivity?.id, 'all-day');
      expect(result.todayTodos.map((todo) => todo.id), ['overdue']);
      expect(result.todayTodos.first.groupName, '工作');
      expect(result.nextBoundary, DateTime(2026, 7, 15, 23, 59));
    });

    test('今日待办汇总会排除下一规划块关联的待办', () {
      final todo = TodoItem(
        id: 'planned-todo',
        title: '整理发布说明',
        dueDate: DateTime(2026, 7, 15, 18),
      );
      final other = TodoItem(
        id: 'other-todo',
        title: '回复消息',
        dueDate: DateTime(2026, 7, 15, 20),
      );
      final plan = TodoPlanBlock(
        id: 'next-plan',
        todoId: todo.id,
        titleSnapshot: todo.title,
        startTime: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 12).millisecondsSinceEpoch,
      );

      final result = OngoingActivityService.resolve(
        todos: [todo, other],
        planBlocks: [plan],
        courses: const [],
        now: now,
      );

      expect(result.nextActivity?.id, plan.id);
      expect(result.todayTodos.map((item) => item.id), ['other-todo']);
    });

    test('开始时刻包含、结束时刻排除', () {
      final todo = TodoItem(
        title: '边界任务',
        createdDate: now.millisecondsSinceEpoch,
        dueDate: now.add(const Duration(hours: 1)),
      );

      final atStart = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: const [],
        courses: const [],
        now: now,
      );
      final atEnd = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: const [],
        courses: const [],
        now: now.add(const Duration(hours: 1)),
      );

      expect(atStart.activity?.title, '边界任务');
      expect(atEnd.activity, isNull);
    });
  });

  group('ReminderScheduleService', () {
    final now = DateTime(2026, 7, 15, 10);
    final limit = now.add(const Duration(days: 7));

    test('提前提醒时间已过但事项未开始时仍可补发', () {
      expect(
        ReminderScheduleService.shouldSchedulePreStart(
          startAt: now.add(const Duration(minutes: 10)),
          triggerAt: now.subtract(const Duration(minutes: 5)),
          now: now,
          limit: limit,
        ),
        isTrue,
      );
    });

    test('事项已经开始后不再补发开始前提醒', () {
      expect(
        ReminderScheduleService.shouldSchedulePreStart(
          startAt: now,
          triggerAt: now.subtract(const Duration(minutes: 15)),
          now: now,
          limit: limit,
        ),
        isFalse,
      );
    });

    test('固定日程的多个提醒会进入统一调度列表', () {
      final start = now.add(const Duration(hours: 2));
      final item = FixedScheduleItem(
        id: 'exam-reminder',
        title: '高数考试',
        date: '2026-07-15',
        startTime: start.millisecondsSinceEpoch,
        endTime: start.add(const Duration(hours: 2)).millisecondsSinceEpoch,
        location: 'A101',
        reminderMinutes: const [60, 15],
      );

      final reminders = ReminderScheduleService.buildFixedScheduleReminders(
        fixedSchedules: [item],
        now: now,
        limit: limit,
      );

      expect(reminders, hasLength(2));
      expect(reminders.map((item) => item['type']).toSet(), {'fixed_schedule'});
      expect(reminders.first['fixedScheduleId'], 'exam-reminder');
      expect(reminders.first['text'], contains('A101'));
    });
  });

  group('MacPomodoroStatusBarService', () {
    final nowMs = DateTime(2026, 7, 15, 10).millisecondsSinceEpoch;

    test('过期倒计时不会继续阻挡远端专注', () {
      final state = PomodoroRunState(
        phase: PomodoroPhase.focusing,
        mode: TimerMode.countdown,
        targetEndMs: nowMs - 1,
      );

      expect(
        MacPomodoroStatusBarService.isUsableLocalState(
          state,
          nowMs: nowMs,
        ),
        isFalse,
      );
    });

    test('暂停状态和正计时仍视为有效本地专注', () {
      final paused = PomodoroRunState(
        phase: PomodoroPhase.focusing,
        mode: TimerMode.countdown,
        targetEndMs: nowMs - 1,
        isPaused: true,
      );
      final countUp = PomodoroRunState(
        phase: PomodoroPhase.focusing,
        mode: TimerMode.countUp,
        targetEndMs: 0,
      );

      expect(
        MacPomodoroStatusBarService.isUsableLocalState(
          paused,
          nowMs: nowMs,
        ),
        isTrue,
      );
      expect(
        MacPomodoroStatusBarService.isUsableLocalState(
          countUp,
          nowMs: nowMs,
        ),
        isTrue,
      );
    });

    test('远端暂停、继续和切换任务会保留完整计时快照', () {
      final initial = MacPomodoroStatusBarService.mergeRemotePayload(
        CrossDevicePomodoroState(
          action: 'SYNC_FOCUS',
          sessionUuid: 'session-1',
          todoTitle: '写方案',
          targetEndMs: nowMs + 25 * 60 * 1000,
          timestamp: nowMs,
          mode: 0,
        ),
        null,
        nowMs: nowMs,
      )!;

      final paused = MacPomodoroStatusBarService.mergeRemotePayload(
        const CrossDevicePomodoroState(
          action: 'PAUSE',
          sessionUuid: 'session-1',
          pausedAtMs: 100,
          accumulatedMs: 20,
          pauseStartMs: 100,
        ),
        initial,
        nowMs: nowMs + 100,
      )!;
      expect(paused['isPaused'], isTrue);
      expect(paused['targetEndMs'], initial['targetEndMs']);
      expect(paused['todoTitle'], '写方案');

      final resumedTarget = nowMs + 30 * 60 * 1000;
      final resumed = MacPomodoroStatusBarService.mergeRemotePayload(
        CrossDevicePomodoroState(
          action: 'RESUME',
          sessionUuid: 'session-1',
          targetEndMs: resumedTarget,
        ),
        paused,
        nowMs: nowMs + 200,
      )!;
      expect(resumed['isPaused'], isFalse);
      expect(resumed['targetEndMs'], resumedTarget);

      final switched = MacPomodoroStatusBarService.mergeRemotePayload(
        CrossDevicePomodoroState(
          action: 'SWITCH',
          sessionUuid: 'session-2',
          todoTitle: '写代码',
          timestamp: nowMs + 300,
        ),
        resumed,
        nowMs: nowMs + 300,
      )!;
      expect(switched['sessionUuid'], 'session-2');
      expect(switched['todoTitle'], '写代码');
      expect(switched['targetEndMs'], resumedTarget);
      expect(switched['sessionStartMs'], nowMs + 300);
    });

    test('旧会话的暂停事件不会覆盖当前远端番茄钟', () {
      final current = <String, dynamic>{
        'sessionUuid': 'session-current',
        'targetEndMs': nowMs + 1000,
      };

      expect(
        MacPomodoroStatusBarService.mergeRemotePayload(
          const CrossDevicePomodoroState(
            action: 'PAUSE',
            sessionUuid: 'session-old',
          ),
          current,
          nowMs: nowMs,
        ),
        isNull,
      );
    });

    test('远端快照会保留设备、轮次、标签和关联规划', () {
      final payload = MacPomodoroStatusBarService.mergeRemotePayload(
        CrossDevicePomodoroState(
          action: 'START',
          sourceDevice: 'flutter_device-123456',
          sourceDeviceName: 'iPhone 17 (Phone)',
          planBlockId: 'plan-1',
          currentCycle: 2,
          totalCycles: 4,
          plannedFocusSeconds: 1500,
          tags: const ['学习', '深度工作'],
          note: '完成第一版',
        ),
        null,
        nowMs: nowMs,
      )!;

      expect(payload['sourceDeviceName'], 'iPhone 17 (Phone)');
      expect(payload['currentCycle'], 2);
      expect(payload['totalCycles'], 4);
      expect(payload['tagNames'], ['学习', '深度工作']);
      expect(payload['planBlockId'], 'plan-1');
      expect(payload['note'], '完成第一版');
    });

    test('详情概览会汇总今日专注并选择最近倒数日', () {
      final now = DateTime(2026, 7, 15, 10);
      final payload = MacPomodoroStatusBarService.buildIslandOverviewPayload(
        countdowns: [
          CountdownItem(
            title: '已完成纪念日',
            targetDate: DateTime(2026, 7, 16),
            isCompleted: true,
          ),
          CountdownItem(
            id: 'countdown-nearest',
            title: '项目发布',
            targetDate: DateTime(2026, 7, 17),
          ),
          CountdownItem(
            title: '暑假',
            targetDate: DateTime(2026, 7, 20),
          ),
        ],
        todayRecords: [
          PomodoroRecord(
            uuid: 'record-1',
            startTime: DateTime(2026, 7, 15, 8).millisecondsSinceEpoch,
            plannedDuration: 600,
            actualDuration: 600,
          ),
          PomodoroRecord(
            uuid: 'record-2',
            startTime: DateTime(2026, 7, 15, 9).millisecondsSinceEpoch,
            plannedDuration: 1200,
            actualDuration: 1200,
          ),
        ],
        localState: PomodoroRunState(
          phase: PomodoroPhase.focusing,
          sessionUuid: 'running-session',
          sessionStartMs: DateTime(2026, 7, 15, 9, 45).millisecondsSinceEpoch,
        ),
        now: now,
      );

      expect(payload['todayFocusBaseSeconds'], 1800);
      expect(payload['todayFocusBaseCount'], 2);
      expect(payload['includeCurrentFocus'], isTrue);
      expect(payload['countdownId'], 'countdown-nearest');
      expect(payload['countdownTitle'], '项目发布');
      expect(payload['countdownDays'], 2);
    });
  });

  group('PomodoroSyncService', () {
    test('WebSocket JSON 会解析灵动岛所需的专注详情', () {
      final state = CrossDevicePomodoroState.fromJson({
        'action': 'START',
        'source_device': 'flutter_mac-1',
        'source_device_name': 'MacBook Pro',
        'plan_block_id': 'plan-1',
        'current_cycle': 2,
        'total_cycles': 4,
        'planned_focus_seconds': 1500,
        'tags': ['学习'],
      });

      expect(state.sourceDevice, 'flutter_mac-1');
      expect(state.sourceDeviceName, 'MacBook Pro');
      expect(state.planBlockId, 'plan-1');
      expect(state.currentCycle, 2);
      expect(state.totalCycles, 4);
      expect(state.plannedFocusSeconds, 1500);
      expect(state.tags, ['学习']);
    });

    test('设备 ID 比较兼容 flutter_ 前缀', () {
      expect(
        PomodoroSyncService.deviceIdsMatch('flutter_mac-1', 'mac-1'),
        isTrue,
      );
      expect(
        PomodoroSyncService.deviceIdsMatch('mac-1', 'flutter_mac-1'),
        isTrue,
      );
      expect(
        PomodoroSyncService.deviceIdsMatch('flutter_mac-1', 'flutter_phone-1'),
        isFalse,
      );
    });
  });
}
