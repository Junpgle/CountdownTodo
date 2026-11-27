part of '../conflict_inbox_screen.dart';

extension _ConflictInboxLayoutExt on _ConflictInboxScreenState {
  Widget _buildModernBackground(bool isDark) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    );
  }

  Widget _buildModernAppBar(bool isDark) {
    final compactActions = MediaQuery.sizeOf(context).width < 380;
    final actionGap = compactActions ? 4.0 : 12.0;
    return ClipRect(
      child: Stack(
        children: [
          const Positioned.fill(child: FloatingGlassTopBarBackground()),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (_isBatchMode) ...[
                  _buildAppBarAction(
                    onTap: () => _mutateState(() {
                      _isBatchMode = false;
                      _selectedConflictIds.clear();
                    }),
                    icon: Icons.close_rounded,
                    tooltip: '取消批量模式',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已选择 ${_selectedConflictIds.length} 项',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.blueGrey.shade900,
                      ),
                    ),
                  ),
                ] else ...[
                  _buildAppBarAction(
                    onTap: () => Navigator.of(context).pop(),
                    icon: Icons.arrow_back_rounded,
                    tooltip: '返回',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '冲突对齐中心',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : Colors.blueGrey.shade900,
                          ),
                        ),
                        Text(
                          'Uni-Sync 4.0 智能数据对齐引擎',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white54
                                : Colors.blueGrey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(width: compactActions ? 8 : 16),
                if (!_isBatchMode) ...[
                  _buildAppBarAction(
                    icon: Icons.smart_toy_outlined,
                    onTap: _openAiAssistant,
                    tooltip: 'AI冲突助手',
                  ),
                  SizedBox(width: actionGap),
                  _buildAppBarAction(
                    icon: _isScanning ? null : Icons.radar_rounded,
                    loading: _isScanning,
                    onTap: _isScanning ? null : _scanAllTodoConflicts,
                    tooltip: '扫描全部冲突',
                  ),
                  SizedBox(width: actionGap),
                  _buildAppBarAction(
                    icon: Icons.refresh_rounded,
                    onTap: _loadConflicts,
                    tooltip: '刷新列表',
                  ),
                  SizedBox(width: actionGap),
                  _buildAppBarAction(
                    icon: Icons.help_outline_rounded,
                    onTap: _showConflictHelp,
                    tooltip: '查看帮助',
                  ),
                  SizedBox(width: actionGap),
                  _buildAppBarAction(
                    icon: Icons.checklist_rounded,
                    onTap: _conflictItems.isNotEmpty
                        ? () => _mutateState(() => _isBatchMode = true)
                        : null,
                    tooltip: '批量管理',
                  ),
                ] else ...[
                  _buildAppBarAction(
                    icon: Icons.select_all_rounded,
                    onTap:
                        _selectedConflictIds.length ==
                            _visibleConflictItems.length
                        ? () => _mutateState(() => _selectedConflictIds.clear())
                        : () => _mutateState(() {
                            _selectedConflictIds.clear();
                            for (final item in _visibleConflictItems) {
                              _selectedConflictIds.add(_getConflictId(item));
                            }
                          }),
                    tooltip:
                        _selectedConflictIds.length ==
                            _visibleConflictItems.length
                        ? '取消全选'
                        : '全选',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarAction({
    IconData? icon,
    bool loading = false,
    VoidCallback? onTap,
    required String tooltip,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context).width < 380 ? 40.0 : 44.0;
    final content = Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 20),
        ),
      ),
    );

    return FloatingGlassAppBarAction(
      size: size,
      borderRadius: size / 2,
      tint: colorScheme.surface.withValues(alpha: 0.24),
      haloColor: colorScheme.primary,
      child: content,
    );
  }

  Future<void> _openAiAssistant() async {
    try {
      final results = await Future.wait<dynamic>([
        StorageService.getTodos(widget.username),
        StorageService.getTodoGroups(widget.username),
        CourseService.getAllCourses(widget.username),
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getRecords(),
      ]);
      if (!mounted) return;
      await AiTodoChatLauncher.open(
        context,
        username: widget.username,
        todos: (results[0] as List<TodoItem>)
            .where((t) => !t.isDeleted)
            .toList(),
        todoGroups: (results[1] as List<TodoGroup>)
            .where((g) => !g.isDeleted)
            .toList(),
        courses: (results[2] as List<CourseItem>)
            .where((c) => !c.isDeleted)
            .toList(),
        timeLogs: (results[3] as List<TimeLogItem>)
            .where((l) => !l.isDeleted)
            .toList(),
        pomodoroRecords: (results[4] as List<PomodoroRecord>)
            .where((r) => !r.isDeleted)
            .toList(),
        conflicts: _buildAiConflictContext(),
        onFixedSchedulesChanged: (_) {
          unawaited(_loadConflicts());
        },
        onTodosBatchAction:
            (
              inserted,
              updated, {
              expectedTodoBaselines,
              expectedSeriesMembership,
            }) async {
              final allTodos = await StorageService.getTodos(widget.username);
              final merged = AiTodoActionExecutor.mergeTodoUpdates(
                allTodos,
                inserted,
                updated,
              );
              await StorageService.saveTodos(
                widget.username,
                merged,
                expectedTodoBaselines: expectedTodoBaselines,
                expectedSeriesMembership: expectedSeriesMembership,
              );
              try {
                await _loadConflicts();
              } catch (error) {
                debugPrint(
                  'AI todo conflict refresh failed after save: $error',
                );
              }
            },
      );
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('打开AI助手失败: $e')),
        );
      }
    }
  }

  List<ConflictInfo> _buildAiConflictContext() {
    final conflicts = <ConflictInfo>[...?widget.syncConflicts];
    for (final item in _conflictItems) {
      if (item is TodoItem && item.serverVersionData != null) {
        conflicts.add(
          ConflictInfo(
            type: item.serverVersionData!['type']?.toString() ?? 'todo',
            item: item.toJson(),
            conflictWith: item.serverVersionData!,
          ),
        );
      } else if (item is TodoGroup && item.conflictData != null) {
        conflicts.add(
          ConflictInfo(
            type: 'group',
            item: item.toJson(),
            conflictWith: item.conflictData!,
          ),
        );
      } else if (item is CountdownItem && item.conflictData != null) {
        conflicts.add(
          ConflictInfo(
            type: 'countdown',
            item: item.toJson(),
            conflictWith: item.conflictData!,
          ),
        );
      } else if (item is HabitGoal && item.conflictData != null) {
        conflicts.add(
          ConflictInfo(
            type: 'habit_goals',
            item: item.toJson(),
            conflictWith: item.conflictData!,
          ),
        );
      } else if (item is HabitGoalRuleRevision && item.conflictData != null) {
        conflicts.add(
          ConflictInfo(
            type: 'habit_goal_rule_revisions',
            item: item.toJson(),
            conflictWith: item.conflictData!,
          ),
        );
      }
    }
    return conflicts;
  }

  Widget _buildWideLayout(bool isDark) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              // 左栏：列表
              SizedBox(width: 380, child: _buildConflictList(isDark)),
              // 分割线
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? Colors.white10 : Colors.black12,
              ),
              // 右栏：详情
              Expanded(child: _buildDetailPane(isDark)),
            ],
          ),
        ),
        if (_isBatchMode && _selectedConflictIds.isNotEmpty)
          _buildBatchActionBarWide(isDark),
      ],
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return Column(
      children: [
        Expanded(child: _buildConflictList(isDark)),
        if (_isBatchMode && _selectedConflictIds.isNotEmpty)
          _buildBatchActionBar(isDark),
      ],
    );
  }

  Widget _buildConflictList(bool isDark) {
    if (_isLoading) return _buildSkeleton();
    if (_visibleConflictItems.isEmpty) return _buildEmptyState();

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final id = key.value;
          final index = _visibleConflictItems.indexWhere(
            (item) => _itemId(item) == id,
          );
          return index != -1 ? index : null;
        }
        return null;
      },
      itemCount: _visibleConflictItems.length,
      itemBuilder: (context, index) {
        final item = _visibleConflictItems[index];
        final isSelected = _selectedItem == item;
        final id = _itemId(item) ?? '$index';
        return Padding(
          key: ValueKey<String>(id),
          padding: const EdgeInsets.only(bottom: 12),
          child: RepaintBoundary(
            child: _buildModernConflictCard(item, isSelected, isDark),
          ),
        );
      },
    );
  }

  Widget _buildDetailPane(bool isDark) {
    if (_selectedItem == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_motion_rounded,
              size: 64,
              color: isDark ? Colors.white10 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              '请选择一个冲突项进行对齐',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.black38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // 根据选中的项目类型渲染不同的详情视图
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          if (animation.value <= 0.001) return const SizedBox.shrink();
          if (animation.value >= 0.999) return child!;
          return FadeTransition(opacity: animation, child: child);
        },
      ),
      child: Container(
        key: ValueKey(_itemId(_selectedItem)),
        child: _buildEmbeddedResolutionUI(_selectedItem, isDark),
      ),
    );
  }

  Widget _buildLocalScheduleDetail(dynamic item, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailHeader(
            icon: Icons.schedule_rounded,
            title: '时间冲突排查',
            subtitle: '该待办与已有日程在时间上存在重叠，请调整其时间。',
            isDark: isDark,
          ),
          const SizedBox(height: 32),
          _buildLocalScheduleCard(item, isDark),
        ],
      ),
    );
  }

  Widget _buildMissingSnapshotDetail(dynamic item, bool isDark) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailHeader(
              icon: Icons.auto_fix_high_rounded,
              title: '云端快照同步异常',
              subtitle: '本地标记了冲突但未找到云端备份，可能是同步链路中断导致。建议执行一键修复。',
              isDark: isDark,
              center: true,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: () => _batchResolveGhostConflicts([item]),
                icon: const Icon(Icons.flash_on_rounded),
                label: const Text(
                  '立即修复并同步',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    bool center = false,
  }) {
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.blueGrey.shade900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: isDark ? Colors.white54 : Colors.blueGrey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmbeddedResolutionUI(dynamic item, bool isDark) {
    if (_isLocalScheduleConflict(item)) {
      return _buildLocalScheduleDetail(item, isDark);
    }

    final serverVersion = _findServerVersion(item);
    if (serverVersion == null || serverVersion.isEmpty) {
      return _buildMissingSnapshotDetail(item, isDark);
    }

    final localJson = _itemToJson(item);
    final table = _resolveTable(item);

    return _ConflictResolutionSheet(
      localItem: localJson,
      serverItem: serverVersion,
      table: table,
      username: widget.username,
      isEmbedded: true,
      onResolved: () {
        _mutateState(() => _selectedItem = null);
        _loadConflicts();
      },
    );
  }

  Widget _buildSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.05);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemExtent: 176.0,
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        height: 160,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
