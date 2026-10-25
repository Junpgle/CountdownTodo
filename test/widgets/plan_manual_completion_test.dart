@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/plan_manual_completion_service.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:countdown_todo/widgets/plan_manual_completion_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  late PlanAvailabilityFixture f;
  late PlanManualCompletionService service;
  late TodoPlanBlock block;
  late GlobalKey<PlanManualCompletionHostState> host;
  var saves = 0, reminders = 0;
  var reminderFailure = false;
  Completer<void>? reminderWait;
  final now = DateTime(2026, 10, 8, 12);
  const user = PlanAvailabilityFixture.username;
  Finder key(String s) => find.byKey(ValueKey(s));
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> click(WidgetTester t, Finder target) async {
    await t.ensureVisible(target);
    await t.tap(target);
    await settle(t);
  }

  Future<void> open(
    WidgetTester t, {
    Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
    });
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        ),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: PlanManualCompletionHost(
            key: host,
            onRefresh: () => saves++,
            removeReminders: (receipt) async {
              reminders++;
              if (reminderWait != null) await reminderWait!.future;
              if (reminderFailure) {
                throw StateError('synthetic notification failure');
              }
            },
            child: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showPlanBlockEditorSheet<void>(
                      context: context,
                      builder: (_) => PlanBlockEditorSheet(
                        block: block,
                        username: user,
                        startTime: DateTime.fromMillisecondsSinceEpoch(
                          block.startTime,
                        ),
                        endTime: DateTime.fromMillisecondsSinceEpoch(
                          block.endTime,
                        ),
                        todos: [
                          TodoItem(
                            id: 'todo-target',
                            title: '整理材料',
                            dueDate: DateTime(2026, 10, 9),
                            teamUuid: 'team',
                            collabType: 1,
                          ),
                        ],
                        todoGroups: const [],
                        clock: () => now,
                        manualCompletionService: service,
                        onManualCompleted: (r) => host.currentState!.present(r),
                        onSaved: () => saves++,
                      ),
                    ),
                    child: const Text('打开规划'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('其他页面')),
                      ),
                    ),
                    child: const Text('离开来源页面'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await settle(t);
  }

  Future<void> preview(WidgetTester t) async {
    await click(t, find.text('打开规划'));
    await click(t, find.byTooltip('更多操作'));
    await click(t, find.text('确认规划已完成'));
    expect(find.text('确认这次规划已完成？'), findsOneWidget);
  }

  Future<void> confirm(WidgetTester t) => click(t, key('plan-manual-confirm'));
  Future<int> logs() async => (await f.db.query('op_logs')).length;
  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    await f.db.update('todos', {'team_uuid': 'team', 'collab_type': 1});
    debugDefaultTargetPlatformOverride = null;
    await initializeDateFormatting();
    await LiquidGlassEffectService.setEnabled(false);
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
    service = PlanManualCompletionService(
      databaseOverride: f.db,
      clock: () => now,
    );
    block = TodoPlanBlock(
      id: 'manual',
      todoId: 'todo-target',
      titleSnapshot: '整理材料',
      startTime: DateTime(2026, 10, 8, 9).millisecondsSinceEpoch,
      endTime: DateTime(2026, 10, 8, 10).millisecondsSinceEpoch,
      plannedMinutes: 60,
      status: TodoPlanStatus.missed,
      reminderMinutes: 0,
    );
    await f.block(block);
    host = GlobalKey<PlanManualCompletionHostState>();
    saves = 0;
    reminders = 0;
    reminderFailure = false;
    reminderWait = null;
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await f.dispose();
  });
  testWidgets('cancel is read only and leaves original editor', (t) async {
    await open(t);
    await preview(t);
    await click(t, find.text('返回核对'));
    expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
    expect(await logs(), 0);
    expect(saves, 0);
  });
  testWidgets(
    'confirm returns to source, removes only target reminders, and undo restores status',
    (t) async {
      await open(t);
      await preview(t);
      await confirm(t);
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
      expect(key('plan-manual-undo'), findsOneWidget);
      expect(saves, 1);
      expect(reminders, 1);
      expect(await logs(), 1);
      await click(t, key('plan-manual-undo'));
      expect((await f.db.query('todo_plan_blocks')).single['status'], 6);
      expect(await logs(), 2);
      expect(reminders, 1);
      expect(await f.db.query('pomodoro_records'), isEmpty);
      expect((await f.db.query('todos')).single['is_completed'], 0);
    },
  );
  testWidgets('unsaved remark is retained and never silently submitted', (
    t,
  ) async {
    await open(t);
    await click(t, find.text('打开规划'));
    await t.enterText(key('plan-remark'), '保留当前输入');
    await settle(t);
    await click(t, find.byTooltip('更多操作'));
    await click(t, find.text('确认规划已完成'));
    expect(find.textContaining('请先保存修改'), findsWidgets);
    expect(find.text('保留当前输入'), findsOneWidget);
    expect(key('plan-manual-confirm'), findsNothing);
    expect(await logs(), 0);
  });
  testWidgets(
    'changed plan while confirming is rejected without closing editor',
    (t) async {
      await open(t);
      await preview(t);
      await f.db.update('todo_plan_blocks', {'remark': '他人修改'});
      await confirm(t);
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(find.textContaining('规划或投入已变化'), findsWidgets);
      expect(await logs(), 0);
    },
  );
  testWidgets(
    'reminder retry never repeats the status write and undo remains available',
    (t) async {
      reminderFailure = true;
      await open(t);
      await preview(t);
      await confirm(t);
      expect(key('plan-manual-retry-reminders'), findsOneWidget);
      expect(await logs(), 1);
      reminderFailure = false;
      await click(t, key('plan-manual-retry-reminders'));
      expect(reminders, 2);
      expect(await logs(), 1);
      expect(key('plan-manual-undo'), findsOneWidget);
      await click(t, key('plan-manual-undo'));
      expect(await logs(), 2);
    },
  );
  testWidgets('slow reminder coordination never blocks the ten-second undo', (
    t,
  ) async {
    reminderWait = Completer<void>();
    await open(t);
    await preview(t);
    await confirm(t);
    expect(t.widget<TextButton>(key('plan-manual-undo')).onPressed, isNotNull);
    await click(t, key('plan-manual-undo'));
    expect((await f.db.query('todo_plan_blocks')).single['status'], 6);
    expect(await logs(), 2);
    reminderWait!.complete();
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('expiry hides undo and never writes an automatic reversal', (
    t,
  ) async {
    await open(t);
    await preview(t);
    await confirm(t);
    await t.pump(const Duration(seconds: 11));
    await settle(t);
    expect(key('plan-manual-undo'), findsNothing);
    expect(await logs(), 1);
  });
  testWidgets(
    'leaving source page invalidates receipt and returning does not revive it',
    (t) async {
      await open(t);
      final request = await service.prepare(user, 'manual');
      final receipt = await service.confirm(request, sync: false);
      host.currentState!.present(receipt);
      await settle(t);
      expect(receipt.canUndo, isTrue);
      await click(t, find.text('离开来源页面'));
      expect(receipt.canUndo, isFalse);
      Navigator.of(t.element(find.text('其他页面'))).pop();
      await settle(t);
      expect(key('plan-manual-undo'), findsNothing);
    },
  );
  testWidgets('identity signal clears undo immediately', (t) async {
    await open(t);
    await preview(t);
    await confirm(t);
    StorageService.triggerRefresh({DataRefreshDomain.all});
    await t.pump(const Duration(milliseconds: 101));
    await settle(t);
    expect(key('plan-manual-undo'), findsNothing);
    expect(await logs(), 1);
  });
  testWidgets('next completion replaces only the previous single receipt', (
    t,
  ) async {
    await open(t);
    final first = await service.confirm(
      await service.prepare(user, 'manual'),
      sync: false,
    );
    host.currentState!.present(first);
    await settle(t);
    final secondBlock = TodoPlanBlock.fromJson(block.toJson())..id = 'second';
    await f.block(secondBlock);
    final second = await service.confirm(
      await service.prepare(user, 'second'),
      sync: false,
    );
    host.currentState!.present(second);
    await settle(t);
    expect(first.canUndo, isFalse);
    expect(second.canUndo, isTrue);
    expect(key('plan-manual-undo'), findsOneWidget);
  });
  for (final entry in [
    (const Size(320, 700), 1.8, Brightness.dark),
    (const Size(720, 360), 1.0, Brightness.light),
    (const Size(1280, 900), 1.8, Brightness.dark),
  ]) {
    testWidgets('confirmation and notice fit ${entry.$1} scale ${entry.$2}', (
      t,
    ) async {
      await open(t, size: entry.$1, scale: entry.$2, brightness: entry.$3);
      await preview(t);
      expect(t.takeException(), isNull);
      await confirm(t);
      expect(key('plan-manual-undo'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
