import 'package:countdown_todo/features/habits/models/habit_checkin.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/models/habit_goal_rule.dart';
import 'package:countdown_todo/features/habits/repositories/habit_repository.dart';
import 'package:countdown_todo/features/habits/services/habit_rule_resolver.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HabitRepository.reminderStartFor（18.1 完成型固定提醒映射）', () {
    test('把一天内分钟数映射为当天本地时刻', () {
      final start = HabitRepository.reminderStartFor(
        DateTime(2026, 8, 5),
        22 * 60,
      );
      expect(start, DateTime(2026, 8, 5, 22, 0));
    });

    test('跨午夜边界（04:30）映射正确', () {
      final start = HabitRepository.reminderStartFor(
        DateTime(2026, 8, 5),
        4 * 60 + 30,
      );
      expect(start, DateTime(2026, 8, 5, 4, 30));
    });

    test('越界分钟数被钳制在 0..1439', () {
      final under = HabitRepository.reminderStartFor(DateTime(2026, 8, 5), -10);
      expect(under, DateTime(2026, 8, 5, 0, 0));
      final over = HabitRepository.reminderStartFor(DateTime(2026, 8, 5), 1500);
      expect(over, DateTime(2026, 8, 5, 23, 59));
    });
  });

  group('完成型习惯与待办解耦及迁移', () {
    late PlanAvailabilityFixture fixture;

    setUp(() async {
      fixture = PlanAvailabilityFixture();
      await fixture.initialize();
    });

    tearDown(() => fixture.dispose());

    test('新建完成型习惯不会在待办中生成循环待办，且 sourceIds 为空', () async {
      final initialTodos = await StorageService.getTodos(
        PlanAvailabilityFixture.username,
        includeDeleted: true,
      );
      final initialTodoCount = initialTodos.length;

      final rule = HabitGoalRuleRevision(
        habitUuid: 'habit-pushup',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
      );
      final goal = await HabitRepository.createGoal(
        name: '每天俯卧撑',
        icon: '💪',
        sourceType: HabitSourceType.recurringTodo,
        sourceIds: const [],
        rule: rule,
        username: PlanAvailabilityFixture.username,
      );

      expect(goal.sourceType, HabitSourceType.recurringTodo);
      expect(goal.sourceIds, isEmpty);
      expect(goal.displayMode, HabitDisplayMode.habitOnly);

      final todosAfter = await StorageService.getTodos(
        PlanAvailabilityFixture.username,
        includeDeleted: true,
      );
      expect(todosAfter.length, initialTodoCount);
    });

    test('完成型习惯通过 toggleCompletion 和 setCompletion 管理打卡记录', () async {
      final rule = HabitGoalRuleRevision(
        habitUuid: 'habit-pushup-2',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
      );
      final goal = await HabitRepository.createGoal(
        name: '每天俯卧撑',
        sourceType: HabitSourceType.recurringTodo,
        rule: rule,
        username: PlanAvailabilityFixture.username,
      );

      final today = DateTime(2026, 10, 8);
      final dayKey = HabitRuleResolver.dayKey(today);

      // 1. 打卡完成
      final success = await HabitRepository.toggleCompletion(
        goal: goal,
        logicalDate: today,
        username: PlanAvailabilityFixture.username,
      );
      expect(success, isTrue);

      var checkIns = await HabitRepository.getCheckIns(
        habitUuid: goal.uuid,
        fromDate: dayKey,
        toDate: dayKey,
      );
      var activeCheckIns = checkIns.where((c) => !c.isDeleted).toList();
      expect(activeCheckIns, hasLength(1));
      expect(activeCheckIns.first.value, 1.0);
      expect(activeCheckIns.first.source, HabitCheckInSource.manual);

      // 2. 再次切换打卡（取消完成）
      await HabitRepository.toggleCompletion(
        goal: goal,
        logicalDate: today,
        username: PlanAvailabilityFixture.username,
      );

      checkIns = await HabitRepository.getCheckIns(
        habitUuid: goal.uuid,
        fromDate: dayKey,
        toDate: dayKey,
      );
      activeCheckIns = checkIns.where((c) => !c.isDeleted).toList();
      expect(activeCheckIns, isEmpty);

      // 3. setCompletion 设为已完成
      await HabitRepository.setCompletion(
        goal: goal,
        logicalDate: today,
        done: true,
        username: PlanAvailabilityFixture.username,
      );
      checkIns = await HabitRepository.getCheckIns(
        habitUuid: goal.uuid,
        fromDate: dayKey,
        toDate: dayKey,
      );
      activeCheckIns = checkIns.where((c) => !c.isDeleted).toList();
      expect(activeCheckIns, hasLength(1));
    });

    test('从循环待办系列转为习惯：导入历史完成和跳过记录，原循环待办移入回收站', () async {
      final seriesId = 'series-desk-cleanup';
      final todo1 = TodoItem(
        id: 'todo-desk-1',
        title: '整理桌面',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        createdDate: DateTime(2026, 10, 5, 9).millisecondsSinceEpoch,
        isDone: true,
      );
      final todo2 = TodoItem(
        id: 'todo-desk-2',
        title: '整理桌面',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        createdDate: DateTime(2026, 10, 6, 9).millisecondsSinceEpoch,
        isSkipped: true,
      );
      final todo3 = TodoItem(
        id: 'todo-desk-3',
        title: '整理桌面',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: seriesId,
        createdDate: DateTime(2026, 10, 7, 9).millisecondsSinceEpoch,
        isDone: false,
      );

      await StorageService.saveTodos(PlanAvailabilityFixture.username, [
        todo1,
        todo2,
        todo3,
      ]);

      final goal = await HabitRepository.createGoalFromSeries(
        todo: todo1,
        username: PlanAvailabilityFixture.username,
      );

      expect(goal, isNotNull);
      expect(goal!.name, '整理桌面');
      expect(goal.sourceType, HabitSourceType.recurringTodo);
      expect(goal.sourceIds, isEmpty);

      // 验证历史记录已导入 HabitCheckIn
      final checkIns = await HabitRepository.getCheckIns(habitUuid: goal.uuid);
      final activeCheckIns = checkIns.where((c) => !c.isDeleted).toList();
      expect(activeCheckIns, hasLength(2));

      final doneCheckIn = activeCheckIns.firstWhere(
        (c) => c.logicalDate == '2026-10-05',
      );
      expect(doneCheckIn.value, 1.0);
      expect(doneCheckIn.source, HabitCheckInSource.manual);

      final skipCheckIn = activeCheckIns.firstWhere(
        (c) => c.logicalDate == '2026-10-06',
      );
      expect(skipCheckIn.source, HabitCheckInSource.skip);

      // 验证原待办系列已移入回收站（isDeleted == true）
      final activeTodos = await StorageService.getTodos(
        PlanAvailabilityFixture.username,
        includeDeleted: false,
      );
      expect(
        activeTodos.where((t) => t.recurrenceSeriesId == seriesId),
        isEmpty,
      );

      final allTodos = await StorageService.getTodos(
        PlanAvailabilityFixture.username,
        includeDeleted: true,
      );
      final seriesDeletedTodos = allTodos
          .where((t) => t.recurrenceSeriesId == seriesId)
          .toList();
      expect(seriesDeletedTodos, hasLength(3));
      expect(seriesDeletedTodos.every((t) => t.isDeleted), isTrue);
    });

    test('自动迁移旧版绑定了循环待办系列的完成型习惯', () async {
      final legacySeriesId = 'legacy-series-read';
      final todoOld1 = TodoItem(
        id: 'legacy-todo-1',
        title: '每日读书',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: legacySeriesId,
        createdDate: DateTime(2026, 10, 1, 9).millisecondsSinceEpoch,
        isDone: true,
      );
      final todoOld2 = TodoItem(
        id: 'legacy-todo-2',
        title: '每日读书',
        recurrence: RecurrenceType.daily,
        recurrenceSeriesId: legacySeriesId,
        createdDate: DateTime(2026, 10, 2, 9).millisecondsSinceEpoch,
        isDone: false,
      );
      await StorageService.saveTodos(PlanAvailabilityFixture.username, [
        todoOld1,
        todoOld2,
      ]);

      // 直接向习惯表插入一条带有 sourceIds 的旧版习惯记录
      final legacyGoal = HabitGoal(
        uuid: 'legacy-goal-read',
        name: '每日读书',
        sourceType: HabitSourceType.recurringTodo,
        sourceIds: [legacySeriesId],
        displayMode: HabitDisplayMode.habitOnly,
      );
      final legacyRule = HabitGoalRuleRevision(
        uuid: 'legacy-rule-read',
        habitUuid: legacyGoal.uuid,
        effectiveFromDate: '2026-10-01',
        periodType: HabitPeriodType.daily,
        targetValue: 1,
      );
      await fixture.db.insert('habit_goals', legacyGoal.toJson());
      await fixture.db.insert('habit_goal_rule_revisions', legacyRule.toJson());

      // 执行迁移
      await HabitRepository.migrateLegacyRecurringTodoHabits(
        username: PlanAvailabilityFixture.username,
      );

      final migratedGoals = await HabitRepository.getGoals();
      final migratedGoal = migratedGoals.firstWhere(
        (g) => g.uuid == legacyGoal.uuid,
      );
      expect(migratedGoal.sourceIds, isEmpty);

      // 验证历史记录已导入
      final checkIns = await HabitRepository.getCheckIns(
        habitUuid: legacyGoal.uuid,
      );
      final activeCheckIns = checkIns.where((c) => !c.isDeleted).toList();
      expect(activeCheckIns, hasLength(1));
      expect(activeCheckIns.first.logicalDate, '2026-10-01');
      expect(activeCheckIns.first.value, 1.0);

      // 验证原待办已软删除
      final activeTodos = await StorageService.getTodos(
        PlanAvailabilityFixture.username,
        includeDeleted: false,
      );
      expect(
        activeTodos.where((t) => t.recurrenceSeriesId == legacySeriesId),
        isEmpty,
      );
    });
  });
}
