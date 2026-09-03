import 'dart:async';

import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/screens/habit_archived_screen.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/folder_manage_screen.dart';
import 'package:countdown_todo/screens/pomodoro/unified_tag_manager_screen.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<PomodoroTag> sampleTags() => [
      PomodoroTag(uuid: 'read', name: '阅读与学习', color: '#3F51B5'),
      PomodoroTag(uuid: 'work', name: '项目工作', color: '#009688'),
      PomodoroTag(
          uuid: 'old', name: '已结束的课程', color: '#795548', isArchived: true),
    ];

List<HabitGoal> sampleHabits() => [
      HabitGoal(
          uuid: 'read',
          name: '每天读几页书',
          icon: '📖',
          isArchived: true,
          sourceType: HabitSourceType.durationCheckIn),
      HabitGoal(uuid: 'walk', name: '晚饭后散步', icon: '🌿', isArchived: true),
    ];

FolderManageScreen sampleFolders(
        {ValueChanged<List<TodoItem>>? onTodosChanged}) =>
    FolderManageScreen(
      username: 'ui-review',
      todoGroups: [
        TodoGroup(id: 'work', name: '工作项目'),
        TodoGroup(id: 'life', name: '生活计划')
      ],
      allTodos: [
        TodoItem(title: '梳理本周项目计划', groupId: 'work'),
        TodoItem(title: '整理会议记录', groupId: 'work', isDone: true)
      ],
      onGroupsChanged: (_) {},
      onTodosChanged: onTodosChanged ?? (_) {},
    );

Future<void> pumpManagementPage(WidgetTester tester, Widget page,
    {Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: brightness)),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: page,
  ));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 220,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('标签搜索、选择与清空保留回调', (tester) async {
    List<String> selected = [];
    await pumpManagementPage(
        tester,
        UnifiedTagManagerScreen(
            allTags: sampleTags(),
            showSelection: true,
            onChanged: (_, ids) => selected = List.of(ids)));
    await tester.enterText(find.byType(TextField), '阅读');
    await tester.pumpAndSettle();
    expect(find.text('项目工作'), findsNothing);
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    await tapVisible(tester, find.text('选择'));
    expect(selected, ['read']);
    await tapVisible(tester, find.byTooltip('清空搜索'));
    expect(find.text('项目工作'), findsOneWidget);
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
  });

  testWidgets('标签归档与恢复保留身份及选择语义', (tester) async {
    List<PomodoroTag> saved = [];
    List<String> selected = ['read'];
    await pumpManagementPage(
        tester,
        UnifiedTagManagerScreen(
            allTags: sampleTags(),
            selectedUuids: selected,
            showSelection: true,
            onChanged: (tags, ids) {
              saved = List.of(tags);
              selected = List.of(ids);
            }));
    await tapVisible(tester, find.text('归档').first);
    expect(saved.firstWhere((t) => t.uuid == 'read').isArchived, isTrue);
    expect(selected, isEmpty);
    await tapVisible(tester, find.text('已归档 2'));
    await tapVisible(tester, find.text('恢复').last);
    expect(saved.firstWhere((t) => t.uuid == 'read').isArchived, isFalse);
    expect(find.text('使用中 2'), findsOneWidget);
  });

  testWidgets('禁用归档入口且保留排序回调', (tester) async {
    List<PomodoroTag> saved = [];
    await pumpManagementPage(
        tester,
        UnifiedTagManagerScreen(
            allTags: sampleTags(),
            showArchive: false,
            onChanged: (tags, _) => saved = tags));
    expect(find.text('归档'), findsNothing);
    expect(find.text('已归档 1'), findsNothing);
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 1);
    await tester.pumpAndSettle();
    expect(saved.take(2).map((t) => t.uuid), ['work', 'read']);
  });

  testWidgets('手机标签编辑弹层支持空值校验与保存', (tester) async {
    List<PomodoroTag> saved = [];
    await pumpManagementPage(
        tester,
        UnifiedTagManagerScreen(
            allTags: sampleTags(), onChanged: (tags, _) => saved = tags));
    await tapVisible(tester, find.text('编辑').first);
    await tester.enterText(find.widgetWithText(TextField, '阅读与学习'), '');
    await tapVisible(tester, find.text('保存'));
    expect(find.text('请输入标签名称'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '深度阅读');
    await tapVisible(tester, find.text('保存'));
    expect(saved.firstWhere((t) => t.uuid == 'read').name, '深度阅读');
    expect(saved.firstWhere((t) => t.uuid == 'read').version, 2);
  });

  testWidgets('桌面切换编辑对象与新建不会串用草稿', (tester) async {
    await pumpManagementPage(
        tester, UnifiedTagManagerScreen(allTags: sampleTags()),
        size: const Size(1200, 900));
    await tapVisible(tester, find.text('阅读与学习'));
    await tester.enterText(find.byType(TextField).last, '未保存草稿');
    await tapVisible(tester, find.text('项目工作'));
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '项目工作');
    await tapVisible(tester, find.text('添加标签'));
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty);
  });

  testWidgets('小屏大字与键盘下的标签表单可滚动', (tester) async {
    await pumpManagementPage(
        tester, UnifiedTagManagerScreen(allTags: sampleTags()),
        size: const Size(320, 640), scale: 1.8, brightness: Brightness.dark);
    await tapVisible(tester, find.text('添加标签'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件夹搜索与展开操作清晰可用', (tester) async {
    List<TodoItem> changed = [];
    await pumpManagementPage(
        tester, sampleFolders(onTodosChanged: (todos) => changed = todos));
    await tester.enterText(find.byType(TextField), '工作');
    await tester.pumpAndSettle();
    expect(find.text('生活计划'), findsNothing);
    await tapVisible(tester, find.text('工作项目'));
    expect(find.text('重命名'), findsOneWidget);
    await tapVisible(tester, find.byTooltip('移出文件夹').first);
    expect(changed.first.groupId, isNull);
    expect(changed.last.groupId, 'work');
  });

  testWidgets('文件夹展示设置保存原有模式', (tester) async {
    await pumpManagementPage(tester, sampleFolders());
    await tapVisible(tester, find.text('首页展示方式'));
    await tapVisible(tester, find.text('文件夹单独显示'));
    expect(await StorageService.getTodoFolderDisplayMode(), 'separate');
    expect(tester.takeException(), isNull);
  });

  testWidgets('文件夹命名弹窗校验空值且可取消', (tester) async {
    await pumpManagementPage(tester, sampleFolders());
    await tapVisible(tester, find.text('新建文件夹'));
    await tapVisible(tester, find.text('保存'));
    expect(find.text('请输入文件夹名称'), findsOneWidget);
    await tapVisible(tester, find.text('取消'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('文件夹与习惯在320宽大字体无溢出 $brightness', (tester) async {
      await pumpManagementPage(tester, sampleFolders(),
          size: const Size(320, 740), scale: 1.8, brightness: brightness);
      await tapVisible(tester, find.text('工作项目'));
      await tapVisible(tester, find.text('解散文件夹'));
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('取消'));
      await pumpManagementPage(
          tester, HabitArchivedScreen(loadGoals: () async => sampleHabits()),
          size: const Size(320, 740), scale: 1.8, brightness: brightness);
      await tester.ensureVisible(find.text('恢复习惯').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('习惯归档搜索且排除删除及未归档数据', (tester) async {
    await pumpManagementPage(
        tester,
        HabitArchivedScreen(
            loadGoals: () async => [
                  ...sampleHabits(),
                  HabitGoal(name: '未归档'),
                  HabitGoal(name: '已删除', isArchived: true, isDeleted: true)
                ]));
    expect(find.text('已归档 · 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '散步');
    await tester.pumpAndSettle();
    expect(find.text('每天读几页书'), findsNothing);
    expect(find.text('晚饭后散步'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的习惯'), findsOneWidget);
  });

  testWidgets('习惯加载失败可重试', (tester) async {
    var attempts = 0;
    await pumpManagementPage(tester, HabitArchivedScreen(loadGoals: () async {
      if (attempts++ == 0) throw StateError('offline');
      return sampleHabits();
    }));
    expect(find.text('暂时无法加载习惯'), findsOneWidget);
    await tapVisible(tester, find.text('重新加载'));
    expect(find.text('每天读几页书'), findsOneWidget);
  });

  testWidgets('恢复习惯禁止重复提交，失败后可再次操作', (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await pumpManagementPage(
        tester,
        HabitArchivedScreen(
            loadGoals: () async => sampleHabits(),
            restoreGoal: (_) {
              calls++;
              return pending.future;
            }));
    await tester.tap(find.text('恢复习惯').first);
    await tester.pump();
    expect(calls, 1);
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('恢复失败，请稍后重试'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
        isNotNull);
  });

  testWidgets('恢复习惯成功返回刷新标记', (tester) async {
    bool? result;
    String? restored;
    await pumpManagementPage(
        tester,
        Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await Navigator.of(context)
                            .push<bool>(MaterialPageRoute(
                                builder: (_) => HabitArchivedScreen(
                                      loadGoals: () async => sampleHabits(),
                                      restoreGoal: (goal) async {
                                        restored = goal.uuid;
                                      },
                                    )));
                      },
                      child: const Text('打开归档')),
                )));
    await tapVisible(tester, find.text('打开归档'));
    await tapVisible(tester, find.text('恢复习惯').first);
    expect(restored, 'read');
    expect(result, isTrue);
  });
}
