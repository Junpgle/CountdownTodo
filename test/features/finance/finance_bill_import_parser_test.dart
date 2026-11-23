import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_bill_import_parser.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final categories = FinanceDefaults.categories
      .map(FinanceCategory.fromMap)
      .toList();
  final paymentMethods = FinanceDefaults.paymentMethods
      .map(FinancePaymentMethod.fromMap)
      .toList();

  group('FinanceBillImportParser', () {
    test(
      'parses WeChat CSV with BOM, refunds, neutral rows, and closed rows',
      () {
        const csvText = '''
微信支付账单明细
昵称：[测试用户]
----------------------微信支付账单明细列表--------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-11-10 12:30:00,商户消费,美团外卖,黄焖鸡米饭,支出,¥28.50,零钱,支付成功,wx_001,m_001,/
2026-11-10 14:00:00,微信红包,好友A,/,收入,¥50.00,零钱,已存入零钱,wx_002,m_002,生日红包
2026-11-10 15:00:00,商户消费,淘宝店铺,退货退款,收入,¥15.00,零钱,已全额退款,wx_003,m_003,/
2026-11-10 16:00:00,零钱通转入,零钱通,/,中性交易,¥100.00,零钱,支付成功,wx_004,m_004,/
2026-11-10 17:00:00,商户消费,测试商户,未完成订单,支出,¥99.00,零钱,交易关闭,wx_005,m_005,/
''';
        final bytes = Uint8List.fromList([
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode(csvText),
        ]);
        final result = FinanceBillImportParser.parseBytes(
          bytes,
          fileName: 'wechat_bill.csv',
          categories: categories,
          paymentMethods: paymentMethods,
        );

        expect(result.platform, FinanceBillPlatform.wechat);
        expect(result.skippedStatusCount, 1);
        expect(result.neutralCount, 1);
        expect(result.items.length, 4);

        final expense = result.items[0];
        expect(expense.type, FinanceTransactionType.expense);
        expect(expense.amountMinor, 2850);
        expect(expense.transactionDate, '2026-11-10');
        expect(expense.merchant, '美团外卖');
        expect(expense.categoryUuid, 'finance-system-category-food-takeout');
        expect(expense.paymentMethodUuid, 'finance-system-payment-wechat');
        expect(expense.selected, isTrue);

        final income = result.items[1];
        expect(income.type, FinanceTransactionType.income);
        expect(income.amountMinor, 5000);
        expect(income.selected, isTrue);

        final refund = result.items[2];
        expect(refund.type, FinanceTransactionType.refund);
        expect(refund.amountMinor, 1500);
        expect(refund.categoryUuid, 'finance-system-category-refund');
        expect(refund.selected, isTrue);

        final neutral = result.items[3];
        expect(neutral.isNeutral, isTrue);
        expect(neutral.selected, isFalse);
      },
    );

    test('parses GBK-encoded Alipay CSV with trailing spaces and duplicate detection', () {
      const alipayCsv = '''
支付宝交易记录明细查询 
账号:[test@example.com] 
---------------------------------交易记录明细列表------------------------------------ 
交易时间 ,交易分类 ,交易对方 ,对方账号 ,商品说明 ,收/支 ,金额 ,收/付款方式 ,交易状态 ,交易订单号 ,商家订单号 ,备注 
2026-11-11 08:15:00 ,餐饮美食 ,瑞幸咖啡 ,luckin@example.com ,生椰拿铁 ,支出 ,18.90 ,花呗 ,交易成功 ,ali_001 ,m_ali_001 , 
2026-11-11 09:00:00 ,交通出行 ,滴滴出行 ,didi@example.com ,快车 ,支出 ,32.00 ,招商银行信用卡(1234) ,交易成功 ,ali_002 ,m_ali_002 , 
2026-11-11 10:00:00 ,投资理财 ,余额宝 ,yeb@example.com ,余额宝转入 ,不计收支 ,500.00 ,支付宝余额 ,交易成功 ,ali_003 ,m_ali_003 , 
2026-11-11 11:00:00 ,日用百货 ,某超市 ,shop@example.com ,纸巾 ,支出 ,12.00 ,花呗 ,交易关闭 ,ali_004 ,m_ali_004 , 
''';
      final bytes = Uint8List.fromList(gbk.encode(alipayCsv));
      final existing = [
        FinanceTransaction(
          type: FinanceTransactionType.expense,
          amountMinor: 1890,
          transactionDate: '2026-11-11',
          occurredAt: DateTime(2026, 11, 11, 8, 15, 30).millisecondsSinceEpoch,
          merchant: '瑞幸咖啡',
        ),
      ];

      final result = FinanceBillImportParser.parseBytes(
        bytes,
        fileName: 'alipay_bill.csv',
        categories: categories,
        paymentMethods: paymentMethods,
        existingTransactions: existing,
      );

      expect(result.platform, FinanceBillPlatform.alipay);
      expect(result.skippedStatusCount, 1);
      expect(result.duplicateCount, 1);
      expect(result.neutralCount, 1);
      expect(result.items.length, 3);

      final coffee = result.items[0];
      expect(coffee.isDuplicate, isTrue);
      expect(coffee.selected, isFalse);
      expect(coffee.categoryUuid, 'finance-system-category-food-coffee');
      expect(coffee.paymentMethodUuid, 'finance-system-payment-alipay');

      final taxi = result.items[1];
      expect(taxi.isDuplicate, isFalse);
      expect(taxi.selected, isTrue);
      expect(taxi.categoryUuid, 'finance-system-category-transport-taxi');
      expect(taxi.paymentMethodUuid, 'finance-system-payment-credit');
    });

    test(
      'parses WeChat XLSX archive with sharedStrings and sparse cell refs',
      () {
        const sharedStringsXml = '''<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>微信支付账单明细</t></si>
  <si><t>交易时间</t></si>
  <si><t>交易类型</t></si>
  <si><t>交易对方</t></si>
  <si><t>商品</t></si>
  <si><t>收/支</t></si>
  <si><t>金额(元)</t></si>
  <si><t>支付方式</t></si>
  <si><t>当前状态</t></si>
  <si><t>2026-11-12 19:20:00</t></si>
  <si><t>商户消费</t></si>
  <si><t>星巴克</t></si>
  <si><t>美式咖啡</t></si>
  <si><t>支出</t></si>
  <si><t>¥33.00</t></si>
  <si><t>零钱</t></si>
  <si><t>支付成功</t></si>
</sst>''';

        const sheet1Xml = '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c></row>
    <row r="2">
      <c r="A2" t="s"><v>1</v></c>
      <c r="B2" t="s"><v>2</v></c>
      <c r="C2" t="s"><v>3</v></c>
      <c r="D2" t="s"><v>4</v></c>
      <c r="E2" t="s"><v>5</v></c>
      <c r="F2" t="s"><v>6</v></c>
      <c r="G2" t="s"><v>7</v></c>
      <c r="H2" t="s"><v>8</v></c>
    </row>
    <row r="3">
      <c r="A3" t="s"><v>9</v></c>
      <c r="B3" t="s"><v>10</v></c>
      <c r="C3" t="s"><v>11</v></c>
      <c r="D3" t="s"><v>12</v></c>
      <c r="E3" t="s"><v>13</v></c>
      <c r="F3" t="s"><v>14</v></c>
      <c r="G3" t="s"><v>15</v></c>
      <c r="H3" t="s"><v>16</v></c>
    </row>
  </sheetData>
</worksheet>''';

        final archive = Archive()
          ..addFile(
            ArchiveFile(
              'xl/sharedStrings.xml',
              utf8.encode(sharedStringsXml).length,
              utf8.encode(sharedStringsXml),
            ),
          )
          ..addFile(
            ArchiveFile(
              'xl/worksheets/sheet1.xml',
              utf8.encode(sheet1Xml).length,
              utf8.encode(sheet1Xml),
            ),
          );
        final xlsxBytes = Uint8List.fromList(ZipEncoder().encode(archive));

        final result = FinanceBillImportParser.parseBytes(
          xlsxBytes,
          fileName: 'wechat_bill.xlsx',
          categories: categories,
          paymentMethods: paymentMethods,
        );

        expect(result.platform, FinanceBillPlatform.wechat);
        expect(result.items.length, 1);
        final item = result.items.first;
        expect(item.merchant, '星巴克');
        expect(item.amountMinor, 3300);
        expect(item.categoryUuid, 'finance-system-category-food-coffee');
        expect(item.paymentMethodUuid, 'finance-system-payment-wechat');
      },
    );

    test('maps campus card recharge to transfer, excludes from summary, and updates both balances', () {
      final campusMethod = FinancePaymentMethod(
        uuid: 'pm-campus-card',
        name: '校园卡',
        icon: '🎓',
      );
      final methodsWithCampus = [...paymentMethods, campusMethod];

      const csvText = '''
微信支付账单明细
----------------------微信支付账单明细列表--------------------
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-11-13 08:00:00,商户消费,XX大学校园卡中心,校园卡充值,支出,¥100.00,招商银行储蓄卡(0001),支付成功,wx_201,m_201,/
2026-11-13 12:00:00,商户消费,学校第一食堂,午饭,支出,¥15.00,零钱,支付成功,wx_203,m_203,/
''';
      final bytes = Uint8List.fromList(utf8.encode(csvText));
      final result = FinanceBillImportParser.parseBytes(
        bytes,
        fileName: 'campus_wechat.csv',
        categories: categories,
        paymentMethods: methodsWithCampus,
      );

      expect(result.items.length, 2);
      final transferItem = result.items[0];
      expect(transferItem.type, FinanceTransactionType.transfer);
      expect(transferItem.selected, isTrue);
      expect(transferItem.paymentMethodUuid, 'finance-system-payment-bank');
      expect(transferItem.targetPaymentMethodUuid, 'pm-campus-card');

      final txs = result.items.map((e) => e.toTransaction()).toList();
      final summary = FinanceSummary.fromTransactions(txs);
      expect(summary.expenseMinor, 1500);
      expect(summary.incomeMinor, 0);

      final snapshotAt = DateTime(2026, 11, 13, 7, 0).millisecondsSinceEpoch;
      final asOfAt = DateTime(2026, 11, 13, 23, 59).millisecondsSinceEpoch;
      final balances = FinanceRepository.paymentMethodBalancesAt(
        snapshots: [
          FinanceBudget(
            monthKey: '2026-11',
            paymentMethodUuid: 'finance-system-payment-bank',
            amountMinor: 50000,
            balanceSnapshotAt: snapshotAt,
          ),
          FinanceBudget(
            monthKey: '2026-11',
            paymentMethodUuid: 'pm-campus-card',
            amountMinor: 2000,
            balanceSnapshotAt: snapshotAt,
          ),
        ],
        transactions: txs,
        loanRepayments: const [],
        loanInterestTransactionUuids: const {},
        asOfAt: asOfAt,
      );

      expect(balances['finance-system-payment-bank'], 40000);
      expect(balances['pm-campus-card'], 12000);
    });

    test(
      'parses Chinese bank CSV with split date/time and debit/credit columns',
      () {
        const bankCsv = '''
招商银行个人银行交易流水明细
交易日期,交易时间,收入金额,支出金额,交易摘要,对方户名,交易附言
2026-11-14,09:30:00,,42.50,快捷支付,美团外卖,午餐
2026-11-14,18:00:00,8500.00,,代发工资,XX科技有限公司,11月工资
''';
        final result = FinanceBillImportParser.parseBytes(
          Uint8List.fromList(utf8.encode(bankCsv)),
          fileName: 'cmb_statement.csv',
          categories: categories,
          paymentMethods: paymentMethods,
        );

        expect(result.platform, FinanceBillPlatform.bank);
        expect(result.items.length, 2);

        final expense = result.items[0];
        expect(expense.type, FinanceTransactionType.expense);
        expect(expense.amountMinor, 4250);
        expect(expense.transactionDate, '2026-11-14');
        expect(expense.merchant, '美团外卖');
        expect(expense.paymentMethodUuid, 'finance-system-payment-bank');
        expect(expense.categoryUuid, 'finance-system-category-food-takeout');

        final income = result.items[1];
        expect(income.type, FinanceTransactionType.income);
        expect(income.amountMinor, 850000);
        expect(income.categoryUuid, 'finance-system-category-salary');
      },
    );

    test(
      'parses third-party accounting app CSV with transfer target account',
      () {
        const qianjiCsv = '''
钱迹账单导出
时间,分类,类型,金额,账户1,账户2,备注
2026-11-15 10:00:00,餐饮,支出,25.00,支付宝,,早饭
2026-11-15 11:00:00,转账,转账,1000.00,银行卡,微信,转入零钱
''';
        final result = FinanceBillImportParser.parseBytes(
          Uint8List.fromList(utf8.encode(qianjiCsv)),
          fileName: 'qianji_export.csv',
          categories: categories,
          paymentMethods: paymentMethods,
        );

        expect(result.platform, FinanceBillPlatform.thirdPartyApp);
        expect(result.items.length, 2);

        expect(result.items[0].type, FinanceTransactionType.expense);
        expect(result.items[0].amountMinor, 2500);
        expect(
          result.items[0].paymentMethodUuid,
          'finance-system-payment-alipay',
        );

        final transfer = result.items[1];
        expect(transfer.type, FinanceTransactionType.transfer);
        expect(transfer.amountMinor, 100000);
        expect(transfer.paymentMethodUuid, 'finance-system-payment-bank');
        expect(
          transfer.targetPaymentMethodUuid,
          'finance-system-payment-wechat',
        );
        expect(transfer.selected, isTrue);
      },
    );

    test(
      'parses TSV and signed-amount generic CSV without direction column',
      () {
        const tsvText =
            'Date\tMerchant\tCategory\tAmount\tAccount\tNotes\n'
            '2026/11/16 08:20:00\tStarbucks\t咖啡\t-32.00\t信用卡\tLatte\n'
            '2026/11/16 17:00:00\tACME Corp\t工资\t+6000.00\t银行卡\tPayroll\n';
        final result = FinanceBillImportParser.parseBytes(
          Uint8List.fromList(utf8.encode(tsvText)),
          fileName: 'generic_bill.tsv',
          categories: categories,
          paymentMethods: paymentMethods,
        );

        expect(result.platform, FinanceBillPlatform.generic);
        expect(result.items.length, 2);
        expect(result.items[0].type, FinanceTransactionType.expense);
        expect(result.items[0].amountMinor, 3200);
        expect(
          result.items[0].paymentMethodUuid,
          'finance-system-payment-credit',
        );
        expect(
          result.items[0].categoryUuid,
          'finance-system-category-food-coffee',
        );

        expect(result.items[1].type, FinanceTransactionType.income);
        expect(result.items[1].amountMinor, 600000);
        expect(
          result.items[1].paymentMethodUuid,
          'finance-system-payment-bank',
        );
      },
    );

    test('parses JSON bill file', () {
      final jsonText = jsonEncode({
        'source': 'custom',
        'transactions': [
          {
            'date': '2026-11-17 12:15:00',
            'type': 'expense',
            'amount': 48.8,
            'merchant': '肯德基',
            'category': '餐饮',
            'account': '微信',
            'note': '午饭',
            'orderId': 'json_001',
          },
          {
            'date': '2026-11-17 15:00:00',
            'type': 'income',
            'amount': 200,
            'merchant': '报销',
            'category': '奖金',
            'account': '银行卡',
            'orderId': 'json_002',
          },
        ],
      });
      final result = FinanceBillImportParser.parseBytes(
        Uint8List.fromList(utf8.encode(jsonText)),
        fileName: 'bills.json',
        categories: categories,
        paymentMethods: paymentMethods,
      );

      expect(result.platform, FinanceBillPlatform.generic);
      expect(result.items.length, 2);
      expect(result.items[0].type, FinanceTransactionType.expense);
      expect(result.items[0].amountMinor, 4880);
      expect(result.items[0].merchant, '肯德基');
      expect(result.items[1].type, FinanceTransactionType.income);
      expect(result.items[1].amountMinor, 20000);
    });

    test('parses OFX and QIF bank statements', () {
      const ofxText = '''
OFXHEADER:100
DATA:OFXSGML
<OFX>
<BANKMSGSRSV1>
<STMTTRNRS>
<STMTRS>
<BANKACCTFROM>
<ACCTID>6222021234567890
<ACCTTYPE>CHECKING
</BANKACCTFROM>
<BANKTRANLIST>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261116103000
<TRNAMT>-128.50
<FITID>OFX_001
<NAME>Apple Store
<MEMO>App Store
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261117090000
<TRNAMT>3000.00
<FITID>OFX_002
<NAME>Employer
<MEMO>Salary
</STMTTRN>
</BANKTRANLIST>
</STMTRS>
</STMTTRNRS>
</BANKMSGSRSV1>
</OFX>
''';
      final ofxResult = FinanceBillImportParser.parseBytes(
        Uint8List.fromList(utf8.encode(ofxText)),
        fileName: 'bank.ofx',
        categories: categories,
        paymentMethods: paymentMethods,
      );
      expect(ofxResult.platform, FinanceBillPlatform.bank);
      expect(ofxResult.items.length, 2);
      expect(ofxResult.items[0].type, FinanceTransactionType.expense);
      expect(ofxResult.items[0].amountMinor, 12850);
      expect(ofxResult.items[0].transactionDate, '2026-11-16');
      expect(ofxResult.items[0].orderId, 'OFX_001');
      expect(ofxResult.items[1].type, FinanceTransactionType.income);
      expect(ofxResult.items[1].amountMinor, 300000);

      const qifText = '''
!Type:CCard
D11/16/2026
T-56.00
P麦当劳
M晚餐
L餐饮
^
D11/17/2026
T100.00
P还款
L[银行卡]
^
''';
      final qifResult = FinanceBillImportParser.parseBytes(
        Uint8List.fromList(utf8.encode(qifText)),
        fileName: 'card.qif',
        categories: categories,
        paymentMethods: paymentMethods,
      );
      expect(qifResult.platform, FinanceBillPlatform.bank);
      expect(qifResult.items.length, 2);
      expect(qifResult.items[0].type, FinanceTransactionType.expense);
      expect(qifResult.items[0].amountMinor, 5600);
      expect(qifResult.items[0].transactionDate, '2026-11-16');
      expect(
        qifResult.items[0].paymentMethodUuid,
        'finance-system-payment-credit',
      );
      expect(qifResult.items[1].type, FinanceTransactionType.transfer);
      expect(qifResult.items[1].amountMinor, 10000);
    });
  });
}
