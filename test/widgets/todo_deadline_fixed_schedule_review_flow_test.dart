import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/todo_editor_save_result.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/todo_section_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 250));
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

  testWidgets('期限改到考试开始后先复核；取消保留输入，确认才提交快照', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final todo = TodoItem(
      id: 'deadline-review-flow',
      title: '打印准考证',
      createdAt: DateTime(2026, 10, 24, 8).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 10, 26, 18),
    );
    final schedule = FixedScheduleItem(
      id: 'deadline-review-exam',
      title: '线性代数考试',
      date: '2026-10-27',
      startTime: DateTime(2026, 10, 27, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 27, 11).millisecondsSinceEpoch,
      relatedTodoIds: [todo.id],
    );
    await fixture.db.insert('fixed_schedules', schedule.toJson());

    var writes = 0;
    Set<String>? guardedTodoIds;
    List<FixedScheduleItem>? guardedSchedules;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: const ValueKey('open-deadline-editor'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TodoEditScreen(
                    todo: todo,
                    todos: [todo],
                    todoGroups: const [],
                    username: PlanAvailabilityFixture.username,
                    clock: () => DateTime(2026, 10, 24),
                    onTodosChanged: (_) {},
                    onGroupsChanged: (_) {},
                    onEditorSave:
                        (
                          _,
                          _, {
                          expectedSeriesMembership,
                          expectedFixedScheduleTodoIds,
                          expectedFixedScheduleBaselines,
                        }) async {
                          writes++;
                          guardedTodoIds = expectedFixedScheduleTodoIds;
                          guardedSchedules = expectedFixedScheduleBaselines;
                          return const TodoEditorSaveResult();
                        },
                  ),
                ),
              ),
              child: const Text('编辑待办'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑待办'));
    await _settle(tester);

    final dueTile = find.textContaining('10-26 18:00 前完成');
    await tester.ensureVisible(dueTile);
    await tester.tap(dueTile);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('27').last);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK').last);
    await _settle(tester);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('关联固定日程复核'), findsOneWidget);
    expect(find.text('线性代数考试'), findsOneWidget);
    expect(writes, 0);
    await tester.tap(find.text('返回修改'));
    await _settle(tester);
    expect(find.byType(TodoEditScreen), findsOneWidget);
    expect(find.textContaining('10-27 18:00 前完成'), findsOneWidget);
    expect(todo.dueDate, DateTime(2026, 10, 26, 18));
    expect(writes, 0);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('关联固定日程复核'), findsOneWidget);
    await tester.tap(find.text('确认保存'));
    await _settle(tester);

    expect(find.byType(TodoEditScreen), findsNothing);
    expect(writes, 1);
    expect(guardedTodoIds, {todo.id});
    expect(guardedSchedules?.map((item) => item.id), [schedule.id]);
    expect(todo.dueDate, DateTime(2026, 10, 26, 18));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('没有期限变化时编辑标题不会读取或展示关联期限复核', (tester) async {
    final todo = TodoItem(id: 'title-only-review', title: '准备材料');
    final schedule = FixedScheduleItem(
      id: 'title-only-event',
      title: '关联考试',
      date: '2026-10-27',
      startTime: DateTime(2026, 10, 27, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 27, 10).millisecondsSinceEpoch,
      relatedTodoIds: [todo.id],
    );
    await fixture.db.insert('fixed_schedules', schedule.toJson());
    var writes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoEditScreen(
            todo: todo,
            todos: [todo],
            todoGroups: const [],
            username: PlanAvailabilityFixture.username,
            onTodosChanged: (_) {},
            onGroupsChanged: (_) {},
            onEditorSave:
                (
                  _,
                  _, {
                  expectedSeriesMembership,
                  expectedFixedScheduleTodoIds,
                  expectedFixedScheduleBaselines,
                }) async {
                  writes++;
                  return const TodoEditorSaveResult();
                },
          ),
        ),
      ),
    );
    await _settle(tester);
    final title = find.byType(TextField).first;
    await tester.ensureVisible(title);
    await tester.enterText(title, '新标题');
    await tester.tap(find.text('保存'));
    await _settle(tester);

    expect(writes, 1);
    expect(find.text('关联固定日程复核'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
