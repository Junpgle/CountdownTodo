import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/todo_overdue_triage_service.dart';
import 'package:countdown_todo/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('TodoOverdueTriageService', () {
    final fixedNow = DateTime(2026, 10, 9, 14, 30);
    late TodoOverdueTriageService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'current_login_user': 'user_test',
      });
      service = TodoOverdueTriageService(clock: () => fixedNow);
    });

    test('filterOverdueTodos filters only active overdue items', () {
      final todos = [
        TodoItem(
          id: '1',
          title: '逾期任务1',
          dueDate: DateTime(2026, 10, 8, 10, 0),
        ),
        TodoItem(
          id: '2',
          title: '已完成逾期任务',
          dueDate: DateTime(2026, 10, 8, 10, 0),
          isDone: true,
        ),
        TodoItem(
          id: '3',
          title: '已删除逾期任务',
          dueDate: DateTime(2026, 10, 8, 10, 0),
          isDeleted: true,
        ),
        TodoItem(
          id: '3-skipped',
          title: '已跳过逾期任务',
          dueDate: DateTime(2026, 10, 8, 10, 0),
          recurrenceSeriesId: 'series-skip',
          isSkipped: true,
        ),
        TodoItem(id: '4', title: '未来任务', dueDate: DateTime(2026, 10, 9, 18, 0)),
        TodoItem(id: '5', title: '无截止时间任务'),
        TodoItem(
          id: '6',
          title: '排除的重复系列',
          dueDate: DateTime(2026, 10, 8, 10, 0),
          recurrenceSeriesId: 'series_1',
        ),
      ];

      final overdue = service.filterOverdueTodos(
        todos: todos,
        excludedRecurrenceSeriesIds: {'series_1'},
      );

      expect(overdue.length, 1);
      expect(overdue.first.id, '1');
      expect(overdue.first.title, '逾期任务1');
    });

    test('date-only tasks are not overdue before their day has ended', () {
      final lateEveningService = TodoOverdueTriageService(
        clock: () => DateTime(2026, 10, 9, 23, 59, 59, 500),
      );
      final overdue = lateEveningService.filterOverdueTodos(
        todos: [
          TodoItem(
            id: 'today',
            title: '今天内完成',
            dueDate: DateTime(2026, 10, 9, 23, 59),
            isAllDay: true,
          ),
          TodoItem(
            id: 'yesterday',
            title: '昨天内完成',
            dueDate: DateTime(2026, 10, 8, 23, 59),
            isAllDay: true,
          ),
        ],
      );

      expect(overdue.map((todo) => todo.id), ['yesterday']);
    });

    test('tomorrow rescheduling follows calendar days across DST', () {
      final beforeSpringForward = TodoOverdueTriageService(
        clock: () => DateTime(2026, 3, 7, 23, 30),
      );
      final dateOnly = TodoItem(
        id: 'date-only',
        title: '日期待办',
        dueDate: DateTime(2026, 3, 6, 23, 59),
        isAllDay: true,
      );
      final timed = TodoItem(
        id: 'timed',
        title: '限时待办',
        dueDate: DateTime(2026, 3, 6, 18),
      );

      expect(
        beforeSpringForward
            .computeRescheduledDueDate(
              dateOnly,
              target: OverdueRescheduleTarget.tomorrow,
            )
            .dueDate,
        DateTime(2026, 3, 8, 23, 59),
      );
      expect(
        beforeSpringForward
            .computeRescheduledDueDate(
              timed,
              target: OverdueRescheduleTarget.tomorrow,
            )
            .dueDate,
        DateTime(2026, 3, 8, 18),
      );
    });

    test('computeRescheduledDueDate handles today with past hour fallback', () {
      // 原时间是上午 9:00，当前是下午 14:30，今天 9:00 已过，应回退至 23:59
      final pastHourTodo = TodoItem(
        id: '1',
        title: '早起背单词',
        dueDate: DateTime(2026, 10, 8, 9, 0),
      );

      final res1 = service.computeRescheduledDueDate(
        pastHourTodo,
        target: OverdueRescheduleTarget.today,
      );

      expect(res1.dueDate, DateTime(2026, 10, 9, 23, 59));
      expect(res1.isDateOnly, isFalse);

      // 原时间是晚上 20:00，当前是下午 14:30，今天 20:00 仍未到，保留 20:00
      final futureHourTodo = TodoItem(
        id: '2',
        title: '晚上开会',
        dueDate: DateTime(2026, 10, 8, 20, 0),
      );

      final res2 = service.computeRescheduledDueDate(
        futureHourTodo,
        target: OverdueRescheduleTarget.today,
      );

      expect(res2.dueDate, DateTime(2026, 10, 9, 20, 0));
      expect(res2.isDateOnly, isFalse);
    });

    test('computeRescheduledDueDate handles dateOnly items', () {
      final dateOnlyTodo = TodoItem(
        id: '1',
        title: '提交报告',
        dueDate: DateTime(2026, 10, 8, 23, 59),
        isAllDay: true,
      );

      final resToday = service.computeRescheduledDueDate(
        dateOnlyTodo,
        target: OverdueRescheduleTarget.today,
      );
      expect(resToday.isDateOnly, isTrue);
      expect(resToday.dueDate, DateTime(2026, 10, 9, 23, 59));

      final resTomorrow = service.computeRescheduledDueDate(
        dateOnlyTodo,
        target: OverdueRescheduleTarget.tomorrow,
      );
      expect(resTomorrow.isDateOnly, isTrue);
      expect(resTomorrow.dueDate, DateTime(2026, 10, 10, 23, 59));
    });

    test('computeRescheduledDueDate handles tomorrow and clear targets', () {
      final todo = TodoItem(
        id: '1',
        title: '写需求文档',
        dueDate: DateTime(2026, 10, 7, 16, 45),
      );

      final resTomorrow = service.computeRescheduledDueDate(
        todo,
        target: OverdueRescheduleTarget.tomorrow,
      );
      expect(resTomorrow.dueDate, DateTime(2026, 10, 10, 16, 45));
      expect(resTomorrow.isDateOnly, isFalse);

      final resClear = service.computeRescheduledDueDate(
        todo,
        target: OverdueRescheduleTarget.clear,
      );
      expect(resClear.dueDate, isNull);
      expect(resClear.isDateOnly, isFalse);
    });

    test(
      'applyBatchReschedule updates items and persists to storage',
      () async {
        final todo1 = TodoItem(
          id: 't1',
          title: '待办1',
          createdDate: DateTime(2026, 10, 8, 9).millisecondsSinceEpoch,
          dueDate: DateTime(2026, 10, 8, 10, 0),
        );
        final todo2 = TodoItem(
          id: 't2',
          title: '待办2',
          createdDate: DateTime(2026, 10, 8, 10).millisecondsSinceEpoch,
          dueDate: DateTime(2026, 10, 8, 11, 0),
        );
        final normalTodo = TodoItem(
          id: 't3',
          title: '正常待办',
          createdDate: DateTime(2026, 10, 15, 11).millisecondsSinceEpoch,
          dueDate: DateTime(2026, 10, 15, 12, 0),
        );

        final allTodos = [todo1, todo2, normalTodo];
        await StorageService.saveTodos('user_test', allTodos);

        final result = await service.applyBatchReschedule(
          username: 'user_test',
          todosToReschedule: [todo1, todo2],
          target: OverdueRescheduleTarget.tomorrow,
          allTodos: allTodos,
        );

        expect(result.modifiedCount, 2);
        expect(result.target, OverdueRescheduleTarget.tomorrow);

        final updated1 = result.updatedTodos.firstWhere((t) => t.id == 't1');
        expect(updated1.dueDate, DateTime(2026, 10, 10, 10, 0));
        expect(updated1.version, greaterThan(1));

        final updated3 = result.updatedTodos.firstWhere((t) => t.id == 't3');
        expect(updated3.dueDate, DateTime(2026, 10, 15, 12, 0));
      },
    );

    test(
      'schedulePlanBlock creates plan block and adjusts todo due date',
      () async {
        final todo = TodoItem(
          id: 't_plan',
          title: '待办准备排期',
          createdDate: DateTime(2026, 10, 8, 9).millisecondsSinceEpoch,
          dueDate: DateTime(2026, 10, 8, 10, 0),
        );
        final allTodos = [todo];
        await StorageService.saveTodos('user_test', allTodos);

        final slot = PlanTimeSlot(
          DateTime(2026, 10, 9, 16, 0),
          DateTime(2026, 10, 9, 16, 45),
        );

        final block = await service.schedulePlanBlock(
          username: 'user_test',
          todo: todo,
          slot: slot,
          allTodos: allTodos,
        );

        expect(block.todoId, 't_plan');
        expect(block.titleSnapshot, '待办准备排期');
        expect(block.startTime, slot.start.millisecondsSinceEpoch);
        expect(block.endTime, slot.end.millisecondsSinceEpoch);
        expect(block.plannedMinutes, 45);
        expect(block.status, TodoPlanStatus.planned);

        // 验证待办由于安排了 16:45 结束的规划，其截止时间对齐至 16:45，不再逾期
        expect(todo.dueDate, slot.end);
        expect(todo.isDateOnly, isFalse);
      },
    );

    test(
      'schedule conflict refresh includes the last hour on DST fallback day',
      () async {
        final prefs = await StorageService.prefs;
        await prefs.setString('current_login_user', 'dst_conflict_test');
        await prefs.setBool('conflict_detection_enabled', true);
        expect(await StorageService.getConflictDetectionEnabled(), isTrue);

        final runId = DateTime.now().microsecondsSinceEpoch;
        final firstId = 'dst-conflict-first-$runId';
        final secondId = 'dst-conflict-second-$runId';
        final first = TodoItem(
          id: firstId,
          title: '夏令时晚间安排一',
          createdDate: DateTime(2026, 11, 1, 23, 15).millisecondsSinceEpoch,
          dueDate: DateTime(2026, 11, 1, 23, 45),
        );
        final second = TodoItem(
          id: secondId,
          title: '夏令时晚间安排二',
          createdDate: DateTime(2026, 11, 1, 23, 30).millisecondsSinceEpoch,
          dueDate: DateTime(2026, 11, 1, 23, 55),
        );

        await StorageService.saveTodos('dst_conflict_test', [
          first,
        ], sync: false);
        await StorageService.saveTodos('dst_conflict_test', [
          second,
        ], sync: false);

        final saved = await StorageService.getTodos(
          'dst_conflict_test',
          includeDeleted: true,
        );
        final conflictTodos = saved
            .where((todo) => todo.id == firstId || todo.id == secondId)
            .toList();
        expect(conflictTodos, hasLength(2));
        expect(
          conflictTodos.every((todo) => todo.hasConflict),
          isTrue,
          reason: conflictTodos
              .map(
                (todo) =>
                    '${todo.id}: start=${todo.effectiveStartTime} '
                    'due=${todo.dueDate} dateOnly=${todo.isDateOnly} '
                    'conflict=${todo.hasConflict}',
              )
              .join('\n'),
        );

        final db = await DatabaseHelper.instance.databaseForUser(
          'dst_conflict_test',
        );
        final pendingLogs = await db.query(
          'op_logs',
          where: 'target_uuid IN (?, ?)',
          whereArgs: [firstId, secondId],
        );
        expect(pendingLogs, hasLength(2));
        expect(
          pendingLogs.every((log) {
            final payload = jsonDecode(log['data_json']! as String) as Map;
            return payload['has_conflict'] == 0 &&
                payload['conflict_data'] == null;
          }),
          isTrue,
          reason: '本地冲突标记不能改写待同步的用户操作',
        );
      },
    );
  });
}
