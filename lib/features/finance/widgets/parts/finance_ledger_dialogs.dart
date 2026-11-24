part of '../finance_widgets.dart';

class _FinanceLedgerCategoryPickerDialog extends StatefulWidget {
  final Map<String, FinanceCategory> categories;
  final Set<String> initialSelection;
  final Map<String, int>? categoryCounts;

  const _FinanceLedgerCategoryPickerDialog({
    required this.categories,
    required this.initialSelection,
    required this.categoryCounts,
  });

  @override
  State<_FinanceLedgerCategoryPickerDialog> createState() =>
      _FinanceLedgerCategoryPickerDialogState();
}

class _FinanceLedgerCategoryPickerDialogState
    extends State<_FinanceLedgerCategoryPickerDialog> {
  late final Set<String> _selected = widget.initialSelection.toSet();
  final Set<String> _expandedRootUuids = <String>{};

  List<FinanceCategory> get _orderedCategories =>
      widget.categories.values.toList()..sort((left, right) {
        final typeOrder = left.type.index.compareTo(right.type.index);
        if (typeOrder != 0) return typeOrder;
        final parentOrder = (left.parentUuid ?? '').compareTo(
          right.parentUuid ?? '',
        );
        if (parentOrder != 0) return parentOrder;
        final sortOrder = left.sortOrder.compareTo(right.sortOrder);
        return sortOrder != 0 ? sortOrder : left.uuid.compareTo(right.uuid);
      });

  List<FinanceCategory> _childrenOf(FinanceCategory parent) =>
      _orderedCategories
          .where((category) => category.parentUuid == parent.uuid)
          .toList(growable: false);

  bool _isRootSelected(FinanceCategory root) => _selected.contains(root.uuid);

  bool _isChildSelected(FinanceCategory parent, FinanceCategory child) =>
      _isRootSelected(parent) || _selected.contains(child.uuid);

  void _toggleRoot(FinanceCategory root) {
    final children = _childrenOf(root);
    setState(() {
      if (!_selected.add(root.uuid)) {
        _selected.remove(root.uuid);
        for (final child in children) {
          _selected.remove(child.uuid);
        }
      } else {
        for (final child in children) {
          _selected.remove(child.uuid);
        }
      }
    });
  }

  void _toggleRootExpansion(FinanceCategory root) {
    setState(() {
      if (!_expandedRootUuids.add(root.uuid)) {
        _expandedRootUuids.remove(root.uuid);
      }
    });
  }

  void _toggleChild(FinanceCategory parent, FinanceCategory child) {
    setState(() {
      if (_selected.remove(parent.uuid)) {
        for (final sibling in _childrenOf(parent)) {
          if (sibling.uuid != child.uuid) _selected.add(sibling.uuid);
        }
        return;
      }
      if (!_selected.add(child.uuid)) _selected.remove(child.uuid);
    });
  }

  String _categoryLabel(FinanceCategory category) {
    final status = category.isDeleted
        ? '（已删除）'
        : category.isArchived
        ? '（已归档）'
        : '';
    return '${category.icon} ${financeCategorySiblingDisplayName(category, _orderedCategories)}$status';
  }

  @override
  Widget build(BuildContext context) {
    final categoryByUuid = widget.categories;
    final roots = _orderedCategories
        .where((category) {
          final parentUuid = category.parentUuid?.trim();
          if (parentUuid == null || parentUuid.isEmpty) return true;
          final parent = categoryByUuid[parentUuid];
          return parent == null || parent.type != category.type;
        })
        .toList(growable: false);
    final expenseRoots = roots
        .where((category) => category.type == FinanceCategoryType.expense)
        .toList(growable: false);
    final incomeRoots = roots
        .where((category) => category.type == FinanceCategoryType.income)
        .toList(growable: false);
    return AlertDialog(
      title: const Text('选择分类'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: ListView(
          children: [
            CheckboxListTile(
              value: _selected.contains(financeUncategorizedCategoryFilterUuid),
              title: const Text('未分类'),
              secondary: _countLabel(
                widget.categoryCounts?[financeUncategorizedCategoryFilterUuid],
              ),
              onChanged: (_) => setState(() {
                if (!_selected.add(financeUncategorizedCategoryFilterUuid)) {
                  _selected.remove(financeUncategorizedCategoryFilterUuid);
                }
              }),
              contentPadding: EdgeInsets.zero,
            ),
            for (final section in [
              ('支出', expenseRoots),
              ('收入', incomeRoots),
            ]) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  section.$1,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final root in section.$2) ...[
                Builder(
                  builder: (context) {
                    final children = _childrenOf(root);
                    final isExpanded = _expandedRootUuids.contains(root.uuid);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: children.isEmpty
                                    ? () => _toggleRoot(root)
                                    : () => _toggleRootExpansion(root),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(_categoryLabel(root)),
                                      ),
                                      if (widget.categoryCounts != null) ...[
                                        const SizedBox(width: 8),
                                        _countLabel(
                                          widget.categoryCounts![root.uuid] ??
                                              0,
                                        )!,
                                      ],
                                      if (children.isNotEmpty)
                                        Icon(
                                          isExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Checkbox(
                              value: _isRootSelected(root),
                              onChanged: (_) => _toggleRoot(root),
                            ),
                          ],
                        ),
                        if (isExpanded)
                          for (final child in children)
                            CheckboxListTile(
                              value: _isChildSelected(root, child),
                              title: Text(_categoryLabel(child)),
                              secondary: _countLabel(
                                widget.categoryCounts?[child.uuid],
                              ),
                              onChanged: (_) => _toggleChild(root, child),
                              contentPadding: const EdgeInsets.only(left: 24),
                              dense: true,
                            ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toSet()),
          child: const Text('应用'),
        ),
      ],
    );
  }

  Widget? _countLabel(int? count) {
    if (count == null) return null;
    return Text(
      '$count笔',
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _FinanceBatchFieldChoice<T> {
  final T value;

  const _FinanceBatchFieldChoice(this.value);
}

class _FinanceBatchCategoryPickerDialog extends StatefulWidget {
  final Map<String, FinanceCategory> categories;
  final FinanceCategoryType categoryType;
  final int selectedCount;

  const _FinanceBatchCategoryPickerDialog({
    required this.categories,
    required this.categoryType,
    required this.selectedCount,
  });

  @override
  State<_FinanceBatchCategoryPickerDialog> createState() =>
      _FinanceBatchCategoryPickerDialogState();
}

class _FinanceBatchCategoryPickerDialogState
    extends State<_FinanceBatchCategoryPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeCategories =
        widget.categories.values
            .where(
              (category) =>
                  category.type == widget.categoryType &&
                  !category.isDeleted &&
                  !category.isArchived,
            )
            .toList()
          ..sort((left, right) {
            final parentOrder = (left.parentUuid ?? '').compareTo(
              right.parentUuid ?? '',
            );
            if (parentOrder != 0) return parentOrder;
            final sortOrder = left.sortOrder.compareTo(right.sortOrder);
            return sortOrder != 0 ? sortOrder : left.uuid.compareTo(right.uuid);
          });
    final byUuid = {for (final c in activeCategories) c.uuid: c};
    final roots = activeCategories
        .where((category) {
          final parentUuid = category.parentUuid?.trim();
          return parentUuid == null ||
              parentUuid.isEmpty ||
              !byUuid.containsKey(parentUuid);
        })
        .toList(growable: false);
    final normalizedQuery = _query.trim().toLowerCase();

    final rows = <({FinanceCategory category, bool isChild})>[];
    for (final root in roots) {
      final children = activeCategories
          .where((category) => category.parentUuid == root.uuid)
          .toList(growable: false);
      final rootMatches =
          normalizedQuery.isEmpty ||
          root.name.toLowerCase().contains(normalizedQuery);
      final matchingChildren = children
          .where(
            (child) =>
                normalizedQuery.isEmpty ||
                child.name.toLowerCase().contains(normalizedQuery),
          )
          .toList(growable: false);
      if (rootMatches || matchingChildren.isNotEmpty) {
        rows.add((category: root, isChild: false));
        for (final child in matchingChildren) {
          rows.add((category: child, isChild: true));
        }
      }
    }

    return AlertDialog(
      title: Text('批量修改分类（${widget.selectedCount} 笔）'),
      content: SizedBox(
        width: 400,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索分类',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (normalizedQuery.isEmpty ||
                      '未分类'.contains(normalizedQuery))
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        child: const Text('🏷️'),
                      ),
                      title: const Text('未分类'),
                      subtitle: Text(
                        '清除所选账单的分类',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        const _FinanceBatchFieldChoice<String?>(null),
                      ),
                    ),
                  for (final row in rows)
                    ListTile(
                      contentPadding: EdgeInsets.only(
                        left: row.isChild ? 36 : 16,
                        right: 16,
                      ),
                      leading: Text(
                        row.category.icon,
                        style: TextStyle(fontSize: row.isChild ? 18 : 22),
                      ),
                      title: Text(
                        financeCategorySiblingDisplayName(
                          row.category,
                          activeCategories,
                        ),
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        _FinanceBatchFieldChoice<String?>(row.category.uuid),
                      ),
                    ),
                  if (rows.isEmpty && normalizedQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '没有匹配的分类',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _FinanceBatchPaymentMethodPickerDialog extends StatelessWidget {
  final Map<String, FinancePaymentMethod> paymentMethods;
  final int selectedCount;

  const _FinanceBatchPaymentMethodPickerDialog({
    required this.paymentMethods,
    required this.selectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeMethods =
        paymentMethods.values
            .where((pm) => !pm.isDeleted && !pm.isArchived)
            .toList()
          ..sort((left, right) {
            final order = left.sortOrder.compareTo(right.sortOrder);
            return order != 0 ? order : left.uuid.compareTo(right.uuid);
          });
    return AlertDialog(
      title: Text('批量修改账户（$selectedCount 笔）'),
      content: SizedBox(
        width: 380,
        height: 360,
        child: ListView(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.money_off_csred_outlined, size: 18),
              ),
              title: const Text('未指定账户'),
              subtitle: Text(
                '清除所选账单的账户关联',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              onTap: () => Navigator.pop(
                context,
                const _FinanceBatchFieldChoice<String?>(null),
              ),
            ),
            for (final pm in activeMethods)
              ListTile(
                leading: Text(pm.icon, style: const TextStyle(fontSize: 22)),
                title: Text(financePaymentMethodDisplayName(pm, activeMethods)),
                onTap: () => Navigator.pop(
                  context,
                  _FinanceBatchFieldChoice<String?>(pm.uuid),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _FinanceBatchEditResult {
  final bool applyCategory;
  final String? categoryUuid;
  final bool applyPaymentMethod;
  final String? paymentMethodUuid;
  final bool applyDate;
  final DateTime? date;
  final bool applyMerchant;
  final String? merchant;
  final bool applyNote;
  final String? note;

  const _FinanceBatchEditResult({
    required this.applyCategory,
    required this.categoryUuid,
    required this.applyPaymentMethod,
    required this.paymentMethodUuid,
    required this.applyDate,
    required this.date,
    required this.applyMerchant,
    required this.merchant,
    required this.applyNote,
    required this.note,
  });
}

class _FinanceBatchEditDialog extends StatefulWidget {
  final int selectedCount;
  final Map<String, FinanceCategory> categories;
  final Map<String, FinancePaymentMethod> paymentMethods;
  final FinanceCategoryType? categoryType;
  final String? categoryDisabledReason;
  final DateTime initialDate;

  const _FinanceBatchEditDialog({
    required this.selectedCount,
    required this.categories,
    required this.paymentMethods,
    required this.categoryType,
    required this.categoryDisabledReason,
    required this.initialDate,
  });

  @override
  State<_FinanceBatchEditDialog> createState() =>
      _FinanceBatchEditDialogState();
}

class _FinanceBatchEditDialogState extends State<_FinanceBatchEditDialog> {
  bool _applyCategory = false;
  String? _categoryUuid;
  bool _applyPaymentMethod = false;
  String? _paymentMethodUuid;
  bool _applyDate = false;
  late DateTime _date = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
    widget.initialDate.day,
  );
  bool _applyMerchant = false;
  final TextEditingController _merchantController = TextEditingController();
  bool _applyNote = false;
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _hasAnyChange =>
      _applyCategory ||
      _applyPaymentMethod ||
      _applyDate ||
      _applyMerchant ||
      _applyNote;

  Future<void> _pickCategory() async {
    final type = widget.categoryType;
    if (type == null) return;
    final choice = await showAppDialog<_FinanceBatchFieldChoice<String?>>(
      context: context,
      builder: (context) => _FinanceBatchCategoryPickerDialog(
        categories: widget.categories,
        categoryType: type,
        selectedCount: widget.selectedCount,
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _applyCategory = true;
      _categoryUuid = choice.value;
    });
  }

  Future<void> _pickPaymentMethod() async {
    final choice = await showAppDialog<_FinanceBatchFieldChoice<String?>>(
      context: context,
      builder: (context) => _FinanceBatchPaymentMethodPickerDialog(
        paymentMethods: widget.paymentMethods,
        selectedCount: widget.selectedCount,
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _applyPaymentMethod = true;
      _paymentMethodUuid = choice.value;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _applyDate = true;
      _date = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final categoryLabel = _categoryUuid == null
        ? '未分类'
        : financeCategoryReferenceDisplayName(
            _categoryUuid,
            widget.categories.values,
          );
    final paymentMethod = _paymentMethodUuid == null
        ? null
        : widget.paymentMethods[_paymentMethodUuid];
    final paymentLabel = paymentMethod == null
        ? '未指定账户'
        : '${paymentMethod.icon} ${financePaymentMethodDisplayName(paymentMethod, widget.paymentMethods.values)}';

    return AlertDialog(
      title: Text('批量修改（${widget.selectedCount} 笔）'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: _applyCategory,
                onChanged: widget.categoryType == null
                    ? null
                    : (checked) {
                        if (checked == true) {
                          unawaited(_pickCategory());
                        } else {
                          setState(() => _applyCategory = false);
                        }
                      },
                title: const Text('修改分类'),
                subtitle: Text(
                  widget.categoryDisabledReason ??
                      (_applyCategory ? '将改为：$categoryLabel' : '点击选择目标分类'),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                secondary: IconButton(
                  tooltip: '选择分类',
                  onPressed: widget.categoryType == null ? null : _pickCategory,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _applyPaymentMethod,
                onChanged: (checked) {
                  if (checked == true) {
                    unawaited(_pickPaymentMethod());
                  } else {
                    setState(() => _applyPaymentMethod = false);
                  }
                },
                title: const Text('修改账户'),
                subtitle: Text(
                  _applyPaymentMethod ? '将改为：$paymentLabel' : '点击选择目标账户',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                secondary: IconButton(
                  tooltip: '选择账户',
                  onPressed: _pickPaymentMethod,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _applyDate,
                onChanged: (checked) {
                  if (checked == true) {
                    unawaited(_pickDate());
                  } else {
                    setState(() => _applyDate = false);
                  }
                },
                title: const Text('修改日期'),
                subtitle: Text(
                  _applyDate ? '将改为：${dateKey(_date)}' : '点击选择新日期',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                secondary: IconButton(
                  tooltip: '选择日期',
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _applyMerchant,
                onChanged: (checked) =>
                    setState(() => _applyMerchant = checked ?? false),
                title: const Text('修改商户 / 标题'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_applyMerchant)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _merchantController,
                    decoration: InputDecoration(
                      labelText: '商户 / 标题（留空则清空）',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              CheckboxListTile(
                value: _applyNote,
                onChanged: (checked) =>
                    setState(() => _applyNote = checked ?? false),
                title: const Text('修改备注'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_applyNote)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: '备注内容（留空则清空）',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _hasAnyChange
              ? () => Navigator.pop(
                  context,
                  _FinanceBatchEditResult(
                    applyCategory: _applyCategory,
                    categoryUuid: _categoryUuid,
                    applyPaymentMethod: _applyPaymentMethod,
                    paymentMethodUuid: _paymentMethodUuid,
                    applyDate: _applyDate,
                    date: _date,
                    applyMerchant: _applyMerchant,
                    merchant: _merchantController.text,
                    applyNote: _applyNote,
                    note: _noteController.text,
                  ),
                )
              : null,
          child: const Text('应用修改'),
        ),
      ],
    );
  }
}
