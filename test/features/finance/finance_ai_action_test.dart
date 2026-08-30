import 'package:countdown_todo/features/finance/models/finance_ai_action.dart';
import 'package:countdown_todo/features/finance/services/finance_text_parser.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('提取账单查询和已有账单操作块', () {
    const reply = '''本月支出如下，修改和删除请确认：
[FINANCE_ACTION_START]
[
  {"action":"finance_summary","from":"2026-08-01","to":"2026-09-01"},
  {"action":"update_finance","transactionId":"tx-1","amount":30,"category":"餐饮"},
  {"action":"delete_finance","transactionId":"tx-2","reason":"重复记录"}
]
[FINANCE_ACTION_END]''';

    final actions = FinanceTextParser.extractAssistantActions(reply);

    expect(actions, hasLength(3));
    expect(actions[0].type, FinanceAiActionType.summary);
    expect(actions[0].from, '2026-08-01');
    expect(actions[1].type, FinanceAiActionType.update);
    expect(actions[1].transactionId, 'tx-1');
    expect(actions[1].amountMinor, 3000);
    expect(actions[1].hasCategory, isTrue);
    expect(actions[2].type, FinanceAiActionType.delete);
    expect(actions[2].reason, '重复记录');
    expect(
      FinanceTextParser.cleanAssistantContent(reply),
      '本月支出如下，修改和删除请确认：',
    );
  });

  test('忽略没有真实账单ID的危险操作', () {
    const reply = '''[FINANCE_ACTION_START]
[{"action":"update_finance","amount":30},{"action":"delete_finance"}]
[FINANCE_ACTION_END]''';

    expect(FinanceTextParser.extractAssistantActions(reply), isEmpty);
  });

  test('账单操作可以写入聊天历史并保留确认状态', () {
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: '请确认账单操作',
      financeActions: [
        FinanceAiAction(
          type: FinanceAiActionType.update,
          transactionId: 'tx-1',
          amountMinor: 3000,
          hasAmount: true,
        ),
      ],
    );

    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.financeActions, hasLength(1));
    expect(restored.financeActions!.single.transactionId, 'tx-1');
    expect(restored.financeActions!.single.amountMinor, 3000);
    expect(restored.financeActions!.single.isAdded, isFalse);
  });
}
