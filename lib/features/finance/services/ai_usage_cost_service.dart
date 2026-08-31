import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../services/database_helper.dart';
import '../../../services/storage/user_session_storage.dart';
import '../models/finance_models.dart';
import 'finance_repository.dart';

int _readNonNegativeInt(Object? value) {
  final parsed =
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
  return parsed < 0 ? 0 : parsed;
}

/// One model's configured CNY prices.  Prices use micro-yuan so a low-cost
/// request is retained accurately even when its eventual ledger total is
/// still below one fen.
class AiUsagePricing {
  final String provider;
  final String model;
  final int cachedInputMicrosPerMillion;
  final int inputMicrosPerMillion;
  final int outputMicrosPerMillion;
  final int imageMicrosPerImage;
  final int audioMicrosPerHour;

  const AiUsagePricing({
    required this.provider,
    required this.model,
    this.cachedInputMicrosPerMillion = 0,
    this.inputMicrosPerMillion = 0,
    this.outputMicrosPerMillion = 0,
    this.imageMicrosPerImage = 0,
    this.audioMicrosPerHour = 0,
  });

  String get id => '$provider::$model';

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'model': model,
        'cached_input_micros_per_million': cachedInputMicrosPerMillion,
        'input_micros_per_million': inputMicrosPerMillion,
        'output_micros_per_million': outputMicrosPerMillion,
        'image_micros_per_image': imageMicrosPerImage,
        'audio_micros_per_hour': audioMicrosPerHour,
      };

  factory AiUsagePricing.fromJson(Map<String, dynamic> json) => AiUsagePricing(
        provider: json['provider']?.toString() ?? '',
        model: json['model']?.toString() ?? '',
        cachedInputMicrosPerMillion:
            _readNonNegativeInt(json['cached_input_micros_per_million']),
        inputMicrosPerMillion:
            _readNonNegativeInt(json['input_micros_per_million']),
        outputMicrosPerMillion:
            _readNonNegativeInt(json['output_micros_per_million']),
        imageMicrosPerImage:
            _readNonNegativeInt(json['image_micros_per_image']),
        audioMicrosPerHour: _readNonNegativeInt(json['audio_micros_per_hour']),
      );
}

class AiUsageRecord {
  final String uuid;
  final String provider;
  final String model;
  final String operation;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int cachedPromptTokens;
  final int imageTokens;
  final int audioTokens;
  final int videoTokens;
  final int reasoningTokens;
  final int audioSeconds;
  final int imageCount;
  final int? costMicros;
  final bool isPriced;
  final DateTime createdAt;

  const AiUsageRecord({
    required this.uuid,
    required this.provider,
    required this.model,
    required this.operation,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.cachedPromptTokens,
    required this.imageTokens,
    required this.audioTokens,
    required this.videoTokens,
    required this.reasoningTokens,
    required this.audioSeconds,
    required this.imageCount,
    required this.costMicros,
    required this.isPriced,
    required this.createdAt,
  });

  int get uncachedPromptTokens =>
      (promptTokens - cachedPromptTokens).clamp(0, promptTokens).toInt();

  factory AiUsageRecord.fromMap(Map<String, dynamic> map) {
    final promptTokens = _readNonNegativeInt(map['prompt_tokens']);
    final cachedPromptTokens = _readNonNegativeInt(map['cached_prompt_tokens']);
    return AiUsageRecord(
      uuid: map['uuid']?.toString() ?? '',
      provider: map['provider']?.toString() ?? '',
      model: map['model']?.toString() ?? '',
      operation: map['operation']?.toString() ?? '',
      promptTokens: promptTokens,
      completionTokens: _readNonNegativeInt(map['completion_tokens']),
      totalTokens: _readNonNegativeInt(map['total_tokens']),
      cachedPromptTokens:
          cachedPromptTokens > promptTokens ? promptTokens : cachedPromptTokens,
      imageTokens: _readNonNegativeInt(map['image_tokens']),
      audioTokens: _readNonNegativeInt(map['audio_tokens']),
      videoTokens: _readNonNegativeInt(map['video_tokens']),
      reasoningTokens: _readNonNegativeInt(map['reasoning_tokens']),
      audioSeconds: _readNonNegativeInt(map['audio_seconds']),
      imageCount: _readNonNegativeInt(map['image_count']),
      costMicros: (map['cost_micros'] as num?)?.toInt(),
      isPriced: (map['is_priced'] as num?)?.toInt() == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _readNonNegativeInt(map['created_at']),
      ),
    );
  }
}

class AiUsageBreakdown {
  final String provider;
  final String model;
  int calls;
  int totalTokens;
  int cachedPromptTokens;
  int imageTokens;
  int audioTokens;
  int videoTokens;
  int audioSeconds;
  int costMicros;
  int unpricedCalls;

  AiUsageBreakdown({
    required this.provider,
    required this.model,
    this.calls = 0,
    this.totalTokens = 0,
    this.cachedPromptTokens = 0,
    this.imageTokens = 0,
    this.audioTokens = 0,
    this.videoTokens = 0,
    this.audioSeconds = 0,
    this.costMicros = 0,
    this.unpricedCalls = 0,
  });
}

class AiUsageSummary {
  final int calls;
  final int totalTokens;
  final int costMicros;
  final int unpricedCalls;
  final List<AiUsageBreakdown> breakdowns;

  const AiUsageSummary({
    this.calls = 0,
    this.totalTokens = 0,
    this.costMicros = 0,
    this.unpricedCalls = 0,
    this.breakdowns = const [],
  });
}

/// Tracks usage returned by providers and mirrors priced calls into the
/// personal ledger. The raw usage table stays on-device, while the resulting
/// finance transaction uses the existing personal finance sync path.
abstract final class AiUsageCostService {
  static const _settingsPrefix = 'ai_usage_cost_settings';
  static const _aiCategoryUuid = 'finance-system-category-ai-service';
  static const _otherPaymentMethodUuid = 'finance-system-payment-other';
  static const _microsPerYuan = 1000000;
  static const _microsPerFen = 10000;
  static const _tokensPerMillion = 1000000;

  // Domestic MiMo pay-as-you-go prices, stored as micro-yuan per million
  // tokens. Token Plan is deliberately excluded: its quota is not the same
  // billing system as the ordinary MiMo API balance.
  static const List<AiUsagePricing> _builtInPricing = [
    AiUsagePricing(
      provider: 'mimo',
      model: 'mimo-v2.5',
      cachedInputMicrosPerMillion: 20000,
      inputMicrosPerMillion: 1000000,
      outputMicrosPerMillion: 2000000,
    ),
    AiUsagePricing(
      provider: 'mimo',
      model: 'mimo-v2.5-pro',
      cachedInputMicrosPerMillion: 25000,
      inputMicrosPerMillion: 3000000,
      outputMicrosPerMillion: 6000000,
    ),
    AiUsagePricing(
      provider: 'mimo',
      model: 'mimo-v2.5-asr',
      audioMicrosPerHour: 500000,
    ),
  ];

  @visibleForTesting
  static Database? databaseOverride;

  static Future<Database> get _database async =>
      databaseOverride ?? await DatabaseHelper.instance.database;

  static Future<String> _settingsKey() async {
    final username = await UserSessionStorage.getCurrentUsername();
    return username == null || username.isEmpty
        ? _settingsPrefix
        : '${_settingsPrefix}_$username';
  }

  static Future<({bool autoLedger, List<AiUsagePricing> prices})>
      _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _settingsKey());
    if (raw == null || raw.isEmpty) {
      return (autoLedger: true, prices: _withBuiltInPricing(const []));
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final values = (json['prices'] as List? ?? const [])
          .whereType<Map>()
          .map((item) =>
              AiUsagePricing.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.provider.isNotEmpty && item.model.isNotEmpty)
          .toList();
      return (
        autoLedger: json['auto_ledger'] != false,
        prices: _withBuiltInPricing(values),
      );
    } catch (_) {
      return (autoLedger: true, prices: _withBuiltInPricing(const []));
    }
  }

  static List<AiUsagePricing> _withBuiltInPricing(
    List<AiUsagePricing> configured,
  ) {
    final values = [...configured];
    for (final pricing in _builtInPricing) {
      if (!values.any((item) => item.id == pricing.id)) {
        values.add(pricing);
      }
    }
    values.sort((a, b) => a.id.compareTo(b.id));
    return values;
  }

  static bool isBuiltInPricing(AiUsagePricing pricing) =>
      _builtInPricing.any((item) => item.id == pricing.id);

  static Future<void> _saveSettings({
    required bool autoLedger,
    required List<AiUsagePricing> prices,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      await _settingsKey(),
      jsonEncode({
        'auto_ledger': autoLedger,
        'prices': prices.map((item) => item.toJson()).toList(),
      }),
    );
  }

  static Future<bool> isAutoLedgerEnabled() async =>
      (await _loadSettings()).autoLedger;

  static Future<void> setAutoLedgerEnabled(bool enabled) async {
    final settings = await _loadSettings();
    await _saveSettings(autoLedger: enabled, prices: settings.prices);
  }

  static Future<List<AiUsagePricing>> getPricing() async =>
      (await _loadSettings()).prices;

  static Future<void> savePricing(AiUsagePricing pricing) async {
    final settings = await _loadSettings();
    final values = [...settings.prices];
    final index = values.indexWhere((item) => item.id == pricing.id);
    if (index == -1) {
      values.add(pricing);
    } else {
      values[index] = pricing;
    }
    values.sort((a, b) => a.id.compareTo(b.id));
    await _saveSettings(autoLedger: settings.autoLedger, prices: values);
  }

  static Future<void> deletePricing(String id) async {
    final settings = await _loadSettings();
    await _saveSettings(
      autoLedger: settings.autoLedger,
      prices: settings.prices.where((item) => item.id != id).toList(),
    );
  }

  static Future<void> recordUsage({
    required String provider,
    required String model,
    required String operation,
    required int promptTokens,
    required int completionTokens,
    required int totalTokens,
    int cachedPromptTokens = 0,
    int imageTokens = 0,
    int audioTokens = 0,
    int videoTokens = 0,
    int reasoningTokens = 0,
    int audioSeconds = 0,
    int imageCount = 0,
    bool usageAvailable = true,
    DateTime? now,
  }) async {
    if (provider.trim().isEmpty || model.trim().isEmpty) return;
    final normalizedPromptTokens = _readNonNegativeInt(promptTokens);
    final normalizedCompletionTokens = _readNonNegativeInt(completionTokens);
    final suppliedTotalTokens = _readNonNegativeInt(totalTokens);
    final normalizedTotalTokens = suppliedTotalTokens == 0
        ? normalizedPromptTokens + normalizedCompletionTokens
        : suppliedTotalTokens;
    final normalizedCachedPromptTokens = _readNonNegativeInt(
      cachedPromptTokens,
    );
    final normalizedImageTokens = _readNonNegativeInt(imageTokens);
    final normalizedAudioTokens = _readNonNegativeInt(audioTokens);
    final normalizedVideoTokens = _readNonNegativeInt(videoTokens);
    final normalizedReasoningTokens = _readNonNegativeInt(reasoningTokens);
    final normalizedAudioSeconds = _readNonNegativeInt(audioSeconds);
    final normalizedImageCount = _readNonNegativeInt(imageCount);
    final clampedCachedPromptTokens =
        normalizedCachedPromptTokens > normalizedPromptTokens
            ? normalizedPromptTokens
            : normalizedCachedPromptTokens;
    final settings = await _loadSettings();
    final pricing = settings.prices
        .where((item) => item.provider == provider && item.model == model)
        .firstOrNull;
    final costMicros = usageAvailable
        ? _calculateCostMicros(
            pricing,
            provider: provider,
            model: model,
            promptTokens: normalizedPromptTokens,
            completionTokens: normalizedCompletionTokens,
            cachedPromptTokens: clampedCachedPromptTokens,
            imageTokens: normalizedImageTokens,
            audioSeconds: normalizedAudioSeconds,
            imageCount: normalizedImageCount,
          )
        : null;
    final timestamp = now ?? DateTime.now();
    final ledgerKey =
        costMicros == null ? null : '${dateKey(timestamp)}|$provider|$model';
    final db = await _database;
    await DatabaseHelper.ensureAiUsageSchema(db);
    await db.insert('ai_usage_records', {
      'uuid': const Uuid().v4(),
      'provider': provider,
      'model': model,
      'operation': operation,
      'prompt_tokens': normalizedPromptTokens,
      'completion_tokens': normalizedCompletionTokens,
      'total_tokens': normalizedTotalTokens,
      'cached_prompt_tokens': clampedCachedPromptTokens,
      'image_tokens': normalizedImageTokens,
      'audio_tokens': normalizedAudioTokens,
      'video_tokens': normalizedVideoTokens,
      'reasoning_tokens': normalizedReasoningTokens,
      'audio_seconds': normalizedAudioSeconds,
      'image_count': normalizedImageCount,
      'cost_micros': costMicros,
      'is_priced': costMicros == null ? 0 : 1,
      'ledger_key': ledgerKey,
      'created_at': timestamp.millisecondsSinceEpoch,
    });
    if (settings.autoLedger && ledgerKey != null) {
      await _syncLedgerAggregate(
        db: db,
        ledgerKey: ledgerKey,
        date: timestamp,
        provider: provider,
        model: model,
      );
    }
  }

  static int? _calculateCostMicros(
    AiUsagePricing? pricing, {
    required String provider,
    required String model,
    required int promptTokens,
    required int completionTokens,
    required int cachedPromptTokens,
    required int imageTokens,
    required int audioSeconds,
    required int imageCount,
  }) {
    if (pricing == null) return null;
    final normalizedPromptTokens = _readNonNegativeInt(promptTokens);
    final normalizedCompletionTokens = _readNonNegativeInt(completionTokens);
    final normalizedCachedPromptTokens = _readNonNegativeInt(
      cachedPromptTokens,
    );
    final cachedTokens = normalizedCachedPromptTokens > normalizedPromptTokens
        ? normalizedPromptTokens
        : normalizedCachedPromptTokens;
    final uncachedTokens = normalizedPromptTokens - cachedTokens;
    final isMimo = provider == 'mimo' || provider == 'mimo_token_plan';

    // MiMo ASR is billed by audio duration, not by the token fields in the
    // response. A missing duration must remain unpriced instead of guessing.
    if (model == 'mimo-v2.5-asr' || audioSeconds > 0) {
      if (audioSeconds <= 0 || pricing.audioMicrosPerHour <= 0) return null;
      return _roundProduct(audioSeconds, pricing.audioMicrosPerHour, 3600);
    }

    if (uncachedTokens > 0 && pricing.inputMicrosPerMillion <= 0) {
      return null;
    }
    if (normalizedCompletionTokens > 0 && pricing.outputMicrosPerMillion <= 0) {
      return null;
    }
    final cachedInputRate = pricing.cachedInputMicrosPerMillion > 0
        ? pricing.cachedInputMicrosPerMillion
        : pricing.inputMicrosPerMillion;
    if (cachedTokens > 0 && cachedInputRate <= 0) {
      return null;
    }
    if (isMimo && imageTokens > 0 && normalizedPromptTokens <= 0) {
      return null;
    }
    if (!isMimo && imageCount > 0 && pricing.imageMicrosPerImage <= 0) {
      return null;
    }

    // MiMo reports image/audio/video tokens as parts of prompt_tokens. Do not
    // add a per-image fee on top of that total. For other providers, retain
    // the existing optional fixed image fee behavior.
    final tokenNumerator = uncachedTokens * pricing.inputMicrosPerMillion +
        cachedTokens * cachedInputRate +
        normalizedCompletionTokens * pricing.outputMicrosPerMillion;
    final tokenCostMicros =
        (tokenNumerator + (_tokensPerMillion ~/ 2)) ~/ _tokensPerMillion;
    return tokenCostMicros +
        (isMimo ? 0 : imageCount * pricing.imageMicrosPerImage);
  }

  static int _roundProduct(int value, int microsPerUnit, int divisor) {
    final numerator = value * microsPerUnit;
    return (numerator + (divisor ~/ 2)) ~/ divisor;
  }

  static Future<void> _syncLedgerAggregate({
    required Database db,
    required String ledgerKey,
    required DateTime date,
    required String provider,
    required String model,
  }) async {
    final totalMicros = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COALESCE(SUM(cost_micros), 0) FROM ai_usage_records '
          'WHERE ledger_key = ? AND is_priced = 1',
          [ledgerKey],
        )) ??
        0;
    final amountMinor = (totalMicros + (_microsPerFen ~/ 2)) ~/ _microsPerFen;
    if (amountMinor <= 0) return;

    final links = await db.query(
      'ai_usage_ledger_links',
      where: 'ledger_key = ?',
      whereArgs: [ledgerKey],
      limit: 1,
    );
    final existing = links.isEmpty
        ? null
        : await FinanceRepository.getTransaction(
            links.single['finance_transaction_uuid']?.toString() ?? '',
          );
    final transaction = existing == null || existing.isDeleted
        ? FinanceTransaction(
            type: FinanceTransactionType.expense,
            amountMinor: amountMinor,
            categoryUuid: _aiCategoryUuid,
            paymentMethodUuid: _otherPaymentMethodUuid,
            transactionDate: dateKey(date),
            merchant: '$provider · $model',
            note: 'AI 调用费用自动汇总（${dateKey(date)}）',
            source: FinanceEntrySource.ai,
          )
        : existing;
    if (existing != null && !existing.isDeleted) {
      transaction.amountMinor = amountMinor;
      transaction.markAsChanged();
    }
    await FinanceRepository.saveTransaction(transaction);
    await db.insert(
      'ai_usage_ledger_links',
      {
        'ledger_key': ledgerKey,
        'finance_transaction_uuid': transaction.uuid,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<AiUsageRecord>> getRecords({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final db = await _database;
    await DatabaseHelper.ensureAiUsageSchema(db);
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('created_at < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final rows = await db.query(
      'ai_usage_records',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(AiUsageRecord.fromMap).toList();
  }

  static Future<AiUsageSummary> getSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    final records = await getRecords(from: from, to: to);
    final breakdowns = <String, AiUsageBreakdown>{};
    var totalTokens = 0;
    var totalCostMicros = 0;
    var unpricedCalls = 0;
    for (final record in records) {
      totalTokens += record.totalTokens;
      totalCostMicros += record.costMicros ?? 0;
      if (!record.isPriced) unpricedCalls++;
      final key = '${record.provider}::${record.model}';
      final item = breakdowns.putIfAbsent(
        key,
        () => AiUsageBreakdown(provider: record.provider, model: record.model),
      );
      item.calls++;
      item.totalTokens += record.totalTokens;
      item.cachedPromptTokens += record.cachedPromptTokens;
      item.imageTokens += record.imageTokens;
      item.audioTokens += record.audioTokens;
      item.videoTokens += record.videoTokens;
      item.audioSeconds += record.audioSeconds;
      item.costMicros += record.costMicros ?? 0;
      if (!record.isPriced) item.unpricedCalls++;
    }
    final values = breakdowns.values.toList()
      ..sort((a, b) => b.costMicros.compareTo(a.costMicros));
    return AiUsageSummary(
      calls: records.length,
      totalTokens: totalTokens,
      costMicros: totalCostMicros,
      unpricedCalls: unpricedCalls,
      breakdowns: values,
    );
  }

  static String formatMicros(int micros) {
    return '¥${(micros / _microsPerYuan).toStringAsFixed(4)}';
  }

  static int yuanToMicros(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed < 0) return 0;
    return (parsed * _microsPerYuan).round();
  }

  static String microsToYuan(int micros) =>
      (micros / _microsPerYuan).toStringAsFixed(6);
}
