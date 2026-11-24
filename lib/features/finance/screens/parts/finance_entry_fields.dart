part of '../finance_entry_screen.dart';

extension _FinanceEntryFields on _FinanceEntryScreenState {
  Widget _buildDateField(ColorScheme colorScheme) {
    return Material(
      color: colorScheme.surface.withValues(alpha: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isSaving || _isLoanInterest ? null : _pickDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 21,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '账单日期',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                dateKey(_date),
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOccurrenceTimeField(ColorScheme colorScheme) {
    final occurredAt = _occurredAt;
    final localTimezoneOffset = occurredAt == null
        ? null
        : _deviceTimezoneOffsetForOccurrence(occurredAt);
    final timeLabel = occurredAt == null
        ? '补充时间'
        : '${occurredAt.hour.toString().padLeft(2, '0')}:'
              '${occurredAt.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: colorScheme.surface.withValues(alpha: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.82),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _isSaving || _isLoanInterest ? null : _pickOccurrenceTime,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 21,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '发生时刻',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (occurredAt == null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '这笔账单没有与日期匹配的发生时刻，余额计算暂按录入时间估算。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
        if (occurredAt != null &&
            _timezoneOffsetMinutes != localTimezoneOffset) ...[
          const SizedBox(height: 6),
          Text(
            '按记录时区 ${financeTimezoneLabel(_timezoneOffsetMinutes)} 显示',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  int _deviceTimezoneOffsetForOccurrence(DateTime occurrence) {
    final occurrenceAt =
        DateTime.utc(
          occurrence.year,
          occurrence.month,
          occurrence.day,
          occurrence.hour,
          occurrence.minute,
          occurrence.second,
          occurrence.millisecond,
          occurrence.microsecond,
        ).millisecondsSinceEpoch -
        _timezoneOffsetMinutes * 60000;
    return DateTime.fromMillisecondsSinceEpoch(occurrenceAt)
        .timeZoneOffset
        .inMinutes;
  }

  Widget _buildInstallmentField(ColorScheme colorScheme) {
    if (_type != FinanceTransactionType.expense) {
      return const SizedBox.shrink();
    }
    final hasPlan = _installmentEnabled;
    final now = DateTime.now();
    final selectedMonthLabel =
        _date.year == now.year && _date.month == now.month
        ? '当前月份'
        : '${_date.year}年${_date.month}月';
    final subtitle = _isEditingInstallment
        ? '修改表单内容时，会同步更新全部分期'
        : hasPlan
        ? '从 ${dateKey(_date)} 开始，每月记入一期账单'
        : '将整笔金额一次性计入$selectedMonthLabel';
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.52),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.82),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              secondary: Icon(
                Icons.calendar_month_outlined,
                color: colorScheme.primary,
              ),
              title: Text(
                _isEditingInstallment ? '分期账单' : '分期付款',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(subtitle),
              value: hasPlan,
              onChanged: _isSaving || _isEditingInstallment
                  ? null
                  : (value) {
                      _mutateState(() {
                        _installmentEnabled = value;
                        if (value) {
                          _installmentCount =
                              FinanceInstallmentCalculator.minCount;
                          _installmentCountController.text = _installmentCount
                              .toString();
                        }
                      });
                    },
            ),
          ),
          if (hasPlan) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: TextFormField(
                controller: _installmentCountController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                inputFormatters: _installmentCountInputFormatters,
                decoration: _fieldDecoration(
                  colorScheme,
                  labelText: '分期月数',
                  prefixIcon: Icons.repeat_rounded,
                  hintText: '${FinanceInstallmentCalculator.minCount}',
                  suffixText: '个月',
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null) {
                    _mutateState(() => _installmentCount = parsed);
                  }
                },
                validator: (value) {
                  final count = int.tryParse(value?.trim() ?? '');
                  if (count == null ||
                      count < FinanceInstallmentCalculator.minCount ||
                      count > FinanceInstallmentCalculator.maxCount) {
                    return '请输入 ${FinanceInstallmentCalculator.minCount}-'
                        '${FinanceInstallmentCalculator.maxCount} 个月';
                  }
                  final amount = parseFinanceAmount(_amountController.text);
                  if (amount != null && count > amount) {
                    return '期数不能超过金额的分（人民币分）';
                  }
                  return null;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '金额按分精确分摊，无法整除时前几期会多 1 分。',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionalFields(ColorScheme colorScheme, {required bool isWide}) {
    final merchant = TextFormField(
      key: const ValueKey('finance-merchant-field'),
      controller: _merchantController,
      textInputAction: TextInputAction.next,
      maxLength: 80,
      onTap: _ensureFocusedFieldVisible,
      decoration: _fieldDecoration(
        colorScheme,
        labelText: '商家（可选）',
        counterText: '',
      ),
    );
    final note = TextFormField(
      key: const ValueKey('finance-note-field'),
      controller: _noteController,
      maxLines: 2,
      maxLength: 300,
      onTap: _ensureFocusedFieldVisible,
      decoration: _fieldDecoration(
        colorScheme,
        labelText: '备注（可选）',
        counterText: '',
        alignLabelWithHint: true,
      ),
    );
    if (!isWide) {
      return Column(children: [merchant, const SizedBox(height: 14), note]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: merchant),
        const SizedBox(width: 12),
        Expanded(child: note),
      ],
    );
  }

  ButtonStyle _primaryButtonStyle(ColorScheme colorScheme) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(colorScheme.primary),
      backgroundBuilder: (context, states, child) =>
          child ?? const SizedBox.shrink(),
      foregroundColor: WidgetStatePropertyAll(colorScheme.onPrimary),
      overlayColor: WidgetStatePropertyAll(
        colorScheme.onPrimary.withValues(alpha: 0.12),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildTypeSelector(ColorScheme colorScheme) {
    final types = [
      FinanceTransactionType.expense,
      FinanceTransactionType.income,
      FinanceTransactionType.refund,
      FinanceTransactionType.transfer,
    ];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (final type in types)
            Expanded(
              child: Semantics(
                button: true,
                selected: type == _type,
                label: type.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _isSaving || _isLoanInterest
                      ? null
                      : () {
                          _dismissKeyboard();
                          if (type == _type ||
                              _isEditingInstallment ||
                              _hasRefundBinding) {
                            return;
                          }
                          _mutateState(() {
                            _type = type;
                            _archivedCategoryRequiresSelection = false;
                            if (type != FinanceTransactionType.expense) {
                              _installmentEnabled = false;
                            }
                            _normalizeSelections(
                              notify: false,
                              preserveUnresolvedPaymentMethod:
                                  widget.transaction != null ||
                                  widget.originalTransaction != null,
                            );
                          });
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: type == _type
                          ? colorScheme.primaryContainer
                          : colorScheme.surface.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      type.label,
                      style: TextStyle(
                        color: type == _type
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: type == _type
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRefundContextCard(ColorScheme colorScheme) {
    final original = _originalTransaction;
    if (original == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '原账单不存在或已删除，这笔退款暂时无法编辑。',
          style: TextStyle(color: colorScheme.onErrorContainer),
        ),
      );
    }
    final refundedMinor = (original.amountMinor - _remainingRefundableMinor)
        .clamp(0, original.amountMinor)
        .toInt();
    final title = original.merchant?.trim().isNotEmpty == true
        ? original.merchant!.trim()
        : original.categoryUuid;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联原账单',
            style: TextStyle(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$title  ·  ${formatFinanceAmount(original.amountMinor)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSecondaryContainer),
          ),
          const SizedBox(height: 4),
          Text(
            '已退 ${formatFinanceAmount(refundedMinor)}  ·  '
            '剩余可退 ${formatFinanceAmount(_remainingRefundableMinor)}',
            style: TextStyle(
              color: colorScheme.onSecondaryContainer.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOneSentenceEntry(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.52),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 19,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    '自然语言记账',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_templates.isNotEmpty)
                  TextButton.icon(
                    style: _compactTextButtonStyle(colorScheme),
                    onPressed: _showTemplatePicker,
                    icon: const Icon(Icons.flash_on_outlined, size: 17),
                    label: Text(
                      _selectedTemplateUuid == null ? '快捷模板' : '更换模板',
                    ),
                  ),
              ],
            ),
            Text(
              FinanceTextParser.quickEntryHelp,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '示例：',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: FinanceTextParser.quickEntryExample,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final input = TextField(
                  key: const ValueKey('finance-quick-entry-input'),
                  controller: _quickEntryController,
                  autofocus: false,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => _applyQuickEntry(),
                  decoration: _fieldDecoration(
                    colorScheme,
                    labelText: '账单描述',
                    hintText: '如：今天早餐 8 元，微信；中午午餐 25 元，支付宝',
                    prefixIcon: Icons.edit_note_rounded,
                    counterText: '',
                  ),
                );
                final action = TextButton.icon(
                  style: _compactTextButtonStyle(colorScheme),
                  onPressed: _isSaving ? null : _applyQuickEntry,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('识别账单'),
                );
                if (constraints.maxWidth >= 520) {
                  return Row(
                    children: [
                      Expanded(child: input),
                      const SizedBox(width: 10),
                      action,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    input,
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTemplatePicker() async {
    _dismissKeyboard();
    final templates = _templates;
    final selected = await showAppModalBottomSheet<FinanceEntryTemplate>(
      context: context,
      showDragHandle: true,
      requestFocus: false,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const ListTile(
              title: Text('选择快捷模板'),
              subtitle: Text('模板只填充默认内容，保存前仍可修改'),
            ),
            for (final template in templates)
              ListTile(
                leading: Icon(
                  template.type == FinanceTransactionType.income
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                ),
                title: Text(
                  financeEntryTemplateDisplayName(template, templates),
                ),
                subtitle: Text(
                  '${template.type.label} · ${formatFinanceAmount(template.amountMinor)}',
                ),
                trailing: template.uuid == _selectedTemplateUuid
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, template),
              ),
          ],
        ),
      ),
    );
    _dismissKeyboard();
    if (selected == null || !mounted) return;
    _mutateState(() {
      _selectedTemplateUuid = selected.uuid;
      _type = selected.type;
      if (selected.type != FinanceTransactionType.expense) {
        _installmentEnabled = false;
      }
      _amountExpression = null;
      _amountController.text = formatFinanceAmount(
        selected.amountMinor,
        withSymbol: false,
      );
      _merchantController.text = selected.merchant ?? '';
      _noteController.text = selected.note ?? '';
      _categoryUuid = selected.categoryUuid;
      _paymentMethodUuid = selected.paymentMethodUuid;
      _unmatchedDraftPaymentMethodName = null;
      _paymentMethodSelectionEdited = true;
      _clearArchivedNewEntryAssociations();
      _normalizeSelections(
        notify: false,
        allowDefaultCategory: !_archivedCategoryRequiresSelection,
      );
    });
    _dismissKeyboard();
  }
}
