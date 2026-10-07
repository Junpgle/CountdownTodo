import 'ai_todo_context_builder.dart';

class AiNativeToolDefinitionBuilder {
  static const Map<String, dynamic> _nativeCdtRecordProperties = {
    'action': {'type': 'string'},
    'title': {'type': 'string'},
    'titleSnapshot': {'type': 'string'},
    'name': {'type': 'string'},
    'remark': {
      'type': ['string', 'null'],
    },
    'date': {
      'type': ['string', 'null'],
      'description': 'yyyy-MM-dd',
    },
    'location': {
      'type': ['string', 'null'],
    },
    'startTime': {
      'type': ['string', 'null'],
      'description': 'yyyy-MM-dd HH:mm',
    },
    'dueDate': {
      'type': ['string', 'null'],
      'description': 'yyyy-MM-dd HH:mm',
    },
    'endTime': {
      'type': ['string', 'null'],
      'description': 'yyyy-MM-dd HH:mm',
    },
    'timeMode': {
      'type': ['string', 'null'],
      'enum': ['unscheduled', 'dateOnly', 'deadline', null],
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
  };

  /// Keep risky actions out of the function schema unless the user explicitly
  /// asks for that operation in this turn. Confirmation cards remain the
  /// second safety barrier after model output is parsed.
  static const Map<String, List<String>> _explicitCdtActionTriggers = {
    'complete_todo': ['完成', '做完', '办完', '勾选', '打钩'],
    'delete_todo': ['删除', '删掉', '删了', '移除', '清空', '取消'],
    'cancel_schedule': ['取消', '撤销'],
    'delete_schedule': ['删除', '删掉', '移除'],
    'delete_plan_block': ['删除', '删掉', '移除'],
    'skip_plan_block': ['跳过', '略过'],
    'delete_time_log': ['删除', '删掉', '移除'],
    'stop_pomodoro': ['停止番茄钟', '停止专注', '结束番茄钟', '结束专注'],
    'complete_countdown': ['完成倒计时'],
    'delete_countdown': ['删除倒计时', '删除', '删掉', '移除'],
    'split_todo': ['拆分待办', '拆分任务', '拆分'],
    'merge_todos': ['合并待办', '合并任务', '合并'],
    'delete_todo_group': ['删除分类', '删除分组', '删除文件夹'],
    'delete_pomodoro_tag': ['删除番茄标签', '删除标签'],
  };

  /// Builds OpenAI-compatible function tools for the actions relevant to one
  /// user request. The returned calls are proposals consumed by the existing
  /// confirmation UI; they are not executed against storage here.
  static List<Map<String, dynamic>> buildNativeToolDefinitions(
    String userMessage, {
    String previousUserMessage = '',
  }) {
    final message = userMessage.trim();
    if (message.isEmpty) return const [];

    final actionPrompt = AiTodoContextBuilder.buildActionProtocolPrompt(
      message,
      previousUserMessage: previousUserMessage,
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
      '取消',
      '移除',
      '停止',
      '开始',
      '补记',
      '改成',
      '改为',
      '删掉',
      '清空',
      '加入',
      '安排到',
    ];
    final isReadOnlyQuery =
        _matchesAny(message, readOnlyWords) &&
        !_matchesAny(message, writeWords) &&
        !AiTodoContextBuilder.hasExplicitFinanceUpdateIntent(message);
    final hasNoPositiveWriteIntent =
        _matchesAny(message, writeWords) &&
        !writeWords.any(
          (word) => AiTodoContextBuilder.isExplicitlyRequested(message, word),
        );
    final isTodoCategorizationRequest =
        _matchesAny(message, ['分类', '归类', '分组', '分个类']) &&
        _matchesAny(message, ['待办', '任务']) &&
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

    final protocolActionNames = _extractProtocolActionNames(actionSection)
        .where((action) {
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
              field: _recordArraySchema(
                requiredFields:
                    field == 'updates' && updatesContainOnlyTodoMutations
                    ? const ['todoId']
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
                      : ['action'],
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

    final hasFinanceAmount = RegExp(r'\d+(?:\.\d+)?\s*(?:元|块(?:钱)?|人民币|¥|￥)')
        .hasMatch(message);
    final financeUpdateVerbs = ['修改', '更新', '更正', '调整', '改成', '改为'];
    final financeDeleteVerbs = [
      '删除',
      '删除掉',
      '删掉',
      '删掉了',
      '删了',
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
    final wantsFinanceDraft =
        !isReadOnlyQuery &&
        !hasOnlyNegatedFinanceDraftIntent &&
        (explicitlyWantsFinanceDraft ||
            (hasFinanceAmount && !wantsFinanceMutation));

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

  static const _createTodoKeywords = ['提醒我', '记得', '新建', '新增', '创建', '添加'];
  static const _existingTodoKeywords = [
    '修改',
    '更新',
    '完成',
    '删除',
    '延期',
    '改期',
    '分类',
    '归类',
    '分个类',
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
