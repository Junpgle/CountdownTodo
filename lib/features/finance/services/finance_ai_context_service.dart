import '../models/finance_models.dart';
import 'finance_repository.dart';

/// The date window used when the assistant asks the finance repository for
/// data.  `to` is exclusive, matching the storage query contract.
class FinanceDateRange {
  final DateTime from;
  final DateTime to;

  const FinanceDateRange(this.from, this.to);

  String get label =>
      '${dateKey(from)} 至 ${dateKey(to.subtract(const Duration(days: 1)))}';
}

/// Builds a small, query-scoped finance snapshot for the AI assistant.
///
/// The snapshot is intentionally separate from the generic todo context:
/// finance data is personal and should only enter a request when the user is
/// asking about existing bills, budgets, or a bill mutation.  Mutations still
/// require a confirmation card in the chat UI.
abstract final class FinanceAiContextService {
  static const _financeNouns = [
    '记账',
    '账单',
    '交易',
    '支出',
    '收入',
    '退款',
    '消费',
    '花费',
    '花了',
    '付款',
    '支付',
    '余额',
    '预算',
    '这笔',
    '那笔',
  ];

  static const _queryWords = [
    '多少',
    '统计',
    '汇总',
    '明细',
    '查询',
    '查看',
    '列出',
    '哪些',
    '排行',
    '占比',
    '余额',
    '预算',
  ];

  static const _periodWords = [
    '本月',
    '这个月',
    '当月',
    '本周',
    '这周',
    '今天',
    '今日',
    '昨天',
    '前天',
    '上月',
    '上个月',
    '最近',
    '今年',
    '本年',
  ];

  static const _summaryNouns = [
    '账单',
    '交易',
    '支出',
    '收入',
    '退款',
    '消费',
    '花费',
    '余额',
    '预算',
  ];

  static const _mutationWords = [
    '修改',
    '更新',
    '更正',
    '改成',
    '改为',
    '删除',
    '删掉',
    '移除',
  ];

  static bool shouldInjectFor(String userMessage) {
    final text = userMessage.trim();
    if (text.isEmpty || !_containsAny(text, _financeNouns)) return false;
    final asksForData = _containsAny(text, _queryWords) ||
        (_containsAny(text, _periodWords) && _containsAny(text, _summaryNouns));
    return asksForData || _containsAny(text, _mutationWords);
  }

  static Future<String> buildContext({
    required String userMessage,
    DateTime? now,
  }) async {
    if (!shouldInjectFor(userMessage)) return '';

    final nowValue = now ?? DateTime.now();
    final range = resolveDateRange(userMessage, now: nowValue);
    try {
      final values = await Future.wait<dynamic>([
        FinanceRepository.getSummary(from: range.from, to: range.to),
        FinanceRepository.getTransactions(
          from: range.from,
          to: range.to,
          limit: 60,
        ),
        FinanceRepository.getCategories(includeArchived: true),
        FinanceRepository.getPaymentMethods(includeArchived: true),
        FinanceRepository.getBudgets(monthKey: financeMonthKey(range.from)),
      ]);
      return _formatContext(
        range: range,
        summary: values[0] as FinanceSummary,
        transactions: values[1] as List<FinanceTransaction>,
        categories: values[2] as List<FinanceCategory>,
        paymentMethods: values[3] as List<FinancePaymentMethod>,
        budgets: values[4] as List<FinanceBudget>,
      );
    } catch (_) {
      // The assistant remains usable when the local database is temporarily
      // unavailable.  It must not receive a guessed or partial transaction.
      return '';
    }
  }

  static FinanceDateRange resolveDateRange(
    String userMessage, {
    DateTime? now,
  }) {
    final current = _day(now ?? DateTime.now());
    final text = userMessage.trim().toLowerCase();
    if (text.contains('前天')) {
      final day = current.subtract(const Duration(days: 2));
      return FinanceDateRange(day, day.add(const Duration(days: 1)));
    }
    if (text.contains('昨天') || text.contains('yesterday')) {
      final day = current.subtract(const Duration(days: 1));
      return FinanceDateRange(day, day.add(const Duration(days: 1)));
    }
    if (text.contains('今天') || text.contains('今日') || text.contains('today')) {
      return FinanceDateRange(current, current.add(const Duration(days: 1)));
    }
    if (text.contains('上周') || text.contains('上星期')) {
      final thisMonday = _mondayOf(current);
      final from = thisMonday.subtract(const Duration(days: 7));
      return FinanceDateRange(from, thisMonday);
    }
    if (text.contains('本周') || text.contains('这周') || text.contains('这星期')) {
      final from = _mondayOf(current);
      return FinanceDateRange(from, from.add(const Duration(days: 7)));
    }
    if (text.contains('上月') || text.contains('上个月')) {
      final from = DateTime(current.year, current.month - 1);
      return FinanceDateRange(from, DateTime(current.year, current.month));
    }
    if (text.contains('今年') || text.contains('本年')) {
      final from = DateTime(current.year);
      return FinanceDateRange(from, DateTime(current.year + 1));
    }
    if (text.contains('本月') || text.contains('这个月') || text.contains('当月')) {
      final from = DateTime(current.year, current.month);
      return FinanceDateRange(from, DateTime(current.year, current.month + 1));
    }
    if (text.contains('最近7天') || text.contains('最近七天')) {
      final from = current.subtract(const Duration(days: 6));
      return FinanceDateRange(from, current.add(const Duration(days: 1)));
    }
    // A bare “账单/支出/余额” query defaults to the current month.  This is
    // predictable and avoids sending the entire lifetime ledger to a model.
    final from = DateTime(current.year, current.month);
    return FinanceDateRange(from, DateTime(current.year, current.month + 1));
  }

  static String _formatContext({
    required FinanceDateRange range,
    required FinanceSummary summary,
    required List<FinanceTransaction> transactions,
    required List<FinanceCategory> categories,
    required List<FinancePaymentMethod> paymentMethods,
    required List<FinanceBudget> budgets,
  }) {
    final categoryMap = {for (final item in categories) item.uuid: item};
    final paymentMap = {for (final item in paymentMethods) item.uuid: item};

    String categoryName(String? uuid) {
      if (uuid == null || uuid.isEmpty) return '未分类';
      return categoryMap[uuid]?.name ?? '未分类';
    }

    String paymentName(String? uuid) {
      if (uuid == null || uuid.isEmpty) return '未指定';
      return paymentMap[uuid]?.name ?? '未指定';
    }

    final lines = <String>[
      '【相关记账上下文｜只读快照】',
      '查询范围: ${range.label}（结束日期不含当天）',
      '汇总: 收入 ${formatFinanceAmount(summary.incomeMinor)} | '
          '支出 ${formatFinanceAmount(summary.expenseMinor)} | '
          '退款 ${formatFinanceAmount(summary.refundMinor)} | '
          '净支出 ${formatFinanceAmount(summary.netExpenseMinor)} | '
          '结余 ${formatFinanceAmount(summary.balanceMinor)} | '
          '共${summary.transactionCount}笔',
    ];

    final categoryTotals = <MapEntry<String, int>>[
      ...summary.expenseByCategory.entries,
    ]..sort((a, b) => b.value.compareTo(a.value));
    if (categoryTotals.isNotEmpty) {
      lines.add(
        '支出分类汇总: ${categoryTotals.take(12).map((entry) => '${categoryName(entry.key)} ${formatFinanceAmount(entry.value)}').join('、')}',
      );
    }
    final incomeTotals = <MapEntry<String, int>>[
      ...summary.incomeByCategory.entries,
    ]..sort((a, b) => b.value.compareTo(a.value));
    if (incomeTotals.isNotEmpty) {
      lines.add(
        '收入分类汇总: ${incomeTotals.take(12).map((entry) => '${categoryName(entry.key)} ${formatFinanceAmount(entry.value)}').join('、')}',
      );
    }

    if (budgets.isNotEmpty) {
      lines.add('预算（${financeMonthKey(range.from)}）:');
      for (final budget in budgets.take(20)) {
        final used = budget.categoryUuid == null
            ? summary.netExpenseMinor
            : summary.expenseByCategory[budget.categoryUuid] ?? 0;
        final remaining = budget.amountMinor - used;
        final scope = budget.categoryUuid == null
            ? '整体'
            : categoryName(budget.categoryUuid);
        lines.add(
          '- $scope: 额度 ${formatFinanceAmount(budget.amountMinor)} | '
          '已用 ${formatFinanceAmount(used)} | '
          '${remaining < 0 ? '超支' : '剩余'} ${formatFinanceAmount(remaining.abs())}',
        );
      }
    }

    lines.add('账单明细（每条都有真实 transactionId，只能用于用户明确的修改/删除；禁止编造ID）:');
    if (transactions.isEmpty) {
      lines.add('- 当前范围没有账单');
    } else {
      for (final transaction in transactions.take(60)) {
        final signed = transaction.type.signedPrefix +
            formatFinanceAmount(transaction.amountMinor);
        final merchant = transaction.merchant?.trim().isNotEmpty == true
            ? ' | 商家: ${transaction.merchant}'
            : '';
        final category = ' | 分类: ${categoryName(transaction.categoryUuid)}';
        final payment =
            ' | 付款方式: ${paymentName(transaction.paymentMethodUuid)}';
        final note = transaction.note?.trim().isNotEmpty == true
            ? ' | 备注: ${_shorten(transaction.note!.trim(), 100)}'
            : '';
        lines.add(
          '- [transactionId: ${transaction.uuid}] ${transaction.transactionDate} | '
          '${transaction.type.label} $signed$category$merchant$payment$note',
        );
      }
    }
    lines.add(
      '安全规则: 查询只读；update_finance/delete_finance 必须引用上面的真实 transactionId，先生成待确认操作，不得直接保存或删除。',
    );
    return lines.join('\n');
  }

  static bool _containsAny(String text, List<String> words) =>
      words.any(text.contains);

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _mondayOf(DateTime value) {
    final day = _day(value);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static String _shorten(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 1)}…';
  }
}
