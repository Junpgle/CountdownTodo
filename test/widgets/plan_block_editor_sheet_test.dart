import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

final day = DateTime(2026, 10, 8);
final now = DateTime(2026, 10, 7, 12);
final target = TodoItem(
  id: 'todo-editor',
  title: '复习高数',
  dueDate: DateTime(2026, 10, 8, 20),
  createdDate: DateTime(2026, 10, 8, 20).millisecondsSinceEpoch,
);
final other = TodoItem(id: 'todo-other', title: '整理笔记');
Finder key(String value) => find.byKey(ValueKey(value));
Future<void> tap(WidgetTester tester, String value) async {
  await tester.ensureVisible(key(value));
  await tester.tap(key(value));
  await tester.pump();
}

Future<void> showEditor(
  WidgetTester tester, {
  required PlanEditorSaver saver,
  Future<void> Function(TodoPlanBlock, TodoItem)? focus,
  PlanAvailabilityLoader? loader,
  Future<TimeEstimationResult> Function(TodoItem)? estimate,
  TodoPlanBlock? block,
  Size size = const Size(1000, 900),
  double scale = 1,
  double keyboard = 0,
  Brightness brightness = Brightness.light,
  String username = 'synthetic',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
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
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-editor'),
            onPressed: () => showPlanBlockEditorSheet<void>(
              context: context,
              builder: (_) => PlanBlockEditorSheet(
                username: username,
                todos: [target, other],
                todoGroups: const [],
                block: block,
                startTime: day.add(const Duration(hours: 13)),
                endTime: day.add(const Duration(hours: 13, minutes: 30)),
                initialTodoId: target.id,
                saver: saver,
                startFocus: focus,
                estimate: estimate,
                availabilityLoader:
                    loader ??
                    (q, {bool forceRefresh = false}) async =>
                        PlanAvailabilitySnapshot(
                          todo: q.todoId == target.id ? target : other,
                          coverage: '应用内合成安排；未计入手机日历',
                          busy: [
                            for (final hour in [9, 11, 14])
                              PlanBusyInterval(
                                day.add(Duration(hours: hour)),
                                day.add(Duration(hours: hour + 1)),
                                source: PlanBusySource.planBlock,
                              ),
                          ],
                        ),
                clock: () => now,
                onSaved: () {},
                navigateOnFocus: false,
              ),
            ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );
  await tap(tester, 'open-editor');
  await tester.pumpAndSettle();
}

Future<void> adopt(WidgetTester tester) async {
  await tap(tester, 'plan-find-time');
  await tap(tester, 'plan-duration-45');
  await tap(tester, 'plan-lookup-slots');
  await tester.pumpAndSettle();
  await tap(
    tester,
    'plan-slot-${day.add(const Duration(hours: 10)).millisecondsSinceEpoch}',
  );
  await tester.pumpAndSettle();
}

Future<TodoPlanBlock> identitySaver(
  TodoPlanBlock block,
  PlanAvailabilitySelection? selection, {
  int? expectedVersion,
  int? expectedUpdatedAt,
  TodoPlanStatus? newStatus,
}) async => block;
void main() {
  for (final width in [320.0, 680.0]) {
    testWidgets('其他设置并排且移除 AI 按钮 width=$width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showEditor(tester, saver: identitySaver, size: Size(width, 1000));
      final single = key('plan-option-单轮番茄');
      final rounds = key('plan-option-番茄轮数');
      final reminder = key('plan-option-提前提醒');
      await tester.ensureVisible(single);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(single).top,
        closeTo(tester.getRect(rounds).top, 1),
      );
      expect(
        tester.getRect(single).right,
        lessThan(tester.getRect(rounds).left),
      );
      if (width >= 680) {
        expect(
          tester.getRect(reminder).top,
          closeTo(tester.getRect(single).top, 1),
        );
      } else {
        expect(
          tester.getRect(reminder).top,
          greaterThan(tester.getRect(single).top),
        );
      }
      expect(find.text('AI 帮我安排更多'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'current_login_user': 'synthetic'});
    await LiquidGlassEffectService.setEnabled(false);
  });
  tearDown(() async {
    await LiquidGlassEffectService.setEnabled(false);
    GlassPerformanceMonitor.stop();
  });
  for (final size in [const Size(320, 640), const Size(720, 360)]) {
    testWidgets('避让设置与编辑时间在短屏大字体可达 size=$size', (tester) async {
      await showEditor(
        tester,
        saver: identitySaver,
        size: size,
        scale: 1.6,
        keyboard: 130,
      );
      await tap(tester, 'plan-find-time');
      await tap(tester, 'plan-avoid-options');
      await tester.pumpAndSettle();
      await tap(tester, 'plan-avoid-toggle-0');
      await tester.pumpAndSettle();
      await tap(tester, 'plan-avoid-edit-0');
      await tester.pumpAndSettle();
      expect(find.text('调整午休时间'), findsOneWidget);
      await tap(tester, 'plan-avoid-confirm');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'plan-save');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('采用只填草稿，取消没有保存或专注调用', (tester) async {
    var saves = 0, starts = 0;
    await showEditor(
      tester,
      saver:
          (
            draft,
            selection, {
            expectedVersion,
            expectedUpdatedAt,
            newStatus,
          }) async {
            saves++;
            return draft;
          },
      focus: (_, _) async {
        starts++;
      },
    );
    await adopt(tester);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('10:45'), findsOneWidget);
    expect(saves, 0);
    expect(starts, 0);
    Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(starts, 0);
    expect(target.dueDate, DateTime(2026, 10, 8, 20));
  });
  testWidgets('显式保存推荐、备注、提醒与番茄配置，保留原对象', (tester) async {
    TodoPlanBlock? saved;
    PlanAvailabilitySelection? chosen;
    final old = TodoPlanBlock(
      id: 'existing',
      todoId: target.id,
      startTime: day.millisecondsSinceEpoch,
      endTime: day.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      remark: '旧备注',
      reminderMinutes: 15,
      pomodoroMinutes: 45,
      pomodoroRounds: 2,
    );
    await showEditor(
      tester,
      block: old,
      saver:
          (
            draft,
            selection, {
            expectedVersion,
            expectedUpdatedAt,
            newStatus,
          }) async {
            saved = draft;
            chosen = selection;
            expect(expectedVersion, old.version);
            return draft;
          },
    );
    await adopt(tester);
    await tap(tester, 'plan-save');
    await tester.pumpAndSettle();
    expect(saved!.id, old.id);
    expect(
      saved!.startTime,
      day.add(const Duration(hours: 10)).millisecondsSinceEpoch,
    );
    expect(saved!.plannedMinutes, 45);
    expect(saved!.remark, '旧备注');
    expect(saved!.reminderMinutes, 15);
    expect(saved!.pomodoroMinutes, 45);
    expect(saved!.pomodoroRounds, 2);
    expect(old.startTime, day.millisecondsSinceEpoch);
    expect(chosen, isNotNull);
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
  });
  testWidgets('保存校验失败保留草稿，零专注启动', (tester) async {
    var starts = 0;
    await showEditor(
      tester,
      saver: (_, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        throw const PlanAvailabilityException('时段已被占用');
      },
      focus: (_, _) async {
        starts++;
      },
    );
    await adopt(tester);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(find.text('时段已被占用'), findsOneWidget);
    expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
    expect(starts, 0);
  });
  testWidgets('重复点击等待中的保存只调用一次', (tester) async {
    final pending = Completer<TodoPlanBlock>();
    var saves = 0;
    TodoPlanBlock? draft;
    await showEditor(
      tester,
      saver: (value, _, {expectedVersion, expectedUpdatedAt, newStatus}) {
        saves++;
        draft = value;
        return pending.future;
      },
    );
    await adopt(tester);
    await tap(tester, 'plan-save');
    await tester.tap(key('plan-save'), warnIfMissed: false);
    await tester.pump();
    expect(saves, 1);
    pending.complete(draft!);
    await tester.pumpAndSettle();
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
  });
  testWidgets('专注失败保留已存规划，重试不重复保存且UUID一致', (tester) async {
    var writes = 0, starts = 0;
    final ids = <String>[];
    await showEditor(
      tester,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        writes++;
        final saved = TodoPlanBlock.fromJson(draft.toJson());
        if (newStatus != null) saved.status = newStatus;
        return saved;
      },
      focus: (block, _) async {
        starts++;
        ids.add(block.id);
        if (starts == 1) throw StateError('模拟启动失败');
      },
    );
    await adopt(tester);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.textContaining('规划已保存，专注未启动'), findsOneWidget);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(ids.toSet(), hasLength(1));
    expect(writes, 2); // One creation plus one focusing-state update.
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
  });
  testWidgets('启动成功但状态写入失败，重试仅更新状态不重复启动', (tester) async {
    var writes = 0, starts = 0;
    await showEditor(
      tester,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        writes++;
        if (writes == 2) throw StateError('状态写入失败');
        return draft;
      },
      focus: (_, _) async {
        starts++;
      },
    );
    await adopt(tester);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(find.textContaining('专注已启动，但规划状态更新失败'), findsOneWidget);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(writes, 3);
  });
  testWidgets('同步刷新使已采用推荐失效，保存被阻止', (tester) async {
    var saves = 0;
    await showEditor(
      tester,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        saves++;
        return draft;
      },
    );
    await adopt(tester);
    StorageService.triggerRefresh(const {DataRefreshDomain.planBlocks});
    await tester.pump(const Duration(milliseconds: 120));
    await tap(tester, 'plan-save');
    await tester.pumpAndSettle();
    expect(find.text('推荐时段已失效，请重新查找或手动修改时间'), findsOneWidget);
    expect(saves, 0);
  });
  testWidgets('旧估时晚返回不能覆盖已采用时段或番茄配置', (tester) async {
    final pending = Completer<TimeEstimationResult>();
    await showEditor(
      tester,
      saver: identitySaver,
      estimate: (_) => pending.future,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('整理笔记').last);
    await tester.pumpAndSettle();
    await adopt(tester);
    pending.complete(
      const TimeEstimationResult(
        estimatedMinutes: 180,
        confidence: 0.8,
        reason: '合成估时',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10:45'), findsOneWidget);
    expect(find.textContaining('历史估时'), findsNothing);
    expect(find.text('按规划时长'), findsOneWidget);
  });
  testWidgets('真实编辑器通过真实隔离存储：采用取消零写入，保存一条规划及oplog', (tester) async {
    final fixture = PlanAvailabilityFixture();
    await tester.runAsync(() => fixture.initialize());
    final repository = PlanAvailabilityRepository(
      databaseOverride: fixture.db,
      clock: () => now,
    );
    await tester.runAsync(
      () => fixture.todo(target.id, target.title, due: target.dueDate),
    );
    Future<TodoPlanBlock> saver(
      TodoPlanBlock draft,
      PlanAvailabilitySelection? selection, {
      int? expectedVersion,
      int? expectedUpdatedAt,
      TodoPlanStatus? newStatus,
    }) => repository.save(
      selection!,
      draft,
      expectedVersion: expectedVersion,
      expectedUpdatedAt: expectedUpdatedAt,
      sync: false,
    );
    Future<void> chooseReal() async {
      await tap(tester, 'plan-find-time');
      await tap(tester, 'plan-duration-45');
      await tap(tester, 'plan-lookup-slots');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tap(
        tester,
        'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
      );
    }

    try {
      await showEditor(
        tester,
        username: PlanAvailabilityFixture.username,
        saver: saver,
        loader: repository.read,
      );
      await chooseReal();
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        isEmpty,
      );
      expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
      await showEditor(
        tester,
        username: PlanAvailabilityFixture.username,
        saver: saver,
        loader: repository.read,
      );
      await chooseReal();
      await tap(tester, 'plan-save');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final rows = await tester.runAsync(
        () => fixture.db.query('todo_plan_blocks'),
      );
      expect(rows, hasLength(1));
      expect(rows!.single['planned_minutes'], 45);
      expect(
        await tester.runAsync(() => fixture.db.query('op_logs')),
        hasLength(1),
      );
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(() => fixture.dispose());
    }
  });
  testWidgets('真实编辑器保存复查新占用，保持草稿且无oplog', (tester) async {
    final fixture = PlanAvailabilityFixture();
    await tester.runAsync(() => fixture.initialize());
    await tester.runAsync(
      () => fixture.todo(target.id, target.title, due: target.dueDate),
    );
    final repository = PlanAvailabilityRepository(
      databaseOverride: fixture.db,
      clock: () => now,
    );
    try {
      await showEditor(
        tester,
        username: PlanAvailabilityFixture.username,
        loader: repository.read,
        saver: (
          draft,
          selection, {
          expectedVersion,
          expectedUpdatedAt,
          newStatus,
        }) => repository.save(selection!, draft, sync: false),
      );
      await tap(tester, 'plan-find-time');
      await tap(tester, 'plan-duration-45');
      await tap(tester, 'plan-lookup-slots');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tap(
        tester,
        'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
      );
      await tester.runAsync(
        () => fixture.fixed(
          'new-meeting',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      await tap(tester, 'plan-save-focus');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('该时段已失效或被占用，请重新查找时段'), findsOneWidget);
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        isEmpty,
      );
      expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(() => fixture.dispose());
    }
  });
  testWidgets('真实规划日视图点击、拖选、编辑三入口均打开共享推荐编辑器', (tester) async {
    // Use a future day: the page legitimately marks overdue plans missed.
    final realNow = DateTime.now();
    final entryDay = DateTime(realNow.year, realNow.month, realNow.day + 1);
    final fixture = PlanAvailabilityFixture();
    await tester.runAsync(() => fixture.initialize());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_todo_plan_guide', true);
    await tester.runAsync(
      () => fixture.block(
        TodoPlanBlock(
          id: 'entry-plan',
          todoId: 'todo-target',
          titleSnapshot: '入口规划',
          startTime: entryDay
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          endTime: entryDay
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        ),
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: TodoPlanScreen(
            username: PlanAvailabilityFixture.username,
            initialDate: entryDay,
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final grid = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.onPanStart != null &&
            widget.onPanUpdate != null &&
            widget.onPanEnd != null,
      );
      expect(grid, findsOneWidget);
      final rect = tester.getRect(grid);
      await tester.tapAt(
        Offset(rect.left + rect.width * 0.6, rect.top + rect.height * 0.5),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(key('plan-find-time'), findsOneWidget);
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .autoFillEstimateOnTodoChange,
        isTrue,
      );
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      await tester.dragFrom(
        Offset(rect.left + rect.width * 0.5, rect.top + rect.height * 0.6),
        const Offset(70, 50),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(key('plan-find-time'), findsOneWidget);
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .autoFillEstimateOnTodoChange,
        isFalse,
      );
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('入口规划'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .block!
            .id,
        'entry-plan',
      );
      expect(key('plan-find-time'), findsOneWidget);
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        hasLength(1),
      );
      expect(
        await tester.runAsync(
          () => fixture.db.query(
            'op_logs',
            where: 'target_table = ?',
            whereArgs: ['todo_plan_blocks'],
          ),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(() => fixture.dispose());
    }
  });
  testWidgets('正在专注和历史规划不提供推荐改期', (tester) async {
    for (final status in [
      TodoPlanStatus.focusing,
      TodoPlanStatus.finished,
      TodoPlanStatus.cancelled,
      TodoPlanStatus.missed,
      TodoPlanStatus.skipped,
    ]) {
      await showEditor(
        tester,
        saver: identitySaver,
        block: TodoPlanBlock(
          todoId: target.id,
          startTime: day.millisecondsSinceEpoch,
          endTime: day.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          status: status,
        ),
      );
      final button = tester.widget<OutlinedButton>(key('plan-find-time'));
      expect(button.onPressed, isNull);
      expect(find.text('该规划状态不支持推荐改期'), findsOneWidget);
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
    }
  });
  for (final geometry in [
    (const Size(320, 640), 1.6, 260.0, Brightness.light),
    (const Size(390, 844), 2.0, 0.0, Brightness.dark),
    (const Size(720, 360), 1.6, 130.0, Brightness.dark),
    (const Size(1280, 900), 2.0, 0.0, Brightness.light),
  ]) {
    for (final glass in [false, true]) {
      testWidgets(
        '实际编辑器 ${geometry.$1} 字体${geometry.$2} 键盘${geometry.$3} 玻璃$glass 控件可达无溢出',
        (tester) async {
          await LiquidGlassEffectService.setEnabled(glass);
          await showEditor(
            tester,
            saver: identitySaver,
            size: geometry.$1,
            scale: geometry.$2,
            keyboard: geometry.$3,
            brightness: geometry.$4,
          );
          await adopt(tester);
          await tester.ensureVisible(key('plan-save'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tap(tester, 'plan-save');
          await tester.pumpAndSettle();
          expect(find.byType(PlanBlockEditorSheet), findsNothing);
        },
      );
    }
  }
}
