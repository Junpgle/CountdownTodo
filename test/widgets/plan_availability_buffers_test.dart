import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_availability_preferences.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/widgets/plan_availability_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Uses the already resolved plugin interface to simulate disk-write failure.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

final day = DateTime(2026, 10, 12), now = DateTime(2026, 10, 11, 7);
final todo = TodoItem(id: 'buffer-task', title: '复习高数');
Finder key(String s) => find.byKey(ValueKey(s));
Finder buffer(String side, int value) => find.byWidgetPredicate(
  (w) =>
      w is DropdownButton<int> &&
      w.key == ValueKey('plan-buffer-$side') &&
      w.value == value,
);
PlanAvailabilitySnapshot sources() => PlanAvailabilitySnapshot(
  todo: todo,
  busy: [
    PlanBusyInterval(
      DateTime(2026, 10, 12, 9),
      DateTime(2026, 10, 12, 10),
      source: PlanBusySource.course,
    ),
  ],
  coverage: '合成课程',
);
Future<void> action(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> pick(
  WidgetTester t,
  String side,
  int previous,
  String value,
) async {
  await action(t, buffer(side, previous));
  await action(t, find.text(value).last);
}

Future<void> host(
  WidgetTester t, {
  bool results = false,
  String username = 'buffers',
  PlanAvailabilityLoader? loader,
  ValueChanged<PlanAvailabilitySelection>? selected,
  ValueChanged<PlanAvailabilityQuery>? changed,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlanAvailabilityPanel(
            username: username,
            todo: todo,
            initialDate: day,
            initialMinutes: 30,
            initialExpanded: true,
            resultsOnly: results,
            clock: () => now,
            loader:
                loader ?? (q, {bool forceRefresh = false}) async => sources(),
            onSelected: selected ?? (_) {},
            onQueryChanged: changed,
            onInvalidated: () {},
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> remember(int before, int after) =>
    PlanAvailabilityPreferences.save(
      'buffers',
      PlanAvailabilityPreferences.defaultWindows,
      {},
      bufferBefore: before,
      bufferAfter: after,
    );

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'changing a buffer preserves focused dropdown state through menu dismissal',
    (t) async {
      await host(t);
      final before = t.state(buffer('before', 0));
      await pick(t, 'before', 0, '10 分钟');
      expect(t.state(buffer('before', 10)), same(before));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'buffer controls live in custom dialog; defaults restore before automatic query',
    (t) async {
      await remember(10, 5);
      final queries = <PlanAvailabilityQuery>[];
      await host(
        t,
        results: true,
        loader: (q, {bool forceRefresh = false}) async {
          queries.add(q);
          return sources();
        },
      );
      expect(queries.single.bufferBefore, 10);
      expect(queries.single.bufferAfter, 5);
      expect(buffer('before', 10), findsNothing);
      expect(find.text('已按开始前10分钟、结束后5分钟查找'), findsOneWidget);
      await action(t, key('plan-find-time'));
      expect(buffer('before', 10), findsOneWidget);
      expect(buffer('after', 5), findsOneWidget);
    },
  );
  testWidgets(
    'changing either side persists and lookup carries both; next account starts zero',
    (t) async {
      PlanAvailabilityQuery? query;
      await host(t, changed: (q) => query = q);
      await pick(t, 'before', 0, '10 分钟');
      await pick(t, 'after', 0, '5 分钟');
      await action(t, key('plan-lookup-slots'));
      expect(query!.bufferBefore, 10);
      expect(query!.bufferAfter, 5);
      expect(
        (await PlanAvailabilityPreferences.load('buffers')).bufferKey,
        '10:5',
      );
      await host(t, username: 'other', changed: (q) => query = q);
      expect(query!.bufferBefore, 0);
      expect(query!.bufferAfter, 0);
    },
  );
  testWidgets(
    'custom interval rejects negative decimal and overflow, preserves value on cancel',
    (t) async {
      await host(t);
      await pick(t, 'before', 0, '自定义…');
      for (final value in ['-1', '1.5', '121']) {
        await t.enterText(key('plan-buffer-custom-input'), value);
        await action(t, key('plan-buffer-custom-confirm'));
        expect(find.text('请输入0–120的整数'), findsOneWidget);
      }
      await t.enterText(key('plan-buffer-custom-input'), '17');
      await action(t, key('plan-buffer-custom-confirm'));
      expect(buffer('before', 17), findsOneWidget);
      await pick(t, 'before', 17, '自定义…');
      await action(t, find.text('取消'));
      expect(buffer('before', 17), findsOneWidget);
      expect(
        (await PlanAvailabilityPreferences.load('buffers')).bufferKey,
        '17:0',
      );
    },
  );
  testWidgets(
    'cancel custom search reloads changed defaults without choosing a time',
    (t) async {
      final selections = <PlanAvailabilitySelection>[];
      final queries = <PlanAvailabilityQuery>[];
      await host(
        t,
        results: true,
        selected: selections.add,
        changed: queries.add,
      );
      await action(t, key('plan-find-time'));
      await pick(t, 'before', 0, '15 分钟');
      await action(t, find.byTooltip('关闭自定义查找'));
      expect(selections, isEmpty);
      expect(queries.last.bufferBefore, 15);
      expect(find.text('已按开始前15分钟、结束后0分钟查找'), findsOneWidget);
      expect(buffer('before', 15), findsNothing);
    },
  );
  testWidgets(
    'empty results never reduce buffers automatically; explicit zero is one query only',
    (t) async {
      await remember(120, 120);
      final queries = <PlanAvailabilityQuery>[];
      final selections = <PlanAvailabilitySelection>[];
      await host(
        t,
        results: true,
        selected: selections.add,
        loader: (q, {bool forceRefresh = false}) async {
          queries.add(q);
          return PlanAvailabilitySnapshot(
            todo: todo,
            coverage: '合成',
            busy: [
              PlanBusyInterval(
                DateTime(2026, 10, 12, 7),
                DateTime(2026, 10, 12, 21),
                source: PlanBusySource.planBlock,
              ),
            ],
          );
        },
      );
      expect(queries, hasLength(1));
      expect(queries.single.bufferBefore, 120);
      await action(t, key('plan-search-without-buffers'));
      expect(queries.last.bufferBefore, 0);
      expect(queries.last.bufferOverride, isTrue);
      expect(find.text('本次未留缓冲'), findsOneWidget);
      expect(selections, isEmpty);
      expect(
        (await PlanAvailabilityPreferences.load('buffers')).bufferKey,
        '120:120',
      );
      await action(t, key('plan-find-time'));
      expect(buffer('before', 0), findsOneWidget);
      await action(t, find.text('恢复记住的缓冲'));
      expect(buffer('before', 120), findsOneWidget);
    },
  );
  testWidgets(
    'failed preference write keeps visible values for this query with honest feedback',
    (t) async {
      SharedPreferencesStorePlatform.instance = _FailingStore();
      final queries = <PlanAvailabilityQuery>[];
      await host(t, changed: queries.add);
      await pick(t, 'before', 0, '10 分钟');
      expect(find.text('本次查找已使用，默认设置未能记住，请重试'), findsOneWidget);
      await action(t, key('plan-lookup-slots'));
      expect(queries.last.bufferBefore, 10);
      expect(queries.last.bufferOverride, isTrue);
      expect(
        (await PlanAvailabilityPreferences.load('buffers')).bufferKey,
        '0:0',
      );
    },
  );

  testWidgets(
    'one-query override survives avoidance edits without clearing remembered buffers',
    (t) async {
      await remember(120, 120);
      await host(
        t,
        results: true,
        loader: (q, {bool forceRefresh = false}) async =>
            PlanAvailabilitySnapshot(
              todo: todo,
              coverage: '合成',
              busy: [
                PlanBusyInterval(
                  DateTime(2026, 10, 12, 7),
                  DateTime(2026, 10, 12, 21),
                  source: PlanBusySource.planBlock,
                ),
              ],
            ),
      );
      await action(t, key('plan-search-without-buffers'));
      await action(t, key('plan-find-time'));
      await action(t, key('plan-avoid-options'));
      await action(t, key('plan-avoid-toggle-0'));
      final p = await PlanAvailabilityPreferences.load('buffers');
      expect(p.bufferKey, '120:120');
      expect(p.selectedIndices, {0});
    },
  );

  testWidgets('late result cannot replace changed buffer condition', (t) async {
    final pending = Completer<PlanAvailabilitySnapshot>();
    var reads = 0;
    await host(
      t,
      loader: (q, {bool forceRefresh = false}) {
        reads++;
        return pending.future;
      },
    );
    await t.ensureVisible(key('plan-lookup-slots'));
    await t.tap(key('plan-lookup-slots'));
    await t.pump();
    // Foreground reload invalidates pending work and restores externally changed defaults.
    await remember(15, 5);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    pending.complete(sources());
    await t.pumpAndSettle();
    expect(reads, 1);
    expect(buffer('before', 15), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is OutlinedButton && w.key.toString().contains('plan-slot-'),
      ),
      findsNothing,
    );
  });
  testWidgets(
    'invalid stored buffer fails closed and reset retains avoidance',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'plan_availability_avoidance_buffers': jsonEncode({
          'version': 2,
          'buffer_before': -1,
          'buffer_after': 5,
          'windows': [
            {'label': '午休', 'start': 750, 'end': 810, 'enabled': true},
          ],
        }),
      });
      var reads = 0;
      await host(
        t,
        results: true,
        loader: (q, {bool forceRefresh = false}) async {
          reads++;
          return sources();
        },
      );
      expect(reads, 0);
      expect(key('plan-reset-buffers'), findsOneWidget);
      await action(t, key('plan-reset-buffers'));
      expect(reads, 1);
      final p = await PlanAvailabilityPreferences.load('buffers');
      expect(p.bufferError, isNull);
      expect(p.selectedIndices, {0});
      expect(p.options.first.startMinutes, 750);
    },
  );
  testWidgets('resetting malformed settings repairs them for the next window',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'plan_availability_avoidance_buffers': 'not-json',
    });
    var reads = 0;
    await host(
      t,
      results: true,
      loader: (q, {bool forceRefresh = false}) async {
        reads++;
        return sources();
      },
    );

    expect(reads, 0);
    await action(t, key('plan-reset-buffers'));
    expect(reads, 1);
    final repaired = await PlanAvailabilityPreferences.load('buffers');
    expect(repaired.bufferError, isNull);
    expect(repaired.bufferKey, '0:0');
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('controls and status fit width $width at 1.8 dark text', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await remember(10, 5);
      await host(t, scale: 1.8, brightness: Brightness.dark);
      await t.ensureVisible(buffer('before', 10));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(buffer('after', 5));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
