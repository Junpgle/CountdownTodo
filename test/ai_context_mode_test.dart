import 'package:countdown_todo/models/ai_context_mode.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:countdown_todo/widgets/ai_tool_call_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认工具查询，切换持久化，原有关闭开关保持关闭', () async {
    expect(
      await ChatStorageService.getContextMode(),
      AiContextMode.functionCalling,
    );
    await ChatStorageService.setSmartContextEnabled(false);
    await ChatStorageService.setContextMode(
      AiContextMode.smartContextInjection,
    );
    expect(
      await ChatStorageService.getContextMode(),
      AiContextMode.smartContextInjection,
    );
    expect(await ChatStorageService.isSmartContextEnabled(), false);
    await ChatStorageService.setContextMode(AiContextMode.functionCalling);
    expect(
      await ChatStorageService.getContextMode(),
      AiContextMode.functionCalling,
    );
    expect(await ChatStorageService.isSmartContextEnabled(), false);
  });

  test('查询参数和实际返回内容保存到历史，并供后续追问引用', () {
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: '已查询',
      nativeToolCalls: [
        const ChatNativeToolCall(
          id: 'q-1',
          name: 'query_finance',
          arguments: '{"view":"transactions"}',
          resultSummary: '查询匹配1条',
          result: {
            'ok': true,
            'items': [
              {'id': 'bill-1', 'amount_minor': 1800},
            ],
          },
        ),
      ],
    );
    final restored = ChatMessage.fromJson(message.toJson());
    expect(
      restored.nativeToolCalls!.single.result,
      message.nativeToolCalls!.single.result,
    );
    expect(restored.toLLMMessage(), contains('bill-1'));
    expect(restored.toLLMMessage(), contains('READ_ONLY_TOOL_HISTORY'));
    final legacy = ChatNativeToolCall.fromJson({
      'id': 'old',
      'name': 'propose_cdt_actions',
      'arguments': '{}',
    });
    expect(legacy.result, null);
  });

  testWidgets('函数详情默认收起，手动展开显示真实参数和返回JSON', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                AiToolCallTile(
                  call: ChatNativeToolCall(
                    id: 'q-1',
                    name: 'query_finance',
                    arguments: '{"view":"summary","start_date":"2026-09-01","end_date_exclusive":"2026-10-01"}',
                    resultSummary: '查询匹配65条',
                    result: {'ok': true, 'net_expense_minor': 12345},
                  ),
                ),
                AiToolCallTile(
                  call: ChatNativeToolCall(
                    id: 'q-2',
                    name: 'query_habits',
                    arguments: '{"habit_id":"habit-1"}',
                    resultSummary: '查询失败：读取失败',
                    result: {'ok': false, 'error': '读取失败'},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('查询了9.1–9.30的收支汇总'), findsOneWidget);
    expect(find.text('查询失败：指定习惯进度详情'), findsOneWidget);
    expect(find.text('App 返回的数据'), findsNothing);
    await tester.tap(find.text('查询了9.1–9.30的收支汇总'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查询失败：指定习惯进度详情'));
    await tester.pumpAndSettle();
    expect(find.text('App 返回的数据'), findsNWidgets(2));
    final data = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data)
        .join('\n');
    expect(data, contains('2026-09-01'));
    expect(data, contains('12345'));
    expect(data, contains('"ok": false'));
    expect(data, contains('读取失败'));
    expect(tester.takeException(), isNull);
  });
}
