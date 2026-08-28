import 'package:flutter/material.dart';

import '../models/finance_models.dart';
import '../services/finance_repository.dart';

class FinanceOverviewPanel extends StatelessWidget {
  final DateTime month;
  final FinanceSummary summary;
  final List<FinanceTransaction> transactions;
  final Map<String, FinanceCategory> categories;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;

  const FinanceOverviewPanel({
    super.key,
    required this.month,
    required this.summary,
    required this.transactions,
    required this.categories,
    required this.onAdd,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topCategories = summary.expenseByCategory.entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCategory = topCategories.isEmpty ? 1 : topCategories.first.value;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildSummaryCard(context, colorScheme),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('记一笔'),
          ),
          const SizedBox(height: 24),
          Text(
            '支出分类',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (topCategories.isEmpty)
            _buildEmptyCard(
              context,
              icon: Icons.pie_chart_outline,
              message: '本月还没有支出记录',
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final entry in topCategories.take(8))
                      _buildCategoryBar(
                        context,
                        entry,
                        maxCategory,
                        colorScheme,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            '每日支出',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: _buildDailyBars(context, colorScheme),
            ),
          ),
          const SizedBox(height: 24),
          _buildInsightCard(context, colorScheme),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${month.year} 年 ${month.month} 月',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 8),
            Text(
              formatFinanceAmount(summary.netExpenseMinor),
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '净支出',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: '收入',
                    value: formatFinanceAmount(summary.incomeMinor),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: '实际支出',
                    value: formatFinanceAmount(summary.netExpenseMinor),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                Expanded(
                  child: _buildSummaryMetric(
                    context,
                    label: '结余',
                    value: formatFinanceAmount(summary.balanceMinor),
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetric(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildCategoryBar(
    BuildContext context,
    MapEntry<String, int> entry,
    int maxCategory,
    ColorScheme colorScheme,
  ) {
    final category = categories[entry.key];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              category == null ? '未分类' : '${category.icon} ${category.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: entry.value / maxCategory,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatFinanceAmount(entry.value),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyBars(BuildContext context, ColorScheme colorScheme) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final values = List<int>.generate(
      daysInMonth,
      (index) =>
          summary.expenseByDate[
              dateKey(DateTime(month.year, month.month, index + 1))] ??
          0,
    );
    final maxValue =
        values.fold<int>(0, (max, value) => value > max ? value : max);
    if (maxValue == 0) {
      return _buildEmptyCard(
        context,
        icon: Icons.bar_chart_outlined,
        message: '有了记录后，这里会显示每日趋势',
        nested: true,
      );
    }
    return SizedBox(
      height: 142,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var index = 0; index < values.length; index++)
              SizedBox(
                width: 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: 12,
                            height: values[index] <= 0
                                ? 2
                                : 88 * values[index] / maxValue + 2,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard(BuildContext context, ColorScheme colorScheme) {
    if (summary.transactionCount == 0) return const SizedBox.shrink();
    final average = summary.netExpenseMinor ~/ summary.transactionCount;
    return Card(
      child: ListTile(
        leading: Icon(Icons.lightbulb_outline, color: colorScheme.primary),
        title: const Text('本月小结'),
        subtitle: Text(
          '共 ${summary.transactionCount} 笔记录，平均每笔 ${formatFinanceAmount(average)}。',
        ),
      ),
    );
  }

  Widget _buildEmptyCard(
    BuildContext context, {
    required IconData icon,
    required String message,
    bool nested = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(nested ? 8 : 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              message,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class FinanceLedgerPanel extends StatelessWidget {
  final List<FinanceTransaction> transactions;
  final Map<String, FinanceCategory> categories;
  final Map<String, FinancePaymentMethod> paymentMethods;
  final String keyword;
  final FinanceTransactionType? filterType;
  final ValueChanged<String> onKeywordChanged;
  final ValueChanged<FinanceTransactionType?> onFilterChanged;
  final ValueChanged<FinanceTransaction> onEdit;
  final ValueChanged<FinanceTransaction> onDelete;

  const FinanceLedgerPanel({
    super.key,
    required this.transactions,
    required this.categories,
    required this.paymentMethods,
    required this.keyword,
    required this.filterType,
    required this.onKeywordChanged,
    required this.onFilterChanged,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = transactions.where((transaction) {
      if (filterType != null && transaction.type != filterType) return false;
      if (keyword.trim().isEmpty) return true;
      final query = keyword.trim().toLowerCase();
      final category = categories[transaction.categoryUuid];
      final payment = paymentMethods[transaction.paymentMethodUuid];
      final content = [
        transaction.merchant,
        transaction.note,
        category?.name,
        payment?.name,
        transaction.transactionDate,
      ].whereType<String>().join(' ').toLowerCase();
      return content.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: onKeywordChanged,
            decoration: InputDecoration(
              hintText: '搜索商家、备注或分类',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: keyword.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => onKeywordChanged(''),
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            scrollDirection: Axis.horizontal,
            children: [
              _buildFilterChip(context, '全部', null),
              for (final type in FinanceTransactionType.values)
                _buildFilterChip(context, type.label, type),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(context)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _buildTransactionTile(
                    context,
                    filtered[index],
                  ),
                ),
        ),
      ],
    );
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
        onSelected: (_) => onFilterChanged(type),
      ),
    );
  }

  Widget _buildTransactionTile(
    BuildContext context,
    FinanceTransaction transaction,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = categories[transaction.categoryUuid];
    final payment = paymentMethods[transaction.paymentMethodUuid];
    final title = transaction.merchant?.isNotEmpty == true
        ? transaction.merchant!
        : category?.name ?? transaction.type.label;
    final subtitleParts = <String>[
      if (category != null) '${category.icon} ${category.name}',
      if (payment != null) '${payment.icon} ${payment.name}',
      if (transaction.note?.isNotEmpty == true) transaction.note!,
    ];
    final amountColor = transaction.type == FinanceTransactionType.expense
        ? colorScheme.error
        : colorScheme.primary;
    return Card(
      child: ListTile(
        onTap: () => onEdit(transaction),
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondaryContainer,
          child: Text(
            category?.icon ?? '💰',
            style: const TextStyle(fontSize: 20),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${transaction.transactionDate}${subtitleParts.isEmpty ? '' : ' · ${subtitleParts.join(' · ')}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatSignedFinanceAmount(
                  transaction.amountMinor, transaction.type),
              style: TextStyle(
                color: amountColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') onEdit(transaction);
                if (value == 'delete') onDelete(transaction);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            keyword.isEmpty && filterType == null ? '本月还没有账单' : '没有匹配的账单',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
