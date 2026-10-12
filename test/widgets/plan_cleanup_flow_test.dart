@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_cleanup.dart';
import 'package:countdown_todo/screens/plan_cleanup_screen.dart';
import 'package:countdown_todo/services/plan_cleanup_repository.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../support/plan_availability_fixture.dart';

class _CleanupRepo extends PlanCleanupRepository {
  _CleanupRepo(Database db)
    : super(databaseOverride: db, clock: () => PlanAvailabilityFixture.now);
  bool loseResponse = false;
  bool failNextRead = false;
  bool failNextDetail = false;
  Completer<void>? detailReadGate;
  int calls = 0;
  @override
  Future<PlanCleanupPage> read(
    String username, {
    String search = '',
    String? folder,
    PlanCleanupCursor? cursor,
  }) async {
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
    final gate = detailReadGate;
    if (gate != null) {
      detailReadGate = null;
      await gate.future;
    }
    if (failNextDetail) {
      failNextDetail = false;
      throw StateError('模拟分页读取失败');
    }
    return super.detail(username, todoId, cursor: cursor);
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
          clock: () => now,
          updateReminders: () async {},
        ),
      ),
    );
    await t.pumpAndSettle();
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
    expect(find.text('已选50段 · 2250分钟'), findsOneWidget);
    await tap(t, find.text('加载更多规划（不自动选中）'));
    expect(find.textContaining('已加载52／总计52'), findsOneWidget);
    expect(find.text('已选50段 · 2250分钟'), findsOneWidget);
    expect(t.widget<Checkbox>(key('cleanup-select-p-51')).value, isFalse);
    await tap(t, key('cleanup-select-p-51'));
    expect(find.text('一次最多选择50段'), findsOneWidget);
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
    expect(find.text('已选50段 · 2250分钟'), findsOneWidget);
    expect(find.textContaining('已保留'), findsOneWidget);

    await tap(t, find.text('加载更多规划（不自动选中）'));
    expect(find.textContaining('已加载52／总计52'), findsOneWidget);
    expect(find.text('已选50段 · 2250分钟'), findsOneWidget);
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
