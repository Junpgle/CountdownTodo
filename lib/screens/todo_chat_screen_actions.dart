part of 'todo_chat_screen.dart';
// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatActions on _TodoChatScreenStateBase {
  String _formatTodoTimeRange(
    String? startTime,
    String? dueDate,
    bool isAllDay,
  ) {
    DateTime? start;
    DateTime? end;

    if (startTime != null && startTime.isNotEmpty) {
      start = DateTime.tryParse(startTime);
    }
    if (dueDate != null && dueDate.isNotEmpty) {
      end = DateTime.tryParse(dueDate);
    }

    if (start == null && end == null) return '未设置时间';

    String formatDateTime(DateTime dt, bool showDate, bool showTime) {
      if (showDate && showTime) {
        return DateFormat('MM/dd HH:mm').format(dt);
      } else if (showDate) {
        return DateFormat('MM/dd').format(dt);
      } else {
        return DateFormat('HH:mm').format(dt);
      }
    }

    bool sameDay(DateTime a, DateTime b) {
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    if (isAllDay) {
      if (start != null && end != null && sameDay(start, end)) {
        return '全天 ${DateFormat('MM/dd').format(start)}';
      } else if (start != null && end != null) {
        return '全天 ${DateFormat('MM/dd').format(start)} ~ ${DateFormat('MM/dd').format(end)}';
      } else if (start != null) {
        return '全天 ${DateFormat('MM/dd').format(start)}';
      } else if (end != null) {
        return '全天 ${DateFormat('MM/dd').format(end)}';
      }
    }

    if (start != null && end != null) {
      if (sameDay(start, end)) {
        return '${DateFormat('MM/dd').format(start)} ${DateFormat('HH:mm').format(start)} ~ ${DateFormat('HH:mm').format(end)}';
      } else {
        return '${DateFormat('MM/dd HH:mm').format(start)} ~ ${DateFormat('MM/dd HH:mm').format(end)}';
      }
    } else if (start != null) {
      final showTime = start.hour != 0 || start.minute != 0;
      return '开始: ${formatDateTime(start, true, showTime)}';
    } else if (end != null) {
      final showTime = end.hour != 0 || end.minute != 0;
      return '截止: ${formatDateTime(end, true, showTime)}';
    }

    return '未设置时间';
  }

  String _formatScheduleActionTime(AiTodoAction action) {
    final existing = _fixedSchedules
        .where((item) => item.id == action.scheduleId)
        .firstOrNull;
    final dateValue =
        action.hasDate ? action.date : action.date ?? existing?.date;
    final startValue = action.hasStartTime
        ? action.startTime
        : action.startTime ??
            (existing?.startTime == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(existing!.startTime!)
                    .toIso8601String());
    final endValue = action.hasDueDate
        ? action.dueDate
        : action.dueDate ??
            (existing?.endTime == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(existing!.endTime!)
                    .toIso8601String());
    final date = dateValue?.trim();
    final start = DateTime.tryParse(startValue ?? '');
    final end = DateTime.tryParse(endValue ?? '');
    final day = date?.isNotEmpty == true
        ? date!
        : start == null
            ? '日期待定'
            : DateFormat('yyyy-MM-dd').format(start);
    if (start == null) return '$day 时间待定';
    final startText = DateFormat('HH:mm').format(start);
    if (end == null) return '$day $startText（结束待定）';
    return '$day $startText-${DateFormat('HH:mm').format(end)}';
  }

  String _getTodoCurrentFolderName(String? todoId) {
    if (todoId == null) return '未知';
    final matches = widget.todos.where((t) => t['id'] == todoId);
    if (matches.isEmpty) return '默认分类';
    final existing = matches.first;
    final gid = existing['groupId'] as String?;
    if (gid == null || gid.isEmpty) return '默认分类';
    return widget.todoGroups
        .firstWhere((g) => g.id == gid, orElse: () => TodoGroup(name: '未知'))
        .name;
  }

  String _getRecurrenceText(String recurrence) {
    switch (recurrence.toLowerCase()) {
      case 'daily':
        return '每天';
      case 'weekly':
        return '每周';
      case 'monthly':
        return '每月';
      case 'weekdays':
        return '工作日';
      default:
        return recurrence;
    }
  }

  Widget _buildMessageFinanceDrafts(ChatMessage msg, bool isDark) {
    final drafts = msg.financeDrafts!
        .where((draft) => !draft.isAdded && !draft.isIgnored)
        .toList();
    if (drafts.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _IridescentActionPanel(
        isDark: isDark,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.24)
                : colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      color: colorScheme.primary,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      drafts.length == 1 ? '待确认记账' : '待确认记账（${drafts.length}笔）',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              ...drafts.map(
                (draft) => Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surface.withValues(alpha: 0.08)
                        : colorScheme.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${draft.type.label}  ${formatFinanceAmount(draft.amountMinor)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color:
                                    draft.type == FinanceTransactionType.expense
                                        ? colorScheme.error
                                        : colorScheme.primary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _editFinanceDraft(draft),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('编辑并保存'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _ignoreFinanceDraft(draft),
                            tooltip: '忽略此账单',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (draft.merchant?.isNotEmpty == true)
                            _buildFinanceDraftMeta(
                              Icons.storefront_outlined,
                              draft.merchant!,
                              colorScheme.onSurfaceVariant,
                            ),
                          if (draft.categoryName?.isNotEmpty == true)
                            _buildFinanceDraftMeta(
                              Icons.category_outlined,
                              draft.categoryName!,
                              colorScheme.onSurfaceVariant,
                            ),
                          _buildFinanceDraftMeta(
                            Icons.calendar_today_outlined,
                            draft.transactionDate,
                            colorScheme.onSurfaceVariant,
                          ),
                          if (draft.paymentMethodName?.isNotEmpty == true)
                            _buildFinanceDraftMeta(
                              Icons.account_balance_wallet_outlined,
                              draft.paymentMethodName!,
                              colorScheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                      if (draft.note?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            draft.note!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  '账单只会在你编辑并保存后写入记账本。',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinanceDraftMeta(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }

  Future<void> _editFinanceDraft(FinanceEntryDraft draft) async {
    final saved = await Navigator.of(context).push<FinanceTransaction>(
      MaterialPageRoute(
        builder: (_) => FinanceEntryScreen(initialDraft: draft),
      ),
    );
    if (saved == null || !mounted) return;
    draft.isAdded = true;
    await _saveHistorySilently();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('账单已保存')),
    );
  }

  Future<void> _ignoreFinanceDraft(FinanceEntryDraft draft) async {
    draft.isIgnored = true;
    await _saveHistorySilently();
    if (mounted) setState(() {});
  }

  Widget _buildMessageFinanceActions(ChatMessage msg, bool isDark) {
    final actions = msg.financeActions!
        .where((action) =>
            action.isMutation && !action.isAdded && !action.isIgnored)
        .toList();
    if (actions.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _IridescentActionPanel(
        isDark: isDark,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.24)
                : colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.manage_search_rounded,
                      color: colorScheme.primary,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      actions.length == 1
                          ? '待确认账单操作'
                          : '待确认账单操作（${actions.length}项）',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              ...actions.map(
                (action) => Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surface.withValues(alpha: 0.08)
                        : colorScheme.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            action.type == FinanceAiActionType.delete
                                ? Icons.delete_outline_rounded
                                : Icons.edit_note_rounded,
                            color: action.type == FinanceAiActionType.delete
                                ? colorScheme.error
                                : colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              action.type == FinanceAiActionType.delete
                                  ? '删除已有账单'
                                  : '修改已有账单',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _ignoreFinanceAction(action),
                            tooltip: '忽略此操作',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 28),
                        child: Text(
                          _describeFinanceAction(action),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: action.type == FinanceAiActionType.delete
                            ? FilledButton.tonalIcon(
                                onPressed: () => _deleteFinanceAction(action),
                                icon:
                                    const Icon(Icons.delete_outline, size: 16),
                                label: const Text('确认删除'),
                                style: FilledButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                            : TextButton.icon(
                                onPressed: () => _editFinanceAction(action),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('查看并保存'),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  '查询是只读的；修改和删除都要由你确认后才会写入记账本。',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _describeFinanceAction(FinanceAiAction action) {
    final id = action.transactionId ?? '未知账单';
    final shortId = id.length > 12 ? '${id.substring(0, 8)}…' : id;
    if (action.type == FinanceAiActionType.delete) {
      final reason = action.reason?.trim();
      return '账单ID $shortId${reason?.isNotEmpty == true ? ' · $reason' : ''}';
    }

    final changes = <String>[];
    if (action.hasType && action.transactionType != null) {
      changes.add('类型改为${action.transactionType!.label}');
    }
    if (action.hasAmount && action.amountMinor != null) {
      changes.add('金额改为${formatFinanceAmount(action.amountMinor!)}');
    }
    if (action.hasDate && action.transactionDate != null) {
      changes.add('日期改为${action.transactionDate}');
    }
    if (action.hasCategory) {
      changes.add('分类改为${action.categoryName ?? '未分类'}');
    }
    if (action.hasPaymentMethod) {
      changes.add('付款方式改为${action.paymentMethodName ?? '未指定'}');
    }
    if (action.hasMerchant) {
      changes.add('商家改为${action.merchant ?? '空'}');
    }
    if (action.hasNote) {
      changes.add('备注改为${action.note ?? '空'}');
    }
    return '账单ID $shortId · ${changes.isEmpty ? '请打开编辑器核对' : changes.join('、')}';
  }

  Future<void> _editFinanceAction(FinanceAiAction action) async {
    final id = action.transactionId;
    if (id == null || id.isEmpty) return;
    final existing = await FinanceRepository.getTransaction(id);
    if (!mounted) return;
    if (existing == null || existing.isDeleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这笔账单已不存在或已被删除，请重新查询后再操作')),
      );
      return;
    }

    final proposed = await _applyFinanceActionToTransaction(action, existing);
    if (!mounted) return;
    final saved = await Navigator.of(context).push<FinanceTransaction>(
      MaterialPageRoute(
        builder: (_) => FinanceEntryScreen(transaction: proposed),
      ),
    );
    if (saved == null || !mounted) return;
    action.isAdded = true;
    await _saveHistorySilently();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('账单已更新')),
    );
  }

  Future<FinanceTransaction> _applyFinanceActionToTransaction(
    FinanceAiAction action,
    FinanceTransaction existing,
  ) async {
    final type = action.hasType && action.transactionType != null
        ? action.transactionType!
        : existing.type;
    final values = await Future.wait<dynamic>([
      FinanceRepository.getCategories(includeArchived: true),
      FinanceRepository.getPaymentMethods(includeArchived: true),
    ]);
    final categories = values[0] as List<FinanceCategory>;
    final paymentMethods = values[1] as List<FinancePaymentMethod>;

    String? categoryUuid = existing.categoryUuid;
    if (action.hasCategory) {
      final resolvedCategory = _findFinanceCategoryUuid(
        categories,
        action.categoryName,
        type,
      );
      categoryUuid = action.categoryUuid ??
          resolvedCategory ??
          (action.categoryName?.trim().isNotEmpty == true
              ? existing.categoryUuid
              : null);
    }
    String? paymentMethodUuid = existing.paymentMethodUuid;
    if (action.hasPaymentMethod) {
      paymentMethodUuid = action.paymentMethodUuid ??
          _findFinancePaymentUuid(paymentMethods, action.paymentMethodName);
    }
    final requestedDate = action.transactionDate?.trim();
    final transactionDate = action.hasDate &&
            requestedDate != null &&
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(requestedDate) &&
            DateTime.tryParse(requestedDate) != null
        ? requestedDate
        : existing.transactionDate;

    return FinanceTransaction(
      uuid: existing.uuid,
      type: type,
      amountMinor: action.hasAmount && action.amountMinor != null
          ? action.amountMinor!
          : existing.amountMinor,
      currencyCode: existing.currencyCode,
      categoryUuid: categoryUuid,
      paymentMethodUuid: paymentMethodUuid,
      transactionDate: transactionDate,
      occurredAt: existing.occurredAt,
      timezoneOffsetMinutes: existing.timezoneOffsetMinutes,
      merchant: action.hasMerchant ? action.merchant : existing.merchant,
      note: action.hasNote ? action.note : existing.note,
      source: existing.source,
      relatedTodoUuid: existing.relatedTodoUuid,
      relatedPlanBlockUuid: existing.relatedPlanBlockUuid,
      relatedTransactionUuid: existing.relatedTransactionUuid,
      isDeleted: false,
      version: existing.version,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt,
      deviceId: existing.deviceId,
    );
  }

  String? _findFinanceCategoryUuid(
    List<FinanceCategory> categories,
    String? name,
    FinanceTransactionType type,
  ) {
    final wanted = _normalizeFinanceOption(name);
    if (wanted.isEmpty) return null;
    final categoryType = type == FinanceTransactionType.income
        ? FinanceCategoryType.income
        : FinanceCategoryType.expense;
    return categories
        .where((item) => item.type == categoryType && !item.isDeleted)
        .where((item) => _normalizeFinanceOption(item.name) == wanted)
        .map((item) => item.uuid)
        .firstOrNull;
  }

  String? _findFinancePaymentUuid(
    List<FinancePaymentMethod> methods,
    String? name,
  ) {
    final wanted = _normalizeFinanceOption(name);
    if (wanted.isEmpty) return null;
    return methods
        .where((item) => !item.isDeleted)
        .where((item) => _normalizeFinanceOption(item.name) == wanted)
        .map((item) => item.uuid)
        .firstOrNull;
  }

  String _normalizeFinanceOption(String? value) {
    return (value ?? '')
        .replaceAll(RegExp(r'^[^\u4e00-\u9fffA-Za-z0-9]+'), '')
        .trim()
        .toLowerCase();
  }

  Future<void> _deleteFinanceAction(FinanceAiAction action) async {
    final id = action.transactionId;
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔账单？'),
        content: const Text('账单会移入记账回收站，之后仍可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FinanceRepository.deleteTransaction(id);
      action.isAdded = true;
      await _saveHistorySilently();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账单已移入回收站')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  Future<void> _ignoreFinanceAction(FinanceAiAction action) async {
    action.isIgnored = true;
    await _saveHistorySilently();
    if (mounted) setState(() {});
  }

  Widget _buildMessageTodoActions(ChatMessage msg, bool isDark) {
    final activeActions = msg.todoActions!
        .where((action) => !action.isAdded && !action.isIgnored)
        .toList();
    if (activeActions.isEmpty) return const SizedBox.shrink();
    final hasExistingMutations =
        activeActions.any((t) => t.mutatesExistingItem);
    final hasPomodoroActions = activeActions.any((t) => t.isPomodoroAction);
    final hasTimeLogActions = activeActions.any((t) => t.isTimeLogAction);
    final hasCountdownActions = activeActions.any((t) => t.isCountdownAction);
    final hasTagActions = activeActions.any((t) => t.isPomodoroTagAction);
    final hasScheduleActions =
        activeActions.any((t) => t.isFixedScheduleAction);

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _IridescentActionPanel(
        isDark: isDark,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.24)
                : colorScheme.primaryContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_task_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasPomodoroActions
                          ? '建议操作番茄钟'
                          : hasScheduleActions
                              ? '建议管理日程'
                              : hasTimeLogActions
                                  ? '建议整理专注记录'
                                  : hasCountdownActions
                                      ? '建议整理倒计时'
                                      : hasTagActions
                                          ? '建议整理番茄标签'
                                          : hasExistingMutations
                                              ? '建议整理待办'
                                              : '建议添加待办',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              ...activeActions.asMap().entries.map((entry) {
                final todo = entry.value;

                final isSelected = todo.isSelected;
                final currentGroupId = todo.groupId;
                final startTime = todo.startTime;
                final dueDate = todo.dueDate;
                final isAllDay = todo.isAllDay;
                final recurrence = todo.recurrence;
                final timeStr = todo.isFixedScheduleAction
                    ? _formatScheduleActionTime(todo)
                    : _formatTodoTimeRange(startTime, dueDate, isAllDay);

                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  todo.isSelected = val == true;
                                });
                                _saveHistorySilently();
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _buildActionBadge(todo),
                                    Expanded(
                                      child: Text(
                                        todo.title ??
                                            (todo.isFixedScheduleAction
                                                ? '未命名日程'
                                                : '未命名待办'),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (todo.mutatesExistingItem)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      _getMutationHint(todo),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey
                                              .withValues(alpha: 0.8),
                                          fontStyle: FontStyle.italic),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: '编辑执行内容',
                            onPressed: () => _editAction(todo),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: '忽略此操作',
                            onPressed: () => _ignoreAction(todo),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      // 时间和循环信息
                      Padding(
                        padding: const EdgeInsets.only(left: 28, top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            if (recurrence != 'none') ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.repeat,
                                size: 13,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _getRecurrenceText(recurrence),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (todo.remark != null && todo.remark!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.notes,
                                size: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.4),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  todo.remark!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (todo.isFixedScheduleAction &&
                          todo.location?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.4),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  todo.location!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildClassificationMetadata(todo),
                      _buildChangeSummary(todo),
                      if (_isDangerousAction(todo))
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 13,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _getDangerHint(todo),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (todo.isTodoAction)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 13,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String?>(
                                      value: widget.todoGroups.any(
                                        (g) => g.id == currentGroupId,
                                      )
                                          ? currentGroupId
                                          : null,
                                      isDense: true,
                                      icon: const Icon(Icons.arrow_drop_down,
                                          size: 16),
                                      hint: const Text('选择分类',
                                          style: TextStyle(fontSize: 11)),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('默认分类',
                                              style: TextStyle(fontSize: 11)),
                                        ),
                                        ...widget.todoGroups.map(
                                          (g) => DropdownMenuItem<String?>(
                                            value: g.id,
                                            child: Text(
                                              g.name,
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        setState(() {
                                          todo.groupId = val;
                                        });
                                        _saveHistorySilently();
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: msg.todoActions!.any(
                      (t) => t.isSelected && !t.isAdded && !t.isIgnored,
                    )
                        ? () => _addTodosForMessage(msg)
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_task, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '执行所选操作 (${activeActions.where((t) => t.isSelected).length})',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassificationMetadata(AiTodoAction action) {
    final priority = action.metadata['priorityLabel']?.toString();
    final rawTags = action.metadata['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    if ((priority == null || priority.isEmpty) && tags.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (priority != null && priority.isNotEmpty)
            _buildMiniMetaChip(Icons.flag_rounded, priority, Colors.orange),
          ...tags.map(
            (tag) => _buildMiniMetaChip(
                Icons.sell_outlined, tag, colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBadge(AiTodoAction action) {
    Color color;
    String label;
    switch (action.type) {
      case AiTodoActionType.createTodo:
        color = Colors.green;
        label = '新增';
        break;
      case AiTodoActionType.completeTodo:
        color = Theme.of(context).colorScheme.primary;
        label = '完成';
        break;
      case AiTodoActionType.deleteTodo:
        color = Colors.red;
        label = '删除';
        break;
      case AiTodoActionType.createFixedSchedule:
        color = Colors.blue;
        label = '新日程';
        break;
      case AiTodoActionType.updateFixedSchedule:
        color = Colors.orange;
        label = '改日程';
        break;
      case AiTodoActionType.cancelFixedSchedule:
        color = Colors.orange;
        label = '取消日程';
        break;
      case AiTodoActionType.deleteFixedSchedule:
        color = Colors.red;
        label = '删日程';
        break;
      case AiTodoActionType.rescheduleTodo:
        color = Colors.purple;
        label = '改期';
        break;
      case AiTodoActionType.bulkRescheduleTodo:
        color = Colors.purple;
        label = '批改';
        break;
      case AiTodoActionType.updateTodo:
        color = Colors.orange;
        label = '修改';
        break;
      case AiTodoActionType.categorizeTodo:
        color = Colors.orange;
        label = '整理';
        break;
      case AiTodoActionType.planTodos:
        color = Colors.teal;
        label = '规划';
        break;
      case AiTodoActionType.createPlanBlock:
        color = Colors.teal;
        label = '时间块';
        break;
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
        color = Colors.teal;
        label = '改规划';
        break;
      case AiTodoActionType.deletePlanBlock:
        color = Colors.red;
        label = '删规划';
        break;
      case AiTodoActionType.skipPlanBlock:
        color = Colors.orange;
        label = '跳过';
        break;
      case AiTodoActionType.startPlanBlockPomodoro:
        color = Colors.redAccent;
        label = '开始规划';
        break;
      case AiTodoActionType.splitTodo:
        color = Colors.indigo;
        label = '拆分';
        break;
      case AiTodoActionType.mergeTodos:
        color = Colors.indigo;
        label = '合并';
        break;
      case AiTodoActionType.createTimeLog:
        color = Colors.cyan;
        label = '记录';
        break;
      case AiTodoActionType.updateTimeLog:
        color = Colors.orange;
        label = '改记录';
        break;
      case AiTodoActionType.deleteTimeLog:
        color = Colors.red;
        label = '删记录';
        break;
      case AiTodoActionType.startPomodoro:
        color = Colors.redAccent;
        label = '开始';
        break;
      case AiTodoActionType.stopPomodoro:
        color = Colors.grey;
        label = '停止';
        break;
      case AiTodoActionType.createCountdown:
        color = Colors.deepOrange;
        label = '倒计时';
        break;
      case AiTodoActionType.updateCountdown:
        color = Colors.orange;
        label = '改倒计时';
        break;
      case AiTodoActionType.completeCountdown:
        color = Colors.green;
        label = '达成';
        break;
      case AiTodoActionType.deleteCountdown:
        color = Colors.red;
        label = '删倒计时';
        break;
      case AiTodoActionType.createTodoGroup:
        color = Colors.green;
        label = '分类';
        break;
      case AiTodoActionType.updateTodoGroup:
        color = Colors.orange;
        label = '改分类';
        break;
      case AiTodoActionType.deleteTodoGroup:
        color = Colors.red;
        label = '删分类';
        break;
      case AiTodoActionType.createPomodoroTag:
        color = Colors.cyan;
        label = '标签';
        break;
      case AiTodoActionType.updatePomodoroTag:
        color = Colors.orange;
        label = '改标签';
        break;
      case AiTodoActionType.deletePomodoroTag:
        color = Colors.red;
        label = '删标签';
        break;
      case AiTodoActionType.unknown:
        color = Colors.grey;
        label = '操作';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _ignoreAction(AiTodoAction action) {
    setState(() {
      action.isIgnored = true;
      action.isSelected = false;
    });
    _recordIgnoreFeedback(action);
    _saveHistorySilently();
  }

  void _recordIgnoreFeedback(AiTodoAction action) {
    if (action.type != AiTodoActionType.categorizeTodo) return;
    final title = action.title ?? '';
    if (title.isEmpty) return;
    final kws = _extractActionKeywords(title);
    if (kws.isEmpty) return;
    if (action.groupId != null) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'group',
        suggestedValue: action.groupId!,
        accepted: false,
      );
    }
    final priority = action.metadata['priority'];
    if (priority != null) {
      SuggestionFeedbackService.record(
        keywords: kws,
        suggestionType: 'priority',
        suggestedValue: '$priority',
        accepted: false,
      );
    }
    final tags = action.metadata['tags'];
    if (tags is List) {
      for (final tag in tags) {
        SuggestionFeedbackService.record(
          keywords: kws,
          suggestionType: 'tag',
          suggestedValue: tag.toString(),
          accepted: false,
        );
      }
    }
  }

  List<String> _extractActionKeywords(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>[];
    for (final m in RegExp(r'[a-z0-9]+').allMatches(lower)) {
      if (m.group(0)!.length >= 2) tokens.add(m.group(0)!);
    }
    for (final m in RegExp(r'[一-鿿]+').allMatches(lower)) {
      final seg = m.group(0)!;
      for (int i = 0; i < seg.length; i++) {
        tokens.add(seg[i]);
      }
      for (int i = 0; i < seg.length - 1; i++) {
        tokens.add(seg.substring(i, i + 2));
      }
    }
    return tokens;
  }

  Future<void> _editAction(AiTodoAction action) async {
    final titleCtrl = TextEditingController(text: action.title ?? '');
    final remarkCtrl = TextEditingController(text: action.remark ?? '');
    final startCtrl = TextEditingController(text: action.startTime ?? '');
    final dueCtrl = TextEditingController(text: action.dueDate ?? '');
    final idCtrl = TextEditingController(
      text: action.isFixedScheduleAction
          ? action.scheduleId ?? ''
          : action.todoId ?? '',
    );
    final dateCtrl = TextEditingController(text: action.date ?? '');
    final locationCtrl = TextEditingController(text: action.location ?? '');
    final durationCtrl =
        TextEditingController(text: action.durationMinutes?.toString() ?? '');
    final reminderCtrl = TextEditingController(
      text: action.isFixedScheduleAction
          ? action.reminderMinutesList.join(',')
          : action.reminderMinutes?.toString() ?? '',
    );
    final colorCtrl = TextEditingController(text: action.color ?? '');
    final statusCtrl = TextEditingController(text: action.status ?? '');
    final tagCtrl = TextEditingController(text: action.tagUuids.join(','));
    var recurrence = action.recurrence;
    var isAllDay = action.isAllDay;
    var timeMode = action.timeMode ??
        (isAllDay
            ? TodoTimeMode.dateOnly.name
            : action.dueDate == null
                ? TodoTimeMode.unscheduled.name
                : TodoTimeMode.deadline.name);
    var recurrenceScope = action.recurrenceScope;
    final initialRecurrence = recurrence;
    final initialIsAllDay = isAllDay;
    final initialTimeMode = timeMode;
    final initialRemarkText = remarkCtrl.text;
    final initialDateText = dateCtrl.text;
    final initialLocationText = locationCtrl.text;
    final initialStartText = startCtrl.text;
    final initialDueText = dueCtrl.text;
    final initialReminderText = reminderCtrl.text;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              _buildActionBadge(action),
              const SizedBox(width: 8),
              const Text('编辑执行内容'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.86,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (action.mutatesExistingItem ||
                      action.isTimeLogAction ||
                      action.isCountdownAction ||
                      action.isTodoGroupAction ||
                      action.isPomodoroTagAction ||
                      action.isFixedScheduleAction)
                    _editField(idCtrl, _idFieldLabel(action)),
                  if (_usesTitle(action))
                    _editField(titleCtrl, _titleLabel(action)),
                  if (_usesRemark(action)) _editField(remarkCtrl, '备注'),
                  if (action.isFixedScheduleAction)
                    _editField(dateCtrl, '日程日期', hint: 'YYYY-MM-DD'),
                  if (action.isFixedScheduleAction)
                    _editField(locationCtrl, '地点'),
                  if (_usesStartTime(action))
                    _editField(startCtrl, _startTimeLabel(action),
                        hint: 'YYYY-MM-DD HH:mm'),
                  if (_usesDueTime(action))
                    _editField(dueCtrl, _dueTimeLabel(action),
                        hint: 'YYYY-MM-DD HH:mm'),
                  if (_usesDuration(action))
                    _editField(durationCtrl, '时长（分钟）',
                        keyboardType: TextInputType.number),
                  if (_usesReminder(action))
                    _editField(reminderCtrl, '提前提醒（分钟）',
                        keyboardType: TextInputType.number),
                  if (_usesColor(action))
                    _editField(colorCtrl, '颜色', hint: '#3B82F6'),
                  if (_usesStatus(action))
                    _editField(statusCtrl, '状态',
                        hint: 'completed 或 interrupted'),
                  if (_usesTags(action)) _editField(tagCtrl, '番茄标签ID（逗号分隔）'),
                  if (action.isTodoAction || action.isFixedScheduleAction) ...[
                    const SizedBox(height: 8),
                    if (action.isTodoAction)
                      DropdownButtonFormField<String>(
                        initialValue: timeMode,
                        decoration: const InputDecoration(labelText: '待办时间语义'),
                        items: const [
                          DropdownMenuItem(
                              value: 'unscheduled', child: Text('未安排')),
                          DropdownMenuItem(
                              value: 'dateOnly', child: Text('日期内完成')),
                          DropdownMenuItem(
                              value: 'deadline', child: Text('截止时刻')),
                        ],
                        onChanged: (value) => setDialogState(() {
                          timeMode = value ?? TodoTimeMode.unscheduled.name;
                          isAllDay = timeMode == TodoTimeMode.dateOnly.name;
                        }),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: recurrence,
                      decoration: const InputDecoration(labelText: '循环'),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('不循环')),
                        DropdownMenuItem(value: 'daily', child: Text('每天')),
                        DropdownMenuItem(value: 'weekly', child: Text('每周')),
                        DropdownMenuItem(value: 'monthly', child: Text('每月')),
                        DropdownMenuItem(value: 'yearly', child: Text('每年')),
                        DropdownMenuItem(value: 'weekdays', child: Text('工作日')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => recurrence = value ?? 'none'),
                    ),
                    if (action.mutatesExistingItem ||
                        (action.isFixedScheduleAction &&
                            action.type !=
                                AiTodoActionType.createFixedSchedule))
                      DropdownButtonFormField<String>(
                        initialValue: recurrenceScope,
                        decoration: const InputDecoration(labelText: '循环作用范围'),
                        items: const [
                          DropdownMenuItem(
                              value: 'occurrence', child: Text('仅本期')),
                          DropdownMenuItem(
                              value: 'future', child: Text('本期及以后')),
                        ],
                        onChanged: (value) => setDialogState(
                          () => recurrenceScope = value ?? 'occurrence',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  if (action.isFixedScheduleAction) {
                    action.scheduleId = _nullIfBlank(idCtrl.text);
                  } else {
                    action.todoId = _nullIfBlank(idCtrl.text);
                  }
                  action.title = _nullIfBlank(titleCtrl.text);
                  action.remark = _nullIfBlank(remarkCtrl.text);
                  action.date = _nullIfBlank(dateCtrl.text);
                  action.location = _nullIfBlank(locationCtrl.text);
                  action.startTime = _nullIfBlank(startCtrl.text);
                  action.dueDate = _nullIfBlank(dueCtrl.text);
                  action.durationMinutes = int.tryParse(durationCtrl.text);
                  if (action.isFixedScheduleAction) {
                    action.reminderMinutesList = reminderCtrl.text
                        .split(',')
                        .map((value) => int.tryParse(value.trim()))
                        .whereType<int>()
                        .toList();
                  } else {
                    action.reminderMinutes = int.tryParse(reminderCtrl.text);
                  }
                  action.color = _nullIfBlank(colorCtrl.text);
                  action.status = _nullIfBlank(statusCtrl.text);
                  action.tagUuids = tagCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  action.recurrence = recurrence;
                  action.isAllDay = isAllDay;
                  action.timeMode = timeMode;
                  action.recurrenceScope = recurrenceScope;
                  action.hasRemark =
                      action.hasRemark || remarkCtrl.text != initialRemarkText;
                  action.hasDate =
                      action.hasDate || dateCtrl.text != initialDateText;
                  action.hasLocation = action.hasLocation ||
                      locationCtrl.text != initialLocationText;
                  action.hasStartTime =
                      action.hasStartTime || startCtrl.text != initialStartText;
                  action.hasDueDate =
                      action.hasDueDate || dueCtrl.text != initialDueText;
                  if (action.isFixedScheduleAction) {
                    action.hasReminderMinutesList =
                        action.hasReminderMinutesList ||
                            reminderCtrl.text != initialReminderText;
                  } else {
                    action.hasReminderMinutes = action.hasReminderMinutes ||
                        reminderCtrl.text != initialReminderText;
                  }
                  action.hasTimeMode = action.hasTimeMode ||
                      timeMode != initialTimeMode ||
                      isAllDay != initialIsAllDay;
                  action.hasIsAllDay = action.hasIsAllDay ||
                      isAllDay != initialIsAllDay ||
                      timeMode != initialTimeMode;
                  action.hasRecurrence =
                      action.hasRecurrence || recurrence != initialRecurrence;
                });
                _saveHistorySilently();
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _usesTitle(AiTodoAction action) =>
      action.type != AiTodoActionType.completeTodo &&
      action.type != AiTodoActionType.deleteTodo &&
      action.type != AiTodoActionType.cancelFixedSchedule &&
      action.type != AiTodoActionType.deleteFixedSchedule &&
      action.type != AiTodoActionType.deleteTimeLog &&
      action.type != AiTodoActionType.stopPomodoro &&
      action.type != AiTodoActionType.completeCountdown &&
      action.type != AiTodoActionType.deleteCountdown &&
      action.type != AiTodoActionType.deleteTodoGroup &&
      action.type != AiTodoActionType.deletePomodoroTag;

  bool _usesRemark(AiTodoAction action) =>
      action.isTodoAction ||
      action.isFixedScheduleAction ||
      action.isTimeLogAction ||
      action.isPlanBlockAction;

  bool _usesStartTime(AiTodoAction action) =>
      action.isTodoAction ||
      action.isFixedScheduleAction ||
      action.isTimeLogAction ||
      action.isPlanBlockAction;

  bool _usesDueTime(AiTodoAction action) =>
      action.isTodoAction ||
      action.isFixedScheduleAction ||
      action.isTimeLogAction ||
      action.isCountdownAction ||
      action.isPlanBlockAction;

  bool _usesDuration(AiTodoAction action) =>
      action.isTimeLogAction ||
      action.isPlanBlockAction ||
      action.type == AiTodoActionType.startPomodoro;

  bool _usesReminder(AiTodoAction action) =>
      action.isTodoAction ||
      action.isFixedScheduleAction ||
      action.isPlanBlockAction;

  bool _usesColor(AiTodoAction action) => action.isPomodoroTagAction;

  bool _usesStatus(AiTodoAction action) =>
      action.type == AiTodoActionType.stopPomodoro;

  bool _usesTags(AiTodoAction action) =>
      action.isTimeLogAction || action.isPomodoroAction;

  String _idFieldLabel(AiTodoAction action) {
    if (action.isFixedScheduleAction) return '日程ID';
    if (action.isTimeLogAction) return '专注记录ID';
    if (action.isCountdownAction) return '倒计时ID';
    if (action.isTodoGroupAction) return '分类ID';
    if (action.isPomodoroTagAction) return '标签ID';
    return '待办ID';
  }

  String _titleLabel(AiTodoAction action) {
    if (action.isFixedScheduleAction) return '日程标题';
    if (action.isTodoGroupAction) return '分类名称';
    if (action.isPomodoroTagAction) return '标签名称';
    if (action.isCountdownAction) return '倒计时标题';
    if (action.isTimeLogAction) return '专注记录标题';
    return '标题';
  }

  String _startTimeLabel(AiTodoAction action) {
    if (action.isTimeLogAction) return '开始时间';
    return '开始时间';
  }

  String _dueTimeLabel(AiTodoAction action) {
    if (action.isFixedScheduleAction) return '结束时间';
    if (action.isCountdownAction) return '目标时间';
    if (action.isTimeLogAction) return '结束时间';
    return '截止时间';
  }

  String _getMutationHint(AiTodoAction action) {
    switch (action.type) {
      case AiTodoActionType.completeTodo:
        return '标记为已完成';
      case AiTodoActionType.deleteTodo:
        return '移动到已删除';
      case AiTodoActionType.createFixedSchedule:
        return '新增固定日程';
      case AiTodoActionType.updateFixedSchedule:
        return '更新固定日程';
      case AiTodoActionType.cancelFixedSchedule:
        return '取消固定日程';
      case AiTodoActionType.deleteFixedSchedule:
        return '删除固定日程';
      case AiTodoActionType.rescheduleTodo:
        return '调整时间安排';
      case AiTodoActionType.bulkRescheduleTodo:
        return '批量调整时间安排';
      case AiTodoActionType.updateTodo:
        return '更新待办内容';
      case AiTodoActionType.categorizeTodo:
        return '从 [${_getTodoCurrentFolderName(action.todoId)}] 移动';
      case AiTodoActionType.planTodos:
        return '生成计划待办';
      case AiTodoActionType.createPlanBlock:
        return '安排到具体时间块';
      case AiTodoActionType.updatePlanBlock:
        return '修改规划块';
      case AiTodoActionType.deletePlanBlock:
        return '删除规划块';
      case AiTodoActionType.reschedulePlanBlocks:
        return '重排规划块';
      case AiTodoActionType.skipPlanBlock:
        return '跳过规划块';
      case AiTodoActionType.startPlanBlockPomodoro:
        return '开始规划番茄钟';
      case AiTodoActionType.splitTodo:
        return action.sourceTodoIds.isEmpty
            ? '拆分为子任务'
            : '从 [${action.sourceTodoIds.join(', ')}] 拆分';
      case AiTodoActionType.mergeTodos:
        return action.sourceTodoIds.isEmpty
            ? '合并为新待办'
            : '合并 [${action.sourceTodoIds.join(', ')}]';
      case AiTodoActionType.createTimeLog:
        return '新增专注记录';
      case AiTodoActionType.updateTimeLog:
        return '修改专注记录';
      case AiTodoActionType.deleteTimeLog:
        return '删除专注记录';
      case AiTodoActionType.startPomodoro:
        return '开始番茄钟';
      case AiTodoActionType.stopPomodoro:
        return '停止当前番茄钟';
      case AiTodoActionType.createCountdown:
        return '新增倒计时';
      case AiTodoActionType.updateCountdown:
        return '修改倒计时';
      case AiTodoActionType.completeCountdown:
        return '标记倒计时达成';
      case AiTodoActionType.deleteCountdown:
        return '删除倒计时';
      case AiTodoActionType.createTodoGroup:
        return '新增待办分类';
      case AiTodoActionType.updateTodoGroup:
        return '修改待办分类';
      case AiTodoActionType.deleteTodoGroup:
        return '删除待办分类';
      case AiTodoActionType.createPomodoroTag:
        return '新增番茄标签';
      case AiTodoActionType.updatePomodoroTag:
        return '修改番茄标签';
      case AiTodoActionType.deletePomodoroTag:
        return '删除番茄标签';
      case AiTodoActionType.createTodo:
      case AiTodoActionType.unknown:
        return '';
    }
  }

  Widget _buildChangeSummary(AiTodoAction action) {
    if (action.isFixedScheduleAction) {
      return _buildFixedScheduleChangeSummary(action);
    }
    if (!action.mutatesExistingItem || !action.isTodoAction) {
      return const SizedBox.shrink();
    }
    final existing = _findExistingTodo(action.todoId);
    if (existing == null) return const SizedBox.shrink();

    final rows = <String>[];
    void addRow(String label, String before, String after) {
      if (before == after || after.isEmpty) return;
      rows.add('$label: $before -> $after');
    }

    addRow('标题', '${existing['title'] ?? ''}', action.title ?? '');
    addRow('备注', '${existing['remark'] ?? ''}', action.remark ?? '');
    if (action.hasStartTime ||
        action.hasDueDate ||
        action.hasTimeMode ||
        action.hasIsAllDay) {
      final beforeTime = _formatTodoTimeRange(
        existing['startTime']?.toString(),
        existing['endTime']?.toString(),
        existing['isAllDay'] == true,
      );
      final afterTime = _formatTodoTimeRange(
        action.startTime ?? existing['startTime']?.toString(),
        action.dueDate ?? existing['endTime']?.toString(),
        action.timeMode == TodoTimeMode.dateOnly.name ||
            (action.timeMode == null &&
                (action.hasIsAllDay
                    ? action.isAllDay
                    : existing['isAllDay'] == true)),
      );
      addRow('时间', beforeTime, afterTime);
    }
    if (action.groupId != null ||
        action.type == AiTodoActionType.categorizeTodo) {
      addRow(
        '分类',
        _getGroupName(existing['groupId']?.toString()),
        _getGroupName(action.groupId),
      );
    }
    if (action.reminderMinutes != null) {
      addRow(
        '提醒',
        '提前${existing['reminderMinutes'] ?? 5}分钟',
        '提前${action.reminderMinutes}分钟',
      );
    }
    if (action.type == AiTodoActionType.completeTodo) {
      addRow('状态', existing['isDone'] == true ? '已完成' : '未完成', '已完成');
    }
    if (action.type == AiTodoActionType.deleteTodo) {
      addRow('删除', existing['isDeleted'] == true ? '已删除' : '未删除', '已删除');
    }
    if (existing['recurrenceSeriesId']?.toString().isNotEmpty == true) {
      rows.add(action.appliesToFutureOccurrences ? '范围: 本期及以后' : '范围: 仅本期');
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (row) => Text(
                  row,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildFixedScheduleChangeSummary(AiTodoAction action) {
    if (action.type == AiTodoActionType.createFixedSchedule) {
      return const SizedBox.shrink();
    }
    final existing = _fixedSchedules
        .where((item) => item.id == action.scheduleId)
        .firstOrNull;
    if (existing == null) return const SizedBox.shrink();
    final rows = <String>[];
    if (action.title?.trim().isNotEmpty == true &&
        action.title!.trim() != existing.title) {
      rows.add('标题: ${existing.title} -> ${action.title!.trim()}');
    }
    if (action.hasDate && action.date != existing.date) {
      rows.add('日期: ${existing.date} -> ${action.date ?? '待确认'}');
    }
    if (action.hasStartTime || action.hasDueDate) {
      final existingAction = AiTodoAction(
        type: AiTodoActionType.updateFixedSchedule,
        date: existing.date,
        startTime: existing.startTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(existing.startTime!)
                .toIso8601String(),
        dueDate: existing.endTime == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(existing.endTime!)
                .toIso8601String(),
      );
      final nextAction = AiTodoAction(
        type: AiTodoActionType.updateFixedSchedule,
        date: action.hasDate ? action.date : existing.date,
        startTime:
            action.hasStartTime ? action.startTime : existingAction.startTime,
        dueDate: action.hasDueDate ? action.dueDate : existingAction.dueDate,
      );
      rows.add(
        '时间: ${_formatScheduleActionTime(existingAction)} -> ${_formatScheduleActionTime(nextAction)}',
      );
    }
    if (action.hasLocation) {
      rows.add('地点: ${existing.location ?? '无'} -> ${action.location ?? '无'}');
    }
    if (action.type == AiTodoActionType.cancelFixedSchedule) {
      rows.add('状态: ${existing.status.name} -> cancelled');
    }
    if (action.type == AiTodoActionType.deleteFixedSchedule) {
      rows.add('删除: 未删除 -> 已删除');
    }
    if (existing.recurrenceSeriesId?.isNotEmpty == true) {
      rows.add(action.appliesToFutureOccurrences ? '范围: 本期及以后' : '范围: 仅本期');
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map(
                (row) => Text(
                  row,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Map<String, dynamic>? _findExistingTodo(String? todoId) {
    if (todoId == null) return null;
    for (final todo in widget.todos) {
      if (todo['id'] == todoId) return todo;
    }
    return null;
  }

  String _getGroupName(String? groupId) {
    if (groupId == null || groupId.isEmpty) return '默认分类';
    return widget.todoGroups
        .firstWhere((g) => g.id == groupId, orElse: () => TodoGroup(name: '未知'))
        .name;
  }

  bool _isDangerousAction(AiTodoAction action) {
    return action.type == AiTodoActionType.deleteTodo ||
        action.type == AiTodoActionType.deleteTimeLog ||
        action.type == AiTodoActionType.cancelFixedSchedule ||
        action.type == AiTodoActionType.deleteFixedSchedule ||
        (action.type == AiTodoActionType.updateFixedSchedule &&
            action.status == 'cancelled') ||
        action.type == AiTodoActionType.stopPomodoro ||
        action.type == AiTodoActionType.deleteCountdown ||
        action.type == AiTodoActionType.completeCountdown ||
        action.type == AiTodoActionType.deleteTodoGroup ||
        action.type == AiTodoActionType.deletePomodoroTag ||
        action.type == AiTodoActionType.deletePlanBlock ||
        action.type == AiTodoActionType.skipPlanBlock ||
        (action.type == AiTodoActionType.splitTodo &&
            action.deleteSourceTodos) ||
        (action.type == AiTodoActionType.mergeTodos &&
            action.deleteSourceTodos);
  }

  String _getDangerHint(AiTodoAction action) {
    switch (action.type) {
      case AiTodoActionType.deleteTodo:
        return '将删除已有待办，执行前请确认';
      case AiTodoActionType.cancelFixedSchedule:
        return '将取消已有日程，执行前请确认';
      case AiTodoActionType.deleteFixedSchedule:
        return '将删除已有日程，执行前请确认';
      case AiTodoActionType.updateFixedSchedule:
        return action.status == 'cancelled' ? '将取消已有日程，执行前请确认' : '';
      case AiTodoActionType.splitTodo:
        return '拆分后会删除原待办，执行前请确认';
      case AiTodoActionType.mergeTodos:
        return '合并后会删除源待办，执行前请确认';
      case AiTodoActionType.deleteTimeLog:
        return '将删除已有专注记录，执行前请确认';
      case AiTodoActionType.stopPomodoro:
        return '将停止当前番茄钟，执行前请确认';
      case AiTodoActionType.deleteCountdown:
        return '将删除已有倒计时，执行前请确认';
      case AiTodoActionType.completeCountdown:
        return '将标记倒计时达成，执行前请确认';
      case AiTodoActionType.deleteTodoGroup:
        return '将删除待办分类，执行前请确认';
      case AiTodoActionType.deletePomodoroTag:
        return '将删除番茄标签，执行前请确认';
      case AiTodoActionType.deletePlanBlock:
        return '将删除规划块，执行前请确认';
      case AiTodoActionType.skipPlanBlock:
        return '将跳过规划块，执行前请确认';
      case AiTodoActionType.createTodo:
      case AiTodoActionType.updateTodo:
      case AiTodoActionType.completeTodo:
      case AiTodoActionType.createFixedSchedule:
      case AiTodoActionType.rescheduleTodo:
      case AiTodoActionType.bulkRescheduleTodo:
      case AiTodoActionType.categorizeTodo:
      case AiTodoActionType.planTodos:
      case AiTodoActionType.createPlanBlock:
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
      case AiTodoActionType.startPlanBlockPomodoro:
      case AiTodoActionType.unknown:
      case AiTodoActionType.createTimeLog:
      case AiTodoActionType.updateTimeLog:
      case AiTodoActionType.startPomodoro:
      case AiTodoActionType.createCountdown:
      case AiTodoActionType.updateCountdown:
      case AiTodoActionType.createTodoGroup:
      case AiTodoActionType.updateTodoGroup:
      case AiTodoActionType.createPomodoroTag:
      case AiTodoActionType.updatePomodoroTag:
        return '';
    }
  }

  Future<void> _saveHistorySilently() async {
    await ChatStorageService.saveHistory(_messages, _activeSessionId);
  }

  Future<void> _addTodosForMessage(ChatMessage msg) async {
    if (msg.todoActions == null) return;

    final existingCountdowns = widget.countdowns.isNotEmpty
        ? widget.countdowns
        : await StorageService.getCountdowns(widget.username);
    final existingTags = widget.pomodoroTags.isNotEmpty
        ? widget.pomodoroTags
        : await PomodoroService.getTags();

    final result = AiTodoActionExecutor.execute(
      actions: msg.todoActions!,
      existingTodos: widget.todos,
      existingTimeLogs: widget.timeLogs,
      existingCountdowns: existingCountdowns,
      existingTodoGroups: widget.todoGroups,
      existingPomodoroTags: existingTags,
      existingPlanBlocks: _planBlocks,
      existingFixedSchedules: _fixedSchedules,
      categoryReminderDefaults: _categoryReminderDefaults,
    );

    if (result.hasChanges) {
      if (widget.onTodosBatchAction != null) {
        widget.onTodosBatchAction!(result.newTodos, result.updatedTodos);
      } else {
        // Fallback to separate calls
        if (result.newTodos.isNotEmpty) {
          if (widget.onTodosBatchInserted != null) {
            widget.onTodosBatchInserted!(result.newTodos);
          } else if (widget.onTodoInserted != null) {
            for (final t in result.newTodos) {
              widget.onTodoInserted!(t);
            }
          }
        }
        if (result.updatedTodos.isNotEmpty && widget.onTodosUpdated != null) {
          widget.onTodosUpdated!(result.updatedTodos);
        }
      }

      if (result.newTimeLogs.isNotEmpty || result.updatedTimeLogs.isNotEmpty) {
        final allLogs = await StorageService.getTimeLogs(widget.username);
        final merged = AiTodoActionExecutor.mergeTimeLogUpdates(
          allLogs,
          result.newTimeLogs,
          result.updatedTimeLogs,
        );
        await StorageService.saveTimeLogs(widget.username, merged, sync: true);
      }

      if (result.newCountdowns.isNotEmpty ||
          result.updatedCountdowns.isNotEmpty) {
        final allCountdowns =
            await StorageService.getCountdowns(widget.username);
        final merged = AiTodoActionExecutor.mergeCountdownUpdates(
          allCountdowns,
          result.newCountdowns,
          result.updatedCountdowns,
        );
        await StorageService.saveCountdowns(widget.username, merged,
            sync: true);
      }

      if (result.newTodoGroups.isNotEmpty ||
          result.updatedTodoGroups.isNotEmpty) {
        final allGroups = await StorageService.getTodoGroups(
          widget.username,
          includeDeleted: true,
        );
        final merged = AiTodoActionExecutor.mergeTodoGroupUpdates(
          allGroups,
          result.newTodoGroups,
          result.updatedTodoGroups,
        );
        await StorageService.saveTodoGroups(widget.username, merged,
            sync: true);
        widget.onTodoGroupsChanged?.call(merged);
      }

      if (result.newPomodoroTags.isNotEmpty ||
          result.updatedPomodoroTags.isNotEmpty) {
        final allTags = await PomodoroService.getTags();
        final merged = AiTodoActionExecutor.mergePomodoroTagUpdates(
          allTags,
          result.newPomodoroTags,
          result.updatedPomodoroTags,
        );
        await PomodoroService.saveTags(merged);
      }

      if (result.newPlanBlocks.isNotEmpty ||
          result.updatedPlanBlocks.isNotEmpty) {
        await StorageService.savePlanBlocks(
          widget.username,
          [...result.newPlanBlocks, ...result.updatedPlanBlocks],
          sync: true,
        );
        _planBlocks = [
          ..._planBlocks.where((existing) => !result.updatedPlanBlocks
              .any((updated) => updated.uuid == existing.uuid)),
          ...result.newPlanBlocks,
          ...result.updatedPlanBlocks,
        ];
      }

      if (result.newFixedSchedules.isNotEmpty ||
          result.updatedFixedSchedules.isNotEmpty) {
        await StorageService.saveFixedSchedules(
          widget.username,
          [
            ...result.newFixedSchedules,
            ...result.updatedFixedSchedules,
          ],
          sync: true,
        );
        _fixedSchedules = AiTodoActionExecutor.mergeFixedScheduleUpdates(
          _fixedSchedules,
          result.newFixedSchedules,
          result.updatedFixedSchedules,
        );
        widget.onFixedSchedulesChanged?.call(_fixedSchedules);
        await ReminderScheduleService.scheduleFromStorage(
          widget.username,
          force: true,
        );
      }

      for (final action in result.pomodoroActions) {
        await _executePomodoroAction(action);
      }

      if (!mounted) return;
      setState(() {});
      _saveHistorySilently();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '已执行所选操作 (新待办: ${result.newTodos.length}, 整理待办: ${result.updatedTodos.length}, 日程: ${result.newFixedSchedules.length + result.updatedFixedSchedules.length}, 规划: ${result.newPlanBlocks.length + result.updatedPlanBlocks.length}, 专注记录: ${result.newTimeLogs.length + result.updatedTimeLogs.length}, 倒计时: ${result.newCountdowns.length + result.updatedCountdowns.length}, 分类: ${result.newTodoGroups.length + result.updatedTodoGroups.length}, 标签: ${result.newPomodoroTags.length + result.updatedPomodoroTags.length}, 番茄钟: ${result.pomodoroActions.length})')),
      );
    }
  }

  Future<void> _executePomodoroAction(AiTodoAction action) async {
    switch (action.type) {
      case AiTodoActionType.startPlanBlockPomodoro:
        final blockId = action.planBlockId;
        if (blockId == null || blockId.isEmpty) return;
        final blocks = _planBlocks.isNotEmpty
            ? _planBlocks
            : await StorageService.getPlanBlocks(widget.username);
        TodoPlanBlock? block;
        for (final item in blocks) {
          if (item.uuid == blockId && !item.isDeleted) {
            block = item;
            break;
          }
        }
        if (block == null) return;
        final existing = await PomodoroService.loadRunState();
        if (existing != null &&
            existing.phase != PomodoroPhase.idle &&
            existing.phase != PomodoroPhase.finished) {
          return;
        }
        final settings = await PomodoroService.getSettings();
        TodoItem? boundTodo;
        final match = widget.todos.where((t) => t['id'] == block!.todoId);
        if (match.isNotEmpty) {
          boundTodo = TodoItem(
            id: block.todoId,
            title: match.first['title']?.toString() ??
                block.titleSnapshot ??
                '规划任务',
          );
        }
        boundTodo ??= TodoItem(
          id: block.todoId,
          title: block.titleSnapshot ?? '规划任务',
        );
        block.status = TodoPlanStatus.focusing;
        block.markAsChanged();
        await StorageService.savePlanBlocks(widget.username, [block]);
        await PomodoroControlService.startFocus(
          settings: settings,
          boundTodo: boundTodo,
          durationMinutes: block.pomodoroRounds > 0
              ? block.pomodoroMinutes * block.pomodoroRounds
              : math.max(1, block.plannedMinutes),
          planBlockId: block.uuid,
          ensureSyncConnection: true,
        );
        break;
      case AiTodoActionType.startPomodoro:
        final existing = await PomodoroService.loadRunState();
        if (existing != null &&
            existing.phase != PomodoroPhase.idle &&
            existing.phase != PomodoroPhase.finished) {
          return;
        }
        final settings = await PomodoroService.getSettings();
        TodoItem? boundTodo;
        if (action.todoId != null) {
          final match = widget.todos.where((t) => t['id'] == action.todoId);
          if (match.isNotEmpty) {
            boundTodo = TodoItem(
              id: action.todoId,
              title: match.first['title']?.toString() ?? action.title ?? '专注',
              isDone: match.first['isDone'] == true,
              isDeleted: match.first['isDeleted'] == true,
            );
          }
        }
        boundTodo ??= action.title?.isNotEmpty == true
            ? TodoItem(id: '', title: action.title!)
            : null;
        await PomodoroControlService.startFocus(
          settings: settings,
          boundTodo: boundTodo,
          tagUuids: action.tagUuids,
          durationMinutes: action.durationMinutes,
          ensureSyncConnection: true,
        );
        break;
      case AiTodoActionType.stopPomodoro:
        await PomodoroControlService.stopCurrentFocus(
          username: widget.username,
          status: action.status == 'completed'
              ? PomodoroRecordStatus.completed
              : PomodoroRecordStatus.interrupted,
          markTodoComplete: action.status == 'completed',
          ensureSyncConnection: true,
        );
        break;
      case AiTodoActionType.createTodo:
      case AiTodoActionType.updateTodo:
      case AiTodoActionType.completeTodo:
      case AiTodoActionType.deleteTodo:
      case AiTodoActionType.createFixedSchedule:
      case AiTodoActionType.updateFixedSchedule:
      case AiTodoActionType.cancelFixedSchedule:
      case AiTodoActionType.deleteFixedSchedule:
      case AiTodoActionType.rescheduleTodo:
      case AiTodoActionType.bulkRescheduleTodo:
      case AiTodoActionType.categorizeTodo:
      case AiTodoActionType.planTodos:
      case AiTodoActionType.createPlanBlock:
      case AiTodoActionType.updatePlanBlock:
      case AiTodoActionType.deletePlanBlock:
      case AiTodoActionType.reschedulePlanBlocks:
      case AiTodoActionType.skipPlanBlock:
      case AiTodoActionType.splitTodo:
      case AiTodoActionType.mergeTodos:
      case AiTodoActionType.createTimeLog:
      case AiTodoActionType.updateTimeLog:
      case AiTodoActionType.deleteTimeLog:
      case AiTodoActionType.createCountdown:
      case AiTodoActionType.updateCountdown:
      case AiTodoActionType.completeCountdown:
      case AiTodoActionType.deleteCountdown:
      case AiTodoActionType.createTodoGroup:
      case AiTodoActionType.updateTodoGroup:
      case AiTodoActionType.deleteTodoGroup:
      case AiTodoActionType.createPomodoroTag:
      case AiTodoActionType.updatePomodoroTag:
      case AiTodoActionType.deletePomodoroTag:
      case AiTodoActionType.unknown:
        break;
    }
  }

  Widget _buildQuickQuestion(
    String text, {
    bool compact = false,
    bool expand = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return _PressableScale(
      onTap: () {
        _inputCtrl.text = text;
        _sendMessage();
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 7 : 10,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: expand ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _buildRawReplyDebugText(ChatMessage msg) {
    final sections = <String>[];
    if (msg.rawContent.trim().isNotEmpty) {
      sections.add(msg.rawContent.trim());
    } else {
      sections.add('当前历史消息没有保存模型原始回复。');
      if (msg.content.trim().isNotEmpty) {
        sections.add('[CLEANED_CONTENT]\n${msg.content.trim()}');
      }
    }

    final actions = msg.todoActions;
    if (actions != null && actions.isNotEmpty) {
      const encoder = JsonEncoder.withIndent('  ');
      sections.add('[PARSED_ACTIONS]\n${encoder.convert(
        actions.map((action) => action.toJson()).toList(),
      )}');
    }

    if (msg.reasoningContent.trim().isNotEmpty) {
      sections.add('[REASONING]\n${msg.reasoningContent.trim()}');
    }

    if (msg.smartContext.trim().isNotEmpty) {
      sections.add('[SMART_CONTEXT]\n${msg.smartContext.trim()}');
    } else {
      sections.add(
          '[SMART_CONTEXT]\n本次回复未触发关键词注入额外上下文（日程/课程/专注记录/冲突/团队）。\n待办、日程等对象会在相关意图出现时按需注入。');
    }

    return sections.join('\n\n');
  }

  Future<void> _showRawReplyDialog(ChatMessage msg) async {
    final colorScheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('模型原始回复'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.82,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
            child: SingleChildScrollView(
              child: SelectableText(
                _buildRawReplyDebugText(msg),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: colorScheme.onSurface,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
