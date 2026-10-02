import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_text_parser.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_native_tool_call_parser.dart';
import 'package:countdown_todo/services/ai_native_tool_definition_builder.dart';
import 'package:countdown_todo/services/ai_query_tool_service.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:countdown_todo/services/ai_tool_chat_runner.dart';
import 'package:flutter_test/flutter_test.dart';

// Offline model-side simulations: each prompt has an explicitly authored tool
// plan and independent expected facts. Only the data providers are fixtures;
// query filtering, paging, round trips and confirmation parsing are production.
// This deliberately does not evaluate an external model's choice of tools.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/services/ai_function_calling_simulation_cases.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
  final results = <Map<String, dynamic>>[];
  const outputPath = String.fromEnvironment('CDT_AI_SIMULATION_OUTPUT');
  tearDownAll(() {
    if (outputPath.isEmpty) return;
    results.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    File(outputPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'reference_time': fixture['reference_time'],
        'timezone': fixture['timezone'],
        'evidence': fixture['evidence'],
        'passed': results.where((r) => r['passed'] == true).length,
        'total': cases.length,
        'cases': results,
      }),
    );
  });

  assert(cases.length == 100);
  assert(cases.map((c) => c['prompt']).toSet().length == 100);
  for (final scenario in cases) {
    test(
      '${scenario['id'].toString().padLeft(3, '0')} ${scenario['prompt']}',
      () async {
        final model = _SimulatedModel(scenario);
        final result = <String, dynamic>{
          'id': scenario['id'],
          'group': scenario['group'],
          'prompt': scenario['prompt'],
          if (scenario['history'] != null) 'history': scenario['history'],
          if (scenario['injected_fault'] != null)
            'injected_fault': scenario['injected_fault'],
          'expected': scenario['expected'],
          if (scenario['absent'] != null) 'absent': scenario['absent'],
          'calls': model.trace,
          'model_requests': model.requests,
        };
        results.add(result);
        try {
          final prompt = scenario['prompt'] as String;
          final previous =
              (scenario['history'] as List?)?.firstOrNull as String? ?? '';
          final tools = [
            ...AiQueryToolService.buildDefinitions(),
            ...AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
              prompt,
              previousUserMessage: previous,
            ),
          ];
          final service = _fixtureService(fixture);
          final snapshots = <Map<String, dynamic>>[
            {
              'role': 'system',
              'content': AiTodoContextBuilder.buildLeanSystemPrompt(
                customPrompt: '',
                promptEnabled: false,
                nativeToolCalls: true,
                queryTools: true,
                now: DateTime(2026, 10, 2, 12),
              ),
            },
            {'role': 'system', 'content': AiQueryToolService.systemPrompt},
            for (final (index, text)
                in ((scenario['history'] as List?) ?? []).indexed)
              {'role': index.isEven ? 'user' : 'assistant', 'content': text},
            {'role': 'user', 'content': prompt},
          ];
          final chunks = await AiToolChatRunner.run(
            messages: snapshots,
            tools: tools,
            streamRound: model.streamRound,
            executeRead: service.execute,
          ).toList();
          final calls = chunks.expand((chunk) => chunk.toolCalls).toList();
          final toolResults = {
            for (final chunk in chunks) ...chunk.toolResults,
          };
          result['app_results'] = toolResults;
          for (final call in calls.where((c) => c.name.startsWith('query_'))) {
            expect(
              toolResults.containsKey(call.id),
              true,
              reason: '每次查询的真实结果必须透过流式事件传回对话',
            );
            expect(
              model.receivedIds,
              contains(call.id),
              reason: '每次查询结果必须以匹配的tool_call_id回到下一轮模型',
            );
          }
          final text = chunks.map((chunk) => chunk.content).join();
          final persisted = ChatMessage.fromJson(
            ChatMessage(
              role: ChatRole.assistant,
              content: text,
              nativeToolCalls: [
                for (final call in calls)
                  ChatNativeToolCall(
                    id: call.id,
                    name: call.name,
                    arguments: call.arguments,
                    result: toolResults[call.id],
                  ),
              ],
            ).toJson(),
          );
          for (final record
              in persisted.nativeToolCalls ?? <ChatNativeToolCall>[]) {
            expect(
              record.result,
              toolResults[record.id],
              reason: '实际返回JSON必须保留到对话历史，供调用卡片展示',
            );
          }
          final compatible = AiNativeToolCallParser.appendToAssistantText(
            text,
            calls,
            allowedToolNames: AiNativeToolDefinitionBuilder.allowedToolNames(
              tools,
            ),
            allowedCdtActionNames:
                AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
            allowedFinanceActionNames:
                AiNativeToolDefinitionBuilder.allowedFinanceActionNames(tools),
          );
          final drafts = FinanceTextParser.extractAssistantDrafts(compatible);
          final actions = AiActionParser.extractTodoActions(
            compatible,
            originalText: prompt,
          );
          final financeActions = FinanceTextParser.extractAssistantActions(
            compatible,
          );
          model.observed['parsed'] = {
            'todo_actions': actions.length,
            'finance_drafts': drafts.length,
            'first_draft_amount_minor': drafts.firstOrNull?.amountMinor,
            'finance_actions': financeActions.length,
            'saved': false,
            'cdt_actions': [for (final action in actions) action.toJson()],
            'drafts': [for (final draft in drafts) draft.toJson()],
            'finance_action_details': [
              for (final action in financeActions) action.toJson(),
            ],
          };
          result['reply'] = text;
          result['parsed'] = model.observed['parsed'];
          result['calculations'] = model.observed['calc'];
          expect(text, isNotEmpty);
          expect(
            model.cursor,
            (scenario['steps'] as List).length,
            reason: '计划中的工具必须全部执行，包括按真实返回ID进行后续查询',
          );
          for (final entry in (scenario['expected'] as Map).entries) {
            expect(
              _at(model.observed, entry.key as String),
              entry.value,
              reason: '${scenario['prompt']} → ${entry.key}',
            );
          }
          for (final path
              in (scenario['absent'] as List? ?? []).cast<String>()) {
            final separator = path.lastIndexOf('.');
            expect(
              _at(model.observed, path.substring(0, separator)),
              isNot(contains(path.substring(separator + 1))),
              reason: '汇总问题不应返回明细：$path',
            );
          }
          if (scenario['behavior'] == 'clarification') expect(calls, isEmpty);
          // Check the exact proposed object and payload, not only that a card exists.
          if (scenario['id'] == 66) {
            expect(actions.single.todoId, 'todo-english');
            expect(actions.single.startTime, '2026-10-03 14:00');
          } else if (scenario['id'] == 95) {
            expect(drafts.single.categoryUuid, 'lunch');
            expect(drafts.single.paymentMethodUuid, 'wechat');
          } else if (scenario['id'] == 96) {
            expect(financeActions.single.transactionId, 'sep-supermarket');
            expect(financeActions.single.amountMinor, 7500);
          } else if (scenario['id'] == 97) {
            expect(actions.single.todoId, 'todo-report');
          }
          result['passed'] = true;
        } catch (error) {
          result['passed'] = false;
          result['error'] = error.toString();
          rethrow;
        }
      },
    );
  }
}

dynamic _at(dynamic value, String path) {
  for (final key in path.split('.')) {
    if (key == r'$length' && value is List) {
      value = value.length;
    } else if (value is Map && value.containsKey(key)) {
      value = value[key];
    } else if (value is List && int.tryParse(key) != null) {
      value = value[int.parse(key)];
    } else {
      throw StateError('工具返回中缺少 $path ($key)');
    }
  }
  return value;
}

dynamic _resolve(dynamic value, Map<String, dynamic> observed) {
  if (value is String && value.startsWith(r'$')) {
    return _at(observed, value.substring(1));
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key: _resolve(entry.value, observed),
    };
  }
  if (value is List) {
    return [for (final item in value) _resolve(item, observed)];
  }
  return value;
}

class _SimulatedModel {
  _SimulatedModel(this.scenario);
  final Map<String, dynamic> scenario;
  final observed = <String, dynamic>{};
  final trace = <Map<String, dynamic>>[];
  final requests = <Map<String, dynamic>>[];
  final receivedIds = <String>{};
  int cursor = 0;
  Map<String, dynamic>? pendingPage;

  Stream<AiChatStreamChunk> streamRound(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async* {
    requests.add({
      'request_chars': jsonEncode({'messages': messages, 'tools': tools})
          .length,
      'tool_result_chars': messages
          .where((m) => m['role'] == 'tool')
          .fold<int>(0, (sum, m) => sum + (m['content'] as String).length),
    });
    for (final message in messages.where((m) => m['role'] == 'tool')) {
      final id = message['tool_call_id'] as String;
      if (!receivedIds.add(id)) continue;
      final call = trace.singleWhere((t) => t['id'] == id);
      final returned =
          jsonDecode(message['content'] as String) as Map<String, dynamic>;
      call['result'] = returned;
      observed[call['label'] as String] = returned;
      final step = call['step'] as Map;
      if (step['collect'] != null) {
        final collected = observed.putIfAbsent(
          step['collect'] as String,
          () => <dynamic>[],
        ) as List;
        collected.addAll(returned['items'] as List? ?? []);
      }
      if (step['paginate'] == true && returned['has_more'] == true) {
        expect(
          returned['next_offset'],
          greaterThan((call['arguments'] as Map)['offset'] ?? 0),
        );
        pendingPage = {
          ...step,
          'label': '${step['label']}_next',
          'arguments': {
            ...call['arguments'] as Map,
            'offset': returned['next_offset'],
          },
        };
      }
    }
    final steps = scenario['steps'] as List;
    if (pendingPage == null && cursor == steps.length) {
      _calculate();
      yield AiChatStreamChunk(content: _reply(), finishReason: 'stop');
      return;
    }
    final step =
        pendingPage ?? Map<String, dynamic>.from(steps[cursor++] as Map);
    pendingPage = null;
    final args = Map<String, dynamic>.from(
      _resolve(step['arguments'], observed) as Map,
    );
    final name = step['name'] as String;
    final definition = tools
        .where((t) => (t['function'] as Map)['name'] == name)
        .firstOrNull;
    expect(definition, isNotNull, reason: '当前提示词/轮次实际开放的函数必须包含$name');
    // Case 14 is intentionally invalid so that the App must return an error
    // which the simulated model then uses to correct the next query.
    if (!(scenario['id'] == 14 && step['label'] == 'q1')) {
      _validate(
        args,
        (definition!['function'] as Map)['parameters'] as Map,
        name,
      );
    }
    final id = 'sim-${scenario['id']}-${trace.length + 1}';
    trace.add({
      'id': id,
      'name': name,
      'arguments': args,
      'label': step['label'],
      'step': step,
    });
    observed[step['label'] as String] = {'arguments': args};
    if (name.startsWith('propose_')) _calculate();
    final call = AiChatFunctionCall(
      id: id,
      name: name,
      arguments: jsonEncode(args),
    );
    yield AiChatStreamChunk(
      toolCallDeltas: [
        AiChatFunctionCallDelta(
          index: 0,
          id: id,
          name: name,
          arguments: call.arguments,
        ),
      ],
    );
    yield AiChatStreamChunk(
      content: name.startsWith('propose_') ? _reply() : '',
      toolCalls: [call],
      finishReason: 'tool_calls',
    );
  }

  String _reply() => (scenario['reply_template'] as String).replaceAllMapped(
    RegExp(r'\{([^{}]+)\}'),
    (match) {
      final parts = match[1]!.split(':');
      final value = _at(observed, parts.first);
      if (parts.length == 1) return value.toString();
      if (parts.last == 'datetime') {
        return (value as String).replaceAll('T', ' ').substring(0, 16);
      }
      final number = (value as num) / (parts.last == 'money' ? 100 : 60);
      return parts.last == 'money'
          ? number.toStringAsFixed(2)
          : number == number.roundToDouble()
          ? number.toInt().toString()
          : number.toStringAsFixed(2);
    },
  );

  void _calculate() {
    final calc = observed.putIfAbsent('calc', () => <String, dynamic>{}) as Map;
    calc['query_pages'] = trace
        .where((c) => c['name'].toString().startsWith('query_'))
        .length;
    List<Map> rows(String key) => (observed[key] as List).cast<Map>();
    int completedSeconds(String key) =>
        rows(key)
            .where((r) => r['status'] == 'completed')
            .fold(0, (sum, r) => sum + (r['duration_seconds'] as num).toInt());
    for (final computation in scenario['calculations'] as List? ?? []) {
      switch (computation) {
        case 'finance_compare':
          calc['change_minor'] =
              (_at(observed, 'q2.summary.net_expense_minor') as int) -
              (_at(observed, 'q3.summary.net_expense_minor') as int);
          calc['decrease_minor'] = -(calc['change_minor'] as int);
        case 'finance_ranking':
          final bills = rows('bills')
              .where((r) => r['is_future'] != true && r['type'] != 'income')
              .toList();
          final expenses = bills.where((r) => r['type'] == 'expense').toList()
            ..sort(
              (a, b) => (b['amount_minor'] as int).compareTo(
                a['amount_minor'] as int,
              ),
            );
          calc['max_expense_minor'] = expenses.first['amount_minor'];
          calc['max_expense_merchant'] = expenses.first['merchant'];
          final merchants = <String, int>{};
          for (final bill in bills) {
            final merchant = bill['merchant'] as String;
            merchants[merchant] =
                (merchants[merchant] ?? 0) +
                (bill['amount_minor'] as int) *
                    (bill['type'] == 'refund' ? -1 : 1);
          }
          final ranked = merchants.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          calc['top_merchant'] = ranked.first.key;
          calc['top_merchant_net_minor'] = ranked.first.value;
        case 'unscheduled':
          calc['unscheduled_count'] = rows('todos')
              .where((r) => r['due_date'] == null && r['created_date'] == null)
              .length;
        case 'study_group':
          final study = rows('todos')
              .where((r) => r['group_id'] == _at(observed, 'q1.items.0.id'))
              .toList();
          calc['study_count'] = study.length;
          calc['study_titles'] = study.map((r) => r['title']).join('、');
        case 'completed_plans':
          final completed = rows('plans')
              .where((r) => r['status'] == 'finished')
              .toList();
          calc['completed_plans'] = completed.length;
          calc['completed_plan_titles'] = completed
              .map((r) => r['title'])
              .join('、');
        case 'overlap':
          var count = 0;
          var seconds = 0;
          for (final plan in rows('plans')) {
            for (final schedule in rows('schedules')) {
              final starts = [
                DateTime.parse(plan['start_time'] as String),
                DateTime.parse(schedule['start_time'] as String),
              ]..sort();
              final ends = [
                DateTime.parse(plan['end_time'] as String),
                DateTime.parse(schedule['end_time'] as String),
              ]..sort();
              final overlap = ends.first.difference(starts.last).inSeconds;
              if (overlap > 0) {
                count++;
                seconds += overlap;
              }
            }
          }
          calc['overlap_count'] = count;
          calc['overlap_seconds'] = seconds;
        case 'completed_focus':
          calc['completed_focus_seconds'] = completedSeconds('focus');
        case 'completed_focus_summary':
          calc['completed_focus_seconds'] = _at(
            observed,
            'q1.summary.duration_seconds',
          );
        case 'merchant_summary':
          calc['top_merchant'] = _at(
            observed,
            'q1.summary.expense_by_merchant.items.0.merchant',
          );
          calc['top_merchant_net_minor'] = _at(
            observed,
            'q1.summary.expense_by_merchant.items.0.net_expense_minor',
          );
        case 'focus_compare_summary':
          calc['focus_change_seconds'] =
              (_at(observed, 'q1.summary.duration_seconds') as num) -
              (_at(observed, 'q2.summary.duration_seconds') as num);
        case 'focus_compare':
          calc['focus_change_seconds'] =
              completedSeconds('focus_today') -
              completedSeconds('focus_yesterday');
        case 'habit_rate':
          calc['habit_rate'] =
              ((_at(observed, 'q1.items.0.progress.met_periods') as num) /
                      (_at(observed, 'q1.items.0.progress.planned_periods')
                          as num) *
                      100)
                  .toStringAsFixed(2);
        case 'unmet_habits':
          final unmet = rows('habits')
              .where((r) => (r['progress'] as Map)['met_periods'] == 0)
              .toList();
          calc['unmet_habit_count'] = unmet.length;
          calc['unmet_habit_name'] = unmet.first['name'];
        default:
          throw StateError('未知计算$computation');
      }
    }
  }
}

void _validate(dynamic value, Map schema, String path) {
  final type = schema['type'];
  expect(
    switch (type) {
      'object' => value is Map,
      'array' => value is List,
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num,
      'boolean' => value is bool,
      _ => true,
    },
    true,
    reason: '$path 类型须遵守实际schema',
  );
  if (schema['enum'] is List) {
    expect(schema['enum'] as List, contains(value), reason: path);
  }
  if (value is Map) {
    final properties = schema['properties'] as Map? ?? {};
    for (final key in schema['required'] as List? ?? []) {
      expect(value.containsKey(key), true, reason: '$path 缺少$key');
    }
    for (final entry in value.entries) {
      if (schema['additionalProperties'] == false) {
        expect(
          properties.containsKey(entry.key),
          true,
          reason: '$path.${entry.key}未在schema声明',
        );
      }
      if (properties[entry.key] is Map) {
        _validate(
          entry.value,
          properties[entry.key] as Map,
          '$path.${entry.key}',
        );
      }
    }
  } else if (value is List && schema['items'] is Map) {
    for (final item in value) {
      _validate(item, schema['items'] as Map, '$path[]');
    }
  }
}

AiQueryToolService _fixtureService(Map<String, dynamic> fixture) {
  final finance = [
    for (final row in fixture['finance'] as List)
      FinanceTransaction(
        uuid: row['id'] as String,
        type: FinanceTransactionType.values.byName(row['type'] as String),
        amountMinor: row['amount_minor'] as int,
        transactionDate: row['date'] as String,
        occurredAt: DateTime.parse(
          '${row['date']}T${(row['hour'] as int).toString().padLeft(2, '0')}:00:00+08:00',
        ).millisecondsSinceEpoch,
        timezoneOffsetMinutes: 480,
        categoryUuid: row['category_id'] as String?,
        paymentMethodUuid: row['payment_method_id'] as String?,
        merchant: row['merchant'] as String,
        isDeleted: row['is_deleted'] as bool,
      ),
  ];
  return AiQueryToolService(
    now: () => DateTime.parse(fixture['reference_time'] as String).toLocal(),
    loadFinanceData: (from, to) async => finance
        .where(
          (row) =>
              !row.isDeleted &&
              row.transactionDate.compareTo(dateKey(from)) >= 0 &&
              row.transactionDate.compareTo(dateKey(to)) < 0,
        )
        .toList(),
    loadFinanceTransaction: (id) async =>
        finance.where((r) => r.uuid == id).firstOrNull,
    loadCategories: () async => [
      for (final row in fixture['categories'] as List)
        FinanceCategory(
          uuid: row['id'] as String,
          name: row['name'] as String,
          type: FinanceCategoryType.values.byName(row['type'] as String),
          parentUuid: row['parent_id'] as String?,
        ),
    ],
    loadPaymentMethods: () async => [
      for (final row in fixture['payment_methods'] as List)
        FinancePaymentMethod(
          uuid: row['id'] as String,
          name: row['name'] as String,
        ),
    ],
    loadBudgets: () async => [
      for (final row in fixture['budgets'] as List)
        FinanceBudget(
          uuid: row['id'] as String,
          monthKey: row['month'] as String,
          amountMinor: row['amount_minor'] as int,
          categoryUuid: row['category_id'] as String?,
        ),
    ],
    loadAppData: (domain) async => [
      for (final row in fixture['app_data'][domain] as List)
        Map<String, dynamic>.from(row as Map),
    ],
    loadHabitData: (from, to, id) async {
      final key = '${dateKey(from)}/${dateKey(to)}';
      final list = (fixture['habit_ranges'][key] as List).cast<Map>();
      return [
        for (final row in list.where((r) => id == null || r['id'] == id))
          Map<String, dynamic>.from(row),
      ];
    },
  );
}
