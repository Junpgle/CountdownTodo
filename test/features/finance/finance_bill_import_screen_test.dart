@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:countdown_todo/features/finance/screens/finance_bill_import_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_settings_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _setupInMemoryFinanceDb(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'tip_shown_coach_finance_intro': true,
  });
  final db = (await tester.runAsync(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    return db;
  }))!;
  addTearDown(() async {
    await tester.runAsync(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() predicate, {
  int maxTries = 60,
}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (predicate()) return;
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('记账设置中的账单导入入口可打开账单导入页', (tester) async {
    await _setupInMemoryFinanceDb(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: FinanceSettingsScreen(
          username: 'tester',
          initialPreferences: true,
        ),
      ),
    );
    final importTile = find.byKey(
      const ValueKey('finance-settings-bill-import'),
    );
    await _waitFor(tester, () => importTile.evaluate().isNotEmpty);

    expect(importTile, findsOneWidget);
    await tester.ensureVisible(importTile);
    await tester.pump();
    await tester.tap(importTile);
    await _waitFor(tester, () => find.text('导入多平台账单').evaluate().isNotEmpty);

    expect(find.text('导入多平台账单'), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.text('导入多平台账单')));
    expect(route, isA<ContainerTransformRoute<bool>>());
  });

  testWidgets('账单导入页支持解析预览、批量修改付款方式并导入到数据库', (tester) async {
    await _setupInMemoryFinanceDb(tester);

    const csvText = '''
微信支付账单明细
----------------------微信支付账单明细列表--------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-11-12 12:00:00,商户消费,麦当劳,巨无霸套餐,支出,¥35.00,零钱,支付成功,wx_101,m_101,/
2026-11-12 18:00:00,商户消费,地铁出行,乘车码,支出,¥4.00,零钱,支付成功,wx_102,m_102,/
''';
    final csvBytes = Uint8List.fromList(utf8.encode(csvText));

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceBillImportScreen(
          onPickFile: () async => (name: 'wechat.csv', bytes: csvBytes),
        ),
      ),
    );
    final pickButton = find.byKey(
      const ValueKey('finance-bill-import-pick-file'),
    );
    await _waitFor(tester, () => pickButton.evaluate().isNotEmpty);

    await tester.tap(pickButton);
    await _waitFor(tester, () => find.text('确认导入 (2 笔)').evaluate().isNotEmpty);

    expect(find.text('微信账单'), findsOneWidget);
    expect(find.text('麦当劳'), findsOneWidget);
    expect(find.text('地铁出行'), findsOneWidget);
    expect(find.text('确认导入 (2 笔)'), findsOneWidget);

    await tester.tap(find.text('批量改付款方式'));
    await _waitFor(tester, () => find.text('银行卡').evaluate().isNotEmpty);
    await tester.tap(find.text('银行卡').last);
    await _waitFor(tester, () => find.text('批量修改付款方式').evaluate().isEmpty);

    await tester.tap(find.byKey(const ValueKey('finance-bill-import-confirm')));
    await _waitFor(tester, () {
      return find
          .byKey(const ValueKey('finance-bill-import-confirm'))
          .evaluate()
          .isEmpty;
    });

    final saved = (await tester.runAsync(FinanceRepository.getTransactions))!;
    expect(saved.length, 2);
    expect(
      saved.every(
        (tx) => tx.paymentMethodUuid == 'finance-system-payment-bank',
      ),
      isTrue,
    );
  });
}
