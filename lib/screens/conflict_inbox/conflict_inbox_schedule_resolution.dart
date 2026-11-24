part of '../conflict_inbox_screen.dart';

extension _ConflictInboxScheduleExt on _ConflictInboxScreenState {
  Future<void> _showLocalScheduleConflict(dynamic item) async {
    final data = _conflictData(item) ?? {};
    final peers =
        (data['conflict_with'] is List
                ? data['conflict_with'] as List
                : const [])
            .where(
              (p) =>
                  p is Map &&
                  !ConflictVisibilityService.isAllDayTodoData(
                    Map<String, dynamic>.from(p),
                  ),
            )
            .toList();

    // 如果过滤掉全天任务后不再冲突，则不显示详情（或提示已解决）
    if (peers.isEmpty && (item is TodoItem)) {
      // 这里的逻辑可以根据需要调整，目前保持能打开但列表为空
    }

    final allTodos = item is TodoItem
        ? await StorageService.getTodos(widget.username, includeDeleted: true)
        : const <TodoItem>[];
    if (!mounted) return;
    final recommendedWindow = item is TodoItem
        ? _suggestPreferredWindow(item, peers)
        : null;
    final recommendedLabel = item is TodoItem && recommendedWindow != null
        ? _buildRecommendedResolutionLabel(item, recommendedWindow)
        : null;
    final recommendedUpdates = item is TodoItem && recommendedWindow != null
        ? <String, ({DateTime start, DateTime end})>{
            item.id: (
              start: recommendedWindow.start,
              end: recommendedWindow.end,
            ),
          }
        : <String, ({DateTime start, DateTime end})>{};
    final groupUpdates = item is TodoItem
        ? _buildGroupScheduleUpdates(item, peers, allTodos)
        : <String, ({DateTime start, DateTime end})>{};
    var selectedMode = item is TodoItem && recommendedUpdates.isNotEmpty
        ? _ScheduleResolutionMode.recommend
        : _ScheduleResolutionMode.manual;
    var selectedIdToEdit = _itemId(item);

    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedUpdates = switch (selectedMode) {
            _ScheduleResolutionMode.recommend => recommendedUpdates,
            _ScheduleResolutionMode.group => groupUpdates,
            _ScheduleResolutionMode.manual =>
              <String, ({DateTime start, DateTime end})>{},
          };
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
            ),
            child: OptionalLiquidGlassSheet(
              topRadius: 20,
              padding: const EdgeInsets.all(20),
              fallbackDecoration: BoxDecoration(
                color: Theme.of(sheetContext).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
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
                      '时间重叠',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _relationLabel(item),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedMode == _ScheduleResolutionMode.manual
                          ? '手动模式：点击上方卡片可选中任一冲突任务进行编辑。'
                          : '先横向查看当前任务和冲突任务，再选择处理方式。执行前会先给出预览。',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (recommendedLabel != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.auto_fix_high_rounded,
                              size: 18,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                recommendedLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildHorizontalConflictGallery(
                      data,
                      peers,
                      selectedUpdates,
                      mode: selectedMode,
                      selectedIdToEdit: selectedIdToEdit,
                      onSelect: (id) =>
                          setSheetState(() => selectedIdToEdit = id),
                    ),
                    const SizedBox(height: 16),
                    if (item is TodoItem) ...[
                      _buildResolutionModeSelector(
                        selectedMode: selectedMode,
                        recommendedEnabled: recommendedUpdates.isNotEmpty,
                        groupEnabled: groupUpdates.isNotEmpty,
                        onChanged: (mode) =>
                            setSheetState(() => selectedMode = mode),
                      ),
                      if (_isApplyingScheduleFix) ...[
                        const SizedBox(height: 12),
                        const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isApplyingScheduleFix
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      Navigator.pop(sheetContext);
                                      await StorageService.ignoreLocalScheduleConflict(
                                        widget.username,
                                        item,
                                      );
                                      await _loadConflicts();
                                      if (!mounted) return;
                                      AppSnackBars.showSnackBarFromMessenger(
                                        messenger,
                                        const SnackBar(
                                          content: Text('已保留现有时间安排，不再提示这组冲突'),
                                        ),
                                      );
                                    },
                              child: const Text('保留现状'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  _isApplyingScheduleFix ||
                                      (selectedMode !=
                                              _ScheduleResolutionMode.manual &&
                                          selectedUpdates.isEmpty)
                                  ? null
                                  : () async {
                                      if (selectedMode ==
                                          _ScheduleResolutionMode.manual) {
                                        final target = allTodos
                                            .cast<TodoItem?>()
                                            .firstWhere(
                                              (todo) =>
                                                  todo?.id == selectedIdToEdit,
                                              orElse: () => null,
                                            );
                                        if (target != null) {
                                          Navigator.pop(sheetContext);
                                          await _openTodoEditor(target);
                                        }
                                        return;
                                      }
                                      if (selectedUpdates.isEmpty) return;
                                      final successMessage =
                                          selectedMode ==
                                              _ScheduleResolutionMode.recommend
                                          ? '已按预览结果调整当前任务'
                                          : '已按预览结果顺排冲突链';
                                      await _persistResolvedTodos(
                                        selectedUpdates,
                                        successMessage: successMessage,
                                        popContext: sheetContext,
                                      );
                                    },
                              child: Text(
                                selectedMode == _ScheduleResolutionMode.manual
                                    ? '进入编辑'
                                    : '确认应用',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('知道了'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalConflictGallery(
    Map<String, dynamic> data,
    List peers,
    Map<String, ({DateTime start, DateTime end})> updates, {
    required _ScheduleResolutionMode mode,
    String? selectedIdToEdit,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "冲突对比 (横向滑动)",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 145,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildScheduleConflictCard(
                Map<String, dynamic>.from(data)..['is_primary'] = true,
                updates,
                mode: mode,
                isSelectedForEdit: selectedIdToEdit == _itemIdFromData(data),
                onSelect: onSelect,
              ),
              if (peers.isEmpty)
                _buildScheduleConflictEmpty()
              else
                ...peers.map<Widget>((peer) {
                  final Map<String, dynamic> peerMap = peer is Map
                      ? Map<String, dynamic>.from(peer)
                      : <String, dynamic>{};
                  final peerId = _itemIdFromData(peerMap);
                  return _buildScheduleConflictCard(
                    peerMap,
                    updates,
                    mode: mode,
                    isSelectedForEdit:
                        peerId != null && selectedIdToEdit == peerId,
                    onSelect: onSelect,
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleConflictEmpty() {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: const Center(
        child: Text(
          "无其他冲突对象",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildScheduleConflictCard(
    Map<String, dynamic> data,
    Map<String, ({DateTime start, DateTime end})> updates, {
    required _ScheduleResolutionMode mode,
    bool isSelectedForEdit = false,
    required ValueChanged<String> onSelect,
  }) {
    final isPrimary = data['is_primary'] == true;
    final id = _itemIdFromData(data);
    final update = id != null ? updates[id] : null;
    final isManualMode = mode == _ScheduleResolutionMode.manual;

    final title = _itemTitle(data);
    final start = _parseMs(
      data['start_time'] ??
          data['startTime'] ??
          data['created_date'] ??
          data['createdDate'],
    );
    final end = _parseMs(
      data['end_time'] ??
          data['endTime'] ??
          data['due_date'] ??
          data['dueDate'],
    );

    final sf = _conflictInboxDateFormat('HH:mm');
    final originalTime = start > 0 && end > 0
        ? '${sf.format(DateTime.fromMillisecondsSinceEpoch(start))} ~ ${sf.format(DateTime.fromMillisecondsSinceEpoch(end))}'
        : '时间未知';

    final resolvedKey = id != null
        ? ValueKey<String>('schedule_conflict_$id')
        : null;
    return RepaintBoundary(
      key: resolvedKey,
      child: GestureDetector(
        onTap: isManualMode && id != null ? () => onSelect(id) : null,
        child: OptionalLiquidGlassCard(
          width: 190,
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.all(12),
          borderRadius: 14,
          highContrast: true,
          tint: isSelectedForEdit
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
              : (isPrimary
                    ? Colors.orangeAccent.withValues(alpha: 0.16)
                    : null),
          fallbackDecoration: BoxDecoration(
            // 主题化取色，修复暗色模式下普通日程卡仍为纯白的问题。
            color: isSelectedForEdit
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : (isPrimary
                      ? Colors.orangeAccent.withValues(alpha: 0.08)
                      : Theme.of(context).colorScheme.surface),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelectedForEdit
                  ? Theme.of(context).colorScheme.primary
                  : (isPrimary
                        ? Colors.orangeAccent.withValues(alpha: 0.25)
                        : Colors.grey.withValues(alpha: 0.15)),
              width: isSelectedForEdit || isPrimary ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isSelectedForEdit
                        ? Icons.check_circle_rounded
                        : (isPrimary
                              ? Icons.push_pin_rounded
                              : Icons.schedule_rounded),
                    size: 14,
                    color: isSelectedForEdit
                        ? Theme.of(context).colorScheme.primary
                        : (isPrimary ? Colors.orangeAccent : Colors.grey),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isPrimary ? "当前任务" : "冲突任务",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelectedForEdit
                          ? Theme.of(context).colorScheme.primary
                          : (isPrimary ? Colors.orangeAccent : Colors.grey),
                    ),
                  ),
                  if (update != null) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "待调",
                        style: TextStyle(
                          fontSize: 9,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              _buildMiniInfoChip(
                _scheduleScopeLabel(data),
                isPrimary
                    ? Colors.orangeAccent
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 6),
              if (update == null)
                Text(
                  originalTime,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelectedForEdit
                        ? Theme.of(context).colorScheme.primary
                        : (isPrimary
                              ? Colors.orangeAccent
                              : Colors.grey.shade600),
                    fontWeight: isSelectedForEdit || isPrimary
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      originalTime,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                        decoration: TextDecoration.lineThrough,
                        height: 1.1,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_right_alt_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${sf.format(update.start)}~${sf.format(update.end)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResolutionModeSelector({
    required _ScheduleResolutionMode selectedMode,
    required bool recommendedEnabled,
    required bool groupEnabled,
    required ValueChanged<_ScheduleResolutionMode> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "处理方式",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildModeChip(
              mode: _ScheduleResolutionMode.recommend,
              label: "推荐调整",
              icon: Icons.auto_awesome_rounded,
              selected: selectedMode == _ScheduleResolutionMode.recommend,
              enabled: recommendedEnabled,
              onTap: () => onChanged(_ScheduleResolutionMode.recommend),
            ),
            const SizedBox(width: 10),
            _buildModeChip(
              mode: _ScheduleResolutionMode.group,
              label: "整组顺排",
              icon: Icons.account_tree_rounded,
              selected: selectedMode == _ScheduleResolutionMode.group,
              enabled: groupEnabled,
              onTap: () => onChanged(_ScheduleResolutionMode.group),
            ),
            const SizedBox(width: 10),
            _buildModeChip(
              mode: _ScheduleResolutionMode.manual,
              label: "手动编辑",
              icon: Icons.edit_calendar_rounded,
              selected: selectedMode == _ScheduleResolutionMode.manual,
              enabled: true,
              onTap: () => onChanged(_ScheduleResolutionMode.manual),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeChip({
    required _ScheduleResolutionMode mode,
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : (enabled ? Colors.grey : Colors.grey.shade300);
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.2),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _parseMs(dynamic value) {
    return JsonValueParser.toInt(value);
  }

  DateTimeRange? _suggestPreferredWindow(TodoItem item, List peers) {
    final startMs = item.createdDate ?? item.createdAt;
    final endMs = item.dueDate?.millisecondsSinceEpoch ?? 0;
    if (startMs <= 0 || endMs <= 0 || endMs <= startMs) return null;

    final durationMs = endMs - startMs;
    var candidateStart = startMs;
    var candidateEnd = candidateStart + durationMs;
    final busyRanges =
        peers
            .whereType<Map>()
            .map((peer) => Map<String, dynamic>.from(peer))
            .map(
              (peer) => (
                start: _parseMs(peer['start_time'] ?? peer['startTime']),
                end: _parseMs(peer['end_time'] ?? peer['endTime']),
              ),
            )
            .where((range) => range.start > 0 && range.end > range.start)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    for (final range in busyRanges) {
      if (!_rangesOverlap(
        candidateStart,
        candidateEnd,
        range.start,
        range.end,
      )) {
        continue;
      }
      candidateStart = range.end + const Duration(minutes: 5).inMilliseconds;
      candidateEnd = candidateStart + durationMs;
    }

    if (candidateStart == startMs) return null;
    return DateTimeRange(
      start: DateTime.fromMillisecondsSinceEpoch(candidateStart),
      end: DateTime.fromMillisecondsSinceEpoch(candidateEnd),
    );
  }

  String _buildRecommendedResolutionLabel(
    TodoItem item,
    DateTimeRange recommendedWindow,
  ) {
    final startMs = item.createdDate ?? item.createdAt;
    final endMs = item.dueDate?.millisecondsSinceEpoch ?? 0;
    final durationMinutes = startMs > 0 && endMs > startMs
        ? ((endMs - startMs) / const Duration(minutes: 1).inMilliseconds)
              .round()
        : 0;
    final shiftedMinutes =
        ((recommendedWindow.start.millisecondsSinceEpoch - startMs) /
                const Duration(minutes: 1).inMilliseconds)
            .round();
    final startDateFormat = _conflictInboxDateFormat('MM-dd HH:mm');
    final endTimeFormat = _conflictInboxDateFormat('HH:mm');
    return '推荐：仅移动开始时间，保留 $durationMinutes 分钟时长。新时间为 '
        '${startDateFormat.format(recommendedWindow.start)} ~ '
        '${endTimeFormat.format(recommendedWindow.end)}'
        '${shiftedMinutes > 0 ? '，整体后移 $shiftedMinutes 分钟' : ''}。';
  }

  bool _rangesOverlap(int startA, int endA, int startB, int endB) {
    return startA < endB && endA > startB;
  }

  Map<String, ({DateTime start, DateTime end})> _buildGroupScheduleUpdates(
    TodoItem seed,
    List peers,
    List<TodoItem> allTodos,
  ) {
    final conflictChain = _buildDirectConflictItems(seed, peers, allTodos);
    if (conflictChain.length <= 1) return {};

    conflictChain.sort((a, b) {
      final byStart = _todoStartMs(a).compareTo(_todoStartMs(b));
      if (byStart != 0) return byStart;
      return _todoEndMs(a).compareTo(_todoEndMs(b));
    });

    final updates = <String, ({DateTime start, DateTime end})>{};
    var anchorEnd = 0;
    for (var i = 0; i < conflictChain.length; i++) {
      final todo = conflictChain[i];
      final startMs = _todoStartMs(todo);
      final endMs = _todoEndMs(todo);
      if (startMs <= 0 || endMs <= startMs) continue;

      final durationMs = endMs - startMs;
      if (i == 0) {
        anchorEnd = endMs;
        continue;
      }

      final minStart = anchorEnd + const Duration(minutes: 5).inMilliseconds;
      if (startMs < minStart) {
        updates[todo.id] = (
          start: DateTime.fromMillisecondsSinceEpoch(minStart),
          end: DateTime.fromMillisecondsSinceEpoch(minStart + durationMs),
        );
        anchorEnd = minStart + durationMs;
      } else {
        anchorEnd = endMs;
      }
    }
    return updates;
  }

  List<TodoItem> _buildDirectConflictItems(
    TodoItem seed,
    List peers,
    List<TodoItem> allTodos,
  ) {
    final seedStart = _todoStartMs(seed);
    final matched = <TodoItem>[seed];

    for (final peer in peers.whereType<Map>()) {
      final peerData = Map<String, dynamic>.from(peer);
      final peerId = _itemIdFromData(peerData);
      final peerStart = _parseMs(
        peerData['start_time'] ??
            peerData['startTime'] ??
            peerData['created_date'] ??
            peerData['createdDate'],
      );
      final peerEnd = _parseMs(
        peerData['end_time'] ??
            peerData['endTime'] ??
            peerData['due_date'] ??
            peerData['dueDate'],
      );

      final todo = allTodos.cast<TodoItem?>().firstWhere(
        (candidate) =>
            candidate != null &&
            !candidate.isDeleted &&
            !candidate.isAllDay &&
            !ConflictVisibilityService.isAllDayTodo(candidate) &&
            _todoEndMs(candidate) > _todoStartMs(candidate) &&
            _isSameLocalDayMs(_todoStartMs(candidate), seedStart) &&
            ((peerId != null && candidate.id == peerId) ||
                (_itemTitle(peerData) == candidate.title &&
                    _todoStartMs(candidate) == peerStart &&
                    _todoEndMs(candidate) == peerEnd)),
        orElse: () => null,
      );
      if (todo != null && !matched.any((existing) => existing.id == todo.id)) {
        matched.add(todo);
      }
    }

    return matched
        .where((todo) => _isSameLocalDayMs(_todoStartMs(todo), seedStart))
        .toList();
  }

  bool _isSameLocalDayMs(int leftMs, int rightMs) {
    final left = DateTime.fromMillisecondsSinceEpoch(leftMs);
    final right = DateTime.fromMillisecondsSinceEpoch(rightMs);
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String? _itemIdFromData(Map<String, dynamic> data) {
    return (data['uuid'] ?? data['id'] ?? data['id_todo'])?.toString();
  }

  int _todoStartMs(TodoItem item) => item.createdDate ?? item.createdAt;

  int _todoEndMs(TodoItem item) => item.dueDate?.millisecondsSinceEpoch ?? 0;

  Widget _buildMiniInfoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _openTodoEditor(TodoItem item) async {
    final allTodos = await StorageService.getTodos(
      widget.username,
      includeDeleted: true,
    );
    final allGroups = await StorageService.getTodoGroups(
      widget.username,
      includeDeleted: true,
    );
    final target = allTodos.cast<TodoItem?>().firstWhere(
      (todo) => todo?.id == item.id,
      orElse: () => null,
    );
    if (!mounted || target == null) return;

    final changed = await Navigator.push<bool>(
      context,
      PageTransitions.material(
        builder: (_) => TodoEditScreen(
          todo: target,
          todos: allTodos,
          onTodosChanged: (updatedTodos) async {
            await StorageService.saveTodos(widget.username, updatedTodos);
          },
          onEditorSave:
              (
                updatedTodos,
                baselines, {
                expectedSeriesMembership,
                expectedFixedScheduleTodoIds,
                expectedFixedScheduleBaselines,
              }) => TodoEditorSaveService.save(
                username: widget.username,
                changedTodos: updatedTodos,
                baselines: baselines,
                expectedSeriesMembership: expectedSeriesMembership,
                expectedFixedScheduleTodoIds: expectedFixedScheduleTodoIds,
                expectedFixedScheduleBaselines: expectedFixedScheduleBaselines,
              ),
          onEditorGroupsSave: (updatedGroups, baselines) =>
              TodoEditorSaveService.saveGroups(
                username: widget.username,
                changedGroups: updatedGroups,
                baselines: baselines,
              ),
          todoGroups: allGroups,
          onGroupsChanged: (updatedGroups) async {
            await StorageService.saveTodoGroups(widget.username, updatedGroups);
          },
          username: widget.username,
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      await StorageService.syncData(widget.username);
    }
    await _loadConflicts();
  }

  Future<void> _persistResolvedTodos(
    Map<String, ({DateTime start, DateTime end})> updates, {
    required String successMessage,
    BuildContext? popContext,
  }) async {
    if (updates.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    _mutateState(() => _isApplyingScheduleFix = true);
    try {
      final allTodos = await StorageService.getTodos(
        widget.username,
        includeDeleted: true,
      );
      var appliedCount = 0;
      for (final todo in allTodos) {
        final update = updates[todo.id];
        if (update == null) continue;
        todo.createdDate = update.start.millisecondsSinceEpoch;
        todo.dueDate = update.end;
        todo.markAsChanged();
        appliedCount++;
      }
      if (appliedCount == 0) return;
      await StorageService.saveTodos(widget.username, allTodos);

      if (appliedCount > 0) {
        Future.microtask(() => StorageService.syncData(widget.username));
      }

      if (!mounted) return;
      if (popContext != null && popContext.mounted) {
        Navigator.pop(popContext);
      } else if (mounted) {
        Navigator.pop(context);
      }
      AppSnackBars.showSnackBarFromMessenger(
        messenger,
        SnackBar(content: Text(successMessage)),
      );
      await _loadConflicts();
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showSnackBarFromMessenger(
        messenger,
        SnackBar(content: Text('处理失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) _mutateState(() => _isApplyingScheduleFix = false);
    }
  }
}
