part of '../conflict_inbox_screen.dart';

extension _ConflictInboxCardsExt on _ConflictInboxScreenState {
  Widget _buildModernConflictCard(dynamic item, bool isSelected, bool isDark) {
    String title = "";
    if (item is TodoItem) {
      title = item.title;
    } else if (item is TodoGroup) {
      title = item.name;
    } else if (item is CountdownItem) {
      title = item.title;
    } else if (item is HabitGoal) {
      title = '习惯目标：${item.name}';
    } else if (item is HabitGoalRuleRevision) {
      title = '习惯规则（${_habitRuleLabel(item)}）';
    }

    final conflictColor = _conflictColor(item);
    final itemId = _getConflictId(item);
    final isBatchSelected = _selectedConflictIds.contains(itemId);

    return OptionalLiquidGlassCard(
      borderRadius: 12,
      clipBehavior: Clip.antiAlias,
      highContrast: true,
      tint: isSelected || isBatchSelected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
          : null,
      fallbackDecoration: BoxDecoration(
        color: isSelected || isBatchSelected
            ? (isDark
                  ? Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.15)
                  : Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.1))
            : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.white.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected || isBatchSelected
              ? Theme.of(context).colorScheme.primary
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05)),
          width: isSelected || isBatchSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isBatchMode) {
            _mutateState(() {
              if (isBatchSelected) {
                _selectedConflictIds.remove(itemId);
              } else {
                _selectedConflictIds.add(itemId);
              }
            });
          } else if (_isWide) {
            _mutateState(() => _selectedItem = item);
          } else {
            _resolveConflict(item);
          }
        },
        onLongPress: _isBatchMode
            ? null
            : () {
                _mutateState(() {
                  _isBatchMode = true;
                  _selectedConflictIds.add(itemId);
                });
              },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_isBatchMode) ...[
                Checkbox(
                  value: isBatchSelected,
                  onChanged: (value) {
                    _mutateState(() {
                      if (value == true) {
                        _selectedConflictIds.add(itemId);
                      } else {
                        _selectedConflictIds.remove(itemId);
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: conflictColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected || isBatchSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isDark
                                  ? Colors.white
                                  : Colors.blueGrey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildMiniBadge(
                          _conflictLabel(item),
                          conflictColor.withValues(alpha: 0.1),
                          conflictColor,
                        ),
                        _buildMiniBadge(
                          _relationLabel(item),
                          Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.1),
                          Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _habitRuleLabel(HabitGoalRuleRevision rule) {
    final target = rule.targetValue;
    final unit = rule.unit;
    if (target > 0) {
      return unit.isNotEmpty ? '$target $unit/次' : '$target/次';
    }
    return '规则 v${rule.version}';
  }

  Widget _buildMiniBadge(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildBatchActionBar(bool isDark) {
    return FloatingGlassControl(
      height: _isBatchApplying ? 120 : 96,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      borderRadius: 28,
      mobilePortraitOnly: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('推荐方案'),
                    onPressed: _isBatchApplying ? null : _batchApplyRecommended,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.phone_android_rounded, size: 18),
                    label: const Text('保留本地'),
                    onPressed: _isBatchApplying ? null : _batchKeepLocal,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.cloud_done_rounded, size: 18),
                    label: const Text('使用服务器'),
                    onPressed: _isBatchApplying ? null : _batchAcceptServer,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_isBatchApplying) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBatchActionBarWide(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '已选择 ${_selectedConflictIds.length} 项冲突',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('推荐方案'),
                onPressed: _isBatchApplying ? null : _batchApplyRecommended,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.phone_android_rounded, size: 18),
                label: const Text('保留本地'),
                onPressed: _isBatchApplying ? null : _batchKeepLocal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.cloud_done_rounded, size: 18),
                label: const Text('使用服务器'),
                onPressed: _isBatchApplying ? null : _batchAcceptServer,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          if (_isBatchApplying) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildScanProgressBanner() {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: StorageService.conflictScanNotifier,
      builder: (context, scanState, _) {
        final isScanning = scanState['isScanning'] == true;
        if (!isScanning) return const SizedBox.shrink();
        final progress = (scanState['progress'] as int?) ?? 0;
        final current = (scanState['current'] as int?) ?? 0;
        final total = (scanState['total'] as int?) ?? 0;
        final message = scanState['message']?.toString() ?? '正在扫描冲突';
        return Container(
          margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.orangeAccent.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      size: 20,
                      color: Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '已扫描 $current / $total',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$progress%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress <= 0 ? null : progress / 100,
                  minHeight: 8,
                  backgroundColor: Colors.orangeAccent.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.orangeAccent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGhostConflictBanner() {
    final ghostItems = _ghostConflictItems;

    if (ghostItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade400, Colors.pink.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "发现 ${ghostItems.length} 项损坏的冲突（无云端快照）",
              style: const TextStyle(
                fontSize: 13,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _batchResolveGhostConflicts(ghostItems),
            child: const Text("一键修复"),
          ),
        ],
      ),
    );
  }

  Future<void> _batchResolveGhostConflicts(List<dynamic> items) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("一键修复"),
        content: Text("将保留这 ${items.length} 项任务，只清除本地损坏的冲突标记。确认继续？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("确认修复"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    _mutateState(() => _isLoading = true);

    try {
      // 1. 一次性获取所有数据源
      final results = await Future.wait([
        StorageService.getTodos(widget.username, includeDeleted: true),
        StorageService.getTodoGroups(widget.username, includeDeleted: true),
        StorageService.getCountdowns(widget.username, includeDeleted: true),
      ]);

      final allTodos = results[0] as List<TodoItem>;
      final allGroups = results[1] as List<TodoGroup>;
      final allCountdowns = results[2] as List<CountdownItem>;

      bool todosChanged = false;
      bool groupsChanged = false;
      bool countdownsChanged = false;

      final todoIds = <String>{};
      final groupIds = <String>{};
      final countdownIds = <String>{};
      for (final ghost in items) {
        final id = _itemId(ghost);
        if (id == null) continue;

        if (ghost is TodoItem) {
          todoIds.add(id);
        } else if (ghost is TodoGroup) {
          groupIds.add(id);
        } else if (ghost is CountdownItem) {
          countdownIds.add(id);
        }
      }

      // 2. 在内存中批量处理，每种数据表只扫描一次。
      for (final todo in allTodos) {
        if (!todoIds.remove(todo.id)) continue;
        todo.hasConflict = false;
        todo.serverVersionData = null;
        todosChanged = true;
      }
      for (final group in allGroups) {
        if (!groupIds.remove(group.id)) continue;
        group.hasConflict = false;
        group.conflictData = null;
        groupsChanged = true;
      }
      for (final countdown in allCountdowns) {
        if (!countdownIds.remove(countdown.id)) continue;
        countdown.hasConflict = false;
        countdown.conflictData = null;
        countdownsChanged = true;
      }

      // 3. 批量持久化（每种类型仅写入一次）
      final saves = <Future>[];
      if (todosChanged) {
        saves.add(
          StorageService.saveTodos(
            widget.username,
            allTodos,
            sync: false,
            isSyncSource: true,
            recomputeScheduleConflicts: false,
          ),
        );
      }
      if (groupsChanged) {
        saves.add(
          StorageService.saveTodoGroups(
            widget.username,
            allGroups,
            sync: false,
            isSyncSource: true,
          ),
        );
      }
      if (countdownsChanged) {
        saves.add(
          StorageService.saveCountdowns(
            widget.username,
            allCountdowns,
            sync: false,
            isSyncSource: true,
          ),
        );
      }

      if (saves.isNotEmpty) {
        await Future.wait(saves);
        Future.microtask(() => StorageService.syncData(widget.username));
      }
    } catch (e) {
      // debugPrint("批量修复失败: $e");
    }

    // 4. 统一刷新界面
    await _loadConflicts();

    if (mounted) {
      AppSnackBars.showSnackBarFromMessenger(
        messenger,
        const SnackBar(content: Text("损坏的冲突已批量修复")),
      );
    }
  }

  Widget _buildConflictStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _buildModernStatCard(
            label: '全部冲突',
            count: _conflictItems.length,
            icon: Icons.all_inbox_rounded,
            color: Theme.of(context).colorScheme.primary,
            isSelected: _selectedFilter == _ConflictFilter.all,
            onTap: () =>
                _mutateState(() => _selectedFilter = _ConflictFilter.all),
          ),
          _buildModernStatCard(
            label: '排程冲突',
            count: _timeConflictItems.length,
            icon: Icons.schedule_rounded,
            color: Colors.orange,
            isSelected: _selectedFilter == _ConflictFilter.time,
            onTap: () =>
                _mutateState(() => _selectedFilter = _ConflictFilter.time),
          ),
          _buildModernStatCard(
            label: '内容版本',
            count: _otherConflictItems.length,
            icon: Icons.difference_rounded,
            color: Colors.indigo,
            isSelected: _selectedFilter == _ConflictFilter.other,
            onTap: () =>
                _mutateState(() => _selectedFilter = _ConflictFilter.other),
          ),
        ],
      ),
    );
  }

  Widget _buildModernStatCard({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isSelected ? color : Colors.grey),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalScheduleCard(dynamic item, bool isDark) {
    final conflictWith = _conflictData(item)?['conflict_with'];
    final peers = conflictWith is List ? conflictWith : [];

    return OptionalLiquidGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(24),
      highContrast: true,
      tint: Colors.orangeAccent.withValues(alpha: 0.16),
      fallbackDecoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "受影响的项目",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildScheduleItemRow(item, isMain: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Icon(
              Icons.link_rounded,
              color: Colors.orangeAccent,
              size: 20,
            ),
          ),
          ...peers.map((p) => _buildScheduleItemRow(p)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _resolveConflict(item),
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text(
                "进入时间对齐助手",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleItemRow(dynamic data, {bool isMain = false}) {
    final Map<String, dynamic> map = data is Map
        ? Map<String, dynamic>.from(data)
        : (data as TodoItem).toJson();
    final title = map['content'] ?? map['title'] ?? '未命名任务';
    final start = _parseMs(
      map['created_date'] ??
          map['createdDate'] ??
          map['start_time'] ??
          map['startTime'],
    );
    final end = _parseMs(
      map['due_date'] ?? map['dueDate'] ?? map['end_time'] ?? map['endTime'],
    );
    final timeFormat = _conflictInboxDateFormat('HH:mm');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMain
            ? Colors.orangeAccent.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMain
              ? Colors.orangeAccent.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isMain ? Icons.warning_amber_rounded : Icons.event_note_rounded,
            color: isMain
                ? Colors.orangeAccent
                : Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${timeFormat.format(DateTime.fromMillisecondsSinceEpoch(start))} ~ '
                  '${timeFormat.format(DateTime.fromMillisecondsSinceEpoch(end))}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showConflictHelp() {
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
            const Text(
              "什么是数据冲突？",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildHelpItem(
              Icons.devices_rounded,
              "多端编辑争议",
              "当你在不同设备上同时修改同一个任务，且系统无法判定哪个版本更新时，会标记为冲突。",
            ),
            _buildHelpItem(
              Icons.history_rounded,
              "版本回退",
              "如果你的本地版本低于云端，但你强行进行了覆盖，系统会保留云端备份并提示争议。",
            ),
            _buildHelpItem(
              Icons.sync_problem_rounded,
              "逻辑冲突",
              "如多个人同时预约了同一个时间段的日程，系统会标记该日程存在冲突。",
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("知道了"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  desc,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasAnyConflicts = _conflictItems.isNotEmpty;
    final title = hasAnyConflicts ? '当前筛选下没有冲突' : '所有数据已完全对齐';
    final subtitle = hasAnyConflicts
        ? '可以切换到“全部”或其他分类查看待处理项'
        : '目前没有任何待解决的同步冲突';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.verified_user_rounded,
            size: 80,
            color: Colors.green.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
