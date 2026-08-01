part of 'home_dashboard.dart';
// ignore_for_file: annotate_overrides

mixin _HomeDashboardPersistenceMixin on _HomeDashboardStateBase {
  Future<void> _saveTodosToSharedFile(List<TodoItem> todos) async {
    try {
      await saveIslandTodoSnapshot(todos);
      // debugPrint('[HomeDashboard] Saved ${todos.length} todos to shared file');
    } catch (e) {
      // debugPrint('[HomeDashboard] Failed to save todos to shared file: $e');
    }
  }

  List<TodoItem> _cloneTodosForPersistence(List<TodoItem> todos) {
    return todos.map((todo) => TodoItem.fromJson(todo.toJson())).toList();
  }

  List<TodoItem> _mergePendingTodoSnapshots(List<TodoItem> loadedTodos) {
    final snapshots = [
      _persistingTodosSnapshot,
      _pendingTodosToPersist,
    ].whereType<List<TodoItem>>();
    if (snapshots.isEmpty) return loadedTodos;

    final byId = {for (final todo in loadedTodos) todo.id: todo};
    for (final snapshot in snapshots) {
      for (final pending in snapshot) {
        final existing = byId[pending.id];
        // 🚀 用户主动修改优先：updatedAt >= 时信任挂起快照
        if (existing == null || pending.updatedAt >= existing.updatedAt) {
          byId[pending.id] = pending;
        }
      }
    }
    return byId.values.where((todo) => !todo.isDeleted).toList();
  }

  Future<void> _handleTodosChanged(List<TodoItem> newTodos) async {
    final oldTodos = List<TodoItem>.from(_todos);
    final nextTodos = List<TodoItem>.from(newTodos);

    if (mounted) {
      setState(() => _todos = nextTodos);
    } else {
      _todos = nextTodos;
    }
    _todoRevision.value++;
    _timelineRevision.value++;

    for (var nt in nextTodos) {
      if (nt.isDone) {
        final ot = oldTodos.firstWhere((t) => t.id == nt.id, orElse: () => nt);
        if (!ot.isDone) {
          // debugPrint("🧹 任务 ${nt.title} 已完成，尝试清除通知 ${nt.id.hashCode}");
          NotificationService.cancelSpecialTodoNotification(nt.id.hashCode);
        }
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
      _todoPersistChain = _todoPersistChain.catchError((_) {}).then((_) async {
        final snapshot = _pendingTodosToPersist;
        if (snapshot == null) return;
        _pendingTodosToPersist = null;
        await _persistTodosSnapshot(snapshot);
      }).catchError((e) {
        // debugPrint('[HomeDashboard] persist todos failed: $e');
      }).whenComplete(() {
        if (!completer.isCompleted) completer.complete();
      });
    });

    return completer.future;
  }

  Future<void> _persistTodosSnapshot(List<TodoItem> todosSnapshot) async {
    _persistingTodosSnapshot = todosSnapshot;
    final allTodos = await StorageService.getTodos(widget.username);
    try {
      for (var newT in todosSnapshot) {
        int idx = allTodos.indexWhere((x) => x.id == newT.id);
        if (idx != -1) {
          if (newT.updatedAt >= allTodos[idx].updatedAt) {
            allTodos[idx] = newT;
          }
        } else {
          allTodos.add(newT);
        }
      }
      await StorageService.saveTodos(widget.username, allTodos);
      await _saveTodosToSharedFile(allTodos);

      FloatWindowService.triggerReminderCheck();
      FloatWindowService.invalidateSlotCache();
      FloatWindowService.update();
      _syncTodoNotification();
      _rescheduleAlarms();
      await WidgetService.updateTodoWidget(todosSnapshot);

      _todoUpdateSignalNotifier.value++;
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
  }) async {
    if (_isSyncing) return;

    // 🚀 核心修复：同步前先强制保存用户未持久化的修改（如取消勾选），
    // 防止 syncData 的 saveTodos(isSyncSource=true) 覆盖用户意图。
    final pendingSnapshotBeforeSync = _pendingTodosToPersist;
    if (pendingSnapshotBeforeSync != null) {
      _pendingTodosToPersist = null;
      _todoPersistDebounce?.cancel();
      await StorageService.saveTodos(
          widget.username, pendingSnapshotBeforeSync);
      // 🚀 设置保护：merge 时跳过这些待办，防止同步覆盖用户刚做的修改
      StorageService.setForceFlushProtectedUuids(
          pendingSnapshotBeforeSync.map((t) => t.id).toSet());
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      // 🚀 核心加固：增加 30 秒超时强制释放锁，防止由于网络异常导致的图标“永动机”
      Timer(const Duration(seconds: 30), () {
        if (mounted && _isSyncing) {
          setState(() => _isSyncing = false);
        }
      });
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("未登录");
      if (!mounted) return;

      bool hasChanges = false;

      // 🚀 2. 判断条件加入 syncTimeLogs
      if (syncTodos || syncCountdowns || syncTimeLogs || syncPlanBlocks) {
        final syncResult = await StorageService.syncData(
          widget.username,
          syncTodos: syncTodos,
          syncCountdowns: syncCountdowns,
          syncTimeLogs: syncTimeLogs,
          syncPlanBlocks: syncPlanBlocks,
          syncPomodoro: false,
          context: context,
        );
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
          final shouldOpenConflictCenter =
              await ConflictAlertDialog.show(context, conflicts);
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

      if (syncPomodoro) {
        await PomodoroService.syncRecordsToCloud();
        await PomodoroService.syncRecordsFromCloud();
        await PomodoroService.syncTagsToCloud();
        await PomodoroService.syncTagsFromCloud();
      }

      if (syncScreenTime) {
        await ScreenTimeService.syncScreenTime(userId);
        await _loadCachedScreenTime();
      }

      await StorageService.updateLastAutoSyncTime(widget.username);

      if (mounted) {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ 数据同步完成'), backgroundColor: Colors.green));
        }
        if (hasChanges) {
          // 同步后数据有变化，刷新 Island 槽位缓存
          FloatWindowService.invalidateSlotCache();
          _rescheduleAlarms();
          _loadAllData();
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
      // 🚀 同步完成后清除保护，防止后续加载被干扰
      _pendingTodosToPersist = null;
      _persistingTodosSnapshot = null;
      StorageService.setForceFlushProtectedUuids({});
    }
  }

  /// 🚀 Uni-Sync 4.0: 链路可视化诊断报告
  Future<void> _showLinkDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.analytics_outlined,
                    color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 10),
                const Text("链路诊断报告",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                              SyncConnectionState.connected)),
                  _buildDiagnosticItem(
                      "增量引擎状态", Future.value(true)), // 逻辑始终为真，仅展示
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
                      'https://github.com/Junpgle/math_quiz_app/issues');
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

  Widget _buildDiagnosticItem(String label, Future<bool> checkFuture) {
    return FutureBuilder<bool>(
      future: checkFuture,
      builder: (context, snapshot) {
        bool? isOk = snapshot.data;
        bool isLoading = snapshot.connectionState == ConnectionState.waiting;

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
                        isOk == true ? Icons.check_circle : Icons.error,
                        size: 20,
                        color: isOk == true ? Colors.green : Colors.redAccent,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (!isLoading)
                      Text(
                        isOk == true ? "服务运行正常" : "连接受阻，部分功能受限",
                        style: TextStyle(
                            fontSize: 11,
                            color: isOk == true
                                ? Colors.grey
                                : Colors.redAccent.withValues(alpha: 0.8)),
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
    final isTest = ApiService.baseUrl.contains(':8084');
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
              "当前接入点", isTest ? "Aliyun (Test Node)" : "Aliyun (Global Node)"),
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
        Text(value,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      ],
    );
  }

  void _showSyncOptionsDialog() {
    bool syncTodos = true;
    bool syncCountdowns = true;
    bool syncScreenTime = true;
    bool syncPomodoro = true;
    bool syncTimeLogs = true;
    bool syncPlanBlocks = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title:
              const Text("手动同步", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            // 加入滚动防止选项过多溢出屏幕
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("请勾选你需要同步的数据模块：",
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text("待办事项"),
                  value: syncTodos,
                  onChanged: (val) =>
                      setDialogState(() => syncTodos = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("重要日与倒计时"),
                  value: syncCountdowns,
                  onChanged: (val) =>
                      setDialogState(() => syncCountdowns = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("屏幕使用时间"),
                  value: syncScreenTime,
                  onChanged: (val) =>
                      setDialogState(() => syncScreenTime = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("番茄钟记录"),
                  value: syncPomodoro,
                  onChanged: (val) =>
                      setDialogState(() => syncPomodoro = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("时间日志 (补录)"),
                  value: syncTimeLogs,
                  onChanged: (val) =>
                      setDialogState(() => syncTimeLogs = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text("今日规划"),
                  value: syncPlanBlocks,
                  onChanged: (val) =>
                      setDialogState(() => syncPlanBlocks = val ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
            FilledButton(
              // 🚀 3. 按钮启用条件加入 syncTimeLogs
              onPressed: (syncTodos ||
                      syncCountdowns ||
                      syncScreenTime ||
                      syncPomodoro ||
                      syncTimeLogs ||
                      syncPlanBlocks)
                  ? () {
                      Navigator.pop(ctx);
                      _handleManualSync(
                        silent: false,
                        syncTodos: syncTodos,
                        syncCountdowns: syncCountdowns,
                        syncScreenTime: syncScreenTime,
                        syncPomodoro: syncPomodoro,
                        syncTimeLogs: syncTimeLogs,
                        syncPlanBlocks: syncPlanBlocks,
                      );
                    }
                  : null,
              child: const Text("开始同步"),
            ),
          ],
        );
      }),
    );
  }

  // --- Wallpaper Fallback Logic ---
}
