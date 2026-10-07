@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_automation_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_budget_entry_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_budget_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_entry_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_home_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_loan_entry_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_loan_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_transaction_detail_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_trash_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/features/finance/widgets/finance_amount_calculator.dart';
import 'package:countdown_todo/features/finance/widgets/finance_catalog_editor.dart';
import 'package:countdown_todo/features/finance/widgets/finance_management_widgets.dart';
import 'package:countdown_todo/features/finance/widgets/finance_today_section.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  note: '本月总预算',
);

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
    await db.insert(
      'finance_categories',
      FinanceCategory(uuid: 'test-food', name: '日常餐饮', icon: '🍜').toMap(),
    );
    await db.insert('finance_budgets', _budget().toMap());
    await db.insert(
      'finance_budgets',
      FinanceBudget(
        uuid: 'test-category-budget',
        monthKey: '2026-09',
        categoryUuid: 'test-food',
        amountMinor: 120000,
      ).toMap(),
    );
    await db.insert(
      'finance_budgets',
      FinanceBudget(
        uuid: 'deleted-budget',
        monthKey: '2026-08',
        amountMinor: 400000,
        isDeleted: true,
      ).toMap(),
    );
    final loan = _loan();
    await db.insert('finance_loans', loan.toMap());
    final schedule = FinanceLoanCalculator.generate(
      principalMinor: loan.principalMinor,
      annualInterestRateBps: loan.annualInterestRateBps,
      termMonths: loan.termMonths,
      startDate: dateFromKey(loan.startDate),
      repaymentDay: loan.repaymentDay,
    );
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
        ).toMap(),
      );
    }
    await db.insert(
      'finance_recurring_rules',
      FinanceRecurringRule(
        uuid: 'test-rent',
        name: '每月房租',
        amountMinor: 250000,
        dayOfMonth: 15,
        startDate: '2026-01-01',
      ).toMap(),
    );
    await db.insert(
      'finance_entry_templates',
      FinanceEntryTemplate(
        uuid: 'test-breakfast',
        name: '工作日早餐',
        amountMinor: 1800,
        categoryUuid: 'test-food',
      ).toMap(),
    );
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
        ).toMap(),
      );
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('页面未在限定时间内完成数据库操作');
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(390, 844),
  double scale = 1,
  Brightness brightness = Brightness.light,
  double keyboard = 0,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: screen,
    ),
  );
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
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

  testWidgets('快速重复点保存不会创建重复账单', (tester) async {
    final db = await _seed(tester);
    await _pump(
      tester,
      FinanceEntryScreen(
        initialDraft: FinanceEntryDraft(
          amountMinor: 1200,
          transactionDate: dateKey(DateTime.now()),
        ),
      ),
    );

    final saveButton = find.text('保存账单');
    await tester.ensureVisible(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.tap(saveButton);
    var rows = <Map<String, Object?>>[];
    for (var attempt = 0; attempt < 100; attempt++) {
      rows = (await tester.runAsync(
        () => db.query('finance_transactions', where: 'is_deleted = 0'),
      ))!;
      if (rows.isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 150));
    expect(rows, hasLength(1));
  });

  testWidgets('记账分类先选大类，再选小类并支持现场新增', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, const FinanceEntryScreen());

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final entryList = tester.widget<ListView>(find.byType(ListView).first);
    final entryPadding = entryList.padding! as EdgeInsets;
    expect(scaffold.extendBodyBehindAppBar, isTrue);
    expect(find.byType(FloatingGlassTopBarContentFade), findsOneWidget);
    expect(entryPadding.top, greaterThan(kToolbarHeight));

    const categoryField = ValueKey(
      'finance-category-FinanceTransactionType.expense-test-food',
    );
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
      'finance-category-FinanceTransactionType.expense-finance-system-category-food-milk-tea',
    );
    await _tap(tester, find.byKey(milkTeaField));
    await _tap(tester, find.text('餐饮').last);
    await _tap(tester, find.byTooltip('新增小类'));
    expect(
      find.byKey(const ValueKey('finance-catalog-parent')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('finance-catalog-name')),
      '夜宵',
    );
    await _tap(tester, find.byKey(const ValueKey('finance-catalog-save')));
    await _waitFor(
      tester,
      () =>
          find.byType(FinanceCatalogEditor).evaluate().isEmpty &&
          find.byTooltip('新增小类').evaluate().isEmpty,
    );
    expect(find.text('餐饮 - 夜宵'), findsOneWidget);
    final rows = (await tester.runAsync(
      () =>
          db.query('finance_categories', where: 'name = ?', whereArgs: ['夜宵']),
    ))!;
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

    const categoryField = ValueKey(
      'finance-category-FinanceTransactionType.expense-test-food',
    );
    await _tap(tester, find.byKey(categoryField));
    await _tap(tester, find.text('餐饮').last);
    await _tap(tester, find.text('奶茶'));
    await tester.pumpAndSettle();

    expect(_hasFocusedEditable(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分期表单改选收入模板后不应把收入保存成分期', (tester) async {
    final db = await _seed(tester);
    await tester.runAsync(
      () => db.insert(
        'finance_entry_templates',
        FinanceEntryTemplate(
          uuid: 'income-template',
          name: '工资收入',
          type: FinanceTransactionType.income,
          amountMinor: 300000,
        ).toMap(),
      ),
    );
    await _pump(tester, const FinanceEntryScreen());

    await _tap(tester, find.text('分期付款'));
    await _tap(tester, find.text('快捷模板'));
    await _tap(tester, find.text('工资收入'));
    expect(find.text('分期付款'), findsNothing);

    await _tap(tester, find.text('保存账单'));
    await _waitFor(
      tester,
      () => find.byType(FinanceEntryScreen).evaluate().isEmpty,
    );
    final rows = await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'type = ? AND is_deleted = 0',
        whereArgs: [FinanceTransactionType.income.name],
      ),
    );
    expect(rows, hasLength(1));
    expect(rows!.single['installment_group_uuid'], isNull);
    expect(rows.single['installment_count'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('计算器拒绝超过金额安全上限的结果并保留边界值', (tester) async {
    Future<void> pumpCalculator(String expression) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinanceAmountCalculatorSheet(
            key: ValueKey(expression),
            initialExpression: expression,
          ),
        ),
      ),
    );

    await pumpCalculator('90071992547409.92');
    var useResultButton = tester.widget<FilledButton>(
      _key('finance-calculator-use-result'),
    );
    expect(useResultButton.onPressed, isNull);
    await _tap(tester, _key('finance-calculator-key-equals'));
    expect(find.text('结果超过可记录金额上限'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpCalculator('90071992547409.91');
    useResultButton = tester.widget<FilledButton>(
      _key('finance-calculator-use-result'),
    );
    expect(useResultButton.onPressed, isNotNull);
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
              of: amountField,
              matching: find.byType(EditableText),
            ),
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
      tester,
      find.byKey(const ValueKey('finance-calculator-use-result')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(amountField).controller!.text, '16');
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
    expect(tester.getBottomLeft(noteField).dy, lessThanOrEqualTo(844 - 240));
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

  testWidgets('自然语言历史账单没有时刻时提示按录入时间估算', (tester) async {
    await _seed(tester);
    await _pump(
      tester,
      const FinanceEntryScreen(),
      size: const Size(1100, 1800),
    );
    await tester.enterText(
      find.byKey(const ValueKey('finance-quick-entry-input')),
      '昨天早餐 8 元',
    );
    await _tap(tester, find.text('识别账单'));

    expect(find.text('补充时间'), findsOneWidget);
    expect(find.text('这笔账单没有与日期匹配的发生时刻，余额计算暂按录入时间估算。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义大类也可以新增自定义小类', (tester) async {
    final db = await _seed(tester);
    await tester.runAsync(
      () => FinanceStorage.saveCategory(
        FinanceCategory(
          uuid: 'test-food-existing-child',
          name: '外卖',
          parentUuid: 'test-food',
          sortOrder: 1,
        ),
      ),
    );
    await _pump(tester, const FinanceEntryScreen());

    const categoryField = ValueKey(
      'finance-category-FinanceTransactionType.expense-test-food',
    );
    await _tap(tester, find.byKey(categoryField));
    expect(find.text('日常餐饮'), findsWidgets);
    expect(find.text('外卖'), findsNothing);

    await _tap(tester, find.text('日常餐饮').last);
    expect(find.text('日常餐饮 · 选择小类'), findsOneWidget);
    expect(find.text('外卖'), findsOneWidget);
    await _tap(tester, find.byTooltip('新增小类'));
    await tester.enterText(
      find.byKey(const ValueKey('finance-catalog-name')),
      '夜宵',
    );
    await _tap(tester, find.byKey(const ValueKey('finance-catalog-save')));
    await _waitFor(
      tester,
      () =>
          find.byType(FinanceCatalogEditor).evaluate().isEmpty &&
          find.byTooltip('新增小类').evaluate().isEmpty,
    );

    expect(find.text('日常餐饮 - 夜宵'), findsOneWidget);
    final rows = (await tester.runAsync(
      () => db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: ['test-food-existing-child'],
      ),
    ))!;
    expect(rows.single['parent_uuid'], 'test-food');
    final customRows = (await tester.runAsync(
      () =>
          db.query('finance_categories', where: 'name = ?', whereArgs: ['夜宵']),
    ))!;
    expect(customRows.single['parent_uuid'], 'test-food');
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史草稿按所选月份说明并提示未知发生时刻', (tester) async {
    await _seed(tester);
    final now = DateTime.now();
    final selectedMonth = DateTime(now.year, now.month - 1);
    final monthLabel = '${selectedMonth.year}年${selectedMonth.month}月';
    final expectedDescription = '将整笔金额一次性计入$monthLabel';
    await _pump(
      tester,
      FinanceEntryScreen(
        initialDraft: FinanceEntryDraft(
          amountMinor: 1200,
          transactionDate: dateKey(
            DateTime(selectedMonth.year, selectedMonth.month, 5),
          ),
        ),
      ),
      size: const Size(1100, 2400),
    );

    expect(find.text(expectedDescription), findsOneWidget);
    expect(find.text('将整笔金额一次性计入当前月份'), findsNothing);
    expect(find.text('补充时间'), findsOneWidget);
    expect(find.text('这笔账单没有与日期匹配的发生时刻，余额计算暂按录入时间估算。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手动选择历史日期后不沿用未经确认的当前时刻', (tester) async {
    await _seed(tester);
    await _pump(
      tester,
      const FinanceEntryScreen(),
      size: const Size(1100, 1800),
    );

    await tester.tap(find.text('账单日期'));
    await tester.pumpAndSettle();
    final previousMonthButton = find.byTooltip('Previous month');
    expect(previousMonthButton, findsOneWidget);
    await tester.tap(previousMonthButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('补充时间'), findsOneWidget);
    expect(find.text('这笔账单没有与日期匹配的发生时刻，余额计算暂按录入时间估算。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑旧账单时保留未记录的发生时刻', (tester) async {
    final db = await _seed(tester);
    final legacyDate = DateTime(2026, 9, 10);
    final transaction = FinanceTransaction.fromMap({
      'uuid': 'legacy-unknown-occurrence',
      'type': 'expense',
      'amount_minor': 1250,
      'currency_code': 'CNY',
      'category_uuid': 'test-food',
      'transaction_date': dateKey(legacyDate),
      'created_at': legacyDate.millisecondsSinceEpoch,
      'updated_at': legacyDate.millisecondsSinceEpoch,
    });
    await tester.runAsync(() => FinanceStorage.saveTransaction(transaction));

    await _pump(tester, FinanceEntryScreen(transaction: transaction));
    expect(find.text('补充时间'), findsOneWidget);
    await tester.ensureVisible(find.text('保存账单'));
    await tester.tap(find.text('保存账单'));
    var rows = <Map<String, Object?>>[];
    for (var attempt = 0; attempt < 100; attempt++) {
      rows = (await tester.runAsync(
        () => db.query(
          'finance_transactions',
          where: 'uuid = ?',
          whereArgs: [transaction.uuid],
        ),
      ))!;
      if (rows.single['version'] == 2) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(rows.single['version'], 2);
    expect(rows.single['occurred_at'], isNull);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑大额账单后原样保存不会因金额回填丢一分', (tester) async {
    final db = await _seed(tester);
    const amountMinor = maxFinanceAmountMinor - 1;
    final transaction = FinanceTransaction(
      uuid: 'edit-large-amount-exact',
      amountMinor: amountMinor,
      categoryUuid: 'test-food',
      transactionDate: dateKey(DateTime.now()),
    );
    await tester.runAsync(() => FinanceStorage.saveTransaction(transaction));

    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FinanceEntryScreen(transaction: transaction),
              ),
            ),
            child: const Text('打开大额账单'),
          ),
        ),
      ),
      size: const Size(1280, 1000),
    );
    await tester.tap(find.text('打开大额账单'));
    await _waitFor(
      tester,
      () =>
          _key('finance-amount-field').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );

    final amountField = tester.widget<TextField>(
      _field('finance-amount-field'),
    );
    expect(amountField.controller!.text, '90,071,992,547,409.90');
    expect(parseFinanceAmount(amountField.controller!.text), amountMinor);
    await _tap(tester, find.text('保存账单'));
    await _waitFor(
      tester,
      () => find.byType(FinanceEntryScreen).evaluate().isEmpty,
    );

    final row = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [transaction.uuid],
      ),
    ))!.single;
    expect(row['amount_minor'], amountMinor);
    expect(row['version'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑大额预算后原样保存不会因金额回填丢一分', (tester) async {
    final db = await _seed(tester);
    const amountMinor = maxFinanceAmountMinor - 1;
    final month = DateTime.now();
    final budget = FinanceBudget(
      uuid: 'edit-large-budget-exact',
      monthKey: financeMonthKey(month),
      amountMinor: amountMinor,
    );
    await tester.runAsync(() => db.insert('finance_budgets', budget.toMap()));

    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FinanceBudgetEntryScreen(
                  month: month,
                  budget: budget,
                ),
              ),
            ),
            child: const Text('打开大额预算'),
          ),
        ),
      ),
      size: const Size(1280, 1000),
    );
    await tester.tap(find.text('打开大额预算'));
    await _waitFor(
      tester,
      () =>
          _key('finance-budget-amount').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );

    final amountField = tester.widget<TextField>(
      _field('finance-budget-amount'),
    );
    expect(amountField.controller!.text, '90,071,992,547,409.90');
    expect(parseFinanceAmount(amountField.controller!.text), amountMinor);
    await _tap(tester, find.text('保存预算'));
    await _waitFor(
      tester,
      () => find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty,
    );

    final row = (await tester.runAsync(
      () => db.query(
        'finance_budgets',
        where: 'uuid = ?',
        whereArgs: [budget.uuid],
      ),
    ))!.single;
    expect(row['amount_minor'], amountMinor);
    expect(row['version'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑未分类账单时不自动添加默认分类', (tester) async {
    final db = await _seed(tester);
    final transaction = FinanceTransaction(
      uuid: 'edit-uncategorized-entry',
      amountMinor: 1250,
      paymentMethodUuid: 'deleted-payment-method',
      transactionDate: dateKey(DateTime.now()),
      merchant: '原本未分类',
    );
    await tester.runAsync(() => FinanceStorage.saveTransaction(transaction));

    await _pump(tester, FinanceEntryScreen(transaction: transaction));
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('已删除或未知付款方式'), findsOneWidget);
    await _tap(tester, find.text('保存账单'));
    var rows = <Map<String, Object?>>[];
    for (var attempt = 0; attempt < 100; attempt++) {
      rows = (await tester.runAsync(
        () => db.query(
          'finance_transactions',
          where: 'uuid = ?',
          whereArgs: [transaction.uuid],
        ),
      ))!;
      if (rows.single['version'] == 2) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(rows.single['version'], 2);
    expect(rows.single['category_uuid'], isNull);
    expect(rows.single['payment_method_uuid'], 'deleted-payment-method');
    expect(tester.takeException(), isNull);
  });

  testWidgets('未分类支出的新退款继续保持未分类', (tester) async {
    final db = await _seed(tester);
    final original = FinanceTransaction(
      uuid: 'uncategorized-refund-original',
      amountMinor: 5000,
      paymentMethodUuid: 'deleted-payment-method',
      transactionDate: dateKey(DateTime.now()),
      merchant: '未分类原账单',
    );
    await tester.runAsync(() => FinanceStorage.saveTransaction(original));

    await _pump(tester, FinanceEntryScreen(originalTransaction: original));
    expect(find.text('未分类'), findsOneWidget);
    await _tap(tester, find.text('保存账单'));
    var rows = <Map<String, Object?>>[];
    for (var attempt = 0; attempt < 100; attempt++) {
      rows = (await tester.runAsync(
        () => db.query(
          'finance_transactions',
          where: 'related_transaction_uuid = ?',
          whereArgs: [original.uuid],
        ),
      ))!;
      if (rows.isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(rows, hasLength(1));
    expect(rows.single['type'], FinanceTransactionType.refund.name);
    expect(rows.single['category_uuid'], isNull);
    expect(rows.single['payment_method_uuid'], 'deleted-payment-method');
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前月预算不提前统计尚未发生的未来账单', (tester) async {
    final db = await _seed(tester);
    var clockNow = DateTime(2026, 9, 15, 12);
    final now = clockNow;
    final laterToday = now.add(const Duration(hours: 1));
    final tomorrow = now.add(const Duration(days: 1));
    await tester.runAsync(() async {
      for (final transaction in [
        FinanceTransaction(
          uuid: 'budget-current-expense',
          amountMinor: 40000,
          categoryUuid: 'test-food',
          transactionDate: dateKey(now),
          occurredAt: now
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
          createdAt: now
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'budget-future-today-expense',
          amountMinor: 20000,
          categoryUuid: 'test-food',
          transactionDate: dateKey(laterToday),
          occurredAt: laterToday.millisecondsSinceEpoch,
          timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
          createdAt: now.millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'budget-future-day-expense',
          amountMinor: 150000,
          categoryUuid: 'test-food',
          transactionDate: dateKey(tomorrow),
          occurredAt: tomorrow.millisecondsSinceEpoch,
          timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
          createdAt: now.millisecondsSinceEpoch,
        ),
      ]) {
        await db.insert('finance_transactions', transaction.toMap());
      }
    });

    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: now, clock: () => clockNow),
      size: const Size(1100, 1000),
    );
    final card = _key('finance-budget-card-test-category-budget');
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: card, matching: find.text('剩余 ¥800.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('超支')),
      findsNothing,
    );

    clockNow = laterToday;
    await tester.pump(const Duration(hours: 1, seconds: 1));
    expect(
      find.descendant(of: card, matching: find.text('剩余 ¥600.00')),
      findsOneWidget,
    );

    clockNow = tomorrow;
    await tester.pump(const Duration(hours: 23, seconds: 1));
    expect(
      find.descendant(of: card, matching: find.text('超支 ¥900.00')),
      findsOneWidget,
    );
  });

  testWidgets('未来月份预算用计划用语显示待发生账单', (tester) async {
    final db = await _seed(tester);
    final now = DateTime.now();
    final futureMonth = DateTime(now.year, now.month + 1);
    final plannedAt = DateTime(futureMonth.year, futureMonth.month, 10, 12);
    await tester.runAsync(() async {
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'future-overall-budget',
          monthKey: financeMonthKey(futureMonth),
          amountMinor: 10000,
        ).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'future-planned-expense',
          amountMinor: 2000,
          transactionDate: dateKey(plannedAt),
          occurredAt: plannedAt.millisecondsSinceEpoch,
          timezoneOffsetMinutes: plannedAt.timeZoneOffset.inMinutes,
          createdAt: now.millisecondsSinceEpoch,
          merchant: '计划账单',
        ).toMap(),
      );
    });

    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: futureMonth),
      size: const Size(1100, 1000),
    );

    expect(
      find.text('${futureMonth.year}年${futureMonth.month}月总预算'),
      findsOneWidget,
    );
    expect(find.text('计划使用 ¥20.00 / ¥100.00'), findsOneWidget);
    expect(find.text('计划剩余 ¥80.00'), findsWidgets);
    expect(find.text('已使用 ¥20.00 / ¥100.00'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == '录入付款方式余额',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('未来月份预算在月初切换为实际统计', (tester) async {
    final db = await _seed(tester);
    var clockNow = DateTime(2026, 10, 31, 23, 59, 58);
    final futureMonth = DateTime(2026, 11);
    final plannedAt = DateTime(2026, 11, 15, 12);
    await tester.runAsync(() async {
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'future-month-rollover-budget',
          monthKey: financeMonthKey(futureMonth),
          amountMinor: 10000,
        ).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'future-month-rollover-expense',
          amountMinor: 2500,
          transactionDate: dateKey(plannedAt),
          occurredAt: plannedAt.millisecondsSinceEpoch,
          createdAt: clockNow.millisecondsSinceEpoch,
        ).toMap(),
      );
    });

    await _pump(
      tester,
      FinanceBudgetScreen(
        initialMonth: futureMonth,
        clock: () => clockNow,
      ),
      size: const Size(1100, 1000),
    );
    expect(find.text('计划使用 ¥25.00 / ¥100.00'), findsOneWidget);

    clockNow = DateTime(2026, 11, 1, 0, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    await _waitFor(
      tester,
      () => find.text('已使用 ¥0.00 / ¥100.00').evaluate().isNotEmpty,
    );

    expect(find.text('计划使用 ¥25.00 / ¥100.00'), findsNothing);
    expect(find.text('已使用 ¥0.00 / ¥100.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未来月份开始后重新载入账户流水', (tester) async {
    final db = await _seed(tester);
    var clockNow = DateTime(2026, 10, 31, 23, 59, 58);
    final snapshotAt = DateTime(2026, 10, 1, 9);
    final plannedAt = DateTime(2026, 11, 15, 12);
    await tester.runAsync(() async {
      await db.insert(
        'finance_payment_methods',
        FinancePaymentMethod(uuid: 'future-card', name: '跨月银行卡').toMap(),
      );
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'future-card-snapshot',
          monthKey: financeMonthKey(snapshotAt),
          paymentMethodUuid: 'future-card',
          amountMinor: 10000,
          balanceSnapshotAt: snapshotAt.millisecondsSinceEpoch,
          createdAt: snapshotAt.millisecondsSinceEpoch,
          updatedAt: snapshotAt.millisecondsSinceEpoch,
        ).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'future-card-expense',
          amountMinor: 2500,
          paymentMethodUuid: 'future-card',
          transactionDate: dateKey(plannedAt),
          occurredAt: plannedAt.millisecondsSinceEpoch,
          createdAt: clockNow.millisecondsSinceEpoch,
        ).toMap(),
      );
    });

    await _pump(
      tester,
      FinanceBudgetScreen(
        initialMonth: DateTime(2026, 11),
        clock: () => clockNow,
      ),
      size: const Size(1100, 1000),
    );
    expect(find.text('未来月份不显示余额'), findsOneWidget);

    clockNow = DateTime(2026, 11, 1, 0, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    final card = _key('finance-budget-card-future-card-snapshot');
    await _waitFor(tester, () => card.evaluate().isNotEmpty);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == '录入付款方式余额',
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );

    clockNow = DateTime(2026, 11, 15, 12, 0, 2);
    await tester.pump(const Duration(days: 15));
    await _waitFor(
      tester,
      () =>
          find
              .descendant(of: card, matching: find.text('当前余额 ¥75.00'))
              .evaluate()
              .isNotEmpty,
    );

    expect(
      find.descendant(of: card, matching: find.text('当前余额 ¥75.00')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('记账概览不提前统计本月未来发生的账单', (tester) async {
    final db = await _seed(tester);
    final now = DateTime.now();
    final pastAt = DateTime(now.year, now.month, now.day);
    final futureAt = DateTime(now.year, now.month, now.day, 23, 59, 59);
    await tester.runAsync(() async {
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'overview-past-expense',
          amountMinor: 4000,
          categoryUuid: 'test-food',
          transactionDate: dateKey(pastAt),
          occurredAt: pastAt.millisecondsSinceEpoch,
          createdAt: pastAt.millisecondsSinceEpoch,
        ).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'overview-future-expense',
          amountMinor: 9000,
          categoryUuid: 'test-food',
          transactionDate: dateKey(futureAt),
          occurredAt: futureAt.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
        ).toMap(),
      );
    });

    await _pump(tester, const FinanceHomeScreen(username: 'default'));

    expect(find.text('¥130.00'), findsNothing);
    expect(find.text('¥40.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记账首页保持打开时会在周期账单到期后自动生成', (tester) async {
    final db = await _seed(tester);
    var clockNow = DateTime(2026, 9, 15, 8, 59);
    await _pump(
      tester,
      FinanceHomeScreen(username: 'default', clock: () => clockNow),
      size: const Size(1100, 1000),
    );

    var rows = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'source = ?',
        whereArgs: [FinanceEntrySource.automation.name],
      ),
    ))!;
    expect(rows, isEmpty);

    clockNow = DateTime(2026, 9, 15, 9, 1);
    await tester.pump(const Duration(minutes: 2));
    for (var attempt = 0; attempt < 40 && rows.isEmpty; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      rows = (await tester.runAsync(
        () => db.query(
          'finance_transactions',
          where: 'source = ? AND transaction_date = ?',
          whereArgs: [FinanceEntrySource.automation.name, '2026-09-15'],
        ),
      ))!;
    }

    expect(rows, hasLength(1));
    expect(rows.single['merchant'], '每月房租');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('云端同步后已打开的账单列表会刷新', (tester) async {
    await _seed(tester);
    final now = DateTime.now();
    await _pump(
      tester,
      const FinanceHomeScreen(username: 'default'),
      size: const Size(1100, 1000),
    );
    await _tap(tester, find.text('账单').hitTestable().last);
    expect(find.text('来自另一台设备的账单'), findsNothing);

    final remoteTransaction = FinanceTransaction(
      uuid: 'remote-finance-screen-refresh',
      amountMinor: 1234,
      transactionDate: dateKey(now),
      merchant: '来自另一台设备的账单',
    );
    await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'transactions': [remoteTransaction.toMap()],
      }),
    );

    await _waitFor(
      tester,
      () => find.text('来自另一台设备的账单').evaluate().isNotEmpty,
    );
    expect(find.text('来自另一台设备的账单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未来月份概览将待发生账单标为计划数据', (tester) async {
    final now = DateTime.now();
    final futureMonth = DateTime(now.year, now.month + 1);
    final plannedAt = DateTime(futureMonth.year, futureMonth.month, 10, 12);
    final transaction = FinanceTransaction(
      uuid: 'future-overview-planned-expense',
      amountMinor: 2500,
      categoryUuid: 'test-food',
      transactionDate: dateKey(plannedAt),
      occurredAt: plannedAt.millisecondsSinceEpoch,
      timezoneOffsetMinutes: plannedAt.timeZoneOffset.inMinutes,
      createdAt: now.millisecondsSinceEpoch,
    );

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: futureMonth,
          summary: FinanceSummary.fromTransactions([transaction]),
          transactions: [transaction],
          categories: {
            'test-food': FinanceCategory(
              uuid: 'test-food',
              name: '日常餐饮',
              icon: '🍜',
            ),
          },
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );

    expect(find.text('计划净支出'), findsOneWidget);
    expect(find.text('计划总支出'), findsOneWidget);
    expect(find.text('计划支出分类'), findsOneWidget);
    expect(find.text('计划每日净支出'), findsOneWidget);
    expect(find.textContaining('平均计划净支出'), findsOneWidget);

    await _tap(tester, find.text('周视图'));
    final weeklyTitle = tester
        .widget<Text>(find.textContaining('每日净支出').first)
        .data!;
    expect(weeklyTitle, startsWith('计划'));

    await _tap(tester, find.text('日视图'));
    final dailyTitle = tester
        .widget<Text>(find.textContaining('时段净支出').first)
        .data!;
    expect(dailyTitle, startsWith('计划'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('概览在选中月份开始时切换到实际统计', (tester) async {
    final db = await _seed(tester);
    var clockNow = DateTime(2026, 10, 31, 23, 59, 58);
    final plannedAt = DateTime(2026, 11, 15, 12);
    await tester.runAsync(() async {
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'overview-next-month-planned-expense',
          amountMinor: 2500,
          categoryUuid: 'test-food',
          transactionDate: dateKey(plannedAt),
          occurredAt: plannedAt.millisecondsSinceEpoch,
          createdAt: clockNow.millisecondsSinceEpoch,
        ).toMap(),
      );
    });

    await _pump(
      tester,
      FinanceHomeScreen(username: 'default', clock: () => clockNow),
      size: const Size(1100, 1000),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('finance-overview-period-next')),
    );
    await _waitFor(
      tester,
      () => find.text('2026年11月').evaluate().isNotEmpty,
    );
    expect(find.text('计划净支出'), findsOneWidget);

    clockNow = DateTime(2026, 11, 1, 0, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    await _waitFor(
      tester,
      () =>
          find.text('计划净支出').evaluate().isEmpty &&
          find.text('净支出').evaluate().isNotEmpty,
    );

    expect(find.text('计划净支出'), findsNothing);
    expect(find.text('净支出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导出菜单按所选月份命名账单', (tester) async {
    await _seed(tester);
    final now = DateTime.now();
    final selectedMonth = DateTime(now.year, now.month - 1);
    await _pump(tester, const FinanceHomeScreen(username: 'default'));

    await _tap(
      tester,
      find.byKey(const ValueKey('finance-overview-period-previous')),
    );
    await _waitFor(
      tester,
      () => find
          .text('${selectedMonth.year}年${selectedMonth.month}月')
          .evaluate()
          .isNotEmpty,
    );
    await _tap(tester, find.byTooltip('更多操作'));

    expect(
      find.text('导出${selectedMonth.year}年${selectedMonth.month}月账单 CSV'),
      findsOneWidget,
    );
    expect(find.text('导出本月 CSV'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CSV 导出失败时向用户显示错误', (tester) async {
    await _seed(tester);
    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        throw PlatformException(
          code: 'test_storage_unavailable',
          message: '测试存储不可用',
        );
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(pathProviderChannel, null),
    );
    await _pump(tester, const FinanceHomeScreen(username: 'default'));

    await _tap(tester, find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('导出本月账单 CSV'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('导出失败：'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页记账摘要不提前计入未来账单且最近一笔显示已发生记录', (tester) async {
    final db = await _seed(tester);
    final now = DateTime.now();
    final pastAt = DateTime(now.year, now.month, now.day);
    final futureAt = DateTime(now.year, now.month, now.day, 23, 59, 59);
    await tester.runAsync(() async {
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'today-section-past-expense',
          amountMinor: 4000,
          categoryUuid: 'test-food',
          transactionDate: dateKey(pastAt),
          occurredAt: pastAt.millisecondsSinceEpoch,
          createdAt: pastAt.millisecondsSinceEpoch,
          merchant: '过去支出',
        ).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'today-section-future-expense',
          amountMinor: 9000,
          categoryUuid: 'test-food',
          transactionDate: dateKey(futureAt),
          occurredAt: futureAt.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          merchant: '未来支出',
        ).toMap(),
      );
    });

    await _pump(
      tester,
      const Scaffold(body: FinanceTodaySection(username: 'default')),
    );

    expect(find.text('本月结余'), findsOneWidget);
    expect(find.text('1 笔'), findsOneWidget);
    expect(find.text('¥130.00'), findsNothing);
    expect(find.text('过去支出'), findsOneWidget);
    expect(find.text('未来支出'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页仅有未来账单时显示待发生记录而不是空账单提示', (tester) async {
    final db = await _seed(tester);
    var now = DateTime(2026, 10, 7, 12);
    final futureAt = DateTime(2026, 10, 7, 20);
    await tester.runAsync(() async {
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'today-section-only-future-expense',
          amountMinor: 6500,
          categoryUuid: 'test-food',
          transactionDate: dateKey(futureAt),
          occurredAt: futureAt.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          merchant: '计划晚餐',
        ).toMap(),
      );
    });

    await _pump(
      tester,
      Scaffold(
        body: FinanceTodaySection(username: 'default', clock: () => now),
      ),
    );

    expect(find.text('0 笔'), findsOneWidget);
    expect(find.text('本月还没有账单，点击开始记录'), findsNothing);
    expect(find.text('计划晚餐'), findsOneWidget);
    expect(find.textContaining('下一笔待发生 · 2026-10-07'), findsOneWidget);
    expect(find.text('-¥65.00'), findsOneWidget);

    now = futureAt;
    await tester.pump(const Duration(hours: 8, milliseconds: 2));
    await _waitFor(
      tester,
      () => find.textContaining('最近一笔 · 2026-10-07').evaluate().isNotEmpty,
    );

    expect(find.textContaining('下一笔待发生'), findsNothing);
    expect(find.text('本月还没有账单，点击开始记录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页最近一笔按有效发生时刻排序旧账单', (tester) async {
    final db = await _seed(tester);
    final now = DateTime.now();
    final legacyCreatedAt = now.subtract(const Duration(hours: 1));
    final earlierAt = now.subtract(const Duration(hours: 2));
    await tester.runAsync(() async {
      await db.insert(
        'finance_transactions',
        FinanceTransaction.fromMap({
          'uuid': 'today-section-legacy-latest',
          'amount_minor': 3000,
          'transaction_date': dateKey(now),
          'created_at': legacyCreatedAt.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
          'merchant': '时间未知但较晚',
        }).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'today-section-known-earlier',
          amountMinor: 2000,
          transactionDate: dateKey(now),
          occurredAt: earlierAt.millisecondsSinceEpoch,
          createdAt: earlierAt.millisecondsSinceEpoch,
          updatedAt: earlierAt.millisecondsSinceEpoch,
          merchant: '有时刻但较早',
        ).toMap(),
      );
    });

    await _pump(
      tester,
      const Scaffold(body: FinanceTodaySection(username: 'default')),
    );

    expect(find.text('时间未知但较晚'), findsOneWidget);
    expect(find.text('有时刻但较早'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页记账小卡明确标出退款后的净支出', (tester) async {
    final db = await _seed(tester);
    final now = DateTime.now();
    final occurredAt = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    final originalUuid = 'today-section-previous-month-expense';
    await tester.runAsync(() async {
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: originalUuid,
          amountMinor: 5000,
          transactionDate: dateKey(DateTime(now.year, now.month - 1, 15)),
          occurredAt: occurredAt - const Duration(days: 20).inMilliseconds,
          createdAt: occurredAt - const Duration(days: 20).inMilliseconds,
          merchant: '上月消费',
        ).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'today-section-previous-month-refund',
          type: FinanceTransactionType.refund,
          amountMinor: 5000,
          relatedTransactionUuid: originalUuid,
          transactionDate: dateKey(now),
          occurredAt: occurredAt,
          createdAt: now.millisecondsSinceEpoch,
          merchant: '本月退款',
        ).toMap(),
      );
    });

    await _pump(
      tester,
      const Scaffold(body: FinanceTodaySection(username: 'default')),
    );

    expect(find.text('净支出'), findsOneWidget);
    expect(find.text('支出'), findsNothing);
    expect(find.text(formatFinanceAmount(-5000)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页记账摘要跨月后自动刷新到新月份', (tester) async {
    final db = await _seed(tester);
    var clockNow = DateTime(2026, 10, 31, 23, 59, 58);
    final nextMonthAt = DateTime(2026, 11);
    await tester.runAsync(() async {
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'today-section-before-month-rollover',
          amountMinor: 2000,
          transactionDate: dateKey(clockNow),
          occurredAt: clockNow.millisecondsSinceEpoch,
          createdAt: clockNow.millisecondsSinceEpoch,
          merchant: '十月账单',
        ).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'today-section-after-month-rollover',
          type: FinanceTransactionType.income,
          amountMinor: 3000,
          transactionDate: dateKey(nextMonthAt),
          occurredAt: nextMonthAt.millisecondsSinceEpoch,
          createdAt: clockNow.millisecondsSinceEpoch,
          merchant: '十一月收入',
        ).toMap(),
      );
    });

    await _pump(
      tester,
      Scaffold(
        body: FinanceTodaySection(username: 'default', clock: () => clockNow),
      ),
    );
    expect(find.text('十月账单'), findsOneWidget);
    expect(find.text('十一月收入'), findsNothing);

    clockNow = DateTime(2026, 11, 1, 0, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    await _waitFor(tester, () => find.text('十一月收入').evaluate().isNotEmpty);

    expect(find.text('十月账单'), findsNothing);
    expect(find.text('十一月收入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记账概览跨月后更新所选月份状态', (tester) async {
    await _seed(tester);
    var clockNow = DateTime(2026, 10, 31, 23, 59, 58);
    await _pump(
      tester,
      FinanceHomeScreen(username: 'default', clock: () => clockNow),
      size: const Size(1100, 1000),
    );

    expect(find.text('本月没有可展示的净支出分类'), findsOneWidget);
    clockNow = DateTime(2026, 11, 1, 0, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    await _waitFor(
      tester,
      () => find.text('2026年10月没有可展示的净支出分类').evaluate().isNotEmpty,
    );

    expect(find.text('本月没有可展示的净支出分类'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('夏令时回拨日以及月底账单在日周月视图中都能显示', (tester) async {
    final spendingLabel = DateTime(2026, 11).isAfter(DateTime.now())
        ? '计划净支出'
        : '净支出';
    final transactions = [
      FinanceTransaction(
        uuid: 'dst-fallback-first-day',
        amountMinor: 2000,
        transactionDate: '2026-11-01',
      ),
      FinanceTransaction(
        uuid: 'dst-fallback-month-end',
        amountMinor: 3000,
        transactionDate: '2026-11-30',
      ),
    ];
    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: DateTime(2026, 11),
          summary: FinanceSummary.fromTransactions(transactions),
          transactions: transactions,
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
      size: const Size(1100, 1200),
    );

    await _tap(tester, find.text('日视图'));
    expect(find.byTooltip('未知时刻 · $spendingLabel ¥20.00'), findsOneWidget);

    await _tap(tester, find.text('周视图'));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('11月1日') == true &&
            widget.message?.contains('$spendingLabel ¥20.00') == true,
      ),
      findsOneWidget,
    );

    await _tap(tester, find.text('月视图'));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('11月30日') == true &&
            widget.message?.contains('$spendingLabel ¥30.00') == true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('日视图小时分布使用账单记录时区', (tester) async {
    final now = DateTime.now();
    final transaction = FinanceTransaction(
      uuid: 'daily-chart-timezone-entry',
      amountMinor: 2000,
      categoryUuid: 'test-food',
      transactionDate: dateKey(now),
      occurredAt:
          DateTime.utc(
            now.year,
            now.month,
            now.day,
            0,
            30,
          ).millisecondsSinceEpoch -
          14 * 60 * 60 * 1000,
      timezoneOffsetMinutes: 14 * 60,
      createdAt: DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    );
    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: DateTime(now.year, now.month),
          summary: FinanceSummary.fromTransactions([transaction]),
          transactions: [transaction],
          categories: {
            'test-food': FinanceCategory(
              uuid: 'test-food',
              name: '日常餐饮',
              icon: '🍜',
            ),
          },
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );
    await _tap(tester, find.text('日视图'));

    expect(find.byTooltip('0时 · 净支出 ¥20.00'), findsOneWidget);
    expect(find.byTooltip('12时 · 净支出 ¥0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日视图把未知发生时刻单独显示', (tester) async {
    final entryAt = DateTime.now().subtract(const Duration(minutes: 1));
    final transaction = FinanceTransaction.fromMap({
      'uuid': 'overview-unknown-occurrence-hour',
      'amount_minor': 2000,
      'transaction_date': dateKey(entryAt),
      'created_at': entryAt.millisecondsSinceEpoch,
      'updated_at': entryAt.millisecondsSinceEpoch,
      'merchant': '时间未知账单',
    });

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: DateTime(entryAt.year, entryAt.month),
          summary: FinanceSummary.fromTransactions([transaction]),
          transactions: [transaction],
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );
    await _tap(tester, find.text('日视图'));

    expect(find.byTooltip('未知时刻 · 净支出 ¥20.00'), findsOneWidget);
    expect(find.byTooltip('12时 · 净支出 ¥20.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('退款超过支出时净支出图表仍显示负值', (tester) async {
    final refund = FinanceTransaction(
      uuid: 'overview-net-refund',
      type: FinanceTransactionType.refund,
      amountMinor: 5000,
      transactionDate: '2026-09-02',
    );

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: _month,
          summary: FinanceSummary.fromTransactions([refund]),
          transactions: [refund],
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );

    expect(find.text('每日净支出'), findsOneWidget);
    expect(find.text('本月还没有净支出记录'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message?.contains('净支出 -¥50.00') == true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('支出与同日退款相抵时图表说明净额为零', (tester) async {
    final occurredAt = DateTime(2026, 9, 2, 10).millisecondsSinceEpoch;
    final transactions = [
      FinanceTransaction(
        uuid: 'overview-offset-expense',
        amountMinor: 5000,
        transactionDate: '2026-09-02',
        occurredAt: occurredAt,
        createdAt: occurredAt,
      ),
      FinanceTransaction(
        uuid: 'overview-offset-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 5000,
        transactionDate: '2026-09-02',
        occurredAt: occurredAt,
        createdAt: occurredAt,
      ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: _month,
          summary: FinanceSummary.fromTransactions(transactions),
          transactions: transactions,
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );

    expect(find.text('支出与退款相抵，净支出为 ¥0.00'), findsOneWidget);
    expect(find.textContaining('还没有净支出记录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记账概览月份箭头遵守日期选择器范围', (tester) async {
    Future<void> pumpMonth(DateTime month) => _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: month,
          summary: const FinanceSummary(),
          transactions: const [],
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );

    await pumpMonth(DateTime(2000));
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('finance-overview-period-previous')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('finance-overview-period-next')),
          )
          .onPressed,
      isNotNull,
    );

    final lastAllowedDate = DateTime.now().add(const Duration(days: 3650));
    await pumpMonth(DateTime(lastAllowedDate.year, lastAllowedDate.month));
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('finance-overview-period-next')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('预算月份箭头遵守日期选择器范围', (tester) async {
    await _seed(tester);
    final now = DateTime.now();
    Future<void> pumpMonth(DateTime month) => _pump(
      tester,
      FinanceBudgetScreen(initialMonth: month, clock: () => now),
      size: const Size(1100, 1000),
    );
    IconButton buttonFor(String tooltip) => tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          )
          .first,
    );

    await pumpMonth(DateTime(2000));
    expect(buttonFor('上个月').onPressed, isNull);
    expect(buttonFor('下个月').onPressed, isNotNull);

    final lastAllowedDate = now.add(const Duration(days: 3650));
    await pumpMonth(DateTime(lastAllowedDate.year, lastAllowedDate.month));
    expect(buttonFor('下个月').onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预算页跨月后更新本月统计标签', (tester) async {
    final db = await _seed(tester);
    var clockNow = DateTime(2026, 10, 31, 23, 59, 58);
    await tester.runAsync(() async {
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'budget-month-rollover',
          monthKey: '2026-10',
          amountMinor: 10000,
        ).toMap(),
      );
    });

    await _pump(
      tester,
      FinanceBudgetScreen(clock: () => clockNow),
      size: const Size(1100, 1000),
    );
    expect(find.text('本月总预算'), findsOneWidget);

    clockNow = DateTime(2026, 11, 1, 0, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    await _waitFor(
      tester,
      () => find.text('2026年10月总预算').evaluate().isNotEmpty,
    );

    expect(find.text('本月总预算'), findsNothing);
    expect(find.text('2026年10月总预算'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史月份的小结和分类空状态显示所选月份', (tester) async {
    final now = DateTime.now();
    final selectedMonth = DateTime(now.year, now.month - 1);
    final transactionDate = dateKey(
      DateTime(selectedMonth.year, selectedMonth.month, 2),
    );
    final transactions = [
      FinanceTransaction(
        uuid: 'overview-offset-expense',
        amountMinor: 5000,
        categoryUuid: 'test-food',
        transactionDate: transactionDate,
      ),
      FinanceTransaction(
        uuid: 'overview-offset-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 5000,
        categoryUuid: 'test-food',
        transactionDate: transactionDate,
      ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: selectedMonth,
          summary: FinanceSummary.fromTransactions(transactions),
          transactions: transactions,
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );

    final monthLabel = '${selectedMonth.year}年${selectedMonth.month}月';
    expect(find.text('$monthLabel没有可展示的净支出分类'), findsOneWidget);
    expect(find.text('$monthLabel小结'), findsOneWidget);
    expect(find.text('本月没有可展示的净支出分类'), findsNothing);
    expect(find.text('本月小结'), findsNothing);

    await _tap(tester, find.text('周视图'));
    final weeklyChartTitle = tester
        .widget<Text>(find.textContaining('每日净支出').first)
        .data!;
    expect(weeklyChartTitle, isNot('本周每日净支出'));
    final weekLabel = weeklyChartTitle.replaceFirst('每日净支出', '');
    expect(find.text('$weekLabel小结'), findsOneWidget);
    expect(find.text('$weekLabel没有可展示的净支出分类'), findsOneWidget);

    await _tap(tester, find.text('日视图'));
    final dailyChartTitle = tester
        .widget<Text>(find.textContaining('时段净支出').first)
        .data!;
    expect(dailyChartTitle, isNot('当天时段净支出'));
    final dayLabel = dailyChartTitle.replaceFirst('时段净支出', '');
    expect(find.text('$dayLabel没有可展示的净支出分类'), findsOneWidget);
    expect(find.text('$dayLabel还没有净支出记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('概览平均净支出不把收入笔数计入分母', (tester) async {
    final occurredAt = DateTime(2026, 9, 2, 10).millisecondsSinceEpoch;
    final transactions = [
      FinanceTransaction(
        uuid: 'overview-average-expense',
        amountMinor: 10000,
        transactionDate: '2026-09-02',
        occurredAt: occurredAt,
        createdAt: occurredAt,
      ),
      FinanceTransaction(
        uuid: 'overview-average-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 2000,
        transactionDate: '2026-09-02',
        occurredAt: occurredAt,
        createdAt: occurredAt,
      ),
      for (var index = 0; index < 3; index++)
        FinanceTransaction(
          uuid: 'overview-average-income-$index',
          type: FinanceTransactionType.income,
          amountMinor: 5000,
          transactionDate: '2026-09-02',
          occurredAt: occurredAt,
          createdAt: occurredAt,
        ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: _month,
          summary: FinanceSummary.fromTransactions(transactions),
          transactions: transactions,
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );

    expect(find.text('共 5 笔记录，支出/退款 2 笔，平均净支出 ¥40.00。'), findsOneWidget);
    expect(find.text('本期结余'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('概览卡片分别显示净支出与总支出', (tester) async {
    final occurredAt = DateTime(2026, 9, 2, 10).millisecondsSinceEpoch;
    final transactions = [
      FinanceTransaction(
        uuid: 'overview-gross-expense',
        amountMinor: 10000,
        transactionDate: '2026-09-02',
        occurredAt: occurredAt,
        createdAt: occurredAt,
      ),
      FinanceTransaction(
        uuid: 'overview-gross-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 2000,
        transactionDate: '2026-09-02',
        occurredAt: occurredAt,
        createdAt: occurredAt,
      ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: _month,
          summary: FinanceSummary.fromTransactions(transactions),
          transactions: transactions,
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );

    expect(find.text('净支出'), findsOneWidget);
    expect(find.text('总支出'), findsOneWidget);
    final summaryCard = find
        .ancestor(of: find.text('总支出'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: summaryCard, matching: find.text('¥80.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summaryCard, matching: find.text('¥100.00')),
      findsOneWidget,
    );
    expect(find.text('实际支出'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有收入时不显示不存在的平均净支出', (tester) async {
    final occurredAt = DateTime(2026, 9, 2, 10).millisecondsSinceEpoch;
    final transactions = [
      FinanceTransaction(
        uuid: 'overview-income-only',
        type: FinanceTransactionType.income,
        amountMinor: 5000,
        transactionDate: '2026-09-02',
        occurredAt: occurredAt,
        createdAt: occurredAt,
      ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: _month,
          summary: FinanceSummary.fromTransactions(transactions),
          transactions: transactions,
          categories: const {},
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    );

    expect(find.text('共 1 笔记录，本期暂无支出或退款记录。'), findsOneWidget);
    expect(find.textContaining('平均净支出'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账单列表将尚未发生的未来账单标记出来', (tester) async {
    final now = DateTime(2026, 10, 2, 12);
    final futureAt = now.add(const Duration(hours: 1));
    final actualAt = now.subtract(const Duration(hours: 1));
    final transactions = [
      FinanceTransaction(
        uuid: 'ledger-upcoming-bill',
        amountMinor: 3000,
        transactionDate: dateKey(futureAt),
        occurredAt: futureAt.millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        merchant: '未来房租',
      ),
      FinanceTransaction(
        uuid: 'ledger-occurred-bill',
        amountMinor: 1500,
        transactionDate: dateKey(now),
        occurredAt: actualAt.millisecondsSinceEpoch,
        createdAt: actualAt.millisecondsSinceEpoch,
        merchant: '已发生账单',
      ),
      FinanceTransaction(
        uuid: 'ledger-upcoming-income',
        type: FinanceTransactionType.income,
        amountMinor: 7200,
        transactionDate: dateKey(futureAt),
        occurredAt: futureAt.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        merchant: '待到账收入',
      ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: FinanceLedgerPanel(
          clock: () => now,
          transactions: transactions,
          categories: const {},
          paymentMethods: const {},
          keyword: '',
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
    );

    expect(find.text('待发生'), findsNWidgets(2));
    expect(find.text('未来房租'), findsOneWidget);
    expect(find.text('净支出 ¥15.00'), findsOneWidget);
    expect(find.text('计划净支出 ¥30.00'), findsOneWidget);
    expect(find.text('计划收入 ¥72.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账单搜索支持列表显示的中文日期', (tester) async {
    final now = DateTime(2026, 9, 5, 12);
    final transactions = [
      FinanceTransaction(
        uuid: 'ledger-search-date-match',
        amountMinor: 3000,
        transactionDate: '2026-09-04',
        merchant: '日期匹配账单',
      ),
      FinanceTransaction(
        uuid: 'ledger-search-date-other',
        amountMinor: 1500,
        transactionDate: '2026-09-05',
        merchant: '其他日期账单',
      ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: FinanceLedgerPanel(
          clock: () => now,
          transactions: transactions,
          categories: const {},
          paymentMethods: const {},
          keyword: '9月4日',
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
    );

    expect(find.text('日期匹配账单'), findsOneWidget);
    expect(find.text('其他日期账单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账单搜索按中文月份精确筛选', (tester) async {
    final now = DateTime(2026, 11, 5, 12);
    final transactions = [
      FinanceTransaction(
        uuid: 'ledger-search-january',
        amountMinor: 3000,
        transactionDate: '2026-01-04',
        merchant: '一月账单',
      ),
      FinanceTransaction(
        uuid: 'ledger-search-november',
        amountMinor: 1500,
        transactionDate: '2026-11-04',
        merchant: '十一月账单',
      ),
    ];

    await _pump(
      tester,
      Scaffold(
        body: FinanceLedgerPanel(
          clock: () => now,
          transactions: transactions,
          categories: const {},
          paymentMethods: const {},
          keyword: '1月',
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
    );

    expect(find.text('一月账单'), findsOneWidget);
    expect(find.text('十一月账单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账单被删除后打开的详情停止显示旧记录', (tester) async {
    final db = await _seed(tester);
    final transaction = FinanceTransaction(
      uuid: 'deleted-open-detail',
      amountMinor: 8500,
      transactionDate: '2026-10-02',
      merchant: '等待同步删除的账单',
    );
    await tester.runAsync(
      () => db.insert('finance_transactions', transaction.toMap()),
    );

    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      FinanceTransactionDetailScreen(transaction: transaction),
                ),
              );
            },
            child: const Text('打开测试账单'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开测试账单'));
    await tester.pumpAndSettle();
    expect(find.text('等待同步删除的账单'), findsOneWidget);

    await tester.runAsync(
      () => FinanceStorage.deleteTransaction(transaction.uuid),
    );
    await _waitFor(tester, () => find.text('账单已删除').evaluate().isNotEmpty);

    expect(find.text('等待同步删除的账单'), findsNothing);
    expect(
      find.byKey(const ValueKey('finance-transaction-detail-edit')),
      findsNothing,
    );
    expect(find.text('这笔记录已从账本中移除。'), findsOneWidget);

    await tester.runAsync(
      () => FinanceStorage.restoreTransaction(transaction.uuid),
    );
    await _waitFor(tester, () => find.text('等待同步删除的账单').evaluate().isNotEmpty);
    expect(
      find.byKey(const ValueKey('finance-transaction-detail-edit')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏账单列表中的大额金额不会挤出卡片', (tester) async {
    final transaction = FinanceTransaction(
      uuid: 'ledger-large-amount-narrow-screen',
      amountMinor: maxFinanceAmountMinor,
      transactionDate: '2026-09-04',
      merchant: '大额账单',
    );

    await _pump(
      tester,
      Scaffold(
        body: FinanceLedgerPanel(
          transactions: [transaction],
          categories: const {},
          paymentMethods: const {},
          keyword: '',
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
      size: const Size(320, 740),
    );

    expect(find.text('大额账单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未分类账单筛选只显示未关联分类的账单', (tester) async {
    final uncategorized = FinanceTransaction(
      uuid: 'ledger-uncategorized',
      amountMinor: 1200,
      transactionDate: '2026-09-04',
      merchant: '未分类支出',
    );
    final categorized = FinanceTransaction(
      uuid: 'ledger-categorized',
      amountMinor: 1800,
      categoryUuid: 'test-food',
      transactionDate: '2026-09-04',
      merchant: '分类支出',
    );
    final deletedCategoryEntry = FinanceTransaction(
      uuid: 'ledger-deleted-category',
      amountMinor: 900,
      categoryUuid: 'deleted-food-category',
      transactionDate: '2026-09-04',
      merchant: '删除分类后保留的账单',
    );
    String? changedCategoryUuid = financeUncategorizedCategoryFilterUuid;

    await _pump(
      tester,
      Scaffold(
        body: FinanceLedgerPanel(
          transactions: [uncategorized, categorized, deletedCategoryEntry],
          categories: {
            'test-food': FinanceCategory(
              uuid: 'test-food',
              name: '日常餐饮',
              icon: '🍜',
            ),
          },
          paymentMethods: const {},
          keyword: '',
          filterType: null,
          categoryUuid: financeUncategorizedCategoryFilterUuid,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onCategoryChanged: (value) => changedCategoryUuid = value,
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
    );

    expect(find.text('未分类支出'), findsOneWidget);
    expect(find.text('分类支出'), findsNothing);
    expect(find.text('删除分类后保留的账单'), findsOneWidget);
    expect(find.text('分类 · 未分类'), findsOneWidget);
    await _tap(
      tester,
      find.byKey(const ValueKey('finance-ledger-category-filter')),
    );
    expect(changedCategoryUuid, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('周视图分类详情进入账单时保留选中周范围', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final inWeek = FinanceTransaction(
      uuid: 'weekly-category-in-range',
      amountMinor: 2400,
      categoryUuid: 'test-food',
      transactionDate: '2026-06-03',
      merchant: '本周账单',
    );
    final outsideWeek = FinanceTransaction(
      uuid: 'weekly-category-out-of-range',
      amountMinor: 5600,
      categoryUuid: 'test-food',
      transactionDate: '2026-06-12',
      merchant: '其它日期账单',
    );
    List<FinanceTransaction>? selectedPeriodTransactions;

    await _pump(
      tester,
      Scaffold(
        body: FinanceOverviewPanel(
          month: DateTime(2026, 6),
          summary: FinanceSummary.fromTransactions([inWeek, outsideWeek]),
          transactions: [inWeek, outsideWeek],
          categories: {
            'test-food': FinanceCategory(
              uuid: 'test-food',
              name: '日常餐饮',
              icon: '🍜',
            ),
          },
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
          onCategorySelected: (_, _, periodTransactions) async {
            selectedPeriodTransactions = periodTransactions;
          },
        ),
      ),
    );
    await _tap(tester, find.text('周视图'));
    await _tap(
      tester,
      find.byKey(const ValueKey('finance-overview-category-test-food')),
    );
    await tester.pumpAndSettle();
    await _tap(
      tester,
      find.byKey(const ValueKey('finance-category-detail-test-food')),
    );
    await tester.pumpAndSettle();

    expect(selectedPeriodTransactions, [inWeek]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史月份账单为空时显示所选月份', (tester) async {
    final now = DateTime.now();
    final selectedMonth = DateTime(now.year, now.month - 1);
    await _pump(
      tester,
      Scaffold(
        body: FinanceLedgerPanel(
          month: selectedMonth,
          transactions: const [],
          categories: const {},
          paymentMethods: const {},
          keyword: '',
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
    );

    expect(
      find.text('${selectedMonth.year}年${selectedMonth.month}月还没有账单'),
      findsOneWidget,
    );
    expect(find.text('本月还没有账单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('纯空格搜索不会把空账单提示成搜索无结果', (tester) async {
    final selectedMonth = DateTime(2026, 9);
    await _pump(
      tester,
      Scaffold(
        body: FinanceLedgerPanel(
          month: selectedMonth,
          transactions: const [],
          categories: const {},
          paymentMethods: const {},
          keyword: '   ',
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
    );

    expect(find.text('2026年9月还没有账单'), findsOneWidget);
    expect(find.text('没有匹配的账单'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑缺少发生时刻的旧账单不会改变当天排序', (tester) async {
    final legacy = FinanceTransaction.fromMap({
      'uuid': 'ledger-edited-legacy-time',
      'amount_minor': 1000,
      'transaction_date': '2026-09-02',
      'created_at': DateTime(2026, 9, 2, 8).millisecondsSinceEpoch,
      'updated_at': DateTime(2026, 9, 2, 18).millisecondsSinceEpoch,
      'merchant': '旧账单',
    });
    final knownTime = DateTime(2026, 9, 2, 11);
    final known = FinanceTransaction(
      uuid: 'ledger-known-time',
      amountMinor: 2000,
      transactionDate: '2026-09-02',
      occurredAt: knownTime.millisecondsSinceEpoch,
      timezoneOffsetMinutes: knownTime.timeZoneOffset.inMinutes,
      createdAt: DateTime(2026, 9, 2, 9).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 9, 2, 10).millisecondsSinceEpoch,
      merchant: '有时间账单',
    );

    await _pump(
      tester,
      Scaffold(
        body: FinanceLedgerPanel(
          transactions: [legacy, known],
          categories: const {},
          paymentMethods: const {},
          keyword: '',
          filterType: null,
          onOpenDetail: (_, _) {},
          onKeywordChanged: (_) {},
          onFilterChanged: (_) {},
          onEdit: (_) {},
          onDelete: (_) {},
          onRefund: (_) {},
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text('有时间账单')).dy,
      lessThan(tester.getTopLeft(find.text('旧账单')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('预算卡片直接编辑并保存，范围和备注保持不变', (tester) async {
    final db = await _seed(tester);
    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: _month),
      size: const Size(1100, 1000),
    );
    await _tap(tester, _key('finance-budget-card-test-budget'));
    await _waitFor(
      tester,
      () => _key('finance-budget-amount').evaluate().isNotEmpty,
    );
    await tester.enterText(_field('finance-budget-amount'), '4500');
    await _tap(tester, find.text('保存预算'));
    await _waitFor(
      tester,
      () =>
          find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    final rows = (await tester.runAsync(
      () => db.query(
        'finance_budgets',
        where: 'uuid = ?',
        whereArgs: ['test-budget'],
      ),
    ))!;
    expect(rows.single['amount_minor'], 450000);
    expect(rows.single['category_uuid'], isNull);
    expect(rows.single['note'], '本月总预算');
    expect(rows.single['version'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('银行卡余额快照后没有收支时显示余额不变', (tester) async {
    final db = await _seed(tester);
    final now = DateTime.now();
    final snapshotAt = now.subtract(const Duration(minutes: 5));
    await tester.runAsync(() async {
      await db.insert(
        'finance_payment_methods',
        FinancePaymentMethod(uuid: 'unchanged-card', name: '未变银行卡').toMap(),
      );
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'unchanged-card-snapshot',
          monthKey: financeMonthKey(now),
          paymentMethodUuid: 'unchanged-card',
          amountMinor: 10000,
          balanceSnapshotAt: snapshotAt.millisecondsSinceEpoch,
          createdAt: snapshotAt.millisecondsSinceEpoch,
          updatedAt: snapshotAt.millisecondsSinceEpoch,
        ).toMap(),
      );
    });

    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: now),
      size: const Size(1100, 1000),
    );
    final card = _key('finance-budget-card-unchanged-card-snapshot');
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: card, matching: find.text('录入后余额不变')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('当前余额 ¥100.00')),
      findsOneWidget,
    );
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
      final income = (await FinanceStorage.getTransaction('unassigned-income'))!
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
      () =>
          find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty &&
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

    await tester.runAsync(
      () => FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'later-card-income',
          type: FinanceTransactionType.income,
          amountMinor: 1000,
          paymentMethodUuid: 'balance-card',
          transactionDate: transactionDate,
        ),
      ),
    );
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
      () =>
          find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty &&
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

  testWidgets('跨时区付款余额按快照月份归属避免污染前月', (tester) async {
    final db = await _seed(tester);
    final actualNow = DateTime.now();
    final clockNow = DateTime(actualNow.year, actualNow.month, 15, 12);
    final previousMonth = DateTime(clockNow.year, clockNow.month - 1);
    final nextMonth = DateTime(previousMonth.year, previousMonth.month + 1);
    final previousMonthEnd = nextMonth.subtract(
      const Duration(milliseconds: 1),
    );
    final previousSnapshotAt = nextMonth.add(const Duration(hours: 20));
    final nextSnapshotAt = previousMonthEnd.subtract(const Duration(hours: 10));

    await tester.runAsync(() async {
      await db.insert(
        'finance_payment_methods',
        FinancePaymentMethod(uuid: 'timezone-card', name: '跨时区银行卡').toMap(),
      );
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'timezone-card-previous-month',
          monthKey: financeMonthKey(previousMonth),
          paymentMethodUuid: 'timezone-card',
          amountMinor: 10000,
          balanceSnapshotAt: previousSnapshotAt.millisecondsSinceEpoch,
        ).toMap(),
      );
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'timezone-card-next-month',
          monthKey: financeMonthKey(nextMonth),
          paymentMethodUuid: 'timezone-card',
          amountMinor: 20000,
          balanceSnapshotAt: nextSnapshotAt.millisecondsSinceEpoch,
        ).toMap(),
      );
    });

    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: previousMonth, clock: () => clockNow),
      size: const Size(1100, 1000),
    );
    expect(find.text('该月余额 ¥100.00'), findsOneWidget);
    expect(find.text('该月余额 ¥200.00'), findsNothing);

    final previousMonthCard = _key(
      'finance-budget-card-timezone-card-previous-month',
    );
    await _tap(tester, previousMonthCard);
    await _waitFor(
      tester,
      () =>
          find.byType(FinanceBudgetEntryScreen).evaluate().isNotEmpty &&
          _key('finance-budget-amount').evaluate().isNotEmpty,
    );
    await tester.enterText(_field('finance-budget-amount'), '110');
    await _tap(tester, find.text('保存余额'));
    await _waitFor(
      tester,
      () => find.byType(FinanceBudgetEntryScreen).evaluate().isEmpty,
    );
    final editedSnapshot = (await tester.runAsync(
      () => FinanceStorage.getBudget('timezone-card-previous-month'),
    ))!;
    expect(editedSnapshot.amountMinor, 11000);
    expect(
      editedSnapshot.effectiveBalanceSnapshotAt,
      previousSnapshotAt.millisecondsSinceEpoch,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史月份余额必须选择实际对应时间并保存到快照', (tester) async {
    final db = await _seed(tester);
    await tester.runAsync(
      () => db.insert(
        'finance_payment_methods',
        FinancePaymentMethod(uuid: 'past-card', name: '历史银行卡').toMap(),
      ),
    );
    final now = DateTime.now();
    final pastMonth = DateTime(now.year, now.month - 1);
    await _pump(tester, FinanceBudgetScreen(initialMonth: pastMonth));
    await tester.scrollUntilVisible(
      find.text('月末付款方式余额'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('月末付款方式余额'), findsOneWidget);
    expect(find.text('付款方式实时余额'), findsNothing);
    await _tap(tester, find.text('选择付款方式并录入余额'));
    await _tap(tester, find.text('历史银行卡'));
    await _waitFor(
      tester,
      () =>
          find.byType(FinanceBudgetEntryScreen).evaluate().isNotEmpty &&
          _key('finance-budget-amount').evaluate().isNotEmpty,
    );
    await tester.enterText(_field('finance-budget-amount'), '100');
    await _tap(tester, find.text('保存余额'));
    expect(find.text('请先选择该月份内的余额对应时间'), findsOneWidget);
    var rows = (await tester.runAsync(
      () => db.query(
        'finance_budgets',
        where: 'payment_method_uuid = ?',
        whereArgs: ['past-card'],
      ),
    ))!;
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
    rows = (await tester.runAsync(
      () => db.query(
        'finance_budgets',
        where: 'payment_method_uuid = ?',
        whereArgs: ['past-card'],
      ),
    ))!;
    expect(rows, hasLength(1));
    final snapshotAt = DateTime.fromMillisecondsSinceEpoch(
      rows.single['balance_snapshot_at'] as int,
    );
    expect(financeMonthKey(snapshotAt), financeMonthKey(pastMonth));
    expect(rows.single['amount_minor'], 10000);
    expect(tester.takeException(), isNull);

    final card = _key(
      'finance-budget-card-${FinanceBudget.stableUuid(financeMonthKey(pastMonth), null, paymentMethodUuid: 'past-card')}',
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
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'before-historical-snapshot',
          amountMinor: 500,
          paymentMethodUuid: 'past-card',
          transactionDate: dateKey(snapshotAt),
          createdAt: snapshotAt.millisecondsSinceEpoch - 60000,
        ),
      );
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'after-historical-snapshot',
          type: FinanceTransactionType.income,
          amountMinor: 2000,
          paymentMethodUuid: 'past-card',
          transactionDate: dateKey(snapshotAt),
          createdAt: snapshotAt.millisecondsSinceEpoch + 60000,
        ),
      );
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
                builder: (_) => const FinanceLoanEntryScreen(),
              ),
            ),
            child: const Text('新增贷款测试'),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('新增贷款测试'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('finance-loan-name'), '新测试贷款');
    await tester.enterText(_field('finance-loan-principal'), '1000');
    await tester.ensureVisible(_key('finance-loan-rate'));
    await tester.enterText(_field('finance-loan-rate'), '12');
    await tester.enterText(_field('finance-loan-term'), '3');
    await _tap(tester, find.text('保存贷款'));
    await _waitFor(
      tester,
      () => find.byType(FinanceLoanEntryScreen).evaluate().isEmpty,
    );
    final rows = (await tester.runAsync(
      () => db.query('finance_loans', where: 'name = ?', whereArgs: ['新测试贷款']),
    ))!;
    expect(rows.single['principal_minor'], 100000);
    expect(rows.single['annual_interest_rate_bps'], 1200);
    final installments = (await tester.runAsync(
      () => db.query(
        'finance_loan_installments',
        where: 'loan_uuid = ?',
        whereArgs: [rows.single['uuid']],
      ),
    ))!;
    expect(installments, hasLength(3));
    expect(
      installments.fold<int>(
        0,
        (sum, row) => sum + (row['principal_minor'] as int),
      ),
      100000,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除已关联退款的原单会提示原因并保留原单', (tester) async {
    final db = await _seed(tester);
    final original = FinanceTransaction(
      uuid: 'ui-refund-original',
      amountMinor: 10000,
      transactionDate: dateKey(DateTime.now()),
      merchant: '退款原单测试',
    );
    await tester.runAsync(() async {
      await FinanceStorage.saveTransaction(original);
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'ui-refund',
          type: FinanceTransactionType.refund,
          amountMinor: 1000,
          transactionDate: original.transactionDate,
          merchant: '原单退款记录',
          relatedTransactionUuid: original.uuid,
        ),
      );
    });
    await _pump(
      tester,
      const FinanceHomeScreen(username: 'default'),
      size: const Size(1100, 1000),
    );
    await tester.tap(find.text('账单').hitTestable().last);
    await tester.pumpAndSettle();
    final row = find
        .ancestor(of: find.text('退款原单测试'), matching: find.byType(ListTile))
        .first;
    await _tap(
      tester,
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await _waitFor(
      tester,
      () => find.text('该账单已关联退款，请先处理退款记录').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    final rows = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [original.uuid],
      ),
    ))!;
    expect(rows.single['is_deleted'], 0);
  });

  testWidgets('删除退款前明确提示净支出和账户余额影响', (tester) async {
    await _seed(tester);
    final now = DateTime.now();
    final original = FinanceTransaction(
      uuid: 'ui-refund-delete-copy-original',
      amountMinor: 10000,
      paymentMethodUuid: 'finance-system-payment-cash',
      transactionDate: dateKey(now),
      merchant: '退款确认原单',
    );
    await tester.runAsync(() async {
      await FinanceStorage.saveTransaction(original);
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'ui-refund-delete-copy-refund',
          type: FinanceTransactionType.refund,
          amountMinor: 1000,
          paymentMethodUuid: 'finance-system-payment-cash',
          transactionDate: original.transactionDate,
          merchant: '需要删除的退款',
          relatedTransactionUuid: original.uuid,
        ),
      );
    });
    await _pump(
      tester,
      const FinanceHomeScreen(username: 'default'),
      size: const Size(1100, 1000),
    );
    await tester.tap(find.text('账单').hitTestable().last);
    await tester.pumpAndSettle();
    final row = find
        .ancestor(of: find.text('需要删除的退款'), matching: find.byType(ListTile))
        .first;
    await _tap(
      tester,
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(
      find.text('删除后，这笔退款不再抵扣净支出，也不再增加该付款方式的余额。确认继续吗？'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨时区账单显示记录时刻且编辑保存保留原始时间戳', (tester) async {
    final db = await _seed(tester);
    final transaction = FinanceTransaction(
      uuid: 'timezone-entry',
      amountMinor: 2000,
      transactionDate: '2026-10-02',
      occurredAt: DateTime.utc(2026, 10, 1, 10, 30).millisecondsSinceEpoch,
      timezoneOffsetMinutes: 840,
    );
    await tester.runAsync(() => FinanceStorage.saveTransaction(transaction));
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FinanceEntryScreen(transaction: transaction),
              ),
            ),
            child: const Text('打开跨时区账单'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开跨时区账单'));
    await _waitFor(tester, () => find.text('00:30').evaluate().isNotEmpty);
    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('按记录时区 UTC+14:00 显示'), findsOneWidget);
    await _tap(tester, find.text('保存账单'));
    await _waitFor(
      tester,
      () => find.byType(FinanceEntryScreen).evaluate().isEmpty,
    );
    final row = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [transaction.uuid],
      ),
    ))!.single;
    expect(row['occurred_at'], transaction.occurredAt);
    expect(row['timezone_offset_minutes'], 840);
    expect(tester.takeException(), isNull);
  });

  testWidgets('还款扣减本金及利息一次，撤销后恢复账户余额', (tester) async {
    final db = await _seed(tester);
    final now = DateTime.now();
    final paidAt = now.subtract(const Duration(hours: 1));
    final snapshotAt = now
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    await tester.runAsync(() async {
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'loan-balance',
          monthKey: financeMonthKey(now),
          paymentMethodUuid: 'finance-system-payment-cash',
          amountMinor: 100000,
          balanceSnapshotAt: snapshotAt,
        ).toMap(),
      );
      await FinanceStorage.setLoanInstallmentPaid(
        'test-installment-2',
        true,
        paymentMethodUuid: 'finance-system-payment-cash',
        paidAt: paidAt,
      );
    });
    final repayment = (await tester.runAsync(
      () => FinanceStorage.getLoanInstallment('test-installment-2'),
    ))!;
    final interest = (await tester.runAsync(
      () => FinanceStorage.getTransaction(repayment.interestTransactionUuid!),
    ))!;
    expect(interest.transactionDate, dateKey(paidAt));
    expect(interest.paymentMethodUuid, 'finance-system-payment-cash');
    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: now),
      size: const Size(1100, 1000),
    );
    final card = _key('finance-budget-card-loan-balance');
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text(
          '当前余额 ${formatFinanceAmount(100000 - repayment.paymentMinor)}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text(formatFinanceAmount(repayment.paymentMinor)),
      ),
      findsOneWidget,
    );
    // Reopen the page after each operation so a stale rendered balance cannot
    // hide a lost cash movement while the revision listener is reloading.
    for (final deleted in [true, false]) {
      await tester.runAsync(
        () => deleted
            ? FinanceStorage.deleteLoan('test-loan')
            : FinanceStorage.restoreLoan('test-loan'),
      );
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
        find.descendant(
          of: card,
          matching: find.text(
            '当前余额 ${formatFinanceAmount(100000 - repayment.paymentMinor)}',
          ),
        ),
        findsOneWidget,
        reason: deleted ? '删除贷款保留已还本金扣款' : '恢复贷款不重复扣款',
      );
    }
    await tester.runAsync(
      () => FinanceStorage.setLoanInstallmentPaid(repayment.uuid, false),
    );
    await _waitFor(
      tester,
      () => find
          .descendant(of: card, matching: find.text('当前余额 ¥1,000.00'))
          .evaluate()
          .isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('利息已退款时撤销还款显示原因且保留已还记录', (tester) async {
    await _seed(tester);
    final paid = (await tester.runAsync(() async {
      await FinanceStorage.setLoanInstallmentPaid(
        'test-installment-2',
        true,
        paymentMethodUuid: 'finance-system-payment-cash',
        paidAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final installment = (await FinanceStorage.getLoanInstallment(
        'test-installment-2',
      ))!;
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'ui-loan-interest-refund',
          type: FinanceTransactionType.refund,
          amountMinor: installment.interestMinor,
          paymentMethodUuid: installment.paymentMethodUuid,
          transactionDate: dateKey(DateTime.now()),
          relatedTransactionUuid: installment.interestTransactionUuid,
        ),
      );
      return installment;
    }))!;
    await _pump(tester, FinanceLoanDetailScreen(loan: _loan()));
    await _tap(tester, _key('finance-loan-filter-paid'));
    await tester.pumpAndSettle();
    await _tap(tester, _key('finance-loan-paid-test-installment-2'));
    await _waitFor(
      tester,
      () => find.textContaining('该账单已关联退款，请先处理退款记录').evaluate().isNotEmpty,
    );
    final preserved = (await tester.runAsync(
      () => FinanceStorage.getLoanInstallment(paid.uuid),
    ))!;
    expect(preserved.isPaid, true);
    expect(preserved.paymentMethodUuid, paid.paymentMethodUuid);
    expect(
      (await tester.runAsync(
        () => FinanceStorage.getTransaction(paid.interestTransactionUuid!),
      ))!.isDeleted,
      false,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨时区分期按实际发生时刻扣减而非创建日期或本机日历日期', (tester) async {
    final db = await _seed(tester);
    final clock = DateTime.utc(2026, 10, 1, 12).toLocal();
    await tester.runAsync(() async {
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'timezone-balance',
          monthKey: '2026-10',
          paymentMethodUuid: 'finance-system-payment-cash',
          amountMinor: 10000,
          balanceSnapshotAt: DateTime.utc(
            2026,
            10,
            1,
            9,
          ).millisecondsSinceEpoch,
        ).toMap(),
      );
      await db.insert(
        'finance_transactions',
        FinanceTransaction(
          uuid: 'timezone-installment',
          amountMinor: 2000,
          paymentMethodUuid: 'finance-system-payment-cash',
          transactionDate: '2026-10-02',
          timezoneOffsetMinutes: 840,
          occurredAt: DateTime.utc(2026, 10, 1, 10, 30).millisecondsSinceEpoch,
          createdAt: DateTime.utc(2026, 9, 15).millisecondsSinceEpoch,
        ).toMap(),
      );
    });
    await _pump(
      tester,
      FinanceBudgetScreen(initialMonth: clock, clock: () => clock),
      size: const Size(1100, 1000),
    );
    final card = _key('finance-budget-card-timezone-balance');
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: card, matching: find.text('当前余额 ¥80.00')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('还款分组与标记操作保留利息账单的生成及撤销语义', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, FinanceLoanDetailScreen(loan: _loan()));
    await _tap(tester, _key('finance-loan-filter-unpaid'));
    await tester.pumpAndSettle();
    expect(_key('finance-loan-installment-test-installment-1'), findsNothing);
    await _tap(tester, _key('finance-loan-paid-test-installment-2'));
    await tester.pumpAndSettle();
    await tester.tap(_key('finance-loan-payment-save'));
    await tester.pump();
    expect(find.text('请选择还款账户或不关联账户'), findsOneWidget);
    await tester.tap(_key('finance-loan-payment-method'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('现金').last);
    await tester.pumpAndSettle();
    await tester.tap(_key('finance-loan-payment-save'));
    await _waitFor(tester, () => find.text('已还 2').evaluate().isNotEmpty);
    final paid = (await tester.runAsync(
      () => FinanceStorage.getLoanInstallment('test-installment-2'),
    ))!;
    expect(paid.isPaid, isTrue);
    expect(paid.paymentMethodUuid, 'finance-system-payment-cash');
    expect(paid.interestTransactionUuid, isNotNull);
    final interest = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [paid.interestTransactionUuid],
      ),
    ))!;
    expect(interest.single['amount_minor'], paid.interestMinor);
    expect(interest.single['is_deleted'], 0);
    await _top(tester);
    await _tap(tester, _key('finance-loan-filter-paid'));
    await tester.pumpAndSettle();
    await _tap(tester, _key('finance-loan-payment-edit-test-installment-2'));
    await tester.pumpAndSettle();
    expect(find.text('修改还款记录'), findsOneWidget);
    await tester.tap(_key('finance-loan-payment-method'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('微信').last);
    await tester.pumpAndSettle();
    await tester.tap(_key('finance-loan-payment-save'));
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('finance-loan-payment-save'))
          .evaluate()
          .isEmpty,
    );
    final edited = (await tester.runAsync(
      () => FinanceStorage.getLoanInstallment('test-installment-2'),
    ))!;
    expect(edited.paymentMethodUuid, 'finance-system-payment-wechat');
    expect(edited.paidAt, paid.paidAt);
    expect(edited.interestTransactionUuid, paid.interestTransactionUuid);
    final editedInterest = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [paid.interestTransactionUuid],
      ),
    ))!;
    expect(
      editedInterest.single['payment_method_uuid'],
      edited.paymentMethodUuid,
    );
    await _tap(tester, _key('finance-loan-paid-test-installment-2'));
    await _waitFor(tester, () => find.text('已还 1').evaluate().isNotEmpty);
    final unpaid = (await tester.runAsync(
      () => FinanceStorage.getLoanInstallment('test-installment-2'),
    ))!;
    expect(unpaid.isPaid, isFalse);
    final deletedInterest = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [paid.interestTransactionUuid],
      ),
    ))!;
    expect(deletedInterest.single['is_deleted'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('贷款和还款详情跨过还款日后自动更新逾期状态', (tester) async {
    final db = await _seed(tester);
    await tester.runAsync(
      () => db.update(
        'finance_loan_installments',
        {'due_date': '2026-10-15'},
        where: 'uuid = ?',
        whereArgs: ['test-installment-2'],
      ),
    );
    var now = DateTime(2026, 10, 15, 23, 59, 58);

    await _pump(tester, FinanceLoanScreen(clock: () => now));
    final loanCard = _key('finance-loan-card-test-loan');
    final loanBadge = find.descendant(
      of: loanCard,
      matching: find.byType(FinanceStatusBadge),
    );
    await _waitFor(tester, () => loanBadge.evaluate().isNotEmpty);
    expect(tester.widget<FinanceStatusBadge>(loanBadge).label, '还款中');

    now = DateTime(2026, 10, 16, 0, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<FinanceStatusBadge>(loanBadge).label, '有逾期待还');
    expect(tester.takeException(), isNull);

    now = DateTime(2026, 10, 15, 23, 59, 58);
    await _pump(
      tester,
      FinanceLoanDetailScreen(loan: _loan(), clock: () => now),
    );
    final installment = _key('finance-loan-installment-test-installment-2');
    final installmentBadge = find.descendant(
      of: installment,
      matching: find.byType(FinanceStatusBadge),
    );
    await _waitFor(tester, () => installmentBadge.evaluate().isNotEmpty);
    expect(tester.widget<FinanceStatusBadge>(installmentBadge).label, '待还');

    now = DateTime(2026, 10, 16, 0, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<FinanceStatusBadge>(installmentBadge).label, '已逾期');
    expect(tester.takeException(), isNull);
  });

  testWidgets('回收站仍可取消恢复或恢复整组分期账单', (tester) async {
    final db = await _seed(tester);
    await _pump(tester, const FinanceTrashScreen());
    await tester.enterText(_key('finance-trash-search'), '旧分期');
    await tester.pumpAndSettle();
    await _tap(
      tester,
      _key('finance-trash-restore-transaction-deleted-installment-1'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('只恢复本期'), findsOneWidget);
    expect(find.text('恢复整组'), findsOneWidget);
    await _tap(tester, find.text('取消'));
    await tester.pumpAndSettle();
    final before = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'installment_group_uuid = ?',
        whereArgs: ['deleted-group'],
      ),
    ))!;
    expect(before.every((row) => row['is_deleted'] == 1), isTrue);
    await _tap(
      tester,
      _key('finance-trash-restore-transaction-deleted-installment-1'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _tap(tester, find.text('恢复整组'));
    await _waitFor(tester, () => find.text('没有找到匹配记录').evaluate().isNotEmpty);
    final restored = (await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'installment_group_uuid = ?',
        whereArgs: ['deleted-group'],
      ),
    ))!;
    expect(restored, hasLength(2));
    expect(restored.every((row) => row['is_deleted'] == 0), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('回收站不能单独恢复已超出当前期数的分期账单', (tester) async {
    final db = await _seed(tester);
    late String removedInstallmentUuid;
    await tester.runAsync(() async {
      final saved = await FinanceStorage.saveInstallmentPlan(
        transaction: FinanceTransaction(
          uuid: 'shortened-plan-first',
          amountMinor: 12000,
          transactionDate: '2026-09-01',
          merchant: '期数调整账单',
        ),
        totalAmountMinor: 12000,
        installmentCount: 3,
        startDate: DateTime(2026, 9, 1),
      );
      removedInstallmentUuid = saved.last.uuid;
      final groupUuid = saved.first.installmentGroupUuid!;
      final group = await FinanceStorage.getInstallmentGroup(
        groupUuid,
        includeDeleted: true,
      );
      await FinanceStorage.saveInstallmentPlan(
        transaction: FinanceTransaction.fromMap(saved.first.toMap()),
        totalAmountMinor: 8000,
        installmentCount: 2,
        startDate: DateTime(2026, 9, 1),
        existingInstallments: group,
      );
    });

    await _pump(tester, const FinanceTrashScreen());
    await _tap(
      tester,
      _key('finance-trash-restore-transaction-$removedInstallmentUuid'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _tap(tester, find.text('只恢复本期'));
    await _waitFor(
      tester,
      () => find.textContaining('超出当前分期计划').evaluate().isNotEmpty,
    );

    final row = await tester.runAsync(
      () => db.query(
        'finance_transactions',
        where: 'uuid = ?',
        whereArgs: [removedInstallmentUuid],
      ),
    );
    expect(row!.single['is_deleted'], 1);
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
        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.runtimeType} 首屏',
        );
        for (var i = 0; i < 9; i++) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -420),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType} 滚动布局',
          );
        }
      }
    }
  });

  testWidgets('预算保存栏在键盘弹出时仍可见，非法金额不会写入', (tester) async {
    final db = await _seed(tester);
    await _pump(
      tester,
      FinanceBudgetEntryScreen(month: _month, budget: _budget()),
      size: const Size(320, 740),
      scale: 1.6,
      keyboard: 240,
    );
    expect(find.text('保存预算').hitTestable(), findsOneWidget);
    await tester.enterText(_field('finance-budget-amount'), '0');
    await _tap(tester, find.text('保存预算'));
    await tester.pumpAndSettle();
    expect(find.text('请输入大于 0、最多两位小数的金额'), findsOneWidget);
    final rows = (await tester.runAsync(
      () => db.query(
        'finance_budgets',
        where: 'uuid = ?',
        whereArgs: ['test-budget'],
      ),
    ))!;
    expect(rows.single['amount_minor'], 500000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('数据加载失败有重试入口，不再显示为空列表', (tester) async {
    final db = await _seed(tester);
    await tester.runAsync(db.close);
    for (final screen in [
      const FinanceAutomationScreen(),
      const FinanceTrashScreen(),
      FinanceBudgetEntryScreen(month: _month),
    ]) {
      await _pump(tester, screen);
      expect(find.textContaining('加载失败'), findsOneWidget);
      expect(
        find.widgetWithText(
          FilledButton,
          screen is FinanceBudgetEntryScreen ? '重试' : '重新加载',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
