part of '../conflict_inbox_screen.dart';

extension _ConflictInboxBatchActionsExt on _ConflictInboxScreenState {
  void _resolveConflict(dynamic item) {
    if (_isLocalScheduleConflict(item)) {
      _showLocalScheduleConflict(item);
      return;
    }

    final serverVersion = _findServerVersion(item);
    if (serverVersion == null || serverVersion.isEmpty) {
      _showMissingServerSnapshot(item);
      return;
    }

    final localJson = _itemToJson(item);
    final table = _resolveTable(item);

    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ConflictResolutionSheet(
        localItem: localJson,
        serverItem: serverVersion,
        table: table,
        username: widget.username,
        onResolved: () {
          _loadConflicts();
        },
      ),
    );
  }

  void _showMissingServerSnapshot(dynamic item) {
    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => OptionalLiquidGlassSheet(
        topRadius: 20,
        padding: const EdgeInsets.all(24),
        fallbackDecoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无云端版本快照',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '当前条目标记为${_conflictLabel(item)}，但本地没有保存可对比的服务器版本内容。',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              '这通常表示当前只有本地冲突标记，或者版本冲突发生时服务器快照尚未落盘。',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _resolveGhostConflict(item);
                    },
                    child: const Text('强制保留本地'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _batchKeepLocal() async {
    if (_selectedConflictIds.isEmpty) return;
    _mutateState(() => _isBatchApplying = true);

    try {
      int successCount = 0;
      int scheduleSkippedCount = 0;
      final ids = _selectedConflictIds.toList();
      final conflictItemsById = _visibleConflictItemsById();

      for (final itemId in ids) {
        try {
          final conflictItem = conflictItemsById[itemId];
          if (conflictItem == null) continue;

          if (_isLocalScheduleConflict(conflictItem) &&
              conflictItem is TodoItem) {
            scheduleSkippedCount++;
            continue;
          }

          // 对于有服务器版本的冲突，使用 _ConflictResolutionSheet 的逻辑
          final serverVersion = _findServerVersion(conflictItem);
          if (serverVersion != null && serverVersion.isNotEmpty) {
            if (await _keepLocalAndQueueSync(conflictItem, syncNow: false)) {
              successCount++;
            }
          } else {
            // 用户明确选择保留本地时，也要生成 oplog，否则另一端收不到本地完成状态。
            if (await _keepLocalAndQueueSync(conflictItem, syncNow: false)) {
              successCount++;
            }
          }
        } catch (e) {
          // debugPrint('批量保留本地失败 $itemId: $e');
        }
      }

      if (successCount > 0) {
        Future.microtask(() => StorageService.syncData(widget.username));
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        _selectedConflictIds.clear();
        _isBatchMode = false;
        await _loadConflicts();
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          SnackBar(
            content: Text(
              scheduleSkippedCount > 0
                  ? '已保留本地版本，成功处理 $successCount 项版本冲突；$scheduleSkippedCount 项时间冲突需单独处理'
                  : '已保留本地版本，成功处理 $successCount 项冲突',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('批量操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _isBatchApplying = false);
    }
  }

  Future<void> _batchAcceptServer() async {
    if (_selectedConflictIds.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    _mutateState(() => _isBatchApplying = true);

    try {
      int successCount = 0;
      int scheduleSkippedCount = 0;
      final ids = _selectedConflictIds.toList();
      final conflictItemsById = _visibleConflictItemsById();

      for (final itemId in ids) {
        try {
          final conflictItem = conflictItemsById[itemId];
          if (conflictItem == null) continue;

          if (_isLocalScheduleConflict(conflictItem) &&
              conflictItem is TodoItem) {
            scheduleSkippedCount++;
            continue;
          }

          final serverVersion = _findServerVersion(conflictItem);
          if (serverVersion == null || serverVersion.isEmpty) continue;

          final localJson = _itemToJson(conflictItem);
          final table = _resolveTable(conflictItem);
          final uuid = localJson['uuid'] ?? localJson['id'] ?? '';

          serverVersion['has_conflict'] = 0;

          await StorageService.resolveConflictLocally(
            uuid: uuid,
            table: table,
            resolvedData: serverVersion,
            createOplog: false,
            touchUpdatedAt: false,
          );

          final apiResult = await ApiService.resolveConflict(
            uuid: uuid,
            table: table,
            resolution: 'accept_server',
          );
          if (apiResult['success'] != true) {
            // debugPrint(
            //     'batch accept_server API failed for $uuid: ${apiResult['error']}');
            await StorageService.resolveConflictLocally(
              uuid: uuid,
              table: table,
              resolvedData: serverVersion,
              createOplog: true,
              touchUpdatedAt: true,
            );
          }

          successCount++;
        } catch (e) {
          // debugPrint('批量采用服务器版本失败 $itemId: $e');
        }
      }

      if (successCount > 0) {
        Future.microtask(() => StorageService.syncData(widget.username));
      }

      if (mounted) {
        _selectedConflictIds.clear();
        _isBatchMode = false;
        await _loadConflicts();
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          SnackBar(
            content: Text(
              scheduleSkippedCount > 0
                  ? '已采用服务器版本，成功处理 $successCount 项版本冲突；$scheduleSkippedCount 项时间冲突需单独处理'
                  : '已采用服务器版本，成功处理 $successCount 项冲突',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          SnackBar(content: Text('批量操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _isBatchApplying = false);
    }
  }

  Future<void> _batchApplyRecommended() async {
    if (_selectedConflictIds.isEmpty) return;

    _showBatchResolutionDialog();
  }

  void _showBatchResolutionDialog() {
    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => OptionalLiquidGlassSheet(
        topRadius: 20,
        padding: const EdgeInsets.all(24),
        fallbackDecoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '批量推荐方案',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '该操作将对选中的 ${_selectedConflictIds.length} 项冲突应用推荐的解决方案。',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '批量推荐只处理版本冲突；时间冲突需要进入单条详情查看预览后确认。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _batchApplyRecommendedExecute();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: const Text('应用推荐方案'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _batchApplyRecommendedExecute() async {
    final messenger = ScaffoldMessenger.of(context);
    _mutateState(() => _isBatchApplying = true);

    try {
      int successCount = 0;
      int scheduleSkippedCount = 0;
      final ids = _selectedConflictIds.toList();
      final conflictItemsById = _visibleConflictItemsById();

      for (final itemId in ids) {
        try {
          final conflictItem = conflictItemsById[itemId];
          if (conflictItem == null) continue;

          if (_isLocalScheduleConflict(conflictItem) &&
              conflictItem is TodoItem) {
            scheduleSkippedCount++;
            continue;
          } else {
            // 对于版本冲突，保留本地版本
            final serverVersion = _findServerVersion(conflictItem);
            if (serverVersion != null && serverVersion.isNotEmpty) {
              final localJson = _itemToJson(conflictItem);
              final table = _resolveTable(conflictItem);

              final uuid = localJson['uuid'] ?? localJson['id'] ?? '';
              final serverVer = serverVersion['version'] as int? ?? 0;
              final currentVer = localJson['version'] as int? ?? 1;
              final newVersion = serverVer > currentVer
                  ? serverVer + 1
                  : currentVer + 1;
              final now = DateTime.now().millisecondsSinceEpoch;

              localJson['version'] = newVersion;
              localJson['updated_at'] = now;
              localJson['has_conflict'] = 0;
              localJson.remove('conflict_data');
              localJson.remove('serverVersionData');

              await StorageService.resolveConflictLocally(
                uuid: uuid,
                table: table,
                resolvedData: localJson,
                createOplog: true,
              );

              try {
                await ApiService.resolveConflict(
                  uuid: uuid,
                  table: table,
                  resolution: 'keep_local',
                  bumpedVersion: newVersion,
                  data: localJson,
                );
              } catch (e) {
                // debugPrint(
                //     'batch resolve_conflict keep_local API failed for $uuid: $e');
              }

              successCount++;
            }
          }
        } catch (e) {
          // debugPrint('批量推荐方案失败 $itemId: $e');
        }
      }

      // Trigger sync so oplog entries get pushed to server immediately
      if (successCount > 0) {
        Future.microtask(() => StorageService.syncData(widget.username));
      }

      if (mounted) {
        _selectedConflictIds.clear();
        _isBatchMode = false;
        await _loadConflicts();
        final message = scheduleSkippedCount > 0
            ? '已应用推荐方案，成功处理 $successCount 项版本冲突；$scheduleSkippedCount 项时间冲突需单独处理'
            : '已应用推荐方案，成功处理 $successCount 项冲突';
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBarFromMessenger(
          messenger,
          SnackBar(content: Text('批量操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _isBatchApplying = false);
    }
  }

  Future<void> _resolveGhostConflict(
    dynamic item, {
    bool refresh = true,
  }) async {
    await _keepLocalAndQueueSync(item, syncNow: refresh);

    if (refresh) {
      await _loadConflicts();
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text("已强制保留本地并加入同步队列")),
        );
      }
    }
  }
}
