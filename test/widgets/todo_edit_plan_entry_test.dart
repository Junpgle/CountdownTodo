import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/widgets/plan_availability_panel.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:countdown_todo/widgets/todo_section_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  late PlanAvailabilityFixture fixture;
  setUp(() async {
    await initializeDateFormatting();
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    await LiquidGlassEffectService.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_coach_edit_todo', true);
  });
  tearDown(() async => fixture.dispose());

  for (final done in [false, true]) {
    testWidgets('首页编辑待办进入规划入口：完成状态=$done', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final todo = TodoItem(id: 'todo-target', title: '复习高数', isDone: done);
      var todoWrites = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: TodoEditScreen(
            todo: todo,
            todos: [todo],
            todoGroups: const [],
            username: PlanAvailabilityFixture.username,
            onTodosChanged: (_) {
              todoWrites++;
            },
            onGroupsChanged: (_) {},
          ),
        ),
      );
      await settle(tester);
      final entry = find.byKey(const ValueKey('todo-create-plan-block'));
      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextButton>(entry).onPressed,
        done ? isNull : isNotNull,
      );
      if (!done) {
        final prediction = await tester.runAsync(
          () =>
              TimeEstimationService.estimate(todo.title, groupId: todo.groupId),
        );
        await tester.tap(entry);
        await settle(tester);
        final editor = tester.widget<PlanBlockEditorSheet>(
          find.byType(PlanBlockEditorSheet),
        );
        expect(editor.initialTodoId, todo.id);
        expect(editor.todos.single.id, todo.id);
        expect(editor.autoRecommendTime, isTrue);
        expect(editor.fullPage, isTrue);
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          ModalRoute.of(tester.element(find.byType(PlanBlockEditorSheet))),
          isA<PageRoute<void>>(),
        );
        expect(editor.autoFillEstimateOnTodoChange, isFalse);
        final panel = tester.widget<PlanAvailabilityPanel>(
          find.byType(PlanAvailabilityPanel),
        );
        expect(panel.resultsOnly, isTrue);
        expect(
          find.byKey(const ValueKey('plan-custom-duration')),
          findsNothing,
        );
        expect(panel.initialMinutes, prediction!.estimatedMinutes);
        expect(panel.estimatedMinutes, prediction.estimatedMinutes);
        Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
        await settle(tester);
      }
      expect(todoWrites, 0);
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        isEmpty,
      );
      expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
