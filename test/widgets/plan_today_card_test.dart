@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/screens/plan_block_stats_screen.dart';
import 'package:countdown_todo/services/plan_review_repository.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/widgets/plan_block_today_section.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';

import '../support/plan_availability_fixture.dart';

class _Controlled extends PlanReviewRepository {
  _Controlled(PlanAvailabilityFixture f, DateTime Function() now)
    : super(databaseOverride: f.db, clock: now);
  int reads = 0;
  bool fail = false;
  Completer<PlanTodayCard>? pending;
  @override
  Future<PlanTodayCard> readTodayCard(String username) async {
    reads++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('合成读取故障');
    return super.readTodayCard(username);
  }
}

void main() {
  late PlanAvailabilityFixture f;
  late _Controlled repo;
  late DateTime now;
  late ValueNotifier<int> revision;
  late ValueNotifier<bool> enabled;
  late ValueNotifier<bool> ticking;
  var maintenance = 0, cardTaps = 0;
  final day = DateTime(2026, 10, 8);
  Finder key(String s) => find.byKey(ValueKey(s));
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> action(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.tap(finder);
    await settle(t);
  }

  Future<void> plan(
    String id,
    int hour, {
    TodoPlanStatus status = TodoPlanStatus.planned,
    int minutes = 60,
  }) => f.block(
    TodoPlanBlock(
      id: id,
      todoId: 'todo-target',
      titleSnapshot: '规划$id',
      startTime: day.add(Duration(hours: hour)).millisecondsSinceEpoch,
      endTime: day
          .add(Duration(hours: hour, minutes: minutes))
          .millisecondsSinceEpoch,
      plannedMinutes: minutes,
      status: status,
    ),
  );
  Future<void> open(
    WidgetTester t, {
    Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light,
    Future<void> Function()? maintain,
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
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListenableBuilder(
                listenable: Listenable.merge([revision, enabled, ticking]),
                builder: (c, _) => TickerMode(
                  enabled: ticking.value,
                  child: PlanBlockTodaySection(
                    username: PlanAvailabilityFixture.username,
                    repository: repo,
                    clock: () => now,
                    refreshTrigger: revision.value,
                    enabled: enabled.value,
                    maintain:
                        maintain ??
                        () async {
                          maintenance++;
                        },
                    onTap: () => cardTaps++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(t);
  }

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    await initializeDateFormatting();
    now = DateTime(2026, 10, 8, 12);
    repo = _Controlled(f, () => now);
    revision = ValueNotifier(0);
    enabled = ValueNotifier(true);
    ticking = ValueNotifier(true);
    maintenance = 0;
    cardTaps = 0;
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    revision.dispose();
    enabled.dispose();
    ticking.dispose();
    await f.dispose();
  });

  testWidgets(
    'real home card editor confirms history and presents source-page undo',
    (t) async {
      await plan('p', 9, status: TodoPlanStatus.missed);
      await open(t);
      await action(t, key('plan-today-row-p'));
      await action(t, key('plan-today-edit-p'));
      await action(t, find.byTooltip('更多操作'));
      await action(t, find.text('确认规划已完成'));
      expect(find.text('10月8日 09:00 — 10月8日 10:00'), findsOneWidget);
      await action(t, key('plan-manual-confirm'));
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
      expect(key('plan-manual-undo'), findsOneWidget);
      expect((await f.db.query('todo_plan_blocks')).single['status'], 1);
      await action(t, key('plan-manual-undo'));
      expect((await f.db.query('todo_plan_blocks')).single['status'], 6);
      expect((await f.db.query('op_logs')).length, 2);
    },
  );

  testWidgets(
    'whole card collapses with compact header and remembers account preference',
    (t) async {
      await plan('p', 14);
      await open(t);
      final expandedHeight = t
          .getSize(find.byType(PlanBlockTodaySection))
          .height;
      await action(t, key('plan-today-collapse'));
      expect(key('plan-today-row-p'), findsNothing);
      expect(find.text('今日规划'), findsOneWidget);
      expect(find.byTooltip('规划统计'), findsOneWidget);
      expect(find.byTooltip('展开今日规划'), findsOneWidget);
      expect(
        t.getSize(find.byType(PlanBlockTodaySection)).height,
        lessThan(100),
      );
      expect(
        t.getSize(find.byType(PlanBlockTodaySection)).height,
        lessThan(expandedHeight),
      );
      expect(cardTaps, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(
          'plan_today_collapsed_${PlanAvailabilityFixture.username}',
        ),
        isTrue,
      );
      await t.pumpWidget(const SizedBox.shrink());
      await open(t);
      expect(key('plan-today-row-p'), findsNothing);
      await action(t, key('plan-today-collapse'));
      expect(key('plan-today-row-p'), findsOneWidget);
      expect(
        prefs.getBool(
          'plan_today_collapsed_${PlanAvailabilityFixture.username}',
        ),
        isFalse,
      );
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );

  testWidgets(
    'title toggles collapse without outer navigation and unrelated account preference is ignored',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('plan_today_collapsed_someone-else', true);
      await plan('p', 14);
      await open(
        t,
        size: const Size(320, 700),
        scale: 1.8,
        brightness: Brightness.dark,
      );
      expect(key('plan-today-row-p'), findsOneWidget);
      await action(t, find.text('今日规划'));
      expect(key('plan-today-row-p'), findsNothing);
      expect(cardTaps, 0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'future plans appear before five completed rows; every row expands without records',
    (t) async {
      for (var i = 0; i < 5; i++) {
        await plan('old$i', i + 5, status: TodoPlanStatus.finished);
      }
      await plan('next', 14);
      await plan('later', 16);
      await open(t);
      final visible = t
          .widgetList<InkWell>(
            find.byWidgetPredicate(
              (w) =>
                  w is InkWell &&
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith(
                    'plan-today-row-',
                  ),
            ),
          )
          .map((w) => (w.key as ValueKey<String>).value)
          .toList();
      expect(visible.take(2), ['plan-today-row-next', 'plan-today-row-later']);
      expect(visible.length, 5);
      expect(find.textContaining('达成'), findsNothing);
      await action(t, key('plan-today-row-next'));
      expect(key('plan-today-edit-next'), findsOneWidget);
      expect(find.text('今日已核实投入 0分'), findsOneWidget);
      expect(cardTaps, 0);
      expect(maintenance, 1);
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );
  testWidgets(
    'same-day refresh retains old rows and disables their navigation',
    (t) async {
      await plan('p', 14);
      await open(t);
      final saved = await repo.readTodayCard(PlanAvailabilityFixture.username);
      final pending = Completer<PlanTodayCard>();
      repo.pending = pending;
      final beforeRect = t.getRect(key('plan-today-row-p'));
      revision.value++;
      await t.pump();
      expect(key('plan-today-row-p'), findsOneWidget);
      expect(key('plan-today-updating'), findsOneWidget);
      expect(t.getRect(key('plan-today-row-p')), beforeRect);
      expect(t.widget<InkWell>(key('plan-today-row-p')).onTap, isNull);
      pending.complete(saved);
      repo.pending = null;
      await settle(t);
      expect(t.widget<InkWell>(key('plan-today-row-p')).onTap, isNotNull);
      expect(maintenance, 2);
    },
  );
  testWidgets(
    'read failure retry is local, never reruns maintenance or writes',
    (t) async {
      repo.fail = true;
      await open(t);
      expect(find.textContaining('合成读取故障'), findsOneWidget);
      expect(find.textContaining('暂无可展示'), findsNothing);
      repo.fail = false;
      await action(t, key('plan-today-retry'));
      expect(find.textContaining('今日暂无'), findsOneWidget);
      expect(maintenance, 1);
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );
  testWidgets('hidden ticker or disabled module does not read or maintain', (
    t,
  ) async {
    ticking.value = false;
    await open(t);
    expect(repo.reads, 0);
    expect(maintenance, 0);
    ticking.value = true;
    await settle(t);
    expect(repo.reads, 1);
    expect(maintenance, 1);
    enabled.value = false;
    await settle(t);
    final count = repo.reads;
    now = DateTime(2026, 10, 9, 12);
    await t.pump(const Duration(days: 2));
    expect(repo.reads, count);
    enabled.value = true;
    await settle(t);
    expect(repo.reads, greaterThan(count));
    expect(maintenance, 1);
  });
  testWidgets('display boundary reload does not rerun legacy policy', (
    t,
  ) async {
    await plan('p', 13);
    await open(t);
    final count = repo.reads;
    now = DateTime(2026, 10, 8, 13);
    await t.pump(const Duration(hours: 1));
    await settle(t);
    expect(repo.reads, greaterThan(count));
    expect(maintenance, 1);
    expect(find.text('时段进行中'), findsOneWidget);
  });
  testWidgets(
    'member switch clears previous rows and late old read is rejected',
    (t) async {
      await plan('p', 14);
      await open(t);
      final old = await repo.readTodayCard(PlanAvailabilityFixture.username);
      final pending = Completer<PlanTodayCard>();
      repo.pending = pending;
      revision.value++;
      await t.pump();
      await (await SharedPreferences.getInstance()).setInt(
        'current_user_id',
        8,
      );
      StorageService.triggerRefresh({DataRefreshDomain.all});
      await t.pump(const Duration(milliseconds: 101));
      expect(key('plan-today-row-p'), findsNothing);
      repo.pending = null;
      pending.complete(old);
      await settle(t);
      // It may have already replaced the old request with a fresh member read.
      final current = await repo.readTodayCard(
        PlanAvailabilityFixture.username,
      );
      expect(current.overview.identity.userId, 8);
      expect(cardTaps, 0);
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );
  testWidgets(
    'current projected row opens the actual editor, not outer card navigation',
    (t) async {
      await plan('p', 14);
      await open(t);
      await action(t, key('plan-today-row-p'));
      await action(t, key('plan-today-edit-p'));
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      final editor = t.widget<PlanBlockEditorSheet>(
        find.byType(PlanBlockEditorSheet),
      );
      expect(editor.block!.id, 'p');
      expect(cardTaps, 0);
      await action(t, find.byTooltip('关闭'));
      expect(key('plan-today-row-p'), findsOneWidget);
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );
  testWidgets(
    'focus details preserve exact day/plan and return without business writes',
    (t) async {
      await plan('p', 14);
      await open(t);
      await action(t, key('plan-today-row-p'));
      await action(t, key('plan-today-focus-p'));
      final detail = t.widget<PlanReviewDetailScreen>(
        find.byType(PlanReviewDetailScreen),
      );
      expect(detail.planId, 'p');
      expect(detail.start, day);
      expect(detail.cumulative, isFalse);
      expect(detail.filter, PlanReviewFilter.focus);
      expect(cardTaps, 0);
      await t.pageBack();
      await settle(t);
      expect(key('plan-today-row-p'), findsOneWidget);
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );
  testWidgets(
    'deleted todo stops editing but history is still reachable through records',
    (t) async {
      await plan('p', 14);
      await open(t);
      await f.db.delete('todos');
      await action(t, key('plan-today-row-p'));
      await action(t, key('plan-today-edit-p'));
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
      expect(find.textContaining('待办已不存在'), findsOneWidget);
      await action(t, key('plan-today-retry'));
      await action(t, key('plan-today-row-p'));
      await action(t, key('plan-today-focus-p'));
      expect(find.byType(PlanReviewDetailScreen), findsOneWidget);
      expect(await f.db.query('op_logs'), isEmpty);
    },
  );
  testWidgets(
    'module visibility changes while maintenance is pending cannot strand the loader',
    (t) async {
      final pending = Completer<void>();
      await open(t, maintain: () => pending.future);
      enabled.value = false;
      await t.pump();
      enabled.value = true;
      await t.pump();
      pending.complete();
      await settle(t);
      expect(find.textContaining('今日暂无'), findsOneWidget);
      expect(repo.reads, 1);
    },
  );
  testWidgets(
    'midnight discards yesterday snapshot and refreshes using a local day',
    (t) async {
      now = DateTime(2026, 10, 8, 23, 59);
      await open(t);
      final count = repo.reads;
      now = DateTime(2026, 10, 9);
      await t.pump(const Duration(minutes: 1));
      await settle(t);
      expect(repo.reads, greaterThan(count));
      expect(maintenance, 1);
    },
  );
  for (final setting in [
    (const Size(320, 700), 1.8, Brightness.dark),
    (const Size(390, 844), 1.0, Brightness.light),
    (const Size(720, 360), 1.0, Brightness.light),
    (const Size(1280, 900), 1.8, Brightness.dark),
  ]) {
    testWidgets('bounded card and expanded actions fit $setting', (t) async {
      for (var i = 0; i < 9; i++) {
        await plan('p$i', 14);
      }
      await open(
        t,
        size: setting.$1,
        scale: setting.$2,
        brightness: setting.$3,
      );
      await action(t, key('plan-today-row-p0'));
      await t.ensureVisible(key('plan-today-edit-p0'));
      await t.pump();
      expect(t.takeException(), isNull);
      if (setting.$2 > 1 && setting.$1.width < 400) {
        expect(find.text('查看今日概览'), findsOneWidget);
      }
    });
  }
}
