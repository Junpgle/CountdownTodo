@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_cleanup.dart';
import 'package:countdown_todo/screens/plan_cleanup_screen.dart';
import 'package:countdown_todo/services/plan_cleanup_repository.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../support/plan_availability_fixture.dart';

class _CleanupRepo extends PlanCleanupRepository {
  _CleanupRepo(Database db, {DateTime Function()? clock})
    : super(
        databaseOverride: db,
        clock: clock ?? () => PlanAvailabilityFixture.now,
      );
  bool loseResponse = false;
  bool failNextRead = false;
  bool failNextDetail = false;
  bool malformedId = false;
  Completer<void>? detailReadGate;
  Completer<void>? detailResultGate;
  Completer<void>? detailResultStarted;
  int calls = 0;
  int reads = 0;
  int detailReads = 0;
  @override
  Future<PlanCleanupPage> read(
    String username, {
    String search = '',
    String? folder,
    PlanCleanupCursor? cursor,
  }) async {
    reads++;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('模拟分页读取失败');
    }
    return super.read(username, search: search, folder: folder, cursor: cursor);
  }

  @override
  Future<PlanCleanupSnapshot> detail(
    String username,
    String todoId, {
    PlanCleanupCursor? cursor,
  }) async {
    detailReads++;
    final gate = detailReadGate;
    if (gate != null) {
      detailReadGate = null;
      await gate.future;
    }
    if (failNextDetail) {
      failNextDetail = false;
      throw StateError('模拟分页读取失败');
    }
    final snapshot = await super.detail(username, todoId, cursor: cursor);
    final resultGate = detailResultGate;
    if (resultGate != null) {
      detailResultGate = null;
      if (detailResultStarted?.isCompleted == false) {
        detailResultStarted!.complete();
      }
      await resultGate.future;
    }
    if (!malformedId || snapshot.rows.isEmpty) return snapshot;
    return PlanCleanupSnapshot(
      identity: snapshot.identity,
      todo: snapshot.todo,
      rows: [
        PlanCleanupItem({
          ...snapshot.rows.first.row,
          'uuid': null,
          'reason': '规划时间或版本需核对',
        }),
        ...snapshot.rows.skip(1),
      ],
      total: snapshot.total,
      eligible: 0,
      fingerprint: snapshot.fingerprint,
      blockedReason: snapshot.blockedReason,
      nextBoundary: snapshot.nextBoundary,
      restarted: snapshot.restarted,
      next: snapshot.next,
    );
  }

  @override
  Future<List<TodoPlanBlock>> cancel(
    PlanCleanupRequest request, {
    bool sync = true,
  }) async {
    calls++;
    final result = await super.cancel(request, sync: false);
    if (loseResponse) {
      loseResponse = false;
      throw StateError('模拟响应丢失');
    }
    return result;
  }
}

class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  late PlanAvailabilityFixture f;
  late _CleanupRepo repo;
  const user = PlanAvailabilityFixture.username;
  final day = PlanAvailabilityFixture.day, now = PlanAvailabilityFixture.now;
  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> block(
    String id, {
    String todo = 'todo-target',
    int minute = 0,
  }) => f.block(
    TodoPlanBlock(
      id: id,
      todoId: todo,
      startTime: day
          .add(Duration(hours: 10, minutes: minute))
          .millisecondsSinceEpoch,
      endTime: day
          .add(Duration(hours: 10, minutes: minute + 45))
          .millisecondsSinceEpoch,
      plannedMinutes: 45,
    ),
  );
  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester t, {
    String? todo = 'todo-target',
    Size size = const Size(390, 844),
    double scale = 1,
    DateTime Function()? clock,
    bool settle = true,
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
            brightness: scale > 1 ? Brightness.dark : Brightness.light,
          ),
        ),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: PlanCleanupScreen(
          username: user,
          todoId: todo,
          repository: repo,
          clock: clock ?? () => now,
          updateReminders: () async {},
        ),
      ),
    );
    if (settle) await t.pumpAndSettle();
  }

  setUp(() async {
    f = PlanAvailabilityFixture();
    await f.initialize();
    debugDefaultTargetPlatformOverride = null;
    await f.db.update('todos', {'is_completed': 1});
    repo = _CleanupRepo(f.db);
  });
  tearDown(() async => f.dispose());
  testWidgets(
    'confirmation cancel is read only; partial selection writes exactly one plan',
    (t) async {
      await block('a');
      await block('b', minute: 60);
      await open(t);
      await tap(t, key('cleanup-select-b'));
      await tap(t, key('cleanup-cancel'));
      await tap(t, find.text('返回核对'));
      expect(await f.db.query('op_logs'), isEmpty);
      await tap(t, key('cleanup-cancel'));
      await tap(t, key('cleanup-confirm'));
      expect(find.text('已取消1段'), findsOneWidget);
      expect(
        (await f.db.query(
          'todo_plan_blocks',
          orderBy: 'uuid',
        )).map((r) => r['status']),
        [3, 0],
      );
      expect((await f.db.query('op_logs')).length, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('first cancellation timestamp is captured after confirmation', (
    t,
  ) async {
    await block('confirmed-time');
    var current = now;
    repo = _CleanupRepo(f.db, clock: () => current);
    await f.db.update(
      'todo_plan_blocks',
      {'updated_at': current.millisecondsSinceEpoch - 1000},
      where: 'uuid=?',
      whereArgs: ['confirmed-time'],
    );
    await open(t, clock: () => current);
    await tap(t, key('cleanup-cancel'));
    current = current.add(const Duration(hours: 1));

    await tap(t, key('cleanup-confirm'));

    final row = (await f.db.query(
      'todo_plan_blocks',
      where: 'uuid=?',
      whereArgs: ['confirmed-time'],
    )).single;
    expect(row['updated_at'], current.millisecondsSinceEpoch);
    expect(find.text('已取消1段'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('selected summary counts overlapping time only once', (t) async {
    await block('overlap-a');
    await block('overlap-b', minute: 30);
    await open(t);

    expect(find.text('已选2段 · 75分钟'), findsOneWidget);
    await tap(t, key('cleanup-cancel'));
    expect(find.textContaining('共75分钟规划时段'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('malformed plan id is shown as blocked without crashing', (t) async {
    await block('malformed-id');
    repo.malformedId = true;
    await open(t);

    expect(find.text('规划时间或版本需核对'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'malformed reminder metadata is shown as needing review',
    (t) async {
      await block('malformed-reminder-metadata');
      await f.db.update(
        'todo_plan_blocks',
        {'reminder_minutes': 'bad', 'actual_focus_seconds': 'bad'},
        where: 'uuid=?',
        whereArgs: ['malformed-reminder-metadata'],
      );
      await open(t);

      expect(find.textContaining('设置需核对'), findsWidgets);
      await tap(t, find.widgetWithText(TextButton, '查看详情'));
      expect(find.textContaining('提醒：设置需核对'), findsOneWidget);
      expect(find.textContaining('累计专注参考：需核对'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('invalid plan duration is not rendered as a real duration', (
    t,
  ) async {
    await block('invalid-duration');
    await f.db.update(
      'todo_plan_blocks',
      {'planned_minutes': -1},
      where: 'uuid=?',
      whereArgs: ['invalid-duration'],
    );
    await open(t);

    expect(find.textContaining('时长需核对'), findsWidgets);
    expect(find.textContaining('-1分钟'), findsNothing);
    await tap(t, find.widgetWithText(TextButton, '查看详情'));
    expect(find.textContaining('时长需核对'), findsWidgets);
    expect(find.textContaining('-1分钟'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('repeated confirmation cannot pop the cleanup page', (t) async {
    await block('confirm-repeat');
    await open(t);
    await tap(t, key('cleanup-cancel'));
    final confirm = t.widget<FilledButton>(key('cleanup-confirm')).onPressed!;
    confirm();
    confirm();
    await t.pumpAndSettle();

    expect(find.text('已取消1段'), findsOneWidget);
    expect(find.text('剩余规划收尾'), findsOneWidget);
    expect((await f.db.query('op_logs')).length, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets('repeated dialog return keeps the cleanup page open', (t) async {
    await block('return-repeat');
    await open(t);
    await tap(t, key('cleanup-cancel'));
    final back = t.widget<TextButton>(
      find.widgetWithText(TextButton, '返回核对'),
    ).onPressed!;
    back();
    back();
    await t.pumpAndSettle();

    expect(find.text('剩余规划收尾'), findsOneWidget);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(await f.db.query('op_logs'), isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('repeated plan detail action opens one dialog', (t) async {
    await block('detail-repeat');
    await open(t);
    final inspect = t
        .widget<TextButton>(find.widgetWithText(TextButton, '查看详情').first)
        .onPressed!;
    inspect();
    inspect();
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('规划核对'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'new source while confirming rejects all and requires fresh selection',
    (t) async {
      await block('a');
      await block('b', minute: 60);
      await open(t);
      await tap(t, key('cleanup-cancel'));
      await block('late', minute: 120);
      await tap(t, key('cleanup-confirm'));
      expect(find.textContaining('已变化'), findsWidgets);
      expect(await f.db.query('op_logs'), isEmpty);
      await tap(t, find.text('重新核对').last);
      expect(find.text('已选0段 · 0分钟'), findsOneWidget);
      expect(find.textContaining('总计3段'), findsOneWidget);
    },
  );
  testWidgets(
    'lost response survives refresh and retries the same committed request',
    (t) async {
      await block('a');
      await block('b', minute: 60);
      repo.loseResponse = true;
      await open(t);
      await tap(t, key('cleanup-cancel'));
      await tap(t, key('cleanup-confirm'));
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.text('重试本次提交'), findsOneWidget);
      await tap(t, key('cleanup-cancel'));
      await tap(t, key('cleanup-confirm'));
      expect(repo.calls, 2);
      expect(find.text('已取消2段'), findsOneWidget);
      expect((await f.db.query('op_logs')).length, 2);
    },
  );
  testWidgets('paging never selects new pages or exceeds 50', (t) async {
    for (var i = 0; i < 52; i++) {
      await block('p-$i', minute: i);
    }
    await open(t);
    expect(find.text('已选50段 · 94分钟'), findsOneWidget);
    await tap(t, find.text('加载更多规划（不自动选中）'));
    expect(find.textContaining('已加载52／总计52'), findsOneWidget);
    expect(find.text('已选50段 · 94分钟'), findsOneWidget);
    expect(t.widget<Checkbox>(key('cleanup-select-p-51')).value, isFalse);
    await tap(t, key('cleanup-select-p-51'));
    expect(find.text('一次最多选择50段'), findsOneWidget);
  });
  testWidgets('search disables stale overview results while filtering', (
    t,
  ) async {
    await f.todo('filter-old', '筛选前待办', done: true);
    await block('filter-old-plan', todo: 'filter-old');
    await open(t, todo: null);

    await t.enterText(key('cleanup-search'), '不存在的待办');
    await t.pump();

    expect(find.text('筛选前待办'), findsOneWidget);
    expect(
      t.widget<InkWell>(key('cleanup-todo-filter-old')).onTap,
      isNull,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.text('筛选前待办'), findsNothing);
    expect(find.text('当前筛选下没有待办'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('refresh locks selection and explains clearing it', (t) async {
    await block('refresh-selection');
    await open(t);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    final gate = Completer<void>();
    repo.detailReadGate = gate;

    await t.tap(find.byTooltip('重新核对'));
    await t.pump();

    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(
      t.widget<Checkbox>(key('cleanup-select-refresh-selection')).onChanged,
      isNull,
    );

    gate.complete();
    await t.pumpAndSettle();
    expect(find.text('已选0段 · 0分钟'), findsOneWidget);
    expect(find.textContaining('原有选择已清空'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('unrelated data refresh preserves reviewed selection', (t) async {
    await block('unrelated-refresh');
    await open(t);
    final readsBefore = repo.detailReads;

    StorageService.triggerRefresh(const {DataRefreshDomain.finance});
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('unchanged detail fingerprint preserves reviewed selection', (
    t,
  ) async {
    await block('unchanged-refresh');
    await open(t);
    final readsBefore = repo.detailReads;

    StorageService.triggerRefresh(const {DataRefreshDomain.planBlocks});
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore + 1);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('folder refresh does not reread plan details', (t) async {
    await block('folder-refresh');
    await open(t);
    final readsBefore = repo.detailReads;

    StorageService.triggerRefresh(const {DataRefreshDomain.todoGroups});
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('focus updates refresh only the focused todo', (t) async {
    await block('focus-target');
    await open(t);
    final readsBefore = repo.detailReads;

    await PomodoroService.saveRunState(
      PomodoroRunState(
        phase: PomodoroPhase.focusing,
        todoUuid: 'other-todo',
      ),
    );
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);

    StorageService.triggerRefresh(const {DataRefreshDomain.pomodoro});
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore + 1);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);

    await PomodoroService.saveRunState(
      PomodoroRunState(
        phase: PomodoroPhase.focusing,
        todoUuid: 'todo-target',
      ),
    );
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore + 2);
    expect(find.text('已选0段 · 0分钟'), findsOneWidget);
    expect(find.textContaining('专注'), findsWidgets);

    await PomodoroService.saveRunState(
      PomodoroRunState(phase: PomodoroPhase.idle),
    );
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore + 3);
    expect(find.text('已选0段 · 0分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('focus clear during initial read does not leave stale blocking', (
    t,
  ) async {
    await block('focus-load-race');
    await PomodoroService.saveRunState(
      PomodoroRunState(
        phase: PomodoroPhase.focusing,
        todoUuid: 'todo-target',
      ),
    );
    final gate = Completer<void>();
    final started = Completer<void>();
    repo.detailResultGate = gate;
    repo.detailResultStarted = started;
    await open(t, settle: false);
    await started.future;
    expect(repo.detailReads, 1);

    await PomodoroService.saveRunState(
      PomodoroRunState(phase: PomodoroPhase.idle),
    );
    await t.pump();
    expect(repo.detailReads, 2);
    gate.complete();
    await t.pumpAndSettle();

    expect(repo.detailReads, 2);
    expect(find.text('待办已完成 · 可处理1段'), findsOneWidget);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(find.text('此待办正在专注或已暂停，请先查看当前专注'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('first successful detail read defaults selection after retry', (
    t,
  ) async {
    await block('initial-read-retry');
    repo.failNextDetail = true;
    await open(t);

    expect(find.textContaining('模拟分页读取失败'), findsOneWidget);
    await tap(t, find.widgetWithText(TextButton, '重新核对'));

    expect(find.text('待办已完成 · 可处理1段'), findsOneWidget);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('unrelated task boundary preserves reviewed selection', (t) async {
    await block('target-boundary');
    await f.todo('other-boundary', '其他待办');
    await f.block(
      TodoPlanBlock(
        id: 'other-boundary-block',
        todoId: 'other-boundary',
        startTime: now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        endTime: now.add(const Duration(minutes: 46)).millisecondsSinceEpoch,
        plannedMinutes: 45,
      ),
    );
    await open(t);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    final readsBefore = repo.detailReads;

    await t.pump(const Duration(minutes: 1));
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('cancelled plan boundary preserves reviewed selection', (t) async {
    await block('target-active');
    await f.block(
      TodoPlanBlock(
        id: 'target-cancelled',
        todoId: 'todo-target',
        startTime: now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        endTime: now.add(const Duration(minutes: 46)).millisecondsSinceEpoch,
        plannedMinutes: 45,
        status: TodoPlanStatus.cancelled,
      ),
    );
    await open(t);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    final readsBefore = repo.detailReads;

    await t.pump(const Duration(minutes: 1));
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('midnight without a plan boundary preserves reviewed selection', (
    t,
  ) async {
    await block('midnight-boundary');
    await open(t);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    final readsBefore = repo.detailReads;

    await t.pump(const Duration(hours: 12));
    await t.pumpAndSettle();

    expect(repo.detailReads, readsBefore);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('refresh read failure preserves selection for retry', (t) async {
    await block('refresh-retry');
    await open(t);
    repo.failNextDetail = true;

    await tap(t, find.byTooltip('重新核对'));

    expect(find.text('已选1段 · 45分钟'), findsOneWidget);
    expect(find.textContaining('已保留当前已加载内容和选择'), findsOneWidget);
    await tap(t, find.widgetWithText(TextButton, '重新核对'));
    expect(find.text('已选0段 · 0分钟'), findsOneWidget);
    expect(find.textContaining('原有选择已清空'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('detail paging failure preserves reviewed selection for retry', (
    t,
  ) async {
    for (var i = 0; i < 52; i++) {
      await block('retry-detail-$i', minute: i);
    }
    await open(t);
    repo.failNextDetail = true;
    await tap(t, find.text('加载更多规划（不自动选中）'));
    expect(repo.failNextDetail, isFalse);

    expect(find.textContaining('已加载50／总计52'), findsOneWidget);
    expect(find.text('已选50段 · 94分钟'), findsOneWidget);
    expect(find.textContaining('已保留'), findsOneWidget);

    await tap(t, find.text('加载更多规划（不自动选中）'));
    expect(find.textContaining('已加载52／总计52'), findsOneWidget);
    expect(find.text('已选50段 · 94分钟'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('overview paging failure keeps loaded rows and retries', (t) async {
    for (var i = 0; i < 51; i++) {
      final id = 'retry-overview-$i';
      await f.todo(id, '待办$i', done: true);
      await block('retry-overview-plan-$i', todo: id, minute: i);
    }
    await open(t, todo: null);
    repo.failNextRead = true;
    await tap(t, find.text('加载更多待办'));
    expect(repo.failNextRead, isFalse);

    expect(find.textContaining('已加载50／总计51'), findsOneWidget);
    expect(find.text('待办0'), findsOneWidget);
    expect(find.textContaining('已保留'), findsOneWidget);

    await tap(t, find.text('加载更多待办'));
    expect(find.textContaining('已加载51／总计51'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('overview ignores boundaries from unfinished todos', (t) async {
    for (var i = 0; i < 51; i++) {
      final id = 'boundary-overview-$i';
      await f.todo(id, '待办$i', done: true);
      await block('boundary-overview-plan-$i', todo: id, minute: 120 + i);
    }
    await f.todo('unfinished-boundary', '未完成待办', done: false);
    await f.block(
      TodoPlanBlock(
        id: 'unfinished-boundary-plan',
        todoId: 'unfinished-boundary',
        startTime: now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        endTime: now.add(const Duration(minutes: 46)).millisecondsSinceEpoch,
        plannedMinutes: 45,
      ),
    );
    await open(t, todo: null);
    await tap(t, find.text('加载更多待办'));
    expect(find.textContaining('已加载51／总计51'), findsOneWidget);
    final readsBeforeBoundary = repo.reads;

    await t.pump(const Duration(minutes: 1));
    await t.pumpAndSettle();

    expect(repo.reads, readsBeforeBoundary);
    expect(find.textContaining('已加载51／总计51'), findsOneWidget);
    expect(find.text('待办50'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('overview boundary refresh keeps already loaded pages', (t) async {
    var testNow = now;
    repo = _CleanupRepo(f.db, clock: () => testNow);
    for (var i = 0; i < 51; i++) {
      final id = 'loaded-boundary-$i';
      await f.todo(id, '分页待办$i', done: true);
      if (i == 0) {
        final start = now.add(const Duration(minutes: 1));
        await f.block(
          TodoPlanBlock(
            id: 'loaded-boundary-plan-$i',
            todoId: id,
            startTime: start.millisecondsSinceEpoch,
            endTime: start.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
            plannedMinutes: 45,
          ),
        );
      } else {
        await block('loaded-boundary-plan-$i', todo: id, minute: 120 + i);
      }
    }
    await open(t, todo: null, clock: () => testNow);
    await tap(t, find.text('加载更多待办'));
    expect(find.textContaining('已加载51／总计51'), findsOneWidget);

    testNow = testNow.add(const Duration(minutes: 1));
    await t.pump(const Duration(minutes: 1));
    await t.pumpAndSettle();

    expect(find.textContaining('已加载51／总计51'), findsOneWidget);
    expect(find.text('分页待办50'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('overview resume keeps already loaded pages', (t) async {
    for (var i = 0; i < 51; i++) {
      final id = 'resume-overview-$i';
      await f.todo(id, '恢复待办$i', done: true);
      await block('resume-overview-plan-$i', todo: id, minute: 120 + i);
    }
    await open(t, todo: null);
    await tap(t, find.text('加载更多待办'));
    expect(find.textContaining('已加载51／总计51'), findsOneWidget);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();

    expect(find.textContaining('已加载51／总计51'), findsOneWidget);
    expect(find.text('恢复待办50'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('overview timer read failure preserves loaded rows', (t) async {
    var testNow = now;
    repo = _CleanupRepo(f.db, clock: () => testNow);
    await f.todo('visible-boundary', '可见待办', done: true);
    await f.block(
      TodoPlanBlock(
        id: 'visible-boundary-plan',
        todoId: 'visible-boundary',
        startTime: now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        endTime: now.add(const Duration(minutes: 46)).millisecondsSinceEpoch,
        plannedMinutes: 45,
      ),
    );
    await open(t, todo: null, clock: () => testNow);
    expect(find.text('可见待办'), findsOneWidget);
    final readsBeforeBoundary = repo.reads;
    repo.failNextRead = true;

    testNow = testNow.add(const Duration(minutes: 1));
    await t.pump(const Duration(minutes: 1));
    await t.pumpAndSettle();

    expect(repo.reads, readsBeforeBoundary + 1);
    expect(find.text('可见待办'), findsOneWidget);
    expect(find.textContaining('已保留当前已加载内容'), findsOneWidget);

    await t.pump(const Duration(minutes: 1));
    await t.pumpAndSettle();
    expect(repo.reads, readsBeforeBoundary + 1);
    expect(t.takeException(), isNull);
  });
  testWidgets('manual overview refresh failure preserves loaded rows', (
    t,
  ) async {
    await f.todo('manual-refresh', '当前待办', done: true);
    await block('manual-refresh-plan', todo: 'manual-refresh', minute: 120);
    await open(t, todo: null);
    repo.failNextRead = true;

    await tap(t, find.byTooltip('重新核对'));

    expect(find.text('当前待办'), findsOneWidget);
    expect(find.textContaining('已保留当前已加载内容'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('overview search cancels the previous boundary timer', (t) async {
    final testNow = now;
    repo = _CleanupRepo(f.db, clock: () => testNow);
    await f.todo('search-boundary', '搜索目标', done: true);
    final start = now.add(const Duration(milliseconds: 250));
    await f.block(
      TodoPlanBlock(
        id: 'search-boundary-plan',
        todoId: 'search-boundary',
        startTime: start.millisecondsSinceEpoch,
        endTime: start.add(const Duration(minutes: 45)).millisecondsSinceEpoch,
        plannedMinutes: 45,
      ),
    );
    await open(t, todo: null, clock: () => testNow);
    final readsBeforeSearch = repo.reads;

    await t.enterText(key('cleanup-search'), '搜索目标');
    await t.pump(const Duration(milliseconds: 250));
    await t.pumpAndSettle();

    expect(repo.reads, readsBeforeSearch + 1);
    expect(find.textContaining('总计1个待办'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('manual refresh cancels a pending overview search', (t) async {
    await f.todo('manual-search', '搜索目标', done: true);
    await block('manual-search-plan', todo: 'manual-search', minute: 120);
    await open(t, todo: null);
    final readsBeforeSearch = repo.reads;

    await t.enterText(key('cleanup-search'), '搜索目标');
    final refresh = find.ancestor(
      of: find.byIcon(Icons.refresh),
      matching: find.byType(IconButton),
    );
    t.widget<IconButton>(refresh).onPressed!();
    await t.pump();
    expect(repo.reads, readsBeforeSearch + 1);

    await t.pump(const Duration(milliseconds: 250));
    await t.pumpAndSettle();

    expect(repo.reads, readsBeforeSearch + 1);
    expect(find.textContaining('总计1个待办'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('pagination account switch clears the previous account page', (
    t,
  ) async {
    for (var i = 0; i < 51; i++) {
      final id = 'switch-overview-$i';
      await f.todo(id, '切换待办$i', done: true);
      await block('switch-overview-plan-$i', todo: id, minute: i);
    }
    await open(t, todo: null);
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'other',
    );
    t
        .widget<TextButton>(find.widgetWithText(TextButton, '加载更多待办'))
        .onPressed!();
    await t.pumpAndSettle();

    expect(find.text('切换待办0'), findsNothing);
    expect(find.textContaining('身份已切换'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'overview explains when changed data restarts pagination',
    (t) async {
      for (var i = 0; i < 51; i++) {
        final id = 'overview-$i';
        await f.todo(id, '待办$i', done: true);
        await block('overview-plan-$i', todo: id, minute: i);
      }
      await open(t, todo: null);
      expect(find.textContaining('已加载50／总计51'), findsOneWidget);

      await f.todo('overview-new', '新增待办', done: true);
      await block('overview-new-plan', todo: 'overview-new', minute: -30);
      await tap(t, find.text('加载更多待办'));

      expect(find.textContaining('已加载50／总计52'), findsOneWidget);
      expect(find.textContaining('列表已变化'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('team plans are read-only with explicit reasons', (t) async {
    final semantics = t.ensureSemantics();
    await block('a');
    await f.db.update('todos', {'team_uuid': 'team'});
    await open(t);
    expect(find.text('团队规划请逐条核对'), findsWidgets);
    expect(t.widget<FilledButton>(key('cleanup-cancel')).onPressed, isNull);
    expect(t.widget<Checkbox>(key('cleanup-select-a')).onChanged, isNull);
    expect(
      t.getSemantics(key('cleanup-select-a')).label,
      contains('45分钟'),
    );
    final details = find.widgetWithText(TextButton, '查看详情');
    expect(
      t.getSemantics(details),
      matchesSemantics(
        label: '查看详情',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tap(t, details);
    expect(find.text('规划核对'), findsOneWidget);
    expect(await f.db.query('op_logs'), isEmpty);
    semantics.dispose();
  });
  testWidgets('literal search opens the exact completed task', (t) async {
    await block('a');
    await f.todo('second', '100%_完成', done: true);
    await block('b', todo: 'second');
    await open(t, todo: null);
    await t.enterText(key('cleanup-search'), '%_');
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.text('复习高数'), findsNothing);
    await tap(t, find.text('100%_完成'));
    expect(key('cleanup-select-b'), findsOneWidget);
    expect(key('cleanup-select-a'), findsNothing);
  });
  testWidgets('foreground identity change invalidates old selection', (
    t,
  ) async {
    await block('a');
    await open(t);
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'other',
    );
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.textContaining('身份已切换'), findsOneWidget);
    expect(t.widget<FilledButton>(key('cleanup-cancel')).onPressed, isNull);
  });
  testWidgets('same-account resume explains cleared selection', (t) async {
    await block('resume-selection');
    await open(t);
    expect(find.text('已选1段 · 45分钟'), findsOneWidget);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();

    expect(find.text('已选0段 · 0分钟'), findsOneWidget);
    expect(find.textContaining('原有选择已清空'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('foreground account change clears a pending retry page', (
    t,
  ) async {
    await block('pending-account-switch');
    repo.loseResponse = true;
    await open(t);
    await tap(t, key('cleanup-cancel'));
    await tap(t, key('cleanup-confirm'));
    expect(find.text('重试本次提交'), findsOneWidget);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('重试本次提交'), findsOneWidget);

    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'other',
    );
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();

    expect(find.text('复习高数'), findsNothing);
    expect(find.textContaining('身份已切换'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('retry after account change clears the pending page', (t) async {
    await block('retry-account-switch');
    repo.loseResponse = true;
    await open(t);
    await tap(t, key('cleanup-cancel'));
    await tap(t, key('cleanup-confirm'));
    expect(find.text('重试本次提交'), findsOneWidget);

    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'other',
    );
    await tap(t, key('cleanup-cancel'));

    expect(find.text('复习高数'), findsNothing);
    expect(find.textContaining('身份已切换'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'entry requires persisted completion and shows read errors separately',
    (t) async {
      await block('a');
      Future<void> entry(bool saved) async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlanCleanupEntry(
                username: user,
                todoId: 'todo-target',
                completionSaved: saved,
                repository: repo,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await entry(false);
      expect(find.textContaining('请先保存'), findsOneWidget);
      await entry(true);
      expect(find.text('处理剩余规划 · 1段'), findsOneWidget);
      await f.db.execute('DROP TABLE pomodoro_records');
      StorageService.triggerRefresh(const {DataRefreshDomain.planBlocks});
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.text('剩余规划读取失败，点击重试'), findsOneWidget);
    },
  );
  testWidgets('entry coalesces rapid repeated opens into one route', (t) async {
    await block('entry-open');
    final pushes = _PushCounter();
    await t.pumpWidget(
      MaterialApp(
        navigatorObservers: [pushes],
        home: Scaffold(
          body: PlanCleanupEntry(
            username: user,
            todoId: 'todo-target',
            completionSaved: true,
            repository: repo,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final before = pushes.pushes;
    final open = t.widget<TextButton>(key('todo-cleanup-plans')).onPressed!;
    open();
    open();
    await t.pumpAndSettle();

    expect(pushes.pushes - before, 1);
    expect(find.text('剩余规划收尾'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final size in [const Size(320, 844), const Size(1280, 900)]) {
    testWidgets('responsive ${size.width} with readable confirmation', (
      t,
    ) async {
      await block('a');
      await open(t, size: size, scale: size.width == 320 ? 1.8 : 1);
      await tap(t, key('cleanup-cancel'));
      expect(t.takeException(), isNull);
      await tap(t, find.text('返回核对'));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
  }
}
