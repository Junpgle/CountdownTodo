@TestOn('vm')
library;

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_reuse_repository.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlanAvailabilityFixture fixture;
  late PlanReuseRepository repository;
  late TodoPlanBlock source;
  final day = PlanAvailabilityFixture.day;

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    repository = PlanReuseRepository(
      database: fixture.db,
      clock: () => day.add(const Duration(hours: 8)),
    );
    source = TodoPlanBlock(
      id: 'reuse-source',
      todoId: 'todo-target',
      startTime: day
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 9))
          .millisecondsSinceEpoch,
      endTime: day
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 10))
          .millisecondsSinceEpoch,
      plannedMinutes: 17,
      actualFocusSeconds: 1234,
      status: TodoPlanStatus.finished,
      source: TodoPlanSource.ai,
      remark: '源备注',
      reminderMinutes: 10,
      pomodoroMinutes: 45,
      pomodoroRounds: 2,
      calendarEventId: 'old-calendar-event',
      pomodoroRecordIds: ['old-focus-record'],
    );
    await fixture.block(source);
  });

  tearDown(() async {
    await fixture.dispose();
  });

  Future<void> openSourceEditor(
    WidgetTester tester,
    TodoPlanBlock block,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-source-editor'),
              onPressed: () => showPlanBlockEditorSheet<void>(
                context: context,
                builder: (_) => PlanBlockEditorSheet(
                  block: block,
                  startTime: DateTime.fromMillisecondsSinceEpoch(
                    block.startTime,
                  ),
                  endTime: DateTime.fromMillisecondsSinceEpoch(block.endTime),
                  todos: [
                    TodoItem(id: 'todo-target', title: '复习高数'),
                    TodoItem(id: 'todo-another', title: '整理笔记'),
                  ],
                  todoGroups: const [],
                  username: PlanAvailabilityFixture.username,
                  onSaved: () {},
                  clock: () => day.add(const Duration(hours: 8)),
                  reuseRepository: repository,
                  availabilityLoader: (query, {forceRefresh = false}) async =>
                      PlanAvailabilitySnapshot(
                        todo: TodoItem(id: query.todoId, title: '复习高数'),
                        busy: const [],
                        coverage: '合成安排',
                      ),
                ),
              ),
              child: const Text('打开原规划'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-source-editor')));
    await tester.pumpAndSettle();
  }

  testWidgets('真实规划菜单打开独立复用页并只读取源设置', (tester) async {
    final sourceBefore = (await fixture.db.query(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: [source.id],
    )).single;
    final operationsBefore = await fixture.db.query('op_logs');

    await openSourceEditor(tester, source);
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    expect(find.text('照此新建'), findsOneWidget);

    await tester.tap(find.text('照此新建'));
    await tester.pumpAndSettle();

    final page = find.byKey(const ValueKey('plan-block-editor-page'));
    expect(page, findsOneWidget);
    final notice = tester.widget<Text>(
      find.descendant(
        of: page,
        matching: find.byKey(const ValueKey('plan-reuse-notice')),
      ),
    );
    expect(notice.data, contains('沿用已有规划设置 · 60分钟'));
    final remark = tester.widget<TextField>(
      find.descendant(
        of: page,
        matching: find.byKey(const ValueKey('plan-remark')),
      ),
    );
    expect(remark.controller!.text, '源备注');
    expect(
      find.descendant(
        of: page,
        matching: find.byKey(const ValueKey('plan-todo-picker-todo-target')),
      ),
      findsOneWidget,
    );

    final sourceAfter = (await fixture.db.query(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: [source.id],
    )).single;
    expect(sourceAfter, sourceBefore);
    expect(await fixture.db.query('op_logs'), operationsBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日历映射规划不显示照此新建入口', (tester) async {
    final mapped = TodoPlanBlock(
      id: 'mapped_course_course-1',
      todoId: 'todo-target',
      startTime: source.startTime,
      endTime: source.endTime,
      source: TodoPlanSource.calendar,
    );
    await openSourceEditor(tester, mapped);
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    expect(find.text('照此新建'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
