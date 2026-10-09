import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_tool_result_context.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _largePage({int offset = 0}) => {
  'ok': true,
  'domain': 'todos',
  'filters': {'domain': 'todos', 'status': 'pending'},
  'summary': {'count': 200, 'completed_count': 0},
  'total_count': 200,
  'offset': offset,
  'items': [
    for (var i = 0; i < 50; i++)
      {'id': 'todo-${offset + i}', 'title': '任务$i', 'remark': '长备注' * 3000},
  ],
  'has_more': true,
  'next_offset': offset + 50,
};

void main() {
  test('长页保留完整汇总，分页接续实际传给模型的记录，原始数据不改变', () {
    final source = _largePage(offset: 20);
    final original = jsonEncode(source);
    final model = AiToolResultContext.forModel(source);
    final encoded = jsonEncode(model);
    final items = model['items'] as List;
    expect(
      encoded.length,
      lessThanOrEqualTo(AiToolResultContext.maxResultChars),
    );
    expect(items, isNotEmpty);
    expect(items.length, lessThan(50));
    expect(model['summary'], source['summary']);
    expect(model['total_count'], 200);
    expect(model['context_truncated'], true);
    expect(model['next_offset'], 20 + items.length);
    expect(items.last['id'], 'todo-${20 + items.length - 1}');
    expect(jsonEncode(source), original);
    const outputPath = String.fromEnvironment('CDT_AI_BUDGET_OUTPUT');
    if (outputPath.isNotEmpty) {
      File(outputPath).writeAsStringSync(
        jsonEncode({
          'fixture': '50 tasks, each with 9000-character synthetic remarks',
          'original_chars': original.length,
          'model_chars': encoded.length,
          'model_rows': items.length,
          'matched_count': model['total_count'],
          'evidence':
              'Serialized characters only, not provider-reported tokens.',
        }),
      );
    }
  });

  test('过大的分类统计只省略分组详情，保留总额并标记遗漏路径', () {
    final model = AiToolResultContext.forModel({
      'ok': true,
      'summary': {
        'transaction_count': 20000,
        'net_expense_minor': 987654,
        'expense_by_category': [
          for (var i = 0; i < 20000; i++)
            {'category_id': 'c-$i', 'net_expense_minor': i},
        ],
      },
    });
    expect(model['ok'], true);
    expect((model['summary'] as Map)['net_expense_minor'], 987654);
    expect(model['omitted_fields'], contains('summary.expense_by_category'));
    expect(jsonEncode(model).length, lessThanOrEqualTo(8000));
  });

  test('单条记录仍超出预算时保留可分页的记录ID', () {
    final source = {
      'ok': true,
      'total_count': 1,
      'offset': 40,
      'items': [
        {
          'id': 'todo-large-detail',
          'title': '标题' * 3000,
          'remark': '备注' * 3000,
          'note': '说明' * 3000,
          'recurrence': '循环规则' * 3000,
        },
      ],
      'has_more': true,
      'next_offset': 41,
    };

    final model = AiToolResultContext.forModel(source);
    final item = (model['items'] as List).single as Map;

    expect(item['id'], 'todo-large-detail');
    expect(item.length, lessThan(5));
    expect(model['context_truncated'], true);
    expect(
      (model['omitted_fields'] as List).any(
        (path) => path.toString().startsWith('items[0].'),
      ),
      true,
    );
    expect(model['next_offset'], 41);
    expect(jsonEncode(model).length, lessThanOrEqualTo(8000));
  });

  test('预算内的单笔详情备注完整保留', () {
    final model = AiToolResultContext.forModel({
      'ok': true,
      'items': [
        {'id': 'todo-1', 'remark': '备注' * 600},
      ],
    });
    expect((model['items'] as List).single['remark'], '备注' * 600);
    expect(model, isNot(contains('context_truncated')));
  });

  test('极小剩余预算返回明确错误，不生成无效JSON或假零值', () {
    final model = AiToolResultContext.forModel({
      'ok': true,
      'summary': {for (var i = 0; i < 1000; i++) 'metric-$i': i},
    }, maxChars: 400);
    expect(model['ok'], false);
    expect(model, contains('error'));
    expect(model, isNot(contains('total_count')));
    expect(jsonEncode(model).length, lessThanOrEqualTo(400));
  });

  test('历史只发送最新简要结果，完整调用记录仍可持久化查看', () {
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: '未完成待办共200条，本次只展示部分。',
      nativeToolCalls: [
        for (var i = 0; i < 20; i++)
          ChatNativeToolCall(
            id: 'q-$i',
            name: 'query_app_data',
            arguments: '{"domain":"todos","offset":${i * 50}}',
            result: _largePage(offset: i * 50),
          ),
      ],
    );
    final persisted = ChatMessage.fromJson(message.toJson());
    final text = persisted.toLLMMessage();
    final history = text
        .split('[READ_ONLY_TOOL_HISTORY]\n')
        .last
        .split('\n[/READ_ONLY_TOOL_HISTORY]')
        .first;
    final decoded = jsonDecode(history) as Map;
    expect(history.length, lessThanOrEqualTo(2000));
    expect(decoded['queries'], isNotEmpty);
    expect(decoded['omitted_queries'], greaterThan(0));
    expect(text, contains('todo-950'));
    expect(persisted.nativeToolCalls!.last.result!['items'], hasLength(50));
    expect(
      (persisted.nativeToolCalls!.last.result!['items'] as List).last['remark'],
      '长备注' * 3000,
    );
    expect(persisted.toLLMMessage(toolHistoryBudget: 0), message.content);
  });

  test('重复查询键不受参数顺序与显式默认值影响，不同条件保持独立', () {
    final a = AiToolResultContext.queryKey(
      'query_app_data',
      '{"domain":"todos","status":"pending"}',
    );
    final b = AiToolResultContext.queryKey(
      'query_app_data',
      '{"limit":10,"offset":0,"view":"list","status":"pending","domain":"todos"}',
    );
    expect(a, b);
    expect(
      a,
      isNot(
        AiToolResultContext.queryKey(
          'query_app_data',
          '{"domain":"todos","status":"pending","limit":10.0}',
        ),
      ),
    );
    expect(
      a,
      isNot(
        AiToolResultContext.queryKey(
          'query_app_data',
          '{"domain":"todos","status":"completed"}',
        ),
      ),
    );
    expect(
      AiToolResultContext.queryKey('query_app_data', '{"domain":"courses"}'),
      isNot(
        AiToolResultContext.queryKey(
          'query_app_data',
          '{"domain":"courses","status":"all"}',
        ),
      ),
    );
  });
}
