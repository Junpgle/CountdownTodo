@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_settings_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_trash_screen.dart';
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
  fail('记账管理页面未在限定时间内刷新');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('同步更新付款方式后刷新已打开的记账设置', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    final localMethod = FinancePaymentMethod(
      uuid: 'remote-refresh-method',
      name: '本机付款方式',
    );
    await tester.runAsync(() => FinanceStorage.savePaymentMethod(localMethod));
    await tester.pumpWidget(
      const MaterialApp(home: FinanceSettingsScreen(username: 'default')),
    );
    await _waitFor(
      tester,
      () => find.text('分类与付款方式').evaluate().isNotEmpty,
    );
    await tester.ensureVisible(find.text('付款方式').last);
    await tester.tap(find.text('付款方式').last);
    await tester.pumpAndSettle();
    await _waitFor(tester, () => find.text('本机付款方式').evaluate().isNotEmpty);

    final remoteMethod = FinancePaymentMethod.fromMap(localMethod.toMap())
      ..name = '另一设备更新的付款方式'
      ..version = localMethod.version + 1
      ..updatedAt = localMethod.updatedAt + 10000;
    await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'payment_methods': [remoteMethod.toMap()],
      }),
    );

    await _waitFor(
      tester,
      () => find.text('另一设备更新的付款方式').evaluate().isNotEmpty,
    );
    expect(find.text('本机付款方式'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同步删除账单后刷新已打开的回收站', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    final transaction = FinanceTransaction(
      uuid: 'remote-trash-refresh-transaction',
      amountMinor: 1200,
      transactionDate: dateKey(DateTime.now()),
      merchant: '另一设备删除的账单',
    );
    await tester.runAsync(() => FinanceStorage.saveTransaction(transaction));
    await tester.pumpWidget(const MaterialApp(home: FinanceTrashScreen()));
    await _waitFor(tester, () => find.text('回收站是空的').evaluate().isNotEmpty);

    final remoteDeleted = FinanceTransaction.fromMap(transaction.toMap())
      ..isDeleted = true
      ..version = transaction.version + 1
      ..updatedAt = transaction.updatedAt + 10000;
    await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'transactions': [remoteDeleted.toMap()],
      }),
    );

    await _waitFor(
      tester,
      () => find.text('另一设备删除的账单').evaluate().isNotEmpty,
    );
    expect(find.text('回收站是空的'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
