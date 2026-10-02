@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_sync_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/focus_do_not_disturb_service.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('云端同步账单达到预算阈值时立即提醒', () async {
    SharedPreferences.setMockInitialValues({});
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(false);

    const accountKey = 'finance-sync-budget-alert-test-user';
    const localNotificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const macStatusBarChannel = MethodChannel(
      'countdown_todo/macos_status_bar',
    );
    final notificationBodies = <String>[];
    final notificationShown = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(localNotificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': true,
            'isSoundEnabled': true,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
          };
        case 'show':
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          notificationBodies.add(arguments['body'] as String);
          if (!notificationShown.isCompleted) notificationShown.complete();
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      macStatusBarChannel,
      (call) async => null,
    );
    addTearDown(() async {
      await FocusDoNotDisturbService.setActive(false, force: true);
      messenger.setMockMethodCallHandler(localNotificationChannel, null);
      messenger.setMockMethodCallHandler(macStatusBarChannel, null);
      debugDefaultTargetPlatformOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(true);
    await AppSettingsStorage.setNormalNotificationEnabled(true);
    await FocusDoNotDisturbService.setActive(false, force: true);
    final now = DateTime.now();
    await FinanceStorage.saveBudget(
      FinanceBudget(
        uuid: 'sync-budget-alert',
        monthKey: financeMonthKey(now),
        amountMinor: 10000,
      ),
    );
    final remoteTransaction = FinanceTransaction(
      uuid: 'sync-budget-alert-expense',
      amountMinor: 8000,
      transactionDate: dateKey(now),
      occurredAt: now.millisecondsSinceEpoch,
    );
    final request = await FinanceSyncService.prepare(
      username: accountKey,
      forceFullSync: false,
    );
    final response = <String, dynamic>{
      'sync_capabilities': {'finance_v1': 1},
      'server_finance_categories': <Map<String, dynamic>>[],
      'server_finance_payment_methods': <Map<String, dynamic>>[],
      'server_finance_transactions': [remoteTransaction.toMap()],
      'server_finance_loans': <Map<String, dynamic>>[],
      'server_finance_loan_installments': <Map<String, dynamic>>[],
      'server_finance_budgets': <Map<String, dynamic>>[],
      'server_finance_recurring_rules': <Map<String, dynamic>>[],
      'server_finance_entry_templates': <Map<String, dynamic>>[],
      'finance_acknowledged_changes': <Map<String, dynamic>>[],
      'new_finance_sync_time': now.millisecondsSinceEpoch,
    };

    final result = await FinanceSyncService.finish(
      request: request,
      response: response,
      supported: true,
    );
    await notificationShown.future.timeout(const Duration(seconds: 5));

    expect(result.remoteChangeCount, 1);
    expect(notificationBodies, ['本月总支出 ¥80.00 / ¥100.00']);
  });
}
