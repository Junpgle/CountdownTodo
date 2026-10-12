import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/plan_backlog_screen.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/plan_backlog_repository.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

class ControlledRepository extends PlanBacklogRepository {
  ControlledRepository(this.requests);
  final List<Completer<PlanBacklogPage>> requests;
  @override
  Future<PlanBacklogPage> read(
    String username,
    DateTime target, {
    bool scheduled = false,
    String search = '',
    String? folder,
    PlanBacklogCursor? cursor,
  }) {
    final request = Completer<PlanBacklogPage>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  late PlanAvailabilityFixture f;
  final now = PlanAvailabilityFixture.now;
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(1000, 900),
    double scale = 1,
    double keyboard = 0,
    Brightness brightness = Brightness.light,
    DateTime Function()? clock,
    PlanBacklogRepository? repository,
    bool fromTimeline = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
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
        home: fromTimeline
            ? TodoPlanScreen(
                username: PlanAvailabilityFixture.username,
                initialDate: PlanAvailabilityFixture.day,
              )
            : PlanBacklogScreen(
                username: PlanAvailabilityFixture.username,
                date: PlanAvailabilityFixture.day,
                clock: clock ?? () => now,
                repository: repository,
              ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    if (repository is! ControlledRepository) await drain(tester);
  }

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_coach_plan_grid', true);
    await prefs.setBool('tip_shown_todo_plan_guide', true);
    await LiquidGlassEffectService.setEnabled(false);
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await f.dispose();
  });

  testWidgets('expired timed todo cannot be arranged on the same day', (
    tester,
  ) async {
    final deadline = DateTime(2026, 10, 8, 8, 30);
    await f.db.update('todos', {
      'due_date': deadline.millisecondsSinceEpoch,
      'is_all_day': 0,
    });
    var instant = DateTime(2026, 10, 8, 8);
    await show(tester, clock: () => instant);

    expect(find.text('安排'), findsOneWidget);
    instant = deadline.add(const Duration(milliseconds: 1));
    await tester.pump(const Duration(minutes: 30, milliseconds: 1));
    await drain(tester);

    expect(find.textContaining('已截止 · 请先查看待办'), findsOneWidget);
    expect(find.text('安排'), findsNothing);
    expect(find.text('查看／编辑待办'), findsOneWidget);
  });

  testWidgets(
    'formal entry waits for estimation, cancel is zero-write; save once moves to arranged',
    (tester) async {
      await show(tester);
      final before = await f.db.query('op_logs');
      await tester.tap(find.text('安排').first);
      await drain(tester);
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      final editor = tester.widget<PlanBlockEditorSheet>(
        find.byType(PlanBlockEditorSheet),
      );
      expect(editor.fullPage, true);
      expect(editor.autoRecommendTime, true);
      expect(editor.initialTodoId, 'todo-target');
      expect(editor.startTime.day, 8);
      expect(find.textContaining('已选用'), findsOneWidget);
      await tester.pageBack();
      await drain(tester);
      expect(await f.db.query('op_logs'), before);
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      await tester.tap(find.text('安排').first);
      await drain(tester);
      final save = find.byKey(const ValueKey('plan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await drain(tester);
      expect(await f.db.query('todo_plan_blocks'), hasLength(1));
      expect((await f.db.query('op_logs')).length, before.length + 1);
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
      await tester.tap(find.text('已有安排').first);
      await drain(tester);
      expect(find.text('复习高数'), findsOneWidget);
      expect(find.text('查看安排'), findsOneWidget);
    },
  );

  testWidgets(
    'new remote arrangement prompts explicit append; cancellation preserves draft',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('安排').first);
      await drain(tester);
      // Place the remote reservation outside the proposed candidate, so this
      // exercises same-task addition independently of occupancy conflicts.
      await tester.runAsync(
        () => f.block(
          TodoPlanBlock(
            id: 'remote-new',
            todoId: 'todo-target',
            startTime: DateTime(2026, 10, 9, 18).millisecondsSinceEpoch,
            endTime: DateTime(2026, 10, 9, 19).millisecondsSinceEpoch,
          ),
        ),
      );
      final save = find.byKey(const ValueKey('plan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await drain(tester);
      expect(find.text('此待办已有新的安排'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await drain(tester);
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(await f.db.query('todo_plan_blocks'), hasLength(1));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await drain(tester);
      await tester.tap(find.text('仍追加这次规划'));
      await drain(tester);
      expect(await f.db.query('todo_plan_blocks'), hasLength(2));
      expect(await f.db.query('op_logs'), hasLength(1));
    },
  );

  testWidgets(
    'completed during editing rejects without writing and keeps draft',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('安排').first);
      await drain(tester);
      await tester.runAsync(() => f.db.update('todos', {'is_completed': 1}));
      final save = find.byKey(const ValueKey('plan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await drain(tester);
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(find.text('待办已完成或失效，请选择未完成的待办'), findsOneWidget);
      expect(await f.db.query('op_logs'), isEmpty);
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
    },
  );

  for (final mutation in [
    'is_deleted',
    'has_conflict',
    'member',
    'focus',
    'oplog',
  ]) {
    testWidgets('formal save rejects $mutation and retains draft', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.text('安排').first);
      await drain(tester);
      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        switch (mutation) {
          case 'member':
            await prefs.setInt('current_user_id', 99);
          case 'focus':
            await prefs.setString(
              'pomodoro_run_state_${PlanAvailabilityFixture.username}',
              jsonEncode(
                PomodoroRunState(
                  phase: PomodoroPhase.focusing,
                  todoUuid: 'todo-target',
                ).toJson(),
              ),
            );
          case 'oplog':
            await f.db.execute(
              "CREATE TRIGGER fail_log BEFORE INSERT ON op_logs BEGIN SELECT RAISE(ABORT,'synthetic'); END",
            );
          default:
            await f.db.update('todos', {mutation: 1});
        }
      });
      final save = find.byKey(const ValueKey('plan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await drain(tester);
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-save-error')), findsOneWidget);
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      expect(await f.db.query('op_logs'), isEmpty);
    });
  }
  testWidgets(
    'independent member can plan with global completed and own unfinished',
    (tester) async {
      await f.db.update('todos', {'collab_type': 1, 'is_completed': 1});
      await f.db.insert('todo_completions', {
        'todo_uuid': 'todo-target',
        'user_id': 0,
        'is_completed': 0,
      });
      await show(tester);
      await tester.tap(find.text('安排').first);
      await drain(tester);
      expect(find.textContaining('已选用'), findsOneWidget);
      final save = find.byKey(const ValueKey('plan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await drain(tester);
      expect(await f.db.query('todo_plan_blocks'), hasLength(1));
      expect(await f.db.query('op_logs'), hasLength(1));
    },
  );
  testWidgets('expired deadline only offers view', (tester) async {
    await f.db.update('todos', {
      'due_date': DateTime(2026, 10, 7, 20).millisecondsSinceEpoch,
    });
    await show(tester);
    expect(find.text('安排'), findsNothing);
    expect(find.text('查看／编辑待办'), findsOneWidget);
    expect(find.textContaining('截止早于目标日期'), findsOneWidget);
  });

  testWidgets(
    'manual new plan uses member completion and rejects later member completion',
    (tester) async {
      await f.db.update('todos', {'collab_type': 1, 'is_completed': 1});
      await f.db.insert('todo_completions', {
        'todo_uuid': 'todo-target',
        'user_id': 0,
        'is_completed': 0,
      });
      final identity = await PlanTodoIdentity.capture(
        PlanAvailabilityFixture.username,
      );
      final todo = await PlanTodoGuard.read(f.db, identity, 'todo-target');
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PlanBlockEditorSheet(
            username: identity.username,
            startTime: PlanAvailabilityFixture.day.add(
              const Duration(hours: 10),
            ),
            endTime: PlanAvailabilityFixture.day.add(const Duration(hours: 11)),
            todos: [todo],
            todoGroups: const [],
            initialTodoId: todo.id,
            autoFillEstimateOnTodoChange: false,
            fullPage: true,
            clock: () => now,
            onSaved: () => saved = true,
          ),
        ),
      );
      addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
      await drain(tester);
      await tester.runAsync(
        () => f.db.update('todo_completions', {'is_completed': 1}),
      );
      final save = find.byKey(const ValueKey('plan-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await drain(tester);
      expect(find.byKey(const ValueKey('plan-save-error')), findsOneWidget);
      expect(saved, false);
      expect(await f.db.query('op_logs'), isEmpty);
      await tester.runAsync(
        () => f.db.update('todo_completions', {'is_completed': 0}),
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await drain(tester);
      expect(saved, true);
      expect(await f.db.query('todo_plan_blocks'), hasLength(1));
      expect(await f.db.query('op_logs'), hasLength(1));
    },
  );
  testWidgets('past target opens today with visible explanation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlanBacklogScreen(
          username: PlanAvailabilityFixture.username,
          date: DateTime(2026, 10, 1),
          clock: () => now,
        ),
      ),
    );
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    await drain(tester);
    expect(find.text('原规划日期已过去，目标日期已切换到今天'), findsOneWidget);
    expect(find.text('目标：10月7日'), findsOneWidget);

    await tester.tap(find.text('目标：10月7日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('目标：10月8日'), findsOneWidget);
    expect(find.text('原规划日期已过去，目标日期已切换到今天'), findsNothing);
  });
  testWidgets(
    'old requests cannot overwrite search or retry and read failure is explicit',
    (tester) async {
      final requests = <Completer<PlanBacklogPage>>[];
      final actual = await const PlanBacklogRepository().read(
        PlanAvailabilityFixture.username,
        PlanAvailabilityFixture.day,
      );
      await show(tester, repository: ControlledRepository(requests));
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pump(const Duration(milliseconds: 300));
      expect(requests, hasLength(2));
      requests[1].completeError(StateError('合成读取故障'));
      await tester.pumpAndSettle();
      expect(find.textContaining('清单读取失败'), findsOneWidget);
      requests[0].complete(actual);
      await tester.pumpAndSettle();
      expect(find.text('复习高数'), findsNothing);
      await tester.tap(find.text('重试'));
      await tester.pump();
      requests[2].complete(actual);
      await tester.pumpAndSettle();
      expect(find.text('复习高数'), findsOneWidget);
    },
  );

  testWidgets(
    'search persists across tabs and literal percent does not match every task',
    (tester) async {
      await f.todo('literal-task', '进度100%_完成');
      await show(tester);
      await tester.enterText(find.byType(TextField), '%_');
      await drain(tester);
      expect(find.text('进度100%_完成'), findsOneWidget);
      expect(find.text('复习高数'), findsNothing);
      await tester.tap(find.text('已有安排'));
      await drain(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '%_',
      );
      expect(find.text('没有符合筛选条件的待办'), findsOneWidget);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(720, 360),
    const Size(1280, 900),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'queue usable without overflow $size $brightness large type keyboard',
        (tester) async {
          await LiquidGlassEffectService.setEnabled(
            brightness == Brightness.dark,
          );
          await show(
            tester,
            size: size,
            scale: 1.8,
            keyboard: 120,
            brightness: brightness,
          );
          await tester.scrollUntilVisible(
            find.text('安排'),
            140,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byType(TextField),
            -140,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(find.byType(TextField), '复习');
          await drain(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    '320 large-type toolbar keeps date and backlog reachable, day navigation in more',
    (tester) async {
      await show(
        tester,
        size: const Size(320, 640),
        scale: 1.8,
        fromTimeline: true,
      );
      expect(find.text('10/8'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('前一天'), findsOneWidget);
      expect(find.text('后一天'), findsOneWidget);
      await tester.tap(find.text('后一天'));
      await drain(tester);
      expect(find.text('10/9'), findsOneWidget);
      await tester.tap(find.byTooltip('待规划'));
      await drain(tester);
      expect(find.byType(PlanBacklogScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
