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
  final Future<void> Function(FinanceCategory parent)? onAddSubcategory;
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
    this.onAddSubcategory,
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
  final _expandedCategoryUuids = <String>{};
  bool _isAdding = false;

  bool get _isPayment => _section == _CatalogSection.payment;
  String get _itemLabel => _isPayment ? '付款方式' : '一级分类';
  String get _lockedItemLabel => _isPayment ? '付款方式' : '分类';
  String get _sectionLabel => switch (_section) {
        _CatalogSection.expense => '支出分类',
        _CatalogSection.income => '收入分类',
        _CatalogSection.payment => '付款方式',
      };

  List<_CatalogEntry> get _entries {
    if (_isPayment) {
      return [
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
      ];
    }

    final categoriesByUuid = <String, FinanceCategory>{
      for (final category in widget.categories) category.uuid: category,
    };
    final type = _section == _CatalogSection.expense
        ? FinanceCategoryType.expense
        : FinanceCategoryType.income;
    final entries = <_CatalogEntry>[];
    for (final category in widget.categories) {
      if (category.isDeleted || category.type != type) continue;
      entries.add(
        _CatalogEntry(
          uuid: category.uuid,
          name: category.name,
          icon: category.icon,
          isSystem: category.isSystem,
          isArchived: category.isArchived,
          parentUuid: category.parentUuid,
          searchName: _categorySearchName(category, categoriesByUuid),
          onEdit: () => widget.onEditCategory(category),
          onArchive: () => widget.onArchiveCategory(category),
          onRestore: () => widget.onRestoreCategory(category),
          onAddSubcategory: category.parentUuid?.trim().isNotEmpty == true ||
                  category.isArchived ||
                  widget.onAddSubcategory == null
              ? null
              : () => widget.onAddSubcategory!(category),
        ),
      );
    }
    return entries;
  }

  String _categorySearchName(
    FinanceCategory category,
    Map<String, FinanceCategory> categoriesByUuid,
  ) {
    final names = <String>[];
    final visited = <String>{};
    FinanceCategory? current = category;
    while (current != null && visited.add(current.uuid)) {
      names.insert(0, current.name);
      final parentUuid = current.parentUuid?.trim();
      if (parentUuid == null || parentUuid.isEmpty) break;
      final parent = categoriesByUuid[parentUuid];
      if (parent == null || parent.type != current.type) break;
      current = parent;
    }
    return names.join(' - ');
  }

  bool _matchesFilter(_CatalogEntry entry, _CatalogFilter filter) =>
      switch (filter) {
        _CatalogFilter.active => !entry.isArchived,
        _CatalogFilter.custom => !entry.isArchived && !entry.isSystem,
        _CatalogFilter.archived => entry.isArchived,
      };

  bool _matchesSearch(_CatalogEntry entry, String query) {
    if (query.isEmpty) return true;
    return entry.name.toLowerCase().contains(query) ||
        entry.icon.contains(query) ||
        entry.searchName.toLowerCase().contains(query);
  }

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
      _expandedCategoryUuids.clear();
    });
  }

  void _toggleCategoryExpanded(String uuid) {
    setState(() {
      if (!_expandedCategoryUuids.add(uuid)) {
        _expandedCategoryUuids.remove(uuid);
      }
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
            _matchesFilter(entry, _filter) && _matchesSearch(entry, query))
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
        else if (_isPayment && _filter == _CatalogFilter.archived)
          _buildGroup(context, '已归档', '恢复后可在新账单中继续使用', visible)
        else if (_isPayment) ...[
          if (personal.isNotEmpty)
            _buildGroup(context, '我的$_itemLabel', '点击卡片即可编辑', personal),
          if (personal.isNotEmpty && system.isNotEmpty)
            const SizedBox(height: 24),
          if (system.isNotEmpty)
            _buildGroup(context, '系统预设', '内置常用项目，随时可用', system),
        ] else ...[
          _buildCategoryGroups(context, entries, visible, query),
        ],
      ],
    );
  }

  Widget _buildCategoryGroups(
    BuildContext context,
    List<_CatalogEntry> entries,
    List<_CatalogEntry> visible,
    String query,
  ) {
    final roots = entries
        .where((entry) => entry.parentUuid?.trim().isNotEmpty != true)
        .toList();
    final childrenByParent = <String, List<_CatalogEntry>>{};
    for (final entry in entries) {
      final parentUuid = entry.parentUuid?.trim();
      if (parentUuid == null || parentUuid.isEmpty) continue;
      childrenByParent
          .putIfAbsent(parentUuid, () => <_CatalogEntry>[])
          .add(entry);
    }
    final visibleUuids = visible.map((entry) => entry.uuid).toSet();
    final groups = <_CategoryGroup>[];
    final assigned = <String>{};

    for (final root in roots) {
      final children = [
        for (final child
            in childrenByParent[root.uuid] ?? const <_CatalogEntry>[])
          if (_matchesFilter(child, _filter)) child,
      ];
      final rootMatches = visibleUuids.contains(root.uuid);
      final matchingChildren =
          children.where((entry) => visibleUuids.contains(entry.uuid)).toList();
      if (!rootMatches && matchingChildren.isEmpty) continue;

      final showAllChildren = query.isEmpty || rootMatches;
      groups.add(_CategoryGroup(
        parent: root,
        children: showAllChildren ? children : matchingChildren,
      ));
      assigned.add(root.uuid);
      assigned.addAll(children.map((entry) => entry.uuid));
    }

    final orphans = visible
        .where((entry) =>
            entry.parentUuid?.trim().isNotEmpty == true &&
            !assigned.contains(entry.uuid))
        .toList();
    if (orphans.isNotEmpty) {
      groups.add(_CategoryGroup(parent: null, children: orphans));
    }

    final rootCount = groups.where((group) => group.parent != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCatalogHeading(
          context,
          title: '一级分类 · $rootCount',
          subtitle: query.isEmpty ? '二级分类已收在所属一级分类下' : '匹配到的二级分类会保留所属一级分类作为上下文',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns =
                (constraints.maxWidth / (280 * math.max(1, textScale)))
                    .floor()
                    .clamp(1, 3);
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final group in groups)
                  SizedBox(
                    width: width,
                    child: _buildCategoryGroup(context, group, query),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCatalogHeading(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          Text(subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildCategoryGroup(
      BuildContext context, _CategoryGroup group, String query) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final parent = group.parent;
    if (parent == null) {
      return Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side:
              BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('未归类的二级分类',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('上级一级分类已不存在，历史数据仍可继续管理',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 8),
              for (final child in group.children)
                _buildSubcategoryTile(context, child),
            ],
          ),
        ),
      );
    }

    final expanded = _expandedCategoryUuids.contains(parent.uuid) ||
        (query.isNotEmpty &&
            group.children.any((child) => _matchesSearch(child, query)));

    return Material(
      key: ValueKey('finance-catalog-item-${parent.uuid}'),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: group.children.isEmpty
                ? null
                : () => _toggleCategoryExpanded(parent.uuid),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIconBadge(context, parent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(parent.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          parent.isArchived
                              ? '已归档 · ${group.children.length} 个二级分类'
                              : '${parent.isSystem ? '系统预设' : '自定义'} · ${group.children.length} 个二级分类',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (group.children.isNotEmpty)
                    Tooltip(
                      message: expanded ? '收起二级分类' : '展开二级分类',
                      child: Semantics(
                        label: expanded ? '收起二级分类' : '展开二级分类',
                        child: AnimatedRotation(
                          key:
                              ValueKey('finance-catalog-expand-${parent.uuid}'),
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          child: Icon(Icons.expand_more_rounded,
                              color: colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  _buildEntryActions(context, parent),
                ],
              ),
            ),
          ),
          if (group.children.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(70, 0, 14, 12),
              child: Text(
                parent.isArchived ? '归档后不会在新账单中显示' : '还没有二级分类',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            )
          else
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: Column(
                        children: [
                          Divider(
                              height: 1,
                              color:
                                  colors.outlineVariant.withValues(alpha: 0.5)),
                          const SizedBox(height: 2),
                          for (final child in group.children)
                            _buildSubcategoryTile(context, child),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildSubcategoryTile(BuildContext context, _CatalogEntry entry) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      key: ValueKey('finance-catalog-item-${entry.uuid}'),
      color: colors.surface.withValues(alpha: 0),
      child: InkWell(
        onTap: (entry.isSystem && _isPayment) || _busyItems.contains(entry.uuid)
            ? null
            : () => _runAction(entry, entry.onEdit),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(entry.icon.isEmpty ? '📦' : entry.icon,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(
                  entry.isArchived
                      ? '已归档'
                      : entry.isSystem
                          ? '系统'
                          : '自定义',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
              _buildEntryActions(context, entry),
            ],
          ),
        ),
      ),
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
    return Material(
      key: ValueKey('finance-catalog-item-${entry.uuid}'),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: (entry.isSystem && _isPayment) || busy
            ? null
            : () => _runAction(entry, entry.onEdit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildIconBadge(context, entry),
                  const Spacer(),
                  _buildEntryActions(context, entry),
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

  Widget _buildIconBadge(BuildContext context, _CatalogEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final tint = switch (_section) {
      _CatalogSection.expense => colors.primaryContainer,
      _CatalogSection.income => colors.tertiaryContainer,
      _CatalogSection.payment => colors.secondaryContainer,
    };
    return Container(
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
    );
  }

  Widget _buildEntryActions(BuildContext context, _CatalogEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final busy = _busyItems.contains(entry.uuid);
    if (busy) {
      return const SizedBox(
          width: 40,
          height: 40,
          child: Padding(
            padding: EdgeInsets.all(10),
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
    }
    if (entry.isSystem && _isPayment) {
      return Tooltip(
        message: '系统预设$_lockedItemLabel不可编辑或归档',
        child: Icon(Icons.lock_outline_rounded,
            size: 16, color: colors.onSurfaceVariant),
      );
    }
    if (entry.isSystem) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '自定义${entry.name}图标',
            onPressed: () => _runAction(entry, entry.onEdit),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          if (entry.onAddSubcategory != null)
            IconButton(
              tooltip: '新增${entry.name}下的小类',
              onPressed: () => _runAction(entry, entry.onAddSubcategory!),
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
        ],
      );
    }
    if (entry.isArchived) {
      return IconButton(
        tooltip: '恢复${entry.name}',
        onPressed: () => _runAction(entry, entry.onRestore),
        icon: const Icon(Icons.unarchive_outlined, size: 20),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.onAddSubcategory != null)
          IconButton(
            tooltip: '新增${entry.name}下的小类',
            onPressed: () => _runAction(entry, entry.onAddSubcategory!),
            icon: const Icon(Icons.add_rounded, size: 20),
          ),
        PopupMenuButton<String>(
          tooltip: '管理${entry.name}',
          icon: Icon(Icons.more_horiz_rounded, color: colors.onSurfaceVariant),
          onSelected: (action) => _runAction(
              entry, action == 'edit' ? entry.onEdit : entry.onArchive),
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
  final String? parentUuid;
  final String searchName;
  final Future<void> Function() onEdit;
  final Future<void> Function() onArchive;
  final Future<void> Function() onRestore;
  final Future<void> Function()? onAddSubcategory;

  const _CatalogEntry({
    required this.uuid,
    required this.name,
    required this.icon,
    required this.isSystem,
    required this.isArchived,
    this.parentUuid,
    this.searchName = '',
    required this.onEdit,
    required this.onArchive,
    required this.onRestore,
    this.onAddSubcategory,
  });
}

class _CategoryGroup {
  final _CatalogEntry? parent;
  final List<_CatalogEntry> children;

  const _CategoryGroup({required this.parent, required this.children});
}
