import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';

class FinanceCategoryDetailScreen extends StatefulWidget {
  final String periodTitle;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime Function() clock;
  final bool isPlanned;
  final String? rootCategoryUuid;
  final bool categoryTapOpensLedger;
  final List<FinanceTransaction> transactions;
  final Map<String, FinanceCategory> categories;
  final Future<void> Function(
    String categoryUuid,
    GlobalKey sourceKey,
    List<FinanceTransaction> periodTransactions,
  )?
  onCategorySelected;

  const FinanceCategoryDetailScreen({
    super.key,
    required this.periodTitle,
    this.periodStart,
    this.periodEnd,
    this.clock = DateTime.now,
    this.isPlanned = false,
    required this.rootCategoryUuid,
    this.categoryTapOpensLedger = true,
    required this.transactions,
    required this.categories,
    this.onCategorySelected,
  });

  @override
  State<FinanceCategoryDetailScreen> createState() =>
      _FinanceCategoryDetailScreenState();
}

class _FinanceCategoryDetailScreenState
    extends State<FinanceCategoryDetailScreen> {
  final Map<String, GlobalKey> _itemSourceKeys = {};
  bool _openingCategoryLedger = false;
  String? _expandedCategoryUuid;
  late List<FinanceTransaction> _transactions;
  late Map<String, FinanceCategory> _categories;
  Map<String, FinanceCategory>? _categoryRootCacheSource;
  Map<String, FinanceCategory> _categoryRootsByUuid = const {};
  Map<String, FinanceCategory>? _categoryLabelCacheSource;
  final Map<String, String> _categoryLabelsByUuid = {};
  Timer? _financeChangeRefreshTimer;
  Timer? _upcomingTransactionTimer;
  int _loadGeneration = 0;

  String get periodTitle => widget.periodTitle;
  String? get rootCategoryUuid => widget.rootCategoryUuid;
  List<FinanceTransaction> get transactions => _transactions;
  Map<String, FinanceCategory> get categories => _categories;
  bool get _isPlanned {
    final from = widget.periodStart;
    return from == null ? widget.isPlanned : from.isAfter(widget.clock());
  }

  @override
  void initState() {
    super.initState();
    _transactions = widget.transactions;
    _categories = widget.categories;
    FinanceStorage.revision.addListener(_onFinanceChanged);
    unawaited(_reloadPeriodData());
  }

  @override
  void didUpdateWidget(covariant FinanceCategoryDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final periodChanged =
        oldWidget.periodStart != widget.periodStart ||
        oldWidget.periodEnd != widget.periodEnd;
    if (periodChanged) {
      _upcomingTransactionTimer?.cancel();
      _upcomingTransactionTimer = null;
      unawaited(_reloadPeriodData());
    }
    if (!identical(oldWidget.transactions, widget.transactions)) {
      _transactions = widget.transactions;
    }
    if (!identical(oldWidget.categories, widget.categories)) {
      _categories = widget.categories;
    }
  }

  @override
  void dispose() {
    _financeChangeRefreshTimer?.cancel();
    _upcomingTransactionTimer?.cancel();
    FinanceStorage.revision.removeListener(_onFinanceChanged);
    super.dispose();
  }

  void _onFinanceChanged() {
    _financeChangeRefreshTimer?.cancel();
    _financeChangeRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      _financeChangeRefreshTimer = null;
      if (mounted) unawaited(_reloadPeriodData());
    });
  }

  Future<void> _reloadPeriodData() async {
    final from = widget.periodStart;
    final to = widget.periodEnd;
    if (from == null || to == null || !from.isBefore(to)) return;

    final generation = ++_loadGeneration;
    try {
      final allTransactions = await FinanceRepository.getTransactions(
        from: from,
        to: to,
      );
      final refreshedCategories = await FinanceRepository.getCategories(
        includeArchived: true,
        includeDeleted: true,
      );
      if (!mounted || generation != _loadGeneration) return;

      final now = widget.clock();
      final nowAt = now.millisecondsSinceEpoch;
      final periodEndAt = to.millisecondsSinceEpoch;
      var nextTransactions = allTransactions;
      int? nextEventAt;
      if (now.isBefore(from)) {
        nextEventAt = from.millisecondsSinceEpoch;
      } else if (now.isBefore(to)) {
        final occurredTransactions = <FinanceTransaction>[];
        for (final transaction in allTransactions) {
          final eventAt = transaction.balanceEventAt();
          if (eventAt <= nowAt) {
            occurredTransactions.add(transaction);
          } else if (eventAt < periodEndAt &&
              (nextEventAt == null || eventAt < nextEventAt)) {
            nextEventAt = eventAt;
          }
        }
        nextTransactions = occurredTransactions;
      }
      _scheduleUpcomingTransactionRefresh(now: now, nextEventAt: nextEventAt);
      final nextCategories = {
        for (final category in refreshedCategories) category.uuid: category,
      };

      setState(() {
        _transactions = nextTransactions;
        _categories = nextCategories;
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('刷新支出分类详情失败：$error');
      // Keep the last usable detail visible if refreshing from local storage fails.
    }
  }

  void _scheduleUpcomingTransactionRefresh({
    required DateTime now,
    required int? nextEventAt,
  }) {
    _upcomingTransactionTimer?.cancel();
    _upcomingTransactionTimer = null;

    if (nextEventAt == null) return;
    final nowAt = now.millisecondsSinceEpoch;

    final delayMs = (nextEventAt - nowAt + 1)
        .clamp(1, const Duration(days: 24).inMilliseconds)
        .toInt();
    _upcomingTransactionTimer = Timer(Duration(milliseconds: delayMs), () {
      _upcomingTransactionTimer = null;
      if (mounted) unawaited(_reloadPeriodData());
    });
  }

  FinanceCategory? get _rootCategory =>
      rootCategoryUuid == null ? null : categories[rootCategoryUuid];

  void _ensureCategoryRootCache() {
    if (identical(_categoryRootCacheSource, categories)) return;

    final rootsByUuid = <String, FinanceCategory>{};
    for (final category in categories.values) {
      var current = category;
      final visited = <String>{};
      while (visited.add(current.uuid)) {
        final parentUuid = current.parentUuid?.trim();
        if (parentUuid == null || parentUuid.isEmpty) break;
        final parent = categories[parentUuid];
        if (parent == null || parent.type != current.type) break;
        current = parent;
      }
      rootsByUuid[category.uuid] = current;
    }

    _categoryRootCacheSource = categories;
    _categoryRootsByUuid = rootsByUuid;
  }

  FinanceCategory _rootFor(FinanceCategory category) {
    _ensureCategoryRootCache();
    return _categoryRootsByUuid[category.uuid] ?? category;
  }

  String _categoryLabel(FinanceCategory category) {
    if (!identical(_categoryLabelCacheSource, categories)) {
      _categoryLabelCacheSource = categories;
      _categoryLabelsByUuid.clear();
    }
    final displayName = _categoryLabelsByUuid.putIfAbsent(
      category.uuid,
      () =>
          financeCategoryReferenceDisplayName(category.uuid, categories.values),
    );
    return '$displayName${category.isArchived ? '（已归档）' : ''}';
  }

  bool _belongsToRoot(FinanceTransaction transaction) {
    final category = categories[transaction.categoryUuid];
    final root = _rootCategory;
    if (root == null) {
      if (rootCategoryUuid != null) {
        return transaction.categoryUuid == rootCategoryUuid;
      }
      return transaction.categoryUuid == null ||
          transaction.categoryUuid!.trim().isEmpty;
    }
    return category != null && _rootFor(category).uuid == root.uuid;
  }

  List<FinanceCategory> _childCategories(FinanceCategory root) => categories
      .values
      .where(
        (category) =>
            category.uuid != root.uuid && _rootFor(category).uuid == root.uuid,
      )
      .toList();

  List<FinanceTransaction> get _matchingTransactions => transactions
      .where(
        (transaction) =>
            transaction.type != FinanceTransactionType.income &&
            _belongsToRoot(transaction),
      )
      .toList();

  ({List<_FinanceCategoryDetailItem> items, int total}) _itemsAndTotal(
    List<FinanceTransaction> matchingTransactions,
  ) {
    final amountByCategory = <String, int>{};
    final countByCategory = <String, int>{};
    var total = 0;
    for (final transaction in matchingTransactions) {
      final contribution = switch (transaction.type) {
        FinanceTransactionType.expense => transaction.amountMinor,
        FinanceTransactionType.refund => -transaction.amountMinor,
        FinanceTransactionType.income => 0,
      };
      total += contribution;
      final categoryUuid = transaction.categoryUuid;
      if (categoryUuid == null) continue;
      amountByCategory[categoryUuid] =
          (amountByCategory[categoryUuid] ?? 0) + contribution;
      countByCategory[categoryUuid] = (countByCategory[categoryUuid] ?? 0) + 1;
    }

    final root = _rootCategory;
    if (root == null) {
      if (matchingTransactions.isEmpty) {
        return (items: const [], total: total);
      }
      final isUncategorized = rootCategoryUuid == null;
      return (
        items: [
          _FinanceCategoryDetailItem(
            categoryUuid: isUncategorized
                ? financeUncategorizedCategoryFilterUuid
                : rootCategoryUuid!,
            title: isUncategorized ? '未分类' : '分类已删除或不可用',
            icon: '💰',
            amountMinor: total,
            transactionCount: matchingTransactions.length,
          ),
        ],
        total: total,
      );
    }

    final children = _childCategories(root);
    final result = <_FinanceCategoryDetailItem>[];
    for (final category in children) {
      final transactionCount = countByCategory[category.uuid] ?? 0;
      if (transactionCount == 0) continue;
      result.add(
        _FinanceCategoryDetailItem(
          categoryUuid: category.uuid,
          title: _categoryLabel(category),
          icon: category.icon,
          amountMinor: amountByCategory[category.uuid] ?? 0,
          transactionCount: transactionCount,
        ),
      );
    }

    final directCount = countByCategory[root.uuid] ?? 0;
    if (directCount > 0) {
      result.add(
        _FinanceCategoryDetailItem(
          categoryUuid: root.uuid,
          title: _categoryLabel(root),
          icon: root.icon,
          amountMinor: amountByCategory[root.uuid] ?? 0,
          transactionCount: directCount,
        ),
      );
    }
    result.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return (items: result, total: total);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final root = _rootCategory;
    final matchingTransactions = _matchingTransactions;
    final summary = _itemsAndTotal(matchingTransactions);
    final items = summary.items;
    final total = summary.total;
    final hasSubcategories = root != null && _childCategories(root).isNotEmpty;
    final String categoryTitle;
    final String sectionTitle;
    final String emptyMessage;
    final isPlanned = _isPlanned;
    if (root == null) {
      categoryTitle = rootCategoryUuid == null ? '未分类' : '分类已删除';
      sectionTitle = rootCategoryUuid == null ? '未分类账单' : '历史账单';
      if (rootCategoryUuid == null) {
        emptyMessage = isPlanned ? '没有可筛选的计划分类账单' : '没有可筛选的分类账单';
      } else {
        emptyMessage = '这个分类已删除或不可用';
      }
    } else {
      categoryTitle = _categoryLabel(root);
      if (root.isDeleted) {
        sectionTitle = '历史账单';
        emptyMessage = '这个分类没有可展示的历史账单';
      } else if (hasSubcategories) {
        sectionTitle = isPlanned ? '计划小类' : '小类';
        emptyMessage = isPlanned ? '这个大类下暂无可展示的计划小类账单' : '这个大类下暂无可展示的小类账单';
      } else {
        sectionTitle = isPlanned ? '计划分类' : '分类';
        emptyMessage = isPlanned ? '这个分类下暂无计划账单' : '这个分类下暂无账单';
      }
    }

    return Scaffold(
      appBar: FloatingGlassAppBar(
        title: Text(isPlanned ? '计划支出分类详情' : '支出分类详情'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Card(
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.12,
                    ),
                    child: Text(
                      root?.icon ?? '💰',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          categoryTitle,
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$periodTitle · ${matchingTransactions.length} 笔'
                          '${isPlanned ? '计划账单' : '账单'}',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isPlanned ? '计划净支出' : '净支出',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer.withValues(
                            alpha: 0.75,
                          ),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        formatFinanceAmount(total),
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            sectionTitle,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _buildItem(
                      context,
                      items[index],
                      expanded:
                          !widget.categoryTapOpensLedger &&
                          _expandedCategoryUuid == items[index].categoryUuid,
                    ),
                    if (index + 1 < items.length)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            widget.categoryTapOpensLedger
                ? isPlanned
                      ? '点击分类即可进入计划账单筛选'
                      : '点击分类即可进入账单筛选'
                : isPlanned
                ? '点击分类可在当前页展开或收起计划账单'
                : '点击分类可在当前页展开或收起对应账单',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    _FinanceCategoryDetailItem item, {
    required bool expanded,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final sourceKey = _itemSourceKeys.putIfAbsent(
      item.categoryUuid,
      GlobalKey.new,
    );
    return Column(
      children: [
        Padding(
          key: sourceKey,
          padding: EdgeInsets.zero,
          child: ListTile(
            key: ValueKey('finance-category-detail-${item.categoryUuid}'),
            onTap: () async {
              if (!widget.categoryTapOpensLedger) {
                setState(() {
                  _expandedCategoryUuid = expanded ? null : item.categoryUuid;
                });
                return;
              }
              final onSelected = widget.onCategorySelected;
              if (onSelected == null) {
                Navigator.of(context).pop(item.categoryUuid);
                return;
              }
              if (_openingCategoryLedger) return;
              _openingCategoryLedger = true;
              try {
                await onSelected(item.categoryUuid, sourceKey, transactions);
              } finally {
                _openingCategoryLedger = false;
              }
            },
            leading: CircleAvatar(
              backgroundColor: colorScheme.secondaryContainer,
              child: Text(item.icon, style: const TextStyle(fontSize: 19)),
            ),
            title: Text(item.title),
            subtitle: Text(
              '${item.transactionCount} 笔${_isPlanned ? '计划账单' : '账单'}'
              '${widget.categoryTapOpensLedger
                  ? ' · 点击查看'
                  : expanded
                  ? ' · 点击收起'
                  : ' · 点击展开'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatFinanceAmount(item.amountMinor),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 4),
                Icon(
                  widget.categoryTapOpensLedger
                      ? Icons.chevron_right
                      : expanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
              ],
            ),
          ),
        ),
        _buildExpandedBills(context, item, expanded: expanded),
      ],
    );
  }

  Widget _buildExpandedBills(
    BuildContext context,
    _FinanceCategoryDetailItem item, {
    required bool expanded,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final matches = expanded
        ? _transactionsForItem(item)
        : const <FinanceTransaction>[];
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: !expanded
          ? const SizedBox(width: double.infinity)
          : Column(
              children: [
                const Divider(height: 1, indent: 72),
                for (var index = 0; index < matches.length; index++) ...[
                  _buildInlineBill(context, matches[index], colorScheme),
                  if (index + 1 < matches.length)
                    Divider(
                      height: 1,
                      indent: 96,
                      color: colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
    );
  }

  List<FinanceTransaction> _transactionsForItem(
    _FinanceCategoryDetailItem item,
  ) {
    final matches = <FinanceTransaction>[];
    for (final transaction in transactions) {
      if (transaction.type == FinanceTransactionType.income) continue;
      final matchesCategory =
          item.categoryUuid == financeUncategorizedCategoryFilterUuid
          ? transaction.categoryUuid == null ||
                transaction.categoryUuid!.trim().isEmpty
          : transaction.categoryUuid == item.categoryUuid;
      if (matchesCategory) matches.add(transaction);
    }
    if (matches.length < 2) return matches;

    final timedMatches = [
      for (final transaction in matches)
        (transaction: transaction, eventAt: transaction.balanceEventAt()),
    ];
    timedMatches.sort((left, right) {
      final dateComparison = right.transaction.transactionDate.compareTo(
        left.transaction.transactionDate,
      );
      if (dateComparison != 0) return dateComparison;
      return right.eventAt.compareTo(left.eventAt);
    });
    for (var index = 0; index < timedMatches.length; index++) {
      matches[index] = timedMatches[index].transaction;
    }
    return matches;
  }

  Widget _buildInlineBill(
    BuildContext context,
    FinanceTransaction transaction,
    ColorScheme colorScheme,
  ) {
    final merchant = transaction.merchant?.trim();
    final note = transaction.note?.trim();
    final title = merchant?.isNotEmpty == true
        ? merchant!
        : note?.isNotEmpty == true
        ? note!
        : transaction.type.label;
    final date = dateFromKey(transaction.transactionDate);
    final occurred = transaction.occurrenceLocalTime;
    final subtitleParts = <String>[
      '${date.month}月${date.day}日',
      if (occurred != null && dateKey(occurred) == transaction.transactionDate)
        '${occurred.hour.toString().padLeft(2, '0')}:'
            '${occurred.minute.toString().padLeft(2, '0')}',
      if (transaction.installmentLabel != null)
        '分期 ${transaction.installmentLabel}',
      if (note?.isNotEmpty == true && note != title) note!,
    ];
    final isRefund = transaction.type == FinanceTransactionType.refund;
    final amount = isRefund
        ? '+${formatFinanceAmount(transaction.amountMinor)}'
        : '−${formatFinanceAmount(transaction.amountMinor)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 9, 16, 9),
      child: Row(
        children: [
          Icon(
            isRefund ? Icons.undo_rounded : Icons.receipt_long_outlined,
            size: 18,
            color: isRefund
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  subtitleParts.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: TextStyle(
              color: isRefund ? colorScheme.primary : colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceCategoryDetailItem {
  final String categoryUuid;
  final String title;
  final String icon;
  final int amountMinor;
  final int transactionCount;

  const _FinanceCategoryDetailItem({
    required this.categoryUuid,
    required this.title,
    required this.icon,
    required this.amountMinor,
    required this.transactionCount,
  });
}
