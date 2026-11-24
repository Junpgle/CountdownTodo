part of 'todo_chat_screen.dart';

// ignore_for_file: annotate_overrides, unused_element, unused_element_parameter

mixin _TodoChatFinanceActions on _TodoChatScreenStateBase {
  Widget _buildMessageFinanceDrafts(ChatMessage msg, bool isDark) {
    final drafts = msg.financeDrafts!
        .where((draft) => !draft.isAdded && !draft.isIgnored)
        .toList();
    if (drafts.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
                                fontSize: 13,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
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
        Text(text, style: TextStyle(fontSize: 11, color: color)),
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
    AppSnackBars.showSnackBar(context, const SnackBar(content: Text('账单已保存')));
  }

  Future<void> _ignoreFinanceDraft(FinanceEntryDraft draft) async {
    draft.isIgnored = true;
    await _saveHistorySilently();
    if (mounted) setState(() {});
  }

  Widget _buildMessageFinanceActions(ChatMessage msg, bool isDark) {
    final actions = msg.financeActions!
        .where(
          (action) => action.isMutation && !action.isAdded && !action.isIgnored,
        )
        .toList();
    if (actions.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
                                fontSize: 13,
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
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
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
      AppSnackBars.showSnackBar(
        context,
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
    AppSnackBars.showSnackBar(context, const SnackBar(content: Text('账单已更新')));
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
      final requestedCategoryUuid = action.categoryUuid?.trim();
      final categoryType = type == FinanceTransactionType.income
          ? FinanceCategoryType.income
          : FinanceCategoryType.expense;
      final categoryById = categories
          .where(
            (item) =>
                item.uuid == requestedCategoryUuid &&
                item.type == categoryType &&
                !item.isDeleted,
          )
          .map((item) => item.uuid)
          .firstOrNull;
      final categoryByName = _findFinanceCategoryUuid(
        categories,
        action.categoryName,
        type,
      );
      if (categoryById != null) {
        categoryUuid = categoryById;
      } else if (requestedCategoryUuid?.isNotEmpty == true) {
        // A stale or mismatched UUID must not be persisted. A unique local
        // name match is a safe recovery; otherwise leave the current value.
        categoryUuid = categoryByName ?? existing.categoryUuid;
      } else if (action.categoryName?.trim().isNotEmpty == true) {
        categoryUuid = categoryByName ?? existing.categoryUuid;
      } else {
        categoryUuid = null;
      }
    }
    String? paymentMethodUuid = existing.paymentMethodUuid;
    if (action.hasPaymentMethod) {
      final requestedPaymentMethodUuid = action.paymentMethodUuid?.trim();
      final paymentMethodById = paymentMethods
          .where(
            (item) =>
                item.uuid == requestedPaymentMethodUuid && !item.isDeleted,
          )
          .map((item) => item.uuid)
          .firstOrNull;
      final paymentMethodByName = _findFinancePaymentUuid(
        paymentMethods,
        action.paymentMethodName,
      );
      if (paymentMethodById != null) {
        paymentMethodUuid = paymentMethodById;
      } else if (requestedPaymentMethodUuid?.isNotEmpty == true) {
        paymentMethodUuid = paymentMethodByName ?? existing.paymentMethodUuid;
      } else if (action.paymentMethodName?.trim().isNotEmpty == true) {
        paymentMethodUuid = paymentMethodByName ?? existing.paymentMethodUuid;
      } else {
        paymentMethodUuid = null;
      }
    }
    final requestedDate = action.transactionDate?.trim();
    final transactionDate =
        action.hasDate &&
            requestedDate != null &&
            isFinanceDateKey(requestedDate)
        ? requestedDate
        : existing.transactionDate;
    final occurredAt = transactionDate == existing.transactionDate
        ? existing.occurredAt
        : financeOccurrenceTimestampForDate(existing, transactionDate);

    final updated = FinanceTransaction(
      uuid: existing.uuid,
      type: type,
      amountMinor: action.hasAmount && action.amountMinor != null
          ? action.amountMinor!
          : existing.amountMinor,
      currencyCode: existing.currencyCode,
      categoryUuid: categoryUuid,
      paymentMethodUuid: paymentMethodUuid,
      transactionDate: transactionDate,
      occurredAt: occurredAt,
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
    if (occurredAt == null) updated.occurredAt = null;
    return updated;
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
    final matches = categories
        .where((item) => item.type == categoryType && !item.isDeleted)
        .where(
          (item) =>
              _normalizeFinanceOption(item.name) == wanted ||
              _normalizeFinanceOption(
                    financeCategoryDisplayName(item, categories),
                  ) ==
                  wanted,
        )
        .map((item) => item.uuid)
        .toSet();
    return matches.length == 1 ? matches.single : null;
  }

  String? _findFinancePaymentUuid(
    List<FinancePaymentMethod> methods,
    String? name,
  ) {
    final wanted = _normalizeFinanceOption(name);
    if (wanted.isEmpty) return null;
    final matches = methods
        .where((item) => !item.isDeleted)
        .where((item) => _normalizeFinanceOption(item.name) == wanted)
        .map((item) => item.uuid)
        .toSet();
    return matches.length == 1 ? matches.single : null;
  }

  String _normalizeFinanceOption(String? value) {
    return (value ?? '')
        .replaceAll(_financeOptionLeadingPunctuationPattern, '')
        .trim()
        .toLowerCase();
  }

  Future<void> _deleteFinanceAction(FinanceAiAction action) async {
    final id = action.transactionId;
    if (id == null || id.isEmpty) return;
    final existing = await FinanceRepository.getTransaction(id);
    if (!mounted) return;
    if (existing == null || existing.isDeleted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('这笔账单已不存在或已被删除，请重新查询后再操作')),
      );
      return;
    }

    final typeLabel = switch (existing.type) {
      FinanceTransactionType.expense => '支出',
      FinanceTransactionType.income => '收入',
      FinanceTransactionType.refund => '退款',
      FinanceTransactionType.transfer => '互转',
    };
    final merchant = existing.merchant?.trim();
    final note = existing.note?.trim();
    final details = [
      '${existing.transactionDate} · $typeLabel · ${formatFinanceAmount(existing.amountMinor)}',
      if (merchant?.isNotEmpty == true) '商家：$merchant',
      if (note?.isNotEmpty == true) '备注：$note',
    ].join('\n');
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔账单？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(details),
            const SizedBox(height: 12),
            const Text('账单会移入记账回收站，之后仍可恢复。'),
          ],
        ),
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
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('账单已移入回收站')),
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  Future<void> _ignoreFinanceAction(FinanceAiAction action) async {
    action.isIgnored = true;
    await _saveHistorySilently();
    if (mounted) setState(() {});
  }
}
