part of '../stats_view.dart';

extension _PomodoroStatsEditor on PomodoroStatsState {
  List<Widget> _buildTodoPickerItems(
    BuildContext dialogContext,
    List<TodoItem> sortedTodos, {
    String searchQuery = '',
  }) {
    final query = searchQuery.trim().toLowerCase();
    final matchingTodos = sortedTodos.where((todo) {
      if (query.isEmpty) return true;
      return todo.title.toLowerCase().contains(query) ||
          (todo.remark?.toLowerCase().contains(query) ?? false) ||
          _todoGroupName(todo).toLowerCase().contains(query);
    }).toList();
    final items = <Widget>[
      ListTile(
        title: const Text('自由专注（无绑定）'),
        leading: const Icon(Icons.clear),
        onTap: () => Navigator.pop(dialogContext, null),
      ),
      const Divider(),
    ];

    String? currentHeader;
    if (matchingTodos.isEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text(query.isEmpty ? '暂无可绑定的待办' : '没有找到匹配的任务')),
        ),
      );
    }
    for (final todo in matchingTodos) {
      final header = '${todo.isDone ? "已完成" : "未完成"} · ${_todoGroupName(todo)}';
      if (header != currentHeader) {
        currentHeader = header;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              header,
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      items.add(
        ListTile(
          title: Text(todo.title),
          subtitle: _todoPickerSubtitle(todo),
          leading: Icon(
            todo.isDone
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
          ),
          onTap: () => Navigator.pop(dialogContext, todo),
        ),
      );
    }
    return items;
  }

  Widget? _todoPickerSubtitle(TodoItem todo) {
    final labels = <String>[
      if (todo.recurrenceSeriesId?.isNotEmpty == true) '重复待办',
      if (todo.remark?.isNotEmpty == true) todo.remark!,
    ];
    return labels.isEmpty ? null : Text(labels.join(' · '));
  }

  List<TodoItem> _sortTodosForPicker(
    List<TodoItem> todos,
    List<TodoGroup> groups,
  ) {
    final groupIndices = <String, int>{};
    for (var index = 0; index < groups.length; index++) {
      final groupId = groups[index].id;
      if (!groupIndices.containsKey(groupId)) {
        groupIndices[groupId] = index;
      }
    }

    int groupRank(TodoItem todo) {
      final groupId = todo.groupId;
      if (groupId == null || groupId.isEmpty) return 1 << 30;
      return groupIndices[groupId] ?? (1 << 30) - 1;
    }

    int urgencyMs(TodoItem todo) {
      if (todo.dueDate != null) return todo.dueDate!.millisecondsSinceEpoch;
      if (todo.createdDate != null && todo.createdDate! > 0) {
        return todo.createdDate!;
      }
      return 1 << 62;
    }

    return List<TodoItem>.from(todos)..sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final groupCompare = groupRank(a).compareTo(groupRank(b));
      if (groupCompare != 0) return groupCompare;
      final urgencyCompare = urgencyMs(a).compareTo(urgencyMs(b));
      if (urgencyCompare != 0) return urgencyCompare;
      return a.title.compareTo(b.title);
    });
  }

  String _todoGroupName(TodoItem todo) {
    final groupId = todo.groupId;
    if (groupId == null || groupId.isEmpty) return '未分类';
    return _todoGroupNamesById[groupId] ?? '未知分类';
  }

  Future<void> _editSession(PomodoroSession session) async {
    // 使用副本进行编辑，避免直接修改原对象导致取消后数据被污染
    final editSession = PomodoroSession(
      uuid: session.uuid,
      todoUuid: session.todoUuid,
      todoTitle: session.todoTitle,
      tagUuids: List.from(session.tagUuids),
      startTime: session.startTime,
      endTime: session.endTime,
      plannedDuration: session.plannedDuration,
      actualDuration: session.actualDuration,
      status: session.status,
      deviceId: session.deviceId,
      planBlockId: session.planBlockId,
      note: session.note,
      totalPauseSeconds: session.totalPauseSeconds,
      pauseIntervals: session.pauseIntervals != null
          ? List.from(session.pauseIntervals!)
          : null,
      isDeleted: session.isDeleted,
      version: session.version,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
    );

    List<String> editTags = List.from(session.tagUuids);
    String? editTodoUuid = session.todoUuid;
    String? editTodoTitle = session.todoTitle;
    String editNote = session.note ?? '';

    await showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sd) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '编辑专注记录',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _deleteSession(session);
                        },
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    '专注开始时间',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _pomodoroStatsDateFormat('yyyy-MM-dd HH:mm:ss').format(
                      DateTime.fromMillisecondsSinceEpoch(
                        editSession.startTime,
                        isUtc: true,
                      ).toLocal(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '专注结束时间',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final currentEnd = DateTime.fromMillisecondsSinceEpoch(
                        editSession.endTime ?? editSession.startTime,
                        isUtc: true,
                      ).toLocal();
                      final pickedTime = await showAppTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(currentEnd),
                      );
                      if (pickedTime != null) {
                        final newEnd = DateTime(
                          currentEnd.year,
                          currentEnd.month,
                          currentEnd.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                        if (newEnd.millisecondsSinceEpoch <=
                            editSession.startTime) {
                          if (ctx.mounted) {
                            AppSnackBars.showSnackBar(
                              ctx,
                              const SnackBar(content: Text('结束时间必须晚于开始时间')),
                            );
                          }
                          return;
                        }
                        sd(() {
                          editSession.endTime = newEnd
                              .toUtc()
                              .millisecondsSinceEpoch;
                          final totalSeconds =
                              ((editSession.endTime! - editSession.startTime) /
                                      1000)
                                  .round();
                          editSession.actualDuration =
                              (totalSeconds -
                                      (editSession.totalPauseSeconds ?? 0))
                                  .clamp(0, totalSeconds);
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _pomodoroStatsDateFormat('HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                editSession.endTime ?? editSession.startTime,
                                isUtc: true,
                              ).toLocal(),
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit_outlined, size: 18),
                        ],
                      ),
                    ),
                  ),
                  // 暂停信息
                  if (editSession.totalPauseSeconds != null &&
                      editSession.totalPauseSeconds! > 0) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          '暂停时长',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          formatDurationChinese(editSession.totalPauseSeconds!),
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (editSession.pauseIntervals != null &&
                            editSession.pauseIntervals!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${editSession.pauseIntervals!.length} 次',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (editSession.pauseIntervals != null &&
                        editSession.pauseIntervals!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              int i = 0;
                              i < editSession.pauseIntervals!.length;
                              i++
                            ) ...[
                              if (i > 0) const SizedBox(height: 4),
                              _buildPauseIntervalRow(
                                ctx,
                                i + 1,
                                editSession.pauseIntervals![i],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    '绑定任务',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      var searchQuery = '';
                      final sortedTodos = _sortTodosForPicker(
                        collapseRecurrenceSeriesForTodoPicker(_todos),
                        _todoGroups,
                      );
                      final picked = await showAppDialog<TodoItem?>(
                        context: ctx,
                        builder: (dctx) => StatefulBuilder(
                          builder: (dctx, setDialogState) => AlertDialog(
                            title: const Text('选择任务'),
                            content: SizedBox(
                              width: double.maxFinite,
                              height:
                                  (MediaQuery.sizeOf(dctx).height -
                                      MediaQuery.viewInsetsOf(dctx).bottom) *
                                  0.55,
                              child: Column(
                                children: [
                                  TextField(
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      hintText: '搜索任务名称、备注或分组',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (value) => setDialogState(() {
                                      searchQuery = value;
                                    }),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: ListView(
                                      children: _buildTodoPickerItems(
                                        dctx,
                                        sortedTodos,
                                        searchQuery: searchQuery,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      if (picked != null) {
                        sd(() {
                          editTodoUuid = picked.id;
                          editTodoTitle = picked.title;
                        });
                      } else if (picked == null && (editTodoUuid != null)) {
                        sd(() {
                          editTodoUuid = null;
                          editTodoTitle = null;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.task_alt_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(editTodoTitle ?? '自由专注（点击选择）'),
                          const Spacer(),
                          const Icon(Icons.chevron_right, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '标签',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (_tags.isEmpty)
                    const Text('暂无标签', style: TextStyle(color: Colors.grey))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags.map((tag) {
                        final sel = editTags.contains(tag.uuid);
                        final color = AppColorUtils.parseHex(tag.color);
                        return FilterChip(
                          label: Text(
                            tag.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          selected: sel,
                          showCheckmark: false,
                          selectedColor: color.withValues(alpha: 0.2),
                          side: BorderSide(
                            color: sel ? color : Colors.grey.shade300,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onSelected: (v) => sd(() {
                            if (v) {
                              editTags.add(tag.uuid);
                            } else {
                              editTags.remove(tag.uuid);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    '备注',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final ctrl = TextEditingController(text: editNote);
                      final result = await showAppDialog<String>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: const Text('编辑备注'),
                          content: TextField(
                            controller: ctrl,
                            maxLines: 5,
                            minLines: 3,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: '记录专注的收获…',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dctx, ctrl.text),
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      );
                      if (result != null) {
                        sd(() => editNote = result);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.note_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              editNote.isEmpty ? '点击添加备注' : editNote,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: editNote.isEmpty ? Colors.grey : null,
                              ),
                            ),
                          ),
                          const Icon(Icons.edit_outlined, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final updated = PomodoroSession(
                          uuid: editSession.uuid,
                          todoUuid: editTodoUuid,
                          todoTitle: editTodoTitle,
                          tagUuids: editTags,
                          startTime: editSession.startTime,
                          endTime: editSession.endTime,
                          plannedDuration: editSession.plannedDuration,
                          actualDuration: editSession.actualDuration,
                          status: editSession.status,
                          deviceId: editSession.deviceId,
                          planBlockId: editSession.planBlockId,
                          note: editNote.isNotEmpty ? editNote : null,
                          totalPauseSeconds: editSession.totalPauseSeconds,
                          pauseIntervals: editSession.pauseIntervals,
                          isDeleted: editSession.isDeleted,
                          version: editSession.version + 1,
                          createdAt: editSession.createdAt,
                          updatedAt: DateTime.now().millisecondsSinceEpoch,
                        );
                        await PomodoroService.updateSession(updated);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) await _loadLocal();
                      },
                      child: const Text('保存'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPauseIntervalRow(
    BuildContext ctx,
    int index,
    PauseInterval interval,
  ) {
    final startStr = _pomodoroStatsDateFormat('HH:mm:ss').format(
      DateTime.fromMillisecondsSinceEpoch(
        interval.startMs,
        isUtc: true,
      ).toLocal(),
    );
    final endStr = interval.isOngoing
        ? '进行中'
        : _pomodoroStatsDateFormat('HH:mm:ss').format(
            DateTime.fromMillisecondsSinceEpoch(
              interval.endMs!,
              isUtc: true,
            ).toLocal(),
          );
    final durationStr = interval.isOngoing
        ? ''
        : formatDurationChinese(interval.durationSeconds);
    return Row(
      children: [
        Text(
          '$index.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$startStr → $endStr',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        if (durationStr.isNotEmpty) ...[
          const Spacer(),
          Text(
            durationStr,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(ctx).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _deleteSession(PomodoroSession session) async {
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条专注记录吗？'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await PomodoroService.deleteSession(session.uuid);
      _loadLocal();
    }
  }
}
