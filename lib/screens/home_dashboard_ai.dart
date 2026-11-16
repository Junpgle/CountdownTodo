part of 'home_dashboard.dart';

// ignore_for_file: annotate_overrides

mixin _HomeDashboardAiMixin on _HomeDashboardStateBase {
  bool _openingQuickVoice = false;
  QuickVoiceGestureController? _quickVoiceGesture;

  void _startQuickVoiceGesture(LongPressStartDetails details) {
    if (_openingQuickVoice) return;
    final gesture = QuickVoiceGestureController(details.globalPosition);
    _quickVoiceGesture = gesture;
    unawaited(_openQuickVoiceChat(gesture: gesture));
  }

  void _moveQuickVoiceGesture(LongPressMoveUpdateDetails details) =>
      _quickVoiceGesture?.move(details.globalPosition);

  void _endQuickVoiceGesture(LongPressEndDetails details) {
    _quickVoiceGesture?.move(details.globalPosition);
    _quickVoiceGesture?.release();
  }

  void _cancelQuickVoiceGesture() => _quickVoiceGesture?.release(cancel: true);

  Future<void> _openQuickVoiceChat({
    QuickVoiceGestureController? gesture,
  }) async {
    if (_openingQuickVoice) return;
    _openingQuickVoice = true;
    try {
      final chatConfig = await ChatStorageService.getChatConfig();
      final config = await LLMService.getConfig();
      final hasChatApi =
          ((chatConfig?['model']?.trim().isNotEmpty ?? false) &&
              (chatConfig?['apiKey']?.trim().isNotEmpty ?? false)) ||
          (config?.isConfigured ?? false);
      final asrKey = await MimoAsrService.resolveApiKey(chatConfig: chatConfig);
      if (!mounted) return;
      if (!hasChatApi || asrKey.isEmpty) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text(
              !hasChatApi
                  ? '请先配置 AI 对话模型和 API Key'
                  : '语音识别需要普通小米 MiMo API Key，请在“模型与 API 配置”中填写',
            ),
            action: SnackBarAction(
              label: '配置',
              onPressed: () {
                Navigator.push(
                  context,
                  PageTransitions.material(
                    builder: (_) => const LLMConfigPage(),
                  ),
                );
              },
            ),
          ),
        );
        return;
      }
      if (!await MinorModeService.instance.authorizeAiInteraction()) {
        if (mounted) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(content: Text('当前未成年人模式暂不允许使用 AI 功能')),
          );
        }
        return;
      }
      if (!mounted) return;
      if (gesture?.isReleased ?? false) return;
      unawaited(HapticFeedback.mediumImpact());
      ChatUsageSummary? voiceUsage;
      String? text;
      var sendImmediately = true;
      if (gesture != null) {
        final result = await showHeldQuickVoiceChat(
          context: context,
          apiKey: asrKey,
          gesture: gesture,
          sourceKey: _homeAddActionKey,
        );
        text = result?.text;
        voiceUsage = result?.usageSummary;
        sendImmediately = result?.sendImmediately ?? true;
      } else {
        text = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (_) => QuickVoiceChatSheet(
            apiKey: asrKey,
            onUsageSummary: (usage) => voiceUsage = usage,
          ),
        );
      }
      if (!mounted || text == null || text.trim().isEmpty) return;
      await _openAiAssistantFromAppBar(
        sourceKey: _homeAddActionKey,
        initialMessage: text,
        sendInitialMessage: sendImmediately,
        initialVoiceUsageSummary: voiceUsage,
      );
    } catch (_) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('无法打开语音对话，请稍后重试')),
        );
      }
    } finally {
      _openingQuickVoice = false;
      if (identical(_quickVoiceGesture, gesture)) _quickVoiceGesture = null;
      gesture?.dispose();
    }
  }

  Future<void> _openPendingRecognitionChat() async {
    final sessionId = _pendingTodoConfirm?['recognitionChatSessionId']
        ?.toString()
        .trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      await ChatStorageService.setActiveSessionId(sessionId);
      if (!mounted) return;
      await _openAiAssistantFromAppBar(initialSessionId: sessionId);
      return;
    }

    final status = _pendingTodoConfirm?['status']?.toString();
    if (status == 'success') {
      await _openPendingTodoConfirm();
    } else if (status == 'failed') {
      await _retryPendingTodoRecognition();
    } else {
      await _openAiAssistantFromAppBar();
    }
  }

  Future<void> _openAiAssistantFromAppBar({
    GlobalKey? sourceKey,
    String? initialMessage,
    String? initialSessionId,
    bool sendInitialMessage = true,
    ChatUsageSummary? initialVoiceUsageSummary,
  }) async {
    final transitionSourceKey = sourceKey ?? _aiButtonKey;
    final todoState = _todoSectionKey.currentState;
    if (todoState != null) {
      await todoState.openAiAssistant(
        sourceKey: transitionSourceKey,
        initialMessage: initialMessage,
        initialSessionId: initialSessionId,
        sendInitialMessage: sendInitialMessage,
        initialVoiceUsageSummary: initialVoiceUsageSummary,
      );
      return;
    }

    try {
      if (!mounted) return;
      await AiTodoChatLauncher.open(
        context,
        username: widget.username,
        sourceKey: transitionSourceKey,
        initialMessage: initialMessage,
        initialSessionId: initialSessionId,
        sendInitialMessage: sendInitialMessage,
        initialVoiceUsageSummary: initialVoiceUsageSummary,
        todos: _todos
            .where((t) => !t.isDone && !t.isDeleted && !t.isSkipped)
            .toList(),
        todoGroups: _todoGroups,
        conflicts: _latestSyncConflicts,
        fixedSchedules: _fixedSchedules,
        loadCourses: () async {
          final list = await CourseService.getAllCourses(widget.username);
          return list.where((course) => !course.isDeleted).toList();
        },
        loadTimeLogs: () async {
          final list = await StorageService.getTimeLogs(widget.username);
          return list.where((log) => !log.isDeleted).toList();
        },
        loadPomodoroRecords: () async {
          final list = await PomodoroService.getRecords();
          return list.where((record) => !record.isDeleted).toList();
        },
        loadTeams: () async {
          final raw = await ApiService.fetchTeams();
          return raw
              .whereType<Map>()
              .map((t) => Team.fromJson(Map<String, dynamic>.from(t)))
              .toList();
        },
        onTodoGroupsChanged: (groups) {
          unawaited(_handleAiTodoGroupsChanged(groups));
        },
        onTodosBatchAction: _handleAiTodosBatchAction,
        onFixedSchedulesChanged: (schedules) {
          if (!mounted) return;
          setState(() {
            _fixedSchedules = schedules
                .where((schedule) => !schedule.isDeleted)
                .toList();
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('打开AI助手失败: $e')),
      );
    }
  }

  Future<void> _handleAiTodoGroupsChanged(List<TodoGroup> groups) async {
    if (!mounted) return;
    setState(() {
      _todoGroups = groups.where((g) => !g.isDeleted).toList();
      _todoDataRevision++;
    });
    await StorageService.saveTodoGroups(widget.username, groups, sync: true);
  }

  Future<void> _handleAiTodosBatchAction(
    List<TodoItem> inserted,
    List<TodoItem> updated, {
    Map<String, TodoItem>? expectedTodoBaselines,
    Map<String, Set<String>>? expectedSeriesMembership,
  }) async {
    final nextTodos = AiTodoActionExecutor.mergeTodoUpdates(
      _todos,
      inserted,
      updated,
    );
    await StorageService.saveTodos(
      widget.username,
      nextTodos,
      expectedTodoBaselines: expectedTodoBaselines,
      expectedSeriesMembership: expectedSeriesMembership,
    );
    if (!mounted) return;
    setState(() {
      _todos = nextTodos;
      _todoDataRevision++;
    });
    try {
      await _saveTodosToSharedFile(nextTodos);
    } catch (error) {
      debugPrint('AI todo shared-file refresh failed after save: $error');
    }
    try {
      _timelineRevision.value++;
      FloatWindowService.triggerReminderCheck();
      FloatWindowService.invalidateSlotCache();
      FloatWindowService.update();
      _syncTodoNotification();
    } catch (error) {
      debugPrint('AI todo UI refresh failed after save: $error');
    }
    try {
      await _rescheduleAlarms();
    } catch (error) {
      debugPrint('AI todo alarm refresh failed after save: $error');
    }
    try {
      await WidgetService.updateTodoWidget(nextTodos);
    } catch (error) {
      debugPrint('AI todo widget refresh failed after save: $error');
    }
  }

  Future<void> _syncDailyAiSuggestion({
    bool forceRefresh = false,
    bool allowWhenDisabled = false,
  }) async {
    final enabled = await DailyAiSuggestionService.isEnabled(widget.username);
    if (!mounted) return;
    final cached = await DailyAiSuggestionService.loadCachedSuggestion(
      widget.username,
    );
    if (!mounted) return;

    if (enabled || allowWhenDisabled) {
      if (cached != null && !forceRefresh) {
        _dailyAiSuggestionNotifier.value = DailyAiSuggestionSnapshot(
          enabled: enabled,
          suggestion: cached,
        );
      } else {
        _dailyAiSuggestionNotifier.value = DailyAiSuggestionSnapshot(
          enabled: enabled,
          isLoading: true,
          suggestion: cached,
        );
      }
    }

    final snapshot = await DailyAiSuggestionService.ensureTodaySuggestion(
      username: widget.username,
      todos: _todos,
      countdowns: _countdowns,
      planBlocks: _planBlocks,
      fixedSchedules: _fixedSchedules,
      courses:
          (_dashboardCourseData['courses'] as List?)
              ?.whereType<CourseItem>()
              .toList() ??
          const [],
      forceRefresh: forceRefresh,
      allowWhenDisabled: allowWhenDisabled,
    );
    if (!mounted) return;
    _dailyAiSuggestionNotifier.value = snapshot;
  }

  void _onDailyAiSuggestionRevisionChanged() {
    if (!mounted) return;
    unawaited(_syncDailyAiSuggestion());
  }

  Widget _buildDailyAiSuggestionSection(bool isLight) {
    return ValueListenableBuilder<DailyAiSuggestionSnapshot>(
      valueListenable: _dailyAiSuggestionNotifier,
      builder: (context, snapshot, _) {
        return AnimatedBuilder(
          animation: _todosNotifier,
          builder: (context, _) {
            return DailyAiSuggestionCard(
              snapshot: snapshot,
              isLight: isLight,
              todos: _todos,
              onRefresh: () => unawaited(
                _syncDailyAiSuggestion(
                  forceRefresh: true,
                  allowWhenDisabled: true,
                ),
              ),
              onToggleExpanded: (expanded) => unawaited(
                DailyAiSuggestionService.setExpanded(widget.username, expanded),
              ),
              onDismiss: () async {
                await Navigator.push(
                  context,
                  PageTransitions.material(
                    builder: (_) => const AiAssistantSettingsPage(
                      initialTarget:
                          AiAssistantSettingsPage.dailyAiSuggestionTarget,
                    ),
                  ),
                );
                if (mounted) {
                  unawaited(_syncDailyAiSuggestion());
                }
              },
              onOpenModelConfig: () async {
                await Navigator.push(
                  context,
                  PageTransitions.material(
                    builder: (_) => const LLMConfigPage(),
                  ),
                );
                if (mounted) {
                  unawaited(_syncDailyAiSuggestion());
                }
              },
              onOpenTodo: _openTodoEditor,
              onOpenAiChat: (prompt) {
                unawaited(
                  _openAiAssistantFromAppBar(
                    initialMessage: prompt,
                    sendInitialMessage: true,
                  ),
                );
              },
              onAskAiOnce: () async {
                await DailyAiSuggestionService.setManualSectionKept(
                  widget.username,
                  true,
                );
                if (!mounted) return;
                unawaited(
                  _syncDailyAiSuggestion(
                    forceRefresh: true,
                    allowWhenDisabled: true,
                  ),
                );
              },
              onEnableDaily: () async {
                await DailyAiSuggestionService.setEnabled(
                  widget.username,
                  true,
                );
                if (!mounted) return;
                unawaited(_syncDailyAiSuggestion(forceRefresh: true));
              },
              onKeepManualSection: () async {
                await DailyAiSuggestionService.setManualSectionKept(
                  widget.username,
                  true,
                );
                if (!mounted) return;
                unawaited(_syncDailyAiSuggestion());
              },
              onDeclinePrompt: () async {
                await DailyAiSuggestionService.dismissFirstOpenPrompt(
                  widget.username,
                );
                if (!mounted) return;
                _dailyAiSuggestionNotifier.value =
                    const DailyAiSuggestionSnapshot(enabled: false);
                AppSnackBars.showSnackBar(
                  context,
                  const SnackBar(
                    content: Text(
                      '已隐藏每日 AI 建议引导；之后可在「设置 → AI 助手设置 → 每日 AI 建议」中随时开启',
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // === 初始化与生命周期 ===
}
