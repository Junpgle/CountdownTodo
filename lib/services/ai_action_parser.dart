import 'dart:convert';

import '../models/ai_todo_action.dart';

class AiActionParser {
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
    const actionTypes = 'create_todo|update_todo|complete_todo|delete_todo|'
        'reschedule_todo|bulk_reschedule|bulk_reschedule_todo|'
        'categorize_todo|plan_todos|split_todo|merge_todos|'
        'create_time_log|update_time_log|delete_time_log|'
        'start_pomodoro|stop_pomodoro|'
        'create_countdown|update_countdown|complete_countdown|delete_countdown|'
        'create_todo_group|update_todo_group|delete_todo_group|'
        'create_group|update_group|delete_group|'
        'create_category|update_category|delete_category|'
        'create_folder|update_folder|delete_folder|'
        'create_pomodoro_tag|update_pomodoro_tag|delete_pomodoro_tag';
    final looseActionBlock = RegExp(
      '\\[\\s*\\{\\s*"action"\\s*:\\s*"(?:$actionTypes)"[\\s\\S]*?\\}\\s*\\]',
    );
    cleaned = cleaned.replaceAll(looseActionBlock, '');

    final looseActionObj = RegExp(
      '\\{\\s*"action"\\s*:\\s*"(?:$actionTypes)"[\\s\\S]*?\\}',
    );
    cleaned = cleaned.replaceAll(looseActionObj, '');

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
    switch (data['action']) {
      case 'create_todo':
      case 'plan_todos':
        return _listFrom(data['todos']).map((todo) {
          return AiTodoAction.fromJson({
            ...todo,
            'action': data['action'],
          });
        }).toList();
      case 'update_todo':
      case 'complete_todo':
      case 'delete_todo':
      case 'reschedule_todo':
      case 'bulk_reschedule':
      case 'bulk_reschedule_todo':
      case 'categorize_todo':
        return _listFrom(data['updates']).map((update) {
          final action = AiTodoAction.fromJson({
            ...update,
            'action': data['action'],
          });
          if ((action.title == null || action.title!.isEmpty) &&
              action.todoId != null) {
            action.title = existingTodoTitles[action.todoId!];
          }
          return action;
        }).toList();
      case 'split_todo':
        return _processSplitTodo(data, existingTodoTitles);
      case 'merge_todos':
        return _processMergeTodos(data, existingTodoTitles);
      case 'create_time_log':
        return _listFrom(data['logs']).map((log) {
          return AiTodoAction.fromJson({
            ...log,
            'action': data['action'],
          });
        }).toList();
      case 'update_time_log':
      case 'delete_time_log':
        return _listFrom(data['updates']).map((update) {
          return AiTodoAction.fromJson({
            ...update,
            'todoId': update['todoId'] ?? update['logId'] ?? update['id'],
            'action': data['action'],
          });
        }).toList();
      case 'start_pomodoro':
      case 'stop_pomodoro':
        return [
          AiTodoAction.fromJson({
            ...data,
            'todoId': data['todoId'],
          }),
        ];
      case 'create_countdown':
        return _listFrom(data['countdowns']).map((countdown) {
          return AiTodoAction.fromJson({
            ...countdown,
            'action': data['action'],
          });
        }).toList();
      case 'update_countdown':
      case 'complete_countdown':
      case 'delete_countdown':
        return _listFrom(data['updates']).map((update) {
          return AiTodoAction.fromJson({
            ...update,
            'todoId': update['todoId'] ?? update['countdownId'] ?? update['id'],
            'action': data['action'],
          });
        }).toList();
      case 'create_todo_group':
      case 'create_group':
      case 'create_category':
      case 'create_folder':
        return _listFrom(
                data['groups'] ?? data['categories'] ?? data['folders'])
            .map((group) {
          return AiTodoAction.fromJson({
            ...group,
            'title': group['title'] ?? group['name'],
            'action': data['action'],
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
        return _listFrom(data['updates']).map((update) {
          return AiTodoAction.fromJson({
            ...update,
            'todoId': update['todoId'] ??
                update['groupId'] ??
                update['categoryId'] ??
                update['folderId'] ??
                update['id'],
            'title': update['title'] ?? update['name'],
            'action': data['action'],
          });
        }).toList();
      case 'create_pomodoro_tag':
        return _listFrom(data['tags']).map((tag) {
          return AiTodoAction.fromJson({
            ...tag,
            'title': tag['title'] ?? tag['name'],
            'action': data['action'],
          });
        }).toList();
      case 'update_pomodoro_tag':
      case 'delete_pomodoro_tag':
        return _listFrom(data['updates']).map((update) {
          return AiTodoAction.fromJson({
            ...update,
            'todoId': update['todoId'] ?? update['tagId'] ?? update['id'],
            'title': update['title'] ?? update['name'],
            'action': data['action'],
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
}
