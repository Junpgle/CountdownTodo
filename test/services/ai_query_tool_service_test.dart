import 'dart:convert';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_query_tool_service.dart';
import 'package:flutter_test/flutter_test.dart';

AiChatFunctionCall query(String name, Map<String, dynamic> args) =>
    AiChatFunctionCall(id: 'call-1', name: name, arguments: jsonEncode(args));

void main() {
  late AiQueryToolService service;
  late List<FinanceTransaction> transactions;
  late List<Map<String, dynamic>> rows;
  late List<(DateTime, DateTime)> requestedRanges;

  setUp(() {
    transactions = [];
    rows = [];
    requestedRanges = [];
    service = AiQueryToolService(
      loadAppData: (_) async => rows,
      loadHabitData: (from, to, id) async {
        requestedRanges.add((from, to));
        return rows;
      },
      loadFinanceData: (from, to) async {
        requestedRanges.add((from, to));
        return transactions;
      },
      loadCategories: () async => [
        FinanceCategory(uuid: 'food', name: '餐饮'),
        FinanceCategory(uuid: 'lunch', name: '午饭', parentUuid: 'food'),
      ],
      loadPaymentMethods: () async => [],
      loadBudgets: () async => [],
    );
  });

  test('工具查询支持读取付款方式实际余额', () {
    final financeDefinition = AiQueryToolService.buildDefinitions().firstWhere(
      (tool) => (tool['function'] as Map)['name'] == 'query_finance',
    );
    final parameters =
        ((financeDefinition['function'] as Map)['parameters'] as Map);
    final view = ((parameters['properties'] as Map)['view'] as Map);

    expect(view['enum'], contains('balances'));
  });

  test('财务工具说明覆盖各视图的日期参数边界', () {
    final financeDefinition = AiQueryToolService.buildDefinitions().firstWhere(
      (tool) => (tool['function'] as Map)['name'] == 'query_finance',
    );
    final description =
        ((financeDefinition['function'] as Map)['description'] as String);

    expect(description, contains('summary、transactions和budgets必须提供日期范围'));
    expect(description, contains('transaction_id可不提供日期'));
    expect(description, contains('catalog和balances不接受日期'));
  });

  test('余额查询从快照扣除后续流水和贷款还款，无快照时保持未知', () async {
    final asOf = DateTime(2026, 10, 2, 12);
    final snapshotAt = DateTime(2026, 10, 2, 9).millisecondsSinceEpoch;
    final expenseAt = DateTime(2026, 10, 2, 10).millisecondsSinceEpoch;
    final incomeAt = DateTime(2026, 10, 2, 10, 30).millisecondsSinceEpoch;
    final repaymentAt = DateTime(2026, 10, 2, 11).millisecondsSinceEpoch;
    int? requestedSnapshotAt;
    DateTime? requestedBefore;
    Set<String>? requestedMethods;
    var categoryLoads = 0;
    final finance = AiQueryToolService(
      loadAppData: (_) async => [],
      loadHabitData: (_, _, _) async => [],
      loadFinanceData: (_, _) async => [],
      loadCategories: () async {
        categoryLoads++;
        return [];
      },
      loadPaymentMethods: () async => [
        FinancePaymentMethod(uuid: 'bank', name: '工资卡'),
        FinancePaymentMethod(uuid: 'cash', name: '现金账户'),
      ],
      loadBudgets: () async => [
        FinanceBudget(
          monthKey: '2026-10',
          paymentMethodUuid: 'bank',
          amountMinor: 100000,
          balanceSnapshotAt: snapshotAt,
        ),
      ],
      loadBalanceTransactions:
          ({
            required snapshotAt,
            required before,
            required paymentMethodUuids,
          }) async {
            requestedSnapshotAt = snapshotAt;
            requestedBefore = before;
            requestedMethods = paymentMethodUuids.toSet();
            return [
              FinanceTransaction(
                uuid: 'expense',
                amountMinor: 1200,
                paymentMethodUuid: 'bank',
                transactionDate: '2026-10-02',
                occurredAt: expenseAt,
              ),
              FinanceTransaction(
                uuid: 'income',
                type: FinanceTransactionType.income,
                amountMinor: 5000,
                paymentMethodUuid: 'bank',
                transactionDate: '2026-10-02',
                occurredAt: incomeAt,
              ),
              FinanceTransaction(
                uuid: 'loan-interest',
                amountMinor: 700,
                paymentMethodUuid: 'bank',
                transactionDate: '2026-10-02',
                occurredAt: repaymentAt,
              ),
            ];
          },
      loadPaidLoanInstallments: () async => [
        FinanceLoanInstallment(
          uuid: 'repayment',
          loanUuid: 'loan',
          installmentIndex: 1,
          dueDate: '2026-10-02',
          paymentMinor: 2000,
          principalMinor: 1300,
          interestMinor: 700,
          remainingPrincipalMinor: 8700,
          isPaid: true,
          paidAt: repaymentAt,
          paymentMethodUuid: 'bank',
          interestTransactionUuid: 'loan-interest',
        ),
      ],
      now: () => asOf,
    );

    final result = await finance.execute(
      query('query_finance', {'view': 'balances'}),
    );

    expect(result['ok'], true);
    expect(result['amount_unit'], 'CNY_minor');
    expect(categoryLoads, 0);
    expect(requestedSnapshotAt, snapshotAt);
    expect(requestedBefore, asOf);
    expect(requestedMethods, {'bank'});
    final items = result['items'] as List<Map<String, dynamic>>;
    final bank = items.firstWhere((item) => item['id'] == 'bank');
    final cash = items.firstWhere((item) => item['id'] == 'cash');
    expect(bank['balance_minor'], 101800);
    expect(bank['snapshot_available'], true);
    expect(cash['balance_minor'], isNull);
    expect(cash['balance_status'], 'unknown_no_snapshot');
  });

  test('完整月度汇总不受明细分页影响，保留退款语义和截止边界', () async {
    transactions = [
      for (var i = 0; i < 65; i++)
        FinanceTransaction(
          uuid: 'expense-${i.toString().padLeft(2, '0')}',
          amountMinor: 100,
          transactionDate: '2026-09-15',
          categoryUuid: 'lunch',
        ),
      FinanceTransaction(
        uuid: 'refund',
        type: FinanceTransactionType.refund,
        amountMinor: 200,
        transactionDate: '2026-09-30',
        categoryUuid: 'lunch',
      ),
      FinanceTransaction(
        uuid: 'income',
        type: FinanceTransactionType.income,
        amountMinor: 10000,
        transactionDate: '2026-09-01',
      ),
      FinanceTransaction(
        uuid: 'outside',
        amountMinor: 90000,
        transactionDate: '2026-10-01',
      ),
      FinanceTransaction(
        uuid: 'deleted',
        amountMinor: 90000,
        transactionDate: '2026-09-15',
        isDeleted: true,
      ),
    ];
    final result = await service.execute(
      query('query_finance', {
        'view': 'transactions',
        'start_date': '2026-09-01',
        'end_date_exclusive': '2026-10-01',
        'limit': 30,
      }),
    );
    expect(result['ok'], true);
    expect(requestedRanges.single, (DateTime(2026, 9), DateTime(2026, 10)));
    expect(result['total_count'], 67);
    expect((result['items'] as List).length, 30);
    expect(result['next_offset'], 30);
    expect(result['has_more'], true);
    expect(result['summary'], containsPair('net_expense_minor', 6300));
    expect(result['summary'], containsPair('income_minor', 10000));
    final lastPage = await service.execute(
      query('query_finance', {
        'view': 'transactions',
        'start_date': '2026-09-01',
        'end_date_exclusive': '2026-10-01',
        'offset': 60,
      }),
    );
    expect((lastPage['items'] as List).length, 7);
    expect(lastPage['has_more'], false);
    expect(lastPage['summary'], result['summary']);
  });

  test('分类查询包含子分类，目录返回真实ID且分页', () async {
    transactions = [
      FinanceTransaction(
        uuid: 'lunch-1',
        amountMinor: 1500,
        transactionDate: '2026-09-02',
        categoryUuid: 'lunch',
      ),
      FinanceTransaction(
        uuid: 'other',
        amountMinor: 3000,
        transactionDate: '2026-09-02',
      ),
    ];
    final result = await service.execute(
      query('query_finance', {
        'view': 'summary',
        'start_date': '2026-09-01',
        'end_date_exclusive': '2026-10-01',
        'category_id': 'food',
      }),
    );
    expect(result['summary'], containsPair('transaction_count', 1));
    expect(result['summary'], containsPair('expense_minor', 1500));
    final catalog = await service.execute(
      query('query_finance', {'view': 'catalog', 'limit': 1}),
    );
    expect(catalog['total_count'], 2);
    expect((catalog['items'] as List).single, containsPair('id', 'food'));
  });

  test('未来账单单独标记，实际汇总和月预算不提前计入', () async {
    final asOf = DateTime(2026, 10, 2);
    final actual = DateTime(2026, 10, 1).millisecondsSinceEpoch;
    final future = DateTime(2026, 10, 10).millisecondsSinceEpoch;
    final finance = AiQueryToolService(
      loadAppData: (_) async => [],
      loadHabitData: (_, _, _) async => [],
      loadCategories: () async => [],
      loadPaymentMethods: () async => [],
      loadBudgets: () async => [
        FinanceBudget(monthKey: '2026-10', amountMinor: 10000),
      ],
      now: () => asOf,
      loadFinanceData: (_, _) async => [
        FinanceTransaction(
          uuid: 'actual',
          amountMinor: 1000,
          transactionDate: '2026-10-01',
          occurredAt: actual,
          createdAt: actual,
        ),
        FinanceTransaction(
          uuid: 'future',
          amountMinor: 4000,
          transactionDate: '2026-10-10',
          occurredAt: future,
          createdAt: actual,
        ),
      ],
    );
    final result = await finance.execute(
      query('query_finance', {
        'view': 'transactions',
        'start_date': '2026-10-01',
        'end_date_exclusive': '2026-11-01',
      }),
    );
    expect(result['summary'], containsPair('expense_minor', 1000));
    expect(result['future_transaction_count'], 1);
    expect(result['total_count'], 2);
    expect((result['items'] as List).first, containsPair('is_future', true));
    final budget = await finance.execute(
      query('query_finance', {
        'view': 'budgets',
        'start_date': '2026-10-02',
        'end_date_exclusive': '2026-10-03',
      }),
    );
    expect((budget['items'] as List).single, containsPair('used_minor', 1000));
    expect(
      (budget['items'] as List).single,
      containsPair('remaining_minor', 9000),
    );
  });

  test('模型给出的日期和参数严格校验，错误不会被伪装为零条记录', () async {
    for (final args in [
      {
        'view': 'summary',
        'start_date': '2026-02-30',
        'end_date_exclusive': '2026-03-01',
      },
      {'view': 'summary', 'start_date': '2026-09-01'},
      {
        'view': 'summary',
        'start_date': '2026-10-01',
        'end_date_exclusive': '2026-09-01',
      },
      {
        'view': 'summary',
        'start_date': '2026-09-01',
        'end_date_exclusive': '2026-10-01',
        'limit': 51,
      },
      {'view': 'catalog', 'offset': -1},
      {'view': 'catalog', 'offset': 1.2},
      {'view': 'catalog', 'sql': 'DROP TABLE finance_transactions'},
    ]) {
      final result = await service.execute(query('query_finance', args));
      expect(result['ok'], false, reason: '$args');
      expect(result, contains('error'));
      expect(result, isNot(contains('summary')));
    }
    expect(requestedRanges, isEmpty);
    expect((await service.execute(query('delete_finance', {})))['ok'], false);
  });

  test('待办按日期和完成状态查询，保留无日期查询，排除删除记录', () async {
    rows = [
      {
        'id': 'today',
        'title': '买牛奶',
        'due_date': '2026-10-02T10:00:00',
        'is_completed': false,
      },
      {
        'id': 'done',
        'title': '读书',
        'due_date': '2026-10-02T11:00:00',
        'is_completed': true,
      },
      {
        'id': 'next',
        'title': '写报告',
        'due_date': '2026-10-03T00:00:00',
        'is_completed': false,
      },
      {
        'id': 'unscheduled',
        'title': '整理书架',
        'created_date': '2026-10-02T09:00:00',
        'is_completed': false,
      },
      {'id': 'deleted', 'title': '旧记录', 'is_deleted': true},
    ];
    final result = await service.execute(
      query('query_app_data', {
        'domain': 'todos',
        'start_date': '2026-10-02',
        'end_date_exclusive': '2026-10-03',
        'status': 'pending',
      }),
    );
    expect(result['total_count'], 1);
    expect((result['items'] as List).single, containsPair('id', 'today'));
    expect(
      (await service.execute(
        query('query_app_data', {'domain': 'todos'}),
      ))['total_count'],
      4,
    );
  });

  test('时间日志重叠范围严格排除结束于起点的记录', () async {
    rows = [
      {
        'id': 'before',
        'start_time': DateTime(2026, 10, 1, 23).millisecondsSinceEpoch,
        'end_time': DateTime(2026, 10, 2).millisecondsSinceEpoch,
      },
      {
        'id': 'overlap',
        'start_time': DateTime(2026, 10, 1, 23, 30).millisecondsSinceEpoch,
        'end_time': DateTime(2026, 10, 2, 0, 30).millisecondsSinceEpoch,
        'duration_seconds': 3600,
      },
    ];
    final result = await service.execute(
      query('query_app_data', {
        'domain': 'time_logs',
        'start_date': '2026-10-02',
        'end_date_exclusive': '2026-10-03',
      }),
    );
    expect(result['total_count'], 1);
    expect((result['items'] as List).single, containsPair('id', 'overlap'));
    expect(result['summary'], containsPair('duration_seconds', 1800));
  });

  test('习惯范围直接交给数据层，读取异常有明确错误', () async {
    rows = [
      {
        'id': 'habit-1',
        'name': '喝水',
        'progress': {'met_periods': 20},
      },
    ];
    final result = await service.execute(
      query('query_habits', {
        'start_date': '2026-09-01',
        'end_date_exclusive': '2026-10-01',
      }),
    );
    expect(result['total_count'], 1);
    expect(requestedRanges.single, (DateTime(2026, 9), DateTime(2026, 10)));
    final failing = AiQueryToolService(
      loadAppData: (_) async => throw StateError('busy'),
      loadHabitData: (_, _, _) async => [],
    );
    expect(
      (await failing.execute(
        query('query_app_data', {'domain': 'todos'}),
      ))['ok'],
      false,
    );
  });

  test('统计不返回明细，列表默认10条且详情必须按ID读取', () async {
    rows = [
      for (var i = 0; i < 80; i++)
        {
          'id': 'todo-$i',
          'title': '任务$i',
          'is_completed': i < 15,
          'remark': '完整备注',
          'group_id': i < 5 ? 'study' : 'work',
        },
    ];
    final summary = await service.execute(
      query('query_app_data', {
        'domain': 'todos',
        'view': 'summary',
        'status': 'pending',
      }),
    );
    expect(summary['total_count'], 65);
    expect(summary['summary'], containsPair('count', 65));
    expect(summary, isNot(contains('items')));
    final list = await service.execute(
      query('query_app_data', {'domain': 'todos'}),
    );
    expect(list['items'], hasLength(10));
    expect(list['next_offset'], 10);
    expect((list['items'] as List).first, isNot(contains('remark')));
    final detail = await service.execute(
      query('query_app_data', {
        'domain': 'todos',
        'view': 'detail',
        'id': 'todo-12',
      }),
    );
    expect((detail['items'] as List).single['remark'], '完整备注');
    expect(
      (await service.execute(
        query('query_app_data', {'domain': 'todos', 'view': 'detail'}),
      ))['ok'],
      false,
    );
  });

  test('分类、无日期与记录状态在App筛选，无需拉全量由模型计算', () async {
    rows = [
      {'id': 'a', 'title': '学习', 'group_id': 'study', 'is_completed': false},
      {'id': 'b', 'title': '工作', 'group_id': 'work', 'due_date': '2026-10-02'},
      {'id': 'c', 'title': '复习', 'group_id': 'study', 'due_date': '2026-10-03'},
    ];
    final result = await service.execute(
      query('query_app_data', {
        'domain': 'todos',
        'group_id': 'study',
        'date_status': 'unscheduled',
      }),
    );
    expect(result['total_count'], 1);
    expect((result['items'] as List).single['id'], 'a');
    rows = [
      {'id': 'done', 'status': 'completed', 'duration_seconds': 1200},
      {'id': 'stopped', 'status': 'interrupted', 'duration_seconds': 30},
    ];
    final focus = await service.execute(
      query('query_app_data', {
        'domain': 'pomodoro_records',
        'record_status': 'completed',
        'view': 'summary',
      }),
    );
    expect(focus['summary'], containsPair('duration_seconds', 1200));
    expect(focus['total_count'], 1);
    expect(focus, isNot(contains('items')));
  });

  test('最大支出只返回一笔，商户排行直接汇总退款后的净支出', () async {
    transactions = [
      FinanceTransaction(
        uuid: 'a',
        transactionDate: '2026-09-01',
        amountMinor: 8000,
        merchant: '超市',
      ),
      FinanceTransaction(
        uuid: 'b',
        transactionDate: '2026-09-02',
        amountMinor: 7000,
        merchant: '书店',
      ),
      FinanceTransaction(
        uuid: 'refund',
        transactionDate: '2026-09-03',
        amountMinor: 2000,
        merchant: '超市',
        type: FinanceTransactionType.refund,
      ),
      FinanceTransaction(
        uuid: 'salary',
        transactionDate: '2026-09-04',
        amountMinor: 999999,
        merchant: '公司',
        type: FinanceTransactionType.income,
      ),
    ];
    final args = {
      'start_date': '2026-09-01',
      'end_date_exclusive': '2026-10-01',
    };
    final maximum = await service.execute(
      query('query_finance', {
        ...args,
        'view': 'transactions',
        'type': 'expense',
        'sort_by': 'amount_desc',
        'limit': 1,
      }),
    );
    expect((maximum['items'] as List).single['id'], 'a');
    final ranking = await service.execute(
      query('query_finance', {
        ...args,
        'view': 'summary',
        'group_by': 'merchant',
        'limit': 1,
      }),
    );
    expect(ranking, isNot(contains('items')));
    final merchants = (ranking['summary'] as Map)['expense_by_merchant'] as Map;
    expect((merchants['items'] as List).single, {
      'merchant': '书店',
      'net_expense_minor': 7000,
    });
    expect(merchants['total_count'], 2);
    expect(merchants['next_offset'], 1);
    expect(ranking['summary'], containsPair('net_expense_minor', 13000));
  });

  test('习惯列表只返回进度，规则仅在指定目标详情中返回', () async {
    rows = [
      for (var i = 0; i < 15; i++)
        {
          'id': 'habit-$i',
          'name': '习惯$i',
          'rules': [
            {'target_value': 8},
          ],
          'progress': {
            'met_periods': 2,
            'planned_periods': 3,
            'record_count': 5,
          },
        },
    ];
    final range = {
      'start_date': '2026-09-01',
      'end_date_exclusive': '2026-10-01',
    };
    final list = await service.execute(query('query_habits', range));
    expect(list['items'], hasLength(10));
    expect((list['items'] as List).first, isNot(contains('rules')));
    final aggregate = await service.execute(
      query('query_habits', {...range, 'view': 'summary'}),
    );
    expect(aggregate, isNot(contains('items')));
    expect(aggregate['summary'], containsPair('record_count', 75));
    final detail = await service.execute(
      query('query_habits', {
        ...range,
        'view': 'detail',
        'habit_id': 'habit-1',
      }),
    );
    expect((detail['items'] as List).single, contains('rules'));
    expect((detail['items'] as List).single['id'], 'habit-1');
  });
}
