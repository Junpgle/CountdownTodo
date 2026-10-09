import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/todo_plan_screen.dart';
import 'package:countdown_todo/models/plan_availability.dart';
import 'package:countdown_todo/services/plan_availability_repository.dart';
import 'package:countdown_todo/services/plan_availability_preferences.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:countdown_todo/widgets/plan_block_editor_sheet.dart';
import 'package:countdown_todo/widgets/plan_availability_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/plan_availability_fixture.dart';

final day = DateTime(2026, 10, 8);
final now = DateTime(2026, 10, 7, 12);
final target = TodoItem(
  id: 'todo-editor',
  title: '复习高数',
  dueDate: DateTime(2026, 10, 8, 20),
  createdDate: DateTime(2026, 10, 8, 20).millisecondsSinceEpoch,
);
final other = TodoItem(id: 'todo-other', title: '整理笔记');
Finder key(String value) => find.byKey(ValueKey(value));
DropdownButton<String> todoDropdown(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
Future<void> tap(WidgetTester tester, String value) async {
  await tester.ensureVisible(key(value));
  await tester.tap(key(value));
  await tester.pump();
  if (value == 'plan-find-time') await tester.pumpAndSettle();
}

Future<void> showEditor(
  WidgetTester tester, {
  required PlanEditorSaver? saver,
  Future<void> Function(TodoPlanBlock, TodoItem)? focus,
  PlanAvailabilityLoader? loader,
  Future<TimeEstimationResult> Function(TodoItem)? estimate,
  TodoPlanBlock? block,
  bool autoRecommendTime = false,
  bool fullPage = false,
  List<TodoItem>? todos,
  String? initialTodoId,
  Size size = const Size(1000, 900),
  double scale = 1,
  double keyboard = 0,
  Brightness brightness = Brightness.light,
  String username = 'synthetic',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-editor'),
            onPressed: () =>
                (fullPage
                ? showPlanBlockEditorPage<void>
                : showPlanBlockEditorSheet<void>)(
                  context: context,
                  builder: (_) => PlanBlockEditorSheet(
                    fullPage: fullPage,
                    username: username,
                    todos: todos ?? [target, other],
                    todoGroups: const [],
                    block: block,
                    autoRecommendTime: autoRecommendTime,
                    startTime: day.add(const Duration(hours: 13)),
                    endTime: day.add(const Duration(hours: 13, minutes: 30)),
                    initialTodoId: initialTodoId ?? target.id,
                    saver: saver,
                    startFocus: focus,
                    estimate:
                        estimate ??
                        (autoRecommendTime
                            ? (_) async => const TimeEstimationResult(
                                estimatedMinutes: 30,
                                confidence: 1,
                                reason: '合成预测',
                              )
                            : null),
                    availabilityLoader:
                        loader ??
                        (q, {bool forceRefresh = false}) async =>
                            PlanAvailabilitySnapshot(
                              todo: q.todoId == target.id ? target : other,
                              coverage: '应用内合成安排；未计入手机日历',
                              busy: [
                                for (final hour in [9, 11, 14])
                                  PlanBusyInterval(
                                    day.add(Duration(hours: hour)),
                                    day.add(Duration(hours: hour + 1)),
                                    source: PlanBusySource.planBlock,
                                  ),
                              ],
                            ),
                    clock: () => now,
                    onSaved: () {},
                    navigateOnFocus: false,
                  ),
                ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );
  await tap(tester, 'open-editor');
  if (autoRecommendTime) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> adopt(WidgetTester tester) async {
  await tap(tester, 'plan-find-time');
  await tap(tester, 'plan-duration-45');
  await tap(tester, 'plan-lookup-slots');
  await tester.pumpAndSettle();
  await tap(
    tester,
    'plan-slot-${day.add(const Duration(hours: 10)).millisecondsSinceEpoch}',
  );
  await tester.pumpAndSettle();
}

Future<TodoPlanBlock> identitySaver(
  TodoPlanBlock block,
  PlanAvailabilitySelection? selection, {
  int? expectedVersion,
  int? expectedUpdatedAt,
  TodoPlanStatus? newStatus,
}) async => block;
void main() {
  Finder slots() => find.byWidgetPredicate(
    (widget) =>
        widget is OutlinedButton &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('plan-slot-'),
  );

  testWidgets('独立规划页先预测75分钟，再自动显示两个建议并采用第一个', (tester) async {
    final prediction = Completer<TimeEstimationResult>();
    final queries = <PlanAvailabilityQuery>[];
    await showEditor(
      tester,
      saver: identitySaver,
      fullPage: true,
      autoRecommendTime: true,
      estimate: (_) => prediction.future,
      loader: (query, {bool forceRefresh = false}) async {
        queries.add(query);
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '合成安排',
        );
      },
    );
    expect(key('plan-block-editor-page'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(key('plan-block-editor-page'))),
      isA<PageRoute<void>>(),
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(queries, isEmpty);
    prediction.complete(
      const TimeEstimationResult(
        estimatedMinutes: 75,
        confidence: 1,
        reason: '合成预测',
      ),
    );
    await tester.pumpAndSettle();
    expect(queries, hasLength(1));
    expect(queries.single.minutes, 75);
    expect(slots(), findsNWidgets(2));
    expect(key('plan-custom-duration'), findsNothing);
    expect(key('plan-availability-date'), findsNothing);
    expect(key('plan-avoid-options'), findsNothing);
    expect(find.textContaining('已选用'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立页预测失败不使用占位30分钟自动查询', (tester) async {
    var reads = 0;
    await showEditor(
      tester,
      saver: identitySaver,
      fullPage: true,
      autoRecommendTime: true,
      estimate: (_) async => throw StateError('预测失败'),
      loader: (query, {bool forceRefresh = false}) async {
        reads++;
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '合成安排',
        );
      },
    );
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('完成时间预测失败，请手动设置时长后查找'), findsOneWidget);
    await tap(tester, 'plan-find-time');
    expect(key('plan-custom-search-dialog'), findsOneWidget);
    expect(key('plan-custom-duration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义弹窗可查8个方案，采用第五个返回后仍显示两个并记住查询和避让', (tester) async {
    final queries = <PlanAvailabilityQuery>[];
    PlanAvailabilitySelection? saved;
    await showEditor(
      tester,
      fullPage: true,
      saver:
          (
            draft,
            selection, {
            expectedVersion,
            expectedUpdatedAt,
            newStatus,
          }) async {
            saved = selection;
            return draft;
          },
      loader: (query, {bool forceRefresh = false}) async {
        queries.add(query);
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '合成安排',
        );
      },
    );
    expect(slots(), findsNWidgets(2));
    await tap(tester, 'plan-find-time');
    expect(key('plan-custom-search-dialog'), findsOneWidget);
    await tap(tester, 'plan-duration-45');
    await tap(tester, 'plan-result-limit-8');
    await tap(tester, 'plan-avoid-options');
    await tester.pumpAndSettle();
    await tap(tester, 'plan-avoid-toggle-0');
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    final dialog = key('plan-custom-search-dialog');
    final choices = find.descendant(of: dialog, matching: slots());
    expect(choices, findsNWidgets(8));
    final chosenKey = tester.widget<OutlinedButton>(choices.at(4)).key;
    await tester.ensureVisible(find.byKey(chosenKey!));
    await tester.tap(find.byKey(chosenKey));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(slots(), findsNWidgets(2));
    expect(find.byKey(chosenKey), findsOneWidget);
    expect(find.textContaining('已选用'), findsOneWidget);
    expect(queries.last.minutes, 45);
    expect(queries.last.resultLimit, 8);
    expect(queries.last.avoidWindows, hasLength(1));
    await tap(tester, 'plan-find-time');
    expect(
      tester.widget<TextField>(key('plan-custom-duration')).controller!.text,
      '45',
    );
    expect(
      tester.widget<ChoiceChip>(key('plan-result-limit-8')).selected,
      isTrue,
    );
    await tap(tester, 'plan-avoid-options');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(key('plan-avoid-toggle-0')).selected,
      isTrue,
    );
    await tester.tap(find.byTooltip('关闭自定义查找'));
    await tester.pumpAndSettle();
    expect(find.byKey(chosenKey), findsOneWidget);
    expect(saved, isNull);
    await tap(tester, 'plan-save');
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.query.minutes, 45);
    expect(saved!.query.avoidWindows, hasLength(1));
    expect(
      saved!.slot.start.millisecondsSinceEpoch,
      int.parse(
        (chosenKey as ValueKey<String>).value.substring('plan-slot-'.length),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹窗取消不改变已采用草稿，退出整页不保存', (tester) async {
    var saves = 0;
    await showEditor(
      tester,
      fullPage: true,
      autoRecommendTime: true,
      saver:
          (
            draft,
            selection, {
            expectedVersion,
            expectedUpdatedAt,
            newStatus,
          }) async {
            saves++;
            return draft;
          },
    );
    await tester.pumpAndSettle();
    final initial = find.textContaining('已选用').evaluate().single.widget as Text;
    await tap(tester, 'plan-find-time');
    await tap(tester, 'plan-duration-60');
    await tester.tap(find.byTooltip('关闭自定义查找'));
    await tester.pumpAndSettle();
    expect(find.text(initial.data!), findsOneWidget);
    Navigator.of(tester.element(key('plan-block-editor-page'))).pop();
    await tester.pumpAndSettle();
    expect(key('open-editor'), findsOneWidget);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(720, 360)]) {
    testWidgets('独立页和查找弹窗短屏键盘大字体可达 $size', (tester) async {
      await showEditor(
        tester,
        fullPage: true,
        saver: identitySaver,
        size: size,
        scale: 1.6,
        keyboard: 130,
        brightness: Brightness.dark,
      );
      await tap(tester, 'plan-find-time');
      await tap(tester, 'plan-duration-45');
      await tap(tester, 'plan-lookup-slots');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dialogChoices = find.descendant(
        of: key('plan-custom-search-dialog'),
        matching: slots(),
      );
      await tester.ensureVisible(dialogChoices.first);
      await tester.tap(dialogChoices.first);
      await tester.pumpAndSettle();
      expect(slots(), findsNWidgets(2));
      await tap(tester, 'plan-save');
      await tester.pumpAndSettle();
      expect(key('plan-block-editor-page'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('独立页外部安排刷新后推荐失效，自动更新两条结果但不覆盖草稿', (tester) async {
    var refreshed = false;
    var saves = 0;
    await showEditor(
      tester,
      fullPage: true,
      autoRecommendTime: true,
      saver:
          (
            draft,
            selection, {
            expectedVersion,
            expectedUpdatedAt,
            newStatus,
          }) async {
            saves++;
            return draft;
          },
      loader: (query, {bool forceRefresh = false}) async =>
          PlanAvailabilitySnapshot(
            todo: target,
            coverage: '合成安排',
            busy: refreshed
                ? [
                    PlanBusyInterval(
                      day.add(const Duration(hours: 8)),
                      day.add(const Duration(hours: 9)),
                      source: PlanBusySource.planBlock,
                    ),
                  ]
                : const [],
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('08:00'), findsOneWidget);
    refreshed = true;
    StorageService.triggerRefresh(const {DataRefreshDomain.planBlocks});
    await tester.pumpAndSettle();
    expect(slots(), findsNWidgets(2));
    expect(find.text('08:00'), findsOneWidget); // The existing draft stays put.
    expect(find.textContaining('已选用'), findsNothing);
    await tap(tester, 'plan-save');
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('推荐时段已失效，请重新查找或手动修改时间'), findsOneWidget);
    final first = slots().first;
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('09:00'), findsOneWidget);
    await tap(tester, 'plan-save');
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整页日历失败保持错误，弹窗明确降级查找后才允许采用', (tester) async {
    final queries = <PlanAvailabilityQuery>[];
    await showEditor(
      tester,
      fullPage: true,
      autoRecommendTime: true,
      saver: identitySaver,
      loader: (query, {bool forceRefresh = false}) async {
        queries.add(query);
        if (!query.appOnly) {
          throw const PlanAvailabilityException(
            '合成日历读取失败',
            canUseAppOnly: true,
          );
        }
        return PlanAvailabilitySnapshot(
          todo: target,
          coverage: '仅应用内安排；未计入手机日历',
          busy: const [],
        );
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('合成日历读取失败'), findsOneWidget);
    expect(slots(), findsNothing);
    await tap(tester, 'plan-find-time');
    await tap(tester, 'plan-lookup-slots');
    await tester.pumpAndSettle();
    await tap(tester, 'plan-app-only');
    await tester.pumpAndSettle();
    expect(queries.map((query) => query.appOnly), [false, false, true]);
    final choices = find.descendant(
      of: key('plan-custom-search-dialog'),
      matching: slots(),
    );
    expect(choices, findsNWidgets(5));
    await tester.ensureVisible(choices.first);
    await tester.tap(choices.first);
    await tester.pumpAndSettle();
    expect(key('plan-custom-search-dialog'), findsNothing);
    expect(slots(), findsNWidgets(2));
    expect(find.textContaining('已选用'), findsOneWidget);
    expect(find.textContaining('未计入手机日历'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('先等完成时间预测，再仅按预测75分钟查找并采用第一建议', (tester) async {
    final prediction = Completer<TimeEstimationResult>();
    final queries = <PlanAvailabilityQuery>[];
    var predictions = 0;
    await showEditor(
      tester,
      autoRecommendTime: true,
      saver: identitySaver,
      estimate: (_) {
        predictions++;
        return prediction.future;
      },
      loader: (q, {bool forceRefresh = false}) async {
        queries.add(q);
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '合成安排',
        );
      },
    );
    expect(predictions, 1);
    expect(queries, isEmpty);
    expect(find.text('正在预测完成时间…'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNull);
    prediction.complete(
      const TimeEstimationResult(
        estimatedMinutes: 75,
        confidence: 1,
        reason: '合成预测',
      ),
    );
    await tester.pumpAndSettle();
    expect(queries, hasLength(1));
    expect(queries.single.minutes, 75);
    expect(find.text('预计用时 1小时15分钟'), findsOneWidget);
    expect(
      tester
          .widget<PlanAvailabilityPanel>(find.byType(PlanAvailabilityPanel))
          .estimatedMinutes,
      75,
    );
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
    expect(find.text('已填入推荐时段，保存前会再次检查。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预测失败不先用固定时长查找，展示手动调整提示', (tester) async {
    var reads = 0;
    await showEditor(
      tester,
      autoRecommendTime: true,
      saver: identitySaver,
      estimate: (_) async => throw StateError('合成预测失败'),
      loader: (q, {bool forceRefresh = false}) async {
        reads++;
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '合成安排',
        );
      },
    );
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('完成时间预测失败，请手动设置时长后查找'), findsOneWidget);
    expect(find.text('已填入推荐时段，保存前会再次检查。'), findsNothing);
    expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预测期间用户修改草稿，晚返回的预测不覆盖用户设置或自动查找', (tester) async {
    final prediction = Completer<TimeEstimationResult>();
    var reads = 0;
    await showEditor(
      tester,
      autoRecommendTime: true,
      saver: identitySaver,
      estimate: (_) => prediction.future,
      loader: (q, {bool forceRefresh = false}) async {
        reads++;
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '合成安排',
        );
      },
    );
    final remark = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '备注（可选）',
    );
    await tester.ensureVisible(remark);
    await tester.enterText(remark, '保留当前设置');
    prediction.complete(
      const TimeEstimationResult(
        estimatedMinutes: 75,
        confidence: 1,
        reason: '晚到预测',
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('13:00'), findsOneWidget);
    expect(find.text('13:30'), findsOneWidget);
    expect(tester.widget<TextField>(remark).controller!.text, '保留当前设置');
    expect(tester.takeException(), isNull);
  });

  testWidgets('预测期间关闭弹窗，晚返回不查找、不保存、不更新已销毁组件', (tester) async {
    final prediction = Completer<TimeEstimationResult>();
    var reads = 0, saves = 0;
    await showEditor(
      tester,
      autoRecommendTime: true,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        saves++;
        return draft;
      },
      estimate: (_) => prediction.future,
      loader: (q, {bool forceRefresh = false}) async {
        reads++;
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '合成安排',
        );
      },
    );
    Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
    await tester.pumpAndSettle();
    prediction.complete(
      const TimeEstimationResult(
        estimatedMinutes: 75,
        confidence: 1,
        reason: '晚到预测',
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('待办入口自动采用第一条建议，恢复避让且可改选其他建议，取消零保存', (tester) async {
    final windows = PlanAvailabilityPreferences.defaultWindows;
    await tester.runAsync(
      () => PlanAvailabilityPreferences.save('synthetic', windows, {
        windows.first,
      }),
    );
    final queries = <PlanAvailabilityQuery>[];
    var saves = 0;
    await showEditor(
      tester,
      autoRecommendTime: true,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        saves++;
        return draft;
      },
      loader: (q, {bool forceRefresh = false}) async {
        queries.add(q);
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '合成安排',
        );
      },
    );
    await tester.pumpAndSettle();
    expect(queries, hasLength(1));
    expect(queries.single.avoidWindows.single.label, '午休');
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('已填入推荐时段，保存前会再次检查。'), findsOneWidget);
    expect(find.text('可用时段 · 5 个建议'), findsOneWidget);
    final otherSlot = day.add(const Duration(hours: 14));
    await tap(tester, 'plan-slot-${otherSlot.millisecondsSinceEpoch}');
    await tester.pumpAndSettle();
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('14:30'), findsOneWidget);
    expect(queries, hasLength(1));
    Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动查找未返回前不能保存，用户修改草稿后旧响应不自动填入', (tester) async {
    final response = Completer<PlanAvailabilitySnapshot>();
    await showEditor(
      tester,
      autoRecommendTime: true,
      saver: identitySaver,
      loader: (_, {bool forceRefresh = false}) => response.future,
    );
    expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNull);
    final remark = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '备注（可选）',
    );
    await tester.ensureVisible(remark);
    await tester.enterText(remark, '用户已开始调整');
    await tester.pump();
    response.complete(
      PlanAvailabilitySnapshot(todo: target, busy: const [], coverage: '合成安排'),
    );
    await tester.pumpAndSettle();
    expect(find.text('13:00'), findsOneWidget);
    expect(find.text('13:30'), findsOneWidget);
    expect(find.text('已填入推荐时段，保存前会再次检查。'), findsNothing);
    expect(find.text('可用时段 · 5 个建议'), findsOneWidget);
    expect(tester.widget<TextField>(remark).controller!.text, '用户已开始调整');
    expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动查找无可用时段时不采用原始时间作为建议', (tester) async {
    var saves = 0;
    await showEditor(
      tester,
      autoRecommendTime: true,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        saves++;
        return draft;
      },
      loader: (_, {bool forceRefresh = false}) async =>
          PlanAvailabilitySnapshot(
            todo: target,
            busy: [
              PlanBusyInterval(
                day,
                day.add(const Duration(days: 1)),
                source: PlanBusySource.fixedSchedule,
              ),
            ],
            coverage: '合成全天占用',
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已填入推荐时段，保存前会再次检查。'), findsNothing);
    expect(find.textContaining('没有连续'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNotNull);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动查找手机日历失败时展示错误，明确降级后仍由用户选择', (tester) async {
    final queries = <PlanAvailabilityQuery>[];
    await showEditor(
      tester,
      autoRecommendTime: true,
      saver: identitySaver,
      loader: (q, {bool forceRefresh = false}) async {
        queries.add(q);
        if (!q.appOnly) {
          throw const PlanAvailabilityException('合成日历失败', canUseAppOnly: true);
        }
        return PlanAvailabilitySnapshot(
          todo: target,
          busy: const [],
          coverage: '应用内合成安排',
        );
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('合成日历失败'), findsOneWidget);
    expect(find.text('已填入推荐时段，保存前会再次检查。'), findsNothing);
    expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNotNull);
    await tap(tester, 'plan-app-only');
    await tester.pumpAndSettle();
    expect(queries.map((q) => q.appOnly), [false, true]);
    expect(find.text('可用时段 · 5 个建议'), findsOneWidget);
    expect(find.text('已填入推荐时段，保存前会再次检查。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建只列出未完成待办，先过滤再折叠循环实例', (tester) async {
    final done = TodoItem(id: 'done', title: '已完成事项', isDone: true);
    final deleted = TodoItem(id: 'deleted', title: '已删除事项', isDeleted: true);
    final completedOccurrence = TodoItem(
      id: 'series-done',
      title: '已完成循环期次',
      isDone: true,
      recurrenceSeriesId: 'series',
      recurrence: RecurrenceType.daily,
      createdDate: day.millisecondsSinceEpoch,
    );
    final futureOccurrence = TodoItem(
      id: 'series-open',
      title: '未完成循环期次',
      recurrenceSeriesId: 'series',
      createdDate: day.add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    await showEditor(
      tester,
      saver: identitySaver,
      initialTodoId: done.id,
      todos: [done, deleted, completedOccurrence, futureOccurrence, other],
    );
    final picker = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(
      todoDropdown(tester).items!
          .where((item) => item.enabled)
          .map((item) => item.value)
          .toSet(),
      {futureOccurrence.id, other.id},
    );
    expect(picker.initialValue, isNot(done.id));
    expect(
      todoDropdown(tester).items!.any(
        (item) =>
            [done.id, deleted.id, completedOccurrence.id].contains(item.value),
      ),
      isFalse,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('已完成事项'), findsNothing);
    expect(find.text('已完成循环期次'), findsNothing);
    expect(find.text('未完成循环期次'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有未完成待办时显示空状态并禁止保存和专注', (tester) async {
    var saves = 0;
    for (final todos in <List<TodoItem>>[
      [],
      [TodoItem(id: 'done', title: '已完成', isDone: true)],
      [TodoItem(id: 'deleted', title: '已删除', isDeleted: true)],
    ]) {
      await showEditor(
        tester,
        saver:
            (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
              saves++;
              return draft;
            },
        todos: todos,
      );
      expect(find.text('暂无可规划的未完成待办'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(key('plan-save-focus')).onPressed,
        isNull,
      );
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
    }
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史规划保留原已完成待办关联，但已完成项不可重新选择', (tester) async {
    final done = TodoItem(id: 'done', title: '历史已完成事项', isDone: true);
    final otherDone = TodoItem(
      id: 'other-done',
      title: '其他已完成事项',
      isDone: true,
    );
    final block = TodoPlanBlock(
      todoId: done.id,
      startTime: day.millisecondsSinceEpoch,
      endTime: day.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      status: TodoPlanStatus.finished,
    );
    await showEditor(
      tester,
      saver: identitySaver,
      block: block,
      todos: [done, otherDone, other],
    );
    final picker = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(picker.initialValue, done.id);
    expect(
      todoDropdown(tester).items!
          .singleWhere((item) => item.value == done.id)
          .enabled,
      isFalse,
    );
    expect(
      todoDropdown(tester).items!.any((item) => item.value == otherDone.id),
      isFalse,
    );
    expect(block.todoId, done.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中后待办完成，保存和保存并专注均拒绝且保留草稿', (tester) async {
    var writes = 0, starts = 0;
    final todo = TodoItem(id: 'mutable', title: '打开时未完成');
    await showEditor(
      tester,
      todos: [todo],
      initialTodoId: todo.id,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        writes++;
        return draft;
      },
      focus: (_, _) async {
        starts++;
      },
    );
    await tester.ensureVisible(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '备注（可选）',
      ),
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '备注（可选）',
      ),
      '保留我的草稿',
    );
    todo.isDone = true;
    for (final action in ['plan-save', 'plan-save-focus']) {
      await tap(tester, action);
      await tester.pumpAndSettle();
      expect(find.text('待办已完成或失效，请选择未完成的待办'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == '备注（可选）',
              ),
            )
            .controller!
            .text,
        '保留我的草稿',
      );
    }
    expect(writes, 0);
    expect(starts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('待办列表刷新后移除已完成选择，须明确重选而非自动换成其他待办', (tester) async {
    final selected = TodoItem(id: 'changing', title: '即将完成');
    final todos = ValueNotifier<List<TodoItem>>([selected, other]);
    addTearDown(todos.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<TodoItem>>(
            valueListenable: todos,
            builder: (_, values, _) => PlanBlockEditorSheet(
              username: 'synthetic',
              autoFillEstimateOnTodoChange: false,
              todos: values,
              todoGroups: const [],
              initialTodoId: selected.id,
              startTime: day.add(const Duration(hours: 13)),
              endTime: day.add(const Duration(hours: 14)),
              saver: identitySaver,
              clock: () => now,
              onSaved: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    selected.isDone = true;
    todos.value = [selected, other];
    await tester.pumpAndSettle();
    final picker = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(picker.initialValue, isNull);
    expect(picker.onChanged, isNotNull);
    expect(
      todoDropdown(tester).items!
          .where((item) => item.enabled)
          .map((item) => item.value),
      [other.id],
    );
    expect(find.text('原待办已完成或失效，请重新选择未完成待办'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNull);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(other.title).last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(key('plan-save')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final column in ['is_completed', 'is_deleted']) {
    testWidgets('手动新建事务检查最新 $column，拒绝无效待办且零写入', (tester) async {
      final fixture = PlanAvailabilityFixture();
      await tester.runAsync(() => fixture.initialize());
      await tester.runAsync(
        () => fixture.todo(target.id, target.title, due: target.dueDate),
      );
      try {
        await showEditor(
          tester,
          username: PlanAvailabilityFixture.username,
          saver: null,
        );
        await tester.runAsync(
          () => fixture.db.update(
            'todos',
            {column: 1},
            where: 'uuid = ?',
            whereArgs: [target.id],
          ),
        );
        await tap(tester, 'plan-save');
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.text('待办已完成或失效，请选择未完成的待办'), findsOneWidget);
        expect(
          await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => fixture.db.query('op_logs')),
          isEmpty,
        );
        expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 120));
        await tester.runAsync(() => fixture.dispose());
      }
    });
  }

  for (final width in [320.0, 680.0]) {
    testWidgets('其他设置并排且移除 AI 按钮 width=$width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showEditor(tester, saver: identitySaver, size: Size(width, 1000));
      final single = key('plan-option-单轮番茄');
      final rounds = key('plan-option-番茄轮数');
      final reminder = key('plan-option-提前提醒');
      await tester.ensureVisible(single);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(single).top,
        closeTo(tester.getRect(rounds).top, 1),
      );
      expect(
        tester.getRect(single).right,
        lessThan(tester.getRect(rounds).left),
      );
      if (width >= 680) {
        expect(
          tester.getRect(reminder).top,
          closeTo(tester.getRect(single).top, 1),
        );
      } else {
        expect(
          tester.getRect(reminder).top,
          greaterThan(tester.getRect(single).top),
        );
      }
      expect(find.text('AI 帮我安排更多'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'current_login_user': 'synthetic'});
    await LiquidGlassEffectService.setEnabled(false);
  });
  tearDown(() async {
    await LiquidGlassEffectService.setEnabled(false);
    GlassPerformanceMonitor.stop();
  });
  for (final size in [const Size(320, 640), const Size(720, 360)]) {
    testWidgets('避让设置与编辑时间在短屏大字体可达 size=$size', (tester) async {
      await showEditor(
        tester,
        saver: identitySaver,
        size: size,
        scale: 1.6,
        keyboard: 130,
      );
      await tap(tester, 'plan-find-time');
      await tap(tester, 'plan-avoid-options');
      await tester.pumpAndSettle();
      await tap(tester, 'plan-avoid-toggle-0');
      await tester.pumpAndSettle();
      await tap(tester, 'plan-avoid-edit-0');
      await tester.pumpAndSettle();
      expect(find.text('调整午休时间'), findsOneWidget);
      await tap(tester, 'plan-avoid-confirm');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'plan-save');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('采用只填草稿，取消没有保存或专注调用', (tester) async {
    var saves = 0, starts = 0;
    await showEditor(
      tester,
      saver:
          (
            draft,
            selection, {
            expectedVersion,
            expectedUpdatedAt,
            newStatus,
          }) async {
            saves++;
            return draft;
          },
      focus: (_, _) async {
        starts++;
      },
    );
    await adopt(tester);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('10:45'), findsOneWidget);
    expect(saves, 0);
    expect(starts, 0);
    Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(starts, 0);
    expect(target.dueDate, DateTime(2026, 10, 8, 20));
  });
  testWidgets('显式保存推荐、备注、提醒与番茄配置，保留原对象', (tester) async {
    TodoPlanBlock? saved;
    PlanAvailabilitySelection? chosen;
    final old = TodoPlanBlock(
      id: 'existing',
      todoId: target.id,
      startTime: day.millisecondsSinceEpoch,
      endTime: day.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      remark: '旧备注',
      reminderMinutes: 15,
      pomodoroMinutes: 45,
      pomodoroRounds: 2,
    );
    await showEditor(
      tester,
      block: old,
      saver:
          (
            draft,
            selection, {
            expectedVersion,
            expectedUpdatedAt,
            newStatus,
          }) async {
            saved = draft;
            chosen = selection;
            expect(expectedVersion, old.version);
            return draft;
          },
    );
    await adopt(tester);
    await tap(tester, 'plan-save');
    await tester.pumpAndSettle();
    expect(saved!.id, old.id);
    expect(
      saved!.startTime,
      day.add(const Duration(hours: 10)).millisecondsSinceEpoch,
    );
    expect(saved!.plannedMinutes, 45);
    expect(saved!.remark, '旧备注');
    expect(saved!.reminderMinutes, 15);
    expect(saved!.pomodoroMinutes, 45);
    expect(saved!.pomodoroRounds, 2);
    expect(old.startTime, day.millisecondsSinceEpoch);
    expect(chosen, isNotNull);
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
  });
  testWidgets('保存校验失败保留草稿，零专注启动', (tester) async {
    var starts = 0;
    await showEditor(
      tester,
      saver: (_, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        throw const PlanAvailabilityException('时段已被占用');
      },
      focus: (_, _) async {
        starts++;
      },
    );
    await adopt(tester);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(find.text('时段已被占用'), findsOneWidget);
    expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
    expect(starts, 0);
  });
  testWidgets('重复点击等待中的保存只调用一次', (tester) async {
    final pending = Completer<TodoPlanBlock>();
    var saves = 0;
    TodoPlanBlock? draft;
    await showEditor(
      tester,
      saver: (value, _, {expectedVersion, expectedUpdatedAt, newStatus}) {
        saves++;
        draft = value;
        return pending.future;
      },
    );
    await adopt(tester);
    await tap(tester, 'plan-save');
    await tester.tap(key('plan-save'), warnIfMissed: false);
    await tester.pump();
    expect(saves, 1);
    pending.complete(draft!);
    await tester.pumpAndSettle();
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
  });
  testWidgets('专注失败保留已存规划，重试不重复保存且UUID一致', (tester) async {
    var writes = 0, starts = 0;
    final ids = <String>[];
    await showEditor(
      tester,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        writes++;
        final saved = TodoPlanBlock.fromJson(draft.toJson());
        if (newStatus != null) saved.status = newStatus;
        return saved;
      },
      focus: (block, _) async {
        starts++;
        ids.add(block.id);
        if (starts == 1) throw StateError('模拟启动失败');
      },
    );
    await adopt(tester);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.textContaining('规划已保存，专注未启动'), findsOneWidget);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(ids.toSet(), hasLength(1));
    expect(writes, 2); // One creation plus one focusing-state update.
    expect(find.byType(PlanBlockEditorSheet), findsNothing);
  });
  testWidgets('启动成功但状态写入失败，重试仅更新状态不重复启动', (tester) async {
    var writes = 0, starts = 0;
    await showEditor(
      tester,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        writes++;
        if (writes == 2) throw StateError('状态写入失败');
        return draft;
      },
      focus: (_, _) async {
        starts++;
      },
    );
    await adopt(tester);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(find.textContaining('专注已启动，但规划状态更新失败'), findsOneWidget);
    await tap(tester, 'plan-save-focus');
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(writes, 3);
  });
  testWidgets('同步刷新使已采用推荐失效，保存被阻止', (tester) async {
    var saves = 0;
    await showEditor(
      tester,
      saver: (draft, _, {expectedVersion, expectedUpdatedAt, newStatus}) async {
        saves++;
        return draft;
      },
    );
    await adopt(tester);
    StorageService.triggerRefresh(const {DataRefreshDomain.planBlocks});
    await tester.pump(const Duration(milliseconds: 120));
    await tap(tester, 'plan-save');
    await tester.pumpAndSettle();
    expect(find.text('推荐时段已失效，请重新查找或手动修改时间'), findsOneWidget);
    expect(saves, 0);
  });
  testWidgets('旧估时晚返回不能覆盖已采用时段或番茄配置', (tester) async {
    final pending = Completer<TimeEstimationResult>();
    await showEditor(
      tester,
      saver: identitySaver,
      estimate: (_) => pending.future,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('整理笔记').last);
    await tester.pumpAndSettle();
    await adopt(tester);
    pending.complete(
      const TimeEstimationResult(
        estimatedMinutes: 180,
        confidence: 0.8,
        reason: '合成估时',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10:45'), findsOneWidget);
    expect(find.textContaining('历史估时'), findsNothing);
    expect(find.text('按规划时长'), findsOneWidget);
  });
  testWidgets('真实编辑器通过真实隔离存储：采用取消零写入，保存一条规划及oplog', (tester) async {
    final fixture = PlanAvailabilityFixture();
    await tester.runAsync(() => fixture.initialize());
    final repository = PlanAvailabilityRepository(
      databaseOverride: fixture.db,
      clock: () => now,
    );
    await tester.runAsync(
      () => fixture.todo(target.id, target.title, due: target.dueDate),
    );
    Future<TodoPlanBlock> saver(
      TodoPlanBlock draft,
      PlanAvailabilitySelection? selection, {
      int? expectedVersion,
      int? expectedUpdatedAt,
      TodoPlanStatus? newStatus,
    }) => repository.save(
      selection!,
      draft,
      expectedVersion: expectedVersion,
      expectedUpdatedAt: expectedUpdatedAt,
      sync: false,
    );
    Future<void> chooseReal() async {
      await tap(tester, 'plan-find-time');
      await tap(tester, 'plan-duration-45');
      await tap(tester, 'plan-lookup-slots');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tap(
        tester,
        'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
      );
    }

    try {
      await showEditor(
        tester,
        username: PlanAvailabilityFixture.username,
        saver: saver,
        loader: repository.read,
      );
      await chooseReal();
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        isEmpty,
      );
      expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
      await showEditor(
        tester,
        username: PlanAvailabilityFixture.username,
        saver: saver,
        loader: repository.read,
      );
      await chooseReal();
      await tap(tester, 'plan-save');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final rows = await tester.runAsync(
        () => fixture.db.query('todo_plan_blocks'),
      );
      expect(rows, hasLength(1));
      expect(rows!.single['planned_minutes'], 45);
      expect(
        await tester.runAsync(() => fixture.db.query('op_logs')),
        hasLength(1),
      );
      expect(find.byType(PlanBlockEditorSheet), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(() => fixture.dispose());
    }
  });
  testWidgets('真实编辑器保存复查新占用，保持草稿且无oplog', (tester) async {
    final fixture = PlanAvailabilityFixture();
    await tester.runAsync(() => fixture.initialize());
    await tester.runAsync(
      () => fixture.todo(target.id, target.title, due: target.dueDate),
    );
    final repository = PlanAvailabilityRepository(
      databaseOverride: fixture.db,
      clock: () => now,
    );
    try {
      await showEditor(
        tester,
        username: PlanAvailabilityFixture.username,
        loader: repository.read,
        saver: (
          draft,
          selection, {
          expectedVersion,
          expectedUpdatedAt,
          newStatus,
        }) => repository.save(selection!, draft, sync: false),
      );
      await tap(tester, 'plan-find-time');
      await tap(tester, 'plan-duration-45');
      await tap(tester, 'plan-lookup-slots');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tap(
        tester,
        'plan-slot-${day.add(const Duration(hours: 8)).millisecondsSinceEpoch}',
      );
      await tester.runAsync(
        () => fixture.fixed(
          'new-meeting',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      await tap(tester, 'plan-save-focus');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('该时段已失效或被占用，请重新查找时段'), findsOneWidget);
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        isEmpty,
      );
      expect(await tester.runAsync(() => fixture.db.query('op_logs')), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(() => fixture.dispose());
    }
  });
  testWidgets('真实规划日视图点击、拖选、编辑三入口均打开共享推荐编辑器', (tester) async {
    // Use a future day: the page legitimately marks overdue plans missed.
    final realNow = DateTime.now();
    final entryDay = DateTime(realNow.year, realNow.month, realNow.day + 1);
    final fixture = PlanAvailabilityFixture();
    await tester.runAsync(() => fixture.initialize());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tip_shown_todo_plan_guide', true);
    await tester.runAsync(
      () => fixture.block(
        TodoPlanBlock(
          id: 'entry-plan',
          todoId: 'todo-target',
          titleSnapshot: '入口规划',
          startTime: entryDay
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          endTime: entryDay
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        ),
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: TodoPlanScreen(
            username: PlanAvailabilityFixture.username,
            initialDate: entryDay,
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final grid = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.onPanStart != null &&
            widget.onPanUpdate != null &&
            widget.onPanEnd != null,
      );
      expect(grid, findsOneWidget);
      final rect = tester.getRect(grid);
      await tester.tapAt(
        Offset(rect.left + rect.width * 0.6, rect.top + rect.height * 0.5),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(key('plan-find-time'), findsOneWidget);
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .fullPage,
        isTrue,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(key('plan-custom-duration'), findsNothing);
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .autoFillEstimateOnTodoChange,
        isTrue,
      );
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      await tester.dragFrom(
        Offset(rect.left + rect.width * 0.5, rect.top + rect.height * 0.6),
        const Offset(70, 50),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanBlockEditorSheet), findsOneWidget);
      expect(key('plan-find-time'), findsOneWidget);
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .fullPage,
        isTrue,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(key('plan-custom-duration'), findsNothing);
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .autoFillEstimateOnTodoChange,
        isFalse,
      );
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('入口规划'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PlanBlockEditorSheet>(find.byType(PlanBlockEditorSheet))
            .block!
            .id,
        'entry-plan',
      );
      expect(key('plan-find-time'), findsOneWidget);
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => fixture.db.query('todo_plan_blocks')),
        hasLength(1),
      );
      expect(
        await tester.runAsync(
          () => fixture.db.query(
            'op_logs',
            where: 'target_table = ?',
            whereArgs: ['todo_plan_blocks'],
          ),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 120));
      await tester.runAsync(() => fixture.dispose());
    }
  });
  testWidgets('正在专注和历史规划不提供推荐改期', (tester) async {
    for (final status in [
      TodoPlanStatus.focusing,
      TodoPlanStatus.finished,
      TodoPlanStatus.cancelled,
      TodoPlanStatus.missed,
      TodoPlanStatus.skipped,
    ]) {
      await showEditor(
        tester,
        saver: identitySaver,
        block: TodoPlanBlock(
          todoId: target.id,
          startTime: day.millisecondsSinceEpoch,
          endTime: day.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          status: status,
        ),
      );
      final button = tester.widget<OutlinedButton>(key('plan-find-time'));
      expect(button.onPressed, isNull);
      expect(find.text('该规划状态不支持推荐改期'), findsOneWidget);
      Navigator.of(tester.element(find.byType(PlanBlockEditorSheet))).pop();
      await tester.pumpAndSettle();
    }
  });
  for (final geometry in [
    (const Size(320, 640), 1.6, 260.0, Brightness.light),
    (const Size(390, 844), 2.0, 0.0, Brightness.dark),
    (const Size(720, 360), 1.6, 130.0, Brightness.dark),
    (const Size(1280, 900), 2.0, 0.0, Brightness.light),
  ]) {
    for (final glass in [false, true]) {
      testWidgets(
        '实际编辑器 ${geometry.$1} 字体${geometry.$2} 键盘${geometry.$3} 玻璃$glass 控件可达无溢出',
        (tester) async {
          await LiquidGlassEffectService.setEnabled(glass);
          await showEditor(
            tester,
            saver: identitySaver,
            size: geometry.$1,
            scale: geometry.$2,
            keyboard: geometry.$3,
            brightness: geometry.$4,
          );
          await adopt(tester);
          await tester.ensureVisible(key('plan-save'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tap(tester, 'plan-save');
          await tester.pumpAndSettle();
          expect(find.byType(PlanBlockEditorSheet), findsNothing);
        },
      );
    }
  }
}
