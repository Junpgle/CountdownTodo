import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final slices = [
    const FinanceDonutSlice(
      categoryUuid: 'cat-a',
      value: 7500,
      color: Colors.teal,
      label: '餐饮',
      icon: '🍜',
    ),
    const FinanceDonutSlice(
      categoryUuid: 'cat-b',
      value: 2500,
      color: Colors.amber,
      label: '交通',
      icon: '🚇',
    ),
  ];

  test('hitTestFinanceDonutSlice detects center hole, slices, and misses', () {
    const size = 200.0;
    // Center hole
    final centerHit = hitTestFinanceDonutSlice(
      localPosition: const Offset(100, 100),
      chartSize: size,
      slices: slices,
      total: 10000,
    );
    expect(centerHit.isHit, isTrue);
    expect(centerHit.isCenter, isTrue);

    // Top-right on ring (around radius ~84, angle 45 deg -> within first 75% slice)
    final firstHit = hitTestFinanceDonutSlice(
      localPosition: const Offset(184, 100),
      chartSize: size,
      slices: slices,
      total: 10000,
    );
    expect(firstHit.isHit, isTrue);
    expect(firstHit.isCenter, isFalse);
    expect(firstHit.categoryUuid, 'cat-a');

    // Top-left on ring (last 25% slice)
    final secondHit = hitTestFinanceDonutSlice(
      localPosition: const Offset(36, 42),
      chartSize: size,
      slices: slices,
      total: 10000,
    );
    expect(secondHit.isHit, isTrue);
    expect(secondHit.categoryUuid, 'cat-b');

    // Outside ring completely
    final miss = hitTestFinanceDonutSlice(
      localPosition: const Offset(0, 0),
      chartSize: size,
      slices: slices,
      total: 10000,
    );
    expect(miss.isHit, isFalse);
  });

  testWidgets(
    'FinanceCategoryDonutChart switches between total and selected states',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return FinanceCategoryDonutChart(
                  slices: slices,
                  total: 10000,
                  donutSize: 200,
                  sweepAnimation: const AlwaysStoppedAnimation(1.0),
                  colorScheme: Theme.of(context).colorScheme,
                  selectedCategoryUuid: selected,
                  onSelectCategory: (uuid) => setState(() => selected = uuid),
                  totalTitle: '总净支出',
                  countLabel: '共 2 项分类',
                  totalContentKey: 'total-test',
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('总净支出'), findsOneWidget);
      expect(find.text('共 2 项分类'), findsOneWidget);

      // Tap right side of the ring -> selects cat-a (餐饮)
      final box = tester.getRect(find.byType(GestureDetector).first);
      await tester.tapAt(Offset(box.right - 16, box.center.dy));
      await tester.pumpAndSettle();
      expect(selected, 'cat-a');
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('占比 75.0%'), findsOneWidget);

      // Tap center -> clears selection
      await tester.tapAt(box.center);
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.text('总净支出'), findsOneWidget);
    },
  );
}
