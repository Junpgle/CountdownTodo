import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/historical_countdowns_screen.dart';
import 'package:countdown_todo/screens/historical_todos_screen.dart';
import 'package:countdown_todo/screens/team_message_center_screen.dart';
import 'package:countdown_todo/utils/time_utils.dart';
import 'package:countdown_todo/widgets/countdown_section_widget.dart';
import 'package:countdown_todo/widgets/share_readonly_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'management_pages_test.dart' show pumpManagementPage, tapVisible;

List<TodoItem> historyTodos() => [
  TodoItem(
    id: 'done',
    title: '完成项目第一阶段',
    remark: '文档已经整理归档',
    isDone: true,
    dueDate: DateTime(2024, 5, 10),
  ),
  TodoItem(id: 'deleted', title: '旧版项目计划', isDeleted: true),
  TodoItem(id: 'deleted2', title: '临时备忘', isDeleted: true),
  TodoItem(id: 'orphan', title: '整理尚未归类的资料', groupId: 'missing'),
  TodoItem(id: 'active', title: '当前进行中的待办'),
];

HistoricalTodosScreen historyTodoPage() => HistoricalTodosScreen(
  username: 'ui-test',
  loadTodos: () async => historyTodos(),
  loadGroups: () async => [],
);

List<CountdownItem> historyCountdowns() => [
  CountdownItem(
    id: 'recent',
    title: '期待已久的夏日旅行',
    targetDate: DateTime(2025, 7, 20),
  ),
  CountdownItem(
    id: 'old',
    title: '第一次独立完成项目',
    targetDate: DateTime(2024, 4, 10),
  ),
  CountdownItem(
    id: 'future',
    title: '未来的计划',
    targetDate: DateTime.now().add(const Duration(days: 100)),
  ),
];

List<Team> messageTeams() => [
  Team(
    uuid: 'team',
    name: '一起把计划变成现实的小组',
    creatorId: 1,
    createdAt: 0,
    userRole: TeamRole.admin,
  ),
];

List<Map<String, dynamic>> teamMessages() => [
  {
    'type': 'JOIN_REQUEST',
    'team_uuid': 'team',
    'user_id': 8,
    'username': '小林',
    'message': '小林申请加入团队，期待和大家一起完成接下来的计划。',
    'timestamp': '1788000000000',
    'request_status': 0,
  },
  {
    'type': 'MEMBER_EXIT',
    'team_uuid': 'team',
    'user_id': 9,
    'username': '小夏',
    'message': '小夏已退出团队',
    'timestamp': 1787000000000,
  },
  {
    'type': 'JOIN_REQUEST',
    'team_uuid': 'team',
    'user_id': 10,
    'username': '小雨',
    'message': '小雨申请加入团队',
    'timestamp': 1786000000000,
    'request_status': 1,
  },
];

TeamMessageCenterScreen messagePage() => TeamMessageCenterScreen(
  managedTeams: messageTeams(),
  fetchMessages: (_) async => {'success': true, 'messages': teamMessages()},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('待办历史保持三类划分且支持备注搜索', (tester) async {
    await pumpManagementPage(tester, historyTodoPage());
    expect(find.text('历史记录 1'), findsOneWidget);
    expect(find.text('回收站 2'), findsOneWidget);
    expect(find.text('待修复 1'), findsOneWidget);
    expect(find.text('当前进行中的待办'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '归档');
    await tester.pumpAndSettle();
    expect(find.text('完成项目第一阶段'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '不匹配');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的待办'), findsOneWidget);
  });

  testWidgets('待办彻底删除先确认，取消不修改记录', (tester) async {
    await pumpManagementPage(tester, historyTodoPage());
    await tapVisible(tester, find.text('回收站 2'));
    await tapVisible(tester, find.text('彻底删除').first);
    expect(find.text('彻底删除这条待办？'), findsOneWidget);
    expect(find.textContaining('删除后无法恢复'), findsOneWidget);
    await tapVisible(tester, find.text('取消'));
    expect(find.text('回收站 2'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('搜索后清空回收站仍明确显示全部数量', (tester) async {
    await pumpManagementPage(tester, historyTodoPage());
    await tapVisible(tester, find.text('回收站 2'));
    await tester.enterText(find.byType(TextField).first, '旧版');
    await tester.pumpAndSettle();
    expect(find.text('找到 1 条待办'), findsOneWidget);
    await tapVisible(tester, find.text('清空全部'));
    expect(find.textContaining('全部 2 条待办'), findsOneWidget);
    await tapVisible(tester, find.text('取消'));
  });

  testWidgets('恢复回收站待办使用最新记录，避免覆盖并发修改', (tester) async {
    final stale = TodoItem(
      id: 'restore',
      title: '旧标题',
      remark: '旧备注',
      isDeleted: true,
    );
    final current = TodoItem(
      id: 'restore',
      title: '最新标题',
      remark: '最新备注',
      groupId: 'active-group',
      isDeleted: true,
    );
    final loadedTodos = <TodoItem>[stale];
    TodoItem? savedTodo;
    await pumpManagementPage(
      tester,
      HistoricalTodosScreen(
        username: 'ui-test',
        loadTodos: () async => loadedTodos,
        loadGroups: () async => [TodoGroup(id: 'active-group', name: '当前文件夹')],
        loadTodoById: (_, _) async => current,
        saveTodo: (_, todo) async {
          savedTodo = todo;
          loadedTodos[0] = todo;
        },
      ),
    );

    await tapVisible(tester, find.text('回收站 1'));
    await tapVisible(tester, find.text('恢复待办'));
    await tester.pumpAndSettle();

    expect(savedTodo?.title, '最新标题');
    expect(savedTodo?.remark, '最新备注');
    expect(savedTodo?.groupId, 'active-group');
    expect(savedTodo?.isDeleted, isFalse);
    expect(stale.title, '旧标题');
    expect(stale.isDeleted, isTrue);
    expect(find.text('回收站 0'), findsOneWidget);
  });

  testWidgets('待修复页展示可读原因与恢复入口', (tester) async {
    await pumpManagementPage(tester, historyTodoPage());
    await tapVisible(tester, find.text('待修复 1'));
    expect(find.text('所属文件夹已失效'), findsOneWidget);
    expect(find.text('恢复到独立待办'), findsOneWidget);
    expect(find.textContaining('无效ID'), findsNothing);
  });

  testWidgets('待办加载错误可重试', (tester) async {
    var attempts = 0;
    await pumpManagementPage(
      tester,
      HistoricalTodosScreen(
        username: 'ui-test',
        loadGroups: () async => [],
        loadTodos: () async {
          if (attempts++ == 0) throw StateError('load failed');
          return historyTodos();
        },
      ),
    );
    expect(find.text('暂时无法加载待办'), findsOneWidget);
    await tapVisible(tester, find.text('重新加载'));
    expect(find.text('完成项目第一阶段'), findsOneWidget);
  });

  testWidgets('倒计时历史搜索、排序且不显示未来记录', (tester) async {
    await pumpManagementPage(
      tester,
      HistoricalCountdownsScreen(
        username: 'ui-test',
        loadCountdowns: () async => historyCountdowns(),
      ),
    );
    expect(find.text('未来的计划'), findsNothing);
    expect(
      tester.getTopLeft(find.text('期待已久的夏日旅行')).dy,
      lessThan(tester.getTopLeft(find.text('第一次独立完成项目')).dy),
    );
    await tapVisible(tester, find.text('最早结束'));
    expect(
      tester.getTopLeft(find.text('第一次独立完成项目')).dy,
      lessThan(tester.getTopLeft(find.text('期待已久的夏日旅行')).dy),
    );
    await tester.enterText(find.byType(TextField), '旅行');
    await tester.pumpAndSettle();
    expect(find.text('找到 1 段记录'), findsOneWidget);
    expect(find.text('第一次独立完成项目'), findsNothing);
  });

  testWidgets('倒计时历史按日历日判断夏令时切换边界', (tester) async {
    await pumpManagementPage(
      tester,
      HistoricalCountdownsScreen(
        username: 'ui-test',
        now: () => DateTime.utc(2026, 3, 9, 4, 30),
        loadCountdowns: () async => [
          CountdownItem(
            id: 'dst-boundary',
            title: '夏令时切换前到期',
            targetDate: DateTime.utc(2026, 3, 8, 5),
          ),
        ],
      ),
    );

    expect(find.text('共 1 段记录'), findsOneWidget);
    expect(find.text('夏令时切换前到期'), findsOneWidget);
    expect(find.text('1 天前结束'), findsOneWidget);
  });

  test('服务端相对时间按本地日历日计算夏令时切换后的明天', () {
    final now = DateTime(2026, 3, 8, 12);
    final tomorrow = DateTime(2026, 3, 9, 9).toUtc().millisecondsSinceEpoch;

    expect(
      AppTimeFormats.relativeFromServerTimestamp(tomorrow, now: now),
      '明天 09:00',
    );
  });

  testWidgets('分享待办的明天标签在夏令时切换后保持正确', (tester) async {
    final now = DateTime(2026, 3, 8, 12);
    final todo = TodoItem(
      id: 'share-tomorrow',
      title: '明日任务',
      createdDate: now.toUtc().millisecondsSinceEpoch,
      dueDate: DateTime(2026, 3, 9, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareTodoSection(
            todos: [todo],
            todoGroups: const [],
            isLight: true,
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1天后'), findsOneWidget);
    expect(find.text('0天后'), findsNothing);
  });

  testWidgets('主页重要日按日期隐藏昨天到期记录', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CountdownSectionWidget(
              username: 'calendar-test',
              isLight: false,
              onDataChanged: () {},
              now: () => DateTime(2026, 3, 9, 0, 30),
              countdowns: [
                CountdownItem(
                  id: 'expired',
                  title: '昨天到期',
                  targetDate: DateTime(2026, 3, 8, 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无有效倒计时'), findsOneWidget);
    expect(find.text('昨天到期'), findsNothing);
  });

  testWidgets('倒计时删除取消与确认只调用一次', (tester) async {
    var calls = 0;
    final items = historyCountdowns();
    final pending = Completer<void>();
    await pumpManagementPage(
      tester,
      HistoricalCountdownsScreen(
        username: 'ui-test',
        loadCountdowns: () async => items,
        deleteCountdown: (item) async {
          calls++;
          await pending.future;
          items.removeWhere((t) => t.id == item.id);
        },
      ),
    );
    await tapVisible(tester, find.text('彻底删除').first);
    await tapVisible(tester, find.text('取消'));
    expect(calls, 0);
    await tapVisible(tester, find.text('彻底删除').first);
    await tester.tap(find.text('确认删除'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    expect(find.text('删除中…'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('共 1 段记录'), findsOneWidget);
    expect(find.text('期待已久的夏日旅行'), findsNothing);
  });

  testWidgets('倒计时删除失败保留记录及重试入口', (tester) async {
    await pumpManagementPage(
      tester,
      HistoricalCountdownsScreen(
        username: 'ui-test',
        loadCountdowns: () async => historyCountdowns(),
        deleteCountdown: (_) async => throw StateError('failure'),
      ),
    );
    await tapVisible(tester, find.text('彻底删除').first);
    await tapVisible(tester, find.text('确认删除'));
    expect(find.text('删除失败，请稍后重试'), findsOneWidget);
    expect(find.text('期待已久的夏日旅行'), findsOneWidget);
    expect(find.text('彻底删除'), findsNWidgets(2));
  });

  testWidgets('倒计时加载失败可重试，离开页面后返回数据不报错', (tester) async {
    var attempts = 0;
    final pending = Completer<List<CountdownItem>>();
    await pumpManagementPage(
      tester,
      HistoricalCountdownsScreen(
        username: 'ui-test',
        loadCountdowns: () {
          if (attempts++ == 0) return Future.error(StateError('failure'));
          return pending.future;
        },
      ),
    );
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(historyCountdowns());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('消息搜索及待处理筛选兼容字符串时间戳', (tester) async {
    await pumpManagementPage(tester, messagePage());
    expect(find.text('全部 3'), findsOneWidget);
    expect(find.text('待处理 1'), findsOneWidget);
    await tapVisible(tester, find.text('待处理 1'));
    expect(find.text('小夏已退出团队'), findsNothing);
    expect(find.text('同意入队'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不匹配');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的消息'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '一起把计划');
    await tester.pumpAndSettle();
    expect(find.text('同意入队'), findsOneWidget);
  });

  for (final action in ['approve', 'reject']) {
    testWidgets('消息处理保留 $action 操作且忙碌时禁用按钮', (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      var handled = false;
      await pumpManagementPage(
        tester,
        TeamMessageCenterScreen(
          managedTeams: messageTeams(),
          fetchMessages: (_) async => {
            'success': true,
            'messages': teamMessages()
                .map(
                  (m) => {
                    ...m,
                    if (m['user_id'] == 8 && handled)
                      'request_status': action == 'approve' ? 1 : 2,
                  },
                )
                .toList(),
          },
          processRequest: (team, user, value) {
            expect(team, 'team');
            expect(user, 8);
            expect(value, action);
            calls++;
            return pending.future;
          },
        ),
      );
      await tester.tap(find.text(action == 'approve' ? '同意入队' : '拒绝'));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('处理中…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      handled = true;
      pending.complete({'success': true});
      await tester.pumpAndSettle();
      expect(find.text('待处理 0'), findsOneWidget);
    });
  }

  testWidgets('消息处理异常解除忙碌状态', (tester) async {
    await pumpManagementPage(
      tester,
      TeamMessageCenterScreen(
        managedTeams: messageTeams(),
        fetchMessages: (_) async => {
          'success': true,
          'messages': teamMessages(),
        },
        processRequest: (_, _, _) async => throw StateError('network'),
      ),
    );
    await tapVisible(tester, find.text('同意入队'));
    expect(find.text('处理失败，请稍后重试'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('消息加载失败不伪装为空列表并支持重试', (tester) async {
    var tries = 0;
    await pumpManagementPage(
      tester,
      TeamMessageCenterScreen(
        managedTeams: messageTeams(),
        fetchMessages: (_) async => tries++ == 0
            ? {'success': false}
            : {'success': true, 'messages': teamMessages()},
      ),
    );
    expect(find.text('1 个团队的消息加载失败，请重试。'), findsOneWidget);
    expect(find.text('暂无系统消息'), findsNothing);
    await tapVisible(tester, find.text('重新加载'));
    expect(find.text('全部 3'), findsOneWidget);
  });

  testWidgets('单个团队请求异常时仍显示其他团队消息', (tester) async {
    await pumpManagementPage(
      tester,
      TeamMessageCenterScreen(
        managedTeams: [
          ...messageTeams(),
          Team(
            uuid: 'offline-team',
            name: '暂时离线团队',
            creatorId: 2,
            createdAt: 0,
            userRole: TeamRole.admin,
          ),
        ],
        fetchMessages: (teamUuid) async {
          if (teamUuid == 'offline-team') {
            throw StateError('network unavailable');
          }
          return {'success': true, 'messages': teamMessages()};
        },
      ),
    );

    expect(find.text('1 个团队的消息加载失败，请重试。'), findsOneWidget);
    expect(find.text('全部 3'), findsOneWidget);
    expect(find.text('小林申请加入团队，期待和大家一起完成接下来的计划。'), findsOneWidget);
    expect(find.text('暂无系统消息'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('三处页面长文字与小屏大字体无溢出 $brightness', (tester) async {
      await pumpManagementPage(
        tester,
        historyTodoPage(),
        size: const Size(320, 740),
        scale: 1.8,
        brightness: brightness,
      );
      await tapVisible(tester, find.text('回收站 2'));
      await tapVisible(tester, find.text('彻底删除').first);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('取消'));
      await pumpManagementPage(
        tester,
        HistoricalCountdownsScreen(
          username: 'ui-test',
          loadCountdowns: () async => [
            CountdownItem(
              title: '这是一个很长很长的倒计时标题，用于验证多行文字不会被截断或挤出卡片',
              targetDate: DateTime(2024),
            ),
          ],
        ),
        size: const Size(320, 740),
        scale: 1.8,
        brightness: brightness,
      );
      await tapVisible(tester, find.text('彻底删除'));
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('取消'));
      await pumpManagementPage(
        tester,
        messagePage(),
        size: const Size(320, 740),
        scale: 1.8,
        brightness: brightness,
      );
      await tester.ensureVisible(find.text('同意入队'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
