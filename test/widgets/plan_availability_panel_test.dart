import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_availability_preferences.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/widgets/plan_availability_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final day = DateTime(2026, 10, 8);
final now = DateTime(2026, 10, 7, 12);
final todo = TodoItem(id: 'todo-panel', title: '复习高数');
PlanAvailabilitySnapshot snapshot({
  List<PlanBusyInterval> busy = const [],
  String coverage = '仅应用内合成安排',
}) => PlanAvailabilitySnapshot(todo: todo, busy: busy, coverage: coverage);
Finder key(String value) => find.byKey(ValueKey(value));
Future<void> tap(WidgetTester tester, String value) async {
  await tester.ensureVisible(key(value));
  await tester.tap(key(value));
  await tester.pump();
  if (value == 'plan-find-time') await tester.pumpAndSettle();
}

Future<void> pumpPanel(
  WidgetTester tester,
  PlanAvailabilityLoader loader, {
  DateTime? date,
  String username = 'synthetic',
  int minutes = 45,
  bool initialExpanded = false,
  bool disableAnimations = false,
  TodoItem? target,
  ValueChanged<PlanAvailabilitySelection>? selected,
  VoidCallback? invalidated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlanAvailabilityPanel(
            username: username,
            todo: target ?? todo,
            initialDate: date ?? day,
            initialMinutes: minutes,
            initialExpanded: initialExpanded,
            loader: loader,
            clock: () => now,
            onSelected: selected ?? (_) {},
            onInvalidated: invalidated ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('展开和收起经过中间高度，快速反向后保留输入且不会查找或写入', (tester) async {
    var loads = 0;
    var invalidations = 0;
    var selections = 0;
    await pumpPanel(
      tester,
      (q, {bool forceRefresh = false}) async {
        loads++;
        return snapshot();
      },
      invalidated: () => invalidations++,
      selected: (_) => selections++,
    );
    final expansion = key('plan-availability-expansion');
    final collapsedHeight = tester.getSize(expansion).height;
    final headerTop = tester.getTopLeft(key('plan-find-time'));
    await tester.tap(key('plan-find-time'));
    await tester.pump();
    expect(tester.getSize(expansion).height, closeTo(collapsedHeight, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    final expandingHeight = tester.getSize(expansion).height;
    await tester.pumpAndSettle();
    final expandedHeight = tester.getSize(expansion).height;
    expect(expandingHeight, greaterThan(collapsedHeight));
    expect(expandingHeight, lessThan(expandedHeight));
    expect(tester.getTopLeft(key('plan-find-time')), headerTop);
    await tester.enterText(key('plan-custom-duration'), '75');
    final before = invalidations;
    await tester.tap(key('plan-find-time'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final collapsingHeight = tester.getSize(expansion).height;
    expect(collapsingHeight, greaterThan(collapsedHeight));
    expect(collapsingHeight, lessThan(expandedHeight));
    await tester.tap(key('plan-find-time'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.getSize(expansion).height, closeTo(expandedHeight, 0.01));
    expect(
      tester.widget<TextField>(key('plan-custom-duration')).controller!.text,
      '75',
    );
    await tester.tap(key('plan-find-time'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.getSize(expansion).height, closeTo(collapsedHeight, 0.01));
    expect(invalidations, before);
    expect(loads, 0);
    expect(selections, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('漏做恢复初始展开不先折叠，减少动画设置立即完成切换', (tester) async {
    await pumpPanel(
      tester,
      (q, {bool forceRefresh = false}) async => snapshot(),
      initialExpanded: true,
      disableAnimations: true,
    );
    final expansion = key('plan-availability-expansion');
    final expandedHeight = tester.getSize(expansion).height;
    await tester.tap(key('plan-find-time'));
    await tester.pump();
    await tester.pump();
    final collapsedHeight = tester.getSize(expansion).height;
    expect(collapsedHeight, lessThan(expandedHeight));
    await tester.tap(key('plan-find-time'));
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(expansion).height, closeTo(expandedHeight, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭重开恢复预设和自定义勾选，查找确实采用恢复的避让', (tester) async {
    final queries = <PlanAvailabilityQuery>[];
    Future<PlanAvailabilitySnapshot> loader(
      PlanAvailabilityQuery query, {
      bool forceRefresh = false,
    }) async {
      queries.add(query);
      return snapshot();
    }

    await pumpPanel(tester, loader, initialExpanded: true);
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-options');
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-toggle-0');
    await tap(tester, 'plan-avoid-toggle-2');
    await tap(tester, 'plan-avoid-add');
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-confirm');
    await tester.pumpAndSettle();
    // Close without saving any plan, then open a new panel.
    await tester.pumpWidget(const SizedBox());
    await pumpPanel(tester, loader, initialExpanded: true);
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-options');
    await tester.pumpAndSettle();
    for (final index in [0, 2, 3]) {
      expect(
        tester.widget<FilterChip>(key('plan-avoid-toggle-$index')).selected,
        isTrue,
      );
    }
    expect(
      tester.widget<FilterChip>(key('plan-avoid-toggle-1')).selected,
      isFalse,
    );
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(queries.single.avoidWindows.map((w) => w.label), [
      '午休',
      '晚餐',
      '自定义',
    ]);
    expect(queries.single.avoidWindows.last.startMinutes, 900);
    await tap(tester, 'plan-avoid-toggle-0');
    await tap(tester, 'plan-avoid-toggle-2');
    await tap(tester, 'plan-avoid-remove-3');
    await tester.pumpWidget(const SizedBox());
    await pumpPanel(tester, loader, initialExpanded: true);
    await tester.pumpAndSettle();
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(queries.last.avoidWindows, isEmpty);
    expect(find.text('已避开 3 个时段'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一面板切换账号不串用勾选，切回恢复本账号', (tester) async {
    final windows = PlanAvailabilityPreferences.defaultWindows;
    await tester.runAsync(
      () => PlanAvailabilityPreferences.save('synthetic', windows, {
        windows.first,
      }),
    );
    await tester.runAsync(
      () => PlanAvailabilityPreferences.save('other-account', windows, {
        windows.last,
      }),
    );
    final queries = <PlanAvailabilityQuery>[];
    Future<PlanAvailabilitySnapshot> loader(
      PlanAvailabilityQuery query, {
      bool forceRefresh = false,
    }) async {
      queries.add(query);
      return snapshot();
    }

    await pumpPanel(tester, loader, initialExpanded: true);
    await tester.pumpAndSettle();
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    await pumpPanel(
      tester,
      loader,
      username: 'other-account',
      initialExpanded: true,
    );
    await tester.pumpAndSettle();
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    await pumpPanel(tester, loader, initialExpanded: true);
    await tester.pumpAndSettle();
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(queries.map((q) => q.username), [
      'synthetic',
      'other-account',
      'synthetic',
    ]);
    expect(queries.map((q) => q.avoidWindows.single.label), ['午休', '晚餐', '午休']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复修改过的预设时段，并传给手动保存查询回调', (tester) async {
    final windows = [
      const PlanDailyTimeWindow('午休', 750, 810),
      ...PlanAvailabilityPreferences.defaultWindows.skip(1),
    ];
    await tester.runAsync(
      () => PlanAvailabilityPreferences.save('synthetic', windows, {
        windows.first,
      }),
    );
    PlanAvailabilityQuery? query;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlanAvailabilityPanel(
            username: 'synthetic',
            todo: todo,
            initialDate: day,
            initialMinutes: 30,
            loader: (q, {bool forceRefresh = false}) async => snapshot(),
            clock: () => now,
            onSelected: (_) {},
            onInvalidated: () {},
            onQueryChanged: (value) => query = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(query!.avoidWindows.single.startMinutes, 750);
    expect(query!.avoidWindows.single.endMinutes, 810);
    expect(tester.takeException(), isNull);
  });

  testWidgets('避让时段可结束于午夜，并可再次打开编辑', (tester) async {
    const midnightWindow = PlanDailyTimeWindow('通宵', 1380, 1440);
    final windows = [
      ...PlanAvailabilityPreferences.defaultWindows,
      midnightWindow,
    ];
    await tester.runAsync(
      () => PlanAvailabilityPreferences.save('synthetic', windows, {
        midnightWindow,
      }),
    );
    await pumpPanel(
      tester,
      (q, {bool forceRefresh = false}) async => snapshot(),
      initialExpanded: true,
    );
    await tester.runAsync(() => PlanAvailabilityPreferences.load('synthetic'));
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-options');
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-edit-3');
    await tester.pumpAndSettle();

    expect(find.text('调整通宵时间'), findsOneWidget);
    await tap(tester, 'plan-avoid-end');
    await tester.pumpAndSettle();
    await tester.tap(find.text('AM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(find.text('调整通宵时间'), findsNothing);
    expect(find.text('23:00–24:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认五条，可调数量与午休用餐避让，修改会使已选推荐失效', (tester) async {
    final queries = <PlanAvailabilityQuery>[];
    var invalidations = 0;
    await pumpPanel(tester, (q, {bool forceRefresh = false}) async {
      queries.add(q);
      return snapshot();
    }, invalidated: () => invalidations++);
    await tap(tester, 'plan-find-time');
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(queries.last.resultLimit, 5);
    expect(find.text('可用时段 · 5 个建议'), findsOneWidget);
    await tap(
      tester,
      'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
    );
    final before = invalidations;
    await tap(tester, 'plan-avoid-options');
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-toggle-0');
    await tap(tester, 'plan-avoid-toggle-1');
    await tap(tester, 'plan-avoid-toggle-2');
    expect(invalidations, greaterThan(before));
    expect(find.text('可用时段 · 5 个建议'), findsNothing);
    await tap(tester, 'plan-result-limit-8');
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(queries.last.resultLimit, 8);
    expect(queries.last.avoidWindows.map((w) => w.label).toSet(), {
      '午休',
      '午餐',
      '晚餐',
    });
    expect(find.text('可用时段 · 8 个建议'), findsOneWidget);
    await tap(tester, 'plan-avoid-add');
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(queries.last.avoidWindows, hasLength(3));
    await tap(tester, 'plan-avoid-add');
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-confirm');
    await tester.pumpAndSettle();
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(queries.last.avoidWindows, hasLength(4));
    expect(queries.last.avoidWindows.last.startMinutes, 900);
    expect(queries.first.avoidWindows, isEmpty);
    await tap(tester, 'plan-avoid-remove-3');
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(queries.last.avoidWindows, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('快捷时长、自定义输入、候选选择仅回调草稿', (tester) async {
    final calls = <PlanAvailabilityQuery>[];
    PlanAvailabilitySelection? chosen;
    await pumpPanel(tester, (q, {bool forceRefresh = false}) async {
      calls.add(q);
      return snapshot();
    }, selected: (s) => chosen = s);
    await tap(tester, 'plan-find-time');
    await tap(tester, 'plan-duration-30');
    await tester.enterText(key('plan-custom-duration'), '45');
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(calls.single.minutes, 45);
    final first = day.add(const Duration(hours: 8));
    await tap(tester, 'plan-slot-${first.millisecondsSinceEpoch}');
    expect(chosen!.slot.minutes, 45);
    expect(chosen!.slot.start, first);
    expect(find.text('仅应用内合成安排'), findsOneWidget);
  });
  testWidgets('无效输入和过去日期不读取来源', (tester) async {
    var calls = 0;
    Future<PlanAvailabilitySnapshot> loader(
      PlanAvailabilityQuery q, {
      bool forceRefresh = false,
    }) async {
      calls++;
      return snapshot();
    }

    await pumpPanel(tester, loader);
    await tap(tester, 'plan-find-time');
    for (final text in ['0', '-1', '9999', 'abc']) {
      await tester.enterText(key('plan-custom-duration'), text);
      await tap(tester, 'plan-lookup-slots');
      expect(find.text('需要时长必须大于零，且不能超过可安排范围'), findsOneWidget);
    }
    await pumpPanel(tester, loader, date: DateTime(2026, 10, 6));
    await tap(tester, 'plan-duration-45');
    await tap(tester, 'plan-lookup-slots');
    expect(find.text('所选日期已过去，请选择今天或之后的日期'), findsOneWidget);
    expect(calls, 0);
  });
  testWidgets('日期 A→B→A 的旧响应不能覆盖最新候选', (tester) async {
    final requests = <Completer<PlanAvailabilitySnapshot>>[];
    Future<PlanAvailabilitySnapshot> loader(
      PlanAvailabilityQuery q, {
      bool forceRefresh = false,
    }) {
      final request = Completer<PlanAvailabilitySnapshot>();
      requests.add(request);
      return request.future;
    }

    await pumpPanel(tester, loader);
    await tap(tester, 'plan-find-time');
    await tap(tester, 'plan-lookup-slots');
    await pumpPanel(tester, loader, date: day.add(const Duration(days: 1)));
    await tap(tester, 'plan-lookup-slots');
    await pumpPanel(tester, loader, date: day);
    await tap(tester, 'plan-lookup-slots');
    requests[2].complete(snapshot(coverage: '最新 A'));
    await tester.pumpAndSettle();
    requests[1].complete(snapshot(coverage: '旧 B'));
    requests[0].complete(snapshot(coverage: '旧 A'));
    await tester.pumpAndSettle();
    expect(find.text('最新 A'), findsOneWidget);
    expect(find.text('旧 A'), findsNothing);
    expect(find.text('旧 B'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets('快速修改时长、待办及关闭面板丢弃旧响应', (tester) async {
    final requests = <Completer<PlanAvailabilitySnapshot>>[];
    Future<PlanAvailabilitySnapshot> loader(
      PlanAvailabilityQuery q, {
      bool forceRefresh = false,
    }) {
      final request = Completer<PlanAvailabilitySnapshot>();
      requests.add(request);
      return request.future;
    }

    await pumpPanel(tester, loader);
    await tap(tester, 'plan-find-time');
    await tap(tester, 'plan-lookup-slots');
    await tap(tester, 'plan-duration-60');
    requests[0].complete(snapshot(coverage: '旧时长'));
    await tester.pumpAndSettle();
    expect(find.text('旧时长'), findsNothing);
    await tap(tester, 'plan-lookup-slots');
    await pumpPanel(
      tester,
      loader,
      target: TodoItem(id: 'other', title: '其他待办'),
    );
    requests[1].complete(snapshot(coverage: '旧待办'));
    await tester.pumpAndSettle();
    expect(find.text('旧待办'), findsNothing);
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpWidget(const SizedBox());
    requests[2].complete(snapshot());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('手机日历失败须明确选择应用内范围，不能默默生成候选', (tester) async {
    final calls = <bool>[];
    await pumpPanel(tester, (q, {bool forceRefresh = false}) async {
      calls.add(q.appOnly);
      if (!q.appOnly) {
        throw const PlanAvailabilityException(
          '合成手机日历查询失败',
          canUseAppOnly: true,
        );
      }
      return snapshot();
    });
    await tap(tester, 'plan-find-time');
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    expect(
      key(
        'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
      ),
      findsNothing,
    );
    expect(calls, [false]);
    await tap(tester, 'plan-app-only');
    await tester.pumpAndSettle();
    expect(calls, [false, true]);
    expect(
      key(
        'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
      ),
      findsOneWidget,
    );
  });
  testWidgets('安排刷新、日历设置与恢复前台均使候选失效', (tester) async {
    await pumpPanel(
      tester,
      (q, {bool forceRefresh = false}) async => snapshot(),
    );
    await tap(tester, 'plan-find-time');
    for (var cause = 0; cause < 3; cause++) {
      await tap(tester, 'plan-lookup-slots');
      await tester.pumpAndSettle();
      expect(
        key(
          'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
        ),
        findsOneWidget,
      );
      if (cause == 0) {
        StorageService.triggerRefresh(const {DataRefreshDomain.courses});
      }
      if (cause == 1) DeviceCalendarReadService.revision.value++;
      if (cause == 2) {
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      }
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        key(
          'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
        ),
        findsNothing,
      );
    }
  });
  testWidgets('共享日期和时间选择器可打开并取消，保留输入', (tester) async {
    await pumpPanel(
      tester,
      (q, {bool forceRefresh = false}) async => snapshot(),
    );
    await tap(tester, 'plan-find-time');
    await tap(tester, 'plan-availability-date');
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-08'), findsOneWidget);
    await tap(tester, 'plan-window-start');
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('从 08:00'), findsOneWidget);
  });
}
