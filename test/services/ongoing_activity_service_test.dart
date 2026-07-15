import 'package:CountDownTodo/models.dart';
import 'package:CountDownTodo/services/macos_pomodoro_status_bar_service_io.dart';
import 'package:CountDownTodo/services/ongoing_activity_service.dart';
import 'package:CountDownTodo/services/pomodoro_service.dart';
import 'package:CountDownTodo/services/pomodoro_sync_service.dart';
import 'package:CountDownTodo/services/reminder_schedule_service.dart';
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

    test('忽略全天和跨日待办，并返回下一处时间边界', () {
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
      expect(result.nextBoundary, DateTime(2026, 7, 15, 14));
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
  });

  group('PomodoroSyncService', () {
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
