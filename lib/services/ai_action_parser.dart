import 'dart:convert';

import '../models/ai_todo_action.dart';

class AiActionParser {
  static const String _actionTypes = 'create_todo|update_todo|complete_todo|'
      'delete_todo|reschedule_todo|bulk_reschedule|bulk_reschedule_todo|'
      'categorize_todo|plan_todos|split_todo|merge_todos|'
      'create_time_log|update_time_log|delete_time_log|'
      'start_pomodoro|stop_pomodoro|'
      'create_countdown|update_countdown|complete_countdown|delete_countdown|'
      'create_todo_group|update_todo_group|delete_todo_group|'
      'create_group|update_group|delete_group|'
      'create_category|update_category|delete_category|'
      'create_folder|update_folder|delete_folder|'
      'create_pomodoro_tag|update_pomodoro_tag|delete_pomodoro_tag';
  static const String _legacyActionMarkers = 'PLAN_TODOS|CREATE_TODO|'
      'UPDATE_TODO|COMPLETE_TODO|DELETE_TODO|RESCHEDULE_TODO|'
      'CREATE_TIME_LOG|UPDATE_TIME_LOG|DELETE_TIME_LOG|'
      'CREATE_COUNTDOWN|UPDATE_COUNTDOWN|DELETE_COUNTDOWN';

  static List<AiTodoAction> extractTodoActions(
    String content, {
    required String originalText,
    Map<String, String> existingTodoTitles = const {},
  }) {
    final actions = <AiTodoAction>[];

    void parseAndProcess(String jsonStr) {
      if (jsonStr.trim().isEmpty) return;

      try {
        final data = jsonDecode(_repairJson(jsonStr.trim()));
        if (data is Map<String, dynamic>) {
          actions.addAll(_processActionMap(data, existingTodoTitles));
        } else if (data is List) {
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              actions.addAll(_processActionMap(item, existingTodoTitles));
            }
          }
        }
      } catch (_) {
        // Ignore malformed action blocks. The assistant response is still shown.
      }
    }

    final matches = RegExp(
      r'\[ACTION_START\](.*?)\[ACTION_END\]',
      dotAll: true,
    ).allMatches(content).toList();

    if (matches.isNotEmpty) {
      for (final match in matches) {
        parseAndProcess(match.group(1) ?? '');
      }
    } else {
      final startIndex = content.indexOf('[ACTION_START]');
      if (startIndex != -1) {
        final remaining =
            content.substring(startIndex + '[ACTION_START]'.length);
        final suggestIndex = remaining.indexOf('[SUGGEST_START]');
        parseAndProcess(
          suggestIndex != -1 ? remaining.substring(0, suggestIndex) : remaining,
        );
      }
    }

    if (actions.isEmpty) {
      final contentWithoutSuggestions = content.replaceAll(
        RegExp(r'\[SUGGEST_START\].*?\[SUGGEST_END\]', dotAll: true),
        '',
      );
      for (final candidate in _findLooseActionJsonBlocks(
        contentWithoutSuggestions,
      )) {
        parseAndProcess(candidate);
      }
    }

    for (final action in actions) {
      action.originalText ??= originalText;
    }
    return actions;
  }

  static String cleanActionContent(String content) {
    String cleaned = content
        .replaceAll(
          RegExp(r'\[ACTION_START\].*?\[ACTION_END\]', dotAll: true),
          '',
        )
        .replaceAll(
          RegExp(r'\[SUGGEST_START\].*?\[SUGGEST_END\]', dotAll: true),
          '',
        );

    // Only remove well-formed JSON arrays/objects that start with "action" key
    // and contain known action types, to avoid accidentally removing user text.
    for (final candidate in _findLooseActionJsonBlocks(cleaned)) {
      cleaned = cleaned.replaceAll(candidate, '');
    }
    cleaned = cleaned
        .replaceAll(RegExp('\\[(?:$_legacyActionMarkers)\\]'), '')
        .replaceAll(RegExp(r'```(?:json)?\s*```', dotAll: true), '');

    return cleaned.trim();
  }

  static List<String> extractSuggestions(String content) {
    final suggestions = <String>[];
    final regex = RegExp(
      r'\[SUGGEST_START\](.*?)\[SUGGEST_END\]',
      dotAll: true,
    );
    for (final match in regex.allMatches(content)) {
      try {
        final jsonStr = match.group(1)!.trim();
        final list = jsonDecode(jsonStr) as List;
        for (final item in list) {
          final suggestion = item.toString().trim();
          if (suggestion.isNotEmpty) suggestions.add(suggestion);
        }
      } catch (_) {}
    }
    return suggestions;
  }

  static List<AiTodoAction> _processActionMap(
    Map<String, dynamic> data,
    Map<String, String> existingTodoTitles,
  ) {
    final actionData = _withInferredAction(data);
    switch (actionData['action']) {
      case 'create_todo':
      case 'plan_todos':
        return _listFromOrSelf(actionData, actionData['todos']).map((todo) {
          return AiTodoAction.fromJson({
            ...todo,
            'action': actionData['action'],
          });
        }).toList();
      case 'update_todo':
      case 'complete_todo':
      case 'delete_todo':
      case 'reschedule_todo':
      case 'bulk_reschedule':
      case 'bulk_reschedule_todo':
      case 'categorize_todo':
        return _listFromOrSelf(actionData, actionData['updates']).map((update) {
          final action = AiTodoAction.fromJson({
            ...update,
            'action': actionData['action'],
          });
          if ((action.title == null || action.title!.isEmpty) &&
              action.todoId != null) {
            action.title = existingTodoTitles[action.todoId!];
          }
          return action;
        }).toList();
      case 'split_todo':
        return _processSplitTodo(actionData, existingTodoTitles);
      case 'merge_todos':
        return _processMergeTodos(actionData, existingTodoTitles);
      case 'create_time_log':
        return _listFromOrSelf(actionData, actionData['logs']).map((log) {
          return AiTodoAction.fromJson({
            ...log,
            'action': actionData['action'],
          });
        }).toList();
      case 'update_time_log':
      case 'delete_time_log':
        return _listFromOrSelf(actionData, actionData['updates']).map((update) {
          return AiTodoAction.fromJson({
            ...update,
            'todoId': update['todoId'] ?? update['logId'] ?? update['id'],
            'action': actionData['action'],
          });
        }).toList();
      case 'start_pomodoro':
      case 'stop_pomodoro':
        return [
          AiTodoAction.fromJson({
            ...actionData,
            'todoId': actionData['todoId'],
          }),
        ];
      case 'create_countdown':
        return _listFromOrSelf(actionData, actionData['countdowns'])
            .map((countdown) {
          return AiTodoAction.fromJson({
            ...countdown,
            'action': actionData['action'],
          });
        }).toList();
      case 'update_countdown':
      case 'complete_countdown':
      case 'delete_countdown':
        return _listFromOrSelf(actionData, actionData['updates']).map((update) {
          return AiTodoAction.fromJson({
            ...update,
            'todoId': update['todoId'] ?? update['countdownId'] ?? update['id'],
            'action': actionData['action'],
          });
        }).toList();
      case 'create_todo_group':
      case 'create_group':
      case 'create_category':
      case 'create_folder':
        return _listFromOrSelf(
                actionData,
                actionData['groups'] ??
                    actionData['categories'] ??
                    actionData['folders'])
            .map((group) {
          return AiTodoAction.fromJson({
            ...group,
            'title': group['title'] ?? group['name'],
            'action': actionData['action'],
          });
        }).toList();
      case 'update_todo_group':
      case 'update_group':
      case 'update_category':
      case 'update_folder':
      case 'delete_todo_group':
      case 'delete_group':
      case 'delete_category':
      case 'delete_folder':
        return _listFromOrSelf(actionData, actionData['updates']).map((update) {
          return AiTodoAction.fromJson({
            ...update,
            'todoId': update['todoId'] ??
                update['groupId'] ??
                update['categoryId'] ??
                update['folderId'] ??
                update['id'],
            'title': update['title'] ?? update['name'],
            'action': actionData['action'],
          });
        }).toList();
      case 'create_pomodoro_tag':
        return _listFromOrSelf(actionData, actionData['tags']).map((tag) {
          return AiTodoAction.fromJson({
            ...tag,
            'title': tag['title'] ?? tag['name'],
            'action': actionData['action'],
          });
        }).toList();
      case 'update_pomodoro_tag':
      case 'delete_pomodoro_tag':
        return _listFromOrSelf(actionData, actionData['updates']).map((update) {
          return AiTodoAction.fromJson({
            ...update,
            'todoId': update['todoId'] ?? update['tagId'] ?? update['id'],
            'title': update['title'] ?? update['name'],
            'action': actionData['action'],
          });
        }).toList();
      default:
        return [];
    }
  }

  static List<AiTodoAction> _processSplitTodo(
    Map<String, dynamic> data,
    Map<String, String> existingTodoTitles,
  ) {
    final sourceTodoId = data['sourceTodoId']?.toString() ??
        data['todoId']?.toString() ??
        data['source_id']?.toString();
    final actions = _listFrom(data['todos']).map((todo) {
      return AiTodoAction.fromJson({
        ...todo,
        'action': 'split_todo',
        'sourceTodoId': sourceTodoId,
        'deleteSourceTodos': data['deleteSource'] == true,
      });
    }).toList();

    if (data['deleteSource'] == true && sourceTodoId != null) {
      actions.add(
        AiTodoAction(
          type: AiTodoActionType.deleteTodo,
          todoId: sourceTodoId,
          title: existingTodoTitles[sourceTodoId],
          metadata: {'generatedBy': 'split_todo'},
        ),
      );
    }
    return actions;
  }

  static List<AiTodoAction> _processMergeTodos(
    Map<String, dynamic> data,
    Map<String, String> existingTodoTitles,
  ) {
    final sourceTodoIds = _stringList(data['sourceTodoIds'] ?? data['todoIds']);
    final todo = data['todo'];
    final actions = <AiTodoAction>[];
    if (todo is Map) {
      actions.add(
        AiTodoAction.fromJson({
          ...Map<String, dynamic>.from(todo),
          'action': 'merge_todos',
          'sourceTodoIds': sourceTodoIds,
          'deleteSourceTodos': data['deleteSources'] == true,
        }),
      );
    }

    if (data['deleteSources'] == true) {
      for (final id in sourceTodoIds) {
        actions.add(
          AiTodoAction(
            type: AiTodoActionType.deleteTodo,
            todoId: id,
            title: existingTodoTitles[id],
            metadata: {'generatedBy': 'merge_todos'},
          ),
        );
      }
    }
    return actions;
  }

  static List<Map<String, dynamic>> _listFrom(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Map<String, dynamic> _withInferredAction(Map<String, dynamic> data) {
    if (data['action'] != null) return data;
    if (data['todos'] is List) {
      return {...data, 'action': 'plan_todos'};
    }
    if (data['countdowns'] is List) {
      return {...data, 'action': 'create_countdown'};
    }
    if (data['logs'] is List) {
      return {...data, 'action': 'create_time_log'};
    }
    if (data['groups'] is List ||
        data['categories'] is List ||
        data['folders'] is List) {
      return {...data, 'action': 'create_todo_group'};
    }
    if (data['tags'] is List) {
      return {...data, 'action': 'create_pomodoro_tag'};
    }
    return data;
  }

  static List<Map<String, dynamic>> _listFromOrSelf(
    Map<String, dynamic> self,
    dynamic value,
  ) {
    final list = _listFrom(value);
    if (list.isNotEmpty) return list;
    return [self];
  }

  static List<String> _stringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [value.toString()];
  }

  static String _repairJson(String jsonStr) {
    var formattedJson = jsonStr;
    var openBraces = 0;
    var closeBraces = 0;
    var openBrackets = 0;
    var closeBrackets = 0;

    for (var i = 0; i < formattedJson.length; i++) {
      if (formattedJson[i] == '{') {
        openBraces++;
      } else if (formattedJson[i] == '}') {
        closeBraces++;
      } else if (formattedJson[i] == '[') {
        openBrackets++;
      } else if (formattedJson[i] == ']') {
        closeBrackets++;
      }
    }

    while (closeBrackets < openBrackets) {
      formattedJson += ']';
      closeBrackets++;
    }
    while (closeBraces < openBraces) {
      formattedJson += '}';
      closeBraces++;
    }
    return formattedJson;
  }

  static List<String> _findLooseActionJsonBlocks(String content) {
    final candidates = <String>[];
    final seen = <String>{};
    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (char != '{' && char != '[') continue;

      final end = _findBalancedJsonEnd(content, i);
      if (end == -1) continue;

      final candidate = content.substring(i, end + 1).trim();
      final hasKnownAction =
          RegExp('"action"\\s*:\\s*"(?:$_actionTypes)"').hasMatch(candidate);
      final hasLegacyContainer = RegExp(
              '"(?:todos|countdowns|logs|groups|categories|folders|tags)"\\s*:')
          .hasMatch(candidate);
      if (!hasKnownAction && !hasLegacyContainer) {
        continue;
      }
      if (seen.add(candidate)) {
        candidates.add(candidate);
      }
      i = end;
    }
    return candidates;
  }

  static int _findBalancedJsonEnd(String content, int start) {
    final stack = <String>[];
    var inString = false;
    var escaped = false;

    for (var i = start; i < content.length; i++) {
      final char = content[i];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        stack.add('}');
      } else if (char == '[') {
        stack.add(']');
      } else if (char == '}' || char == ']') {
        if (stack.isEmpty || stack.last != char) return -1;
        stack.removeLast();
        if (stack.isEmpty) return i;
      }
    }

    return -1;
  }
}
