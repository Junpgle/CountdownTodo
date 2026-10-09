@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_loan_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
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
  fail('UI did not load');
}

void configureView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(false);
  });
  tearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  for (final page in ['list', 'detail']) {
    testWidgets('$page 贷款页在同步还款后应刷新状态', (tester) async {
      configureView(tester);
      final loan = FinanceLoan(
        uuid: 'audit-loan',
        name: '审查贷款',
        principalMinor: 10000,
        termMonths: 1,
        startDate: '2026-01-01',
        repaymentDay: 1,
      );
      late FinanceLoanInstallment installment;
      await tester.runAsync(() async {
        await FinanceStorage.saveLoan(loan);
        installment = (await FinanceStorage.getLoanInstallments(loan.uuid))
            .single;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: page == 'list'
              ? const FinanceLoanScreen()
              : FinanceLoanDetailScreen(loan: loan),
        ),
      );
      await waitFor(
        tester,
        () => page == 'list'
            ? find
                  .byKey(ValueKey('finance-loan-card-${loan.uuid}'))
                  .evaluate()
                  .isNotEmpty
            : find
                  .byKey(
                    ValueKey('finance-loan-installment-${installment.uuid}'),
                  )
                  .evaluate()
                  .isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final remote = FinanceLoanInstallment.fromMap(installment.toMap())
          ..isPaid = true
          ..paidAt = DateTime(2026, 9, 1).millisecondsSinceEpoch
          ..paymentMethodUuid = 'finance-system-payment-cash'
          ..version = installment.version + 1
          ..updatedAt = installment.updatedAt + 10000;
        expect(
          await FinanceStorage.mergeRemoteBundle({
            'loan_installments': [remote.toMap()],
          }),
          1,
        );
        expect(
          (await FinanceStorage.getLoanInstallment(installment.uuid))!.isPaid,
          true,
        );
      });
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final refreshed = page == 'list'
          ? find.text('0 笔还款中 · 1 笔已还清').evaluate().isNotEmpty
          : find.text('已还 1').evaluate().isNotEmpty;
      if (page == 'list') {
        expect(find.text('0 笔还款中 · 1 笔已还清'), findsOneWidget);
      } else {
        expect(find.text('已还 1'), findsOneWidget);
        expect(find.text('撤销已还'), findsOneWidget);
      }
      expect(refreshed, true, reason: '同步完成后无需手动刷新');
    });
  }
}
