import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/todo_create_save_result.dart';
import 'package:countdown_todo/screens/add_todo_screen.dart';
import 'package:countdown_todo/screens/fixed_schedule_related_todo_picker_screen.dart';
import 'package:countdown_todo/screens/todo_confirm_screen.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'tip_shown_coach_add_todo': true});
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
  });

  tearDown(ApiService.clearBaseUrlOverride);

  testWidgets('待办和日程共享输入页，切换日程不会导航到新页面', (tester) async {
    FixedScheduleItem? savedSchedule;
    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          todoGroups: [TodoGroup(name: '收集箱')],
          onTodoAdded: (_) {},
          onFixedScheduleAdded: (item) async => savedSchedule = item,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '团队会议');
    await tester.tap(find.bySemanticsLabel('日程'));
    await tester.pumpAndSettle();

    expect(find.byType(AddTodoScreen), findsOneWidget);
    expect(find.text('团队会议'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixed-schedule-date')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fixed-schedule-start-time')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fixed-schedule-end-time')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('fixed-schedule-time-tbd')),
        matching: find.byKey(const ValueKey('fixed-schedule-date')),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('fixed-schedule-end-time-tbd')),
        matching: find.byKey(const ValueKey('fixed-schedule-end-time')),
      ),
      findsOneWidget,
    );
    expect(find.text('结束时间待定'), findsNothing);
    expect(find.text('某天内完成'), findsNothing);

    await tester.tap(find.text('完成'));
    await tester.pump();

    expect(savedSchedule, isNotNull);
    expect(savedSchedule!.title, '团队会议');
    expect(savedSchedule!.startTime, isNotNull);
    expect(savedSchedule!.endTime, isNotNull);
    expect(savedSchedule!.source, FixedScheduleSource.manual);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('固定日程入口直接打开日程标签', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          initialMode: AddTodoInitialMode.fixedSchedule,
          onTodoAdded: (_) {},
          onFixedScheduleAdded: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('要记录什么日程？'), findsOneWidget);
    expect(find.byKey(const ValueKey('fixed-schedule-date')), findsOneWidget);
    expect(
      find.textContaining(DateFormat('yyyy-MM-dd').format(DateTime.now())),
      findsOneWidget,
    );
    expect(find.text('某天内完成'), findsNothing);
  });

  testWidgets('空闲输入页不会持续调度加载动画帧', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          todoGroups: [TodoGroup(name: '收集箱')],
          onTodoAdded: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('AI确认页按固定日程保存地点且不捏造结束时间', (tester) async {
    FixedScheduleItem? savedSchedule;
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: TodoConfirmScreen(
            llmResults: const [
              {
                'itemKind': 'fixedSchedule',
                'title': '客户同步',
                'location': '第一会议室',
                'remark': '带合同',
                'isAllDay': false,
                'startTime': '2026-08-03 10:00',
                'endTime': null,
                'timeMode': 'range',
                'recurrence': 'none',
                'reminderMinutes': 15,
              },
            ],
            onFixedScheduleAdded: (item) async => savedSchedule = item,
            onConfirm: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('日程 1/1'), findsOneWidget);
    expect(find.textContaining('结束待定'), findsOneWidget);
    expect(find.text('08-03 10:00开始 · 结束待定'), findsOneWidget);
    await tester.tap(find.text('确认并添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存为固定日程'));
    await tester.pumpAndSettle();

    expect(savedSchedule, isNotNull);
    expect(savedSchedule!.location, '第一会议室');
    expect(savedSchedule!.remark, '带合同');
    expect(savedSchedule!.endTime, isNull);
    expect(savedSchedule!.reminderMinutes, [15]);
  });

  testWidgets('AI清单保存失败保留已确认事项，重试沿用同一ID', (tester) async {
    Future<void> pumpConfirmScreen() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }

    final localTodoIds = <String>[];
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: TodoConfirmScreen(
            llmResults: const [
              {'itemKind': 'todo', 'title': '确认清单项', 'timeMode': 'unscheduled'},
            ],
            onConfirm: (results) async {
              attempts++;
              localTodoIds.add(results.single['localTodoId']!.toString());
              if (attempts == 1) throw StateError('合成存储失败');
            },
          ),
        ),
      ),
    );
    await pumpConfirmScreen();

    await tester.tap(find.text('确认并添加'));
    await tester.pump();
    if (find.text('暂存为待办').evaluate().isNotEmpty) {
      await tester.tap(find.text('暂存为待办'));
    }
    await pumpConfirmScreen();
    expect(find.byType(TodoConfirmScreen), findsOneWidget);
    expect(attempts, 1);
    expect(localTodoIds, hasLength(1));
    expect(find.text('重试保存并完成'), findsOneWidget);

    final retryButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('重试保存并完成'),
        matching: find.byType(FilledButton),
      ),
    );
    retryButton.onPressed!.call();
    await pumpConfirmScreen();

    expect(attempts, 2);
    expect(localTodoIds, hasLength(2));
    expect(localTodoIds.first, localTodoIds.last);
    expect(find.byType(TodoConfirmScreen), findsNothing);
  });

  testWidgets('新建待办有草稿时返回提供继续、放弃和保存选项', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-add-todo'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AddTodoScreen(onTodoAdded: (_) {}),
                  ),
                ),
                child: const Text('打开新建待办'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-add-todo')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('manual-todo-title')),
      '尚未保存的清单项',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('manual-todo-title')))
          .controller!
          .text,
      '尚未保存的清单项',
    );
    expect(
      tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
      isFalse,
    );
    await Navigator.of(tester.element(find.byType(AddTodoScreen))).maybePop();
    await tester.pumpAndSettle();

    expect(find.text('内容还没有保存'), findsOneWidget);
    expect(find.text('继续填写'), findsOneWidget);
    expect(find.text('放弃草稿'), findsOneWidget);
    expect(find.text('保存并退出'), findsOneWidget);
    await tester.tap(find.text('继续填写'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('manual-todo-title')))
          .controller!
          .text,
      '尚未保存的清单项',
    );

    await Navigator.of(tester.element(find.byType(AddTodoScreen))).maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃草稿'));
    await tester.pumpAndSettle();
    expect(find.byType(AddTodoScreen), findsNothing);
  });

  testWidgets('手动保存失败保留输入并在重试时沿用同一待办ID', (tester) async {
    final ids = <String>[];
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          onManualTodoSaved: (todo) async {
            attempts++;
            ids.add(todo.id);
            if (attempts == 1) throw StateError('合成存储失败');
            return const TodoCreateSaveResult();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '可重试待办');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.byType(AddTodoScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '可重试待办',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(ids, hasLength(2));
    expect(ids.first, isNotEmpty);
    expect(ids[1], ids.first);
  });

  testWidgets('新建日程支持关联已有待办并正确保存到日程模型', (tester) async {
    FixedScheduleItem? savedSchedule;
    final testTodos = [
      TodoItem(id: 'todo-1', title: '打印准考证', dueDate: DateTime(2026, 11, 1)),
      TodoItem(id: 'todo-2', title: '带身份证', dueDate: DateTime(2026, 11, 2)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          username: 'tester',
          initialMode: AddTodoInitialMode.fixedSchedule,
          onTodoAdded: (_) {},
          onFixedScheduleAdded: (item) async => savedSchedule = item,
          loadRelatedTodoPage:
              (username, {limit = 50, offset = 0, query = '', teamUuid}) async {
                return (todos: testTodos, hasMore: false);
              },
          loadSelectedRelatedTodos: (username, todoIds) async {
            return testTodos.where((t) => todoIds.contains(t.id)).toList();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('fixed-schedule-related-todos')),
      findsOneWidget,
    );
    expect(find.text('关联个人待办'), findsOneWidget);
    expect(find.text('个人私有'), findsWidgets);
    expect(find.textContaining('当前只展示个人待办'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '期末考试');

    // 打开待办选择器
    await tester.tap(
      find.byKey(const ValueKey('fixed-schedule-related-todos')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FixedScheduleRelatedTodoPickerScreen), findsOneWidget);
    expect(find.text('关联待办'), findsOneWidget);
    expect(find.text('打印准考证'), findsOneWidget);
    expect(find.text('带身份证'), findsOneWidget);

    // 选中第一个待办
    await tester.tap(find.byKey(const ValueKey('related-todo-todo-1')));
    await tester.pumpAndSettle();

    // 点击应用关联
    await tester.tap(find.byKey(const ValueKey('apply-related-todos')));
    await tester.pumpAndSettle();

    // 返回 AddTodoScreen 后验证副标题更新
    expect(find.textContaining('已关联 1 项'), findsOneWidget);

    // 点击完成保存日程
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(savedSchedule, isNotNull);
    expect(savedSchedule!.title, '期末考试');
    expect(savedSchedule!.relatedTodoIds, ['todo-1']);
  });

  testWidgets('新建日程如果关联待办跨团队不匹配则阻止保存并提示', (tester) async {
    FixedScheduleItem? savedSchedule;
    final testTodos = [
      TodoItem(id: 'todo-team', title: '团队待办', teamUuid: 'team-a'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          username: 'tester',
          initialMode: AddTodoInitialMode.fixedSchedule,
          initialRelatedTodoIds: {'todo-team'},
          onTodoAdded: (_) {},
          onFixedScheduleAdded: (item) async => savedSchedule = item,
          loadSelectedRelatedTodos: (username, todoIds) async => testTodos,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已关联 1 项'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '个人日程');

    // 此时团队为个人私有，而 todo-team 属于 team-a
    await tester.tap(find.text('完成'));
    await tester.pump();

    expect(savedSchedule, isNull);
    expect(find.text('请在“关联待办”中移除已删除或当前日程不可见的项目后再保存'), findsOneWidget);
  });
}
