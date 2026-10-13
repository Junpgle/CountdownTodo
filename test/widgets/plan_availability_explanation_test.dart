@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/models/plan_weekly_availability.dart';
import 'package:countdown_todo/screens/plan_availability_explanation_screen.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_continuous_range_service.dart';
import 'package:countdown_todo/services/plan_weekly_availability_preferences.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/services/plan_conflict_review_service.dart';
import 'package:countdown_todo/services/missed_plan_recovery_service.dart';
import 'package:countdown_todo/widgets/plan_availability_panel.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

final day = DateTime(2026, 10, 13), now = DateTime(2026, 10, 12, 7);
final todo = TodoItem(id: 'task', title: '合成75分钟任务');
PlanAvailabilityQuery query() => PlanAvailabilityQuery(
  username: 'diagnostic',
  todoId: 'task',
  date: day,
  minutes: 75,
  windowStart: 540,
  windowEnd: 720,
);
PlanAvailabilitySnapshot snap(PlanAvailabilityQuery q, {bool busy = false}) =>
    PlanAvailabilitySnapshot(
      todo: todo,
      busy: busy
          ? [
              PlanBusyInterval(
                DateTime(q.date.year, q.date.month, q.date.day, 9, 45),
                DateTime(q.date.year, q.date.month, q.date.day, 11, 15),
                source: PlanBusySource.fixedSchedule,
              ),
            ]
          : [],
      coverage: '合成来源；未计入手机日历',
    );
PlanContinuousRangeResult result(PlanAvailabilityQuery q) {
  final queries = [
    for (var i = 1; i <= 7; i++)
      q.onDate(DateTime(q.date.year, q.date.month, q.date.day + i), limit: 5),
  ];
  return PlanContinuousRangeService.find(
    queries,
    queries.map(snap).toList(),
    now: now,
    start: queries.first.date,
    end: DateTime(q.date.year, q.date.month, q.date.day + 8),
    coverage: '合成范围',
  );
}

Finder k(String s) => find.byKey(ValueKey(s));
Future<void> tap(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      180,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> page(
  WidgetTester t, {
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  PlanContinuousRangeLoader? range,
  PlanAvailabilityLoader? loader,
  PlanAvailabilityQuery? q,
  PlanAvailabilitySnapshot? initialSnapshot,
  ValueChanged<PlanExplanationResult?>? returned,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final base = q ?? query();
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
            onPressed: () async {
              final r = await Navigator.push<PlanExplanationResult>(
                c,
                MaterialPageRoute(
                  builder: (_) => PlanAvailabilityExplanationScreen(
                    query: base,
                    snapshot: initialSnapshot ?? snap(base, busy: true),
                    clock: () => now,
                    canSplit: true,
                    loader:
                        loader ??
                        (q, {bool forceRefresh = false}) async =>
                            snap(q, busy: q.date == day),
                    rangeLoader:
                        range ??
                        (q, {bool forceRefresh = false}) async => result(q),
                  ),
                ),
              );
              returned?.call(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tap(t, find.text('open'));
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'current_login_user': 'diagnostic',
    }),
  );
  testWidgets(
    'short fragments are references and later dates load only on request',
    (t) async {
      var reads = 0;
      await page(
        t,
        range: (q, {bool forceRefresh = false}) async {
          reads++;
          return result(q);
        },
      );
      expect(find.text('当前条件下最长45分钟，共90分钟碎片'), findsOneWidget);
      expect(find.text('不足75分钟，仅供参考'), findsNWidgets(2));
      expect(find.text('采用'), findsNothing);
      expect(reads, 0);
      await tap(t, k('plan-following-days'));
      expect(reads, 1);
      expect(find.textContaining('找到5个候选'), findsOneWidget);
      expect(find.textContaining('10月14日—10月20日'), findsOneWidget);
    },
  );
  testWidgets(
    'adopt returns next-day complete selection; no automatic choice',
    (t) async {
      PlanExplanationResult? returned;
      await page(t, returned: (r) => returned = r);
      await tap(t, k('plan-following-days'));
      expect(returned, isNull);
      await tap(t, find.text('采用').first);
      expect(returned!.selection!.query.date, DateTime(2026, 10, 14));
      expect(returned!.selection!.slot.minutes, 75);
    },
  );
  testWidgets(
    'following search uses the range read without a duplicate day read',
    (t) async {
      var dayReads = 0, rangeReads = 0;
      await page(
        t,
        loader: (q, {bool forceRefresh = false}) async {
          dayReads++;
          return snap(q);
        },
        range: (q, {bool forceRefresh = false}) async {
          rangeReads++;
          return result(q);
        },
      );
      await tap(t, k('plan-following-days'));
      expect(dayReads, 0);
      expect(rangeReads, 1);
    },
  );
  testWidgets('new occupancy rejects adopt and clears old choices', (t) async {
    var occupied = false;
    await page(
      t,
      loader: (q, {bool forceRefresh = false}) async {
        if (occupied && q.date != day) {
          return PlanAvailabilitySnapshot(
            todo: todo,
            busy: [
              PlanBusyInterval(
                q.dayStart,
                q.dayEnd,
                source: PlanBusySource.course,
              ),
            ],
            coverage: 'changed',
          );
        }
        return snap(q, busy: q.date == day);
      },
    );
    await tap(t, k('plan-following-days'));
    occupied = true;
    await tap(t, find.text('采用').first);
    expect(find.text('该时段已变化，请重新查找后采用'), findsOneWidget);
    expect(find.text('采用'), findsNothing);
    expect(find.text('查找说明'), findsOneWidget);
  });
  testWidgets('failed range never becomes no-result or partial choices', (
    t,
  ) async {
    await page(
      t,
      range: (q, {bool forceRefresh = false}) async =>
          throw const PlanAvailabilityException(
            '手机日历读取失败，请重试或仅按应用内安排查找',
            canUseAppOnly: true,
          ),
    );
    await tap(t, k('plan-following-days'));
    expect(find.textContaining('手机日历读取失败'), findsOneWidget);
    expect(find.text('采用'), findsNothing);
    expect(find.textContaining('完整范围内未找到'), findsNothing);
  });
  testWidgets('expired search deadline offers neither follow-up nor split', (
    t,
  ) async {
    await page(
      t,
      initialSnapshot: PlanAvailabilitySnapshot(
        todo: TodoItem(
          id: 'task',
          title: '合成任务',
          dueDate: DateTime(2026, 10, 13, 8, 30),
        ),
        busy: const [],
        coverage: '合成来源',
      ),
    );
    expect(k('plan-following-days'), findsNothing);
    expect(k('plan-explanation-split'), findsNothing);
    expect(find.textContaining('截止前已无可用时段'), findsOneWidget);
  });
  testWidgets('account switch rejects old adoption', (t) async {
    await page(t);
    await tap(t, k('plan-following-days'));
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'other',
    );
    await tap(t, find.text('采用').first);
    expect(find.textContaining('账号或成员身份已切换'), findsOneWidget);
    expect(find.text('采用'), findsNothing);
  });
  testWidgets(
    'following range refreshes original diagnostics from one shared snapshot',
    (t) async {
      await page(
        t,
        range: (q, {bool forceRefresh = false}) async {
          final r = result(q);
          return PlanContinuousRangeResult(
            r.start,
            r.end,
            r.coverage,
            r.selections,
            r.unknownTimes,
            currentSnapshot: snap(q),
          );
        },
      );
      await tap(t, k('plan-following-days'));
      expect(find.text('当前条件下最长180分钟，共180分钟碎片'), findsOneWidget);
    },
  );

  testWidgets('member switch invalidates the identity captured on opening', (
    t,
  ) async {
    await page(t);
    await (await SharedPreferences.getInstance()).setInt('current_user_id', 7);
    await tap(t, k('plan-following-days'));
    expect(find.textContaining('账号或成员身份已切换'), findsOneWidget);
    expect(find.text('采用'), findsNothing);
  });

  testWidgets(
    'calendar coverage cannot silently disappear during range search',
    (t) async {
      final q = query(), original = snap(query(), busy: true);
      final included = PlanAvailabilitySnapshot(
        todo: original.todo,
        busy: original.busy,
        coverage: '含手机日历',
        deviceCalendarIncluded: true,
      );
      await t.pumpWidget(
        MaterialApp(
          home: PlanAvailabilityExplanationScreen(
            query: q,
            snapshot: included,
            clock: () => now,
            loader: (q, {bool forceRefresh = false}) async => snap(q),
            rangeLoader: (q, {bool forceRefresh = false}) async {
              final r = result(q);
              return PlanContinuousRangeResult(
                r.start,
                r.end,
                r.coverage,
                r.selections,
                r.unknownTimes,
                currentSnapshot: snap(q),
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, k('plan-following-days'));
      expect(find.textContaining('手机日历读取范围已变化'), findsOneWidget);
      expect(find.text('采用'), findsNothing);
    },
  );

  testWidgets('preference revision invalidates visible choices', (t) async {
    await page(t);
    await tap(t, k('plan-following-days'));
    PlanWeeklyAvailabilityPreferences.revision.value++;
    await t.pumpAndSettle();
    expect(find.text('采用'), findsNothing);
    expect(find.textContaining('安排或条件可能已变化'), findsOneWidget);
  });
  testWidgets('late result after leaving cannot update former page', (t) async {
    final pending = Completer<PlanContinuousRangeResult>();
    PlanExplanationResult? returned;
    await page(
      t,
      range: (q, {bool forceRefresh = false}) => pending.future,
      returned: (r) => returned = r,
    );
    await t.ensureVisible(k('plan-following-days'));
    await t.tap(k('plan-following-days'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.pageBack();
    await t.pumpAndSettle();
    pending.complete(result(query()));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(returned, isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('modify and split return explicit actions without selection', (
    t,
  ) async {
    PlanExplanationResult? returned;
    await page(t, returned: (r) => returned = r);
    await tap(t, k('plan-explanation-split'));
    expect(returned!.action, PlanExplanationAction.split);
    expect(returned!.selection, isNull);
    await page(t, returned: (r) => returned = r);
    await tap(t, k('plan-explanation-modify'));
    expect(returned!.action, PlanExplanationAction.modify);
  });
  for (final spec in [
    (const Size(320, 700), 1.8, Brightness.dark),
    (const Size(720, 360), 1.0, Brightness.light),
    (const Size(1280, 900), 1.0, Brightness.light),
  ]) {
    testWidgets('responsive explanation ${spec.$1} scale ${spec.$2}', (
      t,
    ) async {
      await page(t, size: spec.$1, scale: spec.$2, brightness: spec.$3);
      await tap(t, k('plan-following-days'));
      expect(find.textContaining('找到5个候选'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('compact panel adopts cross-day query and preserves duration', (
    t,
  ) async {
    PlanAvailabilitySelection? selected;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlanAvailabilityPanel(
              username: 'diagnostic',
              todo: todo,
              resultsOnly: true,
              initialDate: day,
              initialMinutes: 75,
              initialQuery: query(),
              clock: () => now,
              loader: (q, {bool forceRefresh = false}) async =>
                  snap(q, busy: q.date == day),
              rangeLoader: (q, {bool forceRefresh = false}) async => result(q),
              onSelected: (s) => selected = s,
              onInvalidated: () {},
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, k('plan-explain-availability'));
    await tap(t, k('plan-following-days'));
    await tap(t, find.text('采用').first);
    expect(selected!.query.date, DateTime(2026, 10, 14));
    expect(selected!.query.minutes, 75);
    expect(find.textContaining('已选用'), findsOneWidget);
  });
  testWidgets('nested custom search can return a later-date selection', (
    t,
  ) async {
    PlanAvailabilitySelection? selected;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlanAvailabilityPanel(
              username: 'diagnostic',
              todo: todo,
              resultsOnly: true,
              initialDate: day,
              initialMinutes: 75,
              initialQuery: query(),
              clock: () => now,
              loader: (q, {bool forceRefresh = false}) async =>
                  snap(q, busy: q.date == day),
              rangeLoader: (q, {bool forceRefresh = false}) async => result(q),
              onSelected: (s) => selected = s,
              onInvalidated: () {},
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, k('plan-find-time'));
    await tap(t, find.text('查找时段'));
    await tap(t, k('plan-explain-availability').last);
    await tap(t, k('plan-following-days'));
    await tap(t, find.text('采用').first);
    expect(selected!.query.date, DateTime(2026, 10, 14));
    expect(
      find.byKey(const ValueKey('plan-custom-search-dialog')),
      findsNothing,
    );
  });
  testWidgets(
    'nested custom explanation returns a split request with current conditions',
    (t) async {
      PlanAvailabilityQuery? requested;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanAvailabilityPanel(
                username: 'diagnostic',
                todo: todo,
                resultsOnly: true,
                initialDate: day,
                initialMinutes: 75,
                initialQuery: query(),
                clock: () => now,
                loader: (q, {bool forceRefresh = false}) async =>
                    snap(q, busy: true),
                onSplitRequested: (q) => requested = q,
                onSelected: (_) {},
                onInvalidated: () {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, k('plan-find-time'));
      await tap(t, find.text('查找时段'));
      await tap(t, k('plan-explain-availability').last);
      await tap(t, k('plan-explanation-split'));
      expect(requested!.minutes, 75);
      expect(requested!.windowStart, 540);
      expect(
        find.byKey(const ValueKey('plan-custom-search-dialog')),
        findsNothing,
      );
    },
  );

  group('real editor', () {
    late PlanAvailabilityFixture f;
    setUp(() async {
      f = PlanAvailabilityFixture();
      await f.initialize();
      debugDefaultTargetPlatformOverride = null;
    });
    tearDown(() async {
      await f.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
    for (final mode in ['backlog', 'conflict', 'recovery']) {
      testWidgets(
        'cross-day adoption from $mode editor preserves fields with zero writes',
        (t) async {
          const identity = PlanTodoIdentity(
            PlanAvailabilityFixture.username,
            0,
          );
          final d = PlanAvailabilityFixture.day;
          final target = TodoItem(id: 'todo-target', title: '复习高数');
          final source = TodoPlanBlock(
            id: 'source-$mode',
            todoId: target.id,
            startTime: DateTime(
              d.year,
              d.month,
              d.day,
              9,
            ).millisecondsSinceEpoch,
            endTime: DateTime(
              d.year,
              d.month,
              d.day,
              10,
              15,
            ).millisecondsSinceEpoch,
            plannedMinutes: 75,
            status: mode == 'recovery'
                ? TodoPlanStatus.missed
                : TodoPlanStatus.planned,
          );
          final old = await PlanWeeklyAvailabilityPreferences.load(
            identity.username,
          );
          await PlanWeeklyAvailabilityPreferences.save(
            identity,
            PlanWeeklyRules(
              enabled: true,
              days: List.generate(7, (_) => [const PlanWeeklyWindow(540, 720)]),
            ),
            expectedKey: old.key,
          );
          await f.fixed(
            'meeting',
            DateTime(d.year, d.month, d.day, 9, 45),
            DateTime(d.year, d.month, d.day, 11, 15),
          );
          final repo = PlanAvailabilityRepository(
            databaseOverride: f.db,
            clock: () => PlanAvailabilityFixture.now,
          );
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlanBlockEditorSheet(
                  username: identity.username,
                  todos: [target],
                  todoGroups: const [],
                  initialTodoId: target.id,
                  fullPage: true,
                  autoRecommendTime: mode != 'conflict',
                  block: mode == 'conflict' ? source : null,
                  conflictEdit: mode == 'conflict'
                      ? PlanConflictEditContext(
                          identity.username,
                          source,
                          target,
                          identity: identity,
                        )
                      : null,
                  recovery: mode == 'recovery'
                      ? MissedPlanRecoveryContext(
                          username: identity.username,
                          source: source,
                          todo: target,
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
                  startTime: DateTime(d.year, d.month, d.day, 9),
                  endTime: DateTime(d.year, d.month, d.day, 10, 15),
                  clock: () => PlanAvailabilityFixture.now,
                  estimate: (_) async => const TimeEstimationResult(
                    estimatedMinutes: 75,
                    confidence: 1,
                    reason: '合成',
                  ),
                  availabilityLoader: repo.read,
                  continuousRangeLoader: repo.readFollowingDays,
                  onSaved: () {},
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.enterText(k('plan-remark'), '保留$mode备注');
          await tap(t, k('plan-explain-availability'));
          await tap(t, k('plan-following-days'));
          await tap(t, find.text('采用').first);
          expect(find.text('保留$mode备注'), findsOneWidget);
          expect(find.textContaining('10-09 · 75 分钟 · 已选用'), findsOneWidget);
          expect(await f.db.query('todo_plan_blocks'), isEmpty);
          expect(await f.db.query('op_logs'), isEmpty);
        },
      );
    }
    testWidgets(
      'real editor fills next day, retains remark and saves exactly once',
      (t) async {
        final identity = const PlanTodoIdentity(
          PlanAvailabilityFixture.username,
          0,
        );
        final old = await PlanWeeklyAvailabilityPreferences.load(
          identity.username,
        );
        await PlanWeeklyAvailabilityPreferences.save(
          identity,
          PlanWeeklyRules(
            enabled: true,
            days: List.generate(7, (_) => [const PlanWeeklyWindow(540, 720)]),
          ),
          expectedKey: old.key,
        );
        final d = PlanAvailabilityFixture.day;
        await f.fixed(
          'meeting',
          DateTime(d.year, d.month, d.day, 9, 45),
          DateTime(d.year, d.month, d.day, 11, 15),
        );
        final repo = PlanAvailabilityRepository(
          databaseOverride: f.db,
          clock: () => PlanAvailabilityFixture.now,
        );
        var saved = 0;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlanBlockEditorSheet(
                username: identity.username,
                todos: [TodoItem(id: 'todo-target', title: '复习高数')],
                todoGroups: const [],
                initialTodoId: 'todo-target',
                fullPage: true,
                autoRecommendTime: true,
                startTime: DateTime(d.year, d.month, d.day, 9),
                endTime: DateTime(d.year, d.month, d.day, 10, 15),
                clock: () => PlanAvailabilityFixture.now,
                estimate: (_) async => const TimeEstimationResult(
                  estimatedMinutes: 75,
                  confidence: 1,
                  reason: '合成',
                ),
                availabilityLoader: repo.read,
                continuousRangeLoader: repo.readFollowingDays,
                saver: (
                  b,
                  s, {
                  int? expectedVersion,
                  int? expectedUpdatedAt,
                  TodoPlanStatus? newStatus,
                }) => repo.save(s!, b, sync: false),
                onSaved: () => saved++,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(k('plan-remark'), '跨日仍保留备注');
        await tap(t, k('plan-explain-availability'));
        await tap(t, k('plan-following-days'));
        await tap(t, find.text('采用').first);
        expect(find.text('跨日仍保留备注'), findsOneWidget);
        expect(await f.db.query('todo_plan_blocks'), isEmpty);
        await tap(t, k('plan-save'));
        final rows = await f.db.query('todo_plan_blocks');
        expect(saved, 1);
        expect(rows, hasLength(1));
        expect(
          rows.single['start_time'],
          DateTime(d.year, d.month, d.day + 1, 9).millisecondsSinceEpoch,
        );
        expect(rows.single['planned_minutes'], 75);
        expect(await f.db.query('op_logs'), hasLength(1));
      },
    );
  });
}
