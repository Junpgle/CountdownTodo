@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_automation_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_budget_entry_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_budget_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_entry_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_loan_entry_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_loan_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_trash_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/widgets/finance_catalog_editor.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _month = DateTime(2026, 9);

FinanceLoan _loan() => FinanceLoan(
      uuid: 'test-loan',
      name: '电脑分期',
      lender: '测试出借方',
      principalMinor: 120000,
      annualInterestRateBps: 400,
      termMonths: 3,
      startDate: '2026-09-01',
      repaymentDay: 15,
      note: '备注保留',
    );

FinanceBudget _budget() => FinanceBudget(
    uuid: 'test-budget',
    monthKey: '2026-09',
    amountMinor: 500000,
    note: '本月总预算');

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _field(String value) =>
    find.descendant(of: _key(value), matching: find.byType(TextField));

bool _hasFocusedEditable(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .any((field) => field.focusNode.hasFocus);

Future<Database> _seed(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final db = (await tester.runAsync(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    await db.insert('finance_categories',
        FinanceCategory(uuid: 'test-food', name: '日常餐饮', icon: '🍜').toMap());
    await db.insert('finance_budgets', _budget().toMap());
    await db.insert(
        'finance_budgets',
        FinanceBudget(
                uuid: 'test-category-budget',
                monthKey: '2026-09',
                categoryUuid: 'test-food',
                amountMinor: 120000)
            .toMap());
    await db.insert(
        'finance_budgets',
        FinanceBudget(
                uuid: 'deleted-budget',
                monthKey: '2026-08',
                amountMinor: 400000,
                isDeleted: true)
            .toMap());
    final loan = _loan();
    await db.insert('finance_loans', loan.toMap());
    final schedule = FinanceLoanCalculator.generate(
        principalMinor: loan.principalMinor,
        annualInterestRateBps: loan.annualInterestRateBps,
        termMonths: loan.termMonths,
        startDate: dateFromKey(loan.startDate),
        repaymentDay: loan.repaymentDay);
    for (final item in schedule) {
      await db.insert(
          'finance_loan_installments',
          FinanceLoanInstallment(
            uuid: 'test-installment-${item.index}',
            loanUuid: loan.uuid,
            installmentIndex: item.index,
            dueDate: item.dueDate,
            paymentMinor: item.paymentMinor,
            principalMinor: item.principalMinor,
            interestMinor: item.interestMinor,
            remainingPrincipalMinor: item.remainingPrincipalMinor,
            isPaid: item.index == 1,
          ).toMap());
    }
    await db.insert(
        'finance_recurring_rules',
        FinanceRecurringRule(
                uuid: 'test-rent',
                name: '每月房租',
                amountMinor: 250000,
                dayOfMonth: 15,
                startDate: '2026-01-01')
            .toMap());
    await db.insert(
        'finance_entry_templates',
        FinanceEntryTemplate(
                uuid: 'test-breakfast',
                name: '工作日早餐',
                amountMinor: 1800,
                categoryUuid: 'test-food')
            .toMap());
    for (var i = 1; i <= 2; i++) {
      await db.insert(
          'finance_transactions',
          FinanceTransaction(
            uuid: 'deleted-installment-$i',
            type: FinanceTransactionType.expense,
            amountMinor: 6000,
            categoryUuid: 'test-food',
            transactionDate: '2026-09-01',
            merchant: '旧分期账单',
            installmentGroupUuid: 'deleted-group',
            installmentIndex: i,
            installmentCount: 2,
            installmentTotalMinor: 12000,
            isDeleted: true,
          ).toMap());
    }
    return db;
  }))!;
  addTearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });
  return db;
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('页面未在限定时间内完成数据库操作');
}

Future<void> _pump(WidgetTester tester, Widget screen,
    {Size size = const Size(390, 844),
    double scale = 1,
    Brightness brightness = Brightness.light,
    double keyboard = 0}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: brightness)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard)),
      child: child!,
    ),
    home: screen,
  ));
  await _waitFor(
      tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
  }
  // Keep controls below the transparent top-bar layer after pages begin
  // behind their app bars; the default alignment can place them at y=0.
  await Scrollable.ensureVisible(
    finder.evaluate().first,
    alignment: 0.2,
    duration: Duration.zero,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _top(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();

  testWidgets('记账分类先选大类，再选小类并支持现场新增', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, const FinanceEntryScreen());

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final entryList = tester.widget<ListView>(find.byType(ListView).first);
    final entryPadding = entryList.padding! as EdgeInsets;
    expect(scaffold.extendBodyBehindAppBar, isTrue);
    expect(find.byType(FloatingGlassTopBarContentFade), findsOneWidget);
    expect(entryPadding.top, greaterThan(kToolbarHeight));

    const categoryField =
        ValueKey('finance-category-FinanceTransactionType.expense-test-food');
    await _tap(tester, find.byKey(categoryField));
    expect(find.text('选择大类'), findsOneWidget);
    expect(find.text('奶茶'), findsNothing);

    await _tap(tester, find.text('餐饮').last);
    expect(find.text('餐饮 · 选择小类'), findsOneWidget);
    expect(find.text('奶茶'), findsOneWidget);
    expect(find.byTooltip('新增小类'), findsOneWidget);

    await _tap(tester, find.text('奶茶'));
    await tester.pumpAndSettle();
    expect(find.text('餐饮 - 奶茶'), findsOneWidget);

    const milkTeaField = ValueKey(
        'finance-category-FinanceTransactionType.expense-finance-system-category-food-milk-tea');
    await _tap(tester, find.byKey(milkTeaField));
    await _tap(tester, find.text('餐饮').last);
    await _tap(tester, find.byTooltip('新增小类'));
    expect(
        find.byKey(const ValueKey('finance-catalog-parent')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('finance-catalog-name')), '夜宵');
    await _tap(tester, find.byKey(const ValueKey('finance-catalog-save')));
    await _waitFor(
      tester,
      () =>
          find.byType(FinanceCatalogEditor).evaluate().isEmpty &&
          find.byTooltip('新增小类').evaluate().isEmpty,
    );
    expect(find.text('餐饮 - 夜宵'), findsOneWidget);
    final rows = (await tester.runAsync(() => db.query(
          'finance_categories',
          where: 'name = ?',
          whereArgs: ['夜宵'],
        )))!;
    expect(rows.single['parent_uuid'], 'finance-system-category-food');
    expect(tester.takeException(), isNull);
  });

  testWidgets('记账选择分类后不会重新唤起键盘', (tester) async {
    await _seed(tester);
    await _pump(tester, const FinanceEntryScreen());
    expect(_hasFocusedEditable(tester), isFalse);

    await tester.showKeyboard(find.byType(EditableText).first);
    await tester.pump();
    expect(_hasFocusedEditable(tester), isTrue);

    const categoryField =
        ValueKey('finance-category-FinanceTransactionType.expense-test-food');
    await _tap(tester, find.byKey(categoryField));
    await _tap(tester, find.text('餐饮').last);
    await _tap(tester, find.text('奶茶'));
    await tester.pumpAndSettle();

    expect(_hasFocusedEditable(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记一笔金额打开内置计算器并回填可编辑计算结果', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, const FinanceEntryScreen());

    await _tap(tester, _key('finance-note-field'));
    await tester.enterText(_key('finance-note-field'), '晚餐');

    final amountField = find.byKey(const ValueKey('finance-amount-field'));
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
                of: amountField, matching: find.byType(EditableText)),
          )
          .readOnly,
      isTrue,
    );
    await _tap(tester, amountField);
    expect(find.text('金额计算器'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('finance-calculator-key-clear')),
        matching: find.text('清除'),
      ),
      findsOneWidget,
    );

    Future<void> tapCalculatorKey(String keyName) async {
      await _tap(
        tester,
        find.byKey(ValueKey('finance-calculator-key-$keyName')),
      );
    }

    await tapCalculatorKey('1');
    await tapCalculatorKey('2');
    await tapCalculatorKey('add');
    await tapCalculatorKey('3');
    await tapCalculatorKey('equals');
    expect(find.text('使用结果 ¥15'), findsOneWidget);

    await tapCalculatorKey('backspace');
    await tapCalculatorKey('4');
    await tapCalculatorKey('equals');
    expect(find.text('使用结果 ¥16'), findsOneWidget);

    await _tap(
        tester, find.byKey(const ValueKey('finance-calculator-use-result')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(amountField).controller!.text,
      '16',
    );
    expect(
      tester.widget<TextFormField>(_key('finance-note-field')).controller!.text,
      '晚餐\n计算：12+4 = 16',
    );
    expect(_hasFocusedEditable(tester), isFalse);

    await _tap(tester, amountField);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('finance-calculator-expression')),
          )
          .controller!
          .text,
      '12+4',
    );
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await _tap(tester, _key('finance-merchant-field'));
    await tester.enterText(_key('finance-merchant-field'), '便利店');
    await _tap(tester, find.text('保存账单'));
    await _waitFor(
      tester,
      () => find.byType(FinanceEntryScreen).evaluate().isEmpty,
    );
    final rows = await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'merchant = ?',
        whereArgs: ['便利店'],
      ),
    );
    expect(rows, hasLength(1));
    expect(rows!.single['merchant'], '便利店');
    expect(rows.single['note'], '晚餐\n计算：12+4 = 16');
    expect(tester.takeException(), isNull);
  });

  testWidgets('商家和备注输入时表单会为键盘留出可滚动空间', (tester) async {
    await _seed(tester);
    await _pump(
      tester,
      const FinanceEntryScreen(),
      size: const Size(390, 844),
      keyboard: 240,
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.resizeToAvoidBottomInset, isTrue);
    final noteField = _key('finance-note-field');
    await _tap(tester, noteField);
    expect(
      tester.getBottomLeft(noteField).dy,
      lessThanOrEqualTo(844 - 240),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('自然语言记账支持多笔描述并先逐笔确认', (tester) async {
    await _seed(tester);
    await _pump(tester, const FinanceEntryScreen());
    await tester.enterText(
      find.byKey(const ValueKey('finance-quick-entry-input')),
      '今天早餐 8 元，微信；中午午餐 25 元，支付宝',
    );
    await _tap(tester, find.text('识别账单'));

    expect(find.text('识别到 2 笔账单'), findsOneWidget);
    expect(find.textContaining('· 早餐 · 早餐 · 微信'), findsOneWidget);
    expect(find.textContaining('· 午餐 ·'), findsOneWidget);
    expect(find.text('逐笔确认'), findsOneWidget);

    await _tap(tester, find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(find.text('识别到 2 笔账单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义大类也可以新增自定义小类', (tester) async {
    final db = await _seed(tester);
    await tester.runAsync(() => FinanceStorage.saveCategory(FinanceCategory(
          uuid: 'test-food-existing-child',
          name: '外卖',
          parentUuid: 'test-food',
          sortOrder: 1,
        )));
    await _pump(tester, const FinanceEntryScreen());

    const categoryField =
        ValueKey('finance-category-FinanceTransactionType.expense-test-food');
    await _tap(tester, find.byKey(categoryField));
    expect(find.text('日常餐饮'), findsWidgets);
    expect(find.text('外卖'), findsNothing);

    await _tap(tester, find.text('日常餐饮').last);
    expect(find.text('日常餐饮 · 选择小类'), findsOneWidget);
    expect(find.text('外卖'), findsOneWidget);
    await _tap(tester, find.byTooltip('新增小类'));
    await tester.enterText(
        find.byKey(const ValueKey('finance-catalog-name')), '夜宵');
    await _tap(tester, find.byKey(const ValueKey('finance-catalog-save')));
    await _waitFor(
      tester,
      () =>
          find.byType(FinanceCatalogEditor).evaluate().isEmpty &&
          find.byTooltip('新增小类').evaluate().isEmpty,
    );

    expect(find.text('日常餐饮 - 夜宵'), findsOneWidget);
    final rows = (await tester.runAsync(() => db.query(
          'finance_categories',
          where: 'uuid = ?',
          whereArgs: ['test-food-existing-child'],
        )))!;
    expect(rows.single['parent_uuid'], 'test-food');
    final customRows = (await tester.runAsync(() => db.query(
          'finance_categories',
          where: 'name = ?',
          whereArgs: ['夜宵'],
        )))!;
    expect(customRows.single['parent_uuid'], 'test-food');
    expect(tester.takeException(), isNull);
  });

  testWidgets('预算卡片直接编辑并保存，范围和备注保持不变', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, FinanceBudgetScreen(initialMonth: _month),
        size: const Size(1100, 1000));
    await _tap(tester, _key('finance-budget-card-test-budget'));
    await _waitFor(
        tester, () => _key('finance-budget-amount').evaluate().isNotEmpty);
    await tester.enterText(_field('finance-budget-amount'), '4500');
    await _tap(tester, find.text('保存预算'));
    await _waitFor(
        tester,
        () =>
            find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty);
    final rows = (await tester.runAsync(() => db.query('finance_budgets',
        where: 'uuid = ?', whereArgs: ['test-budget'])))!;
    expect(rows.single['amount_minor'], 450000);
    expect(rows.single['category_uuid'], isNull);
    expect(rows.single['note'], '本月总预算');
    expect(rows.single['version'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('银行卡余额计入录入后的收入、退款和支出', (tester) async {
    final db = await _seed(tester);
    final now = DateTime.now();
    final snapshotAt = now
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final recordedAt = now.millisecondsSinceEpoch;
    final transactionDate = dateKey(now);
    await tester.runAsync(() async {
      await db.insert(
        'finance_payment_methods',
        FinancePaymentMethod(uuid: 'balance-card', name: '测试银行卡').toMap(),
      );
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'balance-card-budget',
          monthKey: financeMonthKey(now),
          paymentMethodUuid: 'balance-card',
          amountMinor: 10000,
          createdAt: snapshotAt,
          updatedAt: snapshotAt,
        ).toMap(),
      );
      for (final transaction in [
        FinanceTransaction(
          uuid: 'card-income',
          type: FinanceTransactionType.income,
          amountMinor: 5000,
          paymentMethodUuid: 'balance-card',
          transactionDate: transactionDate,
          createdAt: recordedAt,
        ),
        FinanceTransaction(
          uuid: 'card-expense',
          amountMinor: 2000,
          paymentMethodUuid: 'balance-card',
          transactionDate: transactionDate,
          createdAt: recordedAt,
        ),
        FinanceTransaction(
          uuid: 'card-refund',
          type: FinanceTransactionType.refund,
          amountMinor: 500,
          paymentMethodUuid: 'balance-card',
          transactionDate: transactionDate,
          createdAt: recordedAt,
        ),
        FinanceTransaction(
          uuid: 'unassigned-income',
          type: FinanceTransactionType.income,
          amountMinor: 100000,
          transactionDate: transactionDate,
          createdAt: recordedAt,
        ),
      ]) {
        await db.insert('finance_transactions', transaction.toMap());
      }
    });

    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: now),
      size: const Size(1100, 1000),
    );
    final card = _key('finance-budget-card-balance-card-budget');
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: card, matching: find.text('录入后净增加')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('当前余额 ¥135.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(LinearProgressIndicator)),
      findsNothing,
      reason: '付款方式余额允许收入超过快照金额，预算进度条不能表示余额变化',
    );

    await tester.runAsync(() async {
      final income =
          (await FinanceStorage.getTransaction('unassigned-income'))!
            ..paymentMethodUuid = 'balance-card';
      income.markAsChanged();
      await FinanceStorage.saveTransaction(income);
    });
    await _waitFor(
      tester,
      () => find
          .descendant(of: card, matching: find.text('当前余额 ¥1,135.00'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.runAsync(
      () => FinanceStorage.deleteTransaction('unassigned-income'),
    );
    await _waitFor(
      tester,
      () => find
          .descendant(of: card, matching: find.text('当前余额 ¥135.00'))
          .evaluate()
          .isNotEmpty,
    );

    await _tap(tester, card);
    await _waitFor(
      tester,
      () => _key('finance-budget-amount').evaluate().isNotEmpty,
    );
    await _tap(tester, find.text('保存余额'));
    await _waitFor(
      tester,
      () => find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    expect(
      find.descendant(of: card, matching: find.text('当前余额 ¥135.00')),
      findsOneWidget,
      reason: '未修改录入金额时，重新保存不能抹掉之后的账单变化',
    );

    await tester.runAsync(() async {
      await FinanceStorage.deleteBudget('balance-card-budget');
      await FinanceStorage.restoreBudget('balance-card-budget');
    });
    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: now),
      size: const Size(1100, 1000),
    );
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: card, matching: find.text('当前余额 ¥135.00')),
      findsOneWidget,
      reason: '从回收站恢复余额记录不能重置快照时间',
    );

    await tester.runAsync(() => FinanceStorage.saveTransaction(
          FinanceTransaction(
            uuid: 'later-card-income',
            type: FinanceTransactionType.income,
            amountMinor: 1000,
            paymentMethodUuid: 'balance-card',
            transactionDate: transactionDate,
          ),
        ));
    await _waitFor(
      tester,
      () => find
          .descendant(of: card, matching: find.text('当前余额 ¥145.00'))
          .evaluate()
          .isNotEmpty,
    );

    await _tap(tester, card);
    await _waitFor(
      tester,
      () => _key('finance-budget-snapshot-time').evaluate().isNotEmpty,
    );
    await _tap(tester, find.text('使用保存时刻'));
    await _tap(tester, find.text('保存余额'));
    await _waitFor(
      tester,
      () => find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty &&
          find
              .descendant(of: card, matching: find.text('当前余额 ¥100.00'))
              .evaluate()
              .isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('付款方式余额跨月结转并按所选月份截止时间计算', (tester) async {
    final db = await _seed(tester);
    var clockNow = DateTime.now();
    final now = clockNow;
    final previousMonth = DateTime(now.year, now.month - 1);
    final snapshotAt = DateTime(
      previousMonth.year,
      previousMonth.month,
      10,
      12,
    );
    final priorExpenseAt = DateTime(
      previousMonth.year,
      previousMonth.month,
      20,
      12,
    );
    final currentIncomeAt = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final currentExpenseAt = currentIncomeAt;
    final futureAt = clockNow.add(const Duration(minutes: 1));
    await tester.runAsync(() async {
      await db.insert(
        'finance_payment_methods',
        FinancePaymentMethod(uuid: 'carry-card', name: '跨月银行卡').toMap(),
      );
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'carry-card-budget',
          monthKey: financeMonthKey(previousMonth),
          paymentMethodUuid: 'carry-card',
          amountMinor: 10000,
          balanceSnapshotAt: snapshotAt.millisecondsSinceEpoch,
        ).toMap(),
      );
      for (final transaction in [
        FinanceTransaction(
          uuid: 'carry-same-minute-income',
          type: FinanceTransactionType.income,
          amountMinor: 800,
          paymentMethodUuid: 'carry-card',
          transactionDate: dateKey(snapshotAt),
          occurredAt: snapshotAt.millisecondsSinceEpoch,
          createdAt: snapshotAt.millisecondsSinceEpoch + 1000,
        ),
        FinanceTransaction(
          uuid: 'carry-prior-expense',
          amountMinor: 1000,
          paymentMethodUuid: 'carry-card',
          transactionDate: dateKey(priorExpenseAt),
          occurredAt: priorExpenseAt.millisecondsSinceEpoch,
          createdAt: priorExpenseAt.millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'carry-current-income',
          type: FinanceTransactionType.income,
          amountMinor: 2500,
          paymentMethodUuid: 'carry-card',
          transactionDate: dateKey(currentIncomeAt),
          occurredAt: currentIncomeAt.millisecondsSinceEpoch,
          createdAt: currentIncomeAt.millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'carry-current-expense',
          amountMinor: 500,
          paymentMethodUuid: 'carry-card',
          transactionDate: dateKey(currentExpenseAt),
          occurredAt: currentExpenseAt.millisecondsSinceEpoch,
          createdAt: currentExpenseAt.millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'carry-future-income',
          type: FinanceTransactionType.income,
          amountMinor: 10000,
          paymentMethodUuid: 'carry-card',
          transactionDate: dateKey(futureAt),
          occurredAt: futureAt.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
        ),
      ]) {
        await db.insert('finance_transactions', transaction.toMap());
      }
      final legacyBackdatedIncome = FinanceTransaction(
        uuid: 'carry-legacy-backdated-income',
        type: FinanceTransactionType.income,
        amountMinor: 700,
        paymentMethodUuid: 'carry-card',
        transactionDate: dateKey(snapshotAt.subtract(const Duration(days: 1))),
        createdAt: currentIncomeAt.millisecondsSinceEpoch,
      ).toMap()..remove('occurred_at');
      await db.insert('finance_transactions', legacyBackdatedIncome);
    });

    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: now, clock: () => clockNow),
      size: const Size(1100, 1000),
    );
    final card = _key('finance-budget-card-carry-card-budget');
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: card, matching: find.text('当前余额 ¥125.00')),
      findsOneWidget,
      reason: '余额应累计跨月收支、快照同分钟后录入的流水和补录旧账，且不应计入尚未发生的账单',
    );

    if (financeMonthKey(futureAt) == financeMonthKey(now)) {
      clockNow = clockNow.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      await _waitFor(
        tester,
        () => find
            .descendant(of: card, matching: find.text('当前余额 ¥225.00'))
            .evaluate()
            .isNotEmpty,
      );
    }

    await _tap(tester, find.byTooltip('上个月'));
    await _waitFor(
      tester,
      () => find
          .descendant(of: card, matching: find.text('该月余额 ¥98.00'))
          .evaluate()
          .isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史月份余额必须选择实际对应时间并保存到快照', (tester) async {
    final db = await _seed(tester);
    await tester.runAsync(() => db.insert(
          'finance_payment_methods',
          FinancePaymentMethod(uuid: 'past-card', name: '历史银行卡').toMap(),
        ));
    final now = DateTime.now();
    final pastMonth = DateTime(now.year, now.month - 1);
    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: pastMonth),
    );
    await _tap(tester, find.text('选择付款方式并录入余额'));
    await _tap(tester, find.text('历史银行卡'));
    await _waitFor(
      tester,
      () => find.byType(FinanceBudgetEntryScreen).evaluate().isNotEmpty &&
          _key('finance-budget-amount').evaluate().isNotEmpty,
    );
    await tester.enterText(_field('finance-budget-amount'), '100');
    await _tap(tester, find.text('保存余额'));
    expect(find.text('请先选择该月份内的余额对应时间'), findsOneWidget);
    var rows = (await tester.runAsync(() => db.query(
          'finance_budgets',
          where: 'payment_method_uuid = ?',
          whereArgs: ['past-card'],
        )))!;
    expect(rows, isEmpty);

    await _tap(tester, find.text('点击选择日期和时刻'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await _tap(tester, find.text('保存余额'));
    await _waitFor(
      tester,
      () => find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty,
    );
    rows = (await tester.runAsync(() => db.query(
          'finance_budgets',
          where: 'payment_method_uuid = ?',
          whereArgs: ['past-card'],
        )))!;
    expect(rows, hasLength(1));
    final snapshotAt = DateTime.fromMillisecondsSinceEpoch(
      rows.single['balance_snapshot_at'] as int,
    );
    expect(financeMonthKey(snapshotAt), financeMonthKey(pastMonth));
    expect(rows.single['amount_minor'], 10000);
    expect(tester.takeException(), isNull);

    final card = _key(
      'finance-budget-card-${FinanceBudget.stableUuid(
        financeMonthKey(pastMonth),
        null,
        paymentMethodUuid: 'past-card',
      )}',
    );
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: card, matching: find.text('该月余额 ¥100.00')),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await FinanceStorage.saveTransaction(FinanceTransaction(
        uuid: 'before-historical-snapshot',
        amountMinor: 500,
        paymentMethodUuid: 'past-card',
        transactionDate: dateKey(snapshotAt),
        createdAt: snapshotAt.millisecondsSinceEpoch - 60000,
      ));
      await FinanceStorage.saveTransaction(FinanceTransaction(
        uuid: 'after-historical-snapshot',
        type: FinanceTransactionType.income,
        amountMinor: 2000,
        paymentMethodUuid: 'past-card',
        transactionDate: dateKey(snapshotAt),
        createdAt: snapshotAt.millisecondsSinceEpoch + 60000,
      ));
    });
    await _waitFor(
      tester,
      () => find
          .descendant(of: card, matching: find.text('该月余额 ¥120.00'))
          .evaluate()
          .isNotEmpty,
    );
  });

  testWidgets('贷款分组表单保存后仍生成精确还款计划', (tester) async {
    final db = await _seed(tester);
    await _pump(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const FinanceLoanEntryScreen())),
                      child: const Text('新增贷款测试'),
                    ))));
    await _tap(tester, find.text('新增贷款测试'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('finance-loan-name'), '新测试贷款');
    await tester.enterText(_field('finance-loan-principal'), '1000');
    await tester.ensureVisible(_key('finance-loan-rate'));
    await tester.enterText(_field('finance-loan-rate'), '12');
    await tester.enterText(_field('finance-loan-term'), '3');
    await _tap(tester, find.text('保存贷款'));
    await _waitFor(
        tester, () => find.byType(FinanceLoanEntryScreen).evaluate().isEmpty);
    final rows = (await tester.runAsync(() =>
        db.query('finance_loans', where: 'name = ?', whereArgs: ['新测试贷款'])))!;
    expect(rows.single['principal_minor'], 100000);
    expect(rows.single['annual_interest_rate_bps'], 1200);
    final installments = (await tester.runAsync(() => db.query(
        'finance_loan_installments',
        where: 'loan_uuid = ?',
        whereArgs: [rows.single['uuid']])))!;
    expect(installments, hasLength(3));
    expect(
        installments.fold<int>(
            0, (sum, row) => sum + (row['principal_minor'] as int)),
        100000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('还款分组与标记操作保留利息账单的生成及撤销语义', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, FinanceLoanDetailScreen(loan: _loan()));
    await _tap(tester, _key('finance-loan-filter-unpaid'));
    await tester.pumpAndSettle();
    expect(_key('finance-loan-installment-test-installment-1'), findsNothing);
    await _tap(tester, _key('finance-loan-paid-test-installment-2'));
    await _waitFor(tester, () => find.text('已还 2').evaluate().isNotEmpty);
    final paid = (await tester.runAsync(
        () => FinanceStorage.getLoanInstallment('test-installment-2')))!;
    expect(paid.isPaid, isTrue);
    expect(paid.interestTransactionUuid, isNotNull);
    final interest = (await tester.runAsync(() => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [paid.interestTransactionUuid])))!;
    expect(interest.single['amount_minor'], paid.interestMinor);
    expect(interest.single['is_deleted'], 0);
    await _top(tester);
    await _tap(tester, _key('finance-loan-filter-paid'));
    await tester.pumpAndSettle();
    await _tap(tester, _key('finance-loan-paid-test-installment-2'));
    await _waitFor(tester, () => find.text('已还 1').evaluate().isNotEmpty);
    final unpaid = (await tester.runAsync(
        () => FinanceStorage.getLoanInstallment('test-installment-2')))!;
    expect(unpaid.isPaid, isFalse);
    final deletedInterest = (await tester.runAsync(() => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [paid.interestTransactionUuid])))!;
    expect(deletedInterest.single['is_deleted'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('回收站仍可取消恢复或恢复整组分期账单', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, const FinanceTrashScreen());
    await tester.enterText(_key('finance-trash-search'), '旧分期');
    await tester.pumpAndSettle();
    await _tap(tester,
        _key('finance-trash-restore-transaction-deleted-installment-1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('只恢复本期'), findsOneWidget);
    expect(find.text('恢复整组'), findsOneWidget);
    await _tap(tester, find.text('取消'));
    await tester.pumpAndSettle();
    final before = (await tester.runAsync(() => db.query('finance_transactions',
        where: 'installment_group_uuid = ?', whereArgs: ['deleted-group'])))!;
    expect(before.every((row) => row['is_deleted'] == 1), isTrue);
    await _tap(tester,
        _key('finance-trash-restore-transaction-deleted-installment-1'));
    await tester.pump(const Duration(milliseconds: 300));
    await _tap(tester, find.text('恢复整组'));
    await _waitFor(tester, () => find.text('没有找到匹配记录').evaluate().isNotEmpty);
    final restored = (await tester.runAsync(() => db.query(
        'finance_transactions',
        where: 'installment_group_uuid = ?',
        whereArgs: ['deleted-group'])))!;
    expect(restored, hasLength(2));
    expect(restored.every((row) => row['is_deleted'] == 0), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实预算、贷款、还款、自动化和回收站适配窄屏与桌面', (tester) async {
    await _seed(tester);
    for (final narrow in [true, false]) {
      for (final screen in [
        FinanceBudgetScreen(initialMonth: _month),
        const FinanceLoanScreen(),
        FinanceLoanDetailScreen(loan: _loan()),
        const FinanceAutomationScreen(),
        const FinanceTrashScreen(),
        FinanceBudgetEntryScreen(month: _month, budget: _budget()),
      ]) {
        await _pump(
          tester,
          screen,
          size: narrow ? const Size(320, 740) : const Size(1280, 900),
          scale: narrow ? 2 : 1,
          brightness: narrow ? Brightness.dark : Brightness.light,
        );
        expect(tester.takeException(), isNull,
            reason: '${screen.runtimeType} 首屏');
        for (var i = 0; i < 9; i++) {
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -420));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${screen.runtimeType} 滚动布局');
        }
      }
    }
  });

  testWidgets('预算保存栏在键盘弹出时仍可见，非法金额不会写入', (tester) async {
    final db = await _seed(tester);
    await _pump(
        tester, FinanceBudgetEntryScreen(month: _month, budget: _budget()),
        size: const Size(320, 740), scale: 1.6, keyboard: 240);
    expect(find.text('保存预算').hitTestable(), findsOneWidget);
    await tester.enterText(_field('finance-budget-amount'), '0');
    await _tap(tester, find.text('保存预算'));
    await tester.pumpAndSettle();
    expect(find.text('请输入大于 0、最多两位小数的金额'), findsOneWidget);
    final rows = (await tester.runAsync(() => db.query('finance_budgets',
        where: 'uuid = ?', whereArgs: ['test-budget'])))!;
    expect(rows.single['amount_minor'], 500000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据加载失败有重试入口，不再显示为空列表', (tester) async {
    final db = await _seed(tester);
    await tester.runAsync(db.close);
    for (final screen in [
      const FinanceAutomationScreen(),
      const FinanceTrashScreen(),
      FinanceBudgetEntryScreen(month: _month)
    ]) {
      await _pump(tester, screen);
      expect(find.textContaining('加载失败'), findsOneWidget);
      expect(
          find.widgetWithText(
              FilledButton, screen is FinanceBudgetEntryScreen ? '重试' : '重新加载'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
