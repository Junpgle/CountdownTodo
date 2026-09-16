import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';

class FinanceCategoryDetailScreen extends StatelessWidget {
  final String periodTitle;
  final String? rootCategoryUuid;
  final List<FinanceTransaction> transactions;
  final Map<String, FinanceCategory> categories;

  const FinanceCategoryDetailScreen({
    super.key,
    required this.periodTitle,
    required this.rootCategoryUuid,
    required this.transactions,
    required this.categories,
  });

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

  bool _belongsToRoot(FinanceTransaction transaction) {
    final category = categories[transaction.categoryUuid];
    final root = _rootCategory;
    if (root == null) return category == null;
    return category != null && _rootFor(category).uuid == root.uuid;
  }

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
    if (root == null) return const [];

    final children = categories.values
        .where((category) =>
            !category.isDeleted &&
            category.uuid != root.uuid &&
            _rootFor(category).uuid == root.uuid)
        .toList();
    final result = <_FinanceCategoryDetailItem>[];
    for (final category in children) {
      final categoryTransactions = matchingTransactions
          .where((transaction) => transaction.categoryUuid == category.uuid)
          .toList();
      final amount = _netExpense(categoryTransactions);
      if (amount <= 0) continue;
      result.add(_FinanceCategoryDetailItem(
        categoryUuid: category.uuid,
        title: category.name,
        icon: category.icon,
        amountMinor: amount,
        transactionCount: categoryTransactions.length,
      ));
    }

    final directTransactions = matchingTransactions
        .where((transaction) => transaction.categoryUuid == root.uuid)
        .toList();
    final directAmount = _netExpense(directTransactions);
    if (directAmount > 0) {
      result.add(_FinanceCategoryDetailItem(
        categoryUuid: root.uuid,
        title: '未细分',
        icon: root.icon,
        amountMinor: directAmount,
        transactionCount: directTransactions.length,
      ));
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

    return Scaffold(
      appBar: AppBar(title: const Text('支出分类详情')),
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
                          root?.name ?? '未分类',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$periodTitle · ${matchingTransactions.length} 笔账单',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatFinanceAmount(total),
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            root == null ? '未分类账单' : '小类',
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
                  root == null ? '没有可筛选的分类账单' : '这个大类下暂无可展示的小类账单',
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
            '点击小类即可查看对应账单',
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
    return ListTile(
      key: ValueKey('finance-category-detail-${item.categoryUuid}'),
      onTap: () => Navigator.of(context).pop(item.categoryUuid),
      leading: CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        child: Text(item.icon, style: const TextStyle(fontSize: 19)),
      ),
      title: Text(item.title),
      subtitle: Text('${item.transactionCount} 笔账单 · 点击查看'),
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
