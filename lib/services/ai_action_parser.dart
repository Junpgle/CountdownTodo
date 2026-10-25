import 'dart:convert';

import '../models.dart';
import '../models/ai_todo_action.dart';
import 'ai_team_binding_resolver.dart';
import 'ai_settings_navigation_service.dart';
import 'ai_tool_result_context.dart';

class AiActionParser {
  static const Set<String> _genericSuggestionTerms = {
    '帮我',
    '请问',
    '可以',
    '是否',
    '如何',
    '怎么',
    '能否',
    '要不要',
    '什么',
    '哪些',
    '今天',
    '明天',
    '昨天',
    '最近',
    '这周',
    '本周',
    '下周',
    '还有',
    '多少',
    '多久',
    '一下',
    '需要',
    '帮忙',
    '使用',
    '深度',
    '规划',
    '待办',
    '任务',
    '课程',
    '节课',
    '效率',
    '紧急',
    '分析',
    '统计',
    '查询',
    '查看',
    '安排',
    '处理',
    '创建',
    '修改',
    '调整',
    '添加',
    '删除',
    '保存',
    '开始',
    '继续',
    '更新',
    '生成',
    '完成',
    '的',
    '了',
    '是',
    '我',
    '你',
    '您',
    '有',
    '在',
    '呢',
    '吗',
    '吧',
    '和',
    '或',
    '这',
    '那',
    '看',
    '问',
    '课程表',
    '上周',
    '每天',
    '每周',
    '周末',
    '本月',
    '本学期',
    '建议',
    '后续',
    '相关',
    '接下来',
    '预测',
    'help',
    'please',
    'how',
    'what',
    'can',
    'could',
    'show',
    'list',
    'today',
    'tomorrow',
    'week',
    'plan',
    'task',
    'todo',
    'course',
    'analyze',
    'analysis',
  };

  static const String _actionTypes =
      'create_todo|update_todo|complete_todo|skip_todo|'
      'create_habit|create_habit_goal|habit_create|'
      'update_habit|update_habit_goal|habit_update|'
      'delete_habit|delete_habit_goal|habit_delete|'
      'delete_todo|reschedule_todo|bulk_reschedule|bulk_reschedule_todo|'
      'create_schedule|update_schedule|cancel_schedule|delete_schedule|'
      'create_fixed_schedule|update_fixed_schedule|cancel_fixed_schedule|'
      'delete_fixed_schedule|'
      'categorize_todo|plan_todos|create_plan_block|update_plan_block|'
      'delete_plan_block|reschedule_plan_blocks|reschedule_plan_block|'
      'skip_plan_block|start_plan_block_pomodoro|'
      'create_todo_plan_block|schedule_todo_block|split_todo|merge_todos|'
      'create_time_log|update_time_log|delete_time_log|'
      'start_pomodoro|stop_pomodoro|'
      'create_countdown|update_countdown|complete_countdown|delete_countdown|'
      'create_todo_group|update_todo_group|delete_todo_group|'
      'create_group|update_group|delete_group|'
      'create_category|update_category|delete_category|'
      'create_folder|update_folder|delete_folder|'
      'create_pomodoro_tag|update_pomodoro_tag|delete_pomodoro_tag';
  static const String _legacyActionMarkers =
      'PLAN_TODOS|CREATE_TODO|'
      'UPDATE_TODO|COMPLETE_TODO|DELETE_TODO|RESCHEDULE_TODO|'
      'CREATE_TIME_LOG|UPDATE_TIME_LOG|DELETE_TIME_LOG|'
      'CREATE_COUNTDOWN|UPDATE_COUNTDOWN|DELETE_COUNTDOWN';

  static List<AiTodoAction> extractTodoActions(
    String content, {
    required String originalText,
    Map<String, String> existingTodoTitles = const {},
    Map<String, String> existingScheduleTitles = const {},
    List<Team> availableTeams = const [],
    Set<String>? allowedActionNames,
  }) {
    content = AiToolResultContext.withoutHistory(content);
    final actions = <AiTodoAction>[];
    final planningIntent = _looksLikePlanningIntent(originalText);

    void processAction(Map<String, dynamic> actionData) {
      final inferredAction = _withInferredAction(
        actionData,
        planningIntent: planningIntent,
      );
      if (allowedActionNames != null) {
        final actionName = _canonicalActionName(
          inferredAction['action']?.toString(),
        );
        if (actionName == null || !allowedActionNames.contains(actionName)) {
          return;
        }
      }
      actions.addAll(
        _processActionMap(
          inferredAction,
          existingTodoTitles,
          existingScheduleTitles,
          planningIntent: planningIntent,
        ),
      );
    }

    void parseAndProcess(String jsonStr) {
      if (jsonStr.trim().isEmpty) return;

      try {
        final data = jsonDecode(_repairJson(jsonStr.trim()));
        if (data is Map<String, dynamic>) {
          final envelopeActions = data['actions'];
          if (envelopeActions is List &&
              (data['version'] == 2 ||
                  data['protocol']?.toString() == 'cdt.actions')) {
            for (final item in envelopeActions.whereType<Map>()) {
              processAction(Map<String, dynamic>.from(item));
            }
          } else {
            processAction(data);
          }
        } else if (data is List) {
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              processAction(item);
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
        final remaining = content.substring(
          startIndex + '[ACTION_START]'.length,
        );
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
      if (action.recurrenceScope == 'series' &&
          (action.type != AiTodoActionType.updateTodo ||
              !_explicitWholeTodoSeriesRequest(originalText))) {
        action
          ..recurrenceScope = 'occurrence'
          ..metadata['wholeSeriesScopeDowngraded'] = true;
      }
      // Execution state belongs to the app, never to a newly returned proposal.
      // History restoration uses AiTodoAction.fromJson directly and retains it.
      action.isAdded = false;
      action.isIgnored = false;
      action.isSelected = true;
      action.originalText ??= originalText;
    }
    _resolveCountdownTeamBindings(
      actions,
      originalText: originalText,
      availableTeams: availableTeams,
    );
    return actions;
  }

  static bool _explicitWholeTodoSeriesRequest(String message) => RegExp(
    r'(整个系列|全系列|所有期次|全部期次|所有周期|全部周期|每一期|全体期次|whole series|entire series|all occurrences)',
    caseSensitive: false,
  ).hasMatch(message);

  static void _resolveCountdownTeamBindings(
    List<AiTodoAction> actions, {
    required String originalText,
    required List<Team> availableTeams,
  }) {
    final hasRequestedTeamBinding =
        AiTeamBindingResolver.hasExplicitBindingIntent(originalText);
    final requestedTeam = AiTeamBindingResolver.requestedTeam(
      originalText,
      teams: availableTeams,
    );
    for (final action in actions.where(
      (action) => action.type == AiTodoActionType.createCountdown,
    )) {
      if (requestedTeam != null) {
        action.teamName = requestedTeam.name;
        action.teamUuid = requestedTeam.uuid;
        action.hasTeamUuid = true;
      } else if (hasRequestedTeamBinding) {
        // An explicit but unmatched local team must never become a pseudo
        // binding on a proposal card. The send flow reports the lookup failure.
        action.teamName = null;
        action.teamUuid = null;
        action.hasTeamUuid = true;
      } else if (action.teamName?.trim().isNotEmpty == true) {
        final team = AiTeamBindingResolver.resolveName(
          action.teamName!,
          teams: availableTeams,
        );
        if (team != null) {
          action.teamUuid = team.uuid;
          action.teamName = team.name;
        } else {
          final teamByUuid = action.teamUuid == null
              ? null
              : _teamByUuid(action.teamUuid!, availableTeams);
          if (teamByUuid != null) {
            action.teamUuid = teamByUuid.uuid;
            action.teamName = teamByUuid.name;
          } else {
            action.teamName = action.teamName!.trim();
          }
        }
        action.hasTeamUuid = true;
      } else if (action.teamUuid?.trim().isNotEmpty == true) {
        final team = _teamByUuid(action.teamUuid!, availableTeams);
        if (team != null) action.teamName = team.name;
        action.hasTeamUuid = true;
      }

      final teamName = action.teamName?.trim();
      if (action.hasTeamUuid && teamName?.isNotEmpty == true) {
        final title = action.title;
        if (title != null) {
          action.title = title
              .replaceFirst(
                RegExp(
                  '^\\s*${RegExp.escape(teamName!)}'
                  r'(?:\s*[·•|:：、\-—–]\s*|\s+)',
                ),
                '',
              )
              .trim();
        }
      }
    }
  }

  static Team? _teamByUuid(String uuid, List<Team> teams) {
    for (final team in teams) {
      if (team.uuid == uuid.trim()) return team;
    }
    return null;
  }

  static String cleanActionContent(String content) {
    final hadLegacyToolCall = RegExp(
      r'</?tool_call\b',
      caseSensitive: false,
    ).hasMatch(content);
    String cleaned =
        AiSettingsNavigationService.cleanContent(
              AiToolResultContext.withoutHistory(content),
            )
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
    cleaned = cleaned.replaceAll(
      RegExp(
        r'<tool_call\b[^>]*>[\s\S]*?</tool_call\s*>',
        caseSensitive: false,
      ),
      '',
    );
    final malformedToolCall = RegExp(
      r'<tool_call\b',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (malformedToolCall != null) {
      cleaned = cleaned.substring(0, malformedToolCall.start);
    }
    cleaned = cleaned.replaceAll(
      RegExp(r'</tool_call\s*>', caseSensitive: false),
      '',
    );

    final visibleContent = cleaned.trim();
    if (visibleContent.isEmpty && hadLegacyToolCall) {
      return '这条回复包含未执行的工具调用，请重新发送问题。';
    }
    return visibleContent;
  }

  static List<String> extractSuggestions(
    String content, {
    Iterable<String> previouslyShown = const [],
    String? contextText,
  }) {
    final regex = RegExp(
      r'\[SUGGEST_START\](.*?)\[SUGGEST_END\]',
      dotAll: true,
    );
    final matches = regex.allMatches(content).toList();
    if (matches.isEmpty) return const [];
    try {
      final jsonStr = matches.last.group(1)!.trim();
      final list = jsonDecode(jsonStr) as List;
      final suggestions = <String>[];
      final seen = previouslyShown
          .map((suggestion) => suggestion.trim().toLowerCase())
          .where((suggestion) => suggestion.isNotEmpty)
          .toSet();
      for (final item in list) {
        if (item is! String) continue;
        final suggestion = item.trim();
        final suggestionTerms = _meaningfulSuggestionTerms(suggestion);
        if (suggestion.isEmpty ||
            suggestion.runes.length > 15 ||
            suggestionTerms.isEmpty ||
            !seen.add(suggestion.toLowerCase()) ||
            (contextText != null &&
                !_isGroundedInContext(suggestion, contextText))) {
          continue;
        }
        suggestions.add(suggestion);
        if (suggestions.length == 4) return suggestions;
      }
      return suggestions;
    } catch (_) {
      return const [];
    }
  }

  static bool _isGroundedInContext(String suggestion, String contextText) {
    if (contextText.trim().isEmpty) return false;
    final suggestionTerms = _meaningfulSuggestionTerms(suggestion);
    if (suggestionTerms.isEmpty) return false;
    final contextTerms = _meaningfulSuggestionTerms(contextText);
    return suggestionTerms.any(contextTerms.contains);
  }

  static Set<String> _meaningfulSuggestionTerms(String text) {
    final terms = <String>{};
    var normalized = text.toLowerCase();
    final genericTerms = _genericSuggestionTerms.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final genericTerm in genericTerms) {
      normalized = normalized.replaceAll(genericTerm, ' ');
    }
    for (final match in RegExp(
      r'[\u4E00-\u9FFF]{2,}|[a-zA-Z][a-zA-Z0-9_-]*',
    ).allMatches(normalized)) {
      final word = match.group(0)!;
      if (RegExp(r'^[a-z]').hasMatch(word)) {
        if (word.length >= 3) terms.add(word);
        continue;
      }
      final runes = word.runes.toList(growable: false);
      for (var length = 2; length <= 3 && length <= runes.length; length++) {
        for (var start = 0; start + length <= runes.length; start++) {
          final term = String.fromCharCodes(runes.skip(start).take(length));
          terms.add(term);
        }
      }
    }
    return terms;
  }

  static List<AiTodoAction> _processActionMap(
    Map<String, dynamic> data,
    Map<String, String> existingTodoTitles,
    Map<String, String> existingScheduleTitles, {
    bool planningIntent = false,
  }) {
    final actionData = _withInferredAction(
      data,
      planningIntent: planningIntent,
    );
    switch (actionData['action']) {
      case 'create_todo':
        return _listFromOrSelf(actionData, actionData['todos']).map((todo) {
          final normalizedTodo = Map<String, dynamic>.from(todo)
            ..remove('date')
            ..remove('startTime')
            ..remove('endTime');
          return AiTodoAction.fromJson({
            ...normalizedTodo,
            'action': actionData['action'],
          });
        }).toList();
      case 'create_habit':
      case 'create_habit_goal':
      case 'habit_create':
        return _listFromOrSelf(
          actionData,
          actionData['habits'] ??
              actionData['goals'] ??
              actionData['items'] ??
              actionData['habit'],
        ).map((habit) {
          return AiTodoAction.fromJson({
            ...habit,
            'title': habit['title'] ?? habit['name'],
            'action': actionData['action'],
          });
        }).toList();
      case 'update_habit':
      case 'update_habit_goal':
      case 'habit_update':
      case 'delete_habit':
      case 'delete_habit_goal':
      case 'habit_delete':
        return _listFromOrSelf(actionData, actionData['updates']).map((habit) {
          final updateFields = <String, dynamic>{
            for (final key in const [
              'name',
              'icon',
              'displayMode',
              'defaultFocusMinutes',
              'targetValue',
              'unit',
              'durationMinutes',
              'targetTimeMinute',
              'timeComparison',
              'timeToleranceMinutes',
              'periodType',
              'weekdaysMask',
              'customIntervalDays',
              'dayBoundaryMinute',
              'quickValues',
              'reminderPolicy',
              'effectiveFromOption',
            ])
              if (habit.containsKey(key)) key: habit[key],
          };
          final existingMetadata = habit['metadata'] is Map
              ? Map<String, dynamic>.from(habit['metadata'] as Map)
              : <String, dynamic>{};
          return AiTodoAction.fromJson({
            ...habit,
            'habitUuid':
                habit['habitUuid'] ??
                habit['habit_uuid'] ??
                habit['habitId'] ??
                habit['habit_id'] ??
                habit['id'],
            'title': habit['title'] ?? habit['name'] ?? habit['habitName'],
            'metadata': {
              ...existingMetadata,
              if (actionData['action'] == 'update_habit' &&
                  updateFields.isNotEmpty)
                'habitUpdateFields': updateFields,
            },
            'action': actionData['action'],
          });
        }).toList();
      case 'plan_todos':
        // Older prompts used plan_todos for both new todos and scheduling an
        // existing todo. Only the latter is safe to preserve. An unmatched or
        // ambiguous title is discarded instead of falling through to todo
        // creation, because planning must never duplicate an existing item.
        return _listFromOrSelf(actionData, actionData['todos'])
            .map((todo) {
              final existingTodoId = _existingTodoIdForPlan(
                todo,
                existingTodoTitles,
              );
              if (existingTodoId == null) return null;
              return AiTodoAction.fromJson({
                ...todo,
                'title': todo['title'] ?? todo['titleSnapshot'],
                'action': 'create_plan_block',
                'todoId': existingTodoId,
              });
            })
            .whereType<AiTodoAction>()
            .toList();
      case 'create_schedule':
      case 'create_fixed_schedule':
        return _listFromOrSelf(
          actionData,
          actionData['schedules'] ?? actionData['fixedSchedules'],
        ).map((schedule) {
          return AiTodoAction.fromJson({
            ...schedule,
            'action': actionData['action'],
          });
        }).toList();
      case 'update_schedule':
      case 'update_fixed_schedule':
      case 'cancel_schedule':
      case 'cancel_fixed_schedule':
      case 'delete_schedule':
      case 'delete_fixed_schedule':
        return _listFromOrSelf(actionData, actionData['updates']).map((
          schedule,
        ) {
          final action = AiTodoAction.fromJson({
            ...schedule,
            'scheduleId':
                schedule['scheduleId'] ??
                schedule['fixedScheduleId'] ??
                schedule['id'],
            'action': actionData['action'],
          });
          if ((action.title == null || action.title!.isEmpty) &&
              action.scheduleId != null) {
            action.title = existingScheduleTitles[action.scheduleId!];
          }
          return action;
        }).toList();
      case 'create_plan_block':
      case 'create_todo_plan_block':
      case 'schedule_todo_block':
        return _listFromOrSelf(
              actionData,
              actionData['blocks'] ??
                  actionData['plans'] ??
                  actionData['todos'],
            )
            .map((block) {
              final newTitle = block['newTodoTitle'];
              final newTodoTitle = newTitle is String ? newTitle.trim() : '';
              final inferredTodoId = _existingTodoIdForPlan({
                ...block,
                if (newTodoTitle.isNotEmpty && block['title'] == null)
                  'title': newTodoTitle,
              }, existingTodoTitles);
              final hasSuppliedId = [
                block['todoId'],
                block['todo_id'],
                block['todoUuid'],
                block['id'],
              ].any((id) => id?.toString().trim().isNotEmpty == true);
              return AiTodoAction.fromJson({
                ...block,
                'todoId': inferredTodoId,
                'title':
                    block['title'] ??
                    block['titleSnapshot'] ??
                    (newTodoTitle.isEmpty ? null : newTodoTitle),
                'metadata': {
                  if (inferredTodoId == null &&
                      !hasSuppliedId &&
                      newTodoTitle.isNotEmpty)
                    'newTodoTitle': newTodoTitle,
                },
                'action': actionData['action'],
              });
            })
            .where((action) {
              final todoId = action.todoId?.trim();
              return action.newTodoTitle != null ||
                  (todoId != null &&
                      todoId.isNotEmpty &&
                      existingTodoTitles.containsKey(todoId));
            })
            .toList();
      case 'update_plan_block':
      case 'delete_plan_block':
      case 'reschedule_plan_blocks':
      case 'reschedule_plan_block':
      case 'skip_plan_block':
      case 'start_plan_block_pomodoro':
        return _listFromOrSelf(
          actionData,
          actionData['blocks'] ?? actionData['updates'],
        ).map((block) {
          return AiTodoAction.fromJson({
            ...block,
            'planBlockId':
                block['planBlockId'] ??
                block['plan_block_id'] ??
                block['blockId'] ??
                block['id'],
            'todoId': block['todoId'] ?? block['todo_id'] ?? block['todoUuid'],
            'title': block['title'] ?? block['titleSnapshot'],
            'action': actionData['action'],
          });
        }).toList();
      case 'categorize_todo':
        return _listFromOrSelf(actionData, actionData['updates'])
            .map((update) {
              final todoId = _resolveExistingTodoId(update, existingTodoTitles);
              final action = AiTodoAction.fromJson({
                ...update,
                'todoId': todoId,
                // Categorization must never rename the todo. Use the local
                // title for the confirmation card instead of model text.
                'title': todoId == null ? null : existingTodoTitles[todoId],
                'action': actionData['action'],
              });
              return action;
            })
            .where(
              (action) =>
                  action.todoId?.trim().isNotEmpty == true &&
                  existingTodoTitles.containsKey(action.todoId),
            )
            .toList();
      case 'update_todo':
      case 'complete_todo':
      case 'delete_todo':
      case 'reschedule_todo':
      case 'bulk_reschedule':
      case 'bulk_reschedule_todo':
        final actionName = actionData['action']?.toString() ?? '';
        final actions = <AiTodoAction>[];
        for (final update in _listFromOrSelf(
          actionData,
          actionData['updates'],
        )) {
          final todoId = _resolveExistingTodoId(update, existingTodoTitles);
          if (todoId == null) continue;
          final action = AiTodoAction.fromJson({
            ...update,
            'todoId': todoId,
            'action': actionName,
          });
          final proposedTitle = action.title?.trim();
          if (action.type != AiTodoActionType.updateTodo ||
              proposedTitle == null ||
              proposedTitle.isEmpty) {
            action.title = existingTodoTitles[todoId];
          }
          actions.add(action);
        }
        return actions;
      case 'skip_todo':
        // Skipping is deliberately bound to one existing UUID. Do not infer
        // an occurrence from a title or accept a future-series scope.
        return _listFromOrSelf(actionData, actionData['updates'])
            .where((update) {
              final suppliedIds = {
                for (final value in [
                  update['todoId'],
                  update['todo_id'],
                  update['todoUuid'],
                  update['id'],
                ])
                  if (value?.toString().trim().isNotEmpty == true)
                    value.toString().trim(),
              };
              return suppliedIds.length == 1 &&
                  existingTodoTitles.containsKey(suppliedIds.single) &&
                  update['recurrenceScope']?.toString() != 'future';
            })
            .map((update) {
              final todoId = _resolveExistingTodoId(
                update,
                existingTodoTitles,
              )!;
              return AiTodoAction.fromJson({
                ...update,
                'todoId': todoId,
                'recurrenceScope': 'occurrence',
                'action': actionData['action'],
              });
            })
            .toList(growable: false);
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
        return _listFromOrSelf(actionData, actionData['countdowns']).map((
          countdown,
        ) {
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
              actionData['folders'],
        ).map((group) {
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
            'todoId':
                update['todoId'] ??
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
    final sourceTodoId =
        [data['sourceTodoId'], data['todoId'], data['source_id']]
            .map((value) => value?.toString().trim() ?? '')
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final splitTodos = _listFrom(data['todos']);
    if (sourceTodoId.isEmpty ||
        !existingTodoTitles.containsKey(sourceTodoId) ||
        splitTodos.isEmpty ||
        splitTodos.any(
          (todo) => todo['title']?.toString().trim().isNotEmpty != true,
        )) {
      return [];
    }
    final deleteSource =
        data['deleteSource'] == true ||
        data['deleteSourceTodos'] == true ||
        data['deleteSources'] == true;
    final actions = splitTodos.map((todo) {
      return AiTodoAction.fromJson({
        ...todo,
        'action': 'split_todo',
        'sourceTodoId': sourceTodoId,
        'deleteSourceTodos': deleteSource,
      });
    }).toList();

    if (deleteSource && actions.isNotEmpty) {
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
    final rawSourceTodoIds = _stringList(
      data['sourceTodoIds'] ?? data['todoIds'],
    ).map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList();
    final todo = data['todo'];
    final deleteSources =
        data['deleteSources'] == true ||
        data['deleteSourceTodos'] == true ||
        data['deleteSource'] == true;
    if (rawSourceTodoIds.length < 2 ||
        rawSourceTodoIds.any((id) => !existingTodoTitles.containsKey(id)) ||
        todo is! Map ||
        todo['title']?.toString().trim().isNotEmpty != true) {
      return [];
    }
    final sourceTodoIds = rawSourceTodoIds;
    final actions = <AiTodoAction>[];
    actions.add(
      AiTodoAction.fromJson({
        ...Map<String, dynamic>.from(todo),
        'action': 'merge_todos',
        'sourceTodoIds': sourceTodoIds,
        'deleteSourceTodos': deleteSources,
      }),
    );

    if (deleteSources) {
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

  static Map<String, dynamic> _withInferredAction(
    Map<String, dynamic> data, {
    bool planningIntent = false,
  }) {
    if (data['action'] != null) return data;
    if (data['todos'] is List) {
      final todoList = data['todos'] as List;
      final hasExistingRef = todoList.any(
        (t) =>
            t is Map &&
            (t.containsKey('todoId') ||
                t.containsKey('todo_id') ||
                t.containsKey('todoUuid')),
      );
      return {
        ...data,
        // An actionless todos payload in a planning request is a legacy
        // planning response. Route it through plan-block validation so it
        // cannot silently create duplicate TodoItems without a real todoId.
        'action': hasExistingRef || planningIntent ? 'create_plan_block' : null,
      };
    }
    if (data['habits'] is List ||
        data['goals'] is List ||
        data['habit'] is Map) {
      return {...data, 'action': 'create_habit'};
    }
    if (data['blocks'] is List || data['plans'] is List) {
      return {...data, 'action': 'create_plan_block'};
    }
    if (data['schedules'] is List || data['fixedSchedules'] is List) {
      return {...data, 'action': 'create_schedule'};
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

  static String? _canonicalActionName(String? action) {
    if (action == null || action.trim().isEmpty) return null;
    switch (action.trim()) {
      case 'create_habit_goal':
      case 'habit_create':
        return 'create_habit';
      case 'update_habit_goal':
      case 'habit_update':
        return 'update_habit';
      case 'delete_habit_goal':
      case 'habit_delete':
        return 'delete_habit';
      case 'create_fixed_schedule':
        return 'create_schedule';
      case 'update_fixed_schedule':
        return 'update_schedule';
      case 'cancel_fixed_schedule':
        return 'cancel_schedule';
      case 'delete_fixed_schedule':
        return 'delete_schedule';
      case 'plan_todos':
      case 'create_todo_plan_block':
      case 'schedule_todo_block':
        return 'create_plan_block';
      case 'reschedule_plan_block':
        return 'reschedule_plan_blocks';
      case 'bulk_reschedule_todo':
        return 'bulk_reschedule';
      case 'create_group':
      case 'create_category':
      case 'create_folder':
        return 'create_todo_group';
      case 'update_group':
      case 'update_category':
      case 'update_folder':
        return 'update_todo_group';
      case 'delete_group':
      case 'delete_category':
      case 'delete_folder':
        return 'delete_todo_group';
      default:
        return action.trim();
    }
  }

  static bool _looksLikePlanningIntent(String text) {
    return RegExp(
      r'(规划|安排.*(待办|任务|时间|计划)|计划.*(待办|任务|时间)|排.*计划|plan(?:ning)?|time\s*block)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static String? _resolveExistingTodoId(
    Map<String, dynamic> todo,
    Map<String, String> existingTodoTitles,
  ) {
    // Providers sometimes return a generic `id` instead of `todoId`. Accept
    // an explicit alias only when all supplied aliases agree and resolve to a
    // real local todo. Never turn a stale or conflicting ID into a title-based
    // guess, which could make the confirmation card target a different item.
    final suppliedIds = {
      for (final value in [
        todo['todoId'],
        todo['todo_id'],
        todo['todoUuid'],
        todo['id'],
      ])
        if (value?.toString().trim().isNotEmpty == true)
          value.toString().trim(),
    };
    if (suppliedIds.isNotEmpty) {
      if (suppliedIds.length != 1) return null;
      final candidate = suppliedIds.single;
      return existingTodoTitles.containsKey(candidate) ? candidate : null;
    }

    final title = (todo['title'] ?? todo['titleSnapshot'] ?? todo['name'])
        ?.toString()
        .trim();
    if (title == null || title.isEmpty) return null;
    final normalizedTitle = _normalizeTitle(title);
    final matches = existingTodoTitles.entries
        .where((entry) => _normalizeTitle(entry.value) == normalizedTitle)
        .toList();
    // Only infer by title when it is unambiguous. An ambiguous title is safer
    // to discard than to attach a plan block to the wrong occurrence.
    return matches.length == 1 ? matches.single.key : null;
  }

  static String? _existingTodoIdForPlan(
    Map<String, dynamic> todo,
    Map<String, String> existingTodoTitles,
  ) {
    final explicitId = todo['todoId'] ?? todo['todo_id'] ?? todo['todoUuid'];
    final normalizedExplicitId = explicitId?.toString().trim();
    if (normalizedExplicitId != null && normalizedExplicitId.isNotEmpty) {
      return existingTodoTitles.containsKey(normalizedExplicitId)
          ? normalizedExplicitId
          : null;
    }

    final legacyId = todo['id']?.toString().trim();
    if (legacyId != null &&
        legacyId.isNotEmpty &&
        existingTodoTitles.containsKey(legacyId)) {
      return legacyId;
    }

    final title = (todo['title'] ?? todo['titleSnapshot'])?.toString().trim();
    if (title == null || title.isEmpty) return null;
    final normalizedTitle = _normalizeTitle(title);
    final matches = existingTodoTitles.entries
        .where((entry) => _normalizeTitle(entry.value) == normalizedTitle)
        .toList();
    return matches.length == 1 ? matches.single.key : null;
  }

  static String _normalizeTitle(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<Map<String, dynamic>> _listFromOrSelf(
    Map<String, dynamic> self,
    dynamic value,
  ) {
    if (value is Map) {
      return [Map<String, dynamic>.from(value)];
    }
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
    final expectedClosers = <String>[];
    var inString = false;
    var escaped = false;

    for (var i = 0; i < jsonStr.length; i++) {
      final char = jsonStr[i];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        expectedClosers.add('}');
      } else if (char == '[') {
        expectedClosers.add(']');
      } else if (char == '}' || char == ']') {
        if (expectedClosers.isEmpty || expectedClosers.last != char) {
          return jsonStr;
        }
        expectedClosers.removeLast();
      }
    }

    if (inString) return jsonStr;
    return '$jsonStr${expectedClosers.reversed.join()}';
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
      final hasKnownAction = RegExp('"action"\\s*:\\s*"(?:$_actionTypes)"')
          .hasMatch(candidate);
      final hasLegacyContainer = RegExp(
        '"(?:todos|habits|goals|schedules|fixedSchedules|blocks|plans|countdowns|logs|groups|categories|folders|tags)"\\s*:',
      ).hasMatch(candidate);
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
