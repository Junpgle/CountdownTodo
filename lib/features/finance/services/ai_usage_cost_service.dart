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

int? _readNullableNonNegativeInt(Object? value) {
  if (value == null) return null;
  return _readNonNegativeInt(value);
}

/// One model's configured CNY prices.  Prices use micro-yuan so a low-cost
/// request is retained accurately even when its eventual ledger total is
/// still below one fen.
class AiUsagePriceTier {
  final int minPromptTokens;
  final int? maxPromptTokens;
  final int minCompletionTokens;
  final int? maxCompletionTokens;
  final int cachedInputMicrosPerMillion;
  final int inputMicrosPerMillion;
  final int outputMicrosPerMillion;

  const AiUsagePriceTier({
    this.minPromptTokens = 0,
    this.maxPromptTokens,
    this.minCompletionTokens = 0,
    this.maxCompletionTokens,
    this.cachedInputMicrosPerMillion = 0,
    this.inputMicrosPerMillion = 0,
    this.outputMicrosPerMillion = 0,
  });

  bool matches({
    required int promptTokens,
    required int completionTokens,
  }) {
    return promptTokens >= minPromptTokens &&
        (maxPromptTokens == null || promptTokens < maxPromptTokens!) &&
        completionTokens >= minCompletionTokens &&
        (maxCompletionTokens == null ||
            completionTokens < maxCompletionTokens!);
  }

  Map<String, dynamic> toJson() => {
        'min_prompt_tokens': minPromptTokens,
        'max_prompt_tokens': maxPromptTokens,
        'min_completion_tokens': minCompletionTokens,
        'max_completion_tokens': maxCompletionTokens,
        'cached_input_micros_per_million': cachedInputMicrosPerMillion,
        'input_micros_per_million': inputMicrosPerMillion,
        'output_micros_per_million': outputMicrosPerMillion,
      };

  factory AiUsagePriceTier.fromJson(Map<String, dynamic> json) =>
      AiUsagePriceTier(
        minPromptTokens: _readNonNegativeInt(json['min_prompt_tokens']),
        maxPromptTokens: _readNullableNonNegativeInt(
          json['max_prompt_tokens'],
        ),
        minCompletionTokens: _readNonNegativeInt(json['min_completion_tokens']),
        maxCompletionTokens: _readNullableNonNegativeInt(
          json['max_completion_tokens'],
        ),
        cachedInputMicrosPerMillion:
            _readNonNegativeInt(json['cached_input_micros_per_million']),
        inputMicrosPerMillion:
            _readNonNegativeInt(json['input_micros_per_million']),
        outputMicrosPerMillion:
            _readNonNegativeInt(json['output_micros_per_million']),
      );
}

class AiUsagePricing {
  final String provider;
  final String model;
  final int cachedInputMicrosPerMillion;
  final int inputMicrosPerMillion;
  final int outputMicrosPerMillion;
  final int imageMicrosPerImage;
  final int audioMicrosPerHour;
  final int peakCachedInputMicrosPerMillion;
  final int peakInputMicrosPerMillion;
  final int peakOutputMicrosPerMillion;
  final bool imageTokensIncluded;
  final bool isFree;
  final List<AiUsagePriceTier> tiers;

  const AiUsagePricing({
    required this.provider,
    required this.model,
    this.cachedInputMicrosPerMillion = 0,
    this.inputMicrosPerMillion = 0,
    this.outputMicrosPerMillion = 0,
    this.imageMicrosPerImage = 0,
    this.audioMicrosPerHour = 0,
    this.peakCachedInputMicrosPerMillion = 0,
    this.peakInputMicrosPerMillion = 0,
    this.peakOutputMicrosPerMillion = 0,
    this.imageTokensIncluded = false,
    this.isFree = false,
    this.tiers = const [],
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
        'peak_cached_input_micros_per_million': peakCachedInputMicrosPerMillion,
        'peak_input_micros_per_million': peakInputMicrosPerMillion,
        'peak_output_micros_per_million': peakOutputMicrosPerMillion,
        'image_tokens_included': imageTokensIncluded,
        'is_free': isFree,
        'tiers': tiers.map((item) => item.toJson()).toList(),
      };

  factory AiUsagePricing.fromJson(Map<String, dynamic> json) {
    final rawTiers = json['tiers'];
    final tiers = rawTiers is List
        ? rawTiers
            .whereType<Map>()
            .map((item) => AiUsagePriceTier.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList()
        : const <AiUsagePriceTier>[];
    return AiUsagePricing(
      provider: json['provider']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      cachedInputMicrosPerMillion:
          _readNonNegativeInt(json['cached_input_micros_per_million']),
      inputMicrosPerMillion:
          _readNonNegativeInt(json['input_micros_per_million']),
      outputMicrosPerMillion:
          _readNonNegativeInt(json['output_micros_per_million']),
      imageMicrosPerImage: _readNonNegativeInt(json['image_micros_per_image']),
      audioMicrosPerHour: _readNonNegativeInt(json['audio_micros_per_hour']),
      peakCachedInputMicrosPerMillion: _readNonNegativeInt(
        json['peak_cached_input_micros_per_million'],
      ),
      peakInputMicrosPerMillion:
          _readNonNegativeInt(json['peak_input_micros_per_million']),
      peakOutputMicrosPerMillion:
          _readNonNegativeInt(json['peak_output_micros_per_million']),
      imageTokensIncluded: json['image_tokens_included'] == true,
      isFree: json['is_free'] == true,
      tiers: tiers,
    );
  }
}

class _AiUsageRates {
  final int cachedInputMicrosPerMillion;
  final int inputMicrosPerMillion;
  final int outputMicrosPerMillion;
  final int imageMicrosPerImage;
  final int audioMicrosPerHour;

  const _AiUsageRates({
    required this.cachedInputMicrosPerMillion,
    required this.inputMicrosPerMillion,
    required this.outputMicrosPerMillion,
    required this.imageMicrosPerImage,
    required this.audioMicrosPerHour,
  });
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

  // Prices are stored as micro-yuan per million tokens. The Zhipu and
  // DeepSeek entries below were checked against their official domestic
  // pricing pages on 2026-08-31. NIM is deliberately not included: NVIDIA's
  // hosted models do not have one universal public per-token price.
  // Sources: https://bigmodel.cn/pricing and
  // https://api-docs.deepseek.com/zh-cn/quick_start/pricing/
  //
  // Domestic MiMo pay-as-you-go prices are included, while Token Plan is
  // deliberately excluded: its quota is not the same billing system as the
  // ordinary MiMo API balance.
  static const List<AiUsagePricing> _builtInPricing = [
    AiUsagePricing(
      provider: 'mimo',
      model: 'mimo-v2.5',
      cachedInputMicrosPerMillion: 20000,
      inputMicrosPerMillion: 1000000,
      outputMicrosPerMillion: 2000000,
      imageTokensIncluded: true,
    ),
    AiUsagePricing(
      provider: 'mimo',
      model: 'mimo-v2.5-pro',
      cachedInputMicrosPerMillion: 25000,
      inputMicrosPerMillion: 3000000,
      outputMicrosPerMillion: 6000000,
      imageTokensIncluded: true,
    ),
    AiUsagePricing(
      provider: 'mimo',
      model: 'mimo-v2.5-asr',
      audioMicrosPerHour: 500000,
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-5',
      cachedInputMicrosPerMillion: 1000000,
      inputMicrosPerMillion: 4000000,
      outputMicrosPerMillion: 18000000,
      tiers: [
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          cachedInputMicrosPerMillion: 1000000,
          inputMicrosPerMillion: 4000000,
          outputMicrosPerMillion: 18000000,
        ),
        AiUsagePriceTier(
          minPromptTokens: 32000,
          cachedInputMicrosPerMillion: 1500000,
          inputMicrosPerMillion: 6000000,
          outputMicrosPerMillion: 22000000,
        ),
      ],
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-5-turbo',
      cachedInputMicrosPerMillion: 1200000,
      inputMicrosPerMillion: 5000000,
      outputMicrosPerMillion: 22000000,
      tiers: [
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          cachedInputMicrosPerMillion: 1200000,
          inputMicrosPerMillion: 5000000,
          outputMicrosPerMillion: 22000000,
        ),
        AiUsagePriceTier(
          minPromptTokens: 32000,
          cachedInputMicrosPerMillion: 1800000,
          inputMicrosPerMillion: 7000000,
          outputMicrosPerMillion: 26000000,
        ),
      ],
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4.7',
      cachedInputMicrosPerMillion: 400000,
      inputMicrosPerMillion: 2000000,
      outputMicrosPerMillion: 8000000,
      tiers: [
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          maxCompletionTokens: 200000,
          cachedInputMicrosPerMillion: 400000,
          inputMicrosPerMillion: 2000000,
          outputMicrosPerMillion: 8000000,
        ),
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          minCompletionTokens: 200000,
          cachedInputMicrosPerMillion: 600000,
          inputMicrosPerMillion: 3000000,
          outputMicrosPerMillion: 14000000,
        ),
        AiUsagePriceTier(
          minPromptTokens: 32000,
          cachedInputMicrosPerMillion: 800000,
          inputMicrosPerMillion: 4000000,
          outputMicrosPerMillion: 16000000,
        ),
      ],
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4.7-flashx',
      cachedInputMicrosPerMillion: 100000,
      inputMicrosPerMillion: 500000,
      outputMicrosPerMillion: 3000000,
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4.5-air',
      cachedInputMicrosPerMillion: 160000,
      inputMicrosPerMillion: 800000,
      outputMicrosPerMillion: 2000000,
      tiers: [
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          maxCompletionTokens: 200000,
          cachedInputMicrosPerMillion: 160000,
          inputMicrosPerMillion: 800000,
          outputMicrosPerMillion: 2000000,
        ),
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          minCompletionTokens: 200000,
          cachedInputMicrosPerMillion: 160000,
          inputMicrosPerMillion: 800000,
          outputMicrosPerMillion: 6000000,
        ),
        AiUsagePriceTier(
          minPromptTokens: 32000,
          cachedInputMicrosPerMillion: 240000,
          inputMicrosPerMillion: 1200000,
          outputMicrosPerMillion: 8000000,
        ),
      ],
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4.6v',
      cachedInputMicrosPerMillion: 200000,
      inputMicrosPerMillion: 1000000,
      outputMicrosPerMillion: 3000000,
      imageTokensIncluded: true,
      tiers: [
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          cachedInputMicrosPerMillion: 200000,
          inputMicrosPerMillion: 1000000,
          outputMicrosPerMillion: 3000000,
        ),
        AiUsagePriceTier(
          minPromptTokens: 32000,
          cachedInputMicrosPerMillion: 400000,
          inputMicrosPerMillion: 2000000,
          outputMicrosPerMillion: 6000000,
        ),
      ],
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4.7-flash',
      isFree: true,
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4-flash-250414',
      isFree: true,
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4.5-flash',
      isFree: true,
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4.6v-flash',
      isFree: true,
      imageTokensIncluded: true,
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4.1v-thinking-flash',
      isFree: true,
      imageTokensIncluded: true,
    ),
    AiUsagePricing(
      provider: 'zhipu',
      model: 'glm-4v-flash',
      isFree: true,
      imageTokensIncluded: true,
    ),
    // The official model guide currently describes AutoGLM-Phone as
    // temporarily free. Keep the entry free until the provider publishes a
    // paid input/output split that can be represented here.
    AiUsagePricing(
      provider: 'zhipu',
      model: 'autoglm-phone',
      isFree: true,
      imageTokensIncluded: true,
    ),
    AiUsagePricing(
      provider: 'deepseek',
      model: 'deepseek-v4-flash',
      cachedInputMicrosPerMillion: 50000,
      inputMicrosPerMillion: 1500000,
      outputMicrosPerMillion: 4500000,
      peakCachedInputMicrosPerMillion: 100000,
      peakInputMicrosPerMillion: 3000000,
      peakOutputMicrosPerMillion: 9000000,
    ),
    AiUsagePricing(
      provider: 'deepseek',
      model: 'deepseek-v4-pro',
      cachedInputMicrosPerMillion: 150000,
      inputMicrosPerMillion: 4500000,
      outputMicrosPerMillion: 13500000,
      peakCachedInputMicrosPerMillion: 300000,
      peakInputMicrosPerMillion: 9000000,
      peakOutputMicrosPerMillion: 27000000,
    ),
    AiUsagePricing(
      provider: 'deepseek',
      model: 'deepseek-v4-flash-vision-exp',
      cachedInputMicrosPerMillion: 50000,
      inputMicrosPerMillion: 1500000,
      outputMicrosPerMillion: 4500000,
      peakCachedInputMicrosPerMillion: 100000,
      peakInputMicrosPerMillion: 3000000,
      peakOutputMicrosPerMillion: 9000000,
      imageTokensIncluded: true,
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

  static Future<AiUsageRecord?> recordUsage({
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
    if (provider.trim().isEmpty || model.trim().isEmpty) return null;
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
    final timestamp = now ?? DateTime.now();
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
            at: timestamp,
          )
        : null;
    final ledgerKey =
        costMicros == null ? null : '${dateKey(timestamp)}|$provider|$model';
    final uuid = const Uuid().v4();
    final record = AiUsageRecord(
      uuid: uuid,
      provider: provider,
      model: model,
      operation: operation,
      promptTokens: normalizedPromptTokens,
      completionTokens: normalizedCompletionTokens,
      totalTokens: normalizedTotalTokens,
      cachedPromptTokens: clampedCachedPromptTokens,
      imageTokens: normalizedImageTokens,
      audioTokens: normalizedAudioTokens,
      videoTokens: normalizedVideoTokens,
      reasoningTokens: normalizedReasoningTokens,
      audioSeconds: normalizedAudioSeconds,
      imageCount: normalizedImageCount,
      costMicros: costMicros,
      isPriced: costMicros != null,
      createdAt: timestamp,
    );
    final db = await _database;
    await DatabaseHelper.ensureAiUsageSchema(db);
    await db.insert('ai_usage_records', {
      'uuid': uuid,
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
    return record;
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
    required DateTime at,
  }) {
    if (pricing == null) return null;
    if (pricing.isFree) return 0;
    final normalizedPromptTokens = _readNonNegativeInt(promptTokens);
    final normalizedCompletionTokens = _readNonNegativeInt(completionTokens);
    final normalizedCachedPromptTokens = _readNonNegativeInt(
      cachedPromptTokens,
    );
    final cachedTokens = normalizedCachedPromptTokens > normalizedPromptTokens
        ? normalizedPromptTokens
        : normalizedCachedPromptTokens;
    final uncachedTokens = normalizedPromptTokens - cachedTokens;
    final normalizedProvider = provider.toLowerCase();
    final isMimo =
        normalizedProvider == 'mimo' || normalizedProvider == 'mimo_token_plan';
    final rates = _ratesFor(
      pricing,
      promptTokens: normalizedPromptTokens,
      completionTokens: normalizedCompletionTokens,
      at: at,
    );
    if (rates == null) return null;

    // MiMo ASR is billed by audio duration, not by the token fields in the
    // response. A missing duration must remain unpriced instead of guessing.
    if (model == 'mimo-v2.5-asr' || audioSeconds > 0) {
      if (audioSeconds <= 0 || rates.audioMicrosPerHour <= 0) return null;
      return _roundProduct(audioSeconds, rates.audioMicrosPerHour, 3600);
    }

    if (uncachedTokens > 0 && rates.inputMicrosPerMillion <= 0) {
      return null;
    }
    if (normalizedCompletionTokens > 0 && rates.outputMicrosPerMillion <= 0) {
      return null;
    }
    final cachedInputRate = rates.cachedInputMicrosPerMillion > 0
        ? rates.cachedInputMicrosPerMillion
        : rates.inputMicrosPerMillion;
    if (cachedTokens > 0 && cachedInputRate <= 0) {
      return null;
    }
    final imageTokensIncluded = pricing.imageTokensIncluded || isMimo;
    if (imageTokensIncluded && imageTokens > 0 && normalizedPromptTokens <= 0) {
      return null;
    }
    if (!imageTokensIncluded &&
        !isMimo &&
        imageCount > 0 &&
        rates.imageMicrosPerImage <= 0) {
      return null;
    }

    // MiMo, Zhipu vision, and DeepSeek vision report media as parts of the
    // prompt token total. Do not add a per-image fee on top of those tokens.
    // For other providers, retain the existing optional fixed image fee.
    final tokenNumerator = uncachedTokens * rates.inputMicrosPerMillion +
        cachedTokens * cachedInputRate +
        normalizedCompletionTokens * rates.outputMicrosPerMillion;
    final tokenCostMicros =
        (tokenNumerator + (_tokensPerMillion ~/ 2)) ~/ _tokensPerMillion;
    return tokenCostMicros +
        (imageTokensIncluded || isMimo
            ? 0
            : imageCount * rates.imageMicrosPerImage);
  }

  static _AiUsageRates? _ratesFor(
    AiUsagePricing pricing, {
    required int promptTokens,
    required int completionTokens,
    required DateTime at,
  }) {
    AiUsagePriceTier? tier;
    if (pricing.tiers.isNotEmpty) {
      for (final candidate in pricing.tiers) {
        if (candidate.matches(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
        )) {
          tier = candidate;
          break;
        }
      }
      if (tier == null) return null;
    }

    var cachedInputMicrosPerMillion = tier?.cachedInputMicrosPerMillion ??
        pricing.cachedInputMicrosPerMillion;
    var inputMicrosPerMillion =
        tier?.inputMicrosPerMillion ?? pricing.inputMicrosPerMillion;
    var outputMicrosPerMillion =
        tier?.outputMicrosPerMillion ?? pricing.outputMicrosPerMillion;
    if (_isDeepSeekPeakPeriod(pricing.provider, at)) {
      if (pricing.peakCachedInputMicrosPerMillion > 0) {
        cachedInputMicrosPerMillion = pricing.peakCachedInputMicrosPerMillion;
      }
      if (pricing.peakInputMicrosPerMillion > 0) {
        inputMicrosPerMillion = pricing.peakInputMicrosPerMillion;
      }
      if (pricing.peakOutputMicrosPerMillion > 0) {
        outputMicrosPerMillion = pricing.peakOutputMicrosPerMillion;
      }
    }
    return _AiUsageRates(
      cachedInputMicrosPerMillion: cachedInputMicrosPerMillion,
      inputMicrosPerMillion: inputMicrosPerMillion,
      outputMicrosPerMillion: outputMicrosPerMillion,
      imageMicrosPerImage: pricing.imageMicrosPerImage,
      audioMicrosPerHour: pricing.audioMicrosPerHour,
    );
  }

  static bool _isDeepSeekPeakPeriod(String provider, DateTime at) {
    if (provider.toLowerCase() != 'deepseek') return false;
    final beijing = at.toUtc().add(const Duration(hours: 8));
    if (beijing.weekday > DateTime.friday) return false;
    final minute = beijing.hour * 60 + beijing.minute;
    return (minute >= 9 * 60 && minute < 12 * 60) ||
        (minute >= 14 * 60 && minute < 18 * 60);
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
