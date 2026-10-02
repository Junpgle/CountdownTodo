@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_budget_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_entry_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_loan_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_trash_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/services/finance_sync_service.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _cash = 'finance-system-payment-cash';
const _wechat = 'finance-system-payment-wechat';

Future<Database> _openDatabase() async {
  SharedPreferences.setMockInitialValues({});
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await DatabaseHelper.ensureFinanceSchema(db);
  FinanceStorage.databaseOverride = db;
  await FinanceStorage.ensureReady();
  return db;
}

Future<FinanceLoanInstallment> _payLoan() async {
  final loan = FinanceLoan(
    uuid: 'consistency-loan',
    name: '贷款测试',
    principalMinor: 10000,
    annualInterestRateBps: 1200,
    termMonths: 1,
    startDate: '2026-09-01',
    repaymentDay: 1,
  );
  await FinanceStorage.saveLoan(loan);
  final installment = (await FinanceStorage.getLoanInstallments(loan.uuid))
      .single;
  await FinanceStorage.setLoanInstallmentPaid(
    installment.uuid,
    true,
    paymentMethodUuid: _cash,
    paidAt: DateTime.now().subtract(const Duration(hours: 1)),
  );
  return (await FinanceStorage.getLoanInstallment(installment.uuid))!;
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready() && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('界面未完成加载');
}

void _configureView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(home: screen));
  await _waitFor(tester, () => true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('记账数据一致性', () {
    late Database db;
    setUp(() async => db = await _openDatabase());
    tearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    for (final reverse in [false, true]) {
      test('同时间的余额替换保留有效新记录，顺序反转=$reverse', () async {
        final old = FinanceBudget(
          uuid: 'old-balance',
          monthKey: '2026-09',
          paymentMethodUuid: _cash,
          amountMinor: 10000,
          isDeleted: true,
          version: 8,
          updatedAt: 200,
        );
        final replacement = FinanceBudget(
          uuid: 'new-balance',
          monthKey: old.monthKey,
          paymentMethodUuid: _cash,
          amountMinor: 20000,
          version: 1,
          updatedAt: 200,
        );
        // Also cover a client which previously downloaded only the tombstone.
        await db.insert('finance_budgets', old.toMap());
        final rows = [old.toMap(), replacement.toMap()];
        await FinanceStorage.mergeRemoteBundle({
          'budgets': reverse ? rows.reversed.toList() : rows,
        });
        final active = await FinanceStorage.getBudgets();
        expect(active, hasLength(1));
        expect(active.single.uuid, replacement.uuid);
        expect(active.single.amountMinor, 20000);
        expect(await db.query('finance_budgets'), hasLength(1));
      });
    }

    test('升级后全量补回曾被旧版本丢弃的余额，成功后恢复增量同步', () async {
      const username = 'budget-upgrade';
      final prefs = await SharedPreferences.getInstance();
      final initial = await FinanceSyncService.prepare(
        username: username,
        forceFullSync: false,
      );
      await prefs.setBool(
        initial.bootstrapKey.replaceFirst(
          'finance_sync_v3_',
          'finance_sync_v2_',
        ),
        true,
      );
      await prefs.setBool(initial.balanceCapabilityKey, true);
      await prefs.setBool(initial.balanceBootstrapKey, true);
      await prefs.setInt(initial.cursorKey, 500);
      final old = FinanceBudget(
        uuid: 'discarded-old-balance',
        monthKey: '2026-09',
        paymentMethodUuid: _cash,
        amountMinor: 10000,
        isDeleted: true,
        version: 8,
        updatedAt: 200,
      );
      await db.insert('finance_budgets', old.toMap());
      final request = await FinanceSyncService.prepare(
        username: username,
        forceFullSync: false,
      );
      expect(request.fullSync, true);
      final response = <String, dynamic>{
        'sync_capabilities': {
          'finance_v1': 1,
          'finance_account_balances_v1': 1,
        },
        for (final section in [
          'categories',
          'payment_methods',
          'transactions',
          'loans',
          'loan_installments',
          'budgets',
          'recurring_rules',
          'entry_templates',
        ])
          'server_finance_$section': <Map<String, dynamic>>[],
        'finance_acknowledged_changes': <Map<String, dynamic>>[],
        'new_finance_sync_time': 600,
      };
      response['server_finance_budgets'] = [
        old.toMap(),
        {
          ...old.toMap(),
          'uuid': 'recovered-balance',
          'is_deleted': 0,
          'version': 1,
          'amount_minor': 20000,
        },
      ];
      final result = await FinanceSyncService.finish(
        request: request,
        response: response,
        supported: true,
      );
      expect(result.cursorAdvanced, true);
      expect((await FinanceStorage.getBudgets()).single.amountMinor, 20000);
      expect(
        (await FinanceSyncService.prepare(
          username: username,
          forceFullSync: false,
        )).fullSync,
        false,
      );
    });

    test('其他设备删除快捷模板后拒绝保存旧页面中的编辑', () async {
      final template = FinanceEntryTemplate(
        uuid: 'stale-edit-deleted-template',
        name: '原模板',
        amountMinor: 1200,
      );
      await FinanceStorage.saveTemplate(template);
      final staleOriginal = (await FinanceStorage.getTemplate(template.uuid))!;
      final staleEdit = FinanceEntryTemplate.fromMap(staleOriginal.toMap())
        ..name = '旧页面中的新名称'
        ..markAsChanged();
      final remoteDelete = FinanceEntryTemplate.fromMap(staleOriginal.toMap())
        ..isDeleted = true
        ..version = staleOriginal.version + 1
        ..updatedAt = staleEdit.updatedAt + 10000;
      await FinanceStorage.mergeRemoteBundle({
        'templates': [remoteDelete.toMap()],
      });

      await expectLater(
        FinanceStorage.saveTemplate(staleEdit, original: staleOriginal),
        throwsA(isA<StateError>()),
      );
      final stored = (await FinanceStorage.getTemplate(template.uuid))!;
      expect(stored.name, '原模板');
      expect(stored.isDeleted, true);
    });

    test('同一余额UUID仍按版本接受删除和恢复', () async {
      final balance = FinanceBudget(
        uuid: 'same-balance',
        monthKey: '2026-09',
        paymentMethodUuid: _cash,
        amountMinor: 0,
        updatedAt: 200,
      );
      await FinanceStorage.mergeRemoteBundle({
        'budgets': [balance.toMap()],
      });
      balance
        ..isDeleted = true
        ..version = 2;
      await FinanceStorage.mergeRemoteBundle({
        'budgets': [balance.toMap()],
      });
      expect(await FinanceStorage.getBudgets(), isEmpty);
      balance
        ..isDeleted = false
        ..version = 3;
      await FinanceStorage.mergeRemoteBundle({
        'budgets': [balance.toMap()],
      });
      expect((await FinanceStorage.getBudgets()).single.version, 3);
    });

    test('余额替换不覆盖本地较新余额或服务端较新删除', () async {
      final local = FinanceBudget(
        uuid: 'local-balance',
        monthKey: '2026-09',
        paymentMethodUuid: _cash,
        amountMinor: 30000,
        updatedAt: 300,
      );
      await db.insert('finance_budgets', local.toMap());
      await FinanceStorage.mergeRemoteBundle({
        'budgets': [
          {
            ...local.toMap(),
            'uuid': 'old-balance',
            'is_deleted': 1,
            'updated_at': 200,
            'version': 8,
          },
          {...local.toMap(), 'uuid': 'replacement', 'updated_at': 200},
        ],
      });
      expect((await FinanceStorage.getBudgets()).single.uuid, local.uuid);
      await FinanceStorage.mergeRemoteBundle({
        'budgets': [
          {
            ...local.toMap(),
            'uuid': 'latest-delete',
            'is_deleted': 1,
            'updated_at': 400,
          },
        ],
      });
      expect(await FinanceStorage.getBudgets(), isEmpty);
    });

    for (final newer in [false, true]) {
      test('导入旧余额UUID时统一比较同范围记录，新备份=$newer', () async {
        final old = FinanceBudget(
          uuid: 'old-import-balance',
          monthKey: '2026-09',
          paymentMethodUuid: _cash,
          amountMinor: 10000,
          isDeleted: true,
          updatedAt: 100,
        );
        final current = FinanceBudget(
          uuid: 'current-import-balance',
          monthKey: old.monthKey,
          paymentMethodUuid: _cash,
          amountMinor: 20000,
          updatedAt: 200,
        );
        final unrelated = [
          FinanceBudget(
            uuid: 'other-account',
            monthKey: old.monthKey,
            paymentMethodUuid: _wechat,
            amountMinor: 30000,
          ),
          FinanceBudget(
            uuid: 'other-month',
            monthKey: '2026-10',
            paymentMethodUuid: _cash,
            amountMinor: 40000,
          ),
          FinanceBudget(
            uuid: 'overall-budget',
            monthKey: old.monthKey,
            amountMinor: 50000,
          ),
        ];
        for (final budget in [old, current, ...unrelated]) {
          await db.insert('finance_budgets', budget.toMap());
        }
        await FinanceStorage.importBundle({
          'budgets': [
            {...old.toMap(), 'is_deleted': 0, 'updated_at': newer ? 300 : 150},
          ],
        });
        final scoped = (await FinanceStorage.getBudgets(monthKey: old.monthKey))
            .where((budget) => budget.paymentMethodUuid == _cash)
            .toList();
        expect(scoped, hasLength(1));
        expect(scoped.single.uuid, newer ? old.uuid : current.uuid);
        expect(scoped.single.amountMinor, newer ? 10000 : 20000);
        expect(scoped.single.pendingSync, newer);
        expect(
          await db.query(
            'finance_budgets',
            where: 'month_key = ? AND payment_method_uuid = ?',
            whereArgs: [old.monthKey, _cash],
          ),
          hasLength(1),
        );
        for (final budget in unrelated) {
          expect(
            (await FinanceStorage.getBudget(budget.uuid))!.toMap(),
            budget.toMap(),
          );
        }
      });
    }

    for (final reverse in [false, true]) {
      test('备份中的余额替换与旧删除不受导入顺序影响，反转=$reverse', () async {
        final old = FinanceBudget(
          uuid: 'backup-retired-balance',
          monthKey: '2026-09',
          paymentMethodUuid: _cash,
          amountMinor: 10000,
          isDeleted: true,
          version: 8,
          updatedAt: 200,
        );
        final replacement = FinanceBudget(
          uuid: 'backup-active-balance',
          monthKey: old.monthKey,
          paymentMethodUuid: _cash,
          amountMinor: 20000,
          version: 1,
          updatedAt: 200,
        );
        final rows = [old.toMap(), replacement.toMap()];
        final result = await FinanceStorage.importBundle({
          'budgets': reverse ? rows.reversed.toList() : rows,
        });
        expect(result, {'imported': 1, 'updated': 0, 'skipped': 1});
        final stored = (await FinanceStorage.getBudgets(includeDeleted: true))
            .single;
        expect(stored.uuid, replacement.uuid);
        expect(stored.isDeleted, false);
        expect(stored.pendingSync, true);
      });
    }

    test('备份同一余额UUID按版本删除和恢复，旧备份不能越过新删除', () async {
      final balance = FinanceBudget(
        uuid: 'backup-same-balance',
        monthKey: '2026-09',
        paymentMethodUuid: _cash,
        amountMinor: 0,
        updatedAt: 200,
      );
      await FinanceStorage.importBundle({
        'budgets': [balance.toMap()],
      });
      balance
        ..isDeleted = true
        ..version = 2;
      await FinanceStorage.importBundle({
        'budgets': [balance.toMap()],
      });
      expect(await FinanceStorage.getBudgets(), isEmpty);
      await FinanceStorage.importBundle({
        'budgets': [
          {...balance.toMap(), 'uuid': 'older-backup', 'updated_at': 100},
        ],
      });
      expect(
        (await FinanceStorage.getBudgets(includeDeleted: true)).single.uuid,
        balance.uuid,
      );
      balance
        ..isDeleted = false
        ..version = 3;
      await FinanceStorage.importBundle({
        'budgets': [balance.toMap()],
      });
      expect((await FinanceStorage.getBudgets()).single.version, 3);
    });

    test('备份拒绝同时关联分类和账户的余额，保留合法的独立范围', () async {
      final invalid = FinanceBudget(
        uuid: 'invalid-double-scope',
        monthKey: '2026-09',
        categoryUuid: 'finance-system-category-food',
        paymentMethodUuid: _cash,
        amountMinor: 10000,
      );
      final valid = [
        FinanceBudget(monthKey: invalid.monthKey, amountMinor: 10000),
        FinanceBudget(
          monthKey: invalid.monthKey,
          categoryUuid: invalid.categoryUuid,
          amountMinor: 5000,
        ),
        FinanceBudget(
          monthKey: invalid.monthKey,
          paymentMethodUuid: _cash,
          amountMinor: 0,
        ),
      ];
      final result = await FinanceStorage.importBundle({
        'budgets': [invalid.toMap(), ...valid.map((item) => item.toMap())],
      });
      expect(result, {'imported': 3, 'updated': 0, 'skipped': 1});
      expect(await FinanceStorage.getBudget(invalid.uuid), isNull);
      expect(await FinanceStorage.getBudgets(), hasLength(3));
    });

    test('旧备份不能把较新的同UUID余额移回旧月份', () async {
      final local = FinanceBudget(
        uuid: 'moved-balance',
        monthKey: '2026-10',
        paymentMethodUuid: _cash,
        amountMinor: 20000,
        updatedAt: 200,
      );
      await db.insert('finance_budgets', local.toMap());
      final result = await FinanceStorage.importBundle({
        'budgets': [
          {...local.toMap(), 'month_key': '2026-09', 'updated_at': 100},
        ],
      });
      expect(result['skipped'], 1);
      expect(
        (await FinanceStorage.getBudget(local.uuid))!.toMap(),
        local.toMap(),
      );
      expect(await FinanceStorage.getBudgets(monthKey: '2026-09'), isEmpty);
    });

    for (final reverse in [false, true]) {
      test('实际备份同时删除原单和退款，顺序反转=$reverse', () async {
        final initialAt = DateTime.now().millisecondsSinceEpoch - 1000;
        final original = FinanceTransaction(
          uuid: 'original',
          amountMinor: 10000,
          transactionDate: '2026-09-01',
          createdAt: initialAt,
          updatedAt: initialAt,
        );
        final refund = FinanceTransaction(
          uuid: 'refund',
          type: FinanceTransactionType.refund,
          amountMinor: 1000,
          relatedTransactionUuid: original.uuid,
          transactionDate: '2026-09-02',
          createdAt: initialAt,
          updatedAt: initialAt,
        );
        await db.insert('finance_transactions', original.toMap());
        await db.insert('finance_transactions', refund.toMap());
        await FinanceStorage.deleteTransaction(refund.uuid);
        await FinanceStorage.deleteTransaction(original.uuid);
        final backup = await FinanceStorage.getExportBundle();
        final maps = List<Map<String, dynamic>>.from(
          backup['transactions'] as List,
        )..sort((a, b) => a['uuid'].toString().compareTo(b['uuid'].toString()));
        backup['transactions'] = reverse ? maps.reversed.toList() : maps;
        await db.delete('finance_transactions');
        await db.insert('finance_transactions', original.toMap());
        await db.insert('finance_transactions', refund.toMap());
        final result = await FinanceStorage.importBundle(backup);
        expect(result['updated'], 2);
        expect(await FinanceStorage.getTransactions(), isEmpty);
        expect(await FinanceStorage.getDeletedTransactions(), hasLength(2));
      });
    }

    test('缺少发生时刻的未来分期按到期日才计入付款余额', () async {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 1, 1);
      final createdAt = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        12,
      ).millisecondsSinceEpoch;
      final first = FinanceTransaction(
        uuid: 'future-installment-no-time-first',
        amountMinor: 1000,
        paymentMethodUuid: _cash,
        transactionDate: dateKey(startDate),
        occurredAt: null,
        installmentGroupUuid: 'future-installment-no-time-group',
        installmentIndex: 1,
        installmentCount: 2,
        installmentTotalMinor: 2000,
        createdAt: createdAt,
        updatedAt: createdAt,
      )..occurredAt = null;
      await FinanceStorage.saveTransaction(first);

      final saved = await FinanceStorage.saveInstallmentPlan(
        transaction: first,
        original: first,
        totalAmountMinor: 3000,
        installmentCount: 3,
        startDate: startDate,
        existingInstallments: [first],
      );
      final futureInstallment = saved.last;
      final dueDate = DateTime(now.year, now.month + 1, 1);

      expect(futureInstallment.transactionDate, dateKey(dueDate));
      expect(futureInstallment.occurredAt, isNull);
      expect(
        futureInstallment.balanceEventAt(),
        greaterThanOrEqualTo(dueDate.millisecondsSinceEpoch),
      );
    });

    test('贷款利息拒绝直接修改现金流、删除和拆分，备注仍可修改', () async {
      final paid = await _payLoan();
      final interest = (await FinanceStorage.getTransaction(
        paid.interestTransactionUuid!,
      ))!;
      final changes = <void Function(FinanceTransaction)>[
        (bill) => bill.amountMinor = 200,
        (bill) => bill.paymentMethodUuid = _wechat,
        (bill) => bill.transactionDate = '2026-09-02',
        (bill) => bill.occurredAt = bill.occurredAt! - 60000,
        (bill) => bill.type = FinanceTransactionType.income,
        (bill) => bill.relatedTransactionUuid = null,
      ];
      for (final change in changes) {
        final bill = FinanceTransaction.fromMap(interest.toMap());
        change(bill);
        bill.markAsChanged();
        await expectLater(
          FinanceStorage.saveTransaction(bill),
          throwsStateError,
        );
      }
      await expectLater(
        FinanceStorage.deleteTransaction(interest.uuid),
        throwsStateError,
      );
      await expectLater(
        FinanceStorage.saveInstallmentPlan(
          transaction: interest,
          totalAmountMinor: 100,
          installmentCount: 2,
          startDate: dateFromKey(interest.transactionDate),
        ),
        throwsStateError,
      );
      expect(
        (await FinanceStorage.getTransaction(interest.uuid))!.toMap(),
        interest.toMap(),
      );
      expect(await FinanceStorage.getTransactions(), hasLength(1));
      interest
        ..merchant = '更新商家'
        ..note = '保留备注'
        ..markAsChanged();
      await FinanceStorage.saveTransaction(interest);
      expect(
        (await FinanceStorage.getTransaction(interest.uuid))!.note,
        '保留备注',
      );
      expect(
        (await FinanceStorage.getLoanInstallment(paid.uuid))!.toMap(),
        paid.toMap(),
      );
    });

    test('通过还款接口改账户和时间会同步利息账单，撤销也保持一致', () async {
      final paid = await _payLoan();
      final at = DateTime.now().subtract(const Duration(minutes: 30));
      await FinanceStorage.setLoanInstallmentPaid(
        paid.uuid,
        true,
        paymentMethodUuid: _wechat,
        paidAt: at,
      );
      final installment = (await FinanceStorage.getLoanInstallment(paid.uuid))!;
      final bill = (await FinanceStorage.getTransaction(
        installment.interestTransactionUuid!,
      ))!;
      expect(bill.paymentMethodUuid, installment.paymentMethodUuid);
      expect(bill.occurredAt, installment.paidAt);
      expect(bill.amountMinor, installment.interestMinor);
      await FinanceStorage.setLoanInstallmentPaid(paid.uuid, false);
      expect((await FinanceStorage.getTransaction(bill.uuid))!.isDeleted, true);
      expect(await FinanceStorage.getPaidLoanInstallments(), isEmpty);
    });

    test('撤销还款的利息不能单独恢复或通过清除关联绕过，重新还款可恢复', () async {
      final paid = await _payLoan();
      final billUuid = paid.interestTransactionUuid!;
      await FinanceStorage.setLoanInstallmentPaid(paid.uuid, false);
      final deleted = (await FinanceStorage.getTransaction(billUuid))!;
      final repayment =
          (await FinanceStorage.getRepaymentForInterestTransaction(billUuid))!;
      expect(repayment.uuid, paid.uuid);
      expect(repayment.isPaid, false);
      expect(repayment.interestTransactionUuid, isNull);
      await expectLater(
        FinanceStorage.restoreTransaction(billUuid),
        throwsStateError,
      );
      final disguised = FinanceTransaction.fromMap(deleted.toMap())
        ..isDeleted = false
        ..relatedTransactionUuid = null;
      await expectLater(
        FinanceStorage.saveTransaction(disguised),
        throwsStateError,
      );
      expect(
        (await FinanceStorage.getTransaction(billUuid))!.toMap(),
        deleted.toMap(),
      );
      expect(await FinanceStorage.getPaidLoanInstallments(), isEmpty);
      await FinanceStorage.setLoanInstallmentPaid(
        paid.uuid,
        true,
        paymentMethodUuid: _cash,
      );
      expect((await FinanceStorage.getTransactions()).single.uuid, billUuid);
      expect(
        (await FinanceStorage.getPaidLoanInstallments()).single.uuid,
        paid.uuid,
      );
    });

    test('旧版本错误恢复的利息仍可删除清理', () async {
      final paid = await _payLoan();
      await FinanceStorage.setLoanInstallmentPaid(paid.uuid, false);
      await db.update(
        'finance_transactions',
        {'is_deleted': 0},
        where: 'uuid = ?',
        whereArgs: [paid.interestTransactionUuid],
      );
      await FinanceStorage.deleteTransaction(paid.interestTransactionUuid!);
      expect(await FinanceStorage.getTransactions(), isEmpty);
      expect(await FinanceStorage.getPaidLoanInstallments(), isEmpty);
    });

    for (final recycled in [false, true]) {
      test('有效还款的误删利息可恢复，贷款已进回收站=$recycled', () async {
        final paid = await _payLoan();
        if (recycled) await FinanceStorage.deleteLoan(paid.loanUuid);
        final repayment = (await FinanceStorage.getLoanInstallment(
          paid.uuid,
          includeDeleted: true,
        ))!;
        await db.update(
          'finance_transactions',
          {'is_deleted': 1},
          where: 'uuid = ?',
          whereArgs: [paid.interestTransactionUuid],
        );
        await FinanceStorage.restoreTransaction(paid.interestTransactionUuid!);
        expect(
          (await FinanceStorage.getTransactions()).single.amountMinor,
          paid.interestMinor,
        );
        expect(
          (await FinanceStorage.getLoanInstallment(
            paid.uuid,
            includeDeleted: true,
          ))!.toMap(),
          repayment.toMap(),
        );
        expect(
          (await FinanceStorage.getPaidLoanInstallments()).single.uuid,
          paid.uuid,
        );
      });
    }

    test('备份重建UUID后的旧利息不能与重新还款生成的新利息同时恢复', () async {
      final paid = await _payLoan();
      final backup = await FinanceStorage.getExportBundle();
      await db.delete('finance_transactions');
      await db.delete('finance_loan_installments');
      await db.delete('finance_loans');
      await FinanceStorage.importBundle(
        backup,
        remapUuid: (uuid) => 'restored-$uuid',
      );
      final importedUuid = 'restored-${paid.interestTransactionUuid}';
      final installmentUuid = 'restored-${paid.uuid}';
      expect(
        (await FinanceStorage.getTransaction(importedUuid))!
            .relatedTransactionUuid,
        installmentUuid,
      );
      await FinanceStorage.setLoanInstallmentPaid(installmentUuid, false);
      await FinanceStorage.setLoanInstallmentPaid(
        installmentUuid,
        true,
        paymentMethodUuid: _cash,
      );
      final repayment = (await FinanceStorage.getLoanInstallment(
        installmentUuid,
      ))!;
      expect(repayment.interestTransactionUuid, isNot(importedUuid));
      await expectLater(
        FinanceStorage.restoreTransaction(importedUuid),
        throwsStateError,
      );
      expect(
        (await FinanceStorage.getTransaction(importedUuid))!.isDeleted,
        true,
      );
      expect(
        (await FinanceStorage.getTransactions()).single.uuid,
        repayment.interestTransactionUuid,
      );
    });

    test('旧分期形式的利息恢复和整组删除也受还款校验，失败整组回滚', () async {
      final paid = await _payLoan();
      await FinanceStorage.setLoanInstallmentPaid(paid.uuid, false);
      const group = 'legacy-interest-group';
      await db.update(
        'finance_transactions',
        {
          'installment_group_uuid': group,
          'installment_index': 2,
          'installment_count': 2,
        },
        where: 'uuid = ?',
        whereArgs: [paid.interestTransactionUuid],
      );
      final other = FinanceTransaction(
        uuid: 'legacy-other-bill',
        amountMinor: 1000,
        transactionDate: '2026-09-01',
        installmentGroupUuid: group,
        installmentIndex: 1,
        installmentCount: 2,
        isDeleted: true,
      );
      await db.insert('finance_transactions', other.toMap());
      await expectLater(
        FinanceStorage.restoreInstallmentGroup(group),
        throwsStateError,
      );
      expect(
        (await FinanceStorage.getTransaction(other.uuid))!.isDeleted,
        true,
      );
      expect(await FinanceStorage.getTransactions(), isEmpty);
      await FinanceStorage.setLoanInstallmentPaid(paid.uuid, true);
      await FinanceStorage.restoreTransaction(other.uuid);
      await expectLater(
        FinanceStorage.deleteInstallmentGroup(group),
        throwsStateError,
      );
      expect(
        (await FinanceStorage.getTransaction(other.uuid))!.isDeleted,
        false,
      );
      expect(
        (await FinanceStorage.getTransaction(paid.interestTransactionUuid!))!
            .isDeleted,
        false,
      );
    });
  });

  testWidgets('回收站拒绝恢复已撤销还款的利息，账户余额不变', (tester) async {
    _configureView(tester);
    final db = (await tester.runAsync(_openDatabase))!;
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    final now = DateTime.now();
    final paid = (await tester.runAsync(() async {
      final snapshot = now.subtract(const Duration(hours: 2));
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'cash-snapshot',
          monthKey: financeMonthKey(snapshot),
          paymentMethodUuid: _cash,
          amountMinor: 50000,
          balanceSnapshotAt: snapshot.millisecondsSinceEpoch,
          createdAt: snapshot.millisecondsSinceEpoch,
          updatedAt: snapshot.millisecondsSinceEpoch,
        ).toMap(),
      );
      final paid = await _payLoan();
      await FinanceStorage.setLoanInstallmentPaid(paid.uuid, false);
      return paid;
    }))!;
    await _pumpScreen(
      tester,
      FinanceBudgetScreen(initialMonth: now, clock: () => now),
    );
    expect(find.text('当前余额 ¥500.00'), findsOneWidget);
    await _pumpScreen(tester, const FinanceTrashScreen());
    final restore = find.byKey(
      ValueKey(
        'finance-trash-restore-transaction-${paid.interestTransactionUuid}',
      ),
    );
    await tester.ensureVisible(restore);
    await tester.pumpAndSettle();
    await tester.tap(restore);
    await _waitFor(
      tester,
      () => find.textContaining('关联还款已撤销').evaluate().isNotEmpty,
    );
    expect(find.text('账单已恢复'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(
      (await tester.runAsync(
        () => FinanceStorage.getTransaction(paid.interestTransactionUuid!),
      ))!.isDeleted,
      true,
    );
    expect(
      (await tester.runAsync(
        () => FinanceStorage.getLoanInstallment(paid.uuid),
      ))!.isPaid,
      false,
    );
    await _pumpScreen(
      tester,
      FinanceBudgetScreen(initialMonth: now, clock: () => now),
    );
    expect(find.text('当前余额 ¥500.00'), findsOneWidget);
  });

  testWidgets('回收站显示余额实际对应的年月日和时间，删除不改变新旧格式快照', (tester) async {
    _configureView(tester);
    final db = (await tester.runAsync(_openDatabase))!;
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await tester.runAsync(() async {
      final snapshotAt = DateTime(2026, 9, 10, 12, 34).millisecondsSinceEpoch;
      final legacyAt = DateTime(2026, 9, 11, 9, 5).millisecondsSinceEpoch;
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'explicit-trash-snapshot',
          monthKey: '2026-09',
          paymentMethodUuid: _cash,
          amountMinor: 10000,
          balanceSnapshotAt: snapshotAt,
          createdAt: snapshotAt,
          updatedAt: DateTime(2026, 9, 20).millisecondsSinceEpoch,
        ).toMap(),
      );
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'legacy-trash-snapshot',
          monthKey: '2026-09',
          paymentMethodUuid: _wechat,
          amountMinor: 20000,
          createdAt: legacyAt,
          updatedAt: legacyAt,
        ).toMap(),
      );
      await FinanceStorage.deleteBudget('explicit-trash-snapshot');
      await FinanceStorage.deleteBudget('legacy-trash-snapshot');
    });
    await _pumpScreen(tester, const FinanceTrashScreen());
    expect(find.text('2026-09 · 余额对应时间 2026年9月10日 12:34'), findsOneWidget);
    expect(find.text('2026-09 · 余额对应时间 2026年9月11日 09:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('利息编辑锁定金额和账户，保留备注并能打开还款记录', (tester) async {
    final db = (await tester.runAsync(_openDatabase))!;
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    final paid = (await tester.runAsync(_payLoan))!;
    final interest = (await tester.runAsync(
      () => FinanceStorage.getTransaction(paid.interestTransactionUuid!),
    ))!;
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FinanceEntryScreen(transaction: interest),
                ),
              ),
              child: const Text('编辑利息'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑利息'));
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('finance-linked-repayment'))
          .evaluate()
          .isNotEmpty,
    );
    final amount = find.byKey(const ValueKey('finance-amount-field'));
    await tester.tap(amount);
    await tester.pumpAndSettle();
    expect(find.text('金额计算器'), findsNothing);
    final payment = find.byKey(
      const ValueKey('finance-payment-finance-system-payment-cash'),
    );
    await tester.ensureVisible(payment);
    await tester.pumpAndSettle();
    await tester.tap(payment);
    await tester.pumpAndSettle();
    expect(find.text('选择付款方式'), findsNothing);
    final note = find.byKey(const ValueKey('finance-note-field'));
    await tester.ensureVisible(note);
    await tester.enterText(note, '界面备注');
    await tester.tap(find.text('保存'));
    await _waitFor(
      tester,
      () => find.byType(FinanceEntryScreen).evaluate().isEmpty,
    );
    final saved = (await tester.runAsync(
      () => FinanceStorage.getTransaction(interest.uuid),
    ))!;
    expect(saved.note, '界面备注');
    expect(saved.amountMinor, paid.interestMinor);
    expect(saved.paymentMethodUuid, paid.paymentMethodUuid);
    await tester.tap(find.text('编辑利息'));
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('finance-linked-repayment'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('finance-linked-repayment')));
    await _waitFor(
      tester,
      () =>
          find.byType(FinanceLoanDetailScreen).evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(find.text('修改还款账户或时间'), findsOneWidget);
    await tester.tap(find.text('修改还款账户或时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finance-loan-payment-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('微信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finance-loan-payment-save')));
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('finance-loan-payment-save'))
          .evaluate()
          .isEmpty,
    );
    await tester.pageBack();
    await _waitFor(
      tester,
      () => find
          .byKey(
            const ValueKey('finance-payment-finance-system-payment-wechat'),
          )
          .evaluate()
          .isNotEmpty,
    );
    await tester.ensureVisible(note);
    await tester.enterText(note, '还款修改后的备注');
    await tester.tap(find.text('保存'));
    await _waitFor(
      tester,
      () => find.byType(FinanceEntryScreen).evaluate().isEmpty,
    );
    final updated = (await tester.runAsync(
      () => FinanceStorage.getTransaction(interest.uuid),
    ))!;
    expect(updated.paymentMethodUuid, _wechat);
    expect(updated.note, '还款修改后的备注');
    expect(tester.takeException(), isNull);
  });
}
