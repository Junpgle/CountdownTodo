import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_text_parser.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedNow = DateTime(2026, 8, 29, 10, 30);

  test('解析约定的多行记账格式', () {
    final drafts = FinanceTextParser.parse(
      '''#记账
类型: 支出
金额: 28.50
分类: 餐饮
商家: 午餐
日期: 今天
付款方式: 微信
备注: 工作日午餐''',
      now: fixedNow,
    );

    expect(drafts, hasLength(1));
    expect(drafts.single.type, FinanceTransactionType.expense);
    expect(drafts.single.amountMinor, 2850);
    expect(drafts.single.categoryName, '餐饮');
    expect(drafts.single.merchant, '午餐');
    expect(drafts.single.transactionDate, '2026-08-29');
    expect(drafts.single.paymentMethodName, '微信');
    expect(drafts.single.source, FinanceEntrySource.import);
  });

  test('解析紧凑格式、收入和退款', () {
    final drafts = FinanceTextParser.parse(
      '''#记账 | 收入 | 1000 | 工资 | 八月工资 | 2026-08-01 | 银行卡

#记账 | 退款 | 8.80 | 退款 | 外卖退款 | 昨天''',
      now: fixedNow,
    );

    expect(drafts, hasLength(2));
    expect(drafts[0].type, FinanceTransactionType.income);
    expect(drafts[0].amountMinor, 100000);
    expect(drafts[0].transactionDate, '2026-08-01');
    expect(drafts[1].type, FinanceTransactionType.refund);
    expect(drafts[1].amountMinor, 880);
    expect(drafts[1].transactionDate, '2026-08-28');
  });

  test('解析多个普通多行记账块', () {
    final drafts = FinanceTextParser.parse(
      '''#记账
类型: 支出
金额: 12.50
分类: 餐饮

#记账
类型: 收入
金额: 100
分类: 工资''',
      now: fixedNow,
    );

    expect(drafts, hasLength(2));
    expect(drafts[0].amountMinor, 1250);
    expect(drafts[1].type, FinanceTransactionType.income);
    expect(drafts[1].amountMinor, 10000);
  });

  test('不依赖中文输入法也能识别显式账单字段', () {
    const text = 'amount:12.50\ntype:expense';

    expect(FinanceTextParser.looksLikeFinanceFormat(text), isTrue);
    final drafts = FinanceTextParser.parse(text, now: fixedNow);

    expect(drafts, hasLength(1));
    expect(drafts.single.amountMinor, 1250);
    expect(drafts.single.type, FinanceTransactionType.expense);
  });

  test('提取 AI 的账单块并从正文移除协议内容', () {
    const reply = '''已帮你整理，请确认：
[FINANCE_START]
[{"itemKind":"finance","type":"expense","amount":12.30,"category":"餐饮","merchant":"咖啡店","date":"2026-08-29","paymentMethod":"支付宝","note":null}]
[FINANCE_END]''';

    final drafts = FinanceTextParser.extractAssistantDrafts(reply);

    expect(drafts, hasLength(1));
    expect(drafts.single.amountMinor, 1230);
    expect(drafts.single.source, FinanceEntrySource.ai);
    expect(FinanceTextParser.cleanAssistantContent(reply), '已帮你整理，请确认：');
  });

  test('取餐码和账单可以分别识别，待办不会被误判成账单', () {
    final pickup = <String, dynamic>{
      'itemKind': 'todo',
      'title': '肯德基取餐',
      'remark': '取餐码: 1234',
    };
    final bill = <String, dynamic>{
      'itemKind': 'finance',
      'type': 'expense',
      'amount': 35.6,
      'merchant': '肯德基',
    };

    expect(FinanceTextParser.isFinanceResult(pickup), isFalse);
    expect(FinanceTextParser.isFinanceResult(bill), isTrue);
    final drafts = FinanceTextParser.fromRecognitionResults([pickup, bill]);
    expect(drafts, hasLength(1));
    expect(drafts.single.amountMinor, 3560);
    expect(drafts.single.merchant, '肯德基');
  });

  test('AI 对话历史可以保留未确认的账单草案', () {
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: '请确认这笔账单',
      financeDrafts: [
        FinanceEntryDraft(
          amountMinor: 1999,
          transactionDate: '2026-08-29',
          merchant: '书店',
          source: FinanceEntrySource.ai,
        ),
      ],
    );

    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.financeDrafts, hasLength(1));
    expect(restored.financeDrafts!.single.amountMinor, 1999);
    expect(restored.financeDrafts!.single.merchant, '书店');
    expect(restored.financeDrafts!.single.isAdded, isFalse);
  });

  final now = DateTime(2026, 8, 30, 15, 20);

  group('一句话记账解析', () {
    test('解析支出、商家、付款方式、分类和备注', () {
      final draft = FinanceTextParser.parseOneSentence(
        '今天午餐花了 28.5 元，微信支付，分类餐饮，备注工作日午餐',
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.type, FinanceTransactionType.expense);
      expect(draft.amountMinor, 2850);
      expect(draft.transactionDate, '2026-08-30');
      expect(draft.merchant, '午餐');
      expect(draft.paymentMethodName, '微信');
      expect(draft.categoryName, '餐饮');
      expect(draft.note, '工作日午餐');
      expect(draft.originalText, contains('28.5'));
    });

    test('支持相对日期、千位分隔金额和收入分类', () {
      final draft = FinanceTextParser.parseOneSentence(
        '昨天收到工资 8,000 元，分类工资',
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.type, FinanceTransactionType.income);
      expect(draft.amountMinor, 800000);
      expect(draft.transactionDate, '2026-08-29');
      expect(draft.categoryName, '工资');
    });

    test('支持退款和付款方式', () {
      final draft = FinanceTextParser.parseOneSentence(
        '前天退款 20 元，支付宝',
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.type, FinanceTransactionType.refund);
      expect(draft.amountMinor, 2000);
      expect(draft.transactionDate, '2026-08-28');
      expect(draft.categoryName, '退款');
      expect(draft.paymentMethodName, '支付宝');
    });

    test('未显式写分类时可从常见事项推断分类', () {
      final draft = FinanceTextParser.parseOneSentence(
        '8月29日打车花了 12 元，现金',
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.transactionDate, '2026-08-29');
      expect(draft.amountMinor, 1200);
      expect(draft.merchant, '打车');
      expect(draft.categoryName, '交通');
      expect(draft.paymentMethodName, '现金');
    });

    test('没有金额时不生成草稿', () {
      expect(
        FinanceTextParser.parseOneSentence('今天午餐，微信支付'),
        isNull,
      );
    });
  });
}
