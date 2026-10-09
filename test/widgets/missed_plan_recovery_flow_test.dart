import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/plan_block_stats_screen.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/missed_plan_recovery_service.dart';
import 'package:countdown_todo/widgets/missed_plan_recovery_flow.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:countdown_todo/widgets/plan_block_today_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../support/plan_availability_fixture.dart';

Finder key(String name) => find.byKey(ValueKey(name));
Future<void> settle(WidgetTester tester) async {
  // A dismissed route completes before the next real SQLite read starts.
  // Drive both stages without waiting for an indeterminate busy indicator.
  for (var stage = 0; stage < 3; stage++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  late PlanAvailabilityFixture fixture;
  late TodoPlanBlock source;
  late DateTime today;
  late MissedPlanRecoveryService service;
  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await initializeDateFormatting();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    today = DateUtils.dateOnly(DateTime.now());
    source = TodoPlanBlock(
      id: 'missed-entry',
      todoId: 'todo-target',
      titleSnapshot: '复习高数',
      startTime: today.millisecondsSinceEpoch,
      endTime: today.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
      status: TodoPlanStatus.missed,
      plannedMinutes: 45,
      remark: '配置继承',
      pomodoroMinutes: 30,
      pomodoroRounds: 2,
      reminderMinutes: 15,
    );
    await fixture.block(source);
    await LiquidGlassEffectService.setEnabled(false);
    await (await SharedPreferences.getInstance()).setBool(
      'tip_shown_todo_plan_guide',
      true,
    );
    service = MissedPlanRecoveryService(
      databaseOverride: fixture.db,
      clock: () => today.add(const Duration(hours: 7)),
    );
  });
  tearDown(() async {
    await LiquidGlassEffectService.setEnabled(false);
    GlassPerformanceMonitor.stop();
    await fixture.dispose();
  });

  for (final entry in ['today', 'stats', 'stats-all', 'day']) {
    testWidgets('正式入口 $entry 进入同一恢复草稿，关闭零写入', (tester) async {
      if (entry == 'stats-all') {
        for (var i = 0; i < 11; i++) {
          await fixture.block(
            TodoPlanBlock(
              id: 'extra-$i',
              todoId: source.todoId,
              startTime: today
                  .add(Duration(minutes: i + 1))
                  .millisecondsSinceEpoch,
              endTime: today
                  .add(Duration(minutes: i + 2))
                  .millisecondsSinceEpoch,
              status: TodoPlanStatus.missed,
              plannedMinutes: 30,
              titleSnapshot: '额外漏做$i',
            ),
          );
        }
        await fixture.block(
          TodoPlanBlock(
            id: 'outside-range',
            todoId: source.todoId,
            startTime: today
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch,
            endTime: today
                .subtract(const Duration(days: 2))
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            status: TodoPlanStatus.missed,
            titleSnapshot: '范围外漏做',
          ),
        );
      }
      final old = await fixture.db.query('todo_plan_blocks');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: entry == 'today'
              ? Scaffold(
                  body: PlanBlockTodaySection(
                    username: PlanAvailabilityFixture.username,
                  ),
                )
              : entry.startsWith('stats')
              ? const PlanBlockStatsScreen(
                  username: PlanAvailabilityFixture.username,
                )
              : TodoPlanScreen(
                  username: PlanAvailabilityFixture.username,
                  initialDate: today,
                ),
        ),
      );
      await settle(tester);
      if (entry == 'today') {
        await click(tester, key('plan-today-row-${source.id}'));
        await click(tester, key('plan-today-recover-${source.id}'));
      } else if (entry == 'stats-all') {
        await click(tester, key('plan-stats-all-missed'));
        expect(find.text('范围外漏做'), findsNothing);
        await tester.scrollUntilVisible(
          key('plan-stats-all-recover-${source.id}'),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await click(tester, key('plan-stats-all-recover-${source.id}'));
      } else if (entry == 'stats') {
        await click(tester, key('plan-stats-recover-${source.id}'));
      } else {
        await click(tester, find.text('复习高数').last);
        expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
        await click(tester, key('plan-recover-from-editor'));
      }
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      final editor = tester.widget<PlanBlockEditorSheet>(
        find.byType(PlanBlockEditorSheet),
      );
      expect(editor.block, isNull);
      expect(editor.recovery?.source.id, source.id);
      expect(editor.todos.single.id, source.todoId);
      expect(
        find.byKey(const ValueKey('plan-recovery-origin')),
        findsOneWidget,
      );
      expect(editor.fullPage, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
      expect(key('plan-date-shortcut-1'), findsNothing);
      await click(tester, key('plan-find-time'));
      expect(key('plan-custom-search-dialog'), findsOneWidget);
      expect(key('plan-date-shortcut-1'), findsOneWidget);
      await click(tester, find.byTooltip('关闭自定义查找'));
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await settle(tester);
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        old,
      );
      expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  Future<void> recoveryEditor(
    WidgetTester tester, {
    PlanEditorSaver? saver,
    Future<void> Function(TodoPlanBlock, TodoItem)? focus,
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
    Brightness brightness = Brightness.light,
    bool glass = false,
  }) async {
    final context = await service.read(
      PlanAvailabilityFixture.username,
      source.id,
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await LiquidGlassEffectService.setEnabled(glass);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (host) => Scaffold(
            body: TextButton(
              key: const ValueKey('open'),
              onPressed: () => showPlanBlockEditorSheet<void>(
                context: host,
                builder: (_) => PlanBlockEditorSheet(
                  username: context.username,
                  todos: [context.todo],
                  todoGroups: const [],
                  initialTodoId: context.todo.id,
                  recovery: context,
                  recoveryService: service,
                  startTime: today.add(const Duration(hours: 8)),
                  endTime: today.add(const Duration(hours: 8, minutes: 45)),
                  clock: service.clock,
                  onSaved: () {},
                  navigateOnFocus: false,
                  availabilityLoader: (q, {bool forceRefresh = false}) =>
                      service.availability.read(q, forceRefresh: forceRefresh),
                  saver:
                      saver ??
                      (
                        draft,
                        selection, {
                        expectedVersion,
                        expectedUpdatedAt,
                        newStatus,
                      }) => service.save(
                        context,
                        draft,
                        selection,
                        expectedVersion: expectedVersion,
                        expectedUpdatedAt: expectedUpdatedAt,
                        newStatus: newStatus,
                        sync: false,
                      ),
                  startFocus: focus,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await click(tester, key('open'));
  }

  testWidgets('采用五个候选，取消零写入，明天快捷选择重新读取今天', (tester) async {
    await recoveryEditor(tester);
    await click(tester, key('plan-lookup-slots'));
    expect(find.text('可用时段 · 5 个建议'), findsOneWidget);
    await click(
      tester,
      key(
        'plan-slot-${today.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
      ),
    );
    await click(tester, find.byTooltip('关闭').last);
    expect(await fixture.db.query('op_logs'), isEmpty);
    await recoveryEditor(tester);
    await click(tester, key('plan-date-shortcut-1'));
    expect(
      tester
          .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
          .recovery,
      isNotNull,
    );
    await click(tester, key('plan-lookup-slots'));
    final tomorrow = today.add(const Duration(days: 1, hours: 8));
    expect(key('plan-slot-${tomorrow.millisecondsSinceEpoch}'), findsOneWidget);
  });

  testWidgets('配置锁定原待办，保存失败保留输入，连击和专注重试复用新UUID', (tester) async {
    final context = await service.read(
      PlanAvailabilityFixture.username,
      source.id,
    );
    final gate = Completer<void>();
    int creates = 0, focusCalls = 0, statusCalls = 0;
    String? savedId;
    await recoveryEditor(
      tester,
      saver:
          (
            draft,
            selection, {
            expectedVersion,
            expectedUpdatedAt,
            newStatus,
          }) async {
            if (newStatus == null) {
              creates++;
              await gate.future;
            } else {
              statusCalls++;
              if (statusCalls == 1) throw StateError('模拟状态失败');
            }
            final saved = await service.save(
              context,
              draft,
              selection,
              expectedVersion: expectedVersion,
              expectedUpdatedAt: expectedUpdatedAt,
              newStatus: newStatus,
              sync: false,
            );
            savedId ??= saved.id;
            expect(saved.id, savedId);
            return saved;
          },
      focus: (block, todo) async {
        expect(block.todoId, source.todoId);
        focusCalls++;
        if (focusCalls == 1) throw StateError('模拟启动失败');
      },
    );
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(dropdown.onChanged, isNull);
    await tester.tap(key('plan-save-focus'));
    await tester.pump();
    await tester.tap(key('plan-save-focus'), warnIfMissed: false);
    gate.complete();
    await settle(tester);
    expect(creates, 1);
    expect(focusCalls, 1);
    expect(find.textContaining('专注未启动'), findsOneWidget);
    await click(tester, key('plan-save-focus'));
    expect(creates, 1);
    expect(focusCalls, 2);
    expect(statusCalls, 1);
    expect(find.textContaining('规划状态更新失败'), findsOneWidget);
    await click(tester, key('plan-save-focus'));
    expect(focusCalls, 2);
    expect(statusCalls, 2);
    expect(await fixture.db.query('todo_plan_blocks'), hasLength(2));
    final old = (await fixture.db.query(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: [source.id],
    )).single;
    expect(old['status'], TodoPlanStatus.missed.index);
    expect(old['remark'], source.remark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已有安排先显示，取消不打开草稿，明确仍新建才进入', (tester) async {
    await fixture.block(
      TodoPlanBlock(
        id: 'followup',
        todoId: source.todoId,
        startTime: today
            .add(const Duration(days: 1, hours: 10))
            .millisecondsSinceEpoch,
        endTime: today
            .add(const Duration(days: 1, hours: 11))
            .millisecondsSinceEpoch,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (host) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-flow'),
              onPressed: () => showMissedPlanRecovery(
                context: host,
                username: PlanAvailabilityFixture.username,
                sourceId: source.id,
                onSaved: () {},
                service: service,
              ),
              child: const Text('重新安排'),
            ),
          ),
        ),
      ),
    );
    await click(tester, key('open-flow'));
    expect(find.text('已有后续规划'), findsOneWidget);
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
    await click(tester, find.text('取消'));
    expect(await fixture.db.query('op_logs'), isEmpty);
    await click(tester, key('open-flow'));
    await click(tester, key('plan-recovery-add-again'));
    expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
    await settle(tester);
  });

  for (final config in [
    (const Size(320, 700), 1.6, 120.0, Brightness.light, false),
    (const Size(390, 844), 1.0, 0.0, Brightness.dark, true),
    (const Size(844, 390), 1.6, 120.0, Brightness.dark, true),
    (const Size(1280, 900), 1.0, 0.0, Brightness.light, false),
  ]) {
    testWidgets('恢复布局可操作无溢出 $config', (tester) async {
      await recoveryEditor(
        tester,
        size: config.$1,
        scale: config.$2,
        keyboard: config.$3,
        brightness: config.$4,
        glass: config.$5,
      );
      await tester.ensureVisible(key('plan-date-shortcut-1'));
      await tester.pumpAndSettle();
      await click(tester, key('plan-date-shortcut-1'));
      await tester.ensureVisible(key('plan-save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await click(tester, find.byTooltip('关闭').last);
    });
  }
  testWidgets('新增后续安排在保存前拒绝，保留输入并要求再明确确认', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (host) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-flow'),
              onPressed: () => showMissedPlanRecovery(
                context: host,
                username: PlanAvailabilityFixture.username,
                sourceId: source.id,
                onSaved: () {},
                service: service,
              ),
              child: const Text('重新安排'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(key('open-flow'));
    await tester.tap(key('open-flow'));
    await settle(tester);
    expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, '保留我的新备注');
    await fixture.block(
      TodoPlanBlock(
        id: 'unseen-ui',
        todoId: source.todoId,
        startTime: today
            .add(const Duration(days: 1, hours: 18))
            .millisecondsSinceEpoch,
        endTime: today
            .add(const Duration(days: 1, hours: 19))
            .millisecondsSinceEpoch,
      ),
    );
    await click(tester, key('plan-save'));
    expect(find.textContaining('出现新的或已变化的后续规划'), findsOneWidget);
    expect(find.text('保留我的新备注'), findsOneWidget);
    expect(await fixture.db.query('op_logs'), isEmpty);
    await click(tester, find.text('查看最新安排'));
    expect(find.text('已有后续规划'), findsOneWidget);
    await click(tester, key('plan-recovery-add-again'));
    final editor = tester.widget<PlanBlockEditorSheet>(
      find.byType(PlanBlockEditorSheet),
    );
    expect(editor.recovery!.acknowledgedFollowups.keys, contains('unseen-ui'));
    expect(find.text('保留我的新备注'), findsOneWidget);
    Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
    await settle(tester);
    expect(await fixture.db.query('op_logs'), isEmpty);
  });
  testWidgets('正在专注只提供查看当前专注，截止过期提供查看待办', (tester) async {
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (host) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-flow'),
                onPressed: () => showMissedPlanRecovery(
                  context: host,
                  username: PlanAvailabilityFixture.username,
                  sourceId: source.id,
                  onSaved: () {},
                  service: service,
                ),
                child: const Text('重新安排'),
              ),
            ),
          ),
        ),
      );
      await click(tester, key('open-flow'));
    }

    await fixture.block(
      TodoPlanBlock(
        id: 'current-focus',
        todoId: source.todoId,
        startTime: today.millisecondsSinceEpoch,
        endTime: today.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        status: TodoPlanStatus.focusing,
      ),
    );
    await open();
    expect(find.text('查看当前专注'), findsOneWidget);
    expect(key('plan-recovery-add-again'), findsNothing);
    await click(tester, find.text('取消'));
    await fixture.db.delete(
      'todo_plan_blocks',
      where: 'uuid = ?',
      whereArgs: ['current-focus'],
    );
    await fixture.db.update(
      'todos',
      {'due_date': today.millisecondsSinceEpoch},
      where: 'uuid = ?',
      whereArgs: [source.todoId],
    );
    await open();
    expect(key('plan-recovery-view-todo'), findsOneWidget);
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
    expect(await fixture.db.query('op_logs'), isEmpty);
    await click(tester, find.text('关闭'));
  });
}
