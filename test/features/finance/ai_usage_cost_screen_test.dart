@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/screens/ai_usage_cost_screen.dart';
import 'package:countdown_todo/features/finance/services/ai_usage_cost_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _setUpDatabase(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'current_login_user': 'ai-usage-screen-test',
  });
  return (await tester.runAsync(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    return db;
  }))!;
}

Future<void> _pumpLoaded(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  for (var attempt = 0; attempt < 100; attempt++) {
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('AI 用量页面未完成加载');
}

Future<void> _tapBelowTopBar(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    finder.evaluate().first,
    alignment: 0.25,
    duration: Duration.zero,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
}

void main() {
  sqfliteFfiInit();

  for (final seconds in [4, 0]) {
    testWidgets(
      'ASR statistics show duration and billing state: $seconds seconds',
      (tester) async {
        final db = await _setUpDatabase(tester);
        addTearDown(() async {
          AiUsageCostService.databaseOverride = null;
          FinanceStorage.databaseOverride = null;
          await db.close();
        });
        await tester.runAsync(
          () => AiUsageCostService.recordUsage(
            provider: 'mimo',
            model: 'mimo-v2.5-asr',
            operation: 'voice_asr',
            promptTokens: 66000,
            completionTokens: 0,
            totalTokens: 66000,
            audioSeconds: seconds,
          ),
        );
        await _pumpLoaded(tester, const AiUsageCostScreen());
        final duration = seconds > 0 ? '录音 4 秒' : '录音时长未返回';
        expect(
          find.text('1 次 · $duration${seconds == 0 ? ' · 1 次待定价' : ''}'),
          findsOneWidget,
        );
        final record = find.text('语音识别 · $duration');
        await tester.scrollUntilVisible(
          record,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        expect(record, findsOneWidget);
        expect(find.text('66,000 Token'), findsNothing);
        final recordTile = find.ancestor(
          of: record,
          matching: find.byType(ListTile),
        );
        if (seconds == 0) {
          expect(
            find.descendant(of: recordTile, matching: find.text('待定价')),
            findsOneWidget,
          );
        } else {
          expect(
            find.descendant(
              of: recordTile,
              matching: find.text(AiUsageCostService.formatMicros(556)),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), null);
      },
    );
  }

  testWidgets('non-MiMo providers display token usage for the same model name',
      (tester) async {
    final db = await _setUpDatabase(tester);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await tester.runAsync(() async {
      await AiUsageCostService.savePricing(
        const AiUsagePricing(
          provider: 'custom',
          model: 'mimo-v2.5-asr',
          inputMicrosPerMillion: 1000000,
          outputMicrosPerMillion: 2000000,
        ),
      );
      await AiUsageCostService.recordUsage(
        provider: 'custom',
        model: 'mimo-v2.5-asr',
        operation: 'audio_chat',
        promptTokens: 1000,
        completionTokens: 500,
        totalTokens: 1500,
        audioSeconds: 4,
      );
    });

    await _pumpLoaded(tester, const AiUsageCostScreen());

    expect(find.text('1 次 · 1,500 Token · 音频 4s'), findsOneWidget);
    final record = find.text('audio_chat · 1,500 Token · 音频 4s');
    await tester.scrollUntilVisible(
      record,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(record, findsOneWidget);
    expect(find.text('录音 4 秒'), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('自动记账说明与月度汇总周期一致', (tester) async {
    final db = await _setUpDatabase(tester);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    await _pumpLoaded(tester, const AiUsageCostScreen());

    expect(
      find.text('同一设备内按月份、服务商与模型合并为一笔支出；多设备账单分别记录并累计'),
      findsOneWidget,
    );
  });

  testWidgets('内置价格提供可见的恢复入口并在恢复前确认', (tester) async {
    final db = await _setUpDatabase(tester);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await tester.runAsync(
      () => AiUsageCostService.savePricing(
        const AiUsagePricing(
          provider: 'mimo',
          model: 'mimo-v2.5',
          inputMicrosPerMillion: 123456,
          outputMicrosPerMillion: 234567,
        ),
      ),
    );
    await _pumpLoaded(tester, const AiUsageCostScreen(managePricing: true));

    final modelCard = find.ancestor(
      of: find.text('mimo · mimo-v2.5 · 内置'),
      matching: find.byType(Card),
    );
    final restoreButton = find.descendant(
      of: modelCard,
      matching: find.byTooltip('恢复内置单价'),
    );
    await tester.scrollUntilVisible(
      restoreButton,
      240,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 12,
    );
    await _tapBelowTopBar(tester, restoreButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('恢复内置单价'), findsOneWidget);
    expect(find.text('将“mimo · mimo-v2.5”恢复为应用内置价格。'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    var pricing = await tester.runAsync(AiUsageCostService.getPricing) ?? [];
    expect(
      pricing
          .firstWhere((item) => item.id == 'mimo::mimo-v2.5')
          .inputMicrosPerMillion,
      123456,
    );

    await _tapBelowTopBar(tester, restoreButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pump();
    for (var attempt = 0; attempt < 100; attempt++) {
      pricing = await tester.runAsync(AiUsageCostService.getPricing) ?? pricing;
      if (pricing
              .firstWhere((item) => item.id == 'mimo::mimo-v2.5')
              .inputMicrosPerMillion ==
          1000000) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(
      pricing
          .firstWhere((item) => item.id == 'mimo::mimo-v2.5')
          .inputMicrosPerMillion,
      1000000,
    );
  });

  testWidgets('无效或溢出的单价不会被保存为零', (tester) async {
    final db = await _setUpDatabase(tester);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await _pumpLoaded(tester, const AiUsageCostScreen(managePricing: true));

    await tester.tap(find.text('添加单价'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'custom');
    await tester.enterText(fields.at(1), 'overflow-model');
    await tester.enterText(fields.at(3), '1e309');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('单价须为有限的非负数字，留空按 0 处理'), findsOneWidget);
    var pricing = await tester.runAsync(AiUsageCostService.getPricing) ?? [];
    expect(pricing.any((item) => item.id == 'custom::overflow-model'), isFalse);
    expect(tester.takeException(), isNull);

    await tester.enterText(fields.at(3), '1.25');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    pricing = await tester.runAsync(AiUsageCostService.getPricing) ?? [];
    expect(
      pricing
          .firstWhere((item) => item.id == 'custom::overflow-model')
          .inputMicrosPerMillion,
      1250000,
    );
    expect(tester.takeException(), isNull);
  });
}
