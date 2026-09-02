import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/finance_models.dart';

enum _CatalogSection { expense, income, payment }

enum _CatalogFilter { active, custom, archived }

/// Presents the personal catalog without changing its persistence rules.
class FinanceCatalogManager extends StatefulWidget {
  final List<FinanceCategory> categories;
  final List<FinancePaymentMethod> paymentMethods;
  final Future<FinanceCategory?> Function(FinanceCategoryType type)
      onAddCategory;
  final Future<bool> Function() onAddPaymentMethod;
  final Future<void> Function(FinanceCategory category) onEditCategory;
  final Future<void> Function(FinanceCategory category) onArchiveCategory;
  final Future<void> Function(FinanceCategory category) onRestoreCategory;
  final Future<void> Function(FinancePaymentMethod method) onEditPaymentMethod;
  final Future<void> Function(FinancePaymentMethod method)
      onArchivePaymentMethod;
  final Future<void> Function(FinancePaymentMethod method)
      onRestorePaymentMethod;

  const FinanceCatalogManager({
    super.key,
    required this.categories,
    required this.paymentMethods,
    required this.onAddCategory,
    required this.onAddPaymentMethod,
    required this.onEditCategory,
    required this.onArchiveCategory,
    required this.onRestoreCategory,
    required this.onEditPaymentMethod,
    required this.onArchivePaymentMethod,
    required this.onRestorePaymentMethod,
  });

  @override
  State<FinanceCatalogManager> createState() => _FinanceCatalogManagerState();
}

class _FinanceCatalogManagerState extends State<FinanceCatalogManager> {
  final _searchController = TextEditingController();
  final _busyItems = <String>{};
  _CatalogSection _section = _CatalogSection.expense;
  _CatalogFilter _filter = _CatalogFilter.active;
  bool _isAdding = false;

  bool get _isPayment => _section == _CatalogSection.payment;
  String get _itemLabel => _isPayment ? '付款方式' : '分类';
  String get _sectionLabel => switch (_section) {
        _CatalogSection.expense => '支出分类',
        _CatalogSection.income => '收入分类',
        _CatalogSection.payment => '付款方式',
      };

  List<_CatalogEntry> get _entries => _isPayment
      ? [
          for (final method in widget.paymentMethods)
            if (!method.isDeleted)
              _CatalogEntry(
                uuid: method.uuid,
                name: method.name,
                icon: method.icon,
                isSystem: method.isSystem,
                isArchived: method.isArchived,
                onEdit: () => widget.onEditPaymentMethod(method),
                onArchive: () => widget.onArchivePaymentMethod(method),
                onRestore: () => widget.onRestorePaymentMethod(method),
              ),
        ]
      : [
          for (final category in widget.categories)
            if (!category.isDeleted &&
                category.type ==
                    (_section == _CatalogSection.expense
                        ? FinanceCategoryType.expense
                        : FinanceCategoryType.income))
              _CatalogEntry(
                uuid: category.uuid,
                name: category.name,
                icon: category.icon,
                isSystem: category.isSystem,
                isArchived: category.isArchived,
                onEdit: () => widget.onEditCategory(category),
                onArchive: () => widget.onArchiveCategory(category),
                onRestore: () => widget.onRestoreCategory(category),
              ),
        ];

  bool _matchesFilter(_CatalogEntry entry, _CatalogFilter filter) =>
      switch (filter) {
        _CatalogFilter.active => !entry.isArchived,
        _CatalogFilter.custom => !entry.isArchived && !entry.isSystem,
        _CatalogFilter.archived => entry.isArchived,
      };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectSection(_CatalogSection section) {
    FocusScope.of(context).unfocus();
    setState(() {
      _section = section;
      _filter = _CatalogFilter.active;
      _searchController.clear();
    });
  }

  Future<void> _add() async {
    if (_isAdding) return;
    setState(() => _isAdding = true);
    try {
      var saved = false;
      var destination = _section;
      if (_isPayment) {
        saved = await widget.onAddPaymentMethod();
      } else {
        final category = await widget.onAddCategory(
          _section == _CatalogSection.expense
              ? FinanceCategoryType.expense
              : FinanceCategoryType.income,
        );
        saved = category != null;
        if (category != null) {
          destination = category.type == FinanceCategoryType.expense
              ? _CatalogSection.expense
              : _CatalogSection.income;
        }
      }
      if (mounted && saved) {
        setState(() {
          _section = destination;
          _filter = _CatalogFilter.active;
          _searchController.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _runAction(
      _CatalogEntry entry, Future<void> Function() action) async {
    if (!_busyItems.add(entry.uuid)) return;
    setState(() {});
    try {
      await action();
    } catch (error) {
      debugPrint('记账目录操作失败：$error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请稍后重试')),
        );
      }
    } finally {
      _busyItems.remove(entry.uuid);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entries = _entries;
    final query = _searchController.text.trim().toLowerCase();
    final visible = entries
        .where((entry) =>
            _matchesFilter(entry, _filter) &&
            (query.isEmpty ||
                entry.name.toLowerCase().contains(query) ||
                entry.icon.contains(query)))
        .toList();
    final personal = visible.where((entry) => !entry.isSystem).toList();
    final system = visible.where((entry) => entry.isSystem).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.category_outlined,
                  color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('分类与付款方式',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '整理常用项目，让每次记账更顺手',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final showIcons = constraints.maxWidth >=
                340 * MediaQuery.textScalerOf(context).scale(14) / 14;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: SegmentedButton<_CatalogSection>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: _CatalogSection.expense,
                        icon: showIcons
                            ? const Icon(Icons.north_east_rounded, size: 18)
                            : null,
                        label: const Text('支出分类')),
                    ButtonSegment(
                        value: _CatalogSection.income,
                        icon: showIcons
                            ? const Icon(Icons.south_west_rounded, size: 18)
                            : null,
                        label: const Text('收入分类')),
                    ButtonSegment(
                        value: _CatalogSection.payment,
                        icon: showIcons
                            ? const Icon(Icons.account_balance_wallet_outlined,
                                size: 18)
                            : null,
                        label: const Text('付款方式')),
                  ],
                  selected: {_section},
                  onSelectionChanged: (selection) =>
                      _selectSection(selection.single),
                  style: ButtonStyle(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                    padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 14)),
                    side: WidgetStatePropertyAll(BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.6))),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('finance-catalog-search'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索$_sectionLabel',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () =>
                              setState(() => _searchController.clear()),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  filled: true,
                  fillColor:
                      colors.surfaceContainerHighest.withValues(alpha: 0.45),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: '新增$_itemLabel',
              child: FilledButton.icon(
                key: const ValueKey('finance-catalog-add'),
                onPressed: _isAdding ? null : _add,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16)),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('新增'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in _CatalogFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('finance-catalog-filter-${filter.name}'),
                    showCheckmark: false,
                    label: Text('${switch (filter) {
                      _CatalogFilter.active => '使用中',
                      _CatalogFilter.custom => '自定义',
                      _CatalogFilter.archived => '已归档',
                    }} · ${entries.where((entry) => _matchesFilter(entry, filter)).length}'),
                    selected: filter == _filter,
                    onSelected: (_) => setState(() => _filter = filter),
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          _buildEmptyState(context, query)
        else if (_filter == _CatalogFilter.archived)
          _buildGroup(context, '已归档', '恢复后可在新账单中继续使用', visible)
        else ...[
          if (personal.isNotEmpty)
            _buildGroup(context, '我的$_itemLabel', '点击卡片即可编辑', personal),
          if (personal.isNotEmpty && system.isNotEmpty)
            const SizedBox(height: 24),
          if (system.isNotEmpty)
            _buildGroup(context, '系统预设', '内置常用项目，随时可用', system),
        ],
      ],
    );
  }

  Widget _buildGroup(BuildContext context, String title, String subtitle,
      List<_CatalogEntry> entries) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('$title · ${entries.length}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns =
                (constraints.maxWidth / (140 * math.max(1, textScale)))
                    .floor()
                    .clamp(1, 4);
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in entries)
                  SizedBox(width: width, child: _buildTile(context, entry)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTile(BuildContext context, _CatalogEntry entry) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _busyItems.contains(entry.uuid);
    final tint = switch (_section) {
      _CatalogSection.expense => colors.primaryContainer,
      _CatalogSection.income => colors.tertiaryContainer,
      _CatalogSection.payment => colors.secondaryContainer,
    };
    return Material(
      key: ValueKey('finance-catalog-item-${entry.uuid}'),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: entry.isSystem || busy
            ? null
            : () => _runAction(entry, entry.onEdit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.isArchived
                          ? colors.surfaceContainerHighest
                          : tint.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(entry.icon.isEmpty ? '📦' : entry.icon,
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (busy)
                    const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else if (entry.isSystem)
                    Tooltip(
                        message: '系统预设$_itemLabel不可编辑或归档',
                        child: Icon(Icons.lock_outline_rounded,
                            size: 16, color: colors.onSurfaceVariant))
                  else if (entry.isArchived)
                    IconButton(
                      tooltip: '恢复${entry.name}',
                      onPressed: () => _runAction(entry, entry.onRestore),
                      icon: const Icon(Icons.unarchive_outlined, size: 20),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: '管理${entry.name}',
                      icon: Icon(Icons.more_horiz_rounded,
                          color: colors.onSurfaceVariant),
                      onSelected: (action) => _runAction(entry,
                          action == 'edit' ? entry.onEdit : entry.onArchive),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined),
                                title: Text('编辑'))),
                        const PopupMenuItem(
                            value: 'archive',
                            child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.archive_outlined),
                                title: Text('归档'))),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Tooltip(
                message: entry.name,
                child: Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.isArchived
                    ? '已归档'
                    : entry.isSystem
                        ? '系统预设'
                        : '自定义',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String query) {
    final theme = Theme.of(context);
    final searching = query.isNotEmpty;
    final archived = _filter == _CatalogFilter.archived;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Icon(
            searching
                ? Icons.search_off_rounded
                : archived
                    ? Icons.inventory_2_outlined
                    : Icons.add_reaction_outlined,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            searching
                ? '没有找到匹配的$_itemLabel'
                : archived
                    ? '还没有归档的$_itemLabel'
                    : '添加你的第一个$_sectionLabel',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            searching
                ? '试试其他名称，或清空搜索查看全部'
                : archived
                    ? '不常用的项目可以归档，历史账单仍会保留'
                    : '选择喜欢的图标，按自己的习惯命名',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: searching
                ? () => setState(() => _searchController.clear())
                : archived
                    ? () => setState(() => _filter = _CatalogFilter.active)
                    : _isAdding
                        ? null
                        : _add,
            icon: Icon(
                searching
                    ? Icons.close_rounded
                    : archived
                        ? Icons.arrow_back_rounded
                        : Icons.add_rounded,
                size: 18),
            label: Text(searching
                ? '清空搜索'
                : archived
                    ? '查看使用中'
                    : '新增$_itemLabel'),
          ),
        ],
      ),
    );
  }
}

class _CatalogEntry {
  final String uuid;
  final String name;
  final String icon;
  final bool isSystem;
  final bool isArchived;
  final Future<void> Function() onEdit;
  final Future<void> Function() onArchive;
  final Future<void> Function() onRestore;

  const _CatalogEntry({
    required this.uuid,
    required this.name,
    required this.icon,
    required this.isSystem,
    required this.isArchived,
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
  });
}
