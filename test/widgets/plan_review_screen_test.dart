import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/screens/plan_block_stats_screen.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/plan_review_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

class _Controlled extends PlanReviewRepository {
  final requests = <Completer<PlanReviewSummary>>[];
  @override
  Future<PlanReviewSummary> read(
    String username,
    DateTime start,
    DateTime end,
  ) {
    final request = Completer<PlanReviewSummary>();
    requests.add(request);
    return request.future;
  }
}

class _Retry extends PlanReviewRepository {
  _Retry() : super(clock: () => DateTime(2026, 10, 9, 12));
  bool fail = true;
  @override
  Future<PlanReviewSummary> read(
    String username,
    DateTime start,
    DateTime end,
  ) {
    if (fail) {
      fail = false;
      return Future.error(StateError('隔离读取失败'));
    }
    return super.read(username, start, end);
  }
}

void main() {
  late PlanAvailabilityFixture f;
  final day = DateTime(2026, 10, 8), now = DateTime(2026, 10, 9, 12);
  late PlanReviewRepository repo;
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(finder);
    await drain(tester);
  }

  Finder key(String name) => find.byKey(ValueKey(name));
  Future<void> focus(
    String id, {
    String? planId = 'plan',
    String? todo = 'todo-target',
    int seconds = 1200,
    int? start,
  }) async {
    final time = start ?? DateTime(2026, 10, 8, 10).millisecondsSinceEpoch;
    await f.db.insert('pomodoro_records', {
      'uuid': id,
      'todo_uuid': todo,
      'todo_title': '专注$id',
      'start_time': time,
      'end_time': time + 1800000,
      'actual_duration': seconds,
      'planned_duration': 1500,
      'status': 'completed',
      'plan_block_id': planId,
      'created_at': 1,
      'updated_at': 1,
    });
  }

  Future<void> show(
    WidgetTester tester, {
    PlanReviewRepository? repository,
    Size size = const Size(1000, 1000),
    double scale = 1,
    Brightness brightness = Brightness.light,
    bool glass = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await LiquidGlassEffectService.setEnabled(glass);
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
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: PlanBlockStatsScreen(
          username: PlanAvailabilityFixture.username,
          initialDate: day,
          clock: () => now,
          repository: repository ?? repo,
        ),
      ),
    );
    await drain(tester);
  }

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    await initializeDateFormatting();
    repo = PlanReviewRepository(clock: () => now);
    await f.block(
      TodoPlanBlock(
        id: 'plan',
        todoId: 'todo-target',
        titleSnapshot: '复习高数',
        startTime: DateTime(2026, 10, 8, 10).millisecondsSinceEpoch,
        endTime: DateTime(2026, 10, 8, 11).millisecondsSinceEpoch,
        plannedMinutes: 60,
        status: TodoPlanStatus.finished,
        actualFocusSeconds: 5400,
      ),
    );
    await focus('current');
  });
  tearDown(() async {
    await LiquidGlassEffectService.setEnabled(false);
    GlassPerformanceMonitor.stop();
    await f.dispose();
  });

  testWidgets('overview explains metrics and scope, no old AI label', (
    tester,
  ) async {
    await f.db.insert('pomodoro_records', {
      'uuid': 'invalid',
      'todo_title': '坏时长记录',
      'start_time': DateTime(2026, 10, 8, 12).millisecondsSinceEpoch,
      'end_time': DateTime(2026, 10, 8, 12, 25).millisecondsSinceEpoch,
      'actual_duration': '未知',
      'planned_duration': 1500,
      'status': 'completed',
      'created_at': 1,
      'updated_at': 1,
    });
    await show(tester);
    expect(find.text('1小时'), findsOneWidget);
    expect(find.text('20分钟'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('AI 建议'), findsNothing);
    await tap(tester, find.byTooltip('统计口径'));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('不代表待办完成度'),
      ),
      findsOneWidget,
    );
    await tap(tester, find.text('知道了'));
    await tap(tester, find.text('1项需要核对'));
    expect(find.textContaining('专注 时长待核对'), findsOneWidget);
    expect(find.textContaining('专注 0分钟'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('focus drilldown partitions and opens existing record detail', (
    tester,
  ) async {
    await focus('free', todo: null, planId: null, seconds: 60);
    await show(tester);
    await tap(tester, key('review-focus'));
    expect(find.byType(PlanReviewDetailScreen), findsOneWidget);
    expect(find.text('2项 · 21分钟'), findsOneWidget);
    await tap(tester, find.widgetWithText(ChoiceChip, '未关联规划'));
    expect(find.text('1项 · 1分钟'), findsOneWidget);
    await tap(tester, key('review-entry-focus-free'));
    expect(find.byType(PomodoroDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'plan detail separates period lifetime and cache and is zero-write',
    (tester) async {
      await focus(
        'past',
        start: DateTime(2026, 10, 7, 10).millisecondsSinceEpoch,
        seconds: 600,
      );
      final before = (await f.db.rawQuery('SELECT total_changes() n'))
          .single['n'];
      await show(tester);
      await tap(tester, key('review-plans'));
      await tap(tester, key('review-entry-plan-plan'));
      expect(find.text('本期记录投入 20分钟'), findsOneWidget);
      expect(find.text('累计记录投入 30分钟'), findsOneWidget);
      expect(find.text('原累计参考 5400秒（不计入实际）'), findsOneWidget);
      await tap(tester, find.text('累计记录'));
      expect(find.text('2项 · 30分钟'), findsOneWidget);
      expect(
        (await f.db.rawQuery('SELECT total_changes() n')).single['n'],
        before,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('50 row details load remaining records without duplicates', (
    tester,
  ) async {
    await f.db.transaction((tx) async {
      for (var i = 0; i < 52; i++) {
        await tx.insert('pomodoro_records', {
          'uuid': 'bulk-$i',
          'todo_title': '更多记录$i',
          'start_time': DateTime(2026, 10, 8, 9).millisecondsSinceEpoch,
          'end_time': DateTime(2026, 10, 8, 9, 1).millisecondsSinceEpoch,
          'actual_duration': 60,
          'planned_duration': 60,
          'status': 'completed',
          'created_at': 1,
          'updated_at': 1,
        });
      }
    });
    await show(tester);
    await tap(tester, key('review-focus'));
    expect(find.text('53项 · 1小时 12分钟'), findsOneWidget);
    await tap(tester, key('review-load-more'));
    expect(key('review-load-more'), findsNothing);
    await tester.ensureVisible(key('review-entry-focus-bulk-9'));
    await tester.pump(const Duration(milliseconds: 300));
    final offset = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .pixels;
    await tap(tester, key('review-entry-focus-bulk-9'));
    expect(find.byType(PomodoroDetailScreen), findsOneWidget);
    await tester.pageBack();
    await drain(tester);
    expect(key('review-load-more'), findsNothing);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .pixels,
      closeTo(offset, 1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('failure is explicit and retry retains date', (tester) async {
    await show(tester, repository: _Retry());
    expect(find.text('统计未能完成'), findsOneWidget);
    expect(find.text('隔离读取失败'), findsOneWidget);
    expect(key('review-focus'), findsNothing);
    await tap(tester, find.text('重试'));
    expect(key('review-focus'), findsOneWidget);
    expect(find.text('2026年10月8日'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('older range response cannot overwrite current dimension', (
    tester,
  ) async {
    final controlled = _Controlled();
    await show(tester, repository: controlled);
    await tester.tap(find.text('周'));
    await tester.pump();
    expect(controlled.requests.length, 2);
    final weekly = await repo.read(
      PlanAvailabilityFixture.username,
      DateTime(2026, 10, 5),
      DateTime(2026, 10, 12),
    );
    controlled.requests[1].complete(weekly);
    await drain(tester);
    controlled.requests[0].completeError(StateError('旧请求错误'));
    await drain(tester);
    expect(find.text('旧请求错误'), findsNothing);
    expect(key('review-focus'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'month navigation and empty future period do not claim zero attainment',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('月'));
      expect(find.text('2026年10月'), findsOneWidget);
      await tap(tester, find.byTooltip('下一时段'));
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('暂无已结束规划'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('identity change cannot reuse old visible detail', (
    tester,
  ) async {
    await show(tester);
    await (await SharedPreferences.getInstance()).setInt('current_user_id', 9);
    await tap(tester, key('review-focus'));
    expect(find.byType(PlanReviewDetailScreen), findsNothing);
    expect(find.text('统计未能完成'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final config in [
    (const Size(320, 700), 1.8, Brightness.light, false),
    (const Size(390, 844), 1.0, Brightness.dark, true),
    (const Size(720, 360), 1.8, Brightness.dark, false),
    (const Size(1280, 900), 1.0, Brightness.light, true),
  ]) {
    testWidgets('readable overview and detail without overflow $config', (
      tester,
    ) async {
      await show(
        tester,
        size: config.$1,
        scale: config.$2,
        brightness: config.$3,
        glass: config.$4,
      );
      if (config.$1.width == 320) {
        expect(tester.getSize(key('review-plans')).width, greaterThan(250));
        expect(find.text('10月8日'), findsOneWidget);
      }
      await tap(tester, key('review-focus'));
      await tap(tester, find.widgetWithText(ChoiceChip, '归属待核对'));
      expect(find.text('当前筛选没有记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
