import 'dart:convert';

import 'ai_chat_service.dart';

/// Converts native function calls into the internal action containers consumed
/// by the existing parsers and confirmation cards. The model never emits these
/// textual wrappers; they are an in-process compatibility format only.
abstract final class AiNativeToolCallParser {
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
    final cdtActions = <Map<String, dynamic>>[];
    final financeDrafts = <Map<String, dynamic>>[];
    final financeActions = <Map<String, dynamic>>[];

    for (final call in calls) {
      if (!allowedToolNames.contains(call.name)) continue;
      final arguments = _decodeArguments(call.arguments);
      if (arguments == null) continue;

      if (call.name == 'propose_cdt_actions') {
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

    if (blocks.isEmpty) return assistantText;
    return [
      assistantText.trim(),
      ...blocks,
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
