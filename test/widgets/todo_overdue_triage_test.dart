import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/todo_overdue_triage_service.dart';
import 'package:countdown_todo/widgets/todo_overdue_triage_banner.dart';
import 'package:countdown_todo/widgets/todo_overdue_triage_sheet.dart';

class _FakeOverdueTriageService extends TodoOverdueTriageService {
  final List<PlanTimeSlot> mockSlots;

  _FakeOverdueTriageService({super.clock, this.mockSlots = const []});

  @override
  Future<List<PlanTimeSlot>> findSmartSlots({
    required String username,
    required TodoItem todo,
    int minutes = 45,
  }) async {
    return mockSlots;
  }

  @override
  Future<TodoPlanBlock> schedulePlanBlock({
    required String username,
    required TodoItem todo,
    required PlanTimeSlot slot,
    required List<TodoItem> allTodos,
  }) async {
    return TodoPlanBlock(
      todoId: todo.id,
      titleSnapshot: todo.title,
      startTime: slot.start.millisecondsSinceEpoch,
      endTime: slot.end.millisecondsSinceEpoch,
      plannedMinutes: slot.minutes,
    );
  }

  @override
  Future<OverdueTriageResult> applyBatchReschedule({
    required String username,
    required List<TodoItem> todosToReschedule,
    required OverdueRescheduleTarget target,
    required List<TodoItem> allTodos,
  }) async {
    return OverdueTriageResult(
      modifiedCount: todosToReschedule.length,
      target: target,
      updatedTodos: allTodos,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('TodoOverdueTriageBanner', () {
    testWidgets('renders nothing when count is 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoOverdueTriageBanner(
              count: 0,
              isLight: true,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsNothing);
      expect(find.textContaining('项待办已逾期'), findsNothing);
    });

    testWidgets('renders banner and triggers onTap when count > 0', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoOverdueTriageBanner(
              count: 4,
              isLight: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('发现 4 项待办已逾期'), findsOneWidget);
      expect(find.text('快速整理'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });
  });

  group('TodoOverdueTriageSheet', () {
    final fixedNow = DateTime(2026, 10, 9, 14, 0);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('displays items, supports select all and batch action', (
      tester,
    ) async {
      final overdueTodos = [
        TodoItem(
          id: '1',
          title: '复习概率论',
          dueDate: DateTime(2026, 10, 8, 18, 0),
        ),
        TodoItem(id: '2', title: '实验报告', dueDate: DateTime(2026, 10, 7, 20, 0)),
      ];

      var todosChangedCalled = false;
      var refreshRequested = false;

      final service = _FakeOverdueTriageService(clock: () => fixedNow);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoOverdueTriageSheet(
              username: 'test_user',
              initialOverdueTodos: overdueTodos,
              allTodos: overdueTodos,
              onTodosChanged: (_) => todosChangedCalled = true,
              onRefreshRequested: () => refreshRequested = true,
              service: service,
            ),
          ),
        ),
      );

      expect(find.text('逾期待办整理'), findsOneWidget);
      expect(find.text('复习概率论'), findsOneWidget);
      expect(find.text('实验报告'), findsOneWidget);
      expect(find.text('已选 2 / 2 项'), findsOneWidget);

      // 取消全选测试
      await tester.tap(find.text('取消全选'));
      await tester.pump();
      expect(find.text('已选 0 / 2 项'), findsOneWidget);

      // 单选第一项
      await tester.tap(find.text('复习概率论'));
      await tester.pump();
      expect(find.text('已选 1 / 2 项'), findsOneWidget);

      // 点击顺延至今日
      await tester.tap(find.text('顺延至今日'));
      await tester.pumpAndSettle();

      expect(todosChangedCalled, isTrue);
      expect(refreshRequested, isTrue);
    });

    testWidgets('supports smart slot finding and inline scheduling', (
      tester,
    ) async {
      final overdueTodos = [
        TodoItem(
          id: '1',
          title: '复习概率论',
          dueDate: DateTime(2026, 10, 8, 18, 0),
        ),
      ];

      final mockSlots = [
        PlanTimeSlot(
          DateTime(2026, 10, 9, 16, 0),
          DateTime(2026, 10, 9, 16, 45),
        ),
      ];

      final service = _FakeOverdueTriageService(
        clock: () => fixedNow,
        mockSlots: mockSlots,
      );

      var todosChangedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoOverdueTriageSheet(
              username: 'test_user',
              initialOverdueTodos: overdueTodos,
              allTodos: overdueTodos,
              onTodosChanged: (_) => todosChangedCalled = true,
              onRefreshRequested: () {},
              service: service,
            ),
          ),
        ),
      );

      // 点击“智能排期”
      await tester.tap(find.text('智能排期'));
      await tester.pumpAndSettle();

      // 应查出可用时段 Chip
      expect(find.byType(ActionChip), findsOneWidget);
      expect(find.textContaining('16:00–16:45'), findsOneWidget);

      // 点击时段 Chip 执行一键规划
      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();

      expect(todosChangedCalled, isTrue);
    });

    testWidgets('showTodoOverdueTriageSheet opens compact dialog and closes', (
      tester,
    ) async {
      final overdueTodos = [
        TodoItem(
          id: '1',
          title: '复习概率论',
          dueDate: DateTime(2026, 10, 8, 18, 0),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showTodoOverdueTriageSheet(
                  context: context,
                  username: 'test_user',
                  overdueTodos: overdueTodos,
                  allTodos: overdueTodos,
                  onTodosChanged: (_) {},
                  onRefreshRequested: () {},
                ),
                child: const Text('打开整理'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开整理'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('逾期待办整理'), findsOneWidget);
      expect(find.text('复习概率论'), findsOneWidget);

      // 点击右上角关闭按钮
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });
  });
}
