@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:countdown_todo/features/finance/services/ai_usage_cost_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/mimo_asr_service.dart';
import 'package:countdown_todo/services/quick_voice_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  final wav = encodePcmWav(Uint8List(32000), sampleRate: 16000);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'voice-billing-test',
    });
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;
    await AiUsageCostService.setAutoLedgerEnabled(false);
  });

  tearDown(() async {
    AiUsageCostService.databaseOverride = null;
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  MimoAsrService service({
    Map<String, Object>? usage,
    int status = 200,
    String text = '明天交报告',
  }) {
    final result = MimoAsrService(
      authorize: () async => true,
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': text},
                },
              ],
              'usage': ?usage,
            }),
          ),
          status,
        ),
      ),
    );
    addTearDown(result.dispose);
    return result;
  }

  test('ASR response writes real usage, duration price and chat cost summary exactly once', () async {
    final result = await service(
      usage: {
        'seconds': 4,
        'prompt_tokens': 46000,
        'completion_tokens': 20000,
        'total_tokens': 66000,
        'prompt_tokens_details': {
          'audio_tokens': 25000,
          'cached_tokens': 45000,
        },
      },
    ).transcribeWithUsage(wavBytes: wav, apiKey: 'synthetic-key');

    final rows = await db.query('ai_usage_records');
    expect(rows, hasLength(1));
    expect(rows.single['operation'], 'voice_asr');
    expect(rows.single['provider'], 'mimo');
    expect(rows.single['model'], 'mimo-v2.5-asr');
    expect(rows.single['audio_seconds'], 4);
    expect(rows.single['audio_tokens'], 25000);
    expect(rows.single['total_tokens'], 66000);
    expect(rows.single['cost_micros'], 556);
    expect(rows.single['is_priced'], 1);
    expect(result.text, '明天交报告');
    expect(result.usageSummary?.costMicros, 556);
    expect(result.usageSummary?.audioSeconds, 4);
    expect(result.usageSummary?.calls, 1);
    expect(await db.query('finance_transactions'), isEmpty);

    final summary = await AiUsageCostService.getSummary(
      from: DateTime(2020),
      to: DateTime(2100),
    );
    expect(summary.calls, 1);
    expect(summary.costMicros, 556);
    expect(summary.breakdowns.single.audioSeconds, 4);
  });

  test('ASR calls accumulate in a single monthly bill and reconciliation is idempotent', () async {
    await AiUsageCostService.setAutoLedgerEnabled(true);
    final asr = service(usage: {'seconds': 60});
    for (var i = 0; i < 2; i++) {
      await asr.transcribeWithUsage(wavBytes: wav, apiKey: 'synthetic-key');
    }
    expect(await db.query('ai_usage_records'), hasLength(2));
    var bills = await db.query('finance_transactions', where: 'is_deleted = 0');
    expect(bills, hasLength(1));
    expect(bills.single['amount_minor'], 2);
    expect(bills.single['category_uuid'], 'finance-system-category-ai-service');
    final id = bills.single['uuid'];
    expect(
      (await db.query('ai_usage_ledger_links')).single['ledger_key'],
      contains('|mimo|mimo-v2.5-asr'),
    );
    await AiUsageCostService.reconcileCurrentMonth();
    await AiUsageCostService.reconcileCurrentMonth();
    bills = await db.query('finance_transactions', where: 'is_deleted = 0');
    expect(bills, hasLength(1));
    expect(bills.single['uuid'], id);
    expect(bills.single['amount_minor'], 2);
    final summary = await AiUsageCostService.getSummary(
      from: DateTime(2020),
      to: DateTime(2100),
    );
    expect(summary.costMicros, 16666);
    expect(summary.breakdowns.single.audioSeconds, 120);
  });

  for (final usage in <Map<String, Object>?>[
    null,
    {'total_tokens': 900},
  ]) {
    test(
      'missing duration stays unpriced without guessing from recording or tokens: $usage',
      () async {
        await AiUsageCostService.setAutoLedgerEnabled(true);
        final result = await service(usage: usage)
            .transcribeWithUsage(wavBytes: wav, apiKey: 'synthetic-key');
        final rows = await db.query('ai_usage_records');
        expect(rows, hasLength(1));
        expect(rows.single['cost_micros'], null);
        expect(rows.single['is_priced'], 0);
        expect(rows.single['audio_seconds'], 0);
        expect(result.usageSummary?.unpricedCalls, 1);
        expect(result.usageSummary?.costMicros, null);
        expect(await db.query('finance_transactions'), isEmpty);
      },
    );
  }

  test('user configured ASR rate drives cost and returned summary', () async {
    await AiUsageCostService.savePricing(
      const AiUsagePricing(
        provider: 'mimo',
        model: 'mimo-v2.5-asr',
        audioMicrosPerHour: 1000000,
      ),
    );
    final result = await service(usage: {'seconds': 36})
        .transcribeWithUsage(wavBytes: wav, apiKey: 'synthetic-key');
    expect(result.usageSummary?.costMicros, 10000);
    expect((await db.query('ai_usage_records')).single['cost_micros'], 10000);
  });

  test('failed HTTP request does not invent usage or a bill', () async {
    await expectLater(
      service(status: 500)
          .transcribeWithUsage(wavBytes: wav, apiKey: 'synthetic-key'),
      throwsException,
    );
    expect(await db.query('ai_usage_records'), isEmpty);
    expect(await db.query('finance_transactions'), isEmpty);
  });

  test('successful billed response with empty transcript retains charge before reporting recognition failure', () async {
    await expectLater(
      service(
        usage: {'seconds': 4},
        text: '',
      ).transcribeWithUsage(wavBytes: wav, apiKey: 'synthetic-key'),
      throwsFormatException,
    );
    expect((await db.query('ai_usage_records')).single['cost_micros'], 556);
  });
}
