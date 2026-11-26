part of '../finance_entry_screen.dart';

extension _FinanceEntryActions on _FinanceEntryScreenState {
  Future<void> _openRepayment() async {
    final repayment = _linkedRepayment;
    if (repayment == null) return;
    try {
      final loan = await FinanceStorage.getLoan(
        repayment.loanUuid,
        includeDeleted: true,
      );
      if (!mounted) return;
      if (loan == null || loan.isDeleted) {
        _showError('请先在记账回收站恢复这笔贷款，再修改或撤销还款');
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => FinanceLoanDetailScreen(loan: loan)),
      );
      final transaction = await FinanceStorage.getTransaction(
        widget.transaction!.uuid,
      );
      if (!mounted || transaction == null) return;
      if (transaction.isDeleted) {
        Navigator.of(context).pop(transaction);
        return;
      }
      final currentRepayment =
          await FinanceStorage.getRepaymentForInterestTransaction(
            transaction.uuid,
          );
      if (!mounted) return;
      // Refresh repayment fields and version while keeping unsaved text edits.
      _mutateState(() {
        _editingTransaction = transaction;
        _linkedRepayment = currentRepayment;
        _type = transaction.type;
        _categoryUuid = transaction.categoryUuid;
        _paymentMethodUuid = transaction.paymentMethodUuid;
        _targetPaymentMethodUuid = transaction.targetPaymentMethodUuid;
        _date = dateFromKey(transaction.transactionDate);
        _occurredAt = transaction.occurrenceLocalTime;
        _occurrenceTimeExplicit = _occurredAt != null;
        _timezoneOffsetMinutes = transaction.timezoneOffsetMinutes;
        _amountController.text = formatFinanceAmount(
          transaction.amountMinor,
          withSymbol: false,
        );
      });
    } catch (error) {
      if (mounted) _showError('打开还款记录失败：$error');
    }
  }

  void _ensureFocusedFieldVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext == null) return;
      Scrollable.ensureVisible(
        focusedContext,
        alignment: 0.2,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showAmountCalculator() async {
    if (_isSaving) return;
    _dismissKeyboard();
    final result = await showFinanceAmountCalculator(
      context,
      initialExpression: _amountExpression ?? _amountController.text,
    );
    _dismissKeyboard();
    if (!mounted || result == null) return;
    _amountExpression = result.expression;
    _amountController.text = result.amount;
    _amountController.selection = TextSelection.collapsed(
      offset: result.amount.length,
    );
    _appendCalculationToNote(
      expression: result.expression,
      amount: result.amount,
    );
    _formKey.currentState?.validate();
  }

  Future<void> _pickDate() async {
    _dismissKeyboard();
    final refundOriginalDate = _isBoundRefund && _originalTransaction != null
        ? dateFromKey(_originalTransaction!.transactionDate)
        : null;
    if (refundOriginalDate != null &&
        refundOriginalDate.isAfter(DateTime.now())) {
      _showError('原支出尚未发生，不能录入退款');
      return;
    }
    final firstDate = refundOriginalDate ?? DateTime(2000);
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _date.isBefore(firstDate) ? firstDate : _date,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择账单日期',
    );
    _dismissKeyboard();
    if (picked == null || !mounted) return;
    final pickedDate = CalendarDateMath.dateOnly(picked);
    final now = DateTime.now();
    final shouldClearEstimatedTime =
        !_occurrenceTimeExplicit &&
        _defaultOccurrenceTimeFor(pickedDate, now) == null;
    _mutateState(() {
      _date = pickedDate;
      final occurredAt = _occurredAt;
      if (occurredAt != null) {
        _occurredAt = shouldClearEstimatedTime
            ? null
            : DateTime(
                _date.year,
                _date.month,
                _date.day,
                occurredAt.hour,
                occurredAt.minute,
              );
        if (widget.transaction == null && _occurredAt != null) {
          final isCurrentDefaultOccurrence =
              dateKey(pickedDate) == dateKey(now) &&
              occurredAt.hour == now.hour &&
              occurredAt.minute == now.minute;
          _timezoneOffsetMinutes = isCurrentDefaultOccurrence
              ? now.timeZoneOffset.inMinutes
              : _occurredAt!.timeZoneOffset.inMinutes;
        }
      }
    });
  }

  Future<void> _pickOccurrenceTime() async {
    if (_isSaving) return;
    _dismissKeyboard();
    final current = _occurredAt ?? DateTime.now();
    final picked = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: '选择账单发生时刻',
    );
    _dismissKeyboard();
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    _mutateState(() {
      _occurredAt = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
      );
      if (widget.transaction == null) {
        final isCurrentDefaultOccurrence =
            dateKey(_date) == dateKey(now) &&
            picked.hour == now.hour &&
            picked.minute == now.minute;
        _timezoneOffsetMinutes = isCurrentDefaultOccurrence
            ? now.timeZoneOffset.inMinutes
            : _occurredAt!.timeZoneOffset.inMinutes;
      }
      _occurrenceTimeExplicit = true;
    });
  }

  DateTime? _defaultOccurrenceTimeFor(DateTime date, DateTime now) {
    if (date.isBefore(CalendarDateMath.dateOnly(now))) return null;
    return DateTime(date.year, date.month, date.day, now.hour, now.minute);
  }

  Future<void> _applyQuickEntry() async {
    if (_isSaving) return;
    final input = _quickEntryController.text.trim();
    if (input.isEmpty) {
      _showError('请先描述账单，例如：今天午餐 28 元，微信支付，分类餐饮');
      return;
    }
    final drafts = FinanceTextParser.parseQuickEntries(input);
    if (drafts.isEmpty) {
      _showError('没有识别到金额；多笔账单可以用换行或分号分开');
      return;
    }

    _dismissKeyboard();
    if (drafts.length > 1) {
      await _reviewQuickEntries(drafts);
      return;
    }
    _applyQuickDraft(drafts.single);
  }

  void _applyQuickDraft(FinanceEntryDraft draft) {
    _dismissKeyboard();
    _mutateState(() {
      _type = draft.type;
      _date = dateFromKey(draft.transactionDate);
      final now = DateTime.now();
      _occurredAt = _defaultOccurrenceTimeFor(_date, now);
      _timezoneOffsetMinutes = financeDefaultOccurrenceTimezoneOffsetMinutes(
        occurrence: _occurredAt,
        now: now,
      );
      _occurrenceTimeExplicit = false;
      _amountExpression = null;
      _amountController.text = formatFinanceAmount(
        draft.amountMinor,
        withSymbol: false,
      );
      _merchantController.text = draft.merchant ?? '';
      _noteController.text = draft.note ?? '';
      _categoryUuid = draft.categoryUuid;
      _paymentMethodUuid = draft.paymentMethodUuid;
      _archivedCategoryRequiresSelection = false;
      _unmatchedDraftPaymentMethodName = null;
      _paymentMethodSelectionEdited = false;
      _selectedTemplateUuid = null;
      _clearArchivedNewEntryAssociations();
      _resolveSelectionsFromDraft(draft);
      _normalizeSelections(
        notify: false,
        allowDefaultCategory:
            !_archivedCategoryRequiresSelection &&
            !_shouldKeepUnresolvedDraftCategory(),
      );
    });
    _showMessage('已识别并填入表单，请核对后保存');
  }

  Future<void> _reviewQuickEntries(List<FinanceEntryDraft> drafts) async {
    final shouldReview = await showAppModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      requestFocus: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.76,
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '识别到 ${drafts.length} 笔账单',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '请逐笔核对后保存，缺少分类或关联账户可在编辑页补充',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.42,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: drafts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      final isIncome =
                          draft.type == FinanceTransactionType.income;
                      return RepaintBoundary(
                        key: ValueKey<int>(index),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: isIncome
                                ? colorScheme.tertiaryContainer
                                : colorScheme.primaryContainer,
                            child: Icon(
                              isIncome
                                  ? Icons.south_west_rounded
                                  : Icons.north_east_rounded,
                              color: isIncome
                                  ? colorScheme.onTertiaryContainer
                                  : colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            '${draft.type.label} · '
                            '${formatFinanceAmount(draft.amountMinor)}',
                          ),
                          subtitle: Text(
                            _quickDraftSummary(draft),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('返回修改'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('逐笔确认'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    _dismissKeyboard();
    if (shouldReview != true || !mounted) return;

    var savedCount = 0;
    for (final draft in drafts) {
      if (!mounted) return;
      final saved = await Navigator.of(context).push<FinanceTransaction>(
        MaterialPageRoute(
          builder: (_) => FinanceEntryScreen(initialDraft: draft),
        ),
      );
      if (saved != null) savedCount++;
    }
    _dismissKeyboard();
    if (!mounted) return;
    if (savedCount > 0) {
      _quickEntryController.clear();
      _showMessage('已保存 $savedCount/${drafts.length} 笔账单');
    }
  }

  String _quickDraftSummary(FinanceEntryDraft draft) {
    final parts = <String>[draft.transactionDate];
    final category = draft.categoryName?.trim();
    final merchant = draft.merchant?.trim();
    final payment = draft.paymentMethodName?.trim();
    parts.add(category == null || category.isEmpty ? '待选择分类' : category);
    if (merchant != null && merchant.isNotEmpty) parts.add(merchant);
    if (payment != null && payment.isNotEmpty) parts.add(payment);
    return parts.join(' · ');
  }

  Future<void> _save() async {
    if (_isSaving || _isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final amount = parseFinanceAmount(_amountController.text);
    if (amount == null) {
      _showError('请输入大于 0 且不超过两位小数的金额');
      return;
    }
    if (_isBoundRefund && _originalTransaction == null) {
      _showError('原账单不存在或已删除，无法保存这笔退款');
      return;
    }
    if (_isBoundRefund && amount > _remainingRefundableMinor) {
      _showError(
        '退款金额不能超过剩余可退金额 '
        '${formatFinanceAmount(_remainingRefundableMinor)}',
      );
      return;
    }

    final installmentCount = _installmentEnabled
        ? int.tryParse(_installmentCountController.text.trim())
        : 1;
    if (installmentCount == null ||
        (_installmentEnabled &&
            (installmentCount < FinanceInstallmentCalculator.minCount ||
                installmentCount > FinanceInstallmentCalculator.maxCount))) {
      _showError(
        '分期月数必须在 ${FinanceInstallmentCalculator.minCount}-'
        '${FinanceInstallmentCalculator.maxCount} 之间',
      );
      return;
    }
    if (_installmentEnabled && installmentCount > amount) {
      _showError('分期月数不能超过金额的分（人民币分）');
      return;
    }

    _mutateState(() => _isSaving = true);
    final old = _editingTransaction;
    final now = DateTime.now().millisecondsSinceEpoch;
    final transaction = FinanceTransaction(
      uuid: old?.uuid,
      type: _type,
      amountMinor: amount,
      currencyCode: old?.currencyCode ?? FinanceDefaults.defaultCurrencyCode,
      categoryUuid: _type == FinanceTransactionType.transfer
          ? null
          : _categoryUuid,
      paymentMethodUuid: _paymentMethodUuid,
      targetPaymentMethodUuid: _type == FinanceTransactionType.transfer
          ? _targetPaymentMethodUuid
          : null,
      transactionDate: dateKey(_date),
      occurredAt: _occurredAt == null
          ? old?.occurredAt ?? now
          : DateTime.utc(
                  _occurredAt!.year,
                  _occurredAt!.month,
                  _occurredAt!.day,
                  _occurredAt!.hour,
                  _occurredAt!.minute,
                  _occurredAt!.second,
                  _occurredAt!.millisecond,
                ).millisecondsSinceEpoch -
                _timezoneOffsetMinutes * 60000,
      timezoneOffsetMinutes: _timezoneOffsetMinutes,
      merchant: _emptyToNull(_merchantController.text),
      note: _noteWithCalculation(),
      source:
          old?.source ??
          widget.initialDraft?.source ??
          FinanceEntrySource.manual,
      relatedTodoUuid: old?.relatedTodoUuid,
      relatedPlanBlockUuid: old?.relatedPlanBlockUuid,
      relatedTransactionUuid:
          _originalTransaction?.uuid ?? old?.relatedTransactionUuid,
      isDeleted: false,
      version: old?.version ?? 1,
      createdAt: old?.createdAt ?? now,
      updatedAt: old?.updatedAt ?? now,
      deviceId: old?.deviceId,
    );
    if (old != null && _occurredAt == null) {
      // This form state means the saved occurrence is missing or does not
      // match the ledger date. Keeping a stale timestamp can make a future
      // bill look as though it already happened.
      transaction.occurredAt = null;
    }
    if (old != null) transaction.markAsChanged();

    try {
      final List<FinanceTransaction> saved;
      if (installmentCount > 1) {
        saved = await FinanceRepository.saveInstallmentPlan(
          transaction: transaction,
          original: old,
          totalAmountMinor: amount,
          installmentCount: installmentCount,
          startDate: _date,
          existingInstallments: _existingInstallments.isNotEmpty
              ? _existingInstallments
              : old == null
              ? const []
              : [old],
        );
      } else {
        await FinanceRepository.saveTransaction(transaction, original: old);
        saved = [transaction];
      }
      if (_selectedTemplateUuid != null) {
        try {
          await FinanceRepository.markTemplateUsed(_selectedTemplateUuid!);
        } catch (_) {
          // 模板使用次数是辅助信息，不应影响账单保存结果。
        }
      }
      if (!mounted) return;
      _saveCompleted = true;
      final activeSaved = saved.where((item) => !item.isDeleted).toList();
      final result = activeSaved.firstWhere(
        (item) => item.uuid == old?.uuid,
        orElse: () => activeSaved.isEmpty ? saved.first : activeSaved.first,
      );
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      _mutateState(() => _isSaving = false);
      _showError('保存失败：$error');
    }
  }

  String? _emptyToNull(String value) => AppTextUtils.trimToNull(value);

  String? _noteWithCalculation() {
    return _noteWithExpression(
      noteText: _noteController.text,
      expression: _amountExpression,
      amount: _amountController.text,
    );
  }

  String? _noteWithExpression({
    required String noteText,
    required String? expression,
    required String amount,
  }) {
    final note = _emptyToNull(noteText);
    final trimmedExpression = expression?.trim();
    if (expression == null ||
        trimmedExpression == null ||
        trimmedExpression.isEmpty ||
        !_expressionOperatorPattern.hasMatch(trimmedExpression)) {
      return note;
    }

    final trimmedAmount = amount.trim();
    if (trimmedAmount.isEmpty) return note;
    final calculationLine = '计算：$trimmedExpression = $trimmedAmount';
    if (note == null) return calculationLine;
    final hasSameLine = note
        .split(_expressionLineBreakPattern)
        .any((line) => line.trim() == calculationLine);
    return hasSameLine ? note : '$note\n$calculationLine';
  }

  void _appendCalculationToNote({
    required String expression,
    required String amount,
  }) {
    final current = _noteController.text;
    final next = _noteWithExpression(
      noteText: current,
      expression: expression,
      amount: amount,
    );
    if (next == null || next == current) return;
    _noteController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _showError(String message) {
    AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    AppSnackBars.hideCurrent(messenger);
    AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
  }
}
