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
  final List<FinanceTransaction> transactions;
  final Map<String, FinanceCategory> categories;
  final Future<void> Function(
    String categoryUuid,
    GlobalKey sourceKey,
    List<FinanceTransaction> periodTransactions,
  )? onCategorySelected;

  const FinanceCategoryDetailScreen({
    super.key,
    required this.periodTitle,
    this.periodStart,
    this.periodEnd,
    this.clock = DateTime.now,
    this.isPlanned = false,
    required this.rootCategoryUuid,
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
  late List<FinanceTransaction> _transactions;
  late Map<String, FinanceCategory> _categories;
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
    final periodChanged = oldWidget.periodStart != widget.periodStart ||
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
      );
      if (!mounted || generation != _loadGeneration) return;

      final now = widget.clock();
      final includesNow = !now.isBefore(from) && now.isBefore(to);
      _scheduleUpcomingTransactionRefresh(
        allTransactions,
        now: now,
        periodStart: from,
        periodEnd: to,
      );
      final nextTransactions = includesNow
          ? allTransactions
                .where(
                  (transaction) =>
                      transaction.balanceEventAt() <=
                      now.millisecondsSinceEpoch,
                )
                .toList(growable: false)
          : allTransactions;
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

  void _scheduleUpcomingTransactionRefresh(
    Iterable<FinanceTransaction> values, {
    required DateTime now,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    _upcomingTransactionTimer?.cancel();
    _upcomingTransactionTimer = null;

    final nowAt = now.millisecondsSinceEpoch;
    final periodEndAt = periodEnd.millisecondsSinceEpoch;
    int? nextEventAt;
    if (now.isBefore(periodStart)) {
      nextEventAt = periodStart.millisecondsSinceEpoch;
    } else if (now.isBefore(periodEnd)) {
      for (final transaction in values) {
        final eventAt = transaction.balanceEventAt();
        if (eventAt > nowAt &&
            eventAt < periodEndAt &&
            (nextEventAt == null || eventAt < nextEventAt)) {
          nextEventAt = eventAt;
        }
      }
    }
    if (nextEventAt == null) return;

    final delayMs = (nextEventAt - nowAt + 1)
        .clamp(1, const Duration(days: 24).inMilliseconds)
        .toInt();
    _upcomingTransactionTimer = Timer(
      Duration(milliseconds: delayMs),
      () {
        _upcomingTransactionTimer = null;
        if (mounted) unawaited(_reloadPeriodData());
      },
    );
  }

  FinanceCategory? get _rootCategory =>
      rootCategoryUuid == null ? null : categories[rootCategoryUuid];

  FinanceCategory _rootFor(FinanceCategory category) {
    var current = category;
    final visited = <String>{};
    while (visited.add(current.uuid)) {
      final parentUuid = current.parentUuid?.trim();
      if (parentUuid == null || parentUuid.isEmpty) break;
      final parent = categories[parentUuid];
      if (parent == null || parent.type != current.type) break;
      current = parent;
    }
    return current;
  }

  String _categoryLabel(FinanceCategory category) =>
      '${financeCategoryDisplayName(category, categories.values)}'
      '${category.isArchived ? '（已归档）' : ''}';

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

  List<FinanceCategory> _childCategories(FinanceCategory root) =>
      categories.values
          .where((category) =>
              !category.isDeleted &&
              category.uuid != root.uuid &&
              _rootFor(category).uuid == root.uuid)
          .toList();

  int _netExpense(Iterable<FinanceTransaction> values) {
    var total = 0;
    for (final transaction in values) {
      total += switch (transaction.type) {
        FinanceTransactionType.expense => transaction.amountMinor,
        FinanceTransactionType.refund => -transaction.amountMinor,
        FinanceTransactionType.income => 0,
      };
    }
    return total;
  }

  List<FinanceTransaction> get _matchingTransactions => transactions
      .where((transaction) =>
          transaction.type != FinanceTransactionType.income &&
          _belongsToRoot(transaction))
      .toList();

  List<_FinanceCategoryDetailItem> _items(
    List<FinanceTransaction> matchingTransactions,
  ) {
    final root = _rootCategory;
    if (root == null) {
      final amount = _netExpense(matchingTransactions);
      if (matchingTransactions.isEmpty) return const [];
      final isUncategorized = rootCategoryUuid == null;
      return [
        _FinanceCategoryDetailItem(
          categoryUuid: isUncategorized
              ? financeUncategorizedCategoryFilterUuid
              : rootCategoryUuid!,
          title: isUncategorized ? '未分类' : '分类已删除或不可用',
          icon: '💰',
          amountMinor: amount,
          transactionCount: matchingTransactions.length,
        ),
      ];
    }

    final children = _childCategories(root);
    final result = <_FinanceCategoryDetailItem>[];
    for (final category in children) {
      final categoryTransactions = matchingTransactions
          .where((transaction) => transaction.categoryUuid == category.uuid)
          .toList();
      if (categoryTransactions.isEmpty) continue;
      final amount = _netExpense(categoryTransactions);
      result.add(
        _FinanceCategoryDetailItem(
          categoryUuid: category.uuid,
          title: _categoryLabel(category),
          icon: category.icon,
          amountMinor: amount,
          transactionCount: categoryTransactions.length,
        ),
      );
    }

    final directTransactions = matchingTransactions
        .where((transaction) => transaction.categoryUuid == root.uuid)
        .toList();
    final directAmount = _netExpense(directTransactions);
    if (directTransactions.isNotEmpty) {
      result.add(
        _FinanceCategoryDetailItem(
          categoryUuid: root.uuid,
          title: _categoryLabel(root),
          icon: root.icon,
          amountMinor: directAmount,
          transactionCount: directTransactions.length,
        ),
      );
    }
    result.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final root = _rootCategory;
    final matchingTransactions = _matchingTransactions;
    final items = _items(matchingTransactions);
    final total = _netExpense(matchingTransactions);
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
      if (hasSubcategories) {
        sectionTitle = isPlanned ? '计划小类' : '小类';
        emptyMessage = isPlanned
            ? '这个大类下暂无可展示的计划小类账单'
            : '这个大类下暂无可展示的小类账单';
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
                    backgroundColor:
                        colorScheme.onPrimaryContainer.withValues(alpha: 0.12),
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
                            color: colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.75),
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
                          color: colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.75),
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
                    _buildItem(context, items[index]),
                    if (index + 1 < items.length)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            isPlanned ? '点击分类即可查看对应计划账单' : '点击分类即可查看对应账单',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    _FinanceCategoryDetailItem item,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final sourceKey = _itemSourceKeys.putIfAbsent(
      item.categoryUuid,
      GlobalKey.new,
    );
    return Padding(
      key: sourceKey,
      padding: EdgeInsets.zero,
      child: ListTile(
        key: ValueKey('finance-category-detail-${item.categoryUuid}'),
        onTap: () async {
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
          '${item.transactionCount} 笔${_isPlanned ? '计划账单' : '账单'} · 点击查看',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatFinanceAmount(item.amountMinor),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
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
