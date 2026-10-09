import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/screens/fixed_schedule_detail_screen.dart';
import 'package:countdown_todo/screens/course_screens.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/plan_conflict_review_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:countdown_todo/widgets/plan_block_today_section.dart';
import 'package:countdown_todo/widgets/plan_conflict_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../support/plan_availability_fixture.dart';

const username = PlanAvailabilityFixture.username;
final day = PlanAvailabilityFixture.day;
DateTime at(int hour, [int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);
Finder key(String value) => find.byKey(ValueKey(value));
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  late PlanAvailabilityFixture fixture;
  late PlanConflictReviewService service;
  late TodoPlanBlock source;
  setUp(() async {
    await initializeDateFormatting();
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    await LiquidGlassEffectService.setEnabled(false);
    source = TodoPlanBlock(
      id: 'ui-plan',
      todoId: 'todo-target',
      titleSnapshot: '复习高数',
      startTime: at(10).millisecondsSinceEpoch,
      endTime: at(11).millisecondsSinceEpoch,
      plannedMinutes: 60,
      actualFocusSeconds: 200,
      calendarEventId: 'keep-event',
      pomodoroRecordIds: ['keep-record'],
      remark: '先复习错题',
      pomodoroRounds: 2,
    );
    await fixture.block(source);
    await fixture.fixed('ui-meeting', at(10, 30), at(11, 30));
    service = PlanConflictReviewService(
      databaseOverride: fixture.db,
      clock: () => PlanAvailabilityFixture.now,
    );
  });
  tearDown(() async {
    await LiquidGlassEffectService.setEnabled(false);
    GlassPerformanceMonitor.stop();
    await fixture.dispose();
  });

  Future<void> host(
    WidgetTester tester, {
    PlanConflictReviewLoader? loader,
    DateTime? date,
    bool followToday = false,
    Size size = const Size(1000, 900),
    double scale = 1,
    double keyboard = 0,
    Brightness brightness = Brightness.light,
    bool glass = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
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
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: PlanConflictIndicator(
            username: username,
            date: followToday ? null : date ?? day,
            service: service,
            loader: loader,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  PlanConflictReviewResult synthetic(
    DateTime date, {
    int days = 1,
    bool appOnly = false,
    bool unknown = false,
    int count = 1,
  }) => PlanConflictReviewResult(
    username: username,
    start: DateTime(date.year, date.month, date.day),
    end: DateTime(date.year, date.month, date.day + days),
    entries: [
      for (var i = 0; i < count; i++)
        PlanConflictEntry(
          TodoPlanBlock.fromJson({...source.toJson(), 'uuid': 'synthetic-$i'}),
          TodoItem(id: 'todo-target', title: '合成规划$i'),
          [
            PlanConflictOverlap(
              PlanBusyInterval(
                at(10, 30),
                at(11),
                source: PlanBusySource.fixedSchedule,
                id: 'meeting',
                title: '合成会议',
              ),
              at(10, 30),
              at(11),
            ),
          ],
        ),
    ],
    coverage: '已检查应用内合成安排',
    unknownTimes: unknown ? ['会议时间待定'] : [],
    appOnly: appOnly,
  );

  testWidgets('入口和列表按规划计数，展开显示精确来源，查看固定日程进入既有详情', (tester) async {
    await host(tester);
    expect(find.text('1条规划时间重叠'), findsOneWidget);
    await click(tester, key('plan-conflict-indicator'));
    expect(find.byType(PlanConflictReviewSheet), findsOneWidget);
    await click(tester, key('plan-conflict-ui-plan'));
    expect(find.text('固定日程 · 合成会议'), findsOneWidget);
    expect(find.text('重叠 10-08 10:30–10-08 11:00'), findsOneWidget);
    await click(tester, key('plan-conflict-source-ui-plan-0'));
    expect(find.byType(PlanConflictReviewSheet), findsNothing);
    final detail = tester.widget<FixedScheduleDetailScreen>(
      find.byType(FixedScheduleDetailScreen),
    );
    expect(detail.item.id, 'ui-meeting');
    expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
  });
  for (final kind in ['course', 'legacy', 'device', 'plan']) {
    testWidgets('查看$kind来源进入正确只读详情，保持零写入', (tester) async {
      await fixture.db.delete('fixed_schedules');
      PlanConflictReviewLoader? loader;
      if (kind == 'course') {
        await fixture.course('source-course', day, 1030, 1130);
      } else if (kind == 'legacy') {
        await fixture.todo(
          'source-legacy',
          '旧执行安排',
          legacyStart: at(10, 30),
          due: at(11, 30),
        );
      } else if (kind == 'plan') {
        await fixture.block(
          TodoPlanBlock(
            id: 'source-other-plan',
            todoId: 'todo-target',
            startTime: at(10, 30).millisecondsSinceEpoch,
            endTime: at(11, 30).millisecondsSinceEpoch,
            titleSnapshot: '另一规划',
          ),
        );
      } else {
        final event = DeviceCalendarEvent(
          id: 'source-device',
          calendarId: 'c',
          title: '手机会议',
          start: at(10, 30),
          end: at(11, 30),
          allDay: false,
        );
        loader = (user, date, {int days = 1, bool appOnly = false}) async =>
            PlanConflictReviewResult(
              username: user,
              start: date,
              end: date.add(Duration(days: days)),
              coverage: '合成手机日历',
              entries: [
                PlanConflictEntry(
                  source,
                  TodoItem(id: source.todoId, title: '复习高数'),
                  [
                    PlanConflictOverlap(
                      PlanBusyInterval(
                        event.start,
                        event.end,
                        source: PlanBusySource.deviceCalendar,
                        id: event.id,
                        title: event.title,
                        record: event,
                      ),
                      at(10, 30),
                      at(11),
                    ),
                  ],
                ),
              ],
            );
      }
      final original = await fixture.db.query('todo_plan_blocks');
      await host(tester, loader: loader);
      await click(tester, key('plan-conflict-indicator'));
      await click(tester, key('plan-conflict-ui-plan'));
      await click(tester, key('plan-conflict-source-ui-plan-0'));
      if (kind == 'course') {
        expect(
          tester
              .widget<CourseDetailScreen>(find.byType(CourseDetailScreen))
              .course
              .uuid,
          'source-course',
        );
      } else if (kind == 'legacy') {
        expect(
          tester
              .widget<TodoDetailScreen>(find.byType(TodoDetailScreen))
              .todo
              .id,
          'source-legacy',
        );
      } else if (kind == 'device') {
        expect(
          tester
              .widget<DeviceCalendarEventDetailScreen>(
                find.byType(DeviceCalendarEventDetailScreen),
              )
              .event
              .id,
          'source-device',
        );
      } else {
        expect(
          tester
              .widget<PlanConflictPlanDetailScreen>(
                find.byType(PlanConflictPlanDetailScreen),
              )
              .block
              .id,
          'source-other-plan',
        );
      }
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        original,
      );
      expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('范围切换明确请求今天或七天，旧范围晚返回不覆盖', (tester) async {
    final pending = Completer<PlanConflictReviewResult>();
    final calls = <(DateTime, int)>[];
    Future<PlanConflictReviewResult> loader(
      String user,
      DateTime date, {
      int days = 1,
      bool appOnly = false,
    }) async {
      calls.add((date, days));
      if (days == 7) return pending.future;
      return synthetic(date, days: days, count: date == day ? 1 : 0);
    }

    await host(tester, loader: loader);
    await click(tester, key('plan-conflict-indicator'));
    await tester.tap(key('plan-conflict-range-week'));
    await tester.pump();
    await click(tester, key('plan-conflict-range-today'));
    expect(find.text('已检查范围内没有发现重叠'), findsOneWidget);
    pending.complete(synthetic(PlanAvailabilityFixture.now, days: 7, count: 3));
    await settle(tester);
    expect(find.text('合成规划0'), findsNothing);
    expect(
      calls.any((call) => call.$2 == 7 && call.$1 == DateTime(2026, 10, 7)),
      isTrue,
    );
  });
  testWidgets('读取失败显示未完成，只有明确点击才使用应用内降级', (tester) async {
    final flags = <bool>[];
    await host(
      tester,
      loader: (user, date, {int days = 1, bool appOnly = false}) async {
        flags.add(appOnly);
        if (!appOnly) {
          throw const PlanAvailabilityException('合成日历失败', canUseAppOnly: true);
        }
        return synthetic(date, days: days, appOnly: true, count: 0);
      },
    );
    expect(find.text('冲突检查未完成'), findsOneWidget);
    await click(tester, key('plan-conflict-indicator'));
    expect(find.text('合成日历失败'), findsOneWidget);
    expect(flags.every((flag) => !flag), isTrue);
    await click(tester, key('plan-conflict-app-only'));
    expect(flags.last, isTrue);
    expect(find.text('仅按应用内安排检查；未计入手机日历'), findsOneWidget);
    expect(find.text('已检查范围内没有发现重叠'), findsOneWidget);
    expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
  });
  testWidgets('待定来源无重叠也显示未完成，不冒充全天无冲突', (tester) async {
    await host(
      tester,
      loader: (user, date, {int days = 1, bool appOnly = false}) async =>
          synthetic(date, count: 0, unknown: true),
    );
    expect(key('plan-conflict-indicator'), findsOneWidget);
    await click(tester, key('plan-conflict-indicator'));
    expect(find.text('冲突检查未完成：部分安排时间待定'), findsOneWidget);
    expect(find.text('已检查范围内没有发现重叠'), findsNothing);
    await click(tester, find.byType(ExpansionTile));
    expect(find.text('会议时间待定'), findsOneWidget);
  });
  testWidgets('新日期已返回后，旧日期晚返回不会污染数量', (tester) async {
    final pending = Completer<PlanConflictReviewResult>();
    Future<PlanConflictReviewResult> loader(
      String user,
      DateTime date, {
      int days = 1,
      bool appOnly = false,
    }) async {
      if (date == day) return pending.future;
      return synthetic(date, count: 2);
    }

    await host(tester, loader: loader);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlanConflictIndicator(
            username: username,
            date: day.add(const Duration(days: 1)),
            service: service,
            loader: loader,
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('2条规划时间重叠'), findsOneWidget);
    pending.complete(synthetic(day, count: 1));
    await settle(tester);
    expect(find.text('2条规划时间重叠'), findsOneWidget);
    expect(find.text('1条规划时间重叠'), findsNothing);
  });
  testWidgets('前台跨午夜后今天及七天范围自动换日，后台不定时读取', (tester) async {
    var time = DateTime(2026, 10, 7, 23, 59);
    service = PlanConflictReviewService(clock: () => time);
    final dates = <DateTime>[];
    await host(
      tester,
      followToday: true,
      loader: (user, date, {int days = 1, bool appOnly = false}) async {
        dates.add(date);
        return synthetic(date, days: days);
      },
    );
    await click(tester, key('plan-conflict-indicator'));
    await click(tester, key('plan-conflict-range-week'));
    time = DateTime(2026, 10, 8);
    await tester.pump(const Duration(minutes: 1));
    await settle(tester);
    expect(dates.last, DateTime(2026, 10, 8));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final reads = dates.length;
    time = DateTime(2026, 10, 9);
    await tester.pump(const Duration(days: 1));
    await settle(tester);
    expect(dates.length, reads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(dates.last, DateTime(2026, 10, 9));
  });

  testWidgets('固定日程数据刷新清除已自然消失的提示且不写处理标记', (tester) async {
    await host(tester);
    expect(key('plan-conflict-indicator'), findsOneWidget);
    await tester.runAsync(
      () => fixture.db.update(
        'fixed_schedules',
        {
          'start_time': at(11).millisecondsSinceEpoch,
          'end_time': at(12).millisecondsSinceEpoch,
        },
        where: 'uuid = ?',
        whereArgs: ['ui-meeting'],
      ),
    );
    StorageService.triggerRefresh(const {DataRefreshDomain.fixedSchedules});
    await settle(tester);
    expect(key('plan-conflict-indicator'), findsNothing);
    expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
  });
  testWidgets('调整安排关闭列表后进入整页，锁定原待办，选择候选再取消零写入', (tester) async {
    final original = await fixture.db.query('todo_plan_blocks');
    await host(tester);
    await click(tester, key('plan-conflict-indicator'));
    await click(tester, key('plan-conflict-adjust-ui-plan'));
    expect(find.byType(PlanConflictReviewSheet), findsNothing);
    final editor = tester.widget<PlanBlockEditorSheet>(
      find.byType(PlanBlockEditorSheet),
    );
    expect(editor.fullPage, isTrue);
    expect(editor.conflictEdit!.block.id, source.id);
    expect(editor.block!.calendarEventId, 'keep-event');
    expect(find.text('调整规划'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged,
      isNull,
    );
    await click(tester, key('plan-slot-${at(8).millisecondsSinceEpoch}'));
    Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
    await settle(tester);
    expect(
      await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
      original,
    );
    expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
  });
  testWidgets('整页改期真实保存只更新原规划并保留实际信息，提示自然消失', (tester) async {
    final todos = await fixture.db.query('todos');
    await host(tester);
    await click(tester, key('plan-conflict-indicator'));
    await click(tester, key('plan-conflict-adjust-ui-plan'));
    await click(tester, key('plan-slot-${at(8).millisecondsSinceEpoch}'));
    await click(tester, key('plan-save'));
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
    final plans = await tester.runAsync(
      () => fixture.db.query('todo_plan_blocks'),
    );
    expect(plans, hasLength(1));
    final saved = TodoPlanBlock.fromJson(plans!.single);
    expect(saved.id, 'ui-plan');
    expect(saved.startTime, at(8).millisecondsSinceEpoch);
    expect(saved.calendarEventId, 'keep-event');
    expect(saved.actualFocusSeconds, 200);
    expect(saved.pomodoroRecordIds, ['keep-record']);
    expect(await tester.runAsync(() => fixture.db.query('todos')), todos);
    expect(
      await tester.runAsync(() => fixture.db.query('op_logs')),
      hasLength(1),
    );
    expect(key('plan-conflict-indicator'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('原冲突区间直接保存被拒绝，备注保留且没有写入', (tester) async {
    await host(tester);
    await click(tester, key('plan-conflict-indicator'));
    await click(tester, key('plan-conflict-adjust-ui-plan'));
    final remark = find.byType(TextField);
    await tester.ensureVisible(remark);
    await tester.enterText(remark, '保留新备注');
    await click(tester, key('plan-save'));
    expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
    expect(find.text('保留新备注'), findsOneWidget);
    expect(find.textContaining('时段已失效或被占用'), findsOneWidget);
    expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
  });
  testWidgets('专注中的规划仅提供查看，不显示调整', (tester) async {
    await fixture.db.update(
      'todo_plan_blocks',
      {'status': TodoPlanStatus.focusing.index},
      where: 'uuid = ?',
      whereArgs: [source.id],
    );
    await host(tester);
    await click(tester, key('plan-conflict-indicator'));
    expect(key('plan-conflict-focus-ui-plan'), findsOneWidget);
    expect(key('plan-conflict-adjust-ui-plan'), findsNothing);
    expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
  });

  for (final config in [
    (const Size(320, 640), 1.6, 130.0, Brightness.light, false),
    (const Size(390, 844), 1.0, 0.0, Brightness.dark, true),
    (const Size(720, 360), 1.6, 130.0, Brightness.dark, true),
    (const Size(1280, 900), 2.0, 0.0, Brightness.light, false),
  ]) {
    testWidgets('列表与来源详情短屏大字键盘可达 $config', (tester) async {
      await host(
        tester,
        size: config.$1,
        scale: config.$2,
        keyboard: config.$3,
        brightness: config.$4,
        glass: config.$5,
      );
      await click(tester, key('plan-conflict-indicator'));
      await tester.scrollUntilVisible(
        key('plan-conflict-ui-plan'),
        60,
        scrollable: find
            .descendant(
              of: find.byType(PlanConflictReviewSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await click(tester, key('plan-conflict-ui-plan'));
      await click(tester, key('plan-conflict-source-ui-plan-0'));
      expect(find.byType(FixedScheduleDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final entry in ['today', 'day']) {
    testWidgets('正式$entry入口显示冲突并打开同一列表，关闭零写入', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await fixture.db.update(
        'todo_plan_blocks',
        {
          'start_time': today.millisecondsSinceEpoch,
          'end_time': DateTime(
            today.year,
            today.month,
            today.day + 1,
          ).millisecondsSinceEpoch,
        },
        where: 'uuid = ?',
        whereArgs: [source.id],
      );
      await fixture.db.update(
        'fixed_schedules',
        {
          'date': dateFormatForTest(today),
          'start_time': today.millisecondsSinceEpoch,
          'end_time': DateTime(
            today.year,
            today.month,
            today.day + 1,
          ).millisecondsSinceEpoch,
        },
        where: 'uuid = ?',
        whereArgs: ['ui-meeting'],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tip_shown_todo_plan_guide', true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: entry == 'today'
              ? const Scaffold(body: PlanBlockTodaySection(username: username))
              : TodoPlanScreen(username: username, initialDate: today),
        ),
      );
      await settle(tester);
      expect(key('plan-conflict-indicator'), findsOneWidget);
      await click(tester, key('plan-conflict-indicator'));
      expect(find.byType(PlanConflictReviewSheet), findsOneWidget);
      expect(key('plan-conflict-ui-plan'), findsOneWidget);
      await click(tester, find.byTooltip('关闭冲突列表'));
      expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

String dateFormatForTest(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
