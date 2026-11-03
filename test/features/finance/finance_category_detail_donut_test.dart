import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_category_detail_screen.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FinanceCategoryDetailScreen Donut Chart & Subcategory Percentage', () {
    testWidgets('小类列表展示环形图及各小类占比，并支持交互高亮查看', (tester) async {
      final now = DateTime(2026, 10, 15);
      final root = FinanceCategory(uuid: 'root-food', name: '餐饮', icon: '🍜');
      final child1 = FinanceCategory(
        uuid: 'child-tea',
        name: '奶茶',
        icon: '🧋',
        parentUuid: root.uuid,
      );
      final child2 = FinanceCategory(
        uuid: 'child-takeout',
        name: '外卖',
        icon: '🥡',
        parentUuid: root.uuid,
      );
      final transactions = [
        FinanceTransaction(
          uuid: 't1',
          amountMinor: 8000,
          categoryUuid: child1.uuid,
          transactionDate: '2026-10-10',
        ),
        FinanceTransaction(
          uuid: 't2',
          amountMinor: 2000,
          categoryUuid: child2.uuid,
          transactionDate: '2026-10-12',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: FinanceCategoryDetailScreen(
            periodTitle: '2026年10月',
            clock: () => now,
            rootCategoryUuid: root.uuid,
            transactions: transactions,
            categories: {
              root.uuid: root,
              child1.uuid: child1,
              child2.uuid: child2,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证小类标题和列表内容
      expect(find.text('小类'), findsOneWidget);
      expect(find.text('80.0%'), findsOneWidget);
      expect(find.text('20.0%'), findsOneWidget);
      expect(find.text('¥80.00'), findsOneWidget);
      expect(find.text('¥20.00'), findsOneWidget);

      // 验证环形图存在，并且初始显示总净支出和 2 项小类
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('小类净支出'), findsOneWidget);
      expect(find.text('¥100.00'), findsNWidgets(2));
      expect(find.text('共 2 项小类'), findsOneWidget);

      // 点击第 1 项小类的图标触发选中
      await tester.tap(find.text('🧋').last);
      await tester.pumpAndSettle();

      // 环心应更新为奶茶及占比
      expect(find.text('占比 80.0%'), findsOneWidget);

      // 点击第 2 项小类的图标切换选中
      await tester.tap(find.text('🥡').last);
      await tester.pumpAndSettle();

      // 环心应更新为外卖及占比
      expect(find.text('占比 20.0%'), findsOneWidget);

      // 再次点击已选中的图标，重置回总额
      await tester.tap(find.text('🥡').last);
      await tester.pumpAndSettle();

      expect(find.text('小类净支出'), findsOneWidget);
      expect(find.text('共 2 项小类'), findsOneWidget);
    });
  });

  group('Finance Navigation across months without restriction', () {
    testWidgets('概览周视图与日视图支持无限跨月向前翻页，并回调 onMonthChanged', (tester) async {
      DateTime currentMonth = DateTime(2026, 10);
      final transactions = <FinanceTransaction>[];
      final categories = <String, FinanceCategory>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return FinanceOverviewPanel(
                  month: currentMonth,
                  clock: () => DateTime(2026, 10, 1),
                  summary: const FinanceSummary(),
                  transactions: transactions,
                  categories: categories,
                  onAdd: () {},
                  addActionKey: GlobalKey(),
                  onRefresh: () async {},
                  onMonthChanged: (newMonth) {
                    setState(() => currentMonth = newMonth);
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到周视图
      await tester.tap(find.text('周视图'));
      await tester.pumpAndSettle();

      // 点击向左箭头（上一周），应当允许跨月到 9 月，不被 10 月截断
      final prevWeekButton = find.byKey(
        const ValueKey('finance-overview-period-previous'),
      );
      expect(prevWeekButton, findsOneWidget);
      await tester.tap(prevWeekButton);
      await tester.pumpAndSettle();

      // 月份应成功联动更新至 9 月
      expect(currentMonth.month, 9);

      // 再次点击上一周，继续向前翻页
      await tester.tap(prevWeekButton);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('账单面板提供月份周期导航，支持点击上一月翻页', (tester) async {
      DateTime currentMonth = DateTime(2026, 10);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return FinanceLedgerPanel(
                  month: currentMonth,
                  clock: () => DateTime(2026, 10, 15),
                  transactions: const [],
                  categories: const {},
                  paymentMethods: const {},
                  keyword: '',
                  filterType: null,
                  onMonthChanged: (newMonth) {
                    setState(() => currentMonth = newMonth);
                  },
                  onOpenDetail: (transaction, key) {},
                  onKeywordChanged: (_) {},
                  onFilterChanged: (_) {},
                  onEdit: (_) {},
                  onDelete: (_) {},
                  onRefund: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026年10月'), findsOneWidget);

      // 点击上一月按钮
      final prevLedgerButton = find.byKey(
        const ValueKey('finance-ledger-period-previous'),
      );
      expect(prevLedgerButton, findsOneWidget);
      await tester.tap(prevLedgerButton);
      await tester.pumpAndSettle();

      // 账单月份应成功变为 9 月
      expect(currentMonth.month, 9);
      expect(find.text('2026年9月'), findsOneWidget);
    });
  });
}
