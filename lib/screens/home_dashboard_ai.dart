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

  Future<void> _openQuickVoiceChat({QuickVoiceGestureController? gesture}) async {
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
            content: Text(!hasChatApi
                ? '请先配置 AI 对话模型和 API Key'
                : '语音识别需要普通小米 MiMo API Key，请在“模型与 API 配置”中填写'),
            action: SnackBarAction(
              label: '配置',
              onPressed: () {
                Navigator.push(
                  context,
                  PageTransitions.material(builder: (_) => const LLMConfigPage()),
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
    final sessionId =
        _pendingTodoConfirm?['recognitionChatSessionId']?.toString().trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      await ChatStorageService.setActiveSessionId(sessionId);
      if (!mounted) return;
      await _openAiAssistantFromAppBar();
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
    bool sendInitialMessage = true,
    ChatUsageSummary? initialVoiceUsageSummary,
  }) async {
    final transitionSourceKey = sourceKey ?? _aiButtonKey;
    final todoState = _todoSectionKey.currentState;
    if (todoState != null) {
      await todoState.openAiAssistant(
        sourceKey: transitionSourceKey,
        initialMessage: initialMessage,
        sendInitialMessage: sendInitialMessage,
        initialVoiceUsageSummary: initialVoiceUsageSummary,
      );
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        CourseService.getAllCourses(widget.username),
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getRecords(),
        ApiService.fetchTeams(),
      ]);
      final courses = (results[0] as List<CourseItem>)
          .where((course) => !course.isDeleted)
          .toList();
      final timeLogs = (results[1] as List<TimeLogItem>)
          .where((log) => !log.isDeleted)
          .toList();
      final pomodoroRecords = (results[2] as List<PomodoroRecord>)
          .where((record) => !record.isDeleted)
          .toList();
      final teams = (results[3] as List)
          .whereType<Map>()
          .map((t) => Team.fromJson(Map<String, dynamic>.from(t)))
          .toList();
      final categoryReminderDefaults =
          await StorageService.getCategoryReminderMinutes(widget.username);

      if (!mounted) return;
      await AiTodoChatLauncher.open(
        context,
        username: widget.username,
        sourceKey: transitionSourceKey,
        initialMessage: initialMessage,
        sendInitialMessage: sendInitialMessage,
        initialVoiceUsageSummary: initialVoiceUsageSummary,
        todos: _todos.where((t) => !t.isDone && !t.isDeleted).toList(),
        todoGroups: _todoGroups,
        courses: courses,
        timeLogs: timeLogs,
        pomodoroRecords: pomodoroRecords,
        conflicts: _latestSyncConflicts,
        teams: teams,
        fixedSchedules: _fixedSchedules,
        categoryReminderDefaults: categoryReminderDefaults,
        onTodoGroupsChanged: (groups) {
          unawaited(_handleAiTodoGroupsChanged(groups));
        },
        onTodosBatchAction: (inserted, updated) {
          unawaited(_handleAiTodosBatchAction(inserted, updated));
        },
        onFixedSchedulesChanged: (schedules) {
          if (!mounted) return;
          setState(() {
            _fixedSchedules =
                schedules.where((schedule) => !schedule.isDeleted).toList();
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
    setState(() => _todoGroups = groups.where((g) => !g.isDeleted).toList());
    await StorageService.saveTodoGroups(widget.username, groups, sync: true);
  }

  Future<void> _handleAiTodosBatchAction(
    List<TodoItem> inserted,
    List<TodoItem> updated,
  ) async {
    final nextTodos = AiTodoActionExecutor.mergeTodoUpdates(
      _todos,
      inserted,
      updated,
    );
    if (!mounted) return;
    setState(() => _todos = nextTodos);
    await StorageService.saveTodos(widget.username, nextTodos);
    await _saveTodosToSharedFile(nextTodos);
    _timelineRevision.value++;
    _todoUpdateSignalNotifier.value++;
    FloatWindowService.triggerReminderCheck();
    FloatWindowService.invalidateSlotCache();
    FloatWindowService.update();
    _syncTodoNotification();
    _rescheduleAlarms();
    await WidgetService.updateTodoWidget(nextTodos);
  }

  // === 初始化与生命周期 ===
}
