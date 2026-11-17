import 'dart:convert';

/// Preset tiers for per-turn AI tool-calling budgets.
enum AiToolBudgetPreset {
  standard('默认'),
  extended('扩展'),
  generous('充裕'),
  unlimited('不限');

  const AiToolBudgetPreset(this.label);

  final String label;
}

/// Per-turn budget limits for AI function calling in [AiToolChatRunner].
///
/// A `null` field means no upper limit is enforced for that dimension.
class AiToolBudget {
  const AiToolBudget({
    required this.maxQueryRounds,
    required this.maxCalls,
    required this.maxTurnChars,
  });

  static const int minQueryRounds = 1;
  static const int maxQueryRoundsSliderMax = 20;
  static const int minCalls = 1;
  static const int maxCallsSliderMax = 50;
  static const int minTurnChars = 4000;
  static const int maxTurnCharsSliderMax = 120000;

  static const AiToolBudget standard = AiToolBudget(
    maxQueryRounds: 4,
    maxCalls: 8,
    maxTurnChars: 24000,
  );

  static const AiToolBudget extended = AiToolBudget(
    maxQueryRounds: 8,
    maxCalls: 16,
    maxTurnChars: 48000,
  );

  static const AiToolBudget generous = AiToolBudget(
    maxQueryRounds: 12,
    maxCalls: 30,
    maxTurnChars: 80000,
  );

  static const AiToolBudget unlimited = AiToolBudget(
    maxQueryRounds: null,
    maxCalls: null,
    maxTurnChars: null,
  );

  final int? maxQueryRounds;
  final int? maxCalls;
  final int? maxTurnChars;

  static const Object _unset = Object();

  static AiToolBudget forPreset(AiToolBudgetPreset preset) => switch (preset) {
    AiToolBudgetPreset.standard => standard,
    AiToolBudgetPreset.extended => extended,
    AiToolBudgetPreset.generous => generous,
    AiToolBudgetPreset.unlimited => unlimited,
  };

  AiToolBudgetPreset? get matchingPreset {
    final norm = normalized();
    for (final preset in AiToolBudgetPreset.values) {
      if (norm == forPreset(preset)) return preset;
    }
    return null;
  }

  AiToolBudget normalized() => AiToolBudget(
    maxQueryRounds: maxQueryRounds == null
        ? null
        : maxQueryRounds! < minQueryRounds
        ? minQueryRounds
        : maxQueryRounds!,
    maxCalls: maxCalls == null
        ? null
        : maxCalls! < minCalls
        ? minCalls
        : maxCalls!,
    maxTurnChars: maxTurnChars == null
        ? null
        : maxTurnChars! < minTurnChars
        ? minTurnChars
        : maxTurnChars!,
  );

  AiToolBudget copyWith({
    Object? maxQueryRounds = _unset,
    Object? maxCalls = _unset,
    Object? maxTurnChars = _unset,
  }) => AiToolBudget(
    maxQueryRounds: identical(maxQueryRounds, _unset)
        ? this.maxQueryRounds
        : maxQueryRounds as int?,
    maxCalls: identical(maxCalls, _unset) ? this.maxCalls : maxCalls as int?,
    maxTurnChars: identical(maxTurnChars, _unset)
        ? this.maxTurnChars
        : maxTurnChars as int?,
  );

  static String formatChars(int? chars) {
    if (chars == null) return '不限';
    if (chars % 1000 == 0) {
      return '${chars ~/ 1000}k';
    }
    return '${(chars / 1000).toStringAsFixed(1)}k';
  }

  String get formattedChars => formatChars(maxTurnChars);

  String get summaryLabel {
    final preset = matchingPreset;
    if (preset == AiToolBudgetPreset.unlimited) {
      return '不限 · 单轮工具调用与数据量不设上限';
    }
    final presetLabel = preset?.label ?? '自定义';
    final roundsText = maxQueryRounds == null ? '不限轮数' : '最多 $maxQueryRounds 轮';
    final callsText = maxCalls == null ? '不限次数' : '$maxCalls 次调用';
    final charsText = maxTurnChars == null ? '不限字符' : '$formattedChars 字符';
    return '$presetLabel · $roundsText · $callsText · $charsText';
  }

  Map<String, dynamic> toJson() => {
    'maxQueryRounds': maxQueryRounds,
    'maxCalls': maxCalls,
    'maxTurnChars': maxTurnChars,
  };

  String toStorageString() => jsonEncode(normalized().toJson());

  static AiToolBudget fromJson(Map<String, dynamic> json) {
    final rounds = json.containsKey('maxQueryRounds')
        ? _parseNullableInt(json['maxQueryRounds'])
        : standard.maxQueryRounds;
    final calls = json.containsKey('maxCalls')
        ? _parseNullableInt(json['maxCalls'])
        : standard.maxCalls;
    final chars = json.containsKey('maxTurnChars')
        ? _parseNullableInt(json['maxTurnChars'])
        : standard.maxTurnChars;
    return AiToolBudget(
      maxQueryRounds: rounds,
      maxCalls: calls,
      maxTurnChars: chars,
    ).normalized();
  }

  static AiToolBudget fromStorage(String? raw) {
    if (raw == null || raw.trim().isEmpty) return standard;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Fall back to default budget when stored payload is malformed.
    }
    return standard;
  }

  static int? _parseNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiToolBudget &&
          runtimeType == other.runtimeType &&
          maxQueryRounds == other.maxQueryRounds &&
          maxCalls == other.maxCalls &&
          maxTurnChars == other.maxTurnChars;

  @override
  int get hashCode => Object.hash(maxQueryRounds, maxCalls, maxTurnChars);
}
