@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_entry_screen.dart';
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
  fail('记账表单未在限定时间内加载同步选项');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('表单打开后同步新增分类，刷新选择器但保留正在填写的内容', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    final now = DateTime.now();
    final localCategory = FinanceCategory(
      uuid: 'entry-local-category',
      name: '本机分类',
    );
    await tester.runAsync(() => FinanceStorage.saveCategory(localCategory));

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceEntryScreen(
          initialDraft: FinanceEntryDraft(
            amountMinor: 1250,
            transactionDate: dateKey(now),
            categoryUuid: localCategory.uuid,
            merchant: '正在填写的商家',
          ),
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('finance-merchant-field'))
          .evaluate()
          .isNotEmpty,
    );

    final remoteCategory = FinanceCategory(
      uuid: 'entry-remote-category',
      name: '另一设备新增分类',
    );
    await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'categories': [remoteCategory.toMap()],
      }),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final merchantField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('finance-merchant-field')),
    );
    final amountField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('finance-amount-field')),
    );
    expect(merchantField.controller!.text, '正在填写的商家');
    expect(amountField.controller!.text, '12.50');

    await tester.tap(
      find.byKey(
        ValueKey(
          'finance-category-${FinanceTransactionType.expense}-${localCategory.uuid}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('另一设备新增分类'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
