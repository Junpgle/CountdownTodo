@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_editor_draft_repository.dart';
import 'package:countdown_todo/services/plan_reuse_repository.dart';
import 'package:countdown_todo/services/plan_todo_guard.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

class _DelayedReuseRepository extends PlanReuseRepository {
  _DelayedReuseRepository(this.result);
  final Completer<PlanReuseSeed> result;
  int reads = 0;
  @override
  Future<PlanReuseSeed> read(String username, String id) {
    reads++;
    return result.future;
  }
}

void main() {
  late PlanAvailabilityFixture f;
  late TodoPlanBlock source;
  late TodoItem todo, other;
  late List<PlanAvailabilityQuery> queries;
  late List<TodoPlanBlock> saves;
  final day = PlanAvailabilityFixture.day, now = PlanAvailabilityFixture.now;
  const identity = PlanTodoIdentity(PlanAvailabilityFixture.username, 0);
  Finder key(String s) => find.byKey(ValueKey(s));
  Future<void> action(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
      if (!tester.binding.hasScheduledFrame) break;
    }
    await tester.pump(const Duration(milliseconds: 400));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
    }
  }

  Future<void> open(
    WidgetTester tester, {
    bool production = false,
    bool failSave = false,
    PlanReuseSeed? seed,
    PlanEditorDraft? draft,
    PlanReuseRepository? reuseRepository,
    Future<TimeEstimationResult> Function(TodoItem)? estimate,
    Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
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
              child: const Text('打开'),
              onPressed: () {
                (seed != null || draft != null
                    ? showPlanBlockEditorPage<void>
                    : showPlanBlockEditorSheet<void>)(
                  context: c,
                  builder: (_) => PlanBlockEditorSheet(
                    block: seed == null && draft == null ? source : null,
                    fullPage: seed != null || draft != null,
                    reuse: seed,
                    restoredDraft: draft,
                    reuseRepository:
                        reuseRepository ??
                        PlanReuseRepository(database: f.db, clock: () => now),
                    draftRepository: PlanEditorDraftRepository(
                      database: f.db,
                      clock: () => now,
                    ),
                    username: identity.username,
                    todos: [todo, other],
                    todoGroups: const [],
                    startTime: seed?.start ?? day.add(const Duration(hours: 9)),
                    endTime: seed?.end ?? day.add(const Duration(hours: 10)),
                    clock: () => now,
                    onSaved: () {},
                    navigateOnFocus: false,
                    estimate:
                        estimate ??
                        (_) async => const TimeEstimationResult(
                          estimatedMinutes: 30,
                          confidence: 1,
                          reason: '合成估时',
                        ),
                    availabilityLoader: (q, {bool forceRefresh = false}) async {
                      queries.add(q);
                      return PlanAvailabilityRepository(
                        databaseOverride: f.db,
                        clock: () => now,
                      ).read(q, forceRefresh: forceRefresh);
                    },
                    saver: production
                        ? null
                        : (
                            b,
                            selection, {
                            expectedVersion,
                            expectedUpdatedAt,
                            newStatus,
                          }) async {
                            saves.add(b);
                            if (failSave) throw StateError('合成保存失败');
                            return b;
                          },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await action(tester, find.text('打开'));
  }

  Future<void> reuse(WidgetTester tester) async {
    await action(tester, find.byTooltip('更多操作'));
    await action(tester, find.text('照此新建'));
  }

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
    todo = await PlanTodoGuard.read(f.db, identity, 'todo-target');
    await f.todo('todo-other', '整理笔记');
    other = await PlanTodoGuard.read(f.db, identity, 'todo-other');
    source = TodoPlanBlock(
      id: 'source',
      todoId: todo.id,
      titleSnapshot: todo.title,
      startTime: day.add(const Duration(hours: 9)).millisecondsSinceEpoch,
      endTime: day.add(const Duration(hours: 10)).millisecondsSinceEpoch,
      plannedMinutes: 777,
      actualFocusSeconds: 99999,
      status: TodoPlanStatus.planned,
      remark: '原始备注',
      reminderMinutes: 10,
      pomodoroMinutes: 45,
      pomodoroRounds: 2,
      calendarEventId: 'original-calendar',
      pomodoroRecordIds: ['original-focus'],
    );
    await f.block(source);
    queries = [];
    saves = [];
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await f.dispose();
  });

  testWidgets('真实菜单打开整页，按60分钟推荐并采用第一项，字段隔离', (tester) async {
    final before = await f.db.query('todo_plan_blocks');
    await open(tester);
    await reuse(tester);
    expect(key('plan-reuse-notice'), findsOneWidget);
    expect(queries, isNotEmpty);
    expect(
      queries.every((q) => q.minutes == 60 && q.excludeBlockId == null),
      isTrue,
    );
    expect(find.textContaining('已选用'), findsOneWidget);
    expect(
      tester.widget<TextField>(key('plan-remark')).controller!.text,
      '原始备注',
    );
    await action(tester, key('plan-save'));
    final saved = saves.single;
    expect(saved.id, isNot(source.id));
    expect(saved.plannedMinutes, 60);
    expect(saved.actualFocusSeconds, 0);
    expect(saved.pomodoroRecordIds, isEmpty);
    expect(saved.calendarEventId, isNull);
    expect(saved.source, TodoPlanSource.manual);
    expect(saved.status, TodoPlanStatus.planned);
    expect(
      [saved.reminderMinutes, saved.pomodoroMinutes, saved.pomodoroRounds],
      [10, 45, 2],
    );
    expect(await f.db.query('todo_plan_blocks'), before);
  });

  testWidgets('首次带入不触摸也保护退出，取消没有业务写入', (tester) async {
    await open(tester);
    await reuse(tester);
    await action(tester, find.byType(BackButton));
    expect(find.text('保留这次规划？'), findsOneWidget);
    await action(tester, find.text('放弃修改'));
    expect(key('plan-reuse-notice'), findsNothing);
    expect(await f.db.query('op_logs'), isEmpty);
    expect((await f.db.query('todo_plan_blocks')).length, 1);
  });

  testWidgets('已完成源待办不自动选其他待办，换任务和迟到估时不改沿用时长', (tester) async {
    await f.db.update(
      'todos',
      {'is_completed': 1},
      where: 'uuid=?',
      whereArgs: [todo.id],
    );
    final prediction = Completer<TimeEstimationResult>();
    await open(tester, estimate: (_) => prediction.future);
    await reuse(tester);
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      isNull,
    );
    expect(queries, isEmpty);
    await action(tester, find.byType(DropdownButtonFormField<String>));
    await action(tester, find.text(other.title).last);
    prediction.complete(
      const TimeEstimationResult(
        estimatedMinutes: 90,
        confidence: 1,
        reason: '迟到',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('60分钟'), findsWidgets);
    await action(tester, key('plan-save'));
    expect(saves.single.todoId, other.id);
    expect(saves.single.plannedMinutes, 60);
    expect(saves.single.remark, source.remark);
  });

  testWidgets('源编辑有未保存修改时拒绝复用', (tester) async {
    await open(tester);
    await tester.ensureVisible(key('plan-remark'));
    await tester.enterText(key('plan-remark'), '尚未保存');
    await reuse(tester);
    expect(key('plan-reuse-notice'), findsNothing);
    expect(find.textContaining('请先保存修改'), findsOneWidget);
  });

  testWidgets('未触摸的复用草稿可暂存恢复，源删除不影响字段或UUID', (tester) async {
    await open(tester);
    await reuse(tester);
    await action(tester, find.byType(BackButton));
    await action(tester, find.text('保留草稿并离开'));
    final repo = PlanEditorDraftRepository(database: f.db, clock: () => now);
    final rows = await repo.list(identity);
    final draft = await repo.read(identity, rows.single.id);
    expect(draft.fields.origin, 'reuse');
    expect(draft.fields.pomodoro, 45);
    await f.db.update('todo_plan_blocks', {'is_deleted': 1});
    await open(tester, draft: draft);
    expect(key('plan-reuse-notice'), findsOneWidget);
    await action(tester, key('plan-save'));
    expect(saves.single.id, draft.targetId);
    expect(saves.single.remark, source.remark);
    expect(saves.single.actualFocusSeconds, 0);
  });

  testWidgets('生产保存先确认追加，保存只增加独立新规划', (tester) async {
    final before = (await f.db.query('todo_plan_blocks')).single;
    await open(tester, production: true);
    await reuse(tester);
    await action(tester, key('plan-save'));
    expect(find.text('此待办已有安排'), findsOneWidget);
    await action(tester, find.text('查看已有安排'));
    expect(find.text('已有安排'), findsOneWidget);
    await action(tester, find.text('返回编辑'));
    await action(tester, key('plan-save'));
    await action(tester, find.text('仍追加这次规划'));
    final rows = await f.db.query('todo_plan_blocks');
    expect(rows.length, 2);
    expect(rows.singleWhere((r) => r['uuid'] == source.id), before);
    final added = rows.singleWhere((r) => r['uuid'] != source.id);
    expect(added['actual_focus_seconds'], 0);
    expect(added['calendar_event_id'], '');
    expect(added['pomodoro_record_ids'], '');
    expect(added['planned_minutes'], 60);
    expect((await f.db.query('op_logs')).length, 1);
  });

  testWidgets('推荐期间新增占用使生产保存失败，保留原草案', (tester) async {
    await open(tester, production: true);
    await reuse(tester);
    await f.fixed(
      'new-meeting',
      day.add(const Duration(hours: 8)),
      day.add(const Duration(hours: 9)),
    );
    await action(tester, key('plan-save'));
    await action(tester, find.text('仍追加这次规划'));
    expect(key('plan-reuse-notice'), findsOneWidget);
    expect(find.textContaining('被占用'), findsOneWidget);
    expect((await f.db.query('todo_plan_blocks')).length, 1);
  });

  testWidgets('没有推荐时，未核实的参考时间不能绕过源块占用保存', (tester) async {
    await f.fixed(
      'full-day-busy',
      day,
      DateTime(day.year, day.month, day.day + 1),
    );
    await open(tester, production: true);
    await reuse(tester);
    expect(find.textContaining('时段尚未核实'), findsOneWidget);
    expect(find.textContaining('已选用'), findsNothing);
    await action(tester, key('plan-save'));
    await action(tester, find.text('仍追加这次规划'));
    expect(find.textContaining('时段已过去、被占用'), findsOneWidget);
    expect((await f.db.query('todo_plan_blocks')).length, 1);
    expect(await f.db.query('op_logs'), isEmpty);
  });

  testWidgets('确认弹窗期间待办完成，事务守卫拒绝写入', (tester) async {
    await open(tester, production: true);
    await reuse(tester);
    await action(tester, key('plan-save'));
    await f.db.update(
      'todos',
      {'is_completed': 1},
      where: 'uuid=?',
      whereArgs: [todo.id],
    );
    await action(tester, find.text('仍追加这次规划'));
    expect(find.textContaining('待办已完成'), findsOneWidget);
    expect((await f.db.query('todo_plan_blocks')).length, 1);
    expect(await f.db.query('op_logs'), isEmpty);
  });

  testWidgets('保存失败重试沿用同一个新UUID', (tester) async {
    await open(tester, failSave: true);
    await reuse(tester);
    await action(tester, key('plan-save'));
    await action(tester, key('plan-save'));
    expect(saves.length, 2);
    expect(saves[0].id, saves[1].id);
    expect(key('plan-reuse-notice'), findsOneWidget);
  });

  testWidgets('追加确认期间切换成员，旧页面拒绝写入', (tester) async {
    await open(tester, production: true);
    await reuse(tester);
    await action(tester, key('plan-save'));
    await (await SharedPreferences.getInstance()).setInt('current_user_id', 77);
    await action(tester, find.text('仍追加这次规划'));
    expect(find.textContaining('身份已切换'), findsOneWidget);
    expect((await f.db.query('todo_plan_blocks')).length, 1);
    expect(await f.db.query('op_logs'), isEmpty);
  });

  testWidgets('追加确认期间已有安排版本变化，拒绝使用旧确认', (tester) async {
    await open(tester, production: true);
    await reuse(tester);
    await action(tester, key('plan-save'));
    await f.db.update('todo_plan_blocks', {'version': 2});
    await action(tester, find.text('仍追加这次规划'));
    expect(find.textContaining('已有安排再次变化'), findsOneWidget);
    expect((await f.db.query('todo_plan_blocks')).length, 1);
    expect(await f.db.query('op_logs'), isEmpty);
  });

  testWidgets('源读取失败可以原菜单重试，不打开空白新建页', (tester) async {
    await open(tester);
    await f.db.delete('todo_plan_blocks');
    await reuse(tester);
    expect(key('plan-reuse-notice'), findsNothing);
    expect(find.textContaining('原规划已删除'), findsOneWidget);
    await f.block(source);
    await reuse(tester);
    expect(key('plan-reuse-notice'), findsOneWidget);
  });

  testWidgets('读取中重复点击不会重复开页，离页迟到结果不导航', (tester) async {
    final pending = Completer<PlanReuseSeed>();
    final delayed = _DelayedReuseRepository(pending);
    final seed = await PlanReuseRepository(
      database: f.db,
      clock: () => now,
    ).read(identity.username, source.id);
    await open(tester, reuseRepository: delayed);
    await action(tester, find.byTooltip('更多操作'));
    await tester.tap(find.text('照此新建'));
    await tester.pumpAndSettle();
    expect(delayed.reads, 1);
    await action(tester, find.byTooltip('更多操作'));
    await tester.tap(find.text('正在读取设置…'));
    await tester.pumpAndSettle();
    expect(delayed.reads, 1);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final editorContext = tester.element(find.byType(PlanBlockEditorSheet));
    Navigator.of(editorContext).removeRoute(ModalRoute.of(editorContext)!);
    await tester.pumpAndSettle();
    pending.complete(seed);
    await tester.pumpAndSettle();
    expect(key('plan-reuse-notice'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final setting in [
    (const Size(320, 700), 1.8, Brightness.dark),
    (const Size(390, 844), 1.0, Brightness.light),
    (const Size(720, 360), 1.0, Brightness.light),
    (const Size(1280, 900), 1.0, Brightness.dark),
  ]) {
    testWidgets('复用页布局 ${setting.$1} 字体 ${setting.$2}', (tester) async {
      final seed = await PlanReuseRepository(
        database: f.db,
        clock: () => now,
      ).read(identity.username, source.id);
      await open(
        tester,
        seed: seed,
        size: setting.$1,
        scale: setting.$2,
        brightness: setting.$3,
      );
      expect(key('plan-reuse-notice'), findsOneWidget);
      await tester.ensureVisible(key('plan-option-提前提醒'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
