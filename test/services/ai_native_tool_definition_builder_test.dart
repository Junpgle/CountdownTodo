import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/features/finance/models/finance_ai_action.dart';
import 'package:countdown_todo/features/finance/services/finance_ai_context_service.dart';
import 'package:countdown_todo/features/finance/services/finance_text_parser.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_native_tool_call_parser.dart';
import 'package:countdown_todo/services/ai_native_tool_definition_builder.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';

Map<String, dynamic> _financeItemProperties(
  List<Map<String, dynamic>> tools,
  String toolName,
  String arrayName,
) {
  final function = Map<String, dynamic>.from(
    tools.singleWhere(
          (tool) =>
              (tool['function'] as Map<String, dynamic>)['name'] == toolName,
        )['function']
        as Map,
  );
  final parameters = Map<String, dynamic>.from(function['parameters'] as Map);
  final properties = Map<String, dynamic>.from(parameters['properties'] as Map);
  final array = Map<String, dynamic>.from(properties[arrayName] as Map);
  final items = Map<String, dynamic>.from(array['items'] as Map);
  return Map<String, dynamic>.from(items['properties'] as Map);
}

void main() {
  group('AiNativeToolDefinitionBuilder', () {
    test('缺少卡片的反馈与口语任务描述承接规划，普通任务描述不强行变成规划', () {
      for (final text in [
        '你没给我操作块', '我没看到卡片', '规划块不显示',
        '操作卡片在哪里',
        '我打算做一点公考的行测和申论，然后做习概的论文提交，再抽时间做党课',
      ]) {
        final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          text,
          previousAssistantMessage: '规划块草案已生成，请核对方案。',
        );
        expect(AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
            contains('create_plan_block'), reason: text);
      }
      final unrelated = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '我打算做一点行测', previousAssistantMessage: '今天心情如何？');
      expect(AiNativeToolDefinitionBuilder.allowedCdtActionNames(unrelated),
          isNot(contains('create_plan_block')));
      expect(AiNativeToolDefinitionBuilder.isMissingActionCardReport('调整首页布局'), false);
    });

    test('截图中的任务、时间偏好、确认与要的都承接规划，不泄漏其他修改动作', () {
      var previousUser = '帮我规划一下今天下午的安排';
      var previousAssistant = '今天下午安排建议，需要我为具体任务生成规划块吗？';
      for (final text in [
        '我要安排行测、申论以及习概的小论文。',
        '避开晚餐时间，到晚上九点半，可以联排',
        '可以，生成规划块',
        '确认',
        '要的',
      ]) {
        final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          text,
          previousUserMessage: previousUser,
          previousAssistantMessage: previousAssistant,
        );
        final actions = AiNativeToolDefinitionBuilder.allowedCdtActionNames(
          tools,
        );
        expect(actions, contains('create_plan_block'), reason: text);
        expect(actions, isNot(contains('delete_todo')), reason: text);
        previousUser = text;
        previousAssistant = '规划块草案：行测、申论和习概论文；请核对方案。';
      }
    });

    test('规划块记录支持待建标题，由App分配ID而不是模型编造ID', () {
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '生成规划块',
      );
      final properties = _financeItemProperties(
        tools,
        'propose_cdt_actions',
        'actions',
      );
      final blockProperties =
          ((properties['blocks'] as Map)['items'] as Map)['properties'] as Map;
      expect(blockProperties, contains('newTodoTitle'));
    });
    test('公考规划及可以的接续保留规划工具，不开放删除或复制待办', () {
      const request =
          '从现在开始，我要安排公考的行测、申论，还有那个习概的选题，'
          '你帮我规划一下，到晚上九点半。';
      for (final text in [request, '可以', '好的！', '生成吧']) {
        final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          text,
          previousUserMessage: request,
        );
        final actions = AiNativeToolDefinitionBuilder.allowedCdtActionNames(
          tools,
        );
        expect(actions, contains('create_plan_block'));
        expect(actions, isNot(contains('delete_plan_block')));
        expect(actions, isNot(contains('create_todo')));
      }
    });

    test('可以承接助手明确询问生成规划的方案', () {
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '可以',
        previousUserMessage: '行测、申论和习概选题，到晚上九点半',
        previousAssistantMessage: '需要我按这个方案生成规划块吗？',
      );
      expect(
        AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
        contains('create_plan_block'),
      );
    });

    test('否定、查询、换话题和无规划上下文的确认不恢复规划工具', () {
      for (final previous in ['不要帮我规划', '查看今天有哪些规划块', '调整液态玻璃']) {
        final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          '可以',
          previousUserMessage: previous,
        );
        expect(
          AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
          isNot(contains('create_plan_block')),
        );
      }
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '先查一下天气',
        previousUserMessage: '帮我规划今天的任务',
      );
      expect(
        AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
        isNot(contains('create_plan_block')),
      );
    });

    test('offers a finance delete tool for colloquial delete wording', () {
      const request = '把上周那笔账单删了';

      expect(AiTodoContextBuilder.isExplicitlyRequested(request, '删了'), isTrue);
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

    test('待办移出分类允许空分类并保留真实待办ID', () {
      const request = '把这个待办移出当前分类';
      final systemPrompt = AiTodoContextBuilder.buildSystemPrompt(
        customPrompt: '',
        promptEnabled: false,
        todos: const [],
        todoGroups: const [],
      );
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        request,
      );
      final actionTool = tools.singleWhere(
        (tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] ==
            'propose_cdt_actions',
      );
      final function = actionTool['function'] as Map<String, dynamic>;
      final parameters = function['parameters'] as Map<String, dynamic>;
      final properties = parameters['properties'] as Map<String, dynamic>;
      final actions = properties['actions'] as Map<String, dynamic>;
      final actionItems = actions['items'] as Map<String, dynamic>;
      final actionProperties =
          actionItems['properties'] as Map<String, dynamic>;
      final updates = actionProperties['updates'] as Map<String, dynamic>;
      final updateItems = updates['items'] as Map<String, dynamic>;
      final updateProperties =
          updateItems['properties'] as Map<String, dynamic>;

      expect(systemPrompt, contains('新分类ID或null（移出分类时）'));
      expect(AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools), {
        'categorize_todo',
      });
      expect(
        updateProperties['groupId'],
        containsPair('type', ['string', 'null']),
      );
      expect(
        (updateProperties['groupId'] as Map<String, dynamic>)['description'],
        contains('填写null'),
      );

      final parsed = AiActionParser.extractTodoActions(
        '[ACTION_START]{"action":"categorize_todo","updates":[{"todoId":"todo-1","groupId":null}]}[ACTION_END]',
        originalText: request,
        existingTodoTitles: const {'todo-1': '准备周报'},
      );

      expect(parsed, hasLength(1));
      expect(parsed.single.todoId, 'todo-1');
      expect(parsed.single.groupId, isNull);
      expect(parsed.single.type.name, 'categorizeTodo');
    });

    test('待办移出文件夹时仍提供分类操作', () {
      const request = '把这个待办移出文件夹';
      final prompt = AiTodoContextBuilder.buildActionProtocolPrompt(request);
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        request,
      );

      expect(prompt, isNot(contains('本轮不生成结构化操作')));
      expect(AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools), {
        'categorize_todo',
      });

      final readOnlyTools =
          AiNativeToolDefinitionBuilder.buildNativeToolDefinitions('查看待办文件夹');
      expect(
        AiNativeToolDefinitionBuilder.allowedCdtActionNames(readOnlyTools),
        isEmpty,
      );
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

    test('记账 AI 工具提供无损分金额字段', () {
      final draftTools =
          AiNativeToolDefinitionBuilder.buildNativeToolDefinitions('记一笔午餐28元');
      final actionTools =
          AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
            '把上周那笔账单金额改为30元',
          );
      final draftProperties = _financeItemProperties(
        draftTools,
        'propose_finance_drafts',
        'drafts',
      );
      final actionProperties = _financeItemProperties(
        actionTools,
        'propose_finance_actions',
        'actions',
      );

      expect(
        (draftProperties['amount_minor'] as Map<String, dynamic>)['type'],
        'string',
      );
      expect(
        (actionProperties['amount_minor'] as Map<String, dynamic>)['type'],
        'string',
      );
      expect(
        AiTodoContextBuilder.buildActionProtocolPrompt('记一笔午餐28元'),
        contains('amount_minor'),
      );
    });

    test('原生记账调用会优先保留精确分金额', () {
      final request = '记一笔午餐28元';
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        request,
      );
      final reply = AiNativeToolCallParser.appendToAssistantText(
        '',
        const [
          AiChatFunctionCall(
            id: 'call-large-draft',
            name: 'propose_finance_drafts',
            arguments: '{"drafts":[{"type":"expense","amount":90071992547409.91,"amount_minor":"9007199254740990","date":"2026-10-03"}]}',
          ),
        ],
        allowedToolNames: AiNativeToolDefinitionBuilder.allowedToolNames(tools),
        allowedCdtActionNames:
            AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
        allowedFinanceActionNames:
            AiNativeToolDefinitionBuilder.allowedFinanceActionNames(tools),
      );

      final drafts = FinanceTextParser.extractAssistantDrafts(reply);
      expect(drafts, hasLength(1));
      expect(drafts.single.amountMinor, 9007199254740990);
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
