import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FinanceRepository.cumulativeBalanceTrend', () {
    test('shows twelve completed months ending at the selected month', () {
      final nowAt = DateTime(2026, 12, 10, 12).millisecondsSinceEpoch;
      final points = FinanceRepository.cumulativeBalanceTrend(
        events: [
          FinanceCumulativeBalanceEvent(
            transactionDate: '2025-11-15',
            eventAt: DateTime(2025, 11, 15, 12).millisecondsSinceEpoch,
            changeMinor: 1000,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-10-31',
            eventAt: DateTime(2026, 10, 31, 23, 59).millisecondsSinceEpoch,
            changeMinor: -200,
          ),
        ],
        selectedMonth: DateTime(2026, 10),
        nowAt: nowAt,
        openingBalanceMinor: 5000,
        openingBalanceStartDate: '2025-11-01',
      );

      expect(points, hasLength(12));
      expect(points.first.month, DateTime(2025, 11));
      expect(points.first.balanceMinor, 6000);
      expect(points.last.month, DateTime(2026, 10));
      expect(points.last.balanceMinor, 5800);
      expect(points.last.isCurrentMonth, isFalse);
    });

    test('current month stops at now and future selection is clamped', () {
      final nowAt = DateTime(2026, 10, 15, 12).millisecondsSinceEpoch;
      final points = FinanceRepository.cumulativeBalanceTrend(
        events: [
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-10-01',
            eventAt: DateTime(2026, 10, 1, 8).millisecondsSinceEpoch,
            changeMinor: 300,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-10-15',
            eventAt: DateTime(2026, 10, 15, 11).millisecondsSinceEpoch,
            changeMinor: -50,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-10-15',
            eventAt: DateTime(2026, 10, 15, 13).millisecondsSinceEpoch,
            changeMinor: 900,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-11-01',
            eventAt: DateTime(2026, 11, 1, 8).millisecondsSinceEpoch,
            changeMinor: -200,
          ),
        ],
        selectedMonth: DateTime(2027, 4),
        nowAt: nowAt,
        openingBalanceMinor: 1000,
        openingBalanceStartDate: '2026-01-01',
      );

      expect(points, hasLength(10));
      expect(points.last.month, DateTime(2026, 10));
      expect(points.last.balanceMinor, 1250);
      expect(points.last.isCurrentMonth, isTrue);
    });

    test('mid-month opening date is inclusive and hides earlier months', () {
      final nowAt = DateTime(2026, 10, 15, 12).millisecondsSinceEpoch;
      final points = FinanceRepository.cumulativeBalanceTrend(
        events: [
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-08-01',
            eventAt: DateTime(2026, 8, 1, 8).millisecondsSinceEpoch,
            changeMinor: 999,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-08-20',
            eventAt: DateTime(2026, 8, 20, 8).millisecondsSinceEpoch,
            changeMinor: 300,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-09-07',
            eventAt: DateTime(2026, 9, 7, 8).millisecondsSinceEpoch,
            changeMinor: -100,
          ),
          FinanceCumulativeBalanceEvent(
            transactionDate: '2026-10-15',
            eventAt: DateTime(2026, 10, 15, 10).millisecondsSinceEpoch,
            changeMinor: 200,
          ),
        ],
        selectedMonth: DateTime(2026, 10),
        nowAt: nowAt,
        openingBalanceMinor: 5000,
        openingBalanceStartDate: '2026-08-20',
      );

      expect(points.map((point) => point.month), [
        DateTime(2026, 8),
        DateTime(2026, 9),
        DateTime(2026, 10),
      ]);
      expect(points.map((point) => point.balanceMinor), [5300, 5200, 5400]);
    });

    test('handles leap February and a negative cumulative balance', () {
      final nowAt = DateTime(2024, 3, 15, 12).millisecondsSinceEpoch;
      final points = FinanceRepository.cumulativeBalanceTrend(
        events: [
          FinanceCumulativeBalanceEvent(
            transactionDate: '2024-02-29',
            eventAt: DateTime(2024, 2, 29, 12).millisecondsSinceEpoch,
            changeMinor: -1250,
          ),
        ],
        selectedMonth: DateTime(2024, 3),
        nowAt: nowAt,
        openingBalanceMinor: 0,
      );

      expect(points, hasLength(12));
      final february = points.singleWhere((point) => point.month.month == 2);
      expect(february.month, DateTime(2024, 2));
      expect(february.balanceMinor, -1250);
      expect(points.last.isCurrentMonth, isTrue);
    });

    test(
      'returns no points before opening date or with no balance history',
      () {
        final nowAt = DateTime(2026, 10, 15, 12).millisecondsSinceEpoch;
        expect(
          FinanceRepository.cumulativeBalanceTrend(
            events: const [],
            selectedMonth: DateTime(2026, 10),
            nowAt: nowAt,
            openingBalanceMinor: 0,
          ),
          isEmpty,
        );
        expect(
          FinanceRepository.cumulativeBalanceTrend(
            events: const [],
            selectedMonth: DateTime(2026, 10),
            nowAt: nowAt,
            openingBalanceMinor: 5000,
            openingBalanceStartDate: '2026-11-01',
          ),
          isEmpty,
        );
      },
    );

    testWidgets('overview shows and lets the user select a monthly point', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 15, 12);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          ),
          home: Scaffold(
            body: FinanceOverviewPanel(
              month: DateTime(2026, 10),
              clock: () => now,
              summary: const FinanceSummary(),
              transactions: const [],
              cumulativeBalanceEvents: [
                FinanceCumulativeBalanceEvent(
                  transactionDate: '2026-10-15',
                  eventAt: DateTime(2026, 10, 15, 8).millisecondsSinceEpoch,
                  changeMinor: 500,
                ),
              ],
              openingBalanceMinor: 10000,
              openingBalanceStartDate: '2025-01-01',
              categories: const {},
              onAdd: () {},
              onEditOpeningBalance: () {},
              addActionKey: GlobalKey(),
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('月度累计结余趋势'));
      await tester.pump();

      expect(find.text('月度累计结余趋势'), findsOneWidget);
      expect(find.text('2026年10月 · 截至今天'), findsOneWidget);
      expect(find.text(formatFinanceAmount(10500)), findsNWidgets(2));
      final chart = find.byKey(
        const ValueKey('finance-cumulative-balance-trend-chart'),
      );
      expect(chart, findsOneWidget);
      await tester.tapAt(
        Offset(tester.getTopLeft(chart).dx + 19, tester.getCenter(chart).dy),
      );
      await tester.pump();

      expect(find.text('2025年11月 · 月末'), findsOneWidget);
      expect(find.text(formatFinanceAmount(10000)), findsOneWidget);
      expect(find.text('累计结余'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark large text keeps the trend usable on a narrow phone', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 15, 12);
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: FinanceOverviewPanel(
              month: DateTime(2026, 10),
              clock: () => now,
              summary: const FinanceSummary(),
              transactions: const [],
              cumulativeBalanceEvents: [
                FinanceCumulativeBalanceEvent(
                  transactionDate: '2026-10-01',
                  eventAt: DateTime(2026, 10, 1, 8).millisecondsSinceEpoch,
                  changeMinor: 500,
                ),
              ],
              openingBalanceMinor: 10000,
              openingBalanceStartDate: '2026-01-01',
              categories: const {},
              onAdd: () {},
              onEditOpeningBalance: () {},
              addActionKey: GlobalKey(),
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FinanceOverviewPanel), findsOneWidget);
      await tester.scrollUntilVisible(find.text('月度累计结余趋势'), 320);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('finance-cumulative-balance-trend-chart')),
        180,
      );
      await tester.pump();

      expect(find.text('月度累计结余趋势'), findsOneWidget);
      expect(find.text('累计结余'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
