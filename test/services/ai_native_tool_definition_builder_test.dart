import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/features/finance/models/finance_ai_action.dart';
import 'package:countdown_todo/features/finance/services/finance_ai_context_service.dart';
import 'package:countdown_todo/features/finance/services/finance_text_parser.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_native_tool_call_parser.dart';
import 'package:countdown_todo/services/ai_native_tool_definition_builder.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';

void main() {
  group('AiNativeToolDefinitionBuilder', () {
    test('offers a finance delete tool for colloquial delete wording', () {
      const request = '把上周那笔账单删了';

      expect(
        AiTodoContextBuilder.isExplicitlyRequested(request, '删了'),
        isTrue,
      );
      expect(
        AiTodoContextBuilder.buildActionProtocolPrompt(request),
        contains('- delete_finance'),
      );

      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        request,
      );
      expect(
        AiNativeToolDefinitionBuilder.allowedFinanceActionNames(tools),
        contains('delete_finance'),
      );
      expect(FinanceAiContextService.shouldInjectFor(request), isTrue);
    });

    test('offers only the requested finance update tool', () {
      const request = '把上周那笔账单金额改成30元';

      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        request,
      );

      expect(AiNativeToolDefinitionBuilder.allowedFinanceActionNames(tools), {
        'update_finance',
      });
      expect(FinanceAiContextService.shouldInjectFor(request), isTrue);
    });

    test('offers finance updates for correction and adjustment wording', () {
      for (final request in [
        '把上周那笔账单更正为30元',
        '把上周那笔账单金额调整为30元',
        '上周那笔账单更正为30元',
        '上周那笔账单金额调整到50元',
        '帮我调整上周那笔账单金额为30元',
        '帮我调整上周那笔账单金额为30元，并分析对预算的影响',
      ]) {
        final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          request,
        );

        expect(AiNativeToolDefinitionBuilder.allowedFinanceActionNames(tools), {
          'update_finance',
        }, reason: request);
      }
    });

    test('keeps finance adjustment questions read-only', () {
      for (final request in [
        '查询上周账单调整情况',
        '查询上周账单调整为30元的记录',
        '分析把上周账单调整为30元后的预算影响',
        '分析上周账单调整为30元后的预算影响',
        '把上周账单调整为30元后的预算影响',
        '把上周账单调整情况分析一下',
      ]) {
        final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          request,
        );

        expect(
          AiNativeToolDefinitionBuilder.allowedToolNames(tools),
          isEmpty,
          reason: request,
        );
      }
    });

    test('does not expose finance mutation tools for a read-only query', () {
      for (final request in ['查询上周账单明细', '哪些账单需要删除']) {
        final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          request,
        );

        expect(AiNativeToolDefinitionBuilder.allowedToolNames(tools), isEmpty);
        expect(
          AiNativeToolDefinitionBuilder.allowedFinanceActionNames(tools),
          isEmpty,
        );
      }
    });

    test(
      'converts an allowed delete call into a finance confirmation action',
      () {
        const toolName = 'propose_finance_actions';
        final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          '删除上周那笔账单',
        );
        final reply = AiNativeToolCallParser.appendToAssistantText(
          '',
          const [
            AiChatFunctionCall(
              id: 'call-delete',
              name: toolName,
              arguments: '{"actions":[{"action":"delete_finance","transactionId":"txn-1"}]}',
            ),
          ],
          allowedToolNames: AiNativeToolDefinitionBuilder.allowedToolNames(
            tools,
          ),
          allowedCdtActionNames:
              AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
          allowedFinanceActionNames:
              AiNativeToolDefinitionBuilder.allowedFinanceActionNames(tools),
        );

        final actions = FinanceTextParser.extractAssistantActions(reply);
        expect(actions, hasLength(1));
        expect(actions.single.type, FinanceAiActionType.delete);
        expect(actions.single.transactionId, 'txn-1');
      },
    );
  });
}
