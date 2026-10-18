import 'dart:convert';

import 'ai_action_parser.dart';
import 'ai_chat_service.dart';
import 'ai_settings_navigation_service.dart';
import 'ai_tool_result_context.dart';

/// Converts native function calls into the internal action containers consumed
/// by the existing parsers and confirmation cards. Text protocol blocks remain
/// available as a compatibility path when the matching native tool was not
/// called; both paths still produce drafts that require user confirmation.
abstract final class AiNativeToolCallParser {
  static final RegExp _actionBlockPattern = RegExp(
    r'\[ACTION_START\][\s\S]*?\[ACTION_END\]',
    dotAll: true,
  );
  static final RegExp _financeDraftBlockPattern = RegExp(
    r'\[FINANCE_START\][\s\S]*?\[FINANCE_END\]',
    dotAll: true,
  );
  static final RegExp _financeActionBlockPattern = RegExp(
    r'\[FINANCE_ACTION_START\][\s\S]*?\[FINANCE_ACTION_END\]',
    dotAll: true,
  );
  static final RegExp _settingsBlockPattern = RegExp(
    r'\[SETTINGS_START\][\s\S]*?\[SETTINGS_END\]',
    dotAll: true,
  );
  static final RegExp _unfinishedFinanceDraftBlockPattern = RegExp(
    r'\[FINANCE_START\][\s\S]*?(?:\[FINANCE_END\]|$)',
  );
  static final RegExp _unfinishedFinanceActionBlockPattern = RegExp(
    r'\[FINANCE_ACTION_START\][\s\S]*?(?:\[FINANCE_ACTION_END\]|$)',
  );

  static String formatRawReply(
    String assistantText,
    List<AiChatFunctionCall> calls,
  ) {
    if (calls.isEmpty) return assistantText;
    const encoder = JsonEncoder.withIndent('  ');
    final rawCalls = encoder.convert([
      for (final call in calls)
        {
          'id': call.id,
          'type': 'function',
          'function': {'name': call.name, 'arguments': call.arguments},
        },
    ]);
    return [
      assistantText.trim(),
      '[NATIVE_TOOL_CALLS]\n$rawCalls',
    ].where((part) => part.isNotEmpty).join('\n\n');
  }

  static String appendToAssistantText(
    String assistantText,
    List<AiChatFunctionCall> calls, {
    required Set<String> allowedToolNames,
    required Set<String> allowedCdtActionNames,
    required Set<String> allowedFinanceActionNames,
  }) {
    assistantText = AiToolResultContext.withoutHistory(assistantText);
    final suggestions = AiActionParser.extractSuggestions(assistantText);
    final fallbackTextBlocks = <String>[];

    void retainFallbackTextBlock(
      RegExp pattern, {
      required bool nativeToolWasCalled,
    }) {
      if (nativeToolWasCalled) return;
      fallbackTextBlocks.addAll(
        pattern.allMatches(assistantText).map((match) => match.group(0)!),
      );
      assistantText = assistantText.replaceAll(pattern, '');
    }

    retainFallbackTextBlock(
      _actionBlockPattern,
      nativeToolWasCalled: calls.any(
        (call) => call.name == 'propose_cdt_actions',
      ),
    );
    retainFallbackTextBlock(
      _financeDraftBlockPattern,
      nativeToolWasCalled: calls.any(
        (call) => call.name == 'propose_finance_drafts',
      ),
    );
    retainFallbackTextBlock(
      _financeActionBlockPattern,
      nativeToolWasCalled: calls.any(
        (call) => call.name == 'propose_finance_actions',
      ),
    );
    retainFallbackTextBlock(
      _settingsBlockPattern,
      nativeToolWasCalled: calls.any(
        (call) => call.name == AiSettingsNavigationService.toolName,
      ),
    );
    assistantText = AiActionParser.cleanActionContent(assistantText)
        .replaceAll(_unfinishedFinanceDraftBlockPattern, '')
        .replaceAll(_unfinishedFinanceActionBlockPattern, '')
        .trim();
    final settingsTargets = <String>[];
    final cdtActions = <Map<String, dynamic>>[];
    final financeDrafts = <Map<String, dynamic>>[];
    final financeActions = <Map<String, dynamic>>[];

    for (final call in calls) {
      if (!allowedToolNames.contains(call.name)) continue;
      final arguments = _decodeArguments(call.arguments);
      if (arguments == null) continue;

      if (call.name == AiSettingsNavigationService.toolName) {
        settingsTargets.addAll(
          AiSettingsNavigationService.validateTargets(arguments['targets']),
        );
      } else if (call.name == 'propose_cdt_actions') {
        final rawActions = arguments['actions'];
        if (rawActions is List) {
          cdtActions.addAll(_filterActions(rawActions, allowedCdtActionNames));
        }
      } else if (call.name == 'propose_finance_drafts') {
        final rawDrafts = arguments['drafts'];
        if (rawDrafts is List) {
          financeDrafts.addAll(
            rawDrafts.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          );
        }
      } else if (call.name == 'propose_finance_actions') {
        final rawActions = arguments['actions'];
        if (rawActions is List) {
          financeActions.addAll(
            _filterActions(rawActions, allowedFinanceActionNames),
          );
        }
      }
    }

    final blocks = <String>[];
    if (settingsTargets.isNotEmpty) {
      blocks.add(
        '[SETTINGS_START]${jsonEncode({'targets': AiSettingsNavigationService.validateTargets(settingsTargets)})}[SETTINGS_END]',
      );
    }
    if (cdtActions.isNotEmpty) {
      blocks.add(
        '[ACTION_START]\n'
        '${jsonEncode({'protocol': 'cdt.actions', 'version': 2, 'actions': cdtActions})}\n'
        '[ACTION_END]',
      );
    }
    if (financeDrafts.isNotEmpty) {
      blocks.add(
        '[FINANCE_START]\n${jsonEncode(financeDrafts)}\n[FINANCE_END]',
      );
    }
    if (financeActions.isNotEmpty) {
      blocks.add(
        '[FINANCE_ACTION_START]\n'
        '${jsonEncode(financeActions)}\n'
        '[FINANCE_ACTION_END]',
      );
    }

    final combinedBlocks = <String>[
      ...fallbackTextBlocks,
      ...blocks,
      if (suggestions.isNotEmpty)
        '[SUGGEST_START]${jsonEncode(suggestions)}[SUGGEST_END]',
    ];
    if (combinedBlocks.isEmpty) return assistantText;
    return [
      assistantText.trim(),
      ...combinedBlocks,
    ].where((part) => part.isNotEmpty).join('\n\n');
  }

  static List<Map<String, dynamic>> _filterActions(
    List<dynamic> rawActions,
    Set<String> allowedActions,
  ) => rawActions
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .where((item) => allowedActions.contains(item['action']?.toString()))
      .toList(growable: false);

  static Map<String, dynamic>? _decodeArguments(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }
}
