import 'dart:convert';
import 'dart:math' as math;

/// Model-facing copies only. The original result remains available in the UI
/// and persisted chat; aggregate totals are never recomputed from a short page.
abstract final class AiToolResultContext {
  static const maxResultChars = 8000;
  static const maxTurnChars = 24000;
  static const maxHistoryChars = 2000;
  static const historyMessages = 3;

  static Map<String, dynamic> forModel(
    Map<String, dynamic> result, {
    int maxChars = maxResultChars,
    int? maxItems,
    int maxStringChars = 2000,
  }) {
    assert(maxChars >= 400);
    var shortened = false;
    Object? copy(Object? value, [int depth = 0]) {
      if (value is String && value.length > maxStringChars) {
        shortened = true;
        return '${value.substring(0, maxStringChars)}…';
      }
      if (value is Map) {
        if (depth > 8) {
          shortened = true;
          return '[嵌套内容省略]';
        }
        return {
          for (final entry in value.entries)
            if (entry.value != null)
              entry.key.toString(): copy(entry.value, depth + 1),
        };
      }
      if (value is List) {
        return [for (final item in value) copy(item, depth + 1)];
      }
      return value;
    }

    final output = copy(result) as Map<String, dynamic>;
    final originalItems = result['items'];
    final items = output['items'];
    final omittedPaths = <String>[];
    if (items is List && maxItems != null && items.length > maxItems) {
      items.removeRange(maxItems, items.length);
    }
    // Reserve space for the explicit scope notice and paging correction below.
    final payloadLimit = maxChars - 350;
    while (jsonEncode(output).length > payloadLimit &&
        items is List &&
        items.length > 1) {
      items.removeLast();
    }
    if (jsonEncode(output).length > payloadLimit && items is List) {
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item is! Map) continue;
        const identityKeys = {
          'id',
          'uuid',
          'todoId',
          'todo_id',
          'todoUuid',
          'transaction_id',
          'habit_id',
        };
        final removableKeys =
            item.keys
                .where((key) => !identityKeys.contains(key.toString()))
                .toList()
              ..sort(
                (left, right) =>
                    jsonEncode(item[right]).length
                        .compareTo(jsonEncode(item[left]).length),
              );
        for (final key in removableKeys) {
          if (jsonEncode(output).length <= payloadLimit) break;
          item.remove(key);
          omittedPaths.add('items[$index].$key');
          shortened = true;
        }
        if (jsonEncode(output).length <= payloadLimit) break;
      }
    }
    if (jsonEncode(output).length > payloadLimit) {
      // Large category breakdowns or detail objects can exceed a page budget.
      // Retain scalar aggregates and filters, explicitly mark omitted arrays.
      void omitCollections(Map map, String path) {
        for (final key in map.keys.toList()) {
          final value = map[key];
          if (value is List && value.isNotEmpty) {
            if (path.isEmpty && key == 'items') {
              for (var index = 0; index < value.length; index++) {
                final item = value[index];
                if (item is Map) omitCollections(item, 'items[$index].');
              }
            } else {
              map.remove(key);
              omittedPaths.add('$path$key');
            }
          } else if (value is Map) {
            omitCollections(value, '$path$key.');
          }
        }
      }

      omitCollections(output, '');
    }
    if (jsonEncode(output).length > payloadLimit) {
      // This fallback applies only to unusually large/unrecognized fields.
      const essential = {
        'ok',
        'error',
        'retryable',
        'view',
        'domain',
        'filters',
        'summary',
        'amount_unit',
        'as_of',
        'goal_scope',
        'total_count',
        'offset',
        'items',
        'has_more',
        'next_offset',
        'future_transaction_count',
      };
      for (final key in output.keys.toList()) {
        if (!essential.contains(key)) {
          output.remove(key);
          omittedPaths.add(key);
        }
      }
      // Keep aggregate numbers even when metadata alone is oversized.
      for (final key in ['filters', 'summary']) {
        if (jsonEncode(output).length <= payloadLimit) break;
        final value = output[key];
        if (value is Map) {
          output[key] = {
            for (final entry in value.entries)
              if (entry.value is num || entry.value is bool)
                entry.key: entry.value,
          };
          omittedPaths.add('$key.text');
        }
      }
    }
    if (originalItems is List &&
        items is List &&
        items.length < originalItems.length) {
      output['items'] = items;
      output['has_more'] = true;
      output['next_offset'] = (result['offset'] as int? ?? 0) + items.length;
      output['returned_count'] = items.length;
      shortened = true;
    }
    if (shortened || omittedPaths.isNotEmpty) {
      output['context_truncated'] = true;
      output['context_notice'] =
          '为控制上下文已省略部分明细或长文本；汇总仍为完整匹配范围。'
          '不要把当前明细当作全部；确有需要时按真实ID读取详情或用next_offset分页。';
      if (omittedPaths.isNotEmpty) {
        output['omitted_fields'] = omittedPaths.take(5).toList();
      }
    }
    if (jsonEncode(output).length > maxChars) {
      return {
        'ok': false,
        'error': '结果超出本轮数据预算，请缩小条件或按真实ID查询详情。',
        'context_truncated': true,
        'retryable': true,
      };
    }
    return output;
  }

  static String history(
    List<Map<String, dynamic>> entries, {
    int maxChars = maxHistoryChars,
  }) {
    if (maxChars < 600 || entries.isEmpty) return '';
    final kept = <Map<String, dynamic>>[];
    for (final entry in entries.reversed) {
      final result = entry['result'];
      if (result is! Map<String, dynamic>) continue;
      final projected = {
        'tool': entry['tool'],
        'arguments': entry['arguments'],
        'result': forModel(
          result,
          maxChars: math.min(1400, maxChars - 200),
          maxItems: 2,
          maxStringChars: 300,
        ),
      };
      if (jsonEncode([...kept, projected]).length > maxChars - 180) break;
      kept.insert(0, projected);
    }
    return jsonEncode({
      'queries': kept,
      'omitted_queries': entries.length - kept.length,
      'notice': '历史查询仅保留简要结果，可能已过时；当前问题需要的最新数据应按条件重查。',
    });
  }

  /// Ignores JSON key order and explicit default values when reusing a query.
  static String queryKey(String name, String arguments) {
    try {
      final args = jsonDecode(arguments);
      if (args is! Map) return '$name:$arguments';
      final normalized = Map<String, dynamic>.from(args);
      if (normalized['offset'] is int && normalized['offset'] == 0) {
        normalized.remove('offset');
      }
      if (normalized['limit'] is int && normalized['limit'] == 10) {
        normalized.remove('limit');
      }
      if (normalized['keyword'] == '') normalized.remove('keyword');
      if (name == 'query_app_data' &&
          normalized['domain'] == 'todos' &&
          normalized['status'] == 'all') {
        normalized.remove('status');
      }
      if (name != 'query_finance' && normalized['view'] == 'list') {
        normalized.remove('view');
      }
      final keys = normalized.keys.toList()..sort();
      return '$name:${jsonEncode({for (final key in keys) key: normalized[key]})}';
    } catch (_) {
      return '$name:$arguments';
    }
  }
}
