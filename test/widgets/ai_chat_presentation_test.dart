import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/widgets/ai_chat_markdown.dart';
import 'package:countdown_todo/widgets/ai_chat_thinking_panel.dart';
import 'package:countdown_todo/widgets/ai_tool_call_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _reasoning = '先读取课程和待办，再安排不冲突的执行时段。';
const _tablePreviewPath = String.fromEnvironment('CDT_MARKDOWN_TABLE_PREVIEW');
const _billingReply = '''### 当前9月30日实际记录（3笔，全是支出）

| 时间 | 商户 | 类别 | 金额 |
| --- | --- | --- | --- |
| 21:34 | 老管家家清官方旗舰店 | 日用 | ¥29.90 |
| 17:02 | 必胜客（宣城万达店） | 餐饮 | ¥45.00 |
| 15:04 | 卡旺卡饮品 | 饮品 | ¥15.00 |

9月收入与结余请查看下方汇总。
''';
const _reply = '''### 今天的安排

| 时间 | 任务 | 说明 |
| --- | --- | --- |
| 19:30–21:00 | 英语国家社会与文化汇报准备 | 今晚先做选题和资料收集，之后继续推进。 |
| 21:00–21:30 | 俯卧撑30个 | 今日打卡，可按状态调整执行时间。 |

以上是可调整的规划块，请核对后确认。

**后续提醒**：明天还有报告任务。
''';
const _call = ChatNativeToolCall(
  id: 'q-1',
  name: 'query_app_data',
  arguments: '{"domain":"todos"}',
  resultSummary: '查询匹配2条，本页返回2条。',
  result: {
    'ok': true,
    'total_count': 2,
    'items': [
      {'id': 'todo-report', 'title': '提交报告'},
      {'id': 'todo-reading', 'title': '复习数据结构'},
    ],
  },
);

Widget _page({
  required Widget panel,
  String reply = '',
  Brightness brightness = Brightness.light,
  double textScale = 1,
  GlobalKey? captureKey,
}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    ),
    fontFamily:
        const String.fromEnvironment('CDT_CHAT_PREVIEW').isEmpty &&
            _tablePreviewPath.isEmpty
        ? null
        : 'CDTChatPreview',
  ),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: RepaintBoundary(
        key: captureKey,
        child: Scaffold(
          appBar: AppBar(title: const Text('帮我规划今天的待办')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                panel,
                if (reply.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: AiChatMarkdown(data: reply),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const previewPath = String.fromEnvironment('CDT_CHAT_PREVIEW');
  if (previewPath.isNotEmpty || _tablePreviewPath.isNotEmpty) {
    setUpAll(() async {
      final font = FontLoader('CDTChatPreview')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('/System/Library/Fonts/Supplemental/Songti.ttc')
                  .readAsBytesSync(),
            ),
          ),
        );
      await font.load();
    });
  }

  testWidgets('有工具无推理文字时仍有思考入口，默认收起且不增加长列表高度', (tester) async {
    if (previewPath.isNotEmpty) {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final capture = GlobalKey();
    await tester.pumpWidget(
      _page(
        captureKey: capture,
        panel: AiChatThinkingPanel(
          hasReply: true,
          calls: [
            for (var i = 0; i < 20; i++)
              ChatNativeToolCall(
                id: 'q-$i',
                name: _call.name,
                arguments: _call.arguments,
                result: _call.result,
                resultSummary: _call.resultSummary,
              ),
          ],
        ),
        reply: _reply,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('思考过程'), findsOneWidget);
    expect(find.text('20 次工具调用'), findsOneWidget);
    expect(find.byType(AiToolCallTile), findsNothing);
    expect(find.text('App 返回的数据'), findsNothing);
    expect(
      tester.getSize(find.byType(AiChatThinkingPanel)).height,
      lessThan(50),
    );
    expect(
      tester.getTopLeft(find.text('思考过程')).dy,
      lessThan(tester.getTopLeft(find.byType(AiChatMarkdown)).dy),
    );
    expect(tester.takeException(), isNull);
    if (previewPath.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final snapshot = await boundary.toImage(pixelRatio: 2);
        final bytes = await snapshot.toByteData(format: ui.ImageByteFormat.png);
        File(previewPath).writeAsBytesSync(bytes!.buffer.asUint8List());
        snapshot.dispose();
      });
    }
  });

  final queryCaptions =
      <(String, Map<String, dynamic>, Map<String, dynamic>?, String)>[
        (
          'query_app_data',
          {'domain': 'todos', 'status': 'pending', 'limit': 30},
          {
            'ok': true,
            'offset': 0,
            'has_more': true,
            'items': List.filled(30, <String, dynamic>{}),
          },
          '查询了未完成待办（第1–30条）',
        ),
        (
          'query_app_data',
          {'domain': 'todos', 'status': 'pending', 'limit': 30, 'offset': 30},
          {
            'ok': true,
            'offset': 30,
            'has_more': false,
            'items': List.filled(12, <String, dynamic>{}),
          },
          '查询了未完成待办（第31–42条）',
        ),
        (
          'query_app_data',
          {'domain': 'todos', 'status': 'completed', 'limit': 30},
          {
            'ok': true,
            'offset': 0,
            'has_more': false,
            'items': [<String, dynamic>{}],
          },
          '查询了已完成待办（1条）',
        ),
        (
          'query_app_data',
          {'domain': 'todos', 'status': 'pending', 'keyword': '报告'},
          {'ok': true, 'items': <dynamic>[]},
          '查询了「报告」相关未完成待办（0条）',
        ),
        (
          'query_finance',
          {
            'view': 'transactions',
            'start_date': '2026-09-01',
            'end_date_exclusive': '2026-10-01',
          },
          {'ok': true},
          '查询了9.1–9.30的账单',
        ),
        (
          'query_finance',
          {
            'view': 'budgets',
            'start_date': '2026-09-23',
            'end_date_exclusive': '2026-09-24',
          },
          {'ok': true},
          '查询了9月的预算',
        ),
        (
          'query_finance',
          {
            'view': 'transactions',
            'start_date': '2025-12-01',
            'end_date_exclusive': '2026-02-01',
          },
          {'ok': true},
          '查询了2025.12.1–2026.1.31的账单',
        ),
        (
          'query_app_data',
          {'domain': 'courses', 'keyword': '王'},
          {'ok': true},
          '查询了「王」相关课程',
        ),
        (
          'query_habits',
          {
            'keyword': '喝水',
            'start_date': '2026-10-02',
            'end_date_exclusive': '2026-10-03',
          },
          {'ok': true},
          '查询了10.2的「喝水」相关习惯进度',
        ),
        (
          'query_app_data',
          {'domain': 'todos', 'status': 'pending', 'limit': 30},
          null,
          '正在查询未完成待办（第1–30条）',
        ),
        (
          'query_finance',
          {
            'view': 'summary',
            'start_date': '2026-02-30',
            'end_date_exclusive': '2026-03-01',
          },
          {'ok': false, 'error': '日期不存在'},
          '查询失败：收支汇总',
        ),
        (
          'query_app_data',
          {
            'domain': 'pomodoro_records',
            'view': 'summary',
            'record_status': 'completed',
          },
          {
            'ok': true,
            'total_count': 20,
            'summary': {'duration_seconds': 7200},
          },
          '查询了已完成专注记录汇总',
        ),
        (
          'query_app_data',
          {
            'domain': 'todos',
            'group_id': 'study',
            'date_status': 'unscheduled',
            'status': 'pending',
          },
          {
            'ok': true,
            'offset': 0,
            'items': [
              {'id': 'task-1'},
            ],
            'has_more': false,
          },
          '查询了指定分类的未安排日期的未完成待办（1条）',
        ),
        (
          'query_finance',
          {'view': 'summary', 'group_by': 'merchant'},
          {'ok': true},
          '查询了商户支出排行',
        ),
      ];
  for (final (function, args, result, caption) in queryCaptions) {
    testWidgets('调用名称按实际条件和返回数量展示：$caption', (tester) async {
      await tester.pumpWidget(
        _page(
          panel: AiToolCallTile(
            call: ChatNativeToolCall(
              id: 'query-caption',
              name: function,
              arguments: jsonEncode(args),
              result: result,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(caption), findsOneWidget);
      expect(find.text('函数：$function'), findsNothing);
      await tester.tap(find.text(caption));
      await tester.pumpAndSettle();
      expect(find.text('函数：$function'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('思考与每次函数详情均能手动展开，参数和实际返回仍可查看', (tester) async {
    await tester.pumpWidget(
      _page(
        panel: const AiChatThinkingPanel(
          reasoning: _reasoning,
          calls: [_call],
          hasReply: true,
        ),
        reply: '正式回复：今天还有2项待办。',
      ),
    );
    await tester.tap(find.text('思考过程'));
    await tester.pumpAndSettle();
    expect(find.byType(AiChatMarkdown), findsNWidgets(2));
    expect(find.text('查询了待办（2条）'), findsOneWidget);
    expect(find.text('App 返回的数据'), findsNothing);
    await tester.tap(find.text('查询了待办（2条）'));
    await tester.pumpAndSettle();
    expect(find.text('App 返回的数据'), findsOneWidget);
    final details = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((text) => text.data ?? '')
        .join('\n');
    expect(details, contains('todos'));
    expect(details, contains('todo-report'));
    expect(details, contains('提交报告'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('回复首次出现自动折叠，之后手动展开不会被文字刷新或收尾反复折叠', (tester) async {
    Widget state({
      required bool hasReply,
      bool streaming = true,
      String reply = '',
    }) => _page(
      panel: AiChatThinkingPanel(
        reasoning: _reasoning,
        calls: const [_call],
        isStreaming: streaming,
        hasReply: hasReply,
      ),
      reply: reply,
    );
    await tester.pumpWidget(state(hasReply: false));
    await tester.tap(find.text('思考过程'));
    await tester.pump();
    expect(find.byType(AiToolCallTile), findsOneWidget);
    await tester.pumpWidget(state(hasReply: true, reply: '正式回复'));
    await tester.pump();
    expect(find.byType(AiToolCallTile), findsNothing);
    await tester.tap(find.text('思考过程'));
    await tester.pump();
    expect(find.byType(AiToolCallTile), findsOneWidget);
    await tester.pumpWidget(state(hasReply: true, reply: '正式回复继续生成'));
    await tester.pump();
    expect(find.byType(AiToolCallTile), findsOneWidget);
    await tester.pumpWidget(
      state(hasReply: true, streaming: false, reply: '完整回复'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AiToolCallTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有正式回复的工具轮次结束，也会折叠并允许重新展开', (tester) async {
    await tester.pumpWidget(
      _page(
        panel: const AiChatThinkingPanel(calls: [_call], isStreaming: true),
      ),
    );
    await tester.tap(find.text('思考过程'));
    await tester.pump();
    expect(find.byType(AiToolCallTile), findsOneWidget);
    await tester.pumpWidget(
      _page(panel: const AiChatThinkingPanel(calls: [_call])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AiToolCallTile), findsNothing);
    await tester.tap(find.text('思考过程'));
    await tester.pumpAndSettle();
    expect(find.byType(AiToolCallTile), findsOneWidget);
  });

  testWidgets('查询结果到达不强制展开详情，已手动展开的详情保持展开', (tester) async {
    const pending = ChatNativeToolCall(
      id: 'q-1',
      name: 'query_app_data',
      arguments: '{"domain":"todos"}',
    );
    Widget state(ChatNativeToolCall call) =>
        _page(panel: AiChatThinkingPanel(calls: [call], hasReply: true));
    await tester.pumpWidget(state(pending));
    await tester.tap(find.text('思考过程'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(state(_call));
    await tester.pumpAndSettle();
    expect(find.text('App 返回的数据'), findsNothing);
    await tester.tap(find.text('查询了待办（2条）'));
    await tester.pumpAndSettle();
    expect(find.text('App 返回的数据'), findsOneWidget);
    await tester.pumpWidget(
      state(
        const ChatNativeToolCall(
          id: 'q-1',
          name: 'query_app_data',
          arguments: '{"domain":"todos"}',
          resultSummary: '已返回查询结果',
          result: {'ok': true, 'total_count': 3},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('App 返回的数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('窄屏、${brightness.name}模式和较大系统字号下，表格可横向查看且无溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _page(
          brightness: brightness,
          textScale: 1.4,
          panel: const AiChatThinkingPanel(calls: [_call], hasReply: true),
          reply: _reply,
        ),
      );
      await tester.pumpAndSettle();
      final horizontal = find.byWidgetPredicate(
        (w) =>
            w is Scrollable &&
            (w.axisDirection == AxisDirection.right ||
                w.axisDirection == AxisDirection.left),
      );
      expect(horizontal, findsOneWidget);
      final scroll = tester.state<ScrollableState>(horizontal);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(tester.getSize(find.byType(Table)).height, lessThan(360));
      await tester.drag(horizontal, const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    testWidgets('${platform.name}表格滑条位于末行下方，不受页面安全区影响且可拖动', (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await tester.pumpWidget(
        _page(
          captureKey: capture,
          textScale: 1.4,
          panel: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(padding: const EdgeInsets.fromLTRB(24, 0, 24, 34)),
              child: Theme(
                data: Theme.of(context).copyWith(
                  platform: platform,
                  scrollbarTheme: const ScrollbarThemeData(interactive: true),
                ),
                child: const AiChatMarkdown(data: _billingReply),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollbarPaint = find.descendant(
        of: find.byType(AiChatMarkdown),
        matching: find.ancestor(
          of: find.byType(Table),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.foregroundPainter is ScrollbarPainter,
          ),
        ),
      );
      expect(scrollbarPaint, findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(scrollbarPaint).foregroundPainter!
              as ScrollbarPainter;
      final rect = tester.getRect(scrollbarPaint);
      final thumbYs = <double>[
        for (double y = 0.5; y < rect.height; y += 0.5)
          if (painter.hitTestOnlyThumbInteractive(
            Offset(rect.width / 4, y),
            ui.PointerDeviceKind.mouse,
          ))
            y,
      ];
      expect(thumbYs, isNotEmpty);
      final thumbTop = rect.top + thumbYs.first;
      expect(thumbTop, greaterThan(tester.getRect(find.byType(Table)).bottom));
      expect(
        rect.top + thumbYs.last,
        lessThan(tester.getTopLeft(find.text('9月收入与结余请查看下方汇总。')).dy),
      );
      if (_tablePreviewPath.isNotEmpty && platform == TargetPlatform.android) {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final snapshot = await boundary.toImage(pixelRatio: 2);
          final bytes = await snapshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          File(_tablePreviewPath).writeAsBytesSync(bytes!.buffer.asUint8List());
          snapshot.dispose();
        });
      }
      final horizontal = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      );
      final scroll = tester.state<ScrollableState>(horizontal);
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width / 4, thumbTop + painter.thickness / 2),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }
}
