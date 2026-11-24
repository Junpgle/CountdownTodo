part of '../finance_entry_screen.dart';

extension _FinanceEntryPickers on _FinanceEntryScreenState {
  ButtonStyle _plainTextButtonStyle(ColorScheme colorScheme) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(
        colorScheme.surface.withValues(alpha: 0),
      ),
      backgroundBuilder: (context, states, child) =>
          child ?? const SizedBox.shrink(),
      foregroundColor: WidgetStatePropertyAll(colorScheme.primary),
      overlayColor: WidgetStatePropertyAll(
        colorScheme.primary.withValues(alpha: 0.08),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  ButtonStyle _compactTextButtonStyle(ColorScheme colorScheme) {
    return _plainTextButtonStyle(colorScheme).copyWith(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    ColorScheme colorScheme, {
    String? labelText,
    String? hintText,
    String? prefixText,
    IconData? prefixIcon,
    String? counterText,
    String? suffixText,
    bool alignLabelWithHint = false,
    FloatingLabelBehavior? floatingLabelBehavior,
    EdgeInsetsGeometry? contentPadding,
    TextStyle? prefixStyle,
    Widget? suffixIcon,
  }) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.82),
      ),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 21, color: colorScheme.onSurfaceVariant),
      counterText: counterText,
      suffixText: suffixText,
      suffixIcon: suffixIcon,
      alignLabelWithHint: alignLabelWithHint,
      floatingLabelBehavior: floatingLabelBehavior,
      isDense: true,
      filled: false,
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      prefixStyle: prefixStyle,
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      ),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
    );
  }

  Widget _buildSelectionFields(
    ColorScheme colorScheme, {
    required bool isWide,
  }) {
    final categoryCandidate = _categoriesByUuid[_categoryUuid];
    final selectedCategory =
        categoryCandidate != null &&
            categoryCandidate.type ==
                financeCategoryTypeForTransaction(_type) &&
            !categoryCandidate.isDeleted
        ? categoryCandidate
        : null;
    final paymentMethodCandidate = _paymentMethodsByUuid[_paymentMethodUuid];
    final selectedPaymentMethod = paymentMethodCandidate?.isDeleted == true
        ? null
        : paymentMethodCandidate;

    final category = _buildFinancePickerField(
      key: ValueKey('finance-category-$_type-$_categoryUuid'),
      colorScheme: colorScheme,
      label: '分类',
      placeholder: _categoryUuid == null
          ? _editingTransaction != null || widget.originalTransaction != null
                ? '未分类'
                : '请选择分类'
          : '已删除或未知分类',
      selectedName: selectedCategory == null
          ? null
          : _categoryName(selectedCategory),
      selectedIcon: selectedCategory?.icon,
      fieldIcon: Icons.category_outlined,
      onTap: _isSaving || _isBoundRefund || _isLoanInterest
          ? null
          : _pickCategory,
    );

    final payment = _buildFinancePickerField(
      key: ValueKey('finance-payment-$_paymentMethodUuid'),
      colorScheme: colorScheme,
      label: switch (_type) {
        FinanceTransactionType.expense => '付款方式（可选）',
        FinanceTransactionType.income => '到账账户（可选）',
        FinanceTransactionType.refund => '退款到账账户（可选）',
        FinanceTransactionType.transfer => '转出账户（可选）',
      },
      placeholder: _paymentMethodUuid != null && selectedPaymentMethod == null
          ? switch (_type) {
              FinanceTransactionType.expense => '已删除或未知付款方式',
              FinanceTransactionType.income => '已删除或未知到账账户',
              FinanceTransactionType.refund => '已删除或未知退款到账账户',
              FinanceTransactionType.transfer => '已删除或未知转出账户',
            }
          : _unmatchedDraftPaymentMethodName != null
          ? switch (_type) {
              FinanceTransactionType.expense =>
                '未匹配付款方式：$_unmatchedDraftPaymentMethodName',
              FinanceTransactionType.income =>
                '未匹配到账账户：$_unmatchedDraftPaymentMethodName',
              FinanceTransactionType.refund =>
                '未匹配退款到账账户：$_unmatchedDraftPaymentMethodName',
              FinanceTransactionType.transfer =>
                '未匹配转出账户：$_unmatchedDraftPaymentMethodName',
            }
          : _type == FinanceTransactionType.expense
          ? '未指定'
          : '未指定（不更新账户余额）',
      selectedName: selectedPaymentMethod == null
          ? null
          : _paymentMethodName(selectedPaymentMethod),
      selectedIcon: selectedPaymentMethod?.icon,
      fieldIcon: Icons.account_balance_wallet_outlined,
      onTap: _isSaving || _isLoanInterest ? null : _pickPaymentMethod,
    );
    if (_type == FinanceTransactionType.transfer) {
      final targetCandidate = _paymentMethodsByUuid[_targetPaymentMethodUuid];
      final selectedTargetPaymentMethod = targetCandidate?.isDeleted == true
          ? null
          : targetCandidate;
      final targetPayment = _buildFinancePickerField(
        key: ValueKey('finance-target-payment-$_targetPaymentMethodUuid'),
        colorScheme: colorScheme,
        label: '转入账户（可选）',
        placeholder:
            _targetPaymentMethodUuid != null &&
                selectedTargetPaymentMethod == null
            ? '已删除或未知转入账户'
            : '未指定（不更新转入账户余额）',
        selectedName: selectedTargetPaymentMethod == null
            ? null
            : _paymentMethodName(selectedTargetPaymentMethod),
        selectedIcon: selectedTargetPaymentMethod?.icon,
        fieldIcon: Icons.savings_outlined,
        onTap: _isSaving || _isLoanInterest ? null : _pickTargetPaymentMethod,
      );
      if (!isWide) {
        return Column(
          children: [payment, const SizedBox(height: 14), targetPayment],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: payment),
          const SizedBox(width: 12),
          Expanded(child: targetPayment),
        ],
      );
    }

    if (!isWide) {
      return Column(children: [category, const SizedBox(height: 14), payment]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: category),
        const SizedBox(width: 12),
        Expanded(child: payment),
      ],
    );
  }

  Widget _buildFinancePickerField({
    required Key key,
    required ColorScheme colorScheme,
    required String label,
    required String placeholder,
    required String? selectedName,
    required String? selectedIcon,
    required IconData fieldIcon,
    required VoidCallback? onTap,
  }) {
    final hasSelection = selectedName != null && selectedName.isNotEmpty;
    final displayName = hasSelection ? selectedName : placeholder;
    final valueColor = hasSelection
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.82);

    return Material(
      key: key,
      color: colorScheme.surface.withValues(alpha: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Icon(
                fieldIcon,
                size: 20,
                color: hasSelection
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (hasSelection && selectedIcon != null) ...[
                          Text(
                            selectedIcon,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: valueColor,
                              fontSize: 15,
                              fontWeight: hasSelection
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCategory() async {
    _dismissKeyboard();
    final parents = _visibleCategoryParents;
    if (parents.isEmpty) return;
    final currentCategory = _categoryByUuid(_categoryUuid);
    final selectedParentUuid = currentCategory == null
        ? parents.first.uuid
        : _topLevelCategory(currentCategory).uuid;
    final parent = await _showFinanceOptionPicker<FinanceCategory>(
      title: '选择大类',
      subtitle: '先选择这笔账单所属的大类',
      headerIcon: Icons.category_outlined,
      options: parents,
      selectedUuid: selectedParentUuid,
      optionUuid: (item) => item.uuid,
      optionBuilder: (context, item, isSelected, onTap) =>
          _buildFinanceOptionTile(
            context,
            title: financeCategorySiblingDisplayName(item, _categories),
            subtitle: '一级分类',
            iconText: item.icon,
            accent: _optionAccent(
              item.colorValue,
              Theme.of(context).colorScheme,
            ),
            isSelected: isSelected,
            onTap: onTap,
          ),
    );
    if (!mounted || parent?.value == null) return;

    final selectedParent = parent!.value!;
    final children = _childrenOf(selectedParent);
    if (children.isEmpty) {
      _dismissKeyboard();
      _mutateState(() {
        _categoryUuid = selectedParent.uuid;
        _archivedCategoryRequiresSelection = false;
      });
      return;
    }

    final current = _categoryByUuid(_categoryUuid);
    final currentBelongsToParent =
        current != null &&
        (current.uuid == selectedParent.uuid ||
            current.parentUuid?.trim() == selectedParent.uuid);
    final selectedParentDisplayName = financeCategorySiblingDisplayName(
      selectedParent,
      _categories,
    );
    final selected = await _showFinanceOptionPicker<FinanceCategory>(
      title:
          '${financeCategoryDisplayName(selectedParent, _categories)} · 选择小类',
      subtitle: '可以只记为大类，也可以选择更具体的细分',
      headerIcon: Icons.account_tree_outlined,
      options: [selectedParent, ...children],
      selectedUuid: currentBelongsToParent ? current.uuid : selectedParent.uuid,
      optionUuid: (item) => item.uuid,
      addTooltip: '新增小类',
      onAdd: () => _addSubcategory(selectedParent),
      optionBuilder: (context, item, isSelected, onTap) {
        final isParent = item.uuid == selectedParent.uuid;
        final itemDisplayName = financeCategorySiblingDisplayName(
          item,
          _categories,
        );
        return _buildFinanceOptionTile(
          context,
          title: isParent ? '仅记为$selectedParentDisplayName' : itemDisplayName,
          subtitle: isParent ? '不选择小类' : '$selectedParentDisplayName下的细分类',
          iconText: item.icon,
          accent: _optionAccent(item.colorValue, Theme.of(context).colorScheme),
          isSelected: isSelected,
          onTap: onTap,
        );
      },
    );
    if (!mounted || selected?.value == null) return;
    _dismissKeyboard();
    _mutateState(() {
      _categoryUuid = selected!.value!.uuid;
      _archivedCategoryRequiresSelection = false;
    });
  }

  Future<FinanceCategory?> _addSubcategory(FinanceCategory parent) async {
    _dismissKeyboard();
    FinanceCategory? created;
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (_) => FinanceCatalogEditor(
        initialIcon: parent.icon,
        categoryType: parent.type,
        availableParents: _categories,
        initialParentUuid: parent.uuid,
        lockParent: true,
        isSubcategory: true,
        onSave: (draft) async {
          final category = FinanceCategory(
            name: draft.name,
            type: draft.type!,
            icon: draft.icon,
            parentUuid: draft.parentUuid,
            sortOrder: _nextSubcategorySortOrder(parent),
          );
          await FinanceRepository.saveCategory(category);
          created = category;
        },
      ),
    );
    _dismissKeyboard();
    if (saved != true || !mounted || created == null) return null;
    _mutateState(() => _replaceCategories([..._categories, created!]));
    return created;
  }

  Future<void> _pickPaymentMethod() async {
    _dismissKeyboard();
    final selected = await _showFinanceOptionPicker<FinancePaymentMethod>(
      title: switch (_type) {
        FinanceTransactionType.expense => '选择付款方式',
        FinanceTransactionType.income => '选择到账账户',
        FinanceTransactionType.refund => '选择退款到账账户',
        FinanceTransactionType.transfer => '选择转出账户',
      },
      subtitle: switch (_type) {
        FinanceTransactionType.expense => '记录这笔账单使用的支付渠道',
        FinanceTransactionType.income => '收入会加到所选账户已录入的余额',
        FinanceTransactionType.refund => '退款会加到所选账户已录入的余额',
        FinanceTransactionType.transfer => '互转金额将从转出账户扣减',
      },
      headerIcon: Icons.account_balance_wallet_outlined,
      options: _visiblePaymentMethods,
      selectedUuid: _paymentMethodUuid,
      optionUuid: (item) => item.uuid,
      includeUnset: true,
      unsetSubtitle: switch (_type) {
        FinanceTransactionType.expense => '暂不记录付款方式',
        FinanceTransactionType.income => '暂不记录到账账户',
        FinanceTransactionType.refund => '暂不记录退款到账账户',
        FinanceTransactionType.transfer => '暂不记录转出账户',
      },
      optionBuilder: (context, item, isSelected, onTap) =>
          _buildFinanceOptionTile(
            context,
            title: financePaymentMethodDisplayName(
              item,
              _visiblePaymentMethods,
            ),
            iconText: item.icon,
            accent: _optionAccent(
              item.colorValue,
              Theme.of(context).colorScheme,
            ),
            isSelected: isSelected,
            onTap: onTap,
          ),
    );
    if (!mounted || selected == null) return;
    _dismissKeyboard();
    _mutateState(() {
      _paymentMethodUuid = selected.value?.uuid;
      _unmatchedDraftPaymentMethodName = null;
      _paymentMethodSelectionEdited = true;
    });
  }

  Future<void> _pickTargetPaymentMethod() async {
    _dismissKeyboard();
    final selected = await _showFinanceOptionPicker<FinancePaymentMethod>(
      title: '选择转入账户',
      subtitle: '互转金额将加到转入账户已录入的余额',
      headerIcon: Icons.savings_outlined,
      options: _visiblePaymentMethods,
      selectedUuid: _targetPaymentMethodUuid,
      optionUuid: (item) => item.uuid,
      includeUnset: true,
      unsetSubtitle: '暂不记录转入账户',
      optionBuilder: (context, item, isSelected, onTap) =>
          _buildFinanceOptionTile(
            context,
            title: financePaymentMethodDisplayName(
              item,
              _visiblePaymentMethods,
            ),
            iconText: item.icon,
            accent: _optionAccent(
              item.colorValue,
              Theme.of(context).colorScheme,
            ),
            isSelected: isSelected,
            onTap: onTap,
          ),
    );
    if (!mounted || selected == null) return;
    _dismissKeyboard();
    _mutateState(() {
      _targetPaymentMethodUuid = selected.value?.uuid;
    });
  }

  Future<_FinanceOptionSelection<T>?> _showFinanceOptionPicker<T>({
    required String title,
    required String subtitle,
    required IconData headerIcon,
    required List<T> options,
    required String? selectedUuid,
    required String Function(T option) optionUuid,
    required Widget Function(
      BuildContext context,
      T option,
      bool isSelected,
      VoidCallback onTap,
    )
    optionBuilder,
    bool includeUnset = false,
    String unsetSubtitle = '暂不记录付款方式',
    String? addTooltip,
    Future<T?> Function()? onAdd,
  }) async {
    _dismissKeyboard();
    final selected = await showAppModalBottomSheet<_FinanceOptionSelection<T>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      requestFocus: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.76,
      ),
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final totalCount = options.length + (includeUnset ? 1 : 0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      headerIcon,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onAdd != null)
                    IconButton(
                      key: ValueKey(addTooltip ?? 'finance-option-add'),
                      tooltip: addTooltip ?? '新增',
                      onPressed: () async {
                        final added = await onAdd();
                        if (!sheetContext.mounted || added == null) return;
                        Navigator.of(sheetContext)
                            .pop(_FinanceOptionSelection<T>(added));
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$totalCount 项',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: totalCount,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (includeUnset && index == 0) {
                    return RepaintBoundary(
                      child: _buildFinanceOptionTile(
                        context,
                        title: '未指定',
                        subtitle: unsetSubtitle,
                        icon: Icons.remove_rounded,
                        accent: colorScheme.outline,
                        isSelected: selectedUuid == null,
                        onTap: () =>
                            Navigator.of(sheetContext)
                                .pop(_FinanceOptionSelection<T>(null)),
                      ),
                    );
                  }
                  final option = options[index - (includeUnset ? 1 : 0)];
                  return RepaintBoundary(
                    child: optionBuilder(
                      context,
                      option,
                      optionUuid(option) == selectedUuid,
                      () =>
                          Navigator.of(sheetContext)
                              .pop(_FinanceOptionSelection<T>(option)),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
    _dismissKeyboard();
    return selected;
  }

  Widget _buildFinanceOptionTile(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? iconText,
    IconData? icon,
    required Color accent,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconBackground = isSelected
        ? colorScheme.primary
        : accent.withValues(alpha: 0.16);
    final iconColor = isSelected ? colorScheme.onPrimary : accent;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.58)
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.55)
              : colorScheme.outlineVariant.withValues(alpha: 0.48),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: iconText == null
                    ? Icon(icon, color: iconColor, size: 20)
                    : Text(iconText, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) => AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) {
                    if (animation.value <= 0.001) {
                      return const SizedBox.shrink();
                    }
                    if (animation.value >= 0.999) return child!;
                    return FadeTransition(opacity: animation, child: child);
                  },
                ),
                child: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('selected'),
                        color: colorScheme.primary,
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        key: const ValueKey('unselected'),
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _optionAccent(int? colorValue, ColorScheme colorScheme) {
    return colorValue == null ? colorScheme.primary : Color(colorValue);
  }
}
