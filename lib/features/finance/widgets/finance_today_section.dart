import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/optional_liquid_glass_surface.dart';
import '../models/finance_models.dart';
import '../services/finance_repository.dart';
import '../services/finance_storage.dart';

/// 首页专注 Tab 使用的紧凑记账概览。
///
/// 这里只展示本月摘要和最近一笔记录，完整账单、预算和自动化仍由
/// 记账页负责，避免首页卡片承担过多操作。
class FinanceTodaySection extends StatefulWidget {
  final String username;
  final bool isLight;
  final VoidCallback? onTap;
  final DateTime Function() clock;

  const FinanceTodaySection({
    super.key,
    required this.username,
    this.isLight = false,
    this.onTap,
    this.clock = DateTime.now,
  });

  @override
  State<FinanceTodaySection> createState() => _FinanceTodaySectionState();
}

class _FinanceTodaySectionState extends State<FinanceTodaySection> {
  FinanceSummary _summary = const FinanceSummary();
  FinanceTransaction? _latestTransaction;
  FinanceTransaction? _upcomingTransaction;
  bool _isLoading = true;
  bool _hasError = false;
  int _loadGeneration = 0;
  Timer? _upcomingTransactionTimer;

  @override
  void initState() {
    super.initState();
    FinanceStorage.revision.addListener(_onFinanceChanged);
    _loadData();
  }

  @override
  void didUpdateWidget(FinanceTodaySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) _loadData();
  }

  @override
  void dispose() {
    FinanceStorage.revision.removeListener(_onFinanceChanged);
    _upcomingTransactionTimer?.cancel();
    super.dispose();
  }

  void _onFinanceChanged() {
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    _upcomingTransactionTimer?.cancel();
    _upcomingTransactionTimer = null;
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final now = widget.clock();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    try {
      final transactions = await FinanceRepository.getTransactions(
        from: monthStart,
        to: nextMonth,
      );
      if (!mounted || generation != _loadGeneration) return;
      final asOfAt = widget.clock().millisecondsSinceEpoch;
      final occurredTransactions = transactions
          .where((transaction) => transaction.balanceEventAt() <= asOfAt)
          .toList(growable: false);
      final upcomingTransaction = transactions
          .where((transaction) => transaction.balanceEventAt() > asOfAt)
          .fold<FinanceTransaction?>(null, (upcoming, transaction) {
            if (upcoming == null) return transaction;
            final upcomingEventAt = upcoming.balanceEventAt();
            final transactionEventAt = transaction.balanceEventAt();
            if (transactionEventAt != upcomingEventAt) {
              return transactionEventAt < upcomingEventAt
                  ? transaction
                  : upcoming;
            }
            return transaction.updatedAt > upcoming.updatedAt
                ? transaction
                : upcoming;
          });
      final latestTransaction = occurredTransactions
          .fold<FinanceTransaction?>(null, (latest, transaction) {
        if (latest == null) return transaction;
        final latestEventAt = latest.balanceEventAt();
        final transactionEventAt = transaction.balanceEventAt();
        if (transactionEventAt != latestEventAt) {
          return transactionEventAt > latestEventAt ? transaction : latest;
        }
        return transaction.updatedAt > latest.updatedAt ? transaction : latest;
      });
      setState(() {
        _summary = FinanceSummary.fromTransactions(
          transactions,
          asOfAt: asOfAt,
        );
        _latestTransaction = latestTransaction;
        _upcomingTransaction = upcomingTransaction;
        _isLoading = false;
        _hasError = false;
      });
      _scheduleUpcomingTransactionRefresh(transactions, asOfAt);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _scheduleUpcomingTransactionRefresh(
    Iterable<FinanceTransaction> transactions,
    int asOfAt,
  ) {
    _upcomingTransactionTimer?.cancel();
    _upcomingTransactionTimer = null;
    final now = DateTime.fromMillisecondsSinceEpoch(asOfAt);
    int? nextEventAt =
        DateTime(now.year, now.month + 1).millisecondsSinceEpoch;
    for (final transaction in transactions) {
      final eventAt = transaction.balanceEventAt();
      if (eventAt > asOfAt &&
          (nextEventAt == null || eventAt < nextEventAt)) {
        nextEventAt = eventAt;
      }
    }
    if (nextEventAt == null) return;
    final delayMs = (nextEventAt - asOfAt + 1)
        .clamp(1, const Duration(days: 24).inMilliseconds)
        .toInt();
    _upcomingTransactionTimer = Timer(
      Duration(milliseconds: delayMs),
      _loadData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = widget.isLight ? Colors.white : colorScheme.onSurface;
    final subColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.72)
        : colorScheme.onSurfaceVariant;
    final iconColor = widget.isLight ? Colors.white : colorScheme.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.isLight
                        ? Colors.white.withValues(alpha: 0.15)
                        : colorScheme.tertiary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 20,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '本月记账',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                if (!_isLoading && !_hasError)
                  Text(
                    '${_summary.transactionCount} 笔',
                    style: TextStyle(
                      fontSize: 12,
                      color: subColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (widget.onTap != null) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, size: 20, color: subColor),
                ],
              ],
            ),
          ),
        ),
        Semantics(
          button: widget.onTap != null,
          label: '本月记账概览',
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: OptionalLiquidGlassCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              borderRadius: 24,
              highContrast: true,
              tint: (widget.isLight ? colorScheme.scrim : colorScheme.tertiary)
                  .withValues(alpha: 0.16),
              isDark:
                  widget.isLight || colorScheme.brightness == Brightness.dark,
              fallbackDecoration: BoxDecoration(
                color: widget.isLight
                    ? Colors.white.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: widget.isLight
                      ? Colors.white.withValues(alpha: 0.2)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 78,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: widget.isLight
                              ? Colors.white
                              : colorScheme.tertiary,
                        ),
                      ),
                    )
                  : _hasError
                      ? _buildError(subColor)
                      : _buildSummary(colorScheme, subColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(ColorScheme colorScheme, Color subColor) {
    final dividerColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.22)
        : colorScheme.outlineVariant.withValues(alpha: 0.35);
    final valueColor = widget.isLight ? Colors.white : colorScheme.onSurface;

    return Column(
      children: [
        Row(
          children: [
            _buildMetric(
              label: '净支出',
              value: formatFinanceAmount(_summary.netExpenseMinor),
              valueColor: widget.isLight ? Colors.white : colorScheme.error,
              labelColor: subColor,
            ),
            _buildMetricDivider(dividerColor),
            _buildMetric(
              label: '收入',
              value: formatFinanceAmount(_summary.incomeMinor),
              valueColor: widget.isLight ? Colors.white : colorScheme.primary,
              labelColor: subColor,
            ),
            _buildMetricDivider(dividerColor),
            _buildMetric(
              label: '本月结余',
              value: formatFinanceAmount(_summary.balanceMinor),
              valueColor: valueColor,
              labelColor: subColor,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(height: 1, thickness: 0.8, color: dividerColor),
        const SizedBox(height: 10),
        if (_latestTransaction != null)
          _buildLatestTransaction(
            _latestTransaction!,
            colorScheme,
            subColor,
            eventLabel: '最近一笔',
          )
        else if (_upcomingTransaction != null)
          _buildLatestTransaction(
            _upcomingTransaction!,
            colorScheme,
            subColor,
            eventLabel: '下一笔待发生',
          )
        else
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 18, color: subColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '本月还没有账单，点击开始记录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: subColor),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required Color valueColor,
    required Color labelColor,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              color: valueColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricDivider(Color color) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: color,
    );
  }

  Widget _buildLatestTransaction(
    FinanceTransaction transaction,
    ColorScheme colorScheme,
    Color subColor, {
    required String eventLabel,
  }) {
    final title = transaction.merchant?.trim().isNotEmpty == true
        ? transaction.merchant!.trim()
        : transaction.type.label;
    final amountColor = widget.isLight
        ? Colors.white
        : transaction.type == FinanceTransactionType.expense
            ? colorScheme.error
            : colorScheme.primary;

    return Row(
      children: [
        Icon(Icons.receipt_long_outlined, size: 18, color: subColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: widget.isLight ? Colors.white : colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$eventLabel · ${transaction.transactionDate}'
                '${transaction.installmentLabel == null ? '' : ' · 分期 ${transaction.installmentLabel}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: subColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatSignedFinanceAmount(transaction.amountMinor, transaction.type),
          style: TextStyle(
            color: amountColor,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildError(Color subColor) {
    return SizedBox(
      height: 78,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 20, color: subColor),
          const SizedBox(width: 8),
          Text(
            '暂时无法读取本月账单',
            style: TextStyle(color: subColor),
          ),
        ],
      ),
    );
  }
}
