import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/plan_drag_service.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../support/plan_availability_fixture.dart';

class TestDragService extends PlanDragService {
  DateTime? testNow;
  @override
  DateTime get now => testNow ?? super.now;
  bool failSave = false, failUndo = false;
  Completer<void>? release;
  @override
  Future<PlanDragChange?> save(
    PlanDragSnapshot snapshot,
    PlanDragTimes times, {
    bool sync = true,
  }) async {
    await release?.future;
    if (failSave) throw const PlanDragException('合成保存失败');
    return super.save(snapshot, times, sync: false);
  }

  @override
  Future<TodoPlanBlock> undo(PlanDragChange change, {bool sync = true}) async {
    if (failUndo) throw const PlanDragException('合成撤销失败，请重试');
    return super.undo(change, sync: false);
  }
}

void main() {
  late PlanAvailabilityFixture fixture;
  late DateTime day;
  late TodoPlanBlock original;
  late TestDragService service;
  DateTime at(int h, [int m = 0]) =>
      DateTime(day.year, day.month, day.day, h, m);
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> host(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light,
    bool glass = false,
    Future<void> Function()? seed,
  }) async {
    await tester.runAsync(() async {
      fixture = PlanAvailabilityFixture();
      await fixture.initialize();
      debugDefaultTargetPlatformOverride = null;
      await LiquidGlassEffectService.setEnabled(glass);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tip_shown_todo_plan_guide', true);
      final now = DateTime.now();
      day = DateTime(now.year, now.month, now.day + 1);
      original = TodoPlanBlock(
        id: 'drag-plan',
        todoId: 'todo-target',
        titleSnapshot: '复习高数',
        startTime: at(22, 30).millisecondsSinceEpoch,
        endTime: at(23, 30).millisecondsSinceEpoch,
        plannedMinutes: 60,
        actualFocusSeconds: 300,
        remark: '保留备注',
        calendarEventId: 'calendar',
        pomodoroRecordIds: ['record'],
        deviceId: 'device',
      );
      await fixture.block(original);
      service = TestDragService();
      await seed?.call();
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => fixture.dispose());
      await LiquidGlassEffectService.setEnabled(false);
      GlassPerformanceMonitor.stop();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: TodoPlanScreen(
          username: PlanAvailabilityFixture.username,
          initialDate: day,
          dragService: service,
        ),
      ),
    );
    await settle(tester);
  }

  Finder movable() => find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onLongPressStart != null,
  );
  Finder grid() => find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onPanStart != null && w.onTapDown != null,
  );
  Future<TodoPlanBlock> persisted(WidgetTester tester) async =>
      TodoPlanBlock.fromJson(
        (await tester.runAsync(
          () => fixture.db.query(
            'todo_plan_blocks',
            where: 'uuid = ?',
            whereArgs: ['drag-plan'],
          ),
        ))!.single,
      );
  Future<void> move(
    WidgetTester tester, {
    double minutes = -60,
    bool cancel = false,
  }) async {
    final hourHeight = tester.getSize(grid()).height / 24;
    final gesture = await tester.startGesture(
      tester.getCenter(movable().first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(Offset(0, hourHeight * minutes / 60));
    await tester.pump();
    if (cancel) {
      await gesture.cancel();
    } else {
      await gesture.up();
    }
    await settle(tester);
  }

  Future<List<Map<String, Object?>>> logs(WidgetTester tester) async =>
      (await tester.runAsync(() => fixture.db.query('op_logs')))!;
  Finder undo() => find.byKey(const ValueKey('plan-drag-undo'));

  testWidgets('整块移到午夜边界保持原60分钟，不截短', (tester) async {
    await host(tester);
    final hourHeight = tester.getSize(grid()).height / 24;
    final gesture = await tester.startGesture(
      tester.getCenter(movable().first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(Offset(0, hourHeight * .75));
    await tester.pump();
    await gesture.up();
    await settle(tester);
    final saved = await persisted(tester);
    expect(saved.plannedMinutes, 60);
    expect(saved.startTime, at(23).millisecondsSinceEpoch);
    expect(saved.endTime, at(24).millisecondsSinceEpoch);
    expect(tester.takeException(), isNull);
  });
  testWidgets('长按未移动零写入零版本变化', (tester) async {
    await host(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(movable().first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await settle(tester);
    expect((await persisted(tester)).toJson(), original.toJson());
    expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('保存后六秒提示消失仍可撤销，只恢复原时间并递增版本', (tester) async {
    await host(tester);
    await move(tester);
    expect(undo(), findsOneWidget);
    expect(find.textContaining('已调整「复习高数」'), findsOneWidget);
    expect(
      (await persisted(tester)).startTime,
      at(21, 30).millisecondsSinceEpoch,
    );
    expect(await logs(tester), hasLength(1));
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('撤销'), findsNothing);
    expect(undo(), findsOneWidget);
    await tester.tap(undo());
    await settle(tester);
    final saved = await persisted(tester);
    final expected = original.toJson()
      ..['version'] = original.version + 2
      ..['updated_at'] = saved.updatedAt;
    expect(saved.toJson(), expected);
    expect(await logs(tester), hasLength(2));
    expect(find.text('已恢复原时段'), findsOneWidget);
    expect(undo(), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('选择提示撤销与工具按钮共用同一身份，连击一次', (tester) async {
    await host(tester);
    await move(tester);
    await tester.tap(find.text('撤销'));
    await tester.tap(undo(), warnIfMissed: false);
    await settle(tester);
    expect((await persisted(tester)).startTime, original.startTime);
    expect(await logs(tester), hasLength(2));
  });
  testWidgets('手势取消或移回原位置零写入，不覆盖已有撤销机会', (tester) async {
    await host(tester);
    await move(tester, cancel: true);
    expect((await persisted(tester)).toJson(), original.toJson());
    expect(await logs(tester), isEmpty);
    await move(tester);
    await move(tester, cancel: true);
    expect(undo(), findsOneWidget);
    expect(await logs(tester), hasLength(1));
    final origin = tester.getCenter(movable().first);
    final gesture = await tester.startGesture(origin);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveTo(origin);
    await tester.pump();
    await gesture.up();
    await settle(tester);
    expect(await logs(tester), hasLength(1));
    expect(undo(), findsOneWidget);
  });
  testWidgets('最新一次调整替换撤销上下文，撤销不跳回更早时段', (tester) async {
    await host(tester);
    await move(tester);
    await move(tester);
    expect(
      (await persisted(tester)).startTime,
      at(20, 30).millisecondsSinceEpoch,
    );
    await tester.tap(undo());
    await settle(tester);
    expect(
      (await persisted(tester)).startTime,
      at(21, 30).millisecondsSinceEpoch,
    );
    expect(await logs(tester), hasLength(3));
    expect(undo(), findsNothing);
  });
  for (final start in [false, true]) {
    testWidgets('慢速小位移累计缩放${start ? '开始' : '结束'}，不修改预览外数据', (tester) async {
      await host(tester);
      final handle = find.byKey(
        ValueKey('plan-resize-${start ? 'start' : 'end'}-drag-plan'),
      );
      final width = tester.getSize(grid()).width;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(Offset(width * .25 / 20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect((await persisted(tester)).toJson(), original.toJson());
      expect((await persisted(tester)).plannedMinutes, 60);
      await gesture.up();
      await settle(tester);
      final saved = await persisted(tester);
      expect(
        start ? saved.startTime : saved.endTime,
        (start ? at(22, 45) : at(23, 45)).millisecondsSinceEpoch,
      );
      expect(saved.plannedMinutes, start ? 45 : 75);
      expect(await logs(tester), hasLength(1));
      await tester.tap(undo());
      await settle(tester);
      expect((await persisted(tester)).plannedMinutes, 60);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('保存失败回到真实位置并保留上一次撤销，撤销失败可重试', (tester) async {
    await host(tester);
    await move(tester);
    service.failSave = true;
    await move(tester);
    expect(find.text('合成保存失败'), findsOneWidget);
    expect(
      (await persisted(tester)).startTime,
      at(21, 30).millisecondsSinceEpoch,
    );
    expect(undo(), findsOneWidget);
    service.failUndo = true;
    await tester.tap(undo());
    await settle(tester);
    expect(undo(), findsOneWidget);
    expect(await logs(tester), hasLength(1));
    service.failUndo = false;
    await tester.tap(undo());
    await settle(tester);
    expect((await persisted(tester)).startTime, original.startTime);
    expect(await logs(tester), hasLength(2));
  });
  testWidgets('预览期间同版本内容变化立即清除，松手不覆盖最新记录', (tester) async {
    await host(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(movable().first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await tester.runAsync(
      () => fixture.db.update(
        'todo_plan_blocks',
        {'remark': '最新备注'},
        where: 'uuid = ?',
        whereArgs: ['drag-plan'],
      ),
    );
    StorageService.triggerRefresh(const {DataRefreshDomain.planBlocks});
    await settle(tester);
    await gesture.up();
    await settle(tester);
    expect((await persisted(tester)).remark, '最新备注');
    expect((await persisted(tester)).startTime, original.startTime);
    expect(await logs(tester), isEmpty);
  });
  testWidgets('后来记录变更自动清除过期撤销，不倒改', (tester) async {
    await host(tester);
    await move(tester);
    await tester.runAsync(
      () => fixture.db.update(
        'todo_plan_blocks',
        {'remark': '最新备注'},
        where: 'uuid = ?',
        whereArgs: ['drag-plan'],
      ),
    );
    StorageService.triggerRefresh(const {DataRefreshDomain.planBlocks});
    await settle(tester);
    expect(undo(), findsNothing);
    expect((await persisted(tester)).remark, '最新备注');
    expect(await logs(tester), hasLength(1));
  });
  testWidgets('切日和离页再进入清除撤销；后台取消未提交预览', (tester) async {
    await host(tester);
    await move(tester);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await settle(tester);
    expect(undo(), findsNothing);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await settle(tester);
    expect(undo(), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(movable().first),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(await logs(tester), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: TodoPlanScreen(
          username: PlanAvailabilityFixture.username,
          initialDate: day,
          dragService: service,
        ),
      ),
    );
    await settle(tester);
    expect(undo(), findsNothing);
  });
  testWidgets('提交后切日不把旧保存提示和撤销放到新日期', (tester) async {
    await host(tester);
    service.release = Completer<void>();
    await move(tester);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await settle(tester);
    service.release!.complete();
    await settle(tester);
    expect(undo(), findsNothing);
    expect(find.textContaining('已调整「'), findsNothing);
    expect(await logs(tester), hasLength(1));
    expect(
      (await persisted(tester)).startTime,
      at(21, 30).millisecondsSinceEpoch,
    );
  });
  for (final status in [
    TodoPlanStatus.focusing,
    TodoPlanStatus.finished,
    TodoPlanStatus.missed,
    TodoPlanStatus.skipped,
    TodoPlanStatus.cancelled,
  ]) {
    testWidgets('${status.name}真实规划只读，拖动不会新建', (tester) async {
      await host(
        tester,
        seed: () async {
          await fixture.db.update('todo_plan_blocks', {'status': status.index});
        },
      );
      expect(movable(), findsNothing);
      expect(
        find.byKey(const ValueKey('plan-resize-start-drag-plan')),
        findsNothing,
      );
      await tester.drag(find.text('复习高数').first, const Offset(30, -30));
      await settle(tester);
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
      expect(await logs(tester), isEmpty);
    });
  }
  testWidgets('当前专注运行标记即使状态未回写也禁止拖动', (tester) async {
    await host(
      tester,
      seed: () => PomodoroService.saveRunState(
        PomodoroRunState(
          phase: PomodoroPhase.focusing,
          planBlockId: 'drag-plan',
        ),
      ),
    );
    expect(movable(), findsNothing);
    expect(await logs(tester), isEmpty);
  });
  testWidgets('撤销原时段过期或账号切换后不留旧入口', (tester) async {
    await host(tester);
    await move(tester);
    service.testNow = at(24);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(undo(), findsNothing);
    expect(await logs(tester), hasLength(1));
    await tester.pumpWidget(
      MaterialApp(
        home: TodoPlanScreen(username: 'other', initialDate: day),
      ),
    );
    await settle(tester);
    expect(undo(), findsNothing);
    expect(await logs(tester), hasLength(1));
  });
  testWidgets('保存未完成时账号切换拒绝旧写入', (tester) async {
    await host(tester);
    service.release = Completer<void>();
    await move(tester);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'other');
    service.release!.complete();
    await settle(tester);
    expect(await logs(tester), isEmpty);
    expect((await persisted(tester)).toJson(), original.toJson());
    expect(undo(), findsNothing);
  });
  for (final config in [
    (const Size(320, 640), 1.6, Brightness.light, false),
    (const Size(390, 844), 1.0, Brightness.dark, true),
    (const Size(720, 360), 1.6, Brightness.dark, true),
    (const Size(1280, 900), 2.0, Brightness.light, false),
  ]) {
    testWidgets('正式全天一屏撤销可达，无溢出 $config', (tester) async {
      await host(
        tester,
        size: config.$1,
        scale: config.$2,
        brightness: config.$3,
        glass: config.$4,
      );
      await move(tester);
      expect(undo(), findsOneWidget);
      expect(
        find.ancestor(of: grid(), matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(
        tester.getBottomRight(find.text('23:00')).dy,
        lessThanOrEqualTo(config.$1.height + 0.01),
      );
      await tester.tap(undo());
      await settle(tester);
      expect((await persisted(tester)).startTime, original.startTime);
      expect(tester.takeException(), isNull);
    });
  }
}
