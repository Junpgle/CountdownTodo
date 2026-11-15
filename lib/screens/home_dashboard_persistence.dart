part of 'home_dashboard.dart';

// ignore_for_file: annotate_overrides

mixin _HomeDashboardPersistenceMixin on _HomeDashboardStateBase {
  Future<bool> _saveTodosToSharedFile(List<TodoItem> todos) async {
    try {
      await saveIslandTodoSnapshot(todos);
      // debugPrint('[HomeDashboard] Saved ${todos.length} todos to shared file');
      return true;
    } catch (e) {
      // debugPrint('[HomeDashboard] Failed to save todos to shared file: $e');
      return false;
    }
  }

  List<TodoItem> _cloneTodosForPersistence(List<TodoItem> todos) {
    return todos.map((todo) => todo.detachedCopy()).toList();
  }

  List<TodoItem> _mergePendingTodoSnapshots(List<TodoItem> loadedTodos) {
    final snapshots = [
      _persistingTodosSnapshot,
      _pendingTodosToPersist,
    ].whereType<List<TodoItem>>();
    if (snapshots.isEmpty) {
      if (!loadedTodos.any((todo) => todo.isDeleted)) return loadedTodos;
      return loadedTodos.where((todo) => !todo.isDeleted).toList();
    }

    final byId = <String, TodoItem>{};
    for (final todo in loadedTodos) {
      if (!todo.isDeleted) byId[todo.id] = todo;
    }
    for (final snapshot in snapshots) {
      for (final pending in snapshot) {
        final existing = byId[pending.id];
        // 🚀 用户主动修改优先：updatedAt >= 时信任挂起快照
        if (existing == null ||
            TodoLwwService.compare(
                  incomingUpdatedAt: pending.updatedAt,
                  incomingVersion: pending.version,
                  currentUpdatedAt: existing.updatedAt,
                  currentVersion: existing.version,
                ) >=
                0) {
          byId[pending.id] = pending;
        }
      }
    }
    return byId.values.where((todo) => !todo.isDeleted).toList();
  }

  Future<void> _handleTodosChanged(List<TodoItem> newTodos) async {
    final oldTodos = _todos;
    final nextTodos = List<TodoItem>.from(newTodos);

    _todos = nextTodos;
    _todoDataRevision++;
    _todosNotifier.value = List<TodoItem>.from(nextTodos);
    _timelineRevision.value++;
    _pomodoroTickNotifier.value++;

    Map<String, bool>? oldTodoCompletionById;
    var completedTodoCount = 0;
    for (final nt in nextTodos) {
      if (!nt.isDone) continue;
      completedTodoCount++;

      if (oldTodoCompletionById == null && completedTodoCount < 3) {
        final ot = oldTodos.firstWhere((t) => t.id == nt.id, orElse: () => nt);
        if (!ot.isDone) {
          // debugPrint("🧹 任务 ${nt.title} 已完成，尝试清除通知 ${nt.id.hashCode}");
          NotificationService.cancelSpecialTodoNotification(nt.id.hashCode);
        }
        continue;
      }

      if (oldTodoCompletionById == null) {
        final completionById = <String, bool>{};
        for (final oldTodo in oldTodos) {
          completionById.putIfAbsent(oldTodo.id, () => oldTodo.isDone);
        }
        oldTodoCompletionById = completionById;
      }
      if (oldTodoCompletionById[nt.id] == false) {
        // debugPrint("🧹 任务 ${nt.title} 已完成，尝试清除通知 ${nt.id.hashCode}");
        NotificationService.cancelSpecialTodoNotification(nt.id.hashCode);
      }
    }

    _pendingTodosToPersist = _cloneTodosForPersistence(nextTodos);
    _todoPersistDebounce?.cancel();
    if (_todoPersistDebounceCompleter?.isCompleted == false) {
      _todoPersistDebounceCompleter!.complete();
    }

    final completer = Completer<void>();
    _todoPersistDebounceCompleter = completer;
    _todoPersistDebounce = Timer(const Duration(milliseconds: 220), () {
      _todoPersistChain = _todoPersistChain
          .catchError((_) {})
          .then((_) async {
            final snapshot = _pendingTodosToPersist;
            if (snapshot == null) return;
            _pendingTodosToPersist = null;
            await _persistTodosSnapshot(snapshot);
          })
          .catchError((e) {
            // debugPrint('[HomeDashboard] persist todos failed: $e');
          })
          .whenComplete(() {
            if (!completer.isCompleted) completer.complete();
          });
    });

    return completer.future;
  }

  Future<TodoEditorSaveResult> _handleTodoEditorSave(
    List<TodoItem> changedTodos,
    Map<String, TodoItem> baselines, {
    Map<String, Set<String>>? expectedSeriesMembership,
    Set<String>? expectedFixedScheduleTodoIds,
    List<FixedScheduleItem>? expectedFixedScheduleBaselines,
  }) async {
    if (changedTodos.isEmpty) return const TodoEditorSaveResult();
    _todoPersistDebounce?.cancel();
    final waiter = _todoPersistDebounceCompleter;
    final task = _todoPersistChain.catchError((Object _) {}).then((_) async {
      final warnings = <String>[];
      final pending = _pendingTodosToPersist;
      _pendingTodosToPersist = null;
      if (pending != null) {
        warnings.addAll(await _persistTodosSnapshot(pending));
      }
      try {
        warnings.addAll(
          await _persistTodosSnapshot(
            changedTodos,
            expectedTodoBaselines: baselines,
            expectedSeriesMembership: expectedSeriesMembership,
            expectedFixedScheduleTodoIds: expectedFixedScheduleTodoIds,
            expectedFixedScheduleBaselines: expectedFixedScheduleBaselines,
          ),
        );
      } catch (error) {
        try {
          final committed = await TodoEditorSaveService.isCommitted(
            widget.username,
            changedTodos,
          );
          if (committed) {
            warnings.add('待办已保存；有后续设备状态更新失败');
          } else {
            rethrow;
          }
        } catch (_) {
          rethrow;
        }
      }
      if (mounted) {
        try {
          await _loadAllData(domains: const {DataRefreshDomain.todos});
        } catch (_) {
          warnings.add('首页待办刷新失败');
        }
      }
      if (waiter?.isCompleted == false) waiter!.complete();
      return TodoEditorSaveResult(warnings: warnings);
    });
    _todoPersistChain = task.then<void>((_) {}).catchError((Object _) {});
    try {
      return await task;
    } catch (_) {
      if (waiter?.isCompleted == false) waiter!.complete();
      rethrow;
    }
  }

  Future<void> _handleTodoEditorGroupsSave(
    List<TodoGroup> changedGroups,
    Map<String, TodoGroup> baselines,
  ) async {
    await TodoEditorSaveService.saveGroups(
      username: widget.username,
      changedGroups: changedGroups,
      baselines: baselines,
    );
    if (!mounted) return;
    final groupsById = {for (final group in _todoGroups) group.id: group};
    for (final group in changedGroups) {
      if (group.isDeleted) {
        groupsById.remove(group.id);
      } else {
        groupsById[group.id] = group;
      }
    }
    setState(() {
      _todoGroups = groupsById.values.toList(growable: false);
      _todoDataRevision++;
    });
  }

  Future<List<String>> _persistTodosSnapshot(
    List<TodoItem> todosSnapshot, {
    Map<String, TodoItem>? expectedTodoBaselines,
    Map<String, Set<String>>? expectedSeriesMembership,
    Set<String>? expectedFixedScheduleTodoIds,
    List<FixedScheduleItem>? expectedFixedScheduleBaselines,
  }) async {
    _persistingTodosSnapshot = todosSnapshot;
    final warnings = <String>[];
    try {
      final allTodos = await StorageService.getTodos(widget.username);
      final todosToPersistById = <String, TodoItem>{};
      if (expectedTodoBaselines == null) {
        for (final todo in allTodos) {
          if (todo.recurrence != RecurrenceType.none &&
              (todo.recurrenceSeriesId == null ||
                  todo.recurrenceSeriesId!.isEmpty)) {
            todo.recurrenceSeriesId = todo.id;
            todosToPersistById[todo.id] = todo;
          }
        }
      }

      final todoIndicesById = <String, int>{};
      for (var index = 0; index < allTodos.length; index++) {
        final id = allTodos[index].id;
        if (!todoIndicesById.containsKey(id)) {
          todoIndicesById[id] = index;
        }
      }
      for (final newTodo in todosSnapshot) {
        final index = todoIndicesById[newTodo.id];
        if (index != null) {
          final existing = allTodos[index];
          if (TodoLwwService.compare(
                incomingUpdatedAt: newTodo.updatedAt,
                incomingVersion: newTodo.version,
                currentUpdatedAt: existing.updatedAt,
                currentVersion: existing.version,
              ) >=
              0) {
            allTodos[index] = newTodo;
            todosToPersistById[newTodo.id] = newTodo;
          }
        } else {
          todoIndicesById[newTodo.id] = allTodos.length;
          allTodos.add(newTodo);
          todosToPersistById[newTodo.id] = newTodo;
        }
      }
      await StorageService.saveTodos(
        widget.username,
        todosToPersistById.values.toList(growable: false),
        bandSyncSnapshot: allTodos,
        expectedTodoBaselines: expectedTodoBaselines,
        expectedSeriesMembership: expectedSeriesMembership,
        expectedFixedScheduleTodoIds: expectedFixedScheduleTodoIds,
        expectedFixedScheduleBaselines: expectedFixedScheduleBaselines,
      );
      if (!await _saveTodosToSharedFile(allTodos)) {
        warnings.add('共享文件更新失败');
      }
      try {
        FloatWindowService.triggerReminderCheck();
        FloatWindowService.invalidateSlotCache();
        FloatWindowService.update();
        _syncTodoNotification();
        await _rescheduleAlarms();
      } catch (_) {
        warnings.add('提醒或浮窗更新失败');
      }
      try {
        await WidgetService.updateTodoWidget(allTodos);
      } catch (_) {
        warnings.add('桌面小组件更新失败');
      }
      return warnings;
    } finally {
      if (identical(_persistingTodosSnapshot, todosSnapshot)) {
        _persistingTodosSnapshot = null;
      }
    }
  }

  Future<void> _handleManualSync({
    bool silent = false,
    bool syncTodos = true,
    bool syncCountdowns = true,
    bool syncScreenTime = true,
    bool syncPomodoro = true,
    bool syncTimeLogs = true,
    bool syncPlanBlocks = true,
    bool syncFixedSchedules = true,
    bool syncHabits = true,
    bool syncFinance = true,
    bool financeSyncExplicitlyAuthorized = false,
  }) async {
    if (_isSyncing || !mounted) return;

    // 在任何 await 之前取得本地同步锁。待持久化快照可能需要一次 SQLite
    // 写入；若锁在其后才设置，快速连点会并行进入两次同步流程。
    setState(() => _isSyncing = true);
    final syncAttempt = ++_syncAttemptGeneration;

    try {
      if (await AppSettingsStorage.isOfflineModeEnabled()) {
        if (silent) {
          unawaited(LanSyncService.instance.triggerBackgroundAutoSync());
        } else if (mounted) {
          AppStatusToast.show(
            context: context,
            anchorKey: _syncButtonKey,
            message: '离线模式已开启，已跳过服务器同步',
          );
        }
        return;
      }

      // 🚀 核心修复：同步前先强制保存用户未持久化的修改（如取消勾选），
      // 防止 syncData 的 saveTodos(isSyncSource=true) 覆盖用户意图。
      final flushedTodoIds = <String>{};
      _todoPersistDebounce?.cancel();
      final flushPendingTask = _todoPersistChain.catchError((Object _) {}).then(
        (_) async {
          while (_pendingTodosToPersist != null) {
            final pending = _pendingTodosToPersist!;
            _pendingTodosToPersist = null;
            flushedTodoIds.addAll(pending.map((todo) => todo.id));
            await _persistTodosSnapshot(pending);
          }
        },
      );
      _todoPersistChain = flushPendingTask
          .then<void>((_) {})
          .catchError((Object _) {});
      await flushPendingTask;
      if (flushedTodoIds.isNotEmpty) {
        // Protect rows persisted immediately before sync from being replaced
        // by an older remote snapshot during this sync pass.
        StorageService.setForceFlushProtectedUuids(flushedTodoIds);
      }

      // 仅记录长耗时诊断，不释放逻辑锁。释放锁必须由真实的同步 Future
      // 结束时的 finally 完成，否则第二次点击会与仍在运行的同步重叠。
      _syncWatchdogTimer?.cancel();
      _syncWatchdogTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && syncAttempt == _syncAttemptGeneration && _isSyncing) {
          debugPrint('[DashboardSync] sync still running after 30 seconds');
        }
      });
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("未登录");
      if (!mounted) return;

      bool hasChanges = false;

      if (syncTodos ||
          syncCountdowns ||
          syncTimeLogs ||
          syncPomodoro ||
          syncPlanBlocks ||
          syncFixedSchedules ||
          syncHabits ||
          syncFinance) {
        final syncResult = await StorageService.syncData(
          widget.username,
          syncTodos: syncTodos,
          syncCountdowns: syncCountdowns,
          // ScreenTimeService owns this endpoint and uploads it below.  Keep
          // it out of the generic sync request so one refresh cannot submit
          // the same day twice and consume two sync-limit entries.
          syncScreenTime: false,
          syncTimeLogs: syncTimeLogs,
          syncPlanBlocks: syncPlanBlocks,
          syncPomodoro: syncPomodoro,
          syncFixedSchedules: syncFixedSchedules,
          syncHabits: syncHabits,
          syncFinance: syncFinance,
          financeSyncExplicitlyAuthorized: financeSyncExplicitlyAuthorized,
          context: context,
        );
        if (syncResult['success'] != true) {
          final error = syncResult['error']?.toString() ?? '同步请求未成功';
          throw StateError(error);
        }
        hasChanges = syncResult['hasChanges'] ?? false;
        final List<String> updatedTodoIds =
            (syncResult['updatedTodoIds'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const <String>[];
        if (updatedTodoIds.isNotEmpty && mounted) {
          _remoteTodoHighlightTimer?.cancel();
          setState(() {
            _updatedByOthersTodoIds
              ..clear()
              ..addAll(updatedTodoIds);
            _remoteTodoHighlightSignal++;
          });
          _remoteTodoHighlightTimer = Timer(const Duration(seconds: 8), () {
            if (!mounted) return;
            setState(() => _updatedByOthersTodoIds.clear());
          });
        }

        // 🚀 新增：处理冲突信息
        final List<ConflictInfo> conflicts = syncResult['conflicts'] ?? [];
        if (mounted) {
          setState(() => _latestSyncConflicts = conflicts);
        }
        final conflictDetectionEnabled =
            await StorageService.getConflictDetectionEnabled();
        if (conflictDetectionEnabled && conflicts.isNotEmpty && mounted) {
          final shouldOpenConflictCenter = await ConflictAlertDialog.show(
            context,
            conflicts,
          );
          if (shouldOpenConflictCenter == true && mounted) {
            await Navigator.push(
              context,
              PageTransitions.material(
                builder: (_) => ConflictInboxScreen(
                  username: widget.username,
                  syncConflicts: conflicts,
                ),
              ),
            );
          }
        }
      }

      // Screen-time has a single owner: the dedicated service.
      if (syncScreenTime) {
        await ScreenTimeService.syncScreenTime(userId);
        await _loadCachedScreenTime();
      }

      await StorageService.updateLastAutoSyncTime(widget.username);

      if (mounted) {
        if (!silent) {
          AppStatusToast.show(
            context: context,
            anchorKey: _syncButtonKey,
            message: '服务器同步完成',
          );
        }
        if (hasChanges) {
          // 同步后数据有变化，刷新 Island 槽位缓存
          FloatWindowService.invalidateSlotCache();
          _rescheduleAlarms();
        }

        // 🚀 同步手环版本信息
        unawaited(UpdateService.syncBandVersionInfo());
      }
      // ... 前面代码保持不变
    } catch (e) {
      // debugPrint("Sync Error: $e");
      String msg = e.toString();

      // 🚀 核心修复 1：Token 检查必须移出 !silent 判断
      // 无论是否是“静默同步”，只要登录失效，就必须强制弹窗
      if (msg.contains("无效的token") ||
          msg.contains("无效的Token") || // 适配你日志中的大写 T
          msg.contains("INVALID_TOKEN") ||
          msg.contains("401")) {
        if (mounted) {
          _showTokenExpiredDialog();
        }
        return; // 拦截后续所有提示
      }

      // 只有非静默同步（手动点击）时，才显示普通的错误 SnackBar
      if (mounted && !silent) {
        if (msg.contains("LIMIT_EXCEEDED:")) {
          msg = msg.split("LIMIT_EXCEEDED:").last;
        } else {
          msg = "同步失败: 获取数据异常";
        }
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (syncAttempt == _syncAttemptGeneration) {
        _syncWatchdogTimer?.cancel();
        _syncWatchdogTimer = null;
        if (mounted) {
          setState(() {
            _isSyncing = false;
          });
        }
        // 🚀 同步完成后清除保护，防止后续加载被干扰。旧同步结束时不能
        // 清除下一次同步刚建立的保护状态。
        _pendingTodosToPersist = null;
        _persistingTodosSnapshot = null;
        StorageService.setForceFlushProtectedUuids({});
      }
    }
  }

  /// 🚀 Uni-Sync 4.0: 链路可视化诊断报告
  Future<void> _showLinkDiagnostics() async {
    final isOfflineMode = await AppSettingsStorage.isOfflineModeEnabled();
    if (!mounted) return;

    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                const Text(
                  "链路诊断报告",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDiagnosticItem("核心 API 服务", ApiService.ping()),
                  _buildDiagnosticItem(
                    "实时同步通道",
                    Future.value(
                      PomodoroSyncService.instance.connectionState ==
                          SyncConnectionState.connected,
                    ),
                    isOfflinePaused: isOfflineMode,
                    offlineMessage: "离线模式已开启，已强制断开 WebSocket",
                  ),
                  _buildDiagnosticItem(
                    "增量引擎状态",
                    Future.value(true),
                  ), // 逻辑始终为真，仅展示
                  if (isOfflineMode) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "当前已开启离线模式：系统会强制断开 WebSocket 并暂停服务器同步，实时同步通道未连接属于正常现象；如需恢复实时同步，请在同步设置中关闭离线模式。",
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 32),
                  _buildEnvironmentInfo(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("关闭"),
              ),
              TextButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(
                    'https://github.com/Junpgle/math_quiz_app/issues',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.bug_report_outlined, size: 16),
                label: const Text("GitHub"),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(context);
                  _handleManualSync(silent: false);
                },
                icon: const Icon(Icons.sync, size: 18),
                label: const Text("强制同步数据"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDiagnosticItem(
    String label,
    Future<bool> checkFuture, {
    bool isOfflinePaused = false,
    String? offlineMessage,
  }) {
    return FutureBuilder<bool>(
      future: checkFuture,
      builder: (context, snapshot) {
        final bool? isOk = snapshot.data;
        final bool isLoading =
            snapshot.connectionState == ConnectionState.waiting;
        final bool pausedByOffline = isOfflinePaused && isOk != true;
        final colorScheme = Theme.of(context).colorScheme;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: isLoading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Icon(
                        isOk == true
                            ? Icons.check_circle
                            : pausedByOffline
                            ? Icons.cloud_off_rounded
                            : Icons.error,
                        size: 20,
                        color: isOk == true
                            ? Colors.green
                            : pausedByOffline
                            ? colorScheme.secondary
                            : Colors.redAccent,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (!isLoading)
                      Text(
                        isOk == true
                            ? "服务运行正常"
                            : pausedByOffline
                            ? (offlineMessage ?? "离线模式已开启，已主动断开连接")
                            : "连接受阻，部分功能受限",
                        style: TextStyle(
                          fontSize: 11,
                          color: isOk == true
                              ? Colors.grey
                              : pausedByOffline
                              ? colorScheme.secondary
                              : Colors.redAccent.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEnvironmentInfo() {
    final isTest = ApiService.isTestServer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          _buildInfoRow(
            "当前接入点",
            isTest ? "Aliyun (Test Node)" : "Aliyun (Global Node)",
          ),
          const SizedBox(height: 8),
          const Text(
            "注意：链路异常可能影响公告获取、版本更新、多设备同步等功能",
            style: TextStyle(fontSize: 10, color: Colors.orangeAccent),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ),
      ],
    );
  }

  Future<void> _showSyncOptionsDialog() async {
    final initialSyncFinance =
        await AppSettingsStorage.isFinanceCloudSyncEnabled(widget.username);
    final isOfflineMode = await AppSettingsStorage.isOfflineModeEnabled();
    if (!mounted) return;

    final selection = await showManualSyncOptionsDialog(
      context,
      initialSyncFinance: initialSyncFinance,
      isOfflineMode: isOfflineMode,
      lanPeerCount: LanSyncService.instance.devices.length,
    );
    if (selection == null || !selection.hasAnySelected || !mounted) return;

    if (selection.target == ManualSyncTarget.lan) {
      await _handleManualLanSync(selection);
      return;
    }

    _handleManualSync(
      silent: false,
      syncTodos: selection.syncTodos,
      syncCountdowns: selection.syncCountdowns,
      syncScreenTime: selection.syncScreenTime,
      syncPomodoro: selection.syncPomodoro,
      syncTimeLogs: selection.syncTimeLogs,
      syncPlanBlocks: selection.syncPlanBlocks,
      syncFixedSchedules: selection.syncFixedSchedules,
      syncHabits: selection.syncHabits,
      syncFinance: selection.syncFinance,
      financeSyncExplicitlyAuthorized: selection.syncFinance,
    );
  }

  Future<void> _handleManualLanSync(ManualSyncSelection selection) async {
    if (_isSyncing || !mounted) return;
    setState(() => _isSyncing = true);
    _suppressNextLanToast = true;
    try {
      final config = LanSyncConfig(
        syncTodos: selection.syncTodos,
        syncCountdowns: selection.syncCountdowns,
        syncTimeLogs: selection.syncTimeLogs,
        syncPomodoroTags: selection.syncPomodoro,
        syncPomodoroRecords: selection.syncPomodoro,
      );
      final result = await LanSyncService.instance.syncManualWithPeers(
        config: config,
      );
      if (!mounted) return;
      if (result.success) {
        await _loadAllData();
        if (!mounted) return;
        AppStatusToast.show(
          context: context,
          anchorKey: _syncButtonKey,
          message: result.message.isNotEmpty ? result.message : '局域网同步成功',
        );
      } else {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      _suppressNextLanToast = false;
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  // --- Wallpaper Fallback Logic ---
}
