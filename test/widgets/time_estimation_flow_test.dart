import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/screens/add_todo_screen.dart';
import 'package:countdown_todo/services/api_service.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

void main() {
  late PlanAvailabilityFixture fixture;
  final now = DateTime.now();
  final evidence = find.byKey(const ValueKey('time-estimation-evidence'));
  const result = TimeEstimationResult(
    estimatedMinutes: 75,
    confidence: .4,
    reason: '合成预测',
  );
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 510));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    });
    await tester.pumpAndSettle();
  }

  setUp(() async {
    fixture = PlanAvailabilityFixture();
    await fixture.initialize();
    debugDefaultTargetPlatformOverride = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_coach_add_todo', true);
    ApiService.setBaseUrlOverride('http://127.0.0.1:1');
    for (var i = 0; i < 3; i++) {
      await fixture.todo('done-$i', '复习高数', done: true);
      for (var j = 0; j < 3; j++) {
        final end = now.subtract(Duration(days: 1, minutes: j * 25));
        await fixture.db.insert('pomodoro_records', {
          'uuid': 'record-$i-$j',
          'todo_uuid': 'done-$i',
          'todo_title': '复习高数',
          'start_time': end
              .subtract(const Duration(minutes: 25))
              .millisecondsSinceEpoch,
          'end_time': end.millisecondsSinceEpoch,
          'actual_duration': 1500,
          'planned_duration': 1500,
          'status': 'completed',
          'created_at': end.millisecondsSinceEpoch,
          'updated_at': end.millisecondsSinceEpoch,
        });
      }
    }
  });
  tearDown(() async {
    ApiService.clearBaseUrlOverride();
    await fixture.dispose();
  });

  Future<void> add(
    WidgetTester tester, {
    Future<TimeEstimationResult> Function(String, String?, String)? estimate,
    String? group,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddTodoScreen(
          initialGroupId: group,
          todoGroups: [TodoGroup(id: 'group-one', name: '学习')],
          onTodoAdded: (_) {},
          onFixedScheduleAdded: (_) async {},
          estimate: estimate,
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('新建待办正式服务展示累计75分钟，打开关闭依据不写业务数据', (tester) async {
    final before = await fixture.db.query('op_logs');
    await add(tester);
    await tester.enterText(find.byType(TextField).first, '复习高数');
    await drain(tester);
    expect(find.text('预计专注用时 1小时15分钟'), findsOneWidget);
    await Scrollable.ensureVisible(tester.element(evidence), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(find.text('本次参考 3 个已完成待办'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('time-estimation-close')));
    await tester.pumpAndSettle();
    expect(find.text('复习高数'), findsOneWidget);
    expect(await fixture.db.query('op_logs'), before);
  });

  testWidgets('500ms防抖，旧标题结果不能覆盖新标题，清空立即移除依据', (tester) async {
    final pending = <String, Completer<TimeEstimationResult>>{};
    await add(
      tester,
      estimate: (title, group, account) {
        expect(account, PlanAvailabilityFixture.username);
        return (pending[title] = Completer<TimeEstimationResult>()).future;
      },
    );
    await tester.enterText(find.byType(TextField).first, '复习高数');
    await tester.pump(const Duration(milliseconds: 490));
    expect(pending, isEmpty);
    await drain(tester);
    await tester.enterText(find.byType(TextField).first, '整理笔记');
    await drain(tester);
    pending['整理笔记']!.complete(result);
    await drain(tester);
    pending['复习高数']!.complete(
      const TimeEstimationResult(
        estimatedMinutes: 180,
        confidence: 1,
        reason: '旧结果',
      ),
    );
    await drain(tester);
    expect(find.text('预计专注用时 1小时15分钟'), findsOneWidget);
    expect(find.textContaining('3小时'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(evidence, findsNothing);
  });

  testWidgets('切换分类、日程或销毁页面，迟到的估时不能复活', (tester) async {
    final pending = <Completer<TimeEstimationResult>>[];
    Future<TimeEstimationResult> estimate(
      String title,
      String? group,
      String account,
    ) {
      final item = Completer<TimeEstimationResult>();
      pending.add(item);
      return item.future;
    }

    await add(tester, estimate: estimate, group: 'group-one');
    await tester.enterText(find.byType(TextField).first, '复习高数');
    await drain(tester);
    await add(tester, estimate: estimate, group: 'group-two');
    await drain(tester);
    expect(pending, hasLength(2));
    pending.first.complete(result);
    await drain(tester);
    expect(evidence, findsNothing);
    await tester.tap(find.bySemanticsLabel('日程'));
    await tester.pumpAndSettle();
    pending.last.complete(result);
    await drain(tester);
    expect(evidence, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('账号在估时期间切换，不展示上一账号历史且保留输入', (tester) async {
    final pending = Completer<TimeEstimationResult>();
    await add(tester, estimate: (_, _, _) => pending.future);
    await tester.enterText(find.byType(TextField).first, '复习高数');
    await drain(tester);
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'another-user',
    );
    pending.complete(result);
    await drain(tester);
    expect(evidence, findsNothing);
    expect(find.text('复习高数'), findsOneWidget);
    await tester.runAsync(() async {
      await (await SharedPreferences.getInstance()).setString(
        'current_login_user',
        PlanAvailabilityFixture.username,
      );
    });
  });

  testWidgets('页面销毁后才返回估时，不能更新已销毁页面', (tester) async {
    final pending = Completer<TimeEstimationResult>();
    await add(tester, estimate: (_, _, _) => pending.future);
    await tester.enterText(find.byType(TextField).first, '复习高数');
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    pending.complete(result);
    await drain(tester);
    expect(evidence, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已有结果在前台恢复检查账号后清除，保留输入', (tester) async {
    await add(tester, estimate: (_, _, _) async => result);
    await tester.enterText(find.byType(TextField).first, '复习高数');
    await drain(tester);
    expect(evidence, findsOneWidget);
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      'another-user',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await drain(tester);
    expect(evidence, findsNothing);
    expect(find.text('复习高数'), findsOneWidget);
    await (await SharedPreferences.getInstance()).setString(
      'current_login_user',
      PlanAvailabilityFixture.username,
    );
  });

  for (final change in ['title', 'group']) {
    testWidgets('规划已有估时遇到同一待办对象的$change原地刷新时失效，保留时段', (tester) async {
      final target = TodoItem(id: 'todo-target', title: '复习高数');
      final todos = [target];
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: PlanBlockEditorSheet(
            fullPage: true,
            username: PlanAvailabilityFixture.username,
            startTime: now.add(const Duration(days: 1)),
            endTime: now.add(const Duration(days: 1, minutes: 30)),
            todos: todos,
            todoGroups: const [],
            initialTodoId: target.id,
            autoRecommendTime: true,
            onSaved: () {},
            estimate: (_) async => result,
            clock: () => now,
            availabilityLoader: (q, {bool forceRefresh = false}) async =>
                PlanAvailabilitySnapshot(
                  todo: target,
                  busy: const [],
                  coverage: '合成安排',
                ),
          ),
        ),
      );
      await show();
      addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
      await drain(tester);
      expect(evidence, findsOneWidget);
      expect(find.text('09:15'), findsOneWidget);
      if (change == 'title') {
        target.title = '整理笔记';
      } else {
        target.groupId = 'group-changed';
      }
      await show();
      await drain(tester);
      expect(evidence, findsNothing);
      expect(find.text('09:15'), findsOneWidget);
      expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
      expect(await fixture.db.query('op_logs'), isEmpty);
    });
  }

  testWidgets('正式规划入口按75分钟找两个建议，不增加番茄轮数', (tester) async {
    final queries = <PlanAvailabilityQuery>[];
    final target = TodoItem(id: 'todo-target', title: '复习高数');
    final before = await fixture.db.query('op_logs');
    await tester.pumpWidget(
      MaterialApp(
        home: PlanBlockEditorSheet(
          fullPage: true,
          username: PlanAvailabilityFixture.username,
          startTime: now.add(const Duration(days: 1)),
          endTime: now.add(const Duration(days: 1, minutes: 30)),
          todos: [target],
          todoGroups: const [],
          initialTodoId: target.id,
          autoRecommendTime: true,
          onSaved: () {},
          clock: () => now,
          availabilityLoader: (query, {bool forceRefresh = false}) async {
            queries.add(query);
            return PlanAvailabilitySnapshot(
              todo: target,
              busy: const [],
              coverage: '合成安排',
            );
          },
        ),
      ),
    );
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    await drain(tester);
    expect(queries, hasLength(1));
    expect(queries.single.minutes, 75);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is OutlinedButton &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('plan-slot-'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('预计专注用时 1小时15分钟'), findsOneWidget);
    final dropdowns = tester
        .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
        .toList();
    expect(dropdowns.map((d) => d.value), [25, 0, 5]);
    await Scrollable.ensureVisible(tester.element(evidence), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(find.text('本次参考 3 个已完成待办'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('time-estimation-close')));
    await tester.pumpAndSettle();
    expect(queries, hasLength(1));
    expect(await fixture.db.query('op_logs'), before);
    expect(await fixture.db.query('todo_plan_blocks'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
