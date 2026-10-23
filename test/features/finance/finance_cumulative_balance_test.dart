import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const startDate = '2026-10-10';
  final now = DateTime(2026, 10, 14, 12);

  test('opening date is based on the earliest occurred ledger date', () {
    final nowAt = now.millisecondsSinceEpoch;
    expect(
      FinanceRepository.defaultCumulativeBalanceStartDate(
        events: [
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-10-20',
            eventAt: nowAt + const Duration(days: 6).inMilliseconds,
            changeMinor: -100,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-09-18',
            eventAt: DateTime(2026, 9, 18).millisecondsSinceEpoch,
            changeMinor: 500,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-10-01',
            eventAt: DateTime(2026, 10, 1).millisecondsSinceEpoch,
            changeMinor: -50,
          ),
        ],
        nowAt: nowAt,
      ),
      '2026-09-18',
    );
  });

  test('future-only ledger defaults the opening date to today', () {
    final nowAt = now.millisecondsSinceEpoch;
    expect(
      FinanceRepository.defaultCumulativeBalanceStartDate(
        events: [
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-10-15',
            eventAt: nowAt + const Duration(hours: 2).inMilliseconds,
            changeMinor: -100,
          ),
        ],
        nowAt: nowAt,
      ),
      '2026-10-14',
    );
    expect(
      FinanceRepository.defaultCumulativeBalanceStartDate(
        events: const [],
        nowAt: nowAt,
      ),
      '2026-10-14',
    );
  });

  test(
    'opening amount and date are stored together and reject future dates',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettingsStorage.setFinanceOpeningBalance(
        'alice',
        amountMinor: 12500,
        startDate: startDate,
        now: now,
      );
      expect(
        await AppSettingsStorage.getFinanceOpeningBalance('alice', now: now),
        (amountMinor: 12500, startDate: startDate),
      );
      expect(
        await AppSettingsStorage.getFinanceOpeningBalance('bob', now: now),
        (amountMinor: 0, startDate: null),
      );
      await expectLater(
        AppSettingsStorage.setFinanceOpeningBalance(
          'alice',
          amountMinor: 12500,
          startDate: '2026-10-15',
          now: now,
        ),
        throwsArgumentError,
      );
      await AppSettingsStorage.clearFinanceOpeningBalance('alice');
      expect(
        await AppSettingsStorage.getFinanceOpeningBalance('alice', now: now),
        (amountMinor: 0, startDate: null),
      );
    },
  );

  test(
    'legacy opening amount is ignored when its date is missing or invalid',
    () async {
      SharedPreferences.setMockInitialValues({
        'finance_opening_balance_amount_alice': 12500,
        'finance_opening_balance_date_alice': '2026-10-15',
      });
      expect(
        await AppSettingsStorage.getFinanceOpeningBalance('alice', now: now),
        (amountMinor: 0, startDate: null),
      );

      SharedPreferences.setMockInitialValues({
        'finance_opening_balance_amount_alice': 12500,
      });
      expect(
        await AppSettingsStorage.getFinanceOpeningBalance('alice', now: now),
        (amountMinor: 0, startDate: null),
      );
    },
  );

  test('cumulative balance applies the start day and as-of boundary', () {
    final asOf = DateTime(2026, 10, 11, 9).millisecondsSinceEpoch;
    final balance = FinanceRepository.cumulativeBalanceAt(
      events: [
        FinanceCumulativeBalanceEvent(
          transactionDate: '2026-10-09',
          eventAt: DateTime(2026, 10, 9, 18).millisecondsSinceEpoch,
          changeMinor: 5000,
        ),
        FinanceCumulativeBalanceEvent(
          transactionDate: startDate,
          eventAt: DateTime(2026, 10, 10, 23).millisecondsSinceEpoch,
          changeMinor: 300,
        ),
        FinanceCumulativeBalanceEvent(
          transactionDate: '2026-10-11',
          eventAt: DateTime(2026, 10, 11, 8).millisecondsSinceEpoch,
          changeMinor: -120,
        ),
        FinanceCumulativeBalanceEvent(
          transactionDate: '2026-10-11',
          eventAt: DateTime(2026, 10, 11, 10).millisecondsSinceEpoch,
          changeMinor: 9999,
        ),
      ],
      asOfAt: asOf,
      openingBalanceMinor: 10000,
      openingBalanceStartDate: startDate,
    );
    expect(balance, 10180);
    expect(
      FinanceRepository.cumulativeBalanceAt(
        events: const [],
        asOfAt: DateTime(2026, 10, 9, 23).millisecondsSinceEpoch,
        openingBalanceMinor: 10000,
        openingBalanceStartDate: startDate,
      ),
      isNull,
    );
  });

  testWidgets('overview shows cumulative balance as of the selected period', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 14, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinanceOverviewPanel(
            month: DateTime(2026, 10),
            summary: const FinanceSummary(),
            transactions: const [],
            cumulativeBalanceEvents: [
              FinanceCumulativeBalanceEvent(
                transactionDate: '2026-10-10',
                eventAt: DateTime(2026, 10, 10, 8).millisecondsSinceEpoch,
                changeMinor: -500,
              ),
              FinanceCumulativeBalanceEvent(
                transactionDate: '2026-10-13',
                eventAt: DateTime(2026, 10, 13, 8).millisecondsSinceEpoch,
                changeMinor: 250,
              ),
            ],
            openingBalanceMinor: 10000,
            openingBalanceStartDate: '2026-10-10',
            categories: const {},
            onAdd: () {},
            onEditOpeningBalance: () {},
            addActionKey: GlobalKey(),
            onRefresh: () async {},
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(find.text('累计结余'), 240);
    await tester.pump();

    expect(find.text('累计结余'), findsOneWidget);
    expect(find.text('截至今天'), findsOneWidget);
    // The current month is also selected by default in the new trend card.
    expect(find.text(formatFinanceAmount(9750)), findsNWidgets(2));
    expect(find.byTooltip('设置期初结余'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
