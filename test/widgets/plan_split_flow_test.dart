@TestOn('vm')
library;

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_split.dart';
import 'package:countdown_todo/screens/plan_split_screen.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_editor_draft_repository.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  late PlanAvailabilityFixture f;
  late TodoItem todo;
  final day = PlanAvailabilityFixture.day, now = PlanAvailabilityFixture.now;
  const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
  Finder key(String k) => find.byKey(ValueKey(k));
  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester t, {
    PlanEditorDraft? draft,
    Size size = const Size(390, 900),
    double scale = 1,
    bool use24Hour = false,
    Brightness brightness = Brightness.light,
    Future<void> Function(TodoPlanBlock, TodoItem)? focus,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        ),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(
            textScaler: TextScaler.linear(scale),
            alwaysUse24HourFormat: use24Hour,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              child: const Text('打开'),
              onPressed: () => showPlanBlockEditorPage<void>(
                context: c,
                builder: (_) => PlanBlockEditorSheet(
                  username: identity.username,
                  fullPage: true,
                  todos: [todo],
                  todoGroups: const [],
                  initialTodoId: todo.id,
                  startTime: day.add(const Duration(hours: 8)),
                  endTime: day.add(const Duration(hours: 9, minutes: 30)),
                  autoFillEstimateOnTodoChange: false,
                  restoredDraft: draft,
                  draftRepository: PlanEditorDraftRepository(
                    database: f.db,
                    clock: () => now,
                  ),
                  clock: () => now,
                  onSaved: () {},
                  startFocus: focus,
                  navigateOnFocus: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tap(t, find.text('打开'));
  }

  Future<void> adopt(WidgetTester t) async {
    await tap(t, key('plan-open-split'));
    await tap(t, key('split-adopt-0'));
  }

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    todo = TodoItem(id: 'todo-target', title: '复习高数');
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await f.dispose();
  });
  testWidgets(
    'adopt entire group is draft only, switching back restores single and common fields',
    (t) async {
      await open(t);
      await adopt(t);
      expect(key('plan-split-preview'), findsOneWidget);
      expect(find.text('保存全部2段'), findsOneWidget);
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      await t.ensureVisible(key('plan-remark'));
      await t.enterText(key('plan-remark'), '共同备注');
      await tap(t, find.text('返回单段'));
      expect(key('plan-split-preview'), findsNothing);
      expect(find.text('90 分钟'), findsOneWidget);
      expect(t.widget<TextField>(key('plan-remark')).controller!.text, '共同备注');
    },
  );
  testWidgets(
    'save group creates exactly two 45 minute blocks and two oplogs',
    (t) async {
      await open(t);
      await adopt(t);
      await tap(t, key('plan-save'));
      final rows = await f.db.query('todo_plan_blocks');
      expect(rows.length, 2);
      expect(rows.map((r) => r['planned_minutes']), [45, 45]);
      expect(await f.db.query('op_logs'), hasLength(2));
      expect(find.text('打开'), findsOneWidget);
    },
  );
  testWidgets(
    'save-and-focus retries only first segment after launch failure',
    (t) async {
      var calls = 0;
      final starts = <TodoPlanBlock>[];
      await open(
        t,
        focus: (b, todo) async {
          calls++;
          starts.add(b);
          if (calls == 1) throw StateError('合成启动失败');
        },
      );
      await adopt(t);
      StorageService.scopedDataRefreshNotifier.notifyListeners();
      await t.pumpAndSettle();
      expect(key('plan-split-stale'), findsOneWidget);
      await tap(t, key('plan-save-focus'));
      expect(await f.db.query('todo_plan_blocks'), hasLength(2));
      expect(starts.single.plannedMinutes, 45);
      expect(key('plan-split-stale'), findsNothing);
      expect(key('plan-split-persisted'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('重试开始第1段'), findsOneWidget);
      expect(t.widget<TextField>(key('plan-remark')).readOnly, isTrue);
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, '返回单段'))
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<DropdownButtonFormField<int>>(
              key('plan-option-每段番茄轮数'),
            )
            .onChanged,
        isNull,
      );
      await tap(t, key('plan-save-focus'));
      expect(calls, 2);
      expect(starts.map((b) => b.id).toSet(), hasLength(1));
      final rows = await f.db.query('todo_plan_blocks');
      expect(rows, hasLength(2));
      expect(
        rows.where((r) => r['status'] == TodoPlanStatus.focusing.index),
        hasLength(1),
      );
    },
  );
  testWidgets(
    'neighbor occupying adopted segment rejects all and does not start focus',
    (t) async {
      var calls = 0;
      await open(
        t,
        focus: (b, t) async {
          calls++;
        },
      );
      await adopt(t);
      await f.fixed(
        'late',
        day.add(const Duration(hours: 8)),
        day.add(const Duration(hours: 9)),
      );
      await tap(t, key('plan-save-focus'));
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      expect(await f.db.query('op_logs'), isEmpty);
      expect(calls, 0);
      expect(key('plan-split-preview'), findsOneWidget);
    },
  );
  testWidgets(
    'moving the first segment later keeps the displayed group chronological',
    (t) async {
      await open(t);
      await adopt(t);
      await tap(t, find.text('调整本段').first);
      await tap(t, find.text('OK').last);
      await tap(t, find.byTooltip('Switch to text input mode'));
      final fields = find.byType(TextField);
      await t.enterText(fields.at(fields.evaluate().length - 2), '10');
      await t.enterText(fields.last, '00');
      await t.tap(find.text('OK').last);
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(find.textContaining('第1段 · 10/8 08:45'), findsOneWidget);
      expect(find.textContaining('第2段 · 10/8 10:00'), findsOneWidget);
    },
  );
  testWidgets(
    'retained group restores actual segments, target ids and common settings',
    (t) async {
      await open(t);
      await adopt(t);
      await tap(t, find.byTooltip('更多操作'));
      await tap(t, find.text('保留草稿'));
      final r = PlanEditorDraftRepository(database: f.db, clock: () => now),
          list = await PlanEditorDraftRepository(database: f.db).list(identity);
      expect(list.single.parts, 2);
      final draft = await r.read(identity, list.single.id);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await open(t, draft: draft);
      expect(key('plan-split-preview'), findsOneWidget);
      expect(find.text('保存全部2段'), findsOneWidget);
      await tap(t, key('plan-save'));
      expect(
        (await f.db.query('todo_plan_blocks')).map((b) => b['uuid']).toSet(),
        draft.fields.split!.ids.toSet(),
      );
      expect(await f.db.query(PlanEditorDraftRepository.table), isEmpty);
    },
  );
  testWidgets(
    'empty split results offer a clear return to continuous planning',
    (t) async {
      await f.fixed(
        'all-day',
        day.add(const Duration(hours: 8)),
        day.add(const Duration(hours: 22)),
      );
      await open(t, size: const Size(320, 900), scale: 1.8);
      await tap(t, key('plan-open-split'));
      expect(key('split-return-single'), findsOneWidget);
      await tap(t, key('split-return-single'));
      expect(key('plan-open-split'), findsOneWidget);
      expect(key('plan-split-preview'), findsNothing);
    },
  );
  testWidgets('missing estimate waits for the user to confirm split duration', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: PlanSplitScreen(
          todo: todo,
          initialQuery: PlanSplitQuery(
            PlanAvailabilityQuery(
              username: identity.username,
              todoId: todo.id,
              date: day,
              minutes: 90,
            ),
          ),
          repository: PlanAvailabilityRepository(
            databaseOverride: f.db,
            clock: () => now,
          ),
          clock: () => now,
          requireDurationConfirmation: true,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('未取得估时，请在修改条件中确认本次总时长'), findsOneWidget);
    expect(key('split-adopt-0'), findsNothing);
    await tap(t, key('split-criteria'));
    await tap(t, key('split-search'));
    expect(key('split-adopt-0'), findsOneWidget);
  });
  for (final spec in [
    (const Size(320, 900), 1.8, Brightness.dark),
    (const Size(1280, 900), 1.0, Brightness.light),
  ]) {
    testWidgets(
      'split results and criteria layout ${spec.$1} scale ${spec.$2}',
      (t) async {
        await open(t, size: spec.$1, scale: spec.$2, brightness: spec.$3);
        await tap(t, key('plan-open-split'));
        expect(t.takeException(), isNull);
        await tap(t, key('split-criteria'));
        expect(t.takeException(), isNull);
        await tap(t, key('split-search'));
        expect(t.takeException(), isNull);
        await tap(t, key('split-adopt-0'));
        expect(t.takeException(), isNull);
        expect(key('plan-split-preview'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'missing estimate requires manual confirmation before any result',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: PlanSplitScreen(
            todo: todo,
            initialQuery: PlanSplitQuery(
              PlanAvailabilityQuery(
                username: identity.username,
                todoId: todo.id,
                date: day,
                minutes: 90,
              ),
            ),
            requireDurationConfirmation: true,
            clock: () => now,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('未取得估时，请在修改条件中确认本次总时长'), findsOneWidget);
      expect(key('split-adopt-0'), findsNothing);
      await tap(t, find.text('确认本次时长'));
      await tap(t, key('split-search'));
      expect(key('split-adopt-0'), findsOneWidget);
    },
  );
  testWidgets(
    'restored split acknowledges a later offset change when the first matches',
    (t) async {
      final slots = [
        PlanTimeSlot(
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 8, minutes: 45)),
        ),
        PlanTimeSlot(
          day.add(const Duration(days: 1, hours: 9)),
          day.add(const Duration(days: 1, hours: 9, minutes: 45)),
        ),
      ];
      final query = PlanSplitQuery(
        PlanAvailabilityQuery(
          username: identity.username,
          todoId: todo.id,
          date: day,
          minutes: 90,
        ),
        days: 2,
      );
      final savedOffsets = PlanSplitDraft(
        query,
        slots,
        ['first', 'second'],
      ).currentZoneOffsets.toList();
      final lastOffset = savedOffsets.length - 1;
      savedOffsets[lastOffset] += savedOffsets[lastOffset] == 14 * 60 ? -60 : 60;
      final r = PlanEditorDraftRepository(database: f.db);
      final d = await r.keep(
        identity,
        PlanDraftFields(
          todoId: todo.id,
          title: todo.title,
          start: slots.first.start.millisecondsSinceEpoch,
          end: slots.first.end.millisecondsSinceEpoch,
          remark: '',
          reminder: 5,
          pomodoro: 25,
          rounds: 0,
          origin: 'timeline',
          offsetMinutes: slots.first.start.timeZoneOffset.inMinutes,
          split: PlanSplitDraft(
            query,
            slots,
            ['first', 'second'],
            savedZoneOffsets: savedOffsets,
          ),
        ),
        targetId: 'first',
      );
      await open(t, draft: d);
      expect(find.text('修改日期'), findsNothing);
      expect(find.text('修改分段条件'), findsOneWidget);
      await tap(t, find.byTooltip('更多操作'));
      await tap(t, find.text('保留草稿'));
      expect((await r.read(identity, d.id)).revision, d.revision);
      expect(find.text('时区已变化，请先确认当前显示的日期与时间'), findsOneWidget);
      await tap(t, key('plan-save'));
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      await tap(t, find.text('确认当前时区时间'));
      await tap(t, key('plan-save'));
      expect(await f.db.query('todo_plan_blocks'), hasLength(2));
    },
  );
  testWidgets(
    'moving second segment before first preserves total and stable draft anchor',
    (t) async {
      final slots = [
        PlanTimeSlot(
          day.add(const Duration(hours: 10)),
          day.add(const Duration(hours: 10, minutes: 45)),
        ),
        PlanTimeSlot(
          day.add(const Duration(hours: 12)),
          day.add(const Duration(hours: 12, minutes: 45)),
        ),
      ];
      final r = PlanEditorDraftRepository(database: f.db);
      final d = await r.keep(
        identity,
        PlanDraftFields(
          todoId: todo.id,
          title: todo.title,
          start: slots.first.start.millisecondsSinceEpoch,
          end: slots.first.end.millisecondsSinceEpoch,
          remark: '',
          reminder: 5,
          pomodoro: 25,
          rounds: 0,
          origin: 'timeline',
          offsetMinutes: slots.first.start.timeZoneOffset.inMinutes,
          split: PlanSplitDraft(
            PlanSplitQuery(
              PlanAvailabilityQuery(
                username: identity.username,
                todoId: todo.id,
                date: day,
                minutes: 90,
              ),
            ),
            slots,
            ['anchor', 'second'],
          ),
        ),
        targetId: 'anchor',
      );
      await open(t, draft: d, use24Hour: true);
      await tap(t, find.text('调整本段').at(1));
      await tap(t, find.text('OK'));
      await tap(t, find.byTooltip('Switch to text input mode'));
      final inputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await t.enterText(inputs.at(0), '8');
      await t.enterText(inputs.at(1), '00');
      await tap(t, find.text('OK'));
      await tap(t, find.byTooltip('更多操作'));
      await tap(t, find.text('保留草稿'));
      final restored = await r.read(identity, d.id);
      expect(restored.targetId, 'anchor');
      expect(restored.fields.split!.ids, ['anchor', 'second']);
      expect(restored.fields.split!.slots.map((s) => s.start.hour), [8, 10]);
      expect(restored.fields.split!.slots.map((s) => s.minutes), [45, 45]);
      expect(await f.db.query('todo_plan_blocks'), isEmpty);
      await tap(t, find.text('返回单段'));
      expect(find.text('放弃已调整的分段？'), findsOneWidget);
    },
  );
}
