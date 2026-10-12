@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_split.dart';
import 'package:countdown_todo/models/plan_weekly_availability.dart';
import 'package:countdown_todo/screens/plan_weekly_availability_screen.dart';
import 'package:countdown_todo/services/plan_weekly_availability_preferences.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/services/missed_plan_recovery_service.dart';
import 'package:countdown_todo/services/plan_conflict_review_service.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/services/plan_editor_draft_repository.dart';
import 'package:countdown_todo/widgets/plan_availability_panel.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/plan_availability_fixture.dart';

class FailingStore extends InMemorySharedPreferencesStore {
  FailingStore() : super.withData({'flutter.current_login_user': 'weekly'});
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

Finder key(String s) => find.byKey(ValueKey(s));
Future<void> tap(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      180,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> host(
  WidgetTester t, {
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
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
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              c,
              MaterialPageRoute(
                builder: (_) =>
                    const PlanWeeklyAvailabilityScreen(username: 'weekly'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tap(t, find.text('open'));
}

Future<void> install(String username, {bool empty = false}) async {
  final loaded = await PlanWeeklyAvailabilityPreferences.load(username);
  await PlanWeeklyAvailabilityPreferences.save(
    PlanTodoIdentity(username, 0),
    PlanWeeklyRules(
      enabled: true,
      days: List.generate(
        7,
        (_) =>
            empty ? <PlanWeeklyWindow>[] : [const PlanWeeklyWindow(540, 720)],
      ),
    ),
    expectedKey: loaded.key,
  );
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'current_login_user': 'weekly',
    }),
  );
  testWidgets(
    'template changes only draft, leaves weekends and enabled state; cancel protects edits',
    (t) async {
      await host(t);
      expect(find.text('全天'), findsNWidgets(7));
      await tap(t, key('weekly-template'));
      expect(find.text('09:00–12:00  14:00–18:00'), findsNWidgets(5));
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly')).rules!.enabled,
        isFalse,
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tap(t, find.text('继续编辑'));
      expect(find.text('每周可安排时间'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(t, find.text('放弃修改'));
      expect(find.text('open'), findsOneWidget);
    },
  );
  testWidgets(
    'day none, copy to chosen weekday, and one save persist complete draft',
    (t) async {
      await host(t);
      await tap(t, key('weekly-enabled'));
      await tap(t, key('weekly-day-0'));
      await tap(t, key('weekly-mode-none'));
      await tap(t, key('weekly-day-apply'));
      await tap(t, key('weekly-copy'));
      await tap(t, find.widgetWithText(CheckboxListTile, '周二'));
      await tap(t, find.text('填入草稿'));
      expect(find.text('不推荐'), findsNWidgets(2));
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly'))
            .rules!
            .days
            .first,
        isNotEmpty,
      );
      await tap(t, key('weekly-save'));
      final saved = (await PlanWeeklyAvailabilityPreferences.load('weekly'))
          .rules!;
      expect(saved.enabled, isTrue);
      expect(saved.days[0], isEmpty);
      expect(saved.days[1], isEmpty);
      expect(saved.days[2], isNotEmpty);
    },
  );
  testWidgets(
    'stale settings page retains input and rejects overwriting another editor',
    (t) async {
      await host(t);
      await tap(t, key('weekly-template'));
      await install('weekly', empty: true);
      await tap(t, key('weekly-save'));
      expect(find.text('每周可安排时间已变化，请重新读取后再编辑'), findsOneWidget);
      expect(find.text('09:00–12:00  14:00–18:00'), findsWidgets);
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly'))
            .rules!
            .days
            .first,
        isEmpty,
      );
    },
  );
  testWidgets('failed write keeps settings draft and announces no success', (
    t,
  ) async {
    SharedPreferencesStorePlatform.instance = FailingStore();
    SharedPreferences.resetStatic();
    await host(t);
    await tap(t, key('weekly-enabled'));
    await tap(t, key('weekly-save'));
    expect(find.text('每周可安排时间保存失败，修改仍保留在页面'), findsOneWidget);
    expect(t.widget<SwitchListTile>(key('weekly-enabled')).value, isTrue);
    expect(
      (await PlanWeeklyAvailabilityPreferences.load('weekly')).rules!.enabled,
      isFalse,
    );
  });
  testWidgets(
    'corrupt settings require explicit reset; no silent fallback or write',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        PlanWeeklyAvailabilityPreferences.storageKey('weekly'),
        '{',
      );
      await host(t);
      expect(key('weekly-enabled'), findsNothing);
      expect(
        prefs.getString(PlanWeeklyAvailabilityPreferences.storageKey('weekly')),
        '{',
      );
      await tap(t, key('weekly-repair'));
      expect(key('weekly-enabled'), findsOneWidget);
      expect(
        prefs.getString(PlanWeeklyAvailabilityPreferences.storageKey('weekly')),
        '{',
      );
      await tap(t, key('weekly-save'));
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly')).error,
        isNull,
      );
    },
  );
  for (final config in [
    (const Size(320, 700), 1.8, Brightness.light),
    (const Size(390, 844), 1.0, Brightness.dark),
    (const Size(1280, 900), 1.0, Brightness.light),
  ]) {
    testWidgets(
      'responsive settings/day editor ${config.$1} font ${config.$2}',
      (t) async {
        await host(t, size: config.$1, scale: config.$2, brightness: config.$3);
        await tap(t, key('weekly-day-0'));
        await tap(t, key('weekly-mode-custom'));
        for (var i = 0; i < 3; i++) {
          await tap(t, key('weekly-add-window'));
        }
        if (key('weekly-add-window').evaluate().isEmpty) {
          await t.scrollUntilVisible(
            key('weekly-add-window'),
            180,
            scrollable: find.byType(Scrollable).last,
          );
        }
        final add = t.widget<TextButton>(key('weekly-add-window'));
        expect(add.onPressed, isNull);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        expect(t.takeException(), isNull);
        await tap(t, key('weekly-day-apply'));
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'panel excluded day offers explicit one-time exemption, keeps other constraints',
    (t) async {
      await install('weekly', empty: true);
      PlanAvailabilitySelection? chosen;
      final day = DateTime(2026, 10, 12),
          todo = TodoItem(id: 'target', title: '合成待办');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanAvailabilityPanel(
                username: 'weekly',
                todo: todo,
                initialDate: day,
                initialMinutes: 60,
                clock: () => DateTime(2026, 10, 11),
                initialExpanded: true,
                onInvalidated: () {},
                onSelected: (s) => chosen = s,
                loader: (q, {bool forceRefresh = false}) async =>
                    PlanAvailabilitySnapshot(
                      todo: todo,
                      busy: const [],
                      coverage: 'synthetic',
                    ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, key('plan-lookup-slots'));
      expect(find.text('周一未设置可安排时间'), findsOneWidget);
      await tap(t, key('plan-weekly-ignore'));
      await tap(t, key('plan-lookup-slots'));
      await tap(
        t,
        key('plan-slot-${DateTime(2026, 10, 12, 8).millisecondsSinceEpoch}'),
      );
      expect(chosen!.query.weekly!.ignored, isTrue);
      expect(chosen!.query.minutes, 60);
      expect(
        (await PlanWeeklyAvailabilityPreferences.load('weekly'))
            .rules!
            .days
            .first,
        isEmpty,
      );
    },
  );
  testWidgets(
    'changed rule invalidates a pending asynchronous recommendation',
    (t) async {
      final pending = Completer<PlanAvailabilitySnapshot>(),
          todo = TodoItem(id: 'target', title: 'test');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanAvailabilityPanel(
                username: 'weekly',
                todo: todo,
                initialDate: DateTime(2026, 10, 12),
                initialMinutes: 60,
                clock: () => DateTime(2026, 10, 11),
                initialExpanded: true,
                onInvalidated: () {},
                onSelected: (_) {},
                loader: (q, {bool forceRefresh = false}) => pending.future,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(key('plan-lookup-slots'));
      await t.tap(key('plan-lookup-slots'));
      await t.pump();
      await install('weekly', empty: true);
      await t.pumpAndSettle();
      pending.complete(
        PlanAvailabilitySnapshot(todo: todo, busy: const [], coverage: 'stale'),
      );
      await t.pumpAndSettle();
      expect(find.text('stale'), findsNothing);
      expect(find.textContaining('采用此时段'), findsNothing);
    },
  );
  testWidgets(
    'returning from unchanged weekly settings keeps selected recommendation',
    (t) async {
      await install('weekly');
      final todo = TodoItem(id: 'target', title: 'test');
      var invalidations = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanAvailabilityPanel(
                username: 'weekly',
                todo: todo,
                initialDate: DateTime(2026, 10, 12),
                initialMinutes: 60,
                clock: () => DateTime(2026, 10, 11),
                resultsOnly: true,
                autoLookupAndSelect: true,
                onInvalidated: () => invalidations++,
                onSelected: (_) {},
                loader: (q, {bool forceRefresh = false}) async =>
                    PlanAvailabilitySnapshot(
                      todo: todo,
                      busy: const [],
                      coverage: 'synthetic',
                    ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('已选用'), findsOneWidget);
      final before = invalidations;
      await tap(t, key('plan-weekly-settings'));
      await tap(t, find.byType(BackButton));
      expect(invalidations, before);
      expect(find.textContaining('已选用'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  group('draft restoration', () {
    late PlanAvailabilityFixture f;
    late PlanEditorDraftRepository drafts;
    const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
    setUp(() async {
      f = PlanAvailabilityFixture();
      await f.initialize();
      debugDefaultTargetPlatformOverride = null;
      drafts = PlanEditorDraftRepository(
        database: f.db,
        clock: () => PlanAvailabilityFixture.now,
      );
    });
    tearDown(() async {
      await f.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
    Future<void> openDraft(
      WidgetTester t, {
      required String mode,
      bool ignored = false,
      bool changed = false,
      bool split = false,
    }) async {
      final old = await PlanWeeklyAvailabilityPreferences.load(
            identity.username,
          ),
          day = PlanAvailabilityFixture.day;
      final splitDraft = split
          ? PlanSplitDraft(
              PlanSplitQuery(
                PlanAvailabilityQuery(
                  username: identity.username,
                  todoId: 'todo-target',
                  date: day,
                  minutes: 90,
                ),
                maximum: 45,
              ),
              [
                PlanTimeSlot(
                  DateTime(day.year, day.month, day.day, 9),
                  DateTime(day.year, day.month, day.day, 9, 45),
                ),
                PlanTimeSlot(
                  DateTime(day.year, day.month, day.day, 14),
                  DateTime(day.year, day.month, day.day, 14, 45),
                ),
              ],
              ['draft-target', 'draft-second'],
            )
          : null;
      final saved = await drafts.keep(
        identity,
        PlanDraftFields(
          todoId: 'todo-target',
          title: '复习高数',
          start: DateTime(
            day.year,
            day.month,
            day.day,
            9,
          ).millisecondsSinceEpoch,
          end: DateTime(
            day.year,
            day.month,
            day.day,
            split ? 9 : 10,
            split ? 45 : 0,
          ).millisecondsSinceEpoch,
          remark: '保留备注',
          reminder: 5,
          pomodoro: 25,
          rounds: 2,
          origin: 'todo',
          offsetMinutes: day.timeZoneOffset.inMinutes,
          scheduleOrigin: mode,
          weeklyKey: old.key,
          weeklyIgnored: ignored,
          split: splitDraft,
        ),
        targetId: 'draft-target',
      );
      if (changed) await install(identity.username, empty: true);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlanBlockEditorSheet(
              username: identity.username,
              fullPage: true,
              restoredDraft: saved,
              draftRepository: drafts,
              todos: [TodoItem(id: 'todo-target', title: '复习高数')],
              todoGroups: const [],
              startTime: DateTime(day.year, day.month, day.day, 9),
              endTime: DateTime(day.year, day.month, day.day, 10),
              initialTodoId: 'todo-target',
              onSaved: () {},
              clock: () => PlanAvailabilityFixture.now,
              availabilityLoader: (q, {bool forceRefresh = false}) async =>
                  PlanAvailabilitySnapshot(
                    todo: TodoItem(id: 'todo-target', title: '复习高数'),
                    busy: const [],
                    coverage: 'synthetic',
                  ),
              saver: (
                b,
                s, {
                int? expectedVersion,
                int? expectedUpdatedAt,
                TodoPlanStatus? newStatus,
              }) async => b,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets(
      'changed recommended draft preserves fields and requires re-search or manual conversion',
      (t) async {
        await openDraft(t, mode: 'recommended', changed: true);
        await tap(t, key('plan-save'));
        expect(find.textContaining('草稿的每周可安排时间已变化'), findsOneWidget);
        expect(find.text('保留备注'), findsOneWidget);
        await tap(t, key('plan-draft-use-manual'));
        await tap(t, key('plan-save'));
        expect(find.textContaining('草稿的每周可安排时间已变化'), findsNothing);
      },
    );
    testWidgets('one-query weekly exemption is not silently restored', (
      t,
    ) async {
      await openDraft(t, mode: 'recommended', ignored: true);
      await tap(t, key('plan-save'));
      expect(find.textContaining('草稿的本次不使用每周规则已失效'), findsOneWidget);
    });
    for (final ignored in [false, true]) {
      testWidgets(
        'split draft revalidates weekly policy and exemption $ignored',
        (t) async {
          await openDraft(
            t,
            mode: 'recommended',
            split: true,
            changed: !ignored,
            ignored: ignored,
          );
          await tap(t, key('plan-save'));
          expect(
            find.textContaining(ignored ? '草稿的本次不使用每周规则已失效' : '草稿的每周可安排时间已变化'),
            findsOneWidget,
          );
          expect(find.text('保留备注'), findsOneWidget);
          expect(await f.db.query('todo_plan_blocks'), isEmpty);
          expect(await f.db.query('op_logs'), isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets('manual draft stays manual outside newly excluded weekday', (
      t,
    ) async {
      await openDraft(t, mode: 'manual', changed: true);
      await tap(t, key('plan-save'));
      expect(find.textContaining('草稿的每周可安排时间已变化'), findsNothing);
      expect(t.takeException(), isNull);
    });
    for (final mode in ['todo', 'backlog', 'conflict', 'recovery']) {
      testWidgets(
        'weekly policy applies to $mode editor recommendations without writes',
        (t) async {
          final old = await PlanWeeklyAvailabilityPreferences.load(
            identity.username,
          );
          await PlanWeeklyAvailabilityPreferences.save(
            identity,
            PlanWeeklyRules(
              enabled: true,
              days: List.generate(
                7,
                (_) => [const PlanWeeklyWindow(840, 1020)],
              ),
            ),
            expectedKey: old.key,
          );
          final todo = TodoItem(id: 'todo-target', title: '复习高数'),
              day = PlanAvailabilityFixture.day;
          final source = TodoPlanBlock(
            id: 'source-$mode',
            todoId: todo.id,
            startTime: DateTime(
              day.year,
              day.month,
              day.day,
              9,
            ).millisecondsSinceEpoch,
            endTime: DateTime(
              day.year,
              day.month,
              day.day,
              10,
              15,
            ).millisecondsSinceEpoch,
            plannedMinutes: 75,
            status: mode == 'recovery'
                ? TodoPlanStatus.missed
                : TodoPlanStatus.planned,
          );
          final queries = <PlanAvailabilityQuery>[];
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlanBlockEditorSheet(
                  username: identity.username,
                  fullPage: true,
                  todos: [todo],
                  todoGroups: const [],
                  initialTodoId: todo.id,
                  block: mode == 'conflict' ? source : null,
                  conflictEdit: mode == 'conflict'
                      ? PlanConflictEditContext(
                          identity.username,
                          source,
                          todo,
                          identity: identity,
                        )
                      : null,
                  recovery: mode == 'recovery'
                      ? MissedPlanRecoveryContext(
                          username: identity.username,
                          source: source,
                          todo: todo,
                          followups: const [],
                          hasCurrentFocus: false,
                          identity: identity,
                        )
                      : null,
                  backlogContext: mode == 'backlog'
                      ? const PlanBacklogSaveContext(
                          identity,
                          'todo-target',
                          '[]',
                        )
                      : null,
                  startTime: DateTime(day.year, day.month, day.day, 9),
                  endTime: DateTime(day.year, day.month, day.day, 10, 15),
                  autoRecommendTime: mode != 'conflict',
                  estimate: (_) async => const TimeEstimationResult(
                    estimatedMinutes: 75,
                    confidence: 1,
                    reason: 'synthetic',
                  ),
                  clock: () => PlanAvailabilityFixture.now,
                  onSaved: () {},
                  availabilityLoader: (q, {bool forceRefresh = false}) async {
                    queries.add(q);
                    return PlanAvailabilitySnapshot(
                      todo: todo,
                      busy: const [],
                      coverage: 'synthetic',
                    );
                  },
                  saver: (
                    b,
                    s, {
                    int? expectedVersion,
                    int? expectedUpdatedAt,
                    TodoPlanStatus? newStatus,
                  }) async => b,
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(queries, isNotEmpty);
          expect(queries.last.weekly!.active, isTrue);
          expect(queries.last.minutes, 75);
          expect(find.text('14:00–15:15'), findsOneWidget);
          expect(
            queries.last.excludeBlockId,
            mode == 'conflict' ? source.id : null,
          );
          expect(await f.db.query('todo_plan_blocks'), isEmpty);
          expect(await f.db.query('op_logs'), isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
  });
}
