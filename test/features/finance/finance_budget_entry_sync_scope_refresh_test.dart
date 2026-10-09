@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_budget_entry_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openDatabase(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  return (await tester.runAsync(() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    return db;
  }))!;
}

void _closeDatabase(Database db) {
  addTearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('预算表单未在限定时间内加载同步付款方式');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('余额表单打开后同步新增付款方式，保留已填写金额', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    final month = DateTime.now();
    final localMethod = FinancePaymentMethod(
      uuid: 'budget-local-method',
      name: '本机银行卡',
    );
    await tester.runAsync(() => FinanceStorage.savePaymentMethod(localMethod));
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceBudgetEntryScreen(
          month: DateTime(month.year, month.month),
          initialPaymentMethodUuid: localMethod.uuid,
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('finance-budget-amount'))
          .evaluate()
          .isNotEmpty,
    );
    final amountField = find.descendant(
      of: find.byKey(const ValueKey('finance-budget-amount')),
      matching: find.byType(TextField),
    );
    await tester.enterText(amountField, '123.45');

    final remoteMethod = FinancePaymentMethod(
      uuid: 'budget-remote-method',
      name: '另一设备新增银行卡',
    );
    final revisionBeforeSync = FinanceStorage.revision.value;
    final mergedCount = await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'payment_methods': [remoteMethod.toMap()],
      }),
    );
    expect(mergedCount, greaterThan(0));
    expect(FinanceStorage.revision.value, greaterThan(revisionBeforeSync));
    final storedMethods = await tester.runAsync(
      () => FinanceStorage.getPaymentMethods(includeArchived: true),
    );
    expect(storedMethods!.any((item) => item.uuid == remoteMethod.uuid), isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(tester.widget<TextField>(amountField).controller!.text, '123.45');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final scopeField = find.byKey(
      ValueKey('finance-budget-scope-payment:${localMethod.uuid}'),
    );
    await tester.ensureVisible(scopeField);
    await tester.tap(scopeField);
    await tester.pumpAndSettle();
    expect(find.textContaining('另一设备新增银行卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
