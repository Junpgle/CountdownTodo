part of '../finance_widgets.dart';

extension _FinanceLedgerActionsExt on _FinanceLedgerPanelState {
  void _toggleSelectionMode() {
    _mutateState(() {
      _selectionMode = !_selectionMode;
      if (_selectionMode) {
        _summaryExpanded = true;
      } else {
        _hasCommittedSelection = _selectedTransactionUuids.isNotEmpty;
      }
    });
  }

  void _clearSelection() {
    _mutateState(() {
      _selectedTransactionUuids.clear();
      _hasCommittedSelection = false;
    });
  }

  void _toggleTransactionSelection(FinanceTransaction transaction) {
    _mutateState(() {
      if (!_selectedTransactionUuids.add(transaction.uuid)) {
        _selectedTransactionUuids.remove(transaction.uuid);
      }
    });
  }

  void _toggleSelectAll(List<_FinanceLedgerOrderEntry> filtered) {
    final visibleUuids = filtered
        .map((entry) => entry.transaction.uuid)
        .toSet();
    _mutateState(() {
      if (visibleUuids.isNotEmpty &&
          visibleUuids.every(_selectedTransactionUuids.contains)) {
        _selectedTransactionUuids.removeAll(visibleUuids);
      } else {
        _selectedTransactionUuids.addAll(visibleUuids);
      }
    });
  }

  void _enterSelectionModeWith(FinanceTransaction transaction) {
    _mutateState(() {
      _selectionMode = true;
      _summaryExpanded = true;
      _selectedTransactionUuids.add(transaction.uuid);
    });
  }

  ({
    FinanceCategoryType? type,
    String? error,
    List<FinanceTransaction> eligible,
  })
  _resolveBatchCategoryContext(List<FinanceTransaction> selected) {
    final eligible = selected
        .where((item) => item.type != FinanceTransactionType.transfer)
        .toList(growable: false);
    if (eligible.isEmpty) {
      return (
        type: null,
        error: '转账记录不支持修改分类',
        eligible: const <FinanceTransaction>[],
      );
    }
    final types = eligible
        .map((item) => financeCategoryTypeForTransaction(item.type))
        .toSet();
    if (types.length > 1) {
      return (
        type: null,
        error: '所选账单同时包含支出和收入，请分开选择后再修改分类',
        eligible: const <FinanceTransaction>[],
      );
    }
    return (type: types.first, error: null, eligible: eligible);
  }

  void _applyLedgerDateToTransaction(
    FinanceTransaction updated,
    DateTime pickedDate,
  ) {
    final targetDate = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
    );
    updated.transactionDate = dateKey(targetDate);
    final localTime = updated.occurrenceLocalTime;
    final utcMillis = DateTime.utc(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      localTime?.hour ?? 12,
      localTime?.minute ?? 0,
      localTime?.second ?? 0,
      localTime?.millisecond ?? 0,
    ).millisecondsSinceEpoch;
    updated.occurredAt = utcMillis - updated.timezoneOffsetMinutes * 60000;
  }

  Future<void> _saveBatchTransactions(
    List<FinanceTransaction> updated, {
    required String successMessage,
  }) async {
    if (updated.isEmpty || _isBatchSaving) return;
    _mutateState(() => _isBatchSaving = true);
    try {
      final saver =
          widget.onBatchSave ?? FinanceRepository.saveTransactionsBatch;
      await saver(updated);
      if (!mounted) return;
      _mutateState(() {
        _selectionMode = false;
        _hasCommittedSelection = false;
        _selectedTransactionUuids.clear();
      });
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text(successMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('批量保存失败：$e')));
    } finally {
      if (mounted) {
        _mutateState(() => _isBatchSaving = false);
      }
    }
  }

  Future<void> _batchEditCategory(List<FinanceTransaction> selected) async {
    if (_isBatchSaving || selected.isEmpty) return;
    final ctx = _resolveBatchCategoryContext(selected);
    if (ctx.error != null || ctx.type == null) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text(ctx.error ?? '无法修改分类')),
      );
      return;
    }
    final choice = await showAppDialog<_FinanceBatchFieldChoice<String?>>(
      context: context,
      builder: (context) => _FinanceBatchCategoryPickerDialog(
        categories: categories,
        categoryType: ctx.type!,
        selectedCount: ctx.eligible.length,
      ),
    );
    if (choice == null || !mounted) return;
    final updated = <FinanceTransaction>[];
    for (final item in ctx.eligible) {
      if (item.categoryUuid == choice.value) continue;
      final copy = FinanceTransaction.fromMap(item.toMap());
      copy.categoryUuid = choice.value;
      copy.markAsChanged();
      updated.add(copy);
    }
    if (updated.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('所选账单分类未发生变化')),
      );
      return;
    }
    final skippedTransfers = selected.length - ctx.eligible.length;
    final categoryLabel = choice.value == null
        ? '未分类'
        : _categoryDisplayName(choice.value);
    final suffix = skippedTransfers > 0 ? '（已跳过 $skippedTransfers 笔转账）' : '';
    await _saveBatchTransactions(
      updated,
      successMessage: '已将 ${updated.length} 笔账单分类改为「$categoryLabel」$suffix',
    );
  }

  Future<void> _batchEditPaymentMethod(
    List<FinanceTransaction> selected,
  ) async {
    if (_isBatchSaving || selected.isEmpty) return;
    final choice = await showAppDialog<_FinanceBatchFieldChoice<String?>>(
      context: context,
      builder: (context) => _FinanceBatchPaymentMethodPickerDialog(
        paymentMethods: paymentMethods,
        selectedCount: selected.length,
      ),
    );
    if (choice == null || !mounted) return;
    final updated = <FinanceTransaction>[];
    var skippedSelfTransfers = 0;
    for (final item in selected) {
      if (item.type == FinanceTransactionType.transfer &&
          choice.value != null &&
          choice.value == item.targetPaymentMethodUuid) {
        skippedSelfTransfers++;
        continue;
      }
      if (item.paymentMethodUuid == choice.value) continue;
      final copy = FinanceTransaction.fromMap(item.toMap());
      copy.paymentMethodUuid = choice.value;
      copy.markAsChanged();
      updated.add(copy);
    }
    if (updated.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            skippedSelfTransfers > 0 ? '转账的转出账户不能与转入账户相同' : '所选账单账户未发生变化',
          ),
        ),
      );
      return;
    }
    final pm = choice.value == null ? null : paymentMethods[choice.value];
    final pmLabel = pm == null ? '未指定账户' : _paymentMethodDisplayName(pm);
    final suffix = skippedSelfTransfers > 0
        ? '（已跳过 $skippedSelfTransfers 笔同账户转账）'
        : '';
    await _saveBatchTransactions(
      updated,
      successMessage: '已将 ${updated.length} 笔账单账户改为「$pmLabel」$suffix',
    );
  }

  Future<void> _batchEditMultipleFields(
    List<FinanceTransaction> selected,
  ) async {
    if (_isBatchSaving || selected.isEmpty) return;
    final categoryContext = _resolveBatchCategoryContext(selected);
    final result = await showAppDialog<_FinanceBatchEditResult>(
      context: context,
      builder: (context) => _FinanceBatchEditDialog(
        selectedCount: selected.length,
        categories: categories,
        paymentMethods: paymentMethods,
        categoryType: categoryContext.type,
        categoryDisabledReason: categoryContext.error,
        initialDate: widget.clock(),
      ),
    );
    if (result == null || !mounted) return;
    final updated = <FinanceTransaction>[];
    for (final item in selected) {
      final copy = FinanceTransaction.fromMap(item.toMap());
      var changed = false;
      if (result.applyCategory &&
          item.type != FinanceTransactionType.transfer &&
          copy.categoryUuid != result.categoryUuid) {
        copy.categoryUuid = result.categoryUuid;
        changed = true;
      }
      if (result.applyPaymentMethod) {
        final conflictsTransferTarget =
            item.type == FinanceTransactionType.transfer &&
            result.paymentMethodUuid != null &&
            result.paymentMethodUuid == item.targetPaymentMethodUuid;
        if (!conflictsTransferTarget &&
            copy.paymentMethodUuid != result.paymentMethodUuid) {
          copy.paymentMethodUuid = result.paymentMethodUuid;
          changed = true;
        }
      }
      if (result.applyDate && result.date != null) {
        final nextKey = dateKey(result.date!);
        if (copy.transactionDate != nextKey) {
          _applyLedgerDateToTransaction(copy, result.date!);
          changed = true;
        }
      }
      if (result.applyMerchant) {
        final nextMerchant = result.merchant?.trim();
        final normalized = nextMerchant == null || nextMerchant.isEmpty
            ? null
            : nextMerchant;
        if (copy.merchant != normalized) {
          copy.merchant = normalized;
          changed = true;
        }
      }
      if (result.applyNote) {
        final nextNote = result.note?.trim();
        final normalized = nextNote == null || nextNote.isEmpty
            ? null
            : nextNote;
        if (copy.note != normalized) {
          copy.note = normalized;
          changed = true;
        }
      }
      if (changed) {
        copy.markAsChanged();
        updated.add(copy);
      }
    }
    if (updated.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('所选账单未发生变化')),
      );
      return;
    }
    await _saveBatchTransactions(
      updated,
      successMessage: '已批量修改 ${updated.length} 笔账单',
    );
  }

  Future<void> _batchDeleteSelected(List<FinanceTransaction> selected) async {
    if (_isBatchSaving || selected.isEmpty) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除所选 ${selected.length} 笔账单？'),
        content: const Text('删除后将移入回收站，不会计入统计，也可在回收站恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _mutateState(() => _isBatchSaving = true);
    try {
      if (widget.onBatchDelete != null) {
        await widget.onBatchDelete!(selected);
      } else {
        final selectedUuids = selected.map((item) => item.uuid).toSet();
        for (final item in selected) {
          if (item.type != FinanceTransactionType.expense) continue;
          final refunds = await FinanceRepository.getRefundsForTransaction(
            item.uuid,
          );
          final hasUnselectedRefund = refunds.any(
            (refund) => !selectedUuids.contains(refund.uuid),
          );
          if (hasUnselectedRefund) {
            if (!mounted) return;
            AppSnackBars.showSnackBar(
              context,
              const SnackBar(content: Text('部分支出账单已关联退款，请先处理退款或一并选中退款记录')),
            );
            return;
          }
        }
        final toDelete = <FinanceTransaction>[];
        for (final item in selected) {
          final copy = FinanceTransaction.fromMap(item.toMap());
          copy.isDeleted = true;
          copy.markAsChanged();
          toDelete.add(copy);
        }
        final saver =
            widget.onBatchSave ?? FinanceRepository.saveTransactionsBatch;
        await saver(toDelete);
      }
      if (!mounted) return;
      _mutateState(() {
        _selectionMode = false;
        _hasCommittedSelection = false;
        _selectedTransactionUuids.clear();
      });
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('已删除 ${selected.length} 笔账单')),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('批量删除失败：$e')));
    } finally {
      if (mounted) {
        _mutateState(() => _isBatchSaving = false);
      }
    }
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    FinanceTransactionType? type,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: filterType == type,
        onSelected: (_) => _updateFilterType(type),
      ),
    );
  }

  Widget _buildCategoryFilterChip(BuildContext context) {
    final selected = categoryUuids;
    final category =
        selected.length == 1 &&
            selected.first != financeUncategorizedCategoryFilterUuid
        ? categories[selected.first]
        : null;
    final label = selected.isEmpty
        ? '分类筛选'
        : selected.length == 1 &&
              selected.first == financeUncategorizedCategoryFilterUuid
        ? '分类 · 未分类'
        : '分类 · ${selected.length} 项';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        key: const ValueKey('finance-ledger-category-filter'),
        avatar: category == null ? null : Text(category.icon),
        label: Text(label),
        selected: selected.isNotEmpty,
        onSelected: (_) {
          if (widget.categoryUuids == null &&
              widget.categoryUuid != null &&
              widget.onCategoryUuidsChanged == null) {
            _updateCategoryFilters(<String>{});
          } else {
            _pickCategories();
          }
        },
      ),
    );
  }

  Widget _buildDateRangeFilterChip(BuildContext context) {
    final now = widget.clock();
    final month = widget.month ?? now;
    final range =
        dateRange ??
        DateTimeRange(
          start: DateTime(month.year, month.month),
          end: DateTime(month.year, month.month + 1, 0),
        );
    final isCustomRange = dateRange != null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        key: const ValueKey('finance-ledger-date-range-filter'),
        avatar: const Icon(Icons.date_range_outlined, size: 18),
        label: Text(
          '${dateKey(range.start)} – ${dateKey(range.end)}',
          maxLines: 1,
        ),
        onPressed: _pickDateRange,
        onDeleted: isCustomRange ? _resetDateRange : null,
        deleteButtonTooltipMessage: '恢复当前月',
      ),
    );
  }

  Widget _buildSummaryFooter(
    BuildContext context,
    List<_FinanceLedgerOrderEntry> filtered,
    int nowAt, {
    required VoidCallback onCollapse,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final showSelectedTotals = _selectionMode || _hasCommittedSelection;
    final selectedEntries = showSelectedTotals
        ? filtered
              .where(
                (entry) =>
                    _selectedTransactionUuids.contains(entry.transaction.uuid),
              )
              .toList(growable: false)
        : filtered;
    final totals = _FinanceLedgerTotals.fromEntries(selectedEntries, nowAt);
    final selectedCount = selectedEntries.length;
    final allVisibleSelected =
        filtered.isNotEmpty &&
        filtered.every(
          (entry) => _selectedTransactionUuids.contains(entry.transaction.uuid),
        );
    final amountLabels = <String>[
      if (totals.expenseMinor > 0)
        '支出 ${formatFinanceAmount(totals.expenseMinor)}',
      if (totals.refundMinor > 0)
        '退款 ${formatFinanceAmount(totals.refundMinor)}',
      if (totals.expenseMinor > 0 || totals.refundMinor > 0)
        '净支出 ${formatFinanceAmount(totals.netExpenseMinor)}',
      if (totals.incomeMinor > 0)
        '收入 ${formatFinanceAmount(totals.incomeMinor)}',
    ];
    final plannedLabels = <String>[
      if (totals.plannedExpenseMinor > 0)
        '计划支出 ${formatFinanceAmount(totals.plannedExpenseMinor)}',
      if (totals.plannedRefundMinor > 0)
        '计划退款 ${formatFinanceAmount(totals.plannedRefundMinor)}',
      if (totals.plannedIncomeMinor > 0)
        '计划收入 ${formatFinanceAmount(totals.plannedIncomeMinor)}',
    ];

    return Card(
      color: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _selectionMode
                        ? Icons.checklist_rounded
                        : Icons.analytics_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    showSelectedTotals
                        ? '${_selectionMode ? '已选' : '所选'} $selectedCount 笔 / ${filtered.length} 笔'
                        : '筛选结果 · ${filtered.length} 笔',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_selectionMode) ...[
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: filtered.isEmpty
                        ? null
                        : () => _toggleSelectAll(filtered),
                    child: Text(allVisibleSelected ? '取消全选' : '全选'),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: _toggleSelectionMode,
                    child: const Text('完成'),
                  ),
                ] else if (_hasCommittedSelection) ...[
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: _toggleSelectionMode,
                    child: const Text('继续选择'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: _clearSelection,
                    child: const Text('清除'),
                  ),
                ] else ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _toggleSelectionMode,
                    icon: const Icon(Icons.checklist_rounded, size: 16),
                    label: const Text('选择账单'),
                  ),
                ],
                const SizedBox(width: 2),
                IconButton(
                  key: const ValueKey('finance-ledger-summary-collapse'),
                  tooltip: '收起账单合计',
                  visualDensity: VisualDensity.compact,
                  onPressed: onCollapse,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (amountLabels.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final label in amountLabels)
                    _buildSummaryMetricChip(context, label),
                ],
              )
            else if (selectedCount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _selectionMode ? '勾选账单后查看所选合计' : '暂无可合计的账目',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            if (plannedLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        plannedLabels.join(' · '),
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (showSelectedTotals && selectedCount > 0) ...[
              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 8),
              _buildBatchActionBar(
                context,
                selectedEntries
                    .map((entry) => entry.transaction)
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBatchActionBar(
    BuildContext context,
    List<FinanceTransaction> selectedTransactions,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final buttonStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(0, 32),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FilledButton.tonalIcon(
          key: const ValueKey('finance-ledger-batch-category'),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
          ),
          onPressed: _isBatchSaving
              ? null
              : () => _batchEditCategory(selectedTransactions),
          icon: const Icon(Icons.category_outlined, size: 15),
          label: const Text('改分类'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('finance-ledger-batch-payment-method'),
          style: buttonStyle,
          onPressed: _isBatchSaving
              ? null
              : () => _batchEditPaymentMethod(selectedTransactions),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 15),
          label: const Text('改账户'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('finance-ledger-batch-edit'),
          style: buttonStyle,
          onPressed: _isBatchSaving
              ? null
              : () => _batchEditMultipleFields(selectedTransactions),
          icon: const Icon(Icons.edit_note_rounded, size: 16),
          label: const Text('批量修改'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('finance-ledger-batch-delete'),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            foregroundColor: colorScheme.error,
            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.45)),
          ),
          onPressed: _isBatchSaving
              ? null
              : () => _batchDeleteSelected(selectedTransactions),
          icon: const Icon(Icons.delete_outline_rounded, size: 15),
          label: const Text('删除'),
        ),
      ],
    );
  }

  Widget _buildSummaryMetricChip(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final isIncome = label.startsWith('收入');
    final isNetExpense = label.startsWith('净支出');
    final isRefund = label.startsWith('退款');

    final Color fgColor;
    final Color bgColor;
    final Color borderColor;
    final IconData icon;

    if (isNetExpense) {
      fgColor = colorScheme.error;
      bgColor = colorScheme.errorContainer.withValues(alpha: 0.28);
      borderColor = colorScheme.error.withValues(alpha: 0.22);
      icon = Icons.trending_down_rounded;
    } else if (isIncome) {
      fgColor = colorScheme.primary;
      bgColor = colorScheme.primaryContainer.withValues(alpha: 0.32);
      borderColor = colorScheme.primary.withValues(alpha: 0.22);
      icon = Icons.trending_up_rounded;
    } else if (isRefund) {
      fgColor = colorScheme.tertiary;
      bgColor = colorScheme.tertiaryContainer.withValues(alpha: 0.28);
      borderColor = colorScheme.tertiary.withValues(alpha: 0.22);
      icon = Icons.replay_rounded;
    } else {
      fgColor = colorScheme.onSurface;
      bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
      borderColor = colorScheme.outlineVariant.withValues(alpha: 0.3);
      icon = Icons.shopping_bag_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fgColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    _FinanceDayGroup group, {
    required bool hideAmountsDuplicatedByFooter,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasExpenseFlow = group.expenseMinor > 0 || group.refundMinor > 0;
    final hasPlannedExpenseFlow =
        group.plannedExpenseMinor > 0 || group.plannedRefundMinor > 0;
    final amountLabels = <String>[
      if (hasExpenseFlow && !hideAmountsDuplicatedByFooter)
        '净支出 ${formatFinanceAmount(group.netExpenseMinor)}',
      if (hasPlannedExpenseFlow)
        '计划净支出 ${formatFinanceAmount(group.plannedNetExpenseMinor)}',
      if (group.incomeMinor > 0 && !hideAmountsDuplicatedByFooter)
        '收入 ${formatFinanceAmount(group.incomeMinor)}',
      if (group.plannedIncomeMinor > 0 && !hideAmountsDuplicatedByFooter)
        '计划收入 ${formatFinanceAmount(group.plannedIncomeMinor)}',
    ];
    if (amountLabels.isEmpty && !hideAmountsDuplicatedByFooter) {
      amountLabels.add('${group.transactions.length} 笔');
    }
    Color labelColor(String label) {
      if (label.contains('收入')) return colorScheme.primary;
      final netExpenseMinor = label.startsWith('计划净支出')
          ? group.plannedNetExpenseMinor
          : group.netExpenseMinor;
      return netExpenseMinor > 0
          ? colorScheme.error
          : colorScheme.onSurfaceVariant;
    }

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.calendar_today_outlined,
                size: 15,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatFinanceDayLabel(group.date),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${group.transactions.length} 笔账单',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final label in amountLabels)
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: labelColor(label),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(
    BuildContext context,
    FinanceTransaction transaction,
    int asOfAt, {
    required bool selectionMode,
    required bool selected,
    required VoidCallback onToggleSelection,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = categories[transaction.categoryUuid];
    final payment = paymentMethods[transaction.paymentMethodUuid];
    final paymentName = payment == null
        ? null
        : _paymentMethodDisplayName(payment);
    final categoryName = _categoryDisplayName(transaction.categoryUuid);
    final merchant = transaction.merchant?.trim();
    final note = transaction.note?.trim();
    final hasCategory =
        category != null || transaction.categoryUuid?.trim().isNotEmpty == true;
    final titleUsesCategory =
        merchant?.isNotEmpty != true && note?.isNotEmpty != true && hasCategory;
    final title = merchant?.isNotEmpty == true
        ? merchant!
        : note?.isNotEmpty == true
        ? note!
        : titleUsesCategory
        ? categoryName
        : transaction.type.label;
    final subtitleParts = <String>[
      if (transaction.balanceEventAt() > asOfAt) '待发生',
      if (!titleUsesCategory)
        category == null
            ? categoryName
            : '${category.icon} $categoryName${category.isArchived ? '（已归档）' : ''}',
      if (payment != null)
        '${payment.icon} $paymentName${payment.isArchived ? '（已归档）' : ''}'
      else if (transaction.paymentMethodUuid?.trim().isNotEmpty == true)
        switch (transaction.type) {
          FinanceTransactionType.expense => '已删除或未知付款方式',
          FinanceTransactionType.income => '已删除或未知到账账户',
          FinanceTransactionType.refund => '已删除或未知退款到账账户',
          FinanceTransactionType.transfer => '已删除或未知转出账户',
        },
      if (transaction.installmentLabel != null)
        '分期 ${transaction.installmentLabel}',
      if (note?.isNotEmpty == true && note != title) note!,
    ];
    final amountColor = transaction.type == FinanceTransactionType.expense
        ? colorScheme.error
        : colorScheme.primary;
    final sourceKey = _cardKeyFor(transaction);
    return RepaintBoundary(
      child: Card(
        key: sourceKey,
        elevation: 0,
        margin: EdgeInsets.zero,
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.8)
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: selectionMode
              ? onToggleSelection
              : () => onOpenDetail(transaction, sourceKey),
          onLongPress: selectionMode
              ? null
              : () => _enterSelectionModeWith(transaction),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 3,
          ),
          leading: selectionMode
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelection(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                )
              : Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    category?.icon ?? '💰',
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
          ),
          subtitle: Text(
            subtitleParts.isEmpty
                ? transaction.type.label
                : subtitleParts.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width - 120).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    formatSignedFinanceAmount(
                      transaction.amountMinor,
                      transaction.type,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: amountColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onSelected: (value) {
                    if (value == 'refund') onRefund(transaction);
                    if (value == 'edit') onEdit(transaction);
                    if (value == 'delete') onDelete(transaction);
                  },
                  itemBuilder: (context) => [
                    if (transaction.type == FinanceTransactionType.expense)
                      const PopupMenuItem(value: 'refund', child: Text('退款')),
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = widget.clock();
    final selectedMonth = widget.month ?? now;
    final monthLabel =
        selectedMonth.year == now.year && selectedMonth.month == now.month
        ? '本月'
        : '${selectedMonth.year}年${selectedMonth.month}月';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            keyword.trim().isEmpty &&
                    filterType == null &&
                    categoryUuids.isEmpty &&
                    dateRange == null
                ? '$monthLabel还没有账单'
                : '没有匹配的账单',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryError(BuildContext context, String error) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 42, color: colorScheme.error),
            const SizedBox(height: 10),
            const Text('筛选账单加载失败'),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
