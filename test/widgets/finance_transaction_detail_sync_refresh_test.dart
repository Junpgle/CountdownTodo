@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_transaction_detail_screen.dart';
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
  fail('账单详情未在限定时间内刷新');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('云同步更新账单后详情和从详情打开的编辑表单显示最新内容', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    final now = DateTime.now();
    final category = FinanceCategory(
      uuid: 'transaction-detail-food',
      name: '餐饮',
      icon: '🍜',
    );
    final method = FinancePaymentMethod(
      uuid: 'transaction-detail-card',
      name: '本机银行卡',
      icon: '💳',
    );
    final transaction = FinanceTransaction(
      uuid: 'transaction-detail-sync',
      amountMinor: 2850,
      transactionDate: dateKey(now),
      occurredAt: now.millisecondsSinceEpoch,
      merchant: '旧商家',
      categoryUuid: category.uuid,
      paymentMethodUuid: method.uuid,
    );
    await tester.runAsync(() async {
      await FinanceStorage.saveCategory(category);
      await FinanceStorage.savePaymentMethod(method);
      await FinanceStorage.saveTransaction(transaction);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceTransactionDetailScreen(
          transaction: transaction,
          category: category,
          paymentMethod: method,
        ),
      ),
    );
    expect(find.text('旧商家'), findsOneWidget);
    expect(find.text('-¥28.50'), findsOneWidget);

    final remoteCategory = FinanceCategory.fromMap(category.toMap())
      ..name = '新分类名称'
      ..version = category.version + 1
      ..updatedAt = category.updatedAt + 10000;
    final remoteMethod = FinancePaymentMethod.fromMap(method.toMap())
      ..name = '另一设备银行卡'
      ..version = method.version + 1
      ..updatedAt = method.updatedAt + 10000;
    final remoteTransaction = FinanceTransaction.fromMap(transaction.toMap())
      ..amountMinor = 5100
      ..merchant = '云端更新商家'
      ..version = transaction.version + 1
      ..updatedAt = transaction.updatedAt + 10000;
    await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'categories': [remoteCategory.toMap()],
        'payment_methods': [remoteMethod.toMap()],
        'transactions': [remoteTransaction.toMap()],
      }),
    );

    await _waitFor(tester, () => find.text('云端更新商家').evaluate().isNotEmpty);
    expect(find.text('旧商家'), findsNothing);
    expect(find.text('-¥51.00'), findsOneWidget);
    expect(find.textContaining('新分类名称'), findsOneWidget);
    expect(find.textContaining('另一设备银行卡'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('finance-transaction-detail-edit')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(
      tester,
      () => find
          .byKey(const ValueKey('finance-amount-field'))
          .evaluate()
          .isNotEmpty,
    );
    final amountField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('finance-amount-field')),
    );
    final merchantField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('finance-merchant-field')),
    );
    expect(amountField.controller!.text, '51');
    expect(merchantField.controller!.text, '云端更新商家');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
