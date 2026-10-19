import '../models.dart';
import 'ai_todo_context_builder.dart';

class AiNativeToolDefinitionBuilder {
  static const Map<String, dynamic> _nativeCdtRecordProperties = {
    'action': {'type': 'string'},
    'title': {'type': 'string'},
    'teamName': {
      'type': ['string', 'null'],
      'description': '仅用于create_countdown；新建时仅在用户明确要求绑定且本地团队列表唯一匹配后填写规范团队名；重发待确认草案时保留原teamName，除非用户本轮明确更改团队。不要编造团队名或填写团队ID；团队名不得拼入title。',
    },
    'titleSnapshot': {'type': 'string'},
    'name': {'type': 'string'},
    'remark': {
      'type': ['string', 'null'],
      'description': '用户明确说“备注是...”时，将备注内容原样写入此字段；不得改写成截止时间或日期。',
    },
    'date': {
      'type': ['string', 'null'],
      'description': 'yyyy-MM-dd；仅用于日程等对应动作，普通待办请勿使用此旧字段。',
    },
    'location': {
      'type': ['string', 'null'],
    },
    'startTime': {
      'type': ['string', 'null'],
      'description':
          'yyyy-MM-dd HH:mm；仅用于日程、规划块等对应动作。普通待办禁止使用，只使用timeMode和dueDate。',
    },
    'dueDate': {
      'type': ['string', 'null'],
      'description': 'yyyy-MM-dd HH:mm；新建倒计时等记录时仅用户明确要求的截止日期或时间。重发倒计时待确认草案时逐字保留原dueDate，即使本轮只修改标题。用户说“备注是六月”时不要据此填写dueDate。',
    },
    'endTime': {
      'type': ['string', 'null'],
      'description': 'yyyy-MM-dd HH:mm；仅用于日程、规划块等对应动作。普通待办禁止使用。',
    },
    'timeMode': {
      'type': ['string', 'null'],
      'enum': ['unscheduled', 'dateOnly', 'deadline', null],
      'description': '普通待办没有明确完成日期/截止时间时使用unscheduled；备注中的日期或月份不算完成日期。',
    },
    'isAllDay': {'type': 'boolean'},
    'recurrence': {
      'type': 'string',
      'enum': [
        'none',
        'daily',
        'weekly',
        'monthly',
        'yearly',
        'weekdays',
        'customDays',
      ],
    },
    'recurrenceSeriesId': {'type': 'string'},
    'recurrenceScope': {
      'type': 'string',
      'enum': ['occurrence', 'future'],
      'description': '默认 occurrence；仅用户明确要求本期及以后时使用 future。',
    },
    'customIntervalDays': {
      'type': ['integer', 'null'],
    },
    'recurrenceEndDate': {
      'type': ['string', 'null'],
      'description': 'yyyy-MM-dd',
    },
    'todoId': {'type': 'string'},
    'newTodoTitle': {
      'type': 'string',
      'description':
          '规划事项确实没有对应待办时填写待建标题，不填写todoId。用户点击确认卡后由App创建待办并分配真实ID，不能声称已创建。',
    },
    'todo_id': {'type': 'string'},
    'todoUuid': {'type': 'string'},
    'scheduleId': {'type': 'string'},
    'schedule_id': {'type': 'string'},
    'fixedScheduleId': {'type': 'string'},
    'fixed_schedule_id': {'type': 'string'},
    'planBlockId': {'type': 'string'},
    'plan_block_id': {'type': 'string'},
    'blockId': {'type': 'string'},
    'logId': {'type': 'string'},
    'countdownId': {'type': 'string'},
    'tagId': {'type': 'string'},
    'habitUuid': {
      'type': 'string',
      'description': '习惯更新或删除必须使用query_habits返回的真实习惯UUID。',
    },
    'habitId': {'type': 'string'},
    'groupId': {'type': 'string'},
    'id': {'type': 'string'},
    'reminderMinutes': {
      'type': ['integer', 'array', 'null'],
      'items': {'type': 'integer'},
    },
    'reminderMinutesList': {
      'type': 'array',
      'items': {'type': 'integer'},
    },
    'reminders': {
      'type': 'array',
      'items': {'type': 'integer'},
    },
    'durationMinutes': {'type': 'integer'},
    'minutes': {'type': 'integer'},
    'tagUuids': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'tagIds': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'icon': {'type': 'string'},
    'sourceType': {
      'type': 'string',
      'enum': [
        'quantityCheckIn',
        'timeCheckIn',
        'durationCheckIn',
        'pomodoroTag',
        'recurringTodo',
      ],
    },
    'habitSourceType': {'type': 'string'},
    'periodType': {
      'type': 'string',
      'enum': ['daily', 'weekly', 'weekdays', 'monthly', 'custom'],
    },
    'habitPeriodType': {'type': 'string'},
    'targetValue': {'type': 'number'},
    'unit': {'type': 'string'},
    'habitUnit': {'type': 'string'},
    'targetTimeMinute': {'type': 'integer'},
    'targetTime': {'type': 'integer'},
    'timeComparison': {
      'type': 'string',
      'enum': ['before', 'after'],
    },
    'habitTimeComparison': {'type': 'string'},
    'timeToleranceMinutes': {'type': 'integer'},
    'weekdaysMask': {'type': 'integer'},
    'dayBoundaryMinute': {'type': 'integer'},
    'quickValues': {
      'type': 'array',
      'items': {'type': 'integer'},
    },
    'reminderPolicy': {
      'type': 'object',
      'properties': {
        'fixedTimes': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
        'progressReminder': {'type': 'boolean'},
        'nearEndReminder': {'type': 'boolean'},
        'dailySummaryReminder': {'type': 'boolean'},
      },
      'additionalProperties': false,
    },
    'habitReminderPolicy': {'type': 'object'},
    'displayMode': {
      'type': 'string',
      'enum': ['habitOnly', 'todoOnly', 'both'],
    },
    'habitDisplayMode': {'type': 'string'},
    'defaultFocusMinutes': {'type': 'integer'},
    'effectiveFromOption': {
      'type': 'string',
      'enum': ['today', 'nextPeriod', 'all'],
      'description': '规则修改默认today；仅用户明确要求下周期或全部历史时使用nextPeriod或all。',
    },
    'sourceIds': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'sourceTodoId': {'type': 'string'},
    'sourceTodoIds': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'todoIds': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'deleteSource': {'type': 'boolean'},
    'deleteSources': {'type': 'boolean'},
    'deleteSourceTodos': {'type': 'boolean'},
    'status': {'type': 'string'},
    'color': {'type': 'string'},
  };

  static Map<String, dynamic> _recordArraySchema({
    List<String> requiredFields = const [],
  }) => {
    'type': 'array',
    'minItems': 1,
    'items': {
      'type': 'object',
      'properties': _nativeCdtRecordProperties,
      if (requiredFields.isNotEmpty) 'required': requiredFields,
      'additionalProperties': false,
    },
  };

  static Set<String> allowedToolNames(List<Map<String, dynamic>>? tools) => {
    for (final tool in tools ?? const <Map<String, dynamic>>[])
      if (tool['function'] is Map)
        (tool['function'] as Map)['name']?.toString() ?? '',
  }..remove('');

  static Set<String> allowedCdtActionNames(List<Map<String, dynamic>>? tools) =>
      _actionEnumForTool(tools, 'propose_cdt_actions');

  static Set<String> allowedFinanceActionNames(
    List<Map<String, dynamic>>? tools,
  ) => _actionEnumForTool(tools, 'propose_finance_actions');

  static Set<String> _actionEnumForTool(
    List<Map<String, dynamic>>? tools,
    String name,
  ) {
    for (final tool in tools ?? const <Map<String, dynamic>>[]) {
      final function = tool['function'];
      if (function is! Map || function['name'] != name) continue;
      final parameters = function['parameters'];
      if (parameters is! Map) return const {};
      final properties = parameters['properties'];
      if (properties is! Map) return const {};
      final actions = properties['actions'];
      if (actions is! Map) return const {};
      final items = actions['items'];
      if (items is! Map) return const {};
      final itemProperties = items['properties'];
      if (itemProperties is! Map) return const {};
      final action = itemProperties['action'];
      if (action is! Map || action['enum'] is! List) return const {};
      return (action['enum'] as List).map((value) => value.toString()).toSet();
    }
    return const {};
  }

  static const List<String> _nativeCdtArrayFields = [
    'todos',
    'updates',
    'schedules',
    'blocks',
    'logs',
    'habits',
    'countdowns',
    'groups',
    'tags',
  ];

  static const Set<String> _todoRecurrenceScopeActions = {
    'update_todo',
    'complete_todo',
    'delete_todo',
    'reschedule_todo',
    'bulk_reschedule',
    'categorize_todo',
  };

  static const Set<String> _todoUpdateContainerActions = {
    'update_todo',
    'complete_todo',
    'delete_todo',
    'reschedule_todo',
    'bulk_reschedule',
    'categorize_todo',
  };

  static const Set<String> _todoScopedActionNames = {
    'create_todo',
    ..._todoUpdateContainerActions,
    'split_todo',
    'merge_todos',
    'create_plan_block',
  };

  static const Set<String> _updatesContainerActions = {
    ..._todoUpdateContainerActions,
    'update_schedule',
    'cancel_schedule',
    'delete_schedule',
    'update_plan_block',
    'reschedule_plan_blocks',
    'delete_plan_block',
    'skip_plan_block',
    'start_plan_block_pomodoro',
    'update_time_log',
    'delete_time_log',
    'update_countdown',
    'complete_countdown',
    'delete_countdown',
    'update_todo_group',
    'delete_todo_group',
    'update_pomodoro_tag',
    'delete_pomodoro_tag',
    'update_habit',
    'delete_habit',
  };

  static const Map<String, Set<String>> _nativeCdtArrayActionNames = {
    'todos': {'create_todo', 'split_todo'},
    'updates': _updatesContainerActions,
    'schedules': {'create_schedule'},
    'blocks': {'create_plan_block'},
    'logs': {'create_time_log'},
    'habits': {'create_habit'},
    'countdowns': {'create_countdown'},
    'groups': {'create_todo_group'},
    'tags': {'create_pomodoro_tag'},
  };

  static String? _requiredArrayFieldForSingleAction(Set<String> actions) {
    if (actions.length != 1) return null;
    final action = actions.single;
    for (final entry in _nativeCdtArrayActionNames.entries) {
      if (entry.value.contains(action)) return entry.key;
    }
    return null;
  }

  /// Keep risky actions out of the function schema unless the user explicitly
  /// asks for that operation in this turn. Confirmation cards remain the
  /// second safety barrier after model output is parsed.
  static const Map<String, List<String>> _explicitCdtActionTriggers = {
    'complete_todo': AiTodoContextBuilder.todoCompletionMutationKeywords,
    'delete_todo': ['删除', '删掉', '删了', '删', '移除', '清空', '清掉', '清除', '去掉', '取消'],
    'cancel_schedule': ['取消', '撤销'],
    'delete_schedule': ['删除', '删掉', '删', '移除', '清掉'],
    'update_plan_block': ['修改', '更新', '更改', '调整'],
    'reschedule_plan_blocks': ['改期', '重排', '重新安排', '改到', '改成', '调整时间', '改时间'],
    'delete_plan_block': ['删除', '删掉', '删', '移除', '清掉', '取消'],
    'skip_plan_block': ['跳过', '略过'],
    'start_plan_block_pomodoro': ['开始', '启动'],
    'delete_time_log': ['删除', '删掉', '删', '移除', '清掉'],
    'create_todo_group': [
      '创建',
      '新建',
      '新增',
      '添加',
      '建立',
      '建个',
      '建一个',
      '加个',
      '加一个',
      '设个',
      '设一个',
    ],
    'update_todo_group': ['修改', '更新', '更名', '改名', '重命名'],
    'delete_todo_group': ['删除', '删掉', '删一下', '删', '移除', '清掉'],
    'stop_pomodoro': ['停止番茄钟', '停止专注', '结束番茄钟', '结束专注'],
    'update_countdown': [
      '修改倒计时',
      '更新倒计时',
      '更改倒计时',
      '调整倒计时',
      '改到',
      '改成',
      '改为',
      '挪到',
      '移到',
      '移动到',
    ],
    'complete_countdown': ['完成倒计时', '办完倒计时', '标记完成', '做完倒计时'],
    'delete_countdown': ['删除倒计时', '取消倒计时', '删除', '删掉', '删', '移除', '清掉'],
    'create_pomodoro_tag': [
      '创建',
      '新建',
      '新增',
      '添加',
      '建立',
      '建个',
      '建一个',
      '加个',
      '加一个',
      '设个',
      '设一个',
    ],
    'update_pomodoro_tag': ['修改', '更新', '更名', '改名', '重命名'],
    'split_todo': ['拆分待办', '拆分任务', '拆分'],
    'merge_todos': ['合并待办', '合并任务', '合并'],
    'delete_pomodoro_tag': ['删除', '删掉', '删一下', '删', '移除', '清掉'],
    'update_habit': ['修改', '更新', '调整', '改成', '改为', '改名', '重命名'],
    'delete_habit': ['删除', '删掉', '删', '移除', '清除', '清空'],
  };

  /// Builds OpenAI-compatible function tools for the actions relevant to one
  /// user request. The returned calls are proposals consumed by the existing
  /// confirmation UI; they are not executed against storage here.
  static List<Map<String, dynamic>> buildNativeToolDefinitions(
    String userMessage, {
    String previousUserMessage = '',
    String previousAssistantMessage = '',
    List<Team> availableTeams = const [],
  }) {
    // A short assent can continue a planning discussion. Keep this scoped to
    // planning; it must not reactivate old delete/complete requests.
    final resolvedMessage = resolvePlanningRequest(
      userMessage,
      previousUserMessage: previousUserMessage,
      previousAssistantMessage: previousAssistantMessage,
    );
    if (resolvedMessage.isEmpty) return const [];
    final financeClarifiedMessage = _inheritFinanceWriteClarification(
      resolvedMessage,
      previousUserMessage: previousUserMessage,
      previousAssistantMessage: previousAssistantMessage,
    );
    final message = AiTodoContextBuilder.inheritExplicitCreationClarification(
      financeClarifiedMessage,
      previousUserMessage: previousUserMessage,
      previousAssistantMessage: previousAssistantMessage,
    );

    final actionPrompt = AiTodoContextBuilder.buildActionProtocolPrompt(
      message,
      previousUserMessage: previousUserMessage,
      previousAssistantMessage: previousAssistantMessage,
      availableTeams: availableTeams,
    );
    final actionSectionEnd = actionPrompt.indexOf('动作块格式');
    final actionSection = actionSectionEnd == -1
        ? actionPrompt
        : actionPrompt.substring(0, actionSectionEnd);
    final isOnlyInformation =
        actionSection.contains('本轮不生成结构化操作') ||
        actionSection.contains('本轮是习惯信息咨询') ||
        actionSection.contains('创建类型不明确');
    final isGenericFallback = actionSection.contains(
      '- create_todo / update_todo / complete_todo / delete_todo',
    );
    final readOnlyWords = [
      '有哪些',
      '有什么',
      '查看',
      '列出',
      '查询',
      '统计',
      '汇总',
      '分析',
      '排行',
      '占比',
      '多少',
      '明细',
      '影响',
      '效果',
      '情况',
      '记录',
      '结果',
      '趋势',
      '建议',
      '是否',
      '有没有',
      '今天什么',
      '明天什么',
    ];
    final writeWords = [
      ..._createTodoKeywords,
      ..._existingTodoKeywords,
      ...AiTodoContextBuilder.todoListMutationKeywords,
      ...AiTodoContextBuilder.focusMutationKeywords,
      '取消',
      '移除',
      '停止',
      '开始',
      '补记',
      '删掉',
      '清空',
      '加入',
      '安排到',
    ];
    final isReadOnlyQuery =
        _matchesAny(message, readOnlyWords) &&
        !AiTodoContextBuilder.isExplicitTodoCreationRequest(message) &&
        !AiTodoContextBuilder.isExplicitHabitCreationRequest(message) &&
        !AiTodoContextBuilder.isExplicitHabitMutationRequest(message) &&
        !AiTodoContextBuilder.isExplicitScheduleMutationRequest(message) &&
        !AiTodoContextBuilder.isExplicitCountdownMutationRequest(message) &&
        !_matchesAny(message, writeWords) &&
        !AiTodoContextBuilder.isExplicitFocusMutationRequest(message) &&
        !AiTodoContextBuilder.isExplicitFinanceDraftRequest(message) &&
        !AiTodoContextBuilder.hasExplicitFinanceUpdateIntent(message);
    final hasNoPositiveWriteIntent =
        _matchesAny(message, writeWords) &&
        !AiTodoContextBuilder.isExplicitTodoCreationRequest(message) &&
        !writeWords.any(
          (word) => AiTodoContextBuilder.isExplicitlyRequested(message, word),
        );
    final isTodoCategorizationRequest =
        _matchesAny(message, ['分类', '归类', '分组', '分个类', '移出文件夹']) &&
        _matchesAny(message, ['待办', '任务']) &&
        !AiTodoContextBuilder.isExplicitTodoGroupManagementRequest(message) &&
        !_matchesAny(message, [
          '有哪些',
          '哪些',
          '查看',
          '列出',
          '查询',
          '统计',
          '新增分类',
          '新建分类',
          '创建分类',
          '添加分类',
          '修改分类',
          '删除分类',
          '删除文件夹',
        ]);

    final countdownOnlyMutationRequest =
        AiTodoContextBuilder.isExplicitCountdownMutationRequest(message) &&
        !AiTodoContextBuilder.isExplicitlyTargetingTodo(message);
    final protocolActionNames = _extractProtocolActionNames(actionSection)
        .where((action) {
          if (countdownOnlyMutationRequest &&
              _todoScopedActionNames.contains(action)) {
            return false;
          }
          final triggers = _explicitCdtActionTriggers[action];
          return triggers == null ||
              triggers.any(
                (trigger) => AiTodoContextBuilder.isExplicitlyRequested(
                  message,
                  trigger,
                ),
              );
        })
        .toSet();
    final availableActions =
        isOnlyInformation ||
            isGenericFallback ||
            isReadOnlyQuery ||
            hasNoPositiveWriteIntent
        ? <String>[]
        : isTodoCategorizationRequest &&
              protocolActionNames.contains('categorize_todo')
        ? const ['categorize_todo']
        : _nativeCdtActionNames
              .where(protocolActionNames.contains)
              .toList(growable: false);
    final includeTodoRecurrenceRules = availableActions.any(
      _todoRecurrenceScopeActions.contains,
    );
    final availableUpdateActions = availableActions
        .where(_updatesContainerActions.contains)
        .toSet();
    final updatesContainOnlyTodoMutations =
        availableUpdateActions.isNotEmpty &&
        availableUpdateActions.every(_todoUpdateContainerActions.contains);
    final updatesContainOnlyHabitMutations =
        availableUpdateActions.isNotEmpty &&
        availableUpdateActions.every(
          (action) => action == 'update_habit' || action == 'delete_habit',
        );
    final updatesContainOnlyCountdownMutations =
        availableUpdateActions.isNotEmpty &&
        availableUpdateActions.every(
          (action) =>
              action == 'update_countdown' ||
              action == 'complete_countdown' ||
              action == 'delete_countdown',
        );
    final requiredArrayField = _requiredArrayFieldForSingleAction(
      availableActions.toSet(),
    );
    final actionProperties = isTodoCategorizationRequest
        ? <String, dynamic>{
            'action': {
              'type': 'string',
              'enum': const ['categorize_todo'],
            },
            'updates': {
              'type': 'array',
              'minItems': 1,
              'items': {
                'type': 'object',
                'properties': {
                  'todoId': {
                    'type': 'string',
                    'description': '逐字使用待办上下文中的真实期次todoId',
                  },
                  'groupId': {
                    'type': ['string', 'null'],
                    'description': '逐字使用待办上下文中的真实分类ID；用户要求移出分类时填写null',
                  },
                },
                'required': const ['todoId', 'groupId'],
                'additionalProperties': false,
              },
            },
          }
        : <String, dynamic>{
            'action': {'type': 'string', 'enum': availableActions},
            for (final field in _nativeCdtArrayFields)
              if (_nativeCdtArrayActionNames[field]?.any(
                    availableActions.contains,
                  ) ??
                  false)
                field: _recordArraySchema(
                  requiredFields: field == 'todos'
                      ? const ['title']
                      : field == 'schedules'
                      ? const ['title', 'date']
                      : field == 'logs'
                      ? const ['title', 'startTime']
                      : field == 'habits'
                      ? const ['name', 'sourceType', 'periodType']
                      : field == 'countdowns'
                      ? const ['title', 'dueDate']
                      : field == 'updates' &&
                            updatesContainOnlyCountdownMutations
                      ? const ['countdownId']
                      : field == 'groups' || field == 'tags'
                      ? const ['name']
                      : field == 'updates' && updatesContainOnlyTodoMutations
                      ? const ['todoId']
                      : field == 'updates' && updatesContainOnlyHabitMutations
                      ? const ['habitUuid', 'title']
                      : const [],
                ),
            'title': {'type': 'string'},
            'todoId': {'type': 'string'},
            'durationMinutes': {'type': 'integer'},
            'tagUuids': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'status': {'type': 'string'},
            'sourceTodoId': {'type': 'string'},
            'source_id': {'type': 'string'},
            'sourceTodoIds': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'todoIds': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'todo': {
              'type': 'object',
              'properties': _nativeCdtRecordProperties,
              'additionalProperties': false,
            },
            'deleteSource': {'type': 'boolean'},
            'deleteSources': {'type': 'boolean'},
            'deleteSourceTodos': {'type': 'boolean'},
          };
    final tools = <Map<String, dynamic>>[];

    if (availableActions.isNotEmpty) {
      final applicableLines = actionSection
          .split('\n')
          .where((line) {
            final lineActionNames = _extractProtocolActionNames(line);
            final isTodoRecurrenceRule =
                includeTodoRecurrenceRules &&
                line.trim().startsWith('- 循环作用域:');
            return (availableActions.any(lineActionNames.contains) ||
                    isTodoRecurrenceRule) &&
                !line.contains('格式（CDT Actions');
          })
          .toSet()
          .join('\n');
      tools.add({
        'type': 'function',
        'function': {
          'name': 'propose_cdt_actions',
          'description':
              '根据用户明确请求提交一组待确认的 CDT 操作草案。调用只会生成确认卡，不会直接保存、删除或完成数据。只使用本轮列出的动作和字段规则；已有对象必须使用真实 ID。\n$applicableLines',
          'parameters': {
            'type': 'object',
            'properties': {
              'actions': {
                'type': 'array',
                'minItems': 1,
                'items': {
                  'type': 'object',
                  'properties': actionProperties,
                  'required': isTodoCategorizationRequest
                      ? ['action', 'updates']
                      : ['action', ?requiredArrayField],
                  'additionalProperties': false,
                },
              },
            },
            'required': ['actions'],
            'additionalProperties': false,
          },
        },
      });
    }

    final financeUpdateVerbs = [
      '修改',
      '更新',
      '更正',
      '编辑',
      '调整',
      '更改',
      '改成',
      '改为',
      '调成',
      '调为',
    ];
    final financeDeleteVerbs = [
      '删除',
      '删除掉',
      '删掉',
      '删掉了',
      '删了',
      '清掉',
      '移除',
      '去掉',
      '清除',
      '撤销',
      '取消',
    ];
    final protocolFinanceActionNames = _extractProtocolActionNames(
      actionSection,
    );
    final hasFinanceMutationProtocol =
        protocolFinanceActionNames.contains('update_finance') ||
        protocolFinanceActionNames.contains('delete_finance');
    final wantsFinanceUpdate =
        !isReadOnlyQuery &&
        hasFinanceMutationProtocol &&
        financeUpdateVerbs.any(
          (verb) => AiTodoContextBuilder.isExplicitlyRequested(message, verb),
        );
    final wantsFinanceDelete =
        !isReadOnlyQuery &&
        hasFinanceMutationProtocol &&
        financeDeleteVerbs.any(
          (verb) => AiTodoContextBuilder.isExplicitlyRequested(message, verb),
        );
    final wantsFinanceMutation = wantsFinanceUpdate || wantsFinanceDelete;
    const financeDraftTriggers = [
      '记一笔',
      '记录一笔',
      '新增一笔',
      '添加一笔',
      '消费了',
      '花了',
      '花费',
      '买了',
      '购买',
      '进账',
      '收款',
      '记账草案',
    ];
    final explicitlyWantsFinanceDraft = financeDraftTriggers.any(
      (trigger) => AiTodoContextBuilder.isExplicitlyRequested(message, trigger),
    );
    final hasOnlyNegatedFinanceDraftIntent =
        _matchesAny(message, financeDraftTriggers) &&
        !explicitlyWantsFinanceDraft;
    final financeDraftIntent =
        AiTodoContextBuilder.shouldOfferFinanceDraftProposal(message);
    final hasExplicitFinanceDraftIntent =
        explicitlyWantsFinanceDraft ||
        AiTodoContextBuilder.isExplicitFinanceDraftRequest(message);
    final wantsFinanceDraft =
        !isReadOnlyQuery &&
        !hasOnlyNegatedFinanceDraftIntent &&
        financeDraftIntent &&
        (!wantsFinanceMutation || hasExplicitFinanceDraftIntent);

    if (wantsFinanceDraft) {
      tools.add({
        'type': 'function',
        'function': {
          'name': 'propose_finance_drafts',
          'description': '识别新增支出、收入或退款并提交待确认草案。amount 单位为元；需要精确保存到分时使用 amount_minor 字符串，单位为人民币分，且优先于 amount。应用会显示“待确认记账”卡片，用户需点击“编辑并保存”后才会写入账本。聊天中的“确认/确定”不会保存账单，不得声称已保存。分类和付款方式 UUID 只能使用本轮记账上下文中的真实值。',
          'parameters': {
            'type': 'object',
            'properties': {
              'drafts': {
                'type': 'array',
                'minItems': 1,
                'items': {
                  'type': 'object',
                  'properties': {
                    'type': {
                      'type': 'string',
                      'enum': ['expense', 'income', 'refund'],
                    },
                    'amount': {'type': 'number'},
                    'amount_minor': {
                      'type': 'string',
                      'description': '金额的人民币分，用十进制整数文本表示；精确到分时使用，优先于 amount。',
                    },
                    'category': {
                      'type': ['string', 'null'],
                    },
                    'categoryUuid': {
                      'type': ['string', 'null'],
                    },
                    'merchant': {
                      'type': ['string', 'null'],
                    },
                    'date': {'type': 'string', 'description': 'yyyy-MM-dd'},
                    'paymentMethod': {
                      'type': ['string', 'null'],
                    },
                    'paymentMethodUuid': {
                      'type': ['string', 'null'],
                    },
                    'note': {
                      'type': ['string', 'null'],
                    },
                  },
                  'required': ['type', 'amount', 'date'],
                  'additionalProperties': false,
                },
              },
            },
            'required': ['drafts'],
            'additionalProperties': false,
          },
        },
      });
    }

    if (wantsFinanceMutation) {
      final availableFinanceActions = [
        if (wantsFinanceUpdate) 'update_finance',
        if (wantsFinanceDelete) 'delete_finance',
      ];
      tools.add({
        'type': 'function',
        'function': {
          'name': 'propose_finance_actions',
          'description': '提交已有账单的修改或删除草案，等待用户在确认卡中操作；不要直接保存或删除。transactionId 必须来自本轮记账上下文，找不到唯一记录时先追问。amount 单位为元；需要精确保存到分时使用 amount_minor 字符串，单位为人民币分，且优先于 amount。',
          'parameters': {
            'type': 'object',
            'properties': {
              'actions': {
                'type': 'array',
                'minItems': 1,
                'items': {
                  'type': 'object',
                  'properties': {
                    'action': {
                      'type': 'string',
                      'enum': availableFinanceActions,
                    },
                    'transactionId': {'type': 'string'},
                    'reason': {
                      'type': ['string', 'null'],
                    },
                    'type': {
                      'type': 'string',
                      'enum': ['expense', 'income', 'refund'],
                    },
                    'amount': {'type': 'number'},
                    'amount_minor': {
                      'type': 'string',
                      'description': '金额的人民币分，用十进制整数文本表示；精确到分时使用，优先于 amount。',
                    },
                    'category': {
                      'type': ['string', 'null'],
                    },
                    'categoryUuid': {
                      'type': ['string', 'null'],
                    },
                    'merchant': {
                      'type': ['string', 'null'],
                    },
                    'date': {
                      'type': ['string', 'null'],
                      'description': 'yyyy-MM-dd',
                    },
                    'paymentMethod': {
                      'type': ['string', 'null'],
                    },
                    'paymentMethodUuid': {
                      'type': ['string', 'null'],
                    },
                    'note': {
                      'type': ['string', 'null'],
                    },
                  },
                  'required': ['action', 'transactionId'],
                  'additionalProperties': false,
                },
              },
            },
            'required': ['actions'],
            'additionalProperties': false,
          },
        },
      });
    }

    return tools;
  }

  static bool isMissingActionCardReport(String text) {
    const card = r'(?:操作块|规划块|操作卡(?:片)?|卡片)';
    const missing = r'(?:没|未|找不到|看不到|不显示|不见|在哪|哪里)';
    return RegExp('$missing.*$card|$card.*$missing').hasMatch(text);
  }

  static String resolvePlanningRequest(
    String userMessage, {
    String previousUserMessage = '',
    String previousAssistantMessage = '',
  }) {
    final message = userMessage.trim();
    final isAssent = RegExp(
      r'^(?:可以|好|好的|好啊|行|嗯|嗯嗯|确认|确定|继续|开始吧|生成吧|要的|需要|是的|就这样|按这个来|照这个安排)[！!。\.\s]*$',
    ).hasMatch(message);
    final planning = RegExp(r'规划|计划块|时间块|plan\s*block', caseSensitive: false);
    if (planning.hasMatch(message) && !isMissingActionCardReport(message)) {
      return message;
    }
    final isPlanningDetail =
        RegExp(r'^(?:避开|排除|到|截止|截至|从|可以联排|联排|连排|先|把|加上|也加|不要安排)')
            .hasMatch(message) &&
        RegExp(r'时间|晚餐|午餐|点|时|分钟|联排|连排|问卷|加上').hasMatch(message);
    final isSchedulingRequest = RegExp(r'(?:我要|帮我|请).*(?:安排|排一下)')
        .hasMatch(message);
    final isTaskDescription = RegExp(r'我(?:打算|准备|想|要).*(?:做|学|复习|安排)')
        .hasMatch(message);
    if (!isAssent &&
        !isPlanningDetail &&
        !isSchedulingRequest &&
        !isTaskDescription &&
        !isMissingActionCardReport(message)) {
      return message;
    }
    final previousPlanningRequest =
        planning.hasMatch(previousUserMessage) &&
        allowedCdtActionNames(buildNativeToolDefinitions(previousUserMessage))
            .contains('create_plan_block');
    final offeredPlanning =
        planning.hasMatch(previousAssistantMessage) &&
        RegExp(r'方案|草案|时段|生成|安排|要不要|是否需要|需要我')
            .hasMatch(previousAssistantMessage);
    if (!previousPlanningRequest && !offeredPlanning) {
      return message;
    }
    return '请按刚才讨论的方案生成规划块';
  }

  static String _inheritFinanceWriteClarification(
    String userMessage, {
    required String previousUserMessage,
    required String previousAssistantMessage,
  }) {
    if (AiTodoContextBuilder.isExplicitOperationDecline(userMessage)) {
      return userMessage;
    }
    final previousRequest = previousUserMessage.trim();
    final assistantReply = previousAssistantMessage.trim();
    if (previousRequest.isEmpty || assistantReply.isEmpty) return userMessage;
    if (_matchesAny(userMessage, const [
      '查看',
      '查询',
      '列出',
      '有哪些',
      '有什么',
      '分析',
      '统计',
      '汇总',
      '多少',
      '明细',
      '趋势',
      '情况',
      '是否',
      '有没有',
      '怎么',
      '为什么',
      '？',
      '?',
    ])) {
      return userMessage;
    }
    final confirmation = userMessage.trim().replaceAll(
      RegExp(r'[\s，。！？,.!?]'),
      '',
    );
    if (const {
      '好',
      '好的',
      '可以',
      '行',
      '确认',
      '确定',
      '继续',
      '是的',
    }.contains(confirmation)) {
      return userMessage;
    }
    if (RegExp(r'待确认|确认卡|编辑并保存|已经生成.{0,8}(?:账单|记账)').hasMatch(assistantReply)) {
      return userMessage;
    }

    final isFinanceWriteRequest =
        AiTodoContextBuilder.isExplicitFinanceDraftRequest(previousRequest) ||
        AiTodoContextBuilder.hasExplicitFinanceUpdateIntent(previousRequest);
    final assistantRequestsDetails = RegExp(
      r'请提供|请补充|请告诉|告诉我|还需要|还差|缺少|哪一笔|哪一个|哪天|哪一天|什么时间|多少元|具体.{0,12}(?:金额|日期|账单|分类|商家|支付方式)',
    ).hasMatch(assistantReply);
    if (!isFinanceWriteRequest || !assistantRequestsDetails) return userMessage;

    return '$previousRequest\n$userMessage';
  }

  static const List<String> _nativeCdtActionNames = [
    'create_todo',
    'update_todo',
    'complete_todo',
    'delete_todo',
    'reschedule_todo',
    'bulk_reschedule',
    'categorize_todo',
    'split_todo',
    'merge_todos',
    'create_habit',
    'update_habit',
    'delete_habit',
    'create_schedule',
    'update_schedule',
    'cancel_schedule',
    'delete_schedule',
    'create_plan_block',
    'update_plan_block',
    'reschedule_plan_blocks',
    'delete_plan_block',
    'skip_plan_block',
    'start_plan_block_pomodoro',
    'create_time_log',
    'update_time_log',
    'delete_time_log',
    'start_pomodoro',
    'stop_pomodoro',
    'create_countdown',
    'update_countdown',
    'complete_countdown',
    'delete_countdown',
    'create_todo_group',
    'update_todo_group',
    'delete_todo_group',
    'create_pomodoro_tag',
    'update_pomodoro_tag',
    'delete_pomodoro_tag',
  ];

  static Set<String> _extractProtocolActionNames(String text) {
    final actions = <String>{};
    for (final line in text.split('\n')) {
      final bullet = line.trim();
      if (!bullet.startsWith('- ')) continue;
      final actionLabel = bullet.substring(2).split(RegExp(r'[:：]')).first;
      actions.addAll(
        RegExp(r'[A-Za-z_][A-Za-z0-9_]*')
            .allMatches(actionLabel)
            .map((match) => match.group(0)!),
      );
    }
    return actions;
  }

  static const _createTodoKeywords = [
    '提醒我',
    '记得',
    '新建',
    '新增',
    '创建',
    '添加',
    '加个',
    '加一个',
    '加条',
    '加一条',
    '加几条',
    '设个',
    '设一个',
  ];
  static const _existingTodoKeywords = [
    '修改',
    '更新',
    '完成',
    '删除',
    '删',
    '延期',
    '改期',
    '分类',
    '归类',
    '分个类',
    '移出文件夹',
    '拆分',
    '合并',
    '重排',
    '重计划',
    '规划',
    '这个待办',
    '该待办',
    '把待办',
  ];

  static bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword));
  }
}
