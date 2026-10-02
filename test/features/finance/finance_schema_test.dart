@TestOn('vm')
library;

import 'dart:convert';

import 'package:countdown_todo/features/finance/services/ai_usage_cost_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/services/finance_sync_service.dart';
import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _balanceSyncResponse({bool supportsBalances = false}) => {
      'sync_capabilities': {
        'finance_v1': 1,
        if (supportsBalances) 'finance_account_balances_v1': 1,
      },
      'server_finance_categories': <Map<String, dynamic>>[],
      'server_finance_payment_methods': <Map<String, dynamic>>[],
      'server_finance_transactions': <Map<String, dynamic>>[],
      'server_finance_loans': <Map<String, dynamic>>[],
      'server_finance_loan_installments': <Map<String, dynamic>>[],
      'server_finance_budgets': <Map<String, dynamic>>[],
      'server_finance_recurring_rules': <Map<String, dynamic>>[],
      'server_finance_entry_templates': <Map<String, dynamic>>[],
      'finance_acknowledged_changes': <Map<String, dynamic>>[],
      'new_finance_sync_time': DateTime.now().millisecondsSinceEpoch,
    };

void main() {
  sqfliteFfiInit();

  group('余额同步与还款账户', () {
    late Database db;
    const user = 'balance-sync-test';
    const account = 'finance-system-payment-cash';

    setUp(() async {
      SharedPreferences.setMockInitialValues({'current_login_user': user});
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      FinanceStorage.databaseOverride = db;
      await DatabaseHelper.ensureFinanceSchema(db);
      await FinanceStorage.ensureReady();
    });
    tearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    test('余额流水查询只读取有快照账户，支持大量账户并跳过已删除流水', () async {
      final snapshotAt = DateTime(2026, 9, 1).millisecondsSinceEpoch;
      for (final transaction in [
        FinanceTransaction(
          uuid: 'balance-query-card-a',
          amountMinor: 100,
          paymentMethodUuid: 'card-a',
          transactionDate: '2026-09-05',
        ),
        FinanceTransaction(
          uuid: 'balance-query-card-b',
          amountMinor: 200,
          paymentMethodUuid: 'card-b',
          transactionDate: '2026-09-06',
        ),
        FinanceTransaction(
          uuid: 'balance-query-untracked-card',
          amountMinor: 300,
          paymentMethodUuid: 'card-without-snapshot',
          transactionDate: '2026-09-07',
        ),
        FinanceTransaction(
          uuid: 'balance-query-no-card',
          amountMinor: 400,
          transactionDate: '2026-09-08',
        ),
        FinanceTransaction(
          uuid: 'balance-query-deleted',
          amountMinor: 500,
          paymentMethodUuid: 'card-a',
          transactionDate: '2026-09-09',
          isDeleted: true,
        ),
      ]) {
        await db.insert('finance_transactions', transaction.toMap());
      }

      final trackedMethods = {
        'card-a',
        'card-b',
        for (var index = 0; index < 400; index++) 'unused-card-$index',
      };
      final transactions = await FinanceStorage.getBalanceTransactions(
        snapshotAt: snapshotAt,
        before: DateTime(2026, 10, 1),
        paymentMethodUuids: trackedMethods,
      );

      expect(
        transactions.map((transaction) => transaction.uuid).toSet(),
        {'balance-query-card-a', 'balance-query-card-b'},
      );
      final indexes = await db.rawQuery(
        'PRAGMA index_list(finance_transactions)',
      );
      expect(
        indexes.any(
          (index) => index['name'] == 'idx_finance_transactions_balance',
        ),
        isTrue,
      );
      expect(
        await FinanceStorage.getBalanceTransactions(
          snapshotAt: snapshotAt,
          before: DateTime(2026, 10, 1),
          paymentMethodUuids: const {},
        ),
        isEmpty,
      );
    });

    test('本地账单保存拒绝超过总期数的分期期次', () async {
      final transaction = FinanceTransaction(
        uuid: 'local-out-of-range-installment-index',
        amountMinor: 600,
        transactionDate: '2026-09-20',
        installmentGroupUuid: 'local-out-of-range-installment-group',
        installmentIndex: 3,
        installmentCount: 2,
        installmentTotalMinor: 1200,
      );

      await expectLater(
        FinanceStorage.saveTransaction(transaction),
        throwsArgumentError,
      );
      expect(await FinanceStorage.getTransaction(transaction.uuid), isNull);
    });

    for (final source in ['backup', 'remote']) {
      test('$source 拒绝超过期数范围的分期记录', () async {
        final transaction = FinanceTransaction(
          uuid: 'out-of-range-$source-installment-index',
          amountMinor: 600,
          transactionDate: '2026-09-20',
          installmentGroupUuid: 'out-of-range-$source-installment-group',
          installmentIndex: 3,
          installmentCount: 2,
          installmentTotalMinor: 1200,
        );
        final legacyInstallmentWithoutTotal = FinanceTransaction(
          uuid: 'valid-$source-installment-without-total',
          amountMinor: 600,
          transactionDate: '2026-09-20',
          installmentGroupUuid: 'valid-$source-installment-group',
          installmentIndex: 2,
          installmentCount: 2,
        );
        final transactions = [
          transaction.toMap(),
          legacyInstallmentWithoutTotal.toMap(),
        ];

        if (source == 'backup') {
          await FinanceStorage.importBundle({
            'transactions': transactions,
          });
        } else {
          await FinanceStorage.mergeRemoteBundle({
            'transactions': transactions,
          });
        }

        expect(await FinanceStorage.getTransaction(transaction.uuid), isNull);
        expect(
          (await FinanceStorage.getTransaction(
            legacyInstallmentWithoutTotal.uuid,
          ))!.isInstallment,
          isTrue,
        );
      });

      test('$source 拒绝负数预算和余额快照', () async {
        final snapshotAt = DateTime(2026, 10, 1).millisecondsSinceEpoch;
        final budgets = [
          FinanceBudget(
            uuid: 'negative-$source-category-budget',
            monthKey: '2026-10',
            categoryUuid: 'expense-category',
            amountMinor: -1200,
          ).toMap(),
          FinanceBudget(
            uuid: 'negative-$source-balance-snapshot',
            monthKey: '2026-10',
            paymentMethodUuid: 'payment-card',
            amountMinor: -5000,
            balanceSnapshotAt: snapshotAt,
          ).toMap(),
        ];

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle({
            'budgets': budgets,
          });
          expect(result['skipped'], 2);
        } else {
          expect(
            await FinanceStorage.mergeRemoteBundle({'budgets': budgets}),
            0,
          );
        }

        expect(
          await FinanceStorage.getBudgets(includeDeleted: true),
          isEmpty,
        );
      });

      test('$source 拒绝负数周期模板贷款金额和超范围利率', () async {
        final recurringRule = FinanceRecurringRule(
          uuid: 'negative-$source-recurring-rule',
          name: '负数周期账单',
          amountMinor: -100,
          startDate: '2026-09-01',
        );
        final template = FinanceEntryTemplate(
          uuid: 'negative-$source-template',
          name: '负数模板',
          amountMinor: -100,
        );
        final loan = FinanceLoan(
          uuid: 'negative-$source-loan',
          name: '负数贷款',
          principalMinor: -100,
          termMonths: 1,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        final outOfRangeRateLoan = FinanceLoan(
          uuid: 'out-of-range-$source-loan-rate',
          name: '超范围利率贷款',
          principalMinor: 10000,
          annualInterestRateBps:
              FinanceLoanCalculator.maxAnnualInterestRateBps + 1,
          termMonths: 1,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        final installment = FinanceLoanInstallment(
          uuid: 'negative-$source-installment',
          loanUuid: loan.uuid,
          installmentIndex: 1,
          dueDate: '2026-10-01',
          paymentMinor: -100,
          principalMinor: -100,
          interestMinor: 0,
          remainingPrincipalMinor: 0,
        );
        final bundle = {
          'recurring_rules': [recurringRule.toMap()],
          'templates': [template.toMap()],
          'loans': [loan.toMap(), outOfRangeRateLoan.toMap()],
          'loan_installments': [installment.toMap()],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['skipped'], 5);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 0);
        }

        expect(
          await FinanceStorage.getRecurringRules(includeDeleted: true),
          isEmpty,
        );
        expect(
          await FinanceStorage.getTemplates(includeDeleted: true),
          isEmpty,
        );
        expect(await FinanceStorage.getLoans(includeDeleted: true), isEmpty);
        expect(
          await FinanceStorage.getLoanInstallments(
            loan.uuid,
            includeDeleted: true,
          ),
          isEmpty,
        );
      });

      test('$source 拒绝无效的账户余额快照时间', () async {
        final invalidSnapshotTimes = <num>[-1, 0, 9000000000000000, 1000.5];
        final budgets = <Map<String, dynamic>>[];
        for (var index = 0; index < invalidSnapshotTimes.length; index++) {
          final paymentMethodUuid = 'invalid-snapshot-method-$source-$index';
          await db.insert(
            'finance_payment_methods',
            FinancePaymentMethod(
              uuid: paymentMethodUuid,
              name: '快照时间测试账户 $index',
            ).toMap(),
          );
          budgets.add(
            FinanceBudget(
              uuid: 'invalid-snapshot-budget-$source-$index',
              monthKey: '2026-10',
              paymentMethodUuid: paymentMethodUuid,
              amountMinor: 1000,
              balanceSnapshotAt: 1000,
            ).toMap()..['balance_snapshot_at'] = invalidSnapshotTimes[index],
          );
        }

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle({'budgets': budgets});
          expect(result['skipped'], invalidSnapshotTimes.length);
        } else {
          expect(
            await FinanceStorage.mergeRemoteBundle({'budgets': budgets}),
            0,
          );
        }
        expect(
          await FinanceStorage.getBudgets(includeDeleted: true),
          isEmpty,
        );
      });

      test('$source 拒绝未来或月份不匹配的账户余额快照', () async {
        final now = DateTime.now();
        final futureAt = now.add(const Duration(days: 1));
        final oldAt = now.subtract(const Duration(days: 40));
        final scenarios = [
          (
            suffix: 'future',
            monthKey: financeMonthKey(futureAt),
            snapshotAt: futureAt,
          ),
          (
            suffix: 'wrong-month',
            monthKey: financeMonthKey(now),
            snapshotAt: oldAt,
          ),
        ];
        final budgets = <Map<String, dynamic>>[];
        for (final scenario in scenarios) {
          final paymentMethodUuid =
              'invalid-balance-snapshot-method-$source-${scenario.suffix}';
          await db.insert(
            'finance_payment_methods',
            FinancePaymentMethod(
              uuid: paymentMethodUuid,
              name: '无效余额快照账户 ${scenario.suffix}',
            ).toMap(),
          );
          budgets.add(
            FinanceBudget(
              uuid: 'invalid-balance-snapshot-$source-${scenario.suffix}',
              monthKey: scenario.monthKey,
              paymentMethodUuid: paymentMethodUuid,
              amountMinor: 1000,
              balanceSnapshotAt: scenario.snapshotAt.millisecondsSinceEpoch,
            ).toMap(),
          );
        }

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle({
            'budgets': budgets,
          });
          expect(result['imported'], 0);
          expect(result['skipped'], 2);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle({'budgets': budgets}), 0);
        }
        expect(
          await FinanceStorage.getBudgets(includeDeleted: true),
          isEmpty,
        );
      });
    }

    test('本地预算拒绝收入分类和不存在的关联项', () async {
      await db.insert(
        'finance_categories',
        FinanceCategory(
          uuid: 'income-budget-category',
          name: '工资',
          type: FinanceCategoryType.income,
        ).toMap(),
      );

      await expectLater(
        FinanceStorage.saveBudget(
          FinanceBudget(
            uuid: 'income-category-budget',
            monthKey: '2026-10',
            categoryUuid: 'income-budget-category',
            amountMinor: 1000,
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        FinanceStorage.saveBudget(
          FinanceBudget(
            uuid: 'missing-category-budget',
            monthKey: '2026-10',
            categoryUuid: 'missing-expense-category',
            amountMinor: 1000,
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        FinanceStorage.saveBudget(
          FinanceBudget(
            uuid: 'missing-method-budget',
            monthKey: '2026-10',
            paymentMethodUuid: 'missing-payment-method',
            amountMinor: 1000,
          ),
        ),
        throwsArgumentError,
      );
      expect(await FinanceStorage.getBudgets(includeDeleted: true), isEmpty);
    });

    for (final source in ['backup', 'remote']) {
      test('$source 拒绝错误分类类型和孤立预算', () async {
        await db.insert(
          'finance_categories',
          FinanceCategory(
            uuid: 'income-$source-budget-category',
            name: '工资',
            type: FinanceCategoryType.income,
          ).toMap(),
        );
        final budgets = [
          FinanceBudget(
            uuid: 'income-$source-category-budget',
            monthKey: '2026-10',
            categoryUuid: 'income-$source-budget-category',
            amountMinor: 1000,
          ).toMap(),
          FinanceBudget(
            uuid: 'orphan-$source-category-budget',
            monthKey: '2026-10',
            categoryUuid: 'missing-$source-category',
            amountMinor: 2000,
          ).toMap(),
          FinanceBudget(
            uuid: 'orphan-$source-payment-budget',
            monthKey: '2026-10',
            paymentMethodUuid: 'missing-$source-payment-method',
            amountMinor: 3000,
          ).toMap(),
        ];

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle({
            'budgets': budgets,
          });
          expect(result['skipped'], 3);
        } else {
          expect(
            await FinanceStorage.mergeRemoteBundle({'budgets': budgets}),
            0,
          );
        }
        expect(
          await FinanceStorage.getBudgets(includeDeleted: true),
          isEmpty,
        );
      });
    }

    for (final source in ['backup', 'remote']) {
      test('$source 拒绝被归一化的无效分类类型', () async {
        final numericType = FinanceCategory(
          uuid: 'invalid-$source-numeric-category-type',
          name: '数值越界分类',
        ).toMap()
          ..['type'] = 99;
        final unknownType = FinanceCategory(
          uuid: 'invalid-$source-string-category-type',
          name: '未知类型分类',
        ).toMap()
          ..['type'] = 'unknown';
        final bundle = {
          'categories': [numericType, unknownType],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['skipped'], 2);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 0);
        }

        final categories = await FinanceStorage.getCategories(
          includeArchived: true,
        );
        expect(
          categories.map((category) => category.uuid),
          isNot(contains('invalid-$source-numeric-category-type')),
        );
        expect(
          categories.map((category) => category.uuid),
          isNot(contains('invalid-$source-string-category-type')),
        );
      });
    }

    for (final source in ['backup', 'remote']) {
      test('$source 忽略缺少标识的分类和付款方式', () async {
        final category = FinanceCategory(
          uuid: 'missing-$source-category-uuid',
          name: '无标识分类',
        ).toMap()
          ..remove('uuid');
        final paymentMethod = FinancePaymentMethod(
          uuid: 'missing-$source-payment-uuid',
          name: '无标识账户',
        ).toMap()
          ..remove('uuid');
        final bundle = {
          'categories': [category],
          'payment_methods': [paymentMethod],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['skipped'], 2);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 0);
        }

        expect(
          (await FinanceStorage.getCategories(includeArchived: true))
              .where((item) => item.name == '无标识分类'),
          isEmpty,
        );
        expect(
          (await FinanceStorage.getPaymentMethods(includeArchived: true))
              .where((item) => item.name == '无标识账户'),
          isEmpty,
        );
      });
    }

    test('备份导入统计格式错误的财务数据行', () async {
      final result = await FinanceStorage.importBundle({
        'categories': [null, <dynamic, dynamic>{1: '非字符串键'}],
        'payment_methods': '错误的数据段',
      });

      expect(result, {'imported': 0, 'skipped': 3, 'updated': 0});
    });

    for (final source in ['backup', 'remote']) {
      test('$source 拒绝无法安全表示的交易时间字段', () async {
        final transactions = [
          FinanceTransaction(
            uuid: 'out-of-range-occurrence-time-$source',
            amountMinor: 500,
            transactionDate: '2026-09-20',
            occurredAt: 9000000000000000,
          ).toMap(),
          FinanceTransaction(
            uuid: 'out-of-range-created-time-$source',
            amountMinor: 500,
            transactionDate: '2026-09-20',
            createdAt: 9000000000000000,
          ).toMap(),
          FinanceTransaction(
            uuid: 'out-of-range-updated-time-$source',
            amountMinor: 500,
            transactionDate: '2026-09-20',
            updatedAt: 9000000000000000,
          ).toMap(),
          FinanceTransaction(
            uuid: 'out-of-range-timezone-offset-$source',
            amountMinor: 500,
            transactionDate: '2026-09-20',
            timezoneOffsetMinutes: 100000,
          ).toMap(),
        ];

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle({
            'transactions': transactions,
          });
          expect(result['skipped'], 4);
        } else {
          expect(
            await FinanceStorage.mergeRemoteBundle({
              'transactions': transactions,
            }),
            0,
          );
        }
        for (final map in transactions) {
          expect(
            await FinanceStorage.getTransaction(map['uuid'] as String),
            isNull,
          );
        }
      });

      test('$source 拒绝会被归一化的无效交易类型', () async {
        final unknownType = FinanceTransaction(
          uuid: 'unknown-$source-transaction-type',
          amountMinor: 500,
          transactionDate: '2026-09-20',
        ).toMap()
          ..['type'] = 'unknown';
        final outOfRangeType = FinanceTransaction(
          uuid: 'out-of-range-$source-transaction-type',
          amountMinor: 500,
          transactionDate: '2026-09-20',
        ).toMap()
          ..['type'] = 99;
        final transactions = [unknownType, outOfRangeType];

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle({
            'transactions': transactions,
          });
          expect(result['skipped'], 2);
        } else {
          expect(
            await FinanceStorage.mergeRemoteBundle({
              'transactions': transactions,
            }),
            0,
          );
        }
        expect(
          await FinanceStorage.getTransaction(unknownType['uuid'] as String),
          isNull,
        );
        expect(
          await FinanceStorage.getTransaction(
            outOfRangeType['uuid'] as String,
          ),
          isNull,
        );
      });

      test('$source 拒绝会被归一化的周期、模板和贷款枚举', () async {
        final recurringRules = [
          FinanceRecurringRule(
            uuid: 'invalid-$source-frequency-name',
            name: '错误频率名称',
            amountMinor: 100,
            startDate: '2026-09-01',
          ).toMap()
            ..['frequency'] = 'unknown',
          FinanceRecurringRule(
            uuid: 'invalid-$source-frequency-number',
            name: '错误频率数字',
            amountMinor: 100,
            startDate: '2026-09-01',
          ).toMap()
            ..['frequency'] = 99,
          FinanceRecurringRule(
            uuid: 'invalid-$source-recurring-type',
            name: '错误周期类型',
            amountMinor: 100,
            startDate: '2026-09-01',
          ).toMap()
            ..['type'] = 'unknown',
        ];
        final templates = [
          FinanceEntryTemplate(
            uuid: 'invalid-$source-template-type-name',
            name: '错误模板类型',
            amountMinor: 100,
          ).toMap()
            ..['type'] = 'unknown',
          FinanceEntryTemplate(
            uuid: 'invalid-$source-template-type-number',
            name: '错误模板类型数字',
            amountMinor: 100,
          ).toMap()
            ..['type'] = 99,
        ];
        final loans = [
          FinanceLoan(
            uuid: 'invalid-$source-loan-method-name',
            name: '错误还款方式名称',
            principalMinor: 1000,
            termMonths: 1,
            startDate: '2026-09-01',
            repaymentDay: 1,
          ).toMap()
            ..['repayment_method'] = 'unknown',
          FinanceLoan(
            uuid: 'invalid-$source-loan-method-number',
            name: '错误还款方式数字',
            principalMinor: 1000,
            termMonths: 1,
            startDate: '2026-09-01',
            repaymentDay: 1,
          ).toMap()
            ..['repayment_method'] = 99,
          FinanceLoan(
            uuid: 'invalid-$source-loan-method-string-number',
            name: '错误还款方式数字字符串',
            principalMinor: 1000,
            termMonths: 1,
            startDate: '2026-09-01',
            repaymentDay: 1,
          ).toMap()
            ..['repayment_method'] = '1',
        ];

        final bundle = {
          'recurring_rules': recurringRules,
          'templates': templates,
          'loans': loans,
        };
        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['skipped'], 8);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 0);
        }
        expect(
          await FinanceStorage.getRecurringRules(includeDeleted: true),
          isEmpty,
        );
        expect(
          await FinanceStorage.getTemplates(includeDeleted: true),
          isEmpty,
        );
        expect(await FinanceStorage.getLoans(includeDeleted: true), isEmpty);
      });

      test('$source 拒绝会导致周期游标计算溢出的时间戳', () async {
        final rule = FinanceRecurringRule(
          uuid: 'out-of-range-$source-recurring-timestamp',
          name: '异常周期时间',
          amountMinor: 100,
          startDate: '2026-09-01',
          updatedAt: 9000000000000000,
          lastGeneratedPeriod: 'invalid-period',
        );

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle({
            'recurring_rules': [rule.toMap()],
          });
          expect(result['skipped'], 1);
        } else {
          expect(
            await FinanceStorage.mergeRemoteBundle({
              'recurring_rules': [rule.toMap()],
            }),
            0,
          );
        }
        expect(
          await FinanceStorage.getRecurringRules(includeDeleted: true),
          isEmpty,
        );
      });

      test('$source 拒绝超出日期时间范围的贷款还款时刻', () async {
        final loan = FinanceLoan(
          uuid: 'loan-with-invalid-paid-at-$source',
          name: '异常还款时刻贷款',
          principalMinor: 1000,
          termMonths: 1,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        final installment = FinanceLoanInstallment(
          uuid: 'invalid-paid-at-installment-$source',
          loanUuid: loan.uuid,
          installmentIndex: 1,
          dueDate: '2026-10-01',
          paymentMinor: 1000,
          principalMinor: 1000,
          interestMinor: 0,
          remainingPrincipalMinor: 0,
          isPaid: true,
          paidAt: 9000000000000000,
          paymentMethodUuid: 'finance-system-payment-cash',
        );
        final bundle = {
          'loans': [loan.toMap()],
          'loan_installments': [installment.toMap()],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['imported'], 1);
          expect(result['skipped'], 1);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 1);
        }
        expect(
          await FinanceStorage.getLoanInstallments(
            loan.uuid,
            includeDeleted: true,
          ),
          isEmpty,
        );
      });

      test('$source 拒绝未来时间标记为已还的贷款期次', () async {
        final loan = FinanceLoan(
          uuid: 'future-paid-loan-$source',
          name: '未来还款贷款',
          principalMinor: 1000,
          termMonths: 1,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        final installment = FinanceLoanInstallment(
          uuid: 'future-paid-installment-$source',
          loanUuid: loan.uuid,
          installmentIndex: 1,
          dueDate: '2026-10-01',
          paymentMinor: 1000,
          principalMinor: 1000,
          interestMinor: 0,
          remainingPrincipalMinor: 0,
          isPaid: true,
          paidAt: DateTime.now()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
          paymentMethodUuid: 'finance-system-payment-cash',
        );
        final bundle = {
          'loans': [loan.toMap()],
          'loan_installments': [installment.toMap()],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['imported'], 1);
          expect(result['skipped'], 1);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 1);
        }
        expect(
          await FinanceStorage.getLoanInstallments(
            loan.uuid,
            includeDeleted: true,
          ),
          isEmpty,
        );
      });

      test('$source 拒绝与贷款计划不一致的还款期次', () async {
        final loan = FinanceLoan(
          uuid: 'mismatched-schedule-loan-$source',
          name: '还款计划一致性贷款',
          principalMinor: 1000,
          termMonths: 1,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        final installment = FinanceLoanInstallment(
          uuid: 'mismatched-schedule-installment-$source',
          loanUuid: loan.uuid,
          installmentIndex: 1,
          dueDate: '2026-10-01',
          paymentMinor: 800,
          principalMinor: 800,
          interestMinor: 0,
          remainingPrincipalMinor: 200,
        );
        final bundle = {
          'loans': [loan.toMap()],
          'loan_installments': [installment.toMap()],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['imported'], 1);
          expect(result['skipped'], 1);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 1);
        }
        expect(
          await FinanceStorage.getLoanInstallments(
            loan.uuid,
            includeDeleted: true,
          ),
          isEmpty,
        );
      });

      test('$source 拒绝超过贷款期限的还款计划', () async {
        final loan = FinanceLoan(
          uuid: 'short-loan-$source',
          name: '一个月贷款',
          principalMinor: 1000,
          termMonths: 1,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        final installment = FinanceLoanInstallment(
          uuid: 'out-of-term-installment-$source',
          loanUuid: loan.uuid,
          installmentIndex: 2,
          dueDate: '2026-11-01',
          paymentMinor: 1000,
          principalMinor: 1000,
          interestMinor: 0,
          remainingPrincipalMinor: 0,
        );
        final bundle = {
          'loans': [loan.toMap()],
          'loan_installments': [installment.toMap()],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['imported'], 1);
          expect(result['skipped'], 1);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 1);
        }
        expect(
          await FinanceStorage.getLoanInstallments(
            loan.uuid,
            includeDeleted: true,
          ),
          isEmpty,
        );
      });

      test('$source 相同期次只保留版本较新的还款计划', () async {
        final loan = FinanceLoan(
          uuid: 'duplicate-installment-loan-$source',
          name: '重复期次贷款',
          principalMinor: 1000,
          termMonths: 2,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        final older = FinanceLoanInstallment(
          uuid: 'duplicate-installment-a-$source',
          loanUuid: loan.uuid,
          installmentIndex: 1,
          dueDate: '2026-10-01',
          paymentMinor: 500,
          principalMinor: 400,
          interestMinor: 100,
          remainingPrincipalMinor: 600,
          version: 1,
          updatedAt: 100,
        );
        final newer = FinanceLoanInstallment(
          uuid: 'duplicate-installment-b-$source',
          loanUuid: loan.uuid,
          installmentIndex: 1,
          dueDate: '2026-10-01',
          paymentMinor: 500,
          principalMinor: 500,
          interestMinor: 0,
          remainingPrincipalMinor: 500,
          version: 2,
          updatedAt: 200,
        );
        final bundle = {
          'loans': [loan.toMap()],
          'loan_installments': [older.toMap(), newer.toMap()],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['imported'], 2);
          expect(result['skipped'], 1);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 2);
        }
        final installments = await FinanceStorage.getLoanInstallments(
          loan.uuid,
        );
        expect(installments, hasLength(1));
        expect(installments.single.uuid, newer.uuid);
      });

      test('$source 不改写已还期次对应的贷款条款和金额', () async {
        final loan = FinanceLoan(
          uuid: 'paid-loan-terms-$source',
          name: '已有还款的贷款',
          principalMinor: 10000,
          annualInterestRateBps: 1200,
          termMonths: 2,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        await FinanceStorage.saveLoan(loan);
        final installments = await FinanceStorage.getLoanInstallments(loan.uuid);
        final paidInstallment = installments.first;
        await FinanceStorage.setLoanInstallmentPaid(
          paidInstallment.uuid,
          true,
          paymentMethodUuid: 'finance-system-payment-cash',
        );
        final currentLoan = (await FinanceStorage.getLoan(loan.uuid))!;
        final currentInstallment =
            (await FinanceStorage.getLoanInstallment(paidInstallment.uuid))!;
        final changedLoan = FinanceLoan.fromMap(currentLoan.toMap())
          ..annualInterestRateBps = 0
          ..version = currentLoan.version + 1
          ..updatedAt = currentLoan.updatedAt + 100;
        final changedAllocation = FinanceLoanCalculator.generate(
          principalMinor: changedLoan.principalMinor,
          annualInterestRateBps: changedLoan.annualInterestRateBps,
          termMonths: changedLoan.termMonths,
          startDate: dateFromKey(changedLoan.startDate),
          repaymentDay: changedLoan.repaymentDay,
          repaymentMethod: changedLoan.repaymentMethod,
        ).first;
        final changedInstallment = FinanceLoanInstallment.fromMap(
          currentInstallment.toMap(),
        )
          ..paymentMinor = changedAllocation.paymentMinor
          ..principalMinor = changedAllocation.principalMinor
          ..interestMinor = changedAllocation.interestMinor
          ..remainingPrincipalMinor = changedAllocation.remainingPrincipalMinor
          ..version = currentInstallment.version + 1
          ..updatedAt = currentInstallment.updatedAt + 100;
        final bundle = {
          'loans': [changedLoan.toMap()],
          'loan_installments': [changedInstallment.toMap()],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['updated'], 0);
          expect(result['skipped'], 2);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 0);
        }
        final storedLoan = (await FinanceStorage.getLoan(loan.uuid))!;
        final storedInstallment =
            (await FinanceStorage.getLoanInstallment(paidInstallment.uuid))!;
        expect(storedLoan.annualInterestRateBps, 1200);
        expect(storedInstallment.paymentMinor, paidInstallment.paymentMinor);
        expect(storedInstallment.principalMinor, paidInstallment.principalMinor);
        expect(storedInstallment.interestMinor, paidInstallment.interestMinor);
      });

      test('$source 拒绝缺少账期和还款期次的记录', () async {
        final transaction = FinanceTransaction(
          uuid: 'missing-transaction-date-$source',
          amountMinor: 100,
          transactionDate: '2026-09-01',
        ).toMap()
          ..remove('transaction_date');
        final budget = FinanceBudget(
          uuid: 'missing-budget-month-$source',
          monthKey: '2026-09',
          amountMinor: 500,
        ).toMap()
          ..remove('month_key');
        final recurringRule = FinanceRecurringRule(
          uuid: 'missing-recurring-start-$source',
          name: '缺少开始日的周期规则',
          amountMinor: 100,
          startDate: '2026-09-01',
        ).toMap()
          ..remove('start_date');
        final loans = [
          FinanceLoan(
            uuid: 'missing-loan-start-$source',
            name: '缺少开始日贷款',
            principalMinor: 1000,
            termMonths: 1,
            startDate: '2026-09-01',
            repaymentDay: 1,
          ).toMap()
            ..remove('start_date'),
          FinanceLoan(
            uuid: 'missing-loan-term-$source',
            name: '缺少期限贷款',
            principalMinor: 1000,
            termMonths: 2,
            startDate: '2026-09-01',
            repaymentDay: 1,
          ).toMap()
            ..remove('term_months'),
          FinanceLoan(
            uuid: 'missing-loan-repayment-day-$source',
            name: '缺少还款日贷款',
            principalMinor: 1000,
            termMonths: 2,
            startDate: '2026-09-01',
            repaymentDay: 1,
          ).toMap()
            ..remove('repayment_day'),
        ];
        final parentLoan = FinanceLoan(
          uuid: 'valid-parent-loan-$source',
          name: '有效父贷款',
          principalMinor: 1000,
          termMonths: 2,
          startDate: '2026-09-01',
          repaymentDay: 1,
        );
        final installments = [
          FinanceLoanInstallment(
            uuid: 'missing-installment-date-$source',
            loanUuid: parentLoan.uuid,
            installmentIndex: 1,
            dueDate: '2026-10-01',
            paymentMinor: 1000,
            principalMinor: 1000,
            interestMinor: 0,
            remainingPrincipalMinor: 0,
          ).toMap()
            ..remove('due_date'),
          FinanceLoanInstallment(
            uuid: 'missing-installment-index-$source',
            loanUuid: parentLoan.uuid,
            installmentIndex: 2,
            dueDate: '2026-11-01',
            paymentMinor: 500,
            principalMinor: 500,
            interestMinor: 0,
            remainingPrincipalMinor: 500,
          ).toMap()
            ..remove('installment_index'),
        ];
        final bundle = {
          'transactions': [transaction],
          'budgets': [budget],
          'recurring_rules': [recurringRule],
          'loans': [...loans, parentLoan.toMap()],
          'loan_installments': installments,
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['imported'], 1);
          expect(result['skipped'], 8);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 1);
        }
        expect(await FinanceStorage.getTransactions(), isEmpty);
        expect(await FinanceStorage.getBudgets(includeDeleted: true), isEmpty);
        expect(await FinanceStorage.getRecurringRules(includeDeleted: true), isEmpty);
        expect(
          await FinanceStorage.getLoans(includeDeleted: true),
          hasLength(1),
        );
        expect(
          await FinanceStorage.getLoanInstallments(
            parentLoan.uuid,
            includeDeleted: true,
          ),
          isEmpty,
        );
      });

      test('$source 拒绝缺少名称的记账记录', () async {
        final category = FinanceCategory(
          uuid: 'missing-name-category-$source',
          name: '残缺分类',
        ).toMap()
          ..remove('name');
        final paymentMethod = FinancePaymentMethod(
          uuid: 'missing-name-method-$source',
          name: '残缺账户',
        ).toMap()
          ..remove('name');
        final recurringRule = FinanceRecurringRule(
          uuid: 'missing-name-rule-$source',
          name: '残缺周期规则',
          amountMinor: 100,
          startDate: '2026-09-01',
        ).toMap()
          ..remove('name');
        final template = FinanceEntryTemplate(
          uuid: 'missing-name-template-$source',
          name: '残缺模板',
          amountMinor: 100,
        ).toMap()
          ..remove('name');
        final loan = FinanceLoan(
          uuid: 'missing-name-loan-$source',
          name: '残缺贷款',
          principalMinor: 1000,
          termMonths: 1,
          startDate: '2026-09-01',
          repaymentDay: 1,
        ).toMap()
          ..remove('name');
        final bundle = {
          'categories': [category],
          'payment_methods': [paymentMethod],
          'recurring_rules': [recurringRule],
          'templates': [template],
          'loans': [loan],
        };

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle(bundle);
          expect(result['imported'], 0);
          expect(result['skipped'], 5);
        } else {
          expect(await FinanceStorage.mergeRemoteBundle(bundle), 0);
        }
        expect(
          (await FinanceStorage.getCategories(includeArchived: true))
              .where((item) => item.uuid == category['uuid']),
          isEmpty,
        );
        expect(
          (await FinanceStorage.getPaymentMethods(includeArchived: true))
              .where((item) => item.uuid == paymentMethod['uuid']),
          isEmpty,
        );
        expect(
          await FinanceStorage.getRecurringRules(includeDeleted: true),
          isEmpty,
        );
        expect(
          await FinanceStorage.getTemplates(includeDeleted: true),
          isEmpty,
        );
        expect(await FinanceStorage.getLoans(includeDeleted: true), isEmpty);
      });

      test('$source 拒绝无效的快捷模板使用次数', () async {
        final templates = [
          FinanceEntryTemplate(
            uuid: 'invalid-template-negative-use-count-$source',
            name: '负数使用次数',
            amountMinor: 100,
            useCount: -3,
          ).toMap(),
          FinanceEntryTemplate(
            uuid: 'invalid-template-overflow-use-count-$source',
            name: '溢出使用次数',
            amountMinor: 100,
            useCount: 0x80000000,
          ).toMap(),
        ];

        if (source == 'backup') {
          final result = await FinanceStorage.importBundle({
            'templates': templates,
          });
          expect(result['imported'], 0);
          expect(result['skipped'], 2);
        } else {
          expect(
            await FinanceStorage.mergeRemoteBundle({'templates': templates}),
            0,
          );
        }
        expect(await FinanceStorage.getTemplates(includeDeleted: true), isEmpty);
      });
    }

    test('本地保存拒绝超范围的快捷模板使用次数', () async {
      for (final useCount in [-3, 0x80000000]) {
        await expectLater(
          FinanceStorage.saveTemplate(
            FinanceEntryTemplate(
              name: '超范围使用次数',
              amountMinor: 100,
              useCount: useCount,
            ),
          ),
          throwsArgumentError,
        );
      }
    });

    test('本地已有的超期活跃还款期次不显示、不影响余额且不能还款', () async {
      final loan = FinanceLoan(
        uuid: 'existing-short-loan',
        name: '一个月贷款',
        principalMinor: 1000,
        termMonths: 1,
        startDate: '2026-09-01',
        repaymentDay: 1,
      );
      final installment = FinanceLoanInstallment(
        uuid: 'existing-out-of-term-installment',
        loanUuid: loan.uuid,
        installmentIndex: 2,
        dueDate: '2026-11-01',
        paymentMinor: 1000,
        principalMinor: 1000,
        interestMinor: 0,
        remainingPrincipalMinor: 0,
        isPaid: true,
        paidAt: DateTime.now().millisecondsSinceEpoch,
        paymentMethodUuid: 'finance-system-payment-cash',
      );
      await db.insert('finance_loans', loan.toMap());
      await db.insert('finance_loan_installments', installment.toMap());

      expect(await FinanceStorage.getLoanInstallments(loan.uuid), isEmpty);
      expect(await FinanceStorage.getPaidLoanInstallments(), isEmpty);
      await expectLater(
        FinanceStorage.setLoanInstallmentPaid(installment.uuid, true),
        throwsStateError,
      );
    });

    test('本地保存、服务端合并和备份导入拒绝不安全的大额账单', () async {
      final unsafeTransaction = FinanceTransaction(
        uuid: 'unsafe-large-transaction',
        amountMinor: maxFinanceAmountMinor + 1,
        transactionDate: '2026-09-01',
      );
      await expectLater(
        FinanceStorage.saveTransaction(unsafeTransaction),
        throwsArgumentError,
      );
      expect(
        await FinanceStorage.mergeRemoteBundle({
          'transactions': [unsafeTransaction.toMap()],
        }),
        0,
      );
      final negativeTransaction = FinanceTransaction(
        uuid: 'negative-remote-transaction',
        amountMinor: -100,
        transactionDate: '2026-09-01',
      );
      expect(
        await FinanceStorage.mergeRemoteBundle({
          'transactions': [negativeTransaction.toMap()],
        }),
        0,
      );
      final transactionImport = await FinanceStorage.importBundle({
        'transactions': [
          unsafeTransaction.toMap(),
          negativeTransaction.toMap(),
        ],
      });
      expect(transactionImport['imported'], 0);
      expect(transactionImport['skipped'], 2);
      expect(
        await FinanceStorage.getTransaction(unsafeTransaction.uuid),
        isNull,
      );

      final unsafeBalance = FinanceBudget(
        uuid: 'unsafe-large-balance',
        monthKey: '2026-09',
        paymentMethodUuid: account,
        amountMinor: maxFinanceAmountMinor + 1,
      );
      await expectLater(
        FinanceStorage.saveBudget(unsafeBalance),
        throwsArgumentError,
      );
      final balanceImport = await FinanceStorage.importBundle({
        'budgets': [unsafeBalance.toMap()],
      });
      expect(balanceImport['imported'], 0);
      expect(balanceImport['skipped'], 1);
      expect(await FinanceStorage.getBudget(unsafeBalance.uuid), isNull);
    });

    test('V56本地余额升级时只排队一次，保留零余额及快照时刻', () async {
      final snapshotAt = DateTime(2026, 9, 20).millisecondsSinceEpoch;
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'legacy-balance',
          monthKey: '2026-09',
          amountMinor: 0,
          paymentMethodUuid: account,
          balanceSnapshotAt: snapshotAt,
        ).toMap(),
      );
      await db.execute(
        'ALTER TABLE finance_loan_installments DROP COLUMN payment_method_uuid',
      );
      await DatabaseHelper.ensureFinanceSchema(db);
      final migrated = (await db.query('finance_budgets')).single;
      expect(migrated['pending_sync'], 1);
      expect(migrated['amount_minor'], 0);
      expect(migrated['balance_snapshot_at'], snapshotAt);
      await db.update('finance_budgets', {'pending_sync': 0});
      await DatabaseHelper.ensureFinanceSchema(db);
      expect((await db.query('finance_budgets')).single['pending_sync'], 0);
    });

    test('零余额使用专用同步字段，旧服务不确认，新服务明确确认后保留快照', () async {
      final snapshotAt = DateTime(2026, 9, 20).millisecondsSinceEpoch;
      await FinanceStorage.saveBudget(
        FinanceBudget(
          uuid: 'zero-balance',
          monthKey: '2026-09',
          amountMinor: 0,
          paymentMethodUuid: account,
          balanceSnapshotAt: snapshotAt,
        ),
        balanceSnapshotAt: snapshotAt,
      );
      final first = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      expect(first.payload['finance_budgets_changes'], isEmpty);
      expect(
        (first.payload['finance_balance_snapshots_changes'] as List)
            .single['uuid'],
        FinanceBudget.stableUuid('2026-09', null, paymentMethodUuid: account),
      );
      await FinanceSyncService.finish(
        request: first,
        response: _balanceSyncResponse(),
        supported: true,
      );
      expect((await db.query('finance_budgets')).single['pending_sync'], 1);
      expect(await FinanceSyncService.balanceSyncSupport(), false);

      final second = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      final pending =
          (second.payload['finance_balance_snapshots_changes'] as List).single
              as Map;
      final ackAt = (pending['updated_at'] as int) + 100;
      final response = _balanceSyncResponse(supportsBalances: true);
      response['finance_acknowledged_changes'] = [
        {
          'table': 'budgets',
          'uuid': pending['uuid'],
          'version': pending['version'],
          'updated_at': ackAt,
        },
      ];
      final result = await FinanceSyncService.finish(
        request: second,
        response: response,
        supported: true,
      );
      expect(result.acknowledgedChangeCount, 1);
      final acknowledged = (await db.query('finance_budgets')).single;
      expect(acknowledged['pending_sync'], 0);
      expect(acknowledged['updated_at'], ackAt);
      expect(acknowledged['balance_snapshot_at'], snapshotAt);
      expect(await FinanceSyncService.balanceSyncSupport(), true);

      // Capability discovery requests a full pull, including older balances
      // whose timestamps are already below the ordinary finance cursor.
      final bootstrap = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      expect(bootstrap.fullSync, true);
      await FinanceSyncService.finish(
        request: bootstrap,
        response: _balanceSyncResponse(supportsBalances: true),
        supported: true,
      );
      expect(
        (await FinanceSyncService.prepare(
          username: user,
          forceFullSync: false,
        )).fullSync,
        false,
      );

      final other = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        await DatabaseHelper.ensureFinanceSchema(other);
        FinanceStorage.databaseOverride = other;
        expect(
          await FinanceStorage.mergeRemoteBundle({
            'budgets': [acknowledged],
          }),
          1,
        );
        final downloaded = (await other.query('finance_budgets')).single;
        expect(downloaded['amount_minor'], 0);
        expect(downloaded['payment_method_uuid'], account);
        expect(downloaded['balance_snapshot_at'], snapshotAt);
        expect(downloaded['pending_sync'], 0);
      } finally {
        FinanceStorage.databaseOverride = db;
        await other.close();
      }
    });

    test('无息还款记录账户，删除保留已发生扣款、撤销才移除', () async {
      final loan = FinanceLoan(
        uuid: 'zero-interest-loan',
        name: '无息借款',
        principalMinor: 10000,
        annualInterestRateBps: 0,
        termMonths: 2,
        startDate: '2026-09-01',
        repaymentDay: 1,
      );
      await FinanceStorage.saveLoan(loan);
      final installment = (await FinanceStorage.getLoanInstallments(loan.uuid))
          .first;
      final paidAt = DateTime.now().subtract(const Duration(hours: 1));
      await FinanceStorage.setLoanInstallmentPaid(
        installment.uuid,
        true,
        paymentMethodUuid: account,
        paidAt: paidAt,
      );
      expect(
        (await FinanceStorage.getPaidLoanInstallments()).single.paymentMinor,
        5000,
      );
      expect(await db.query('finance_transactions'), isEmpty);
      final request = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      expect(
        (request.payload['finance_loan_account_changes'] as List)
            .single['uuid'],
        installment.uuid,
      );
      final local = (await FinanceStorage.getLoanInstallment(
        installment.uuid,
      ))!;
      final response = _balanceSyncResponse();
      final legacy = local.toMap()..remove('payment_method_uuid');
      legacy['version'] = local.version + 10;
      legacy['updated_at'] = local.updatedAt + 100;
      response['server_finance_loan_installments'] = [legacy];
      await FinanceSyncService.finish(
        request: request,
        response: response,
        supported: true,
      );
      expect(
        (await FinanceStorage.getLoanInstallment(installment.uuid))!
            .paymentMethodUuid,
        account,
      );
      expect(
        (await db.query(
          'finance_loan_installments',
          where: 'uuid = ?',
          whereArgs: [installment.uuid],
        )).single['pending_sync'],
        1,
      );
      await FinanceStorage.deleteLoan(loan.uuid);
      expect(
        (await FinanceStorage.getPaidLoanInstallments()).single.paymentMinor,
        5000,
      );
      final deletedBundle = await FinanceStorage.getExportBundle();
      for (final restoreFromCloud in [true, false]) {
        final other = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        try {
          await DatabaseHelper.ensureFinanceSchema(other);
          FinanceStorage.databaseOverride = other;
          if (restoreFromCloud) {
            await FinanceStorage.mergeRemoteBundle(deletedBundle);
          } else {
            await FinanceStorage.importBundle(deletedBundle);
          }
          expect(
            (await FinanceStorage.getPaidLoanInstallments())
                .single
                .paymentMinor,
            5000,
            reason: restoreFromCloud ? '云端恢复已删除贷款的扣款' : '备份恢复已删除贷款的扣款',
          );
          expect(
            (await FinanceStorage.getLoan(
              loan.uuid,
              includeDeleted: true,
            ))!.isDeleted,
            true,
          );
        } finally {
          FinanceStorage.databaseOverride = db;
          await other.close();
        }
      }
      await FinanceStorage.restoreLoan(loan.uuid);
      expect(
        (await FinanceStorage.getPaidLoanInstallments()).single.paidAt,
        paidAt.millisecondsSinceEpoch,
      );
      await FinanceStorage.setLoanInstallmentPaid(installment.uuid, false);
      expect(await FinanceStorage.getPaidLoanInstallments(), isEmpty);
      final undone = (await FinanceStorage.getLoanInstallment(
        installment.uuid,
      ))!;
      expect(undone.paymentMethodUuid, isNull);
      expect(undone.paidAt, isNull);
    });

    test('利息已有退款时撤销还款回滚，先删除退款后可正常撤销', () async {
      final loan = FinanceLoan(
        uuid: 'refunded-interest-loan',
        name: '带息借款',
        principalMinor: 10000,
        annualInterestRateBps: 1200,
        termMonths: 1,
        startDate: '2026-08-01',
        repaymentDay: 1,
      );
      await FinanceStorage.saveLoan(loan);
      final installment = (await FinanceStorage.getLoanInstallments(loan.uuid))
          .single;
      await FinanceStorage.setLoanInstallmentPaid(
        installment.uuid,
        true,
        paymentMethodUuid: account,
        paidAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final paid = (await FinanceStorage.getLoanInstallment(installment.uuid))!;
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'refunded-interest',
          type: FinanceTransactionType.refund,
          amountMinor: paid.interestMinor,
          paymentMethodUuid: account,
          transactionDate: dateKey(DateTime.now()),
          relatedTransactionUuid: paid.interestTransactionUuid,
        ),
      );
      await expectLater(
        FinanceStorage.setLoanInstallmentPaid(paid.uuid, false),
        throwsA(isA<StateError>()),
      );
      final preserved = (await FinanceStorage.getLoanInstallment(paid.uuid))!;
      expect(preserved.toMap(), paid.toMap());
      expect(
        (await FinanceStorage.getTransaction(paid.interestTransactionUuid!))!
            .isDeleted,
        false,
      );
      expect(
        (await FinanceStorage.getTransaction('refunded-interest'))!.isDeleted,
        false,
      );
      await FinanceStorage.deleteTransaction('refunded-interest');
      await FinanceStorage.setLoanInstallmentPaid(paid.uuid, false);
      expect(
        (await FinanceStorage.getLoanInstallment(paid.uuid))!.isPaid,
        false,
      );
      expect(
        (await FinanceStorage.getTransaction(paid.interestTransactionUuid!))!
            .isDeleted,
        true,
      );
      expect(await FinanceStorage.getPaidLoanInstallments(), isEmpty);
    });

    test('云同步修改周期账单规则后报告提醒需要重排', () async {
      final rule = FinanceRecurringRule(
        uuid: 'remote-reminder-rule',
        name: '旧周期账单名称',
        amountMinor: 1200,
        startDate: '2026-01-01',
      );
      await FinanceStorage.saveRecurringRule(rule);
      final request = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      final remoteRule = FinanceRecurringRule.fromMap(rule.toMap())
        ..name = '同步后的周期账单名称'
        ..version = rule.version + 1
        ..updatedAt = rule.updatedAt + 10000
        ..pendingSync = false;
      final response = _balanceSyncResponse(supportsBalances: true)
        ..['server_finance_recurring_rules'] = [remoteRule.toMap()];

      final result = await FinanceSyncService.finish(
        request: request,
        response: response,
        supported: true,
      );

      expect(result.recurringRulesChanged, true);
      expect(
        (await FinanceStorage.getRecurringRule(rule.uuid))!.name,
        '同步后的周期账单名称',
      );

      final unchangedRequest = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      final unchangedResult = await FinanceSyncService.finish(
        request: unchangedRequest,
        response: response,
        supported: true,
      );
      expect(unchangedResult.recurringRulesChanged, false);
    });

    test('同步同批原单和退款墓碑完整应用，两种返回顺序都不漏删除', () async {
      for (final reverse in [false, true]) {
        final suffix = reverse ? 'reversed' : 'ordered';
        final original = FinanceTransaction(
          uuid: 'deleted-original-$suffix',
          amountMinor: 10000,
          transactionDate: '2026-09-01',
          createdAt: 10,
          updatedAt: 10,
        );
        final refund = FinanceTransaction(
          uuid: 'deleted-refund-$suffix',
          type: FinanceTransactionType.refund,
          amountMinor: 1000,
          transactionDate: '2026-09-02',
          relatedTransactionUuid: original.uuid,
          createdAt: 20,
          updatedAt: 20,
        );
        await db.insert('finance_transactions', original.toMap());
        await db.insert('finance_transactions', refund.toMap());
        final request = await FinanceSyncService.prepare(
          username: user,
          forceFullSync: false,
        );
        final records = [
          {
            ...original.toMap(),
            'is_deleted': 1,
            'updated_at': 200,
            'version': 2,
          },
          {...refund.toMap(), 'is_deleted': 1, 'updated_at': 199, 'version': 2},
        ];
        final response = _balanceSyncResponse(supportsBalances: true);
        response['server_finance_transactions'] = reverse
            ? records.reversed.toList()
            : records;
        final result = await FinanceSyncService.finish(
          request: request,
          response: response,
          supported: true,
        );
        expect(
          (await FinanceStorage.getTransaction(original.uuid))!.isDeleted,
          true,
        );
        expect(
          (await FinanceStorage.getTransaction(refund.uuid))!.isDeleted,
          true,
        );
        expect(result.remoteChangeCount, 2);
        expect(result.remoteChangesDeferred, false);
        expect(result.cursorAdvanced, true);
      }
    });

    test('旧版本已经推进游标后，升级仍会全量补回遗漏的原单删除', () async {
      final prefs = await SharedPreferences.getInstance();
      final initial = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      await prefs.setBool(
        initial.bootstrapKey.replaceFirst(
          RegExp(r'finance_sync_v\d+_'),
          'finance_sync_v1_',
        ),
        true,
      );
      await prefs.setBool(initial.balanceCapabilityKey, true);
      await prefs.setBool(initial.balanceBootstrapKey, true);
      await prefs.setInt(initial.cursorKey, 500);
      final original = FinanceTransaction(
        uuid: 'previously-skipped-original',
        amountMinor: 10000,
        transactionDate: '2026-09-01',
        createdAt: 10,
        updatedAt: 10,
      );
      await db.insert('finance_transactions', original.toMap());
      final request = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      expect(request.fullSync, true);
      final response = _balanceSyncResponse(supportsBalances: true);
      response['server_finance_transactions'] = [
        {...original.toMap(), 'is_deleted': 1, 'updated_at': 200, 'version': 2},
      ];
      await FinanceSyncService.finish(
        request: request,
        response: response,
        supported: true,
      );
      expect(
        (await FinanceStorage.getTransaction(original.uuid))!.isDeleted,
        true,
      );
      expect(
        (await FinanceSyncService.prepare(
          username: user,
          forceFullSync: false,
        )).fullSync,
        false,
      );
    });

    test('缺少退款原单时保留同步游标，下一轮全量补齐关联后再前移', () async {
      final prefs = await SharedPreferences.getInstance();
      final initial = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      await prefs.setBool(initial.bootstrapKey, true);
      await prefs.setBool(initial.balanceCapabilityKey, true);
      await prefs.setBool(initial.balanceBootstrapKey, true);
      await prefs.setInt(initial.cursorKey, 100);
      final original = FinanceTransaction(
        uuid: 'deferred-original',
        amountMinor: 10000,
        transactionDate: '2026-09-01',
        createdAt: 10,
        updatedAt: 99,
      );
      final refund = FinanceTransaction(
        uuid: 'deferred-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 1000,
        transactionDate: '2026-09-02',
        relatedTransactionUuid: original.uuid,
        createdAt: 20,
        updatedAt: 200,
      );
      final request = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      expect(request.fullSync, false);
      final response = _balanceSyncResponse(supportsBalances: true);
      response['server_finance_transactions'] = [refund.toMap()];
      final result = await FinanceSyncService.finish(
        request: request,
        response: response,
        supported: true,
      );
      expect(result.remoteChangesDeferred, true);
      expect(result.cursorAdvanced, false);
      expect(prefs.getInt(initial.cursorKey), 100);
      final retry = await FinanceSyncService.prepare(
        username: user,
        forceFullSync: false,
      );
      expect(retry.fullSync, true);
      response['server_finance_transactions'] = [
        refund.toMap(),
        original.toMap(),
      ];
      final retried = await FinanceSyncService.finish(
        request: retry,
        response: response,
        supported: true,
      );
      expect(retried.remoteChangesDeferred, false);
      expect(retried.cursorAdvanced, true);
      expect(
        (await FinanceStorage.getTransaction(refund.uuid))!
            .relatedTransactionUuid,
        original.uuid,
      );
    });
  });

  FinanceTransaction refundTestExpense({
    String uuid = 'original-expense',
    int amountMinor = 10000,
    int updatedAt = 10,
  }) {
    return FinanceTransaction(
      uuid: uuid,
      type: FinanceTransactionType.expense,
      amountMinor: amountMinor,
      categoryUuid: 'category-food',
      paymentMethodUuid: 'payment-card',
      transactionDate: '2026-09-01',
      merchant: '原单商户',
      createdAt: 10,
      updatedAt: updatedAt,
    );
  }

  FinanceTransaction refundTestTransaction({
    required String uuid,
    required String originalUuid,
    required int amountMinor,
    int updatedAt = 20,
  }) {
    return FinanceTransaction(
      uuid: uuid,
      type: FinanceTransactionType.refund,
      amountMinor: amountMinor,
      categoryUuid: 'category-other',
      transactionDate: '2026-09-02',
      relatedTransactionUuid: originalUuid,
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
  }

  test(
      'finance schema creates transaction, catalog, budget and automation tables',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await DatabaseHelper.ensureFinanceSchema(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'finance_%'",
    );
    final names = tables.map((row) => row['name']).toSet();

    expect(
      names,
      containsAll(<Object>{
        'finance_transactions',
        'finance_categories',
        'finance_payment_methods',
        'finance_budgets',
        'finance_recurring_rules',
        'finance_entry_templates',
        'finance_loans',
        'finance_loan_installments',
      }),
    );

    final budgetColumns = await db.rawQuery(
      'PRAGMA table_info(finance_budgets)',
    );
    expect(
      budgetColumns.map((row) => row['name']),
      containsAll(<Object>{
        'month_key',
        'category_uuid',
        'payment_method_uuid',
        'balance_snapshot_at',
        'amount_minor',
        'is_deleted',
        'version',
        'pending_sync',
      }),
    );

    final transactionColumns = await db.rawQuery(
      'PRAGMA table_info(finance_transactions)',
    );
    expect(
      transactionColumns.map((row) => row['name']),
      containsAll(<Object>{
        'installment_group_uuid',
        'installment_index',
        'installment_count',
        'installment_total_minor',
      }),
    );

    final loanColumns = await db.rawQuery(
      'PRAGMA table_info(finance_loans)',
    );
    expect(
      loanColumns.map((row) => row['name']),
      containsAll(<Object>{
        'principal_minor',
        'annual_interest_rate_bps',
        'term_months',
        'repayment_method',
        'pending_sync',
      }),
    );

    final loanInstallmentColumns = await db.rawQuery(
      'PRAGMA table_info(finance_loan_installments)',
    );
    expect(
      loanInstallmentColumns.map((row) => row['name']),
      containsAll(<Object>{
        'loan_uuid',
        'payment_minor',
        'principal_minor',
        'interest_minor',
        'remaining_principal_minor',
        'is_paid',
        'interest_transaction_uuid',
        'pending_sync',
      }),
    );

    for (final table in <String>[
      'finance_categories',
      'finance_payment_methods',
      'finance_transactions',
      'finance_budgets',
      'finance_recurring_rules',
      'finance_entry_templates',
      'finance_loans',
      'finance_loan_installments',
    ]) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      expect(columns.map((row) => row['name']), contains('pending_sync'));
    }
    final categoryColumns = await db.rawQuery(
      'PRAGMA table_info(finance_categories)',
    );
    expect(
      categoryColumns.map((row) => row['name']),
      contains('icon_customized'),
    );
    expect(
      categoryColumns.map((row) => row['name']),
      contains('name_customized'),
    );
  });

  test('旧付款方式余额升级时保留原有快照时间', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE finance_budgets (
        uuid TEXT NOT NULL UNIQUE,
        month_key TEXT NOT NULL,
        category_uuid TEXT,
        payment_method_uuid TEXT,
        amount_minor INTEGER NOT NULL,
        currency_code TEXT NOT NULL,
        note TEXT,
        is_deleted INTEGER NOT NULL,
        version INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        device_id TEXT,
        pending_sync INTEGER NOT NULL
      )
    ''');
    await db.insert('finance_budgets', {
      'uuid': 'legacy-card',
      'month_key': '2026-09',
      'payment_method_uuid': 'card',
      'amount_minor': 10000,
      'currency_code': 'CNY',
      'is_deleted': 0,
      'version': 1,
      'created_at': 100,
      'updated_at': 200,
      'pending_sync': 0,
    });

    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureFinanceSchema(db);

    final rows = await db.query('finance_budgets');
    expect(rows.single['balance_snapshot_at'], 200);
  });

  test('付款余额修改备注和恢复时保留快照，改金额可设为零', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'balance-snapshot-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await db.insert(
      'finance_payment_methods',
      FinancePaymentMethod(uuid: 'card', name: '测试银行卡').toMap(),
    );

    final balance = FinanceBudget(
      monthKey: '2026-09',
      paymentMethodUuid: 'card',
      amountMinor: 10000,
    );
    await FinanceStorage.saveBudget(balance);
    await db.update(
      'finance_budgets',
      {'balance_snapshot_at': 200},
      where: 'uuid = ?',
      whereArgs: [balance.uuid],
    );
    final edited = (await FinanceStorage.getBudget(balance.uuid))!
      ..note = '只修改备注';
    edited.markAsChanged();
    await FinanceStorage.saveBudget(edited);
    expect((await FinanceStorage.getBudget(balance.uuid))!.balanceSnapshotAt, 200);

    final recalibrated = (await FinanceStorage.getBudget(balance.uuid))!;
    recalibrated.markAsChanged();
    await FinanceStorage.saveBudget(
      recalibrated,
      resetBalanceSnapshot: true,
    );
    expect(
      (await FinanceStorage.getBudget(balance.uuid))!.balanceSnapshotAt,
      greaterThan(200),
      reason: '余额数值未变时，也需要能主动重新记录当前余额',
    );

    await db.update(
      'finance_budgets',
      {'balance_snapshot_at': 200},
      where: 'uuid = ?',
      whereArgs: [balance.uuid],
    );

    await FinanceStorage.deleteBudget(balance.uuid);
    await FinanceStorage.restoreBudget(balance.uuid);
    expect((await FinanceStorage.getBudget(balance.uuid))!.balanceSnapshotAt, 200);

    final zero = (await FinanceStorage.getBudget(balance.uuid))!
      ..amountMinor = 0;
    zero.markAsChanged();
    await FinanceStorage.saveBudget(zero);
    final stored = (await FinanceStorage.getBudget(balance.uuid))!;
    expect(stored.amountMinor, 0);
    expect(stored.balanceSnapshotAt, greaterThan(200));
  });

  test('付款方式余额备份恢复保留快照时间和关联账单', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'balance-backup-test',
    });
    final originalDb =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final restoredDb =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await originalDb.close();
      await restoredDb.close();
    });
    await DatabaseHelper.ensureFinanceSchema(originalDb);
    await DatabaseHelper.ensureFinanceSchema(restoredDb);
    FinanceStorage.databaseOverride = originalDb;
    await FinanceStorage.ensureReady();

    final now = DateTime.now();
    final snapshotAt = now
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    await originalDb.insert(
      'finance_payment_methods',
      FinancePaymentMethod(uuid: 'backup-card', name: '备份银行卡').toMap(),
    );
    final balance = FinanceBudget(
      monthKey: financeMonthKey(now),
      paymentMethodUuid: 'backup-card',
      amountMinor: 10000,
    );
    await FinanceStorage.saveBudget(balance);
    await originalDb.update(
      'finance_budgets',
      {'balance_snapshot_at': snapshotAt},
      where: 'uuid = ?',
      whereArgs: [balance.uuid],
    );
    await FinanceStorage.saveTransaction(FinanceTransaction(
      uuid: 'backup-income',
      type: FinanceTransactionType.income,
      amountMinor: 2500,
      paymentMethodUuid: 'backup-card',
      transactionDate: dateKey(now),
    ));

    final backup = await FinanceStorage.getExportBundle();
    FinanceStorage.databaseOverride = restoredDb;
    await FinanceStorage.importBundle(backup);

    final restoredBalance = (await FinanceStorage.getBudget(balance.uuid))!;
    final restoredIncome =
        (await FinanceStorage.getTransaction('backup-income'))!;
    expect(restoredBalance.balanceSnapshotAt, snapshotAt);
    expect(restoredBalance.amountMinor, 10000);
    expect(restoredIncome.paymentMethodUuid, 'backup-card');
    expect(restoredIncome.amountMinor, 2500);
  });

  test('历史月份余额可指定对应时间，修改金额仍保留所选时间', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'historical-balance-time-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await db.insert(
      'finance_payment_methods',
      FinancePaymentMethod(
        uuid: 'historical-card',
        name: '历史银行卡',
      ).toMap(),
    );

    final now = DateTime.now();
    final pastMonth = DateTime(now.year, now.month - 1);
    final snapshotAt = DateTime(
      pastMonth.year,
      pastMonth.month,
      15,
      9,
      30,
    ).millisecondsSinceEpoch;
    final balance = FinanceBudget(
      monthKey: financeMonthKey(pastMonth),
      paymentMethodUuid: 'historical-card',
      amountMinor: 10000,
    );
    await FinanceStorage.saveBudget(
      balance,
      balanceSnapshotAt: snapshotAt,
    );
    expect((await FinanceStorage.getBudget(balance.uuid))!.balanceSnapshotAt,
        snapshotAt);

    final corrected = (await FinanceStorage.getBudget(balance.uuid))!
      ..amountMinor = 12000;
    corrected.markAsChanged();
    await FinanceStorage.saveBudget(
      corrected,
      balanceSnapshotAt: snapshotAt,
    );
    expect((await FinanceStorage.getBudget(balance.uuid))!.balanceSnapshotAt,
        snapshotAt);

    await expectLater(
      FinanceStorage.saveBudget(
        corrected,
        balanceSnapshotAt: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      ),
      throwsArgumentError,
    );
  });

  test('已有系统分类表升级时新增名称自定义标记', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE finance_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'expense',
        icon TEXT NOT NULL DEFAULT '📦',
        icon_customized INTEGER NOT NULL DEFAULT 0,
        color_value INTEGER,
        parent_uuid TEXT,
        is_system INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        pending_sync INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('finance_categories', {
      'uuid': 'finance-system-category-food',
      'name': '餐饮',
      'is_system': 1,
      'created_at': 1,
      'updated_at': 1,
    });

    await DatabaseHelper.ensureFinanceSchema(db);

    final columns = await db.rawQuery('PRAGMA table_info(finance_categories)');
    expect(columns.map((row) => row['name']), contains('name_customized'));
    final row = (await db.query('finance_categories')).single;
    expect(row['name'], '餐饮');
    expect(row['name_customized'], 0);
  });

  test('AI usage schema upgrades existing records with MiMo detail columns',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE ai_usage_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        operation TEXT NOT NULL,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        image_count INTEGER NOT NULL DEFAULT 0,
        cost_micros INTEGER,
        is_priced INTEGER NOT NULL DEFAULT 0,
        ledger_key TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await DatabaseHelper.ensureAiUsageSchema(db);

    final columns = await db.rawQuery('PRAGMA table_info(ai_usage_records)');
    expect(
      columns.map((row) => row['name']),
      containsAll(<Object>{
        'cached_prompt_tokens',
        'image_tokens',
        'audio_tokens',
        'video_tokens',
        'reasoning_tokens',
        'audio_seconds',
      }),
    );
  });

  test('默认细分类写入数据库时保留父分类关系', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-category-hierarchy-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    await FinanceStorage.ensureReady();
    final rows = await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food-milk-tea'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['parent_uuid'], 'finance-system-category-food');
    expect(rows.single['is_system'], 1);

    final onlineShoppingRows = await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food-online-shopping'],
    );

    expect(onlineShoppingRows, hasLength(1));
    expect(
      onlineShoppingRows.single['parent_uuid'],
      'finance-system-category-food',
    );
    expect(onlineShoppingRows.single['is_system'], 1);
  });

  test('自定义小类校验父分类类型，并随大类归档恢复', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-custom-category-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final parent = FinanceCategory(
      uuid: 'custom-food',
      name: '自定义餐饮',
      sortOrder: 1000,
    );
    final child = FinanceCategory(
      uuid: 'custom-late-night',
      name: '夜宵',
      parentUuid: parent.uuid,
      sortOrder: 1001,
    );
    await FinanceStorage.saveCategory(parent);
    await FinanceStorage.saveCategory(child);
    expect(
      (await db.query('finance_categories',
              where: 'uuid = ?', whereArgs: [child.uuid]))
          .single['parent_uuid'],
      parent.uuid,
    );

    await expectLater(
      FinanceStorage.saveCategory(FinanceCategory(
        uuid: 'wrong-type-child',
        name: '收入夜宵',
        type: FinanceCategoryType.income,
        parentUuid: parent.uuid,
      )),
      throwsArgumentError,
    );

    await FinanceStorage.archiveCategory(parent.uuid);
    var childRow = (await db.query('finance_categories',
            where: 'uuid = ?', whereArgs: [child.uuid]))
        .single;
    expect(childRow['is_archived'], 1);
    await FinanceStorage.unarchiveCategory(parent.uuid);
    childRow = (await db.query('finance_categories',
            where: 'uuid = ?', whereArgs: [child.uuid]))
        .single;
    expect(childRow['is_archived'], 0);
  });

  test('系统分类自定义图标会保留且进入待同步状态', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-system-icon-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();

    final food = FinanceCategory.fromMap(
      (await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: ['finance-system-category-food'],
      ))
          .single,
    )
      ..icon = '🥗'
      ..iconCustomized = true
      ..markAsChanged();
    await FinanceStorage.saveCategory(food);
    await FinanceStorage.ensureReady();

    final row = (await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food'],
    ))
        .single;
    expect(row['icon'], '🥗');
    expect(row['icon_customized'], 1);
    expect(row['pending_sync'], 1);
  });

  test('系统分类自定义名称会保留，旧服务端不会收到该覆盖', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-system-name-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();

    final food = FinanceCategory.fromMap(
      (await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: ['finance-system-category-food'],
      ))
          .single,
    )
      ..name = '日常饮食'
      ..markAsChanged();
    await FinanceStorage.saveCategory(food);
    await FinanceStorage.ensureReady();

    final row = (await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food'],
    ))
        .single;
    expect(row['name'], '日常饮食');
    expect(row['name_customized'], 1);
    expect(row['icon_customized'], 0);
    expect(row['pending_sync'], 1);

    final category = FinanceCategory.fromMap(row).toMap();
    final legacyServerChanges = FinanceSyncService.buildChangesForTest(
      {
        'categories': [category]
      },
      cursor: 0,
      fullSync: true,
    );
    expect(legacyServerChanges['categories'], isEmpty);

    final nameCapableServerChanges = FinanceSyncService.buildChangesForTest(
      {
        'categories': [category]
      },
      cursor: 0,
      fullSync: true,
      supportsCategoryNames: true,
    );
    expect(nameCapableServerChanges['categories'], hasLength(1));
    expect(
      nameCapableServerChanges['categories']!.single['name'],
      '日常饮食',
    );

    final firstRequest = await FinanceSyncService.prepare(
      username: 'finance-system-name-test',
      forceFullSync: false,
    );
    expect(firstRequest.supportsCategoryNames, isFalse);
    final handshakeResult = await FinanceSyncService.finish(
      request: firstRequest,
      supported: true,
      response: {
        'server_finance_categories': [
          FinanceCategory(
            uuid: 'finance-system-category-food',
            name: '餐饮',
            icon: '🥗',
            isSystem: true,
            iconCustomized: true,
            version: 100,
            createdAt: 1,
            updatedAt: 1000000000000,
          ).toMap(),
        ],
        'server_finance_payment_methods': <Map<String, dynamic>>[],
        'server_finance_transactions': <Map<String, dynamic>>[],
        'server_finance_budgets': <Map<String, dynamic>>[],
        'server_finance_recurring_rules': <Map<String, dynamic>>[],
        'server_finance_entry_templates': <Map<String, dynamic>>[],
        'finance_acknowledged_changes': <Map<String, dynamic>>[],
        'new_finance_sync_time': 100,
        'sync_capabilities': {
          'finance_v1': 1,
          'finance_category_names_v1': 1,
        },
      },
    );
    expect(handshakeResult.supported, isTrue);
    final afterLegacySnapshot = (await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food'],
    ))
        .single;
    expect(afterLegacySnapshot['name'], '日常饮食');
    expect(afterLegacySnapshot['pending_sync'], 1);
    final nextRequest = await FinanceSyncService.prepare(
      username: 'finance-system-name-test',
      forceFullSync: false,
    );
    expect(nextRequest.supportsCategoryNames, isTrue);
    expect(
      nextRequest.payload['finance_categories_changes']
          .map((item) => item['name']),
      contains('日常饮食'),
    );

    final importResult = await FinanceStorage.importBundle({
      'categories': [
        FinanceCategory(
          uuid: 'finance-system-category-food',
          name: '家庭餐食',
          icon: '🍜',
          isSystem: true,
          nameCustomized: true,
        ).toMap(),
      ],
    });
    expect(importResult['updated'], 1);
    await FinanceStorage.ensureReady();
    final importedRow = (await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food'],
    ))
        .single;
    expect(importedRow['name'], '家庭餐食');
    expect(importedRow['name_customized'], 1);
  });

  test('云端系统分类名称和图标覆盖不会被新设备默认值覆盖', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-remote-icon-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();

    final changed = await FinanceStorage.mergeRemoteBundle({
      'categories': [
        FinanceCategory(
          uuid: 'finance-system-category-food',
          name: '日常饮食',
          icon: '🥗',
          isSystem: true,
          iconCustomized: true,
          nameCustomized: true,
          version: 2,
          createdAt: 1,
          updatedAt: 1,
        ).toMap(),
      ],
    });
    await FinanceStorage.ensureReady();

    final row = (await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food'],
    ))
        .single;
    expect(changed, 1);
    expect(row['name'], '日常饮食');
    expect(row['name_customized'], 1);
    expect(row['icon'], '🥗');
    expect(row['icon_customized'], 1);
    expect(row['pending_sync'], 0);
  });

  test('同一预算范围使用稳定 UUID，远端重复范围只保留较新记录', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'budget-scope-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await db.insert(
      'finance_categories',
      FinanceCategory(uuid: 'category-food', name: '餐饮').toMap(),
    );

    final local = FinanceBudget(
      monthKey: '2026-09',
      categoryUuid: 'category-food',
      amountMinor: 30000,
    );
    await FinanceStorage.saveBudget(local);
    expect(
      local.uuid,
      FinanceBudget.stableUuid('2026-09', 'category-food'),
    );
    await expectLater(
      FinanceStorage.saveBudget(FinanceBudget(
        monthKey: '2026-09',
        categoryUuid: 'category-food',
        amountMinor: 40000,
      )),
      throwsStateError,
    );

    await FinanceStorage.mergeRemoteBundle({
      'budgets': [
        {
          'uuid': 'remote-newer-budget',
          'month_key': '2026-09',
          'category_uuid': 'category-food',
          'amount_minor': 50000,
          'updated_at': local.updatedAt + 100,
          'created_at': local.createdAt,
          'version': 2,
        },
      ],
    });
    final budgets = await FinanceStorage.getBudgets(monthKey: '2026-09');
    expect(budgets, hasLength(1));
    expect(budgets.single.uuid, 'remote-newer-budget');
    expect(budgets.single.amountMinor, 50000);
  });

  test('付款方式余额按月和账户独立保存并进入独立同步字段', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'payment-budget-scope-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    for (final uuid in ['payment-card', 'payment-wallet']) {
      await db.insert(
        'finance_payment_methods',
        FinancePaymentMethod(uuid: uuid, name: uuid).toMap(),
      );
    }

    final card = FinanceBudget(
      monthKey: '2026-09',
      paymentMethodUuid: 'payment-card',
      amountMinor: 50000,
    );
    final wallet = FinanceBudget(
      monthKey: '2026-09',
      paymentMethodUuid: 'payment-wallet',
      amountMinor: 20000,
    );
    await FinanceStorage.saveBudget(card);
    await FinanceStorage.saveBudget(wallet);

    expect(
      card.uuid,
      FinanceBudget.stableUuid(
        '2026-09',
        null,
        paymentMethodUuid: 'payment-card',
      ),
    );
    expect(wallet.uuid, isNot(card.uuid));
    expect((await FinanceStorage.getBudget(card.uuid))!.pendingSync, isTrue);
    expect((await FinanceStorage.getBudget(wallet.uuid))!.pendingSync, isTrue);

    await FinanceStorage.mergeRemoteBundle({
      'budgets': [
        {
          'uuid': 'remote-overall-budget',
          'month_key': '2026-09',
          'amount_minor': 100000,
          'updated_at': 100,
          'created_at': 100,
          'version': 1,
        },
      ],
    });

    final budgets = await FinanceStorage.getBudgets(monthKey: '2026-09');
    expect(budgets, hasLength(3));
    expect(
      budgets.map((item) => item.paymentMethodUuid),
      containsAll(<String?>['payment-card', 'payment-wallet']),
    );

    final syncChanges = FinanceSyncService.buildChangesForTest(
      {
        'budgets': [
          {...card.toMap(), 'pending_sync': 1},
          FinanceBudget(
            uuid: 'overall-budget',
            monthKey: '2026-09',
            amountMinor: 100000,
            pendingSync: true,
          ).toMap(),
        ],
      },
      cursor: 0,
      fullSync: true,
    );
    expect(
      syncChanges['budgets']!.map((item) => item['uuid']),
      unorderedEquals(['overall-budget', card.uuid]),
    );
    expect(syncChanges['balance_snapshots']!.single['uuid'], card.uuid);
  });

  test('远端较新预算墓碑会压住同范围的历史活动副本', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'budget-tombstone-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await db.insert(
      'finance_categories',
      FinanceCategory(uuid: 'category-food', name: '餐饮').toMap(),
    );

    await FinanceStorage.mergeRemoteBundle({
      'budgets': [
        {
          'uuid': 'old-active-budget',
          'month_key': '2026-09',
          'category_uuid': 'category-food',
          'amount_minor': 30000,
          'is_deleted': 0,
          'updated_at': 100,
          'created_at': 100,
          'version': 1,
        },
        {
          'uuid': 'new-budget-tombstone',
          'month_key': '2026-09',
          'category_uuid': 'category-food',
          'amount_minor': 30000,
          'is_deleted': 1,
          'updated_at': 200,
          'created_at': 100,
          'version': 2,
        },
      ],
    });

    expect(await FinanceStorage.getBudgets(monthKey: '2026-09'), isEmpty);
    final stored = await db.query('finance_budgets');
    expect(stored, hasLength(1));
    expect(stored.single['uuid'], 'new-budget-tombstone');
    expect(stored.single['is_deleted'], 1);
  });

  test('记账导出脱敏覆盖贷款和还款明细', () {
    final bundle = <String, dynamic>{
      for (final key in [
        'transactions',
        'categories',
        'payment_methods',
        'budgets',
        'recurring_rules',
        'templates',
        'loans',
        'loan_installments',
      ])
        key: [
          <String, dynamic>{
            'uuid': '$key-1',
            'device_id': 'private-device',
          },
        ],
    };

    FinanceStorage.removeDeviceIdsFromExportBundle(bundle);

    for (final items in bundle.values) {
      expect((items as List).single['device_id'], isNull);
    }
  });

  test('导入跳过无效账单和孤立还款计划', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-import-validation-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final result = await FinanceStorage.importBundle({
      'transactions': [
        {
          'uuid': 'zero-amount',
          'type': 'expense',
          'amount_minor': 0,
          'transaction_date': '2026-09-01',
        },
        {
          'uuid': 'bad-date',
          'type': 'expense',
          'amount_minor': 100,
          'transaction_date': 'not-a-date',
        },
      ],
      'loan_installments': [
        {
          'uuid': 'orphan-installment',
          'loan_uuid': 'missing-loan',
          'installment_index': 1,
          'due_date': '2026-09-01',
          'payment_minor': 110,
          'principal_minor': 100,
          'interest_minor': 10,
          'remaining_principal_minor': 0,
        },
      ],
    });

    expect(result['imported'], 0);
    expect(result['skipped'], 3);
    expect(await db.query('finance_transactions'), isEmpty);
    expect(await db.query('finance_loan_installments'), isEmpty);
  });

  test('历史退款分类迁移到支出侧的专用分类', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'refund-migration-test',
    });
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    final oldUpdatedAt = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    await db.insert('finance_transactions', {
      'uuid': 'legacy-refund',
      'type': 'refund',
      'amount_minor': 1200,
      'currency_code': 'CNY',
      'category_uuid': 'finance-system-category-salary',
      'transaction_date': '2026-01-01',
      'timezone_offset_minutes': 480,
      'source': 'manual',
      'is_deleted': 0,
      'version': 1,
      'created_at': oldUpdatedAt,
      'updated_at': oldUpdatedAt,
      'pending_sync': 0,
    });

    final revisionBeforeRepair = FinanceStorage.revision.value;
    final transactions = await FinanceStorage.getTransactions();
    expect(FinanceStorage.revision.value, revisionBeforeRepair + 1);
    final refundCategory = await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-refund'],
    );

    expect(transactions.single.categoryUuid, 'finance-system-category-refund');
    expect(transactions.single.pendingSync, isTrue);
    expect(refundCategory.single['type'], 'expense');

    await FinanceStorage.getTransactions();
    expect(FinanceStorage.revision.value, revisionBeforeRepair + 1);
  });

  test('贷款保存还款计划，已还利息进入支出并支持删除恢复', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'loan-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    await FinanceStorage.saveLoan(
      FinanceLoan(
        uuid: 'loan-1',
        name: '消费贷',
        lender: '测试银行',
        principalMinor: 1000000,
        annualInterestRateBps: 1200,
        termMonths: 3,
        startDate: '2026-01-31',
        repaymentDay: 31,
      ),
    );

    final installments = await FinanceStorage.getLoanInstallments('loan-1');
    expect(installments, hasLength(3));
    expect(installments.first.dueDate, '2026-02-28');
    expect(
      installments.fold<int>(0, (sum, item) => sum + item.principalMinor),
      1000000,
    );
    expect(installments.last.remainingPrincipalMinor, 0);

    await FinanceStorage.setLoanInstallmentPaid(installments.first.uuid, true);
    final paid =
        await FinanceStorage.getLoanInstallment(installments.first.uuid);
    expect(paid?.isPaid, isTrue);
    expect(paid?.interestTransactionUuid, isNotNull);
    final interestRows = await db.query(
      'finance_transactions',
      where: 'related_transaction_uuid = ? AND is_deleted = 0',
      whereArgs: [installments.first.uuid],
    );
    expect(interestRows, hasLength(1));
    expect(
        interestRows.single['amount_minor'], installments.first.interestMinor);
    expect(
      interestRows.single['category_uuid'],
      'finance-system-category-loan-interest',
    );
    final stableInterestUuid = paid!.interestTransactionUuid;

    await FinanceStorage.setLoanInstallmentPaid(installments.first.uuid, false);
    expect(
      await db.query(
        'finance_transactions',
        where: 'related_transaction_uuid = ? AND is_deleted = 0',
        whereArgs: [installments.first.uuid],
      ),
      isEmpty,
    );
    await FinanceStorage.setLoanInstallmentPaid(installments.first.uuid, true);
    final repaid =
        await FinanceStorage.getLoanInstallment(installments.first.uuid);
    expect(repaid?.interestTransactionUuid, stableInterestUuid);
    expect(
      await db.query(
        'finance_transactions',
        where: 'related_transaction_uuid = ? AND is_deleted = 0',
        whereArgs: [installments.first.uuid],
      ),
      hasLength(1),
    );

    await FinanceStorage.deleteLoan('loan-1');
    expect(await FinanceStorage.getLoans(), isEmpty);
    expect(
      await FinanceStorage.getLoanInstallments('loan-1'),
      isEmpty,
    );
    expect(
      await FinanceStorage.getLoanInstallments('loan-1', includeDeleted: true),
      everyElement(predicate<FinanceLoanInstallment>((item) => item.isDeleted)),
    );

    await FinanceStorage.restoreLoan('loan-1');
    expect(await FinanceStorage.getLoans(), hasLength(1));
    expect(await FinanceStorage.getLoanInstallments('loan-1'), hasLength(3));
  });

  test('分期账单以同一分期组原子保存，并支持整组删除和恢复', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'installment-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final saved = await FinanceStorage.saveInstallmentPlan(
      transaction: FinanceTransaction(
        uuid: 'installment-root',
        amountMinor: 10000,
        transactionDate: '2026-01-31',
        merchant: '年度服务',
      ),
      totalAmountMinor: 10000,
      installmentCount: 3,
      startDate: DateTime(2026, 1, 31),
    );

    expect(saved, hasLength(3));
    expect(saved.map((item) => item.amountMinor).toList(), [3334, 3333, 3333]);
    expect(saved.every((item) => item.isInstallment), isTrue);
    expect(
        saved.map((item) => item.installmentGroupUuid).toSet(), hasLength(1));
    expect(
      await FinanceStorage.getTransactions(
        from: DateTime(2026, 1),
        to: DateTime(2026, 4),
      ),
      hasLength(3),
    );

    final groupUuid = saved.first.installmentGroupUuid!;
    final edited = await FinanceStorage.saveInstallmentPlan(
      transaction: FinanceTransaction(
        uuid: saved.first.uuid,
        amountMinor: 12000,
        transactionDate: '2026-01-31',
        merchant: '年度服务',
        installmentGroupUuid: groupUuid,
      ),
      totalAmountMinor: 12000,
      installmentCount: 2,
      startDate: DateTime(2026, 1, 31),
      existingInstallments: await FinanceStorage.getInstallmentGroup(
        groupUuid,
        includeDeleted: true,
      ),
    );
    expect(edited.map((item) => item.amountMinor).toList(), [6000, 6000]);
    expect(
      await FinanceStorage.getInstallmentGroup(groupUuid, includeDeleted: true),
      everyElement(predicate<FinanceTransaction>(
          (item) => item.isDeleted || item.installmentCount == 2)),
    );
    await expectLater(
      FinanceStorage.restoreTransaction(saved.last.uuid),
      throwsA(isA<StateError>()),
    );
    expect(
      (await FinanceStorage.getTransaction(saved.last.uuid))!.isDeleted,
      isTrue,
    );

    await FinanceStorage.deleteInstallmentGroup(groupUuid);
    expect(await FinanceStorage.getInstallmentGroup(groupUuid), isEmpty);
    expect(
      await FinanceStorage.getInstallmentGroup(groupUuid, includeDeleted: true),
      everyElement(predicate<FinanceTransaction>((item) => item.isDeleted)),
    );

    await FinanceStorage.restoreInstallmentGroup(groupUuid);
    expect(await FinanceStorage.getInstallmentGroup(groupUuid), hasLength(2));
  });

  test('编辑分期组不会恢复单独删除的期次', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'installment-edit-deleted-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final saved = await FinanceStorage.saveInstallmentPlan(
      transaction: FinanceTransaction(
        uuid: 'installment-edit-deleted-first',
        amountMinor: 12000,
        transactionDate: '2026-01-31',
        merchant: '分期账单',
      ),
      totalAmountMinor: 12000,
      installmentCount: 3,
      startDate: DateTime(2026, 1, 31),
    );
    final groupUuid = saved.first.installmentGroupUuid!;
    await FinanceStorage.deleteTransaction(saved[1].uuid);
    final existing = await FinanceStorage.getInstallmentGroup(
      groupUuid,
      includeDeleted: true,
    );
    final original = (await FinanceStorage.getTransaction(saved.first.uuid))!;
    final edited = FinanceTransaction.fromMap(original.toMap())
      ..note = '更新整组备注'
      ..markAsChanged();

    await FinanceStorage.saveInstallmentPlan(
      transaction: edited,
      original: original,
      totalAmountMinor: 12000,
      installmentCount: 3,
      startDate: DateTime(2026, 1, 31),
      existingInstallments: existing,
    );

    expect(
      (await FinanceStorage.getTransaction(saved[1].uuid))!.isDeleted,
      isTrue,
    );
  });

  test('扩展已缩短的分期计划会恢复超出旧期数的期次', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'installment-expand-shortened-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final saved = await FinanceStorage.saveInstallmentPlan(
      transaction: FinanceTransaction(
        uuid: 'installment-expand-shortened-first',
        amountMinor: 12000,
        transactionDate: '2026-01-31',
        merchant: '分期账单',
      ),
      totalAmountMinor: 12000,
      installmentCount: 3,
      startDate: DateTime(2026, 1, 31),
    );
    final groupUuid = saved.first.installmentGroupUuid!;
    var existing = await FinanceStorage.getInstallmentGroup(
      groupUuid,
      includeDeleted: true,
    );
    var original = (await FinanceStorage.getTransaction(saved.first.uuid))!;
    final reduced = await FinanceStorage.saveInstallmentPlan(
      transaction: original,
      original: original,
      totalAmountMinor: 12000,
      installmentCount: 2,
      startDate: DateTime(2026, 1, 31),
      existingInstallments: existing,
    );
    expect(
      (await FinanceStorage.getTransaction(saved.last.uuid))!.isDeleted,
      isTrue,
    );

    existing = await FinanceStorage.getInstallmentGroup(
      groupUuid,
      includeDeleted: true,
    );
    original = (await FinanceStorage.getTransaction(reduced.first.uuid))!;
    final extended = await FinanceStorage.saveInstallmentPlan(
      transaction: original,
      original: original,
      totalAmountMinor: 12000,
      installmentCount: 3,
      startDate: DateTime(2026, 1, 31),
      existingInstallments: existing,
    );

    expect(
      extended.singleWhere((item) => item.installmentIndex == 3).isDeleted,
      isFalse,
    );
  });

  test('旧内置Flash价格缓存迁移到新价且设置只保留用户覆盖', () async {
    const oldFlashPrice = AiUsagePricing(
      provider: 'deepseek',
      model: 'deepseek-v4-flash',
      cachedInputMicrosPerMillion: 50000,
      inputMicrosPerMillion: 1500000,
      outputMicrosPerMillion: 4500000,
      peakCachedInputMicrosPerMillion: 100000,
      peakInputMicrosPerMillion: 3000000,
      peakOutputMicrosPerMillion: 9000000,
    );
    const oldVisionPrice = AiUsagePricing(
      provider: 'deepseek',
      model: 'deepseek-v4-flash-vision-exp',
      cachedInputMicrosPerMillion: 50000,
      inputMicrosPerMillion: 1500000,
      outputMicrosPerMillion: 4500000,
      peakCachedInputMicrosPerMillion: 100000,
      peakInputMicrosPerMillion: 3000000,
      peakOutputMicrosPerMillion: 9000000,
      imageTokensIncluded: true,
    );
    const settingsKey = 'ai_usage_cost_settings_deepseek-pricing-migration';
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'deepseek-pricing-migration',
      settingsKey: jsonEncode({
        'auto_ledger': true,
        'prices': [oldFlashPrice.toJson(), oldVisionPrice.toJson()],
      }),
    });

    var pricing = await AiUsageCostService.getPricing();
    for (final model in <String>[
      'deepseek-v4-flash',
      'deepseek-v4-flash-vision-exp',
    ]) {
      final item = pricing.firstWhere(
        (value) => value.provider == 'deepseek' && value.model == model,
      );
      expect(item.cachedInputMicrosPerMillion, 20000);
      expect(item.inputMicrosPerMillion, 1000000);
      expect(item.outputMicrosPerMillion, 4000000);
      expect(item.peakCachedInputMicrosPerMillion, 40000);
      expect(item.peakInputMicrosPerMillion, 2000000);
      expect(item.peakOutputMicrosPerMillion, 8000000);
      expect(item.imageTokensIncluded, isTrue);
    }

    await AiUsageCostService.setAutoLedgerEnabled(false);
    final preferences = await SharedPreferences.getInstance();
    var storedSettings =
        jsonDecode(preferences.getString(settingsKey)!) as Map<String, dynamic>;
    expect(storedSettings['prices'], isEmpty);

    await AiUsageCostService.savePricing(
      const AiUsagePricing(
        provider: 'deepseek',
        model: 'deepseek-v4-flash',
        inputMicrosPerMillion: 123456,
      ),
    );
    pricing = await AiUsageCostService.getPricing();
    expect(
      pricing
          .firstWhere((item) => item.id == 'deepseek::deepseek-v4-flash')
          .inputMicrosPerMillion,
      123456,
    );
    storedSettings =
        jsonDecode(preferences.getString(settingsKey)!) as Map<String, dynamic>;
    expect(storedSettings['prices'], hasLength(1));
  });

  test('priced AI usage is aggregated into one personal finance transaction',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'ai-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;
    await AiUsageCostService.savePricing(
      const AiUsagePricing(
        provider: 'zhipu',
        model: 'glm-test',
        inputMicrosPerMillion: 1000000,
        outputMicrosPerMillion: 2000000,
      ),
    );

    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-test',
      operation: 'chat',
      promptTokens: 1000000,
      completionTokens: 500000,
      totalTokens: 1500000,
      now: DateTime(2026, 8, 30, 10),
    );

    final summary = await AiUsageCostService.getSummary(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 9, 1),
    );
    expect(summary.calls, 1);
    expect(summary.costMicros, 2000000);
    final transactions = await db.query('finance_transactions');
    expect(transactions, hasLength(1));
    expect(transactions.single['amount_minor'], 200);
    expect(
      transactions.single['category_uuid'],
      'finance-system-category-ai-service',
    );
  });

  test('pricing settings preserve tier and peak metadata', () {
    const pricing = AiUsagePricing(
      provider: 'deepseek',
      model: 'deepseek-v4-flash',
      cachedInputMicrosPerMillion: 50000,
      inputMicrosPerMillion: 1500000,
      outputMicrosPerMillion: 4500000,
      peakCachedInputMicrosPerMillion: 100000,
      peakInputMicrosPerMillion: 3000000,
      peakOutputMicrosPerMillion: 9000000,
      imageTokensIncluded: true,
      tiers: [
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          maxCompletionTokens: 200000,
          cachedInputMicrosPerMillion: 400000,
          inputMicrosPerMillion: 2000000,
          outputMicrosPerMillion: 8000000,
        ),
      ],
    );

    final restored = AiUsagePricing.fromJson(pricing.toJson());
    expect(restored.provider, pricing.provider);
    expect(restored.peakInputMicrosPerMillion, 3000000);
    expect(restored.imageTokensIncluded, isTrue);
    expect(restored.tiers.single.maxPromptTokens, 32000);
    expect(restored.tiers.single.maxCompletionTokens, 200000);
  });

  test('MiMo pricing separates cached input and does not add image fees',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'mimo-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;

    final mimoPricing = (await AiUsageCostService.getPricing()).firstWhere(
      (item) => item.provider == 'mimo' && item.model == 'mimo-v2.5',
    );
    expect(mimoPricing.cachedInputMicrosPerMillion, 20000);
    expect(mimoPricing.inputMicrosPerMillion, 1000000);
    expect(mimoPricing.outputMicrosPerMillion, 2000000);

    final ultraSpeedPricing = (await AiUsageCostService.getPricing()).firstWhere(
      (item) =>
          item.provider == 'mimo' &&
          item.model == 'mimo-v2.6-pro-ultraspeed',
    );
    expect(ultraSpeedPricing.cachedInputMicrosPerMillion, 250000);
    expect(ultraSpeedPricing.inputMicrosPerMillion, 30000000);
    expect(ultraSpeedPricing.outputMicrosPerMillion, 60000000);
    expect(ultraSpeedPricing.imageTokensIncluded, isTrue);

    await AiUsageCostService.recordUsage(
      provider: 'mimo',
      model: 'mimo-v2.5',
      operation: 'vision_todo',
      promptTokens: 10000,
      completionTokens: 2000,
      totalTokens: 12000,
      cachedPromptTokens: 8000,
      imageTokens: 500,
      imageCount: 1,
      now: DateTime(2026, 8, 30, 10),
    );

    final records = await AiUsageCostService.getRecords();
    expect(records, hasLength(1));
    expect(records.single.cachedPromptTokens, 8000);
    expect(records.single.uncachedPromptTokens, 2000);
    expect(records.single.imageTokens, 500);
    // 2,000 * ¥1/M + 8,000 * ¥0.02/M + 2,000 * ¥2/M = ¥0.00616.
    expect(records.single.costMicros, 6160);
    expect(records.single.isPriced, isTrue);

    final summary = await AiUsageCostService.getSummary(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 9, 1),
    );
    expect(summary.costMicros, 6160);
    expect(summary.breakdowns.single.cachedPromptTokens, 8000);
    expect(summary.breakdowns.single.imageTokens, 500);
  });

  test('MiMo ASR pricing uses seconds instead of token prices', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'mimo-asr-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;

    await AiUsageCostService.recordUsage(
      provider: 'mimo',
      model: 'mimo-v2.5-asr',
      operation: 'asr',
      promptTokens: 46,
      completionTokens: 20,
      totalTokens: 66,
      cachedPromptTokens: 45,
      audioTokens: 25,
      audioSeconds: 4,
      now: DateTime(2026, 8, 30, 10),
    );

    final records = await AiUsageCostService.getRecords();
    expect(records.single.audioSeconds, 4);
    // 4 seconds * ¥0.5/hour = ¥0.000555..., rounded to 556 micro-yuan.
    expect(records.single.costMicros, 556);
    expect(records.single.isPriced, isTrue);
  });

  test('MiMo token-priced audio usage keeps token pricing when seconds exist',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'mimo-audio-token-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;

    await AiUsageCostService.recordUsage(
      provider: 'mimo',
      model: 'mimo-v2.5',
      operation: 'audio_chat',
      promptTokens: 10000,
      completionTokens: 2000,
      totalTokens: 12000,
      cachedPromptTokens: 8000,
      audioTokens: 100,
      audioSeconds: 4,
      now: DateTime(2026, 8, 30, 10),
    );

    final record = (await AiUsageCostService.getRecords()).single;
    expect(record.isPriced, isTrue);
    expect(record.costMicros, 6160);
  });

  test('Zhipu pricing applies prompt and completion token tiers', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'zhipu-tier-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;

    final pricing = (await AiUsageCostService.getPricing()).firstWhere(
      (item) => item.provider == 'zhipu' && item.model == 'glm-4.7',
    );
    expect(pricing.tiers, hasLength(3));

    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-4.7',
      operation: 'chat',
      promptTokens: 10000,
      completionTokens: 100000,
      totalTokens: 110000,
      cachedPromptTokens: 2000,
      now: DateTime.utc(2026, 8, 30, 10),
    );
    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-4.7',
      operation: 'chat',
      promptTokens: 40000,
      completionTokens: 100000,
      totalTokens: 140000,
      cachedPromptTokens: 10000,
      now: DateTime.utc(2026, 8, 31, 10),
    );
    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-4.7',
      operation: 'chat',
      promptTokens: 10000,
      completionTokens: 200000,
      totalTokens: 210000,
      cachedPromptTokens: 2000,
      now: DateTime.utc(2026, 8, 31, 11),
    );

    final records = await AiUsageCostService.getRecords();
    expect(
        records.map((item) => item.costMicros),
        containsAll(<int?>[
          816800,
          1728000,
          2825200,
        ]));
    expect(records.every((item) => item.isPriced), isTrue);
  });

  test('Zhipu visual token pricing does not add a per-image fee', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'zhipu-vision-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;

    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-4.6v',
      operation: 'vision_todo',
      promptTokens: 10000,
      completionTokens: 1000,
      totalTokens: 11000,
      cachedPromptTokens: 1000,
      imageTokens: 1500,
      imageCount: 1,
      now: DateTime.utc(2026, 8, 31, 1),
    );

    final record = (await AiUsageCostService.getRecords()).single;
    // 9,000 * ¥1/M + 1,000 * ¥0.2/M + 1,000 * ¥3/M = ¥0.0122.
    expect(record.costMicros, 12200);
    expect(record.isPriced, isTrue);
  });

  test('DeepSeek pricing switches between Beijing peak and off-peak rates',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'deepseek-peak-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;

    for (final timestamp in <DateTime>[
      DateTime.utc(2026, 8, 31, 0), // Beijing 08:00, off-peak.
      DateTime.utc(2026, 8, 31, 2), // Beijing 10:00, peak.
    ]) {
      await AiUsageCostService.recordUsage(
        provider: 'deepseek',
        model: 'deepseek-v4-flash',
        operation: 'chat',
        promptTokens: 1000000,
        completionTokens: 100000,
        totalTokens: 1100000,
        cachedPromptTokens: 400000,
        now: timestamp,
      );
    }

    final records = await AiUsageCostService.getRecords();
    expect(
        records.map((item) => item.costMicros),
        containsAll(<int?>[
          1008000,
          2016000,
        ]));
  });

  test('DeepSeek V4.1 Flash IDs use current rates and include image tokens',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'deepseek-v41-flash-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;

    final pricing = await AiUsageCostService.getPricing();
    for (final model in <String>[
      'deepseek-flash',
      'deepseek-v4-flash',
      'deepseek-v4-flash-vision-exp',
    ]) {
      final modelPricing = pricing.firstWhere(
        (item) => item.provider == 'deepseek' && item.model == model,
      );
      expect(modelPricing.cachedInputMicrosPerMillion, 20000);
      expect(modelPricing.inputMicrosPerMillion, 1000000);
      expect(modelPricing.outputMicrosPerMillion, 4000000);
      expect(modelPricing.peakCachedInputMicrosPerMillion, 40000);
      expect(modelPricing.peakInputMicrosPerMillion, 2000000);
      expect(modelPricing.peakOutputMicrosPerMillion, 8000000);
      expect(modelPricing.imageTokensIncluded, isTrue);

      await AiUsageCostService.recordUsage(
        provider: 'deepseek',
        model: model,
        operation: 'vision_todo',
        promptTokens: 1000000,
        completionTokens: 100000,
        totalTokens: 1100000,
        cachedPromptTokens: 400000,
        imageTokens: 50000,
        imageCount: 1,
        now: DateTime.utc(2026, 8, 31, 0),
      );
    }

    final records = await AiUsageCostService.getRecords();
    expect(records, hasLength(3));
    expect(records.every((item) => item.isPriced), isTrue);
    expect(records.map((item) => item.costMicros), everyElement(1008000));
  });

  test('free provider models are priced at zero when usage is available',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'free-model-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;

    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-4.7-flash',
      operation: 'chat',
      promptTokens: 100000,
      completionTokens: 100000,
      totalTokens: 200000,
      now: DateTime.utc(2026, 8, 31, 1),
    );

    final record = (await AiUsageCostService.getRecords()).single;
    expect(record.costMicros, 0);
    expect(record.isPriced, isTrue);
  });

  test('NVIDIA NIM has no guessed universal built-in price', () async {
    SharedPreferences.setMockInitialValues({});

    final pricing = await AiUsageCostService.getPricing();
    expect(pricing.where((item) => item.provider == 'nvidia_nim'), isEmpty);
  });

  test('unpriced AI usage is retained without creating a guessed expense',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'ai-unpriced-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;
    await AiUsageCostService.savePricing(
      const AiUsagePricing(
        provider: 'custom',
        model: 'unknown-model',
        inputMicrosPerMillion: 1000000,
        outputMicrosPerMillion: 1000000,
        imageMicrosPerImage: 1000000,
      ),
    );

    await AiUsageCostService.recordUsage(
      provider: 'custom',
      model: 'unknown-model',
      operation: 'vision_todo',
      promptTokens: 120,
      completionTokens: 20,
      totalTokens: 140,
      imageCount: 1,
      usageAvailable: false,
      now: DateTime(2026, 8, 30, 10),
    );

    final records = await AiUsageCostService.getRecords();
    expect(records, hasLength(1));
    expect(records.single.isPriced, isFalse);
    expect(await db.query('finance_transactions'), isEmpty);
  });

  test('备份导入不能覆盖或伪造系统目录', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-system-import-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();

    final result = await FinanceStorage.importBundle({
      'categories': [
        {
          'uuid': 'finance-system-category-food',
          'name': '被篡改的分类',
          'type': 'income',
          'is_system': 0,
          'updated_at': 9999999999999,
        },
        {
          'uuid': 'fake-system-category',
          'name': '伪系统分类',
          'type': 'expense',
          'is_system': 1,
          'updated_at': 9999999999999,
        },
      ],
      'payment_methods': [
        {
          'uuid': 'finance-system-payment-cash',
          'name': '被篡改的现金',
          'is_system': 0,
          'updated_at': 9999999999999,
        },
      ],
    });

    expect(result['skipped'], 3);
    final food = await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food'],
    );
    final cash = await db.query(
      'finance_payment_methods',
      where: 'uuid = ?',
      whereArgs: ['finance-system-payment-cash'],
    );
    expect(food.single['name'], isNot('被篡改的分类'));
    expect(cash.single['name'], isNot('被篡改的现金'));
    expect(
      await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: ['fake-system-category'],
      ),
      isEmpty,
    );
  });

  test('旧版数字交易类型备份仍可正常导入', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-numeric-type-import-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final result = await FinanceStorage.importBundle({
      'transactions': [
        {
          'uuid': 'legacy-numeric-refund',
          'type': 2,
          'amount_minor': 880,
          'transaction_date': '2026-08-31',
          'created_at': 10,
          'updated_at': 10,
        },
        {
          'uuid': 'legacy-numeric-string-income',
          'type': '1',
          'amount_minor': 881,
          'transaction_date': '2026-08-31',
          'created_at': 10,
          'updated_at': 10,
        },
      ],
    });
    expect(result['imported'], 2);
    expect(
      (await FinanceStorage.getTransaction('legacy-numeric-refund'))!.type,
      FinanceTransactionType.refund,
    );
    expect(
      (await FinanceStorage.getTransaction('legacy-numeric-string-income'))!
          .type,
      FinanceTransactionType.income,
    );
  });

  test('已删除贷款不接受活动还款计划', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-deleted-loan-import-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    final loan = FinanceLoan(
      uuid: 'deleted-loan',
      name: '已删除贷款',
      principalMinor: 100000,
      annualInterestRateBps: 300,
      termMonths: 12,
      startDate: '2026-01-01',
      repaymentDay: 1,
      isDeleted: true,
      createdAt: 10,
      updatedAt: 10,
    );
    final installment = FinanceLoanInstallment(
      uuid: 'orphan-active-installment',
      loanUuid: loan.uuid,
      installmentIndex: 1,
      dueDate: '2026-02-01',
      paymentMinor: 8500,
      principalMinor: 8300,
      interestMinor: 200,
      remainingPrincipalMinor: 91700,
      createdAt: 11,
      updatedAt: 11,
    );

    final result = await FinanceStorage.importBundle({
      'loans': [loan.toMap()],
      'loan_installments': [installment.toMap()],
    });
    expect(result['imported'], 1);
    expect(result['skipped'], 1);
    expect(
      await db.query('finance_loan_installments'),
      isEmpty,
    );
    expect(
      await FinanceStorage.mergeRemoteBundle({
        'loan_installments': [
          {...installment.toMap(), 'uuid': 'remote-active-installment'},
        ],
      }),
      0,
    );
  });

  test('记账备份导入中途失败时整批回滚', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-atomic-import-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await db.execute('''
      CREATE TRIGGER fail_finance_budget_import
      BEFORE INSERT ON finance_budgets
      BEGIN
        SELECT RAISE(ABORT, 'forced import failure');
      END
    ''');

    await expectLater(
      FinanceStorage.importBundle({
        'categories': [
          {
            'uuid': 'category-before-failure',
            'name': '应当回滚',
            'type': 'expense',
            'updated_at': 10,
          },
        ],
        'budgets': [
          {
            'uuid': 'budget-trigger-failure',
            'month_key': '2026-09',
            'amount_minor': 10000,
            'updated_at': 11,
          },
        ],
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: ['category-before-failure'],
      ),
      isEmpty,
    );
  });

  test('删除后重建稳定范围预算会超过旧墓碑版本', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-budget-recreate-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await db.insert(
      'finance_categories',
      FinanceCategory(uuid: 'category-food', name: '餐饮').toMap(),
    );

    final first = FinanceBudget(
      monthKey: '2026-09',
      categoryUuid: 'category-food',
      amountMinor: 10000,
      updatedAt: 10,
    );
    await FinanceStorage.saveBudget(first);
    await FinanceStorage.deleteBudget(first.uuid);
    final tombstone = (await FinanceStorage.getBudget(first.uuid))!;
    tombstone.updatedAt = 9999999999999;
    await db.update(
      'finance_budgets',
      tombstone.toMap(),
      where: 'uuid = ?',
      whereArgs: [tombstone.uuid],
    );

    final recreated = FinanceBudget(
      monthKey: first.monthKey,
      categoryUuid: first.categoryUuid,
      amountMinor: 20000,
      updatedAt: 20,
    );
    await FinanceStorage.saveBudget(recreated);
    final stored = (await FinanceStorage.getBudget(first.uuid))!;
    expect(recreated.uuid, first.uuid);
    expect(stored.isDeleted, isFalse);
    expect(stored.amountMinor, 20000);
    expect(stored.version, greaterThan(tombstone.version));
    expect(stored.updatedAt, greaterThan(tombstone.updatedAt));
  });

  test('原单支持多次部分退款，累计不能超过原金额', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-refund-binding-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final original = refundTestExpense();
    await FinanceStorage.saveTransaction(original);
    final first = refundTestTransaction(
      uuid: 'refund-1',
      originalUuid: original.uuid,
      amountMinor: 3000,
    );
    await FinanceStorage.saveTransaction(first);
    expect(
      await FinanceStorage.getRemainingRefundableMinor(original.uuid),
      7000,
    );
    final storedFirst = await FinanceStorage.getTransaction(first.uuid);
    expect(storedFirst!.relatedTransactionUuid, original.uuid);
    expect(storedFirst.categoryUuid, original.categoryUuid);

    final second = refundTestTransaction(
      uuid: 'refund-2',
      originalUuid: original.uuid,
      amountMinor: 7000,
    );
    await FinanceStorage.saveTransaction(second);
    expect(
      await FinanceStorage.getRemainingRefundableMinor(original.uuid),
      0,
    );
    await expectLater(
      FinanceStorage.saveTransaction(refundTestTransaction(
        uuid: 'refund-overflow',
        originalUuid: original.uuid,
        amountMinor: 1,
      )),
      throwsStateError,
    );

    first
      ..amountMinor = 2000
      ..updatedAt = 30;
    await FinanceStorage.saveTransaction(first);
    expect(
      await FinanceStorage.getRemainingRefundableMinor(original.uuid),
      1000,
    );
    original
      ..isDeleted = true
      ..updatedAt = 40;
    await expectLater(
      FinanceStorage.saveTransaction(original),
      throwsStateError,
    );
  });

  test('退款只能绑定存在且未删除的支出原单', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-refund-target-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    await expectLater(
      FinanceStorage.saveTransaction(refundTestTransaction(
        uuid: 'missing-original-refund',
        originalUuid: 'missing-original',
        amountMinor: 100,
      )),
      throwsStateError,
    );
    final income = refundTestExpense(uuid: 'income-original')
      ..type = FinanceTransactionType.income;
    await FinanceStorage.saveTransaction(income);
    await expectLater(
      FinanceStorage.saveTransaction(refundTestTransaction(
        uuid: 'income-refund',
        originalUuid: income.uuid,
        amountMinor: 100,
      )),
      throwsStateError,
    );
  });

  test('云端合并先落原单再校验退款，超额记录会被忽略', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-refund-merge-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final original = refundTestExpense(
      uuid: 'remote-original',
      updatedAt: 10,
    );
    final partial = refundTestTransaction(
      uuid: 'remote-refund',
      originalUuid: original.uuid,
      amountMinor: 4000,
      updatedAt: 11,
    );
    expect(
      await FinanceStorage.mergeRemoteBundle({
        'transactions': [partial.toMap(), original.toMap()],
      }),
      2,
    );
    expect(
      await FinanceStorage.getRemainingRefundableMinor(original.uuid),
      6000,
    );

    final overflow = refundTestTransaction(
      uuid: 'remote-overflow',
      originalUuid: original.uuid,
      amountMinor: 6001,
      updatedAt: 12,
    );
    expect(
      await FinanceStorage.mergeRemoteBundle({
        'transactions': [overflow.toMap()],
      }),
      0,
    );
    expect(await FinanceStorage.getTransaction(overflow.uuid), isNull);
  });
}
