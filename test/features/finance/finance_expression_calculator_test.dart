import 'package:countdown_todo/features/finance/services/finance_expression_calculator.dart';
import 'package:countdown_todo/features/finance/widgets/finance_amount_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('记账金额计算式', () {
    test('遵循括号和四则运算优先级', () {
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('12+3*4'),
        ),
        '24',
      );
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('(12+3)*4'),
        ),
        '60',
      );
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('10÷(2+3)'),
        ),
        '2',
      );
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('-2+5'),
        ),
        '3',
      );
    });

    test('结果按分四舍五入并去掉多余的小数零', () {
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('12'),
        ),
        '12',
      );
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('12.3'),
        ),
        '12.3',
      );
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('10/3'),
        ),
        '3.33',
      );
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('2.01/2'),
        ),
        '1.01',
      );
      expect(
        FinanceExpressionCalculator.formatResult(
          FinanceExpressionCalculator.evaluate('0.29/2'),
        ),
        '0.15',
      );
    });

    test('拒绝不完整表达式、精确除零和不完整括号', () {
      expect(
        () => FinanceExpressionCalculator.evaluate('12+'),
        throwsA(isA<FinanceExpressionException>()),
      );
      expect(
        () => FinanceExpressionCalculator.evaluate('(12+3'),
        throwsA(isA<FinanceExpressionException>()),
      );
      expect(
        () => FinanceExpressionCalculator.evaluate('12/0'),
        throwsA(isA<FinanceExpressionException>()),
      );
      expect(
        () => FinanceExpressionCalculator.evaluate('1/(0.1+0.2-0.3)'),
        throwsA(isA<FinanceExpressionException>()),
      );
    });
  });

  testWidgets('计算过程可通过光标、删除键继续编辑', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: const Scaffold(body: FinanceAmountCalculatorSheet()),
      ),
    );

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('finance-calculator-expression')),
          )
          .readOnly,
      isTrue,
    );

    Future<void> tapKey(String keyName) async {
      await tester.tap(find.byKey(ValueKey('finance-calculator-key-$keyName')));
      await tester.pump();
    }

    await tapKey('1');
    await tapKey('2');
    await tapKey('add');
    await tapKey('3');
    await tapKey('equals');
    expect(find.text('使用结果 ¥15'), findsOneWidget);

    await tapKey('backspace');
    await tapKey('4');
    await tapKey('equals');
    expect(find.text('使用结果 ¥16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
