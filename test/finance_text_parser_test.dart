import 'package:countdown_todo/features/finance/services/finance_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('相同账单使用不同付款方式时保留为两笔', () {
    final drafts = FinanceTextParser.parseQuickEntries(
      '今天午餐 28 元，微信；今天午餐 28 元，支付宝',
      now: DateTime(2026, 10, 1),
    );

    expect(drafts, hasLength(2));
    expect(
      drafts.map((item) => item.paymentMethodName),
      ['微信', '支付宝'],
    );
  });
}
