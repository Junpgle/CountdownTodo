import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/todo_editor_save_result.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/search_service.dart';
import 'package:countdown_todo/services/todo_editor_save_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:countdown_todo/widgets/todo_section_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

Future<void> settleEditor(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> openEditor(
  WidgetTester tester, {
  required TodoItem todo,
  List<TodoItem>? todos,
  TodoRecurrenceEditScope recurrenceEditScope =
      TodoRecurrenceEditScope.occurrence,
  Future<TodoEditorSaveResult> Function(
    List<TodoItem>,
    Map<String, TodoItem>, {
    Map<String, Set<String>>? expectedSeriesMembership,
  })?
  onEditorSave,
  void Function(List<TodoItem>)? onTodosChanged,
  void Function(String)? onTodoCompletionCommitted,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('open-editor'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => TodoEditScreen(
                  todo: todo,
                  todos: todos ?? [todo],
                  todoGroups: const [],
                  username: PlanAvailabilityFixture.username,
                  recurrenceEditScope: recurrenceEditScope,
                  onTodoCompletionCommitted: onTodoCompletionCommitted,
                  onTodosChanged: (items) => onTodosChanged?.call(items),
                  onEditorSave: onEditorSave,
                  onGroupsChanged: (_) {},
                ),
              ),
            ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await settleEditor(tester);
}

Future<void> editTitle(WidgetTester tester, String value) async {
  final title = find.byType(TextField).first;
  await tester.ensureVisible(title);
  await tester.enterText(title, value);
  await tester.pump();
}

Future<void> requestEditorBack(WidgetTester tester) async {
  await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets('无修改返回直接退出，不显示保护框', (tester) async {
    final todo = TodoItem(id: 'editor-id', title: '原始标题');
    await openEditor(tester, todo: todo);

    await requestEditorBack(tester);
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsNothing);
    expect(find.text('保留这次修改？'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑后返回可继续编辑或放弃，来源对象不被提前修改', (tester) async {
    final todo = TodoItem(id: 'editor-id', title: '原始标题');
    var writes = 0;
    await openEditor(tester, todo: todo, onTodosChanged: (_) => writes++);
    await editTitle(tester, '尚未保存的标题');

    await requestEditorBack(tester);
    expect(find.text('保留这次修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await settleEditor(tester);
    expect(find.byType(TodoEditScreen), findsOneWidget);
    expect(find.byType(TextField).first, findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '尚未保存的标题',
    );

    await requestEditorBack(tester);
    await tester.tap(find.text('放弃修改'));
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsNothing);
    expect(todo.title, '原始标题');
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存并退出等待显式保存成功，传入独立基线且只提交一次', (tester) async {
    final todo = TodoItem(id: 'legacy-editor-id', title: '原始标题');
    final save = Completer<TodoEditorSaveResult>();
    var writes = 0;
    List<TodoItem>? submitted;
    Map<String, TodoItem>? baselines;
    await openEditor(
      tester,
      todo: todo,
      onEditorSave: (items, readBaselines, {expectedSeriesMembership}) {
        writes++;
        submitted = items;
        baselines = readBaselines;
        return save.future;
      },
    );
    await editTitle(tester, '新标题');
    await requestEditorBack(tester);
    await tester.tap(find.text('保存并退出'));
    await tester.pump();

    expect(find.byType(TodoEditScreen), findsOneWidget);
    expect(writes, 1);
    expect(submitted, hasLength(1));
    expect(submitted!.single.id, 'legacy-editor-id');
    expect(baselines!['legacy-editor-id']!.title, '原始标题');
    expect(todo.title, '原始标题');

    save.complete(const TodoEditorSaveResult());
    await settleEditor(tester);
    expect(find.byType(TodoEditScreen), findsNothing);
    expect(writes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败留在编辑页并保留输入，再次保存成功后退出', (tester) async {
    final todo = TodoItem(id: 'editor-id', title: '原始标题');
    var writes = 0;
    await openEditor(
      tester,
      todo: todo,
      onEditorSave: (_, _, {expectedSeriesMembership}) async {
        writes++;
        if (writes == 1) throw StateError('模拟存储失败');
        return const TodoEditorSaveResult();
      },
    );
    await editTitle(tester, '保留的输入');
    await requestEditorBack(tester);
    await tester.tap(find.text('保存并退出'));
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '保留的输入',
    );
    expect(find.textContaining('修改仍保留'), findsOneWidget);
    expect(todo.title, '原始标题');
    expect(writes, 1);
    await tester.tap(find.text('保存'));
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsNothing);
    expect(writes, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('把输入改回原值后直接返回', (tester) async {
    final todo = TodoItem(id: 'editor-id', title: '原始标题');
    await openEditor(tester, todo: todo);
    await editTitle(tester, '临时标题');
    await editTitle(tester, '原始标题');

    await requestEditorBack(tester);
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsNothing);
    expect(find.text('保留这次修改？'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统返回的重复按键不会丢弃输入或叠加保护框', (tester) async {
    final todo = TodoItem(id: 'system-back-editor', title: '原始标题');
    await openEditor(tester, todo: todo);
    await editTitle(tester, '系统返回保留的输入');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('保留这次修改？'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settleEditor(tester);
    expect(find.byType(TodoEditScreen), findsOneWidget);
    expect(find.text('保留这次修改？'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '系统返回保留的输入',
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('保留这次修改？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空标题选择保存并退出时保留页面并显示校验', (tester) async {
    final todo = TodoItem(id: 'blank-title-editor', title: '原始标题');
    var writes = 0;
    await openEditor(
      tester,
      todo: todo,
      onEditorSave: (_, _, {expectedSeriesMembership}) async {
        writes++;
        return const TodoEditorSaveResult();
      },
    );
    await editTitle(tester, '   ');
    await requestEditorBack(tester);
    await tester.tap(find.text('保存并退出'));
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsOneWidget);
    expect(find.text('请输入待办内容'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '   ',
    );
    expect(writes, 0);
    expect(todo.title, '原始标题');
    expect(tester.takeException(), isNull);
  });

  testWidgets('完成保存失败不会提前发送停止专注信号', (tester) async {
    final todo = TodoItem(id: 'failed-completion-editor', title: '尚未完成');
    final stoppedTodoIds = <String>[];
    await openEditor(
      tester,
      todo: todo,
      onTodoCompletionCommitted: stoppedTodoIds.add,
      onEditorSave: (_, _, {expectedSeriesMembership}) async =>
          throw StateError('模拟提交失败'),
    );

    await tester.tap(find.byKey(const ValueKey('todo_edit_completion_switch')));
    await tester.tap(find.text('保存'));
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsOneWidget);
    expect(todo.isDone, isFalse);
    expect(stoppedTodoIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('完成状态只在明确保存成功后发送一次停止专注信号', (tester) async {
    final todo = TodoItem(id: 'committed-completion-editor', title: '已提交任务');
    final save = Completer<TodoEditorSaveResult>();
    final stoppedTodoIds = <String>[];
    await openEditor(
      tester,
      todo: todo,
      onTodoCompletionCommitted: stoppedTodoIds.add,
      onEditorSave: (_, _, {expectedSeriesMembership}) => save.future,
    );

    await tester.tap(find.byKey(const ValueKey('todo_edit_completion_switch')));
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(stoppedTodoIds, isEmpty);
    expect(find.byType(TodoEditScreen), findsOneWidget);

    save.complete(const TodoEditorSaveResult());
    await settleEditor(tester);

    expect(stoppedTodoIds, [todo.id]);
    expect(find.byType(TodoEditScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('修改后续循环时只提交副本，来源期次保持未修改', (tester) async {
    final current = TodoItem(
      id: 'series-current',
      title: '每周整理',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'series-current',
      createdDate: DateTime(2026, 10, 8).millisecondsSinceEpoch,
    );
    final future = TodoItem(
      id: 'series-future',
      title: '每周整理',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'series-current',
      createdDate: DateTime(2026, 10, 15).millisecondsSinceEpoch,
    );
    List<TodoItem>? submitted;
    await openEditor(
      tester,
      todo: current,
      todos: [current, future],
      recurrenceEditScope: TodoRecurrenceEditScope.future,
      onEditorSave: (items, _, {expectedSeriesMembership}) async {
        submitted = items;
        return const TodoEditorSaveResult();
      },
    );
    await editTitle(tester, '每周整理并复核');
    await tester.tap(find.text('保存'));
    await settleEditor(tester);

    expect(submitted, hasLength(2));
    expect(submitted!.map((item) => item.title), everyElement('每周整理并复核'));
    expect(
      submitted!.map((item) => item.id),
      containsAll([current.id, future.id]),
    );
    expect(current.title, '每周整理');
    expect(future.title, '每周整理');
    expect(tester.takeException(), isNull);
  });

  testWidgets('整系列保存复核影响数量并保留所有期次的独立状态', (tester) async {
    TodoItem occurrence(
      String id,
      int day, {
      bool done = false,
      bool skipped = false,
      RecurrenceType recurrence = RecurrenceType.none,
    }) => TodoItem(
      id: id,
      title: '每周整理',
      isDone: done,
      isSkipped: skipped,
      isSkippedSyncPending: skipped,
      recurrence: recurrence,
      recurrenceSeriesId: 'series-whole-edit',
      createdDate: DateTime(2026, 10, day, 9).millisecondsSinceEpoch,
      dueDate: DateTime(2026, 10, day, 23, 59),
      isAllDay: true,
      recurrenceEndDate: DateTime(2026, 11, 30),
    );

    final past = occurrence('whole-past', 19, done: true);
    final current = occurrence(
      'whole-current',
      20,
      recurrence: RecurrenceType.weekly,
    );
    final future = occurrence('whole-future', 22, skipped: true);
    List<TodoItem>? submitted;
    Map<String, TodoItem>? baselines;
    Map<String, Set<String>>? membership;
    await openEditor(
      tester,
      todo: current,
      todos: [past, current, future],
      recurrenceEditScope: TodoRecurrenceEditScope.series,
      onEditorSave: (items, readBaselines, {expectedSeriesMembership}) async {
        submitted = items;
        baselines = readBaselines;
        membership = expectedSeriesMembership;
        return const TodoEditorSaveResult();
      },
    );

    expect(find.text('整个系列 · 3 期'), findsOneWidget);
    expect(find.text('查看 3 期'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_edit_completion_switch')),
      findsNothing,
    );
    await editTitle(tester, '每周整理并复核');
    await tester.tap(find.text('应用到 3 期').first);
    await settleEditor(tester);
    expect(find.text('确认应用到整个系列'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.textContaining('历史 1 · 今天 1 · 未来 1'),
      ),
      findsOneWidget,
    );
    expect(submitted, isNull);

    await tester.tap(find.text('应用到 3 期').last);
    await settleEditor(tester);

    expect(submitted, hasLength(3));
    expect(submitted!.map((todo) => todo.id).toSet(), {
      'whole-past',
      'whole-current',
      'whole-future',
    });
    expect(submitted!.map((todo) => todo.title), everyElement('每周整理并复核'));
    expect(
      submitted!.singleWhere((todo) => todo.id == 'whole-past').isDone,
      isTrue,
    );
    final savedFuture = submitted!.singleWhere(
      (todo) => todo.id == 'whole-future',
    );
    expect(savedFuture.isSkipped, isTrue);
    expect(savedFuture.isSkippedSyncPending, isTrue);
    expect(
      submitted!.singleWhere((todo) => todo.id == 'whole-current').recurrence,
      RecurrenceType.weekly,
    );
    expect(
      baselines!.keys,
      containsAll(['whole-past', 'whole-current', 'whole-future']),
    );
    expect(membership, {
      'series-whole-edit': {'whole-past', 'whole-current', 'whole-future'},
    });
    expect(past.title, '每周整理');
    expect(current.title, '每周整理');
    expect(future.title, '每周整理');
    expect(tester.takeException(), isNull);
  });

  testWidgets('缩短循环结束日会裁掉结束日后的已物化期次', (tester) async {
    TodoItem occurrence(int day) => TodoItem(
      id: 'series-end-date-$day',
      title: '每周整理',
      recurrence: RecurrenceType.weekly,
      recurrenceSeriesId: 'series-end-date',
      createdDate: DateTime(2026, 10, day, 10).millisecondsSinceEpoch,
      recurrenceEndDate: DateTime(2026, 10, 31),
    );

    final current = occurrence(8);
    final beforeEnd = occurrence(14);
    final afterEnd = occurrence(20);
    List<TodoItem>? submitted;
    await openEditor(
      tester,
      todo: current,
      todos: [current, beforeEnd, afterEnd],
      onEditorSave: (items, _, {expectedSeriesMembership}) async {
        submitted = items;
        return const TodoEditorSaveResult();
      },
    );

    final endDateRow = find.text('重复结束日期');
    await tester.ensureVisible(endDateRow);
    await tester.tap(endDateRow);
    await settleEditor(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    final dayFifteen = find.text('15');
    expect(dayFifteen, findsOneWidget);
    await tester.tap(dayFifteen);
    await tester.tap(find.text('OK').last);
    await settleEditor(tester);
    await tester.tap(find.text('保存'));
    await settleEditor(tester);

    expect(
      submitted!.map((item) => item.id),
      containsAll([current.id, afterEnd.id]),
    );
    expect(submitted!.map((item) => item.id), isNot(contains(beforeEnd.id)));
    final savedCurrent = submitted!.singleWhere(
      (item) => item.id == current.id,
    );
    final savedAfterEnd = submitted!.singleWhere(
      (item) => item.id == afterEnd.id,
    );
    expect(savedCurrent.recurrenceEndDate, DateTime(2026, 10, 15));
    expect(beforeEnd.isDeleted, isFalse);
    expect(beforeEnd.title, '每周整理');
    expect(savedAfterEnd.isDeleted, isTrue);
    expect(savedAfterEnd.recurrence, RecurrenceType.none);
    expect(current.recurrenceEndDate, DateTime(2026, 10, 31));
    expect(afterEnd.isDeleted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页待办卡片进入编辑后保存并退出会写入同一条待办', (tester) async {
    final due = DateTime.now().add(const Duration(hours: 2));
    await fixture.todo('home-editor-target', '首页入口待办', due: due);
    final todos = await StorageService.getTodos(
      PlanAvailabilityFixture.username,
    );
    final target = todos.singleWhere((item) => item.id == 'home-editor-target');
    await PageTransitions.init();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoSectionWidget(
            todos: todos,
            username: PlanAvailabilityFixture.username,
            isLight: true,
            onTodosChanged: (_) {},
            onEditorSave: (items, baselines, {expectedSeriesMembership}) =>
                TodoEditorSaveService.save(
                  username: PlanAvailabilityFixture.username,
                  changedTodos: items,
                  baselines: baselines,
                  expectedSeriesMembership: expectedSeriesMembership,
                ),
            onEditorGroupsSave: (items, baselines) =>
                TodoEditorSaveService.saveGroups(
                  username: PlanAvailabilityFixture.username,
                  changedGroups: items,
                  baselines: baselines,
                ),
            onRefreshRequested: () {},
            todoGroups: const [],
            conflicts: const [],
          ),
        ),
      ),
    );
    await settleEditor(tester);
    final card = find.text('首页入口待办');
    await tester.ensureVisible(card);
    await tester.tap(card);
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsOneWidget);
    await editTitle(tester, '首页保存后的标题');
    await requestEditorBack(tester);
    await tester.tap(find.text('保存并退出'));
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsNothing);
    final stored = await StorageService.getTodos(
      PlanAvailabilityFixture.username,
    );
    expect(
      stored.singleWhere((item) => item.id == target.id).title,
      '首页保存后的标题',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('全局搜索待办入口使用退出保护并可显式保存', (tester) async {
    final result = SearchResult(
      id: 'search-todo-editor',
      title: '复习高数',
      icon: Icons.check_box_outlined,
      type: SearchResultType.todo,
      extraData: const {'uuid': 'todo-target'},
    );
    final sourceKey = GlobalKey();
    await PageTransitions.init();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              key: sourceKey,
              onPressed: () => unawaited(
                SearchNavigationHandler.handle(
                  context,
                  result,
                  sourceKey: sourceKey,
                ),
              ),
              child: const Text('打开搜索待办'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开搜索待办'));
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsOneWidget);
    await editTitle(tester, '搜索入口保存后的标题');
    await requestEditorBack(tester);
    expect(find.text('保留这次修改？'), findsOneWidget);
    await tester.tap(find.text('保存并退出'));
    await settleEditor(tester);

    expect(find.byType(TodoEditScreen), findsNothing);
    final stored = await StorageService.getTodos(
      PlanAvailabilityFixture.username,
    );
    expect(
      stored.singleWhere((item) => item.id == 'todo-target').title,
      '搜索入口保存后的标题',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏、横屏和桌面大字下退出确认完整可用', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final size in [
      const Size(320, 640),
      const Size(390, 844),
      const Size(844, 390),
      const Size(1280, 900),
    ]) {
      tester.view.physicalSize = size;
      final todo = TodoItem(id: 'responsive-editor', title: '原始标题');
      await openEditor(tester, todo: todo);
      await editTitle(tester, '检查动作换行');
      await requestEditorBack(tester);

      expect(find.text('保留这次修改？'), findsOneWidget);
      expect(find.text('继续编辑'), findsOneWidget);
      expect(find.text('放弃修改'), findsOneWidget);
      expect(find.text('保存并退出'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('继续编辑'));
      await settleEditor(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });
}
