part of '../finance_widgets.dart';

class _FinanceLedgerTotals {
  final int expenseMinor;
  final int refundMinor;
  final int incomeMinor;
  final int plannedExpenseMinor;
  final int plannedRefundMinor;
  final int plannedIncomeMinor;

  const _FinanceLedgerTotals({
    required this.expenseMinor,
    required this.refundMinor,
    required this.incomeMinor,
    required this.plannedExpenseMinor,
    required this.plannedRefundMinor,
    required this.plannedIncomeMinor,
  });

  int get netExpenseMinor => expenseMinor - refundMinor;

  factory _FinanceLedgerTotals.fromEntries(
    Iterable<_FinanceLedgerOrderEntry> entries,
    int nowAt,
  ) {
    var expenseMinor = 0;
    var refundMinor = 0;
    var incomeMinor = 0;
    var plannedExpenseMinor = 0;
    var plannedRefundMinor = 0;
    var plannedIncomeMinor = 0;
    for (final entry in entries) {
      final isPlanned = entry.eventAt > nowAt;
      final transaction = entry.transaction;
      switch (transaction.type) {
        case FinanceTransactionType.expense:
          if (isPlanned) {
            plannedExpenseMinor += transaction.amountMinor;
          } else {
            expenseMinor += transaction.amountMinor;
          }
        case FinanceTransactionType.refund:
          if (isPlanned) {
            plannedRefundMinor += transaction.amountMinor;
          } else {
            refundMinor += transaction.amountMinor;
          }
        case FinanceTransactionType.income:
          if (isPlanned) {
            plannedIncomeMinor += transaction.amountMinor;
          } else {
            incomeMinor += transaction.amountMinor;
          }
        case FinanceTransactionType.transfer:
          break;
      }
    }
    return _FinanceLedgerTotals(
      expenseMinor: expenseMinor,
      refundMinor: refundMinor,
      incomeMinor: incomeMinor,
      plannedExpenseMinor: plannedExpenseMinor,
      plannedRefundMinor: plannedRefundMinor,
      plannedIncomeMinor: plannedIncomeMinor,
    );
  }
}

class _FinanceDateRange {
  final DateTime from;
  final DateTime to;

  const _FinanceDateRange(this.from, this.to);
}

class _FinanceOverviewPeriod {
  final DateTime from;
  final DateTime to;
  final String title;
  final String shortTitle;
  final FinanceSummary summary;
  final List<FinanceTransaction> transactions;
  final bool isPlanned;

  const _FinanceOverviewPeriod({
    required this.from,
    required this.to,
    required this.title,
    required this.shortTitle,
    required this.summary,
    required this.transactions,
    required this.isPlanned,
  });
}

class _FinanceOverviewAnalytics {
  final List<_FinanceCategoryTotal> topExpenseCategories;
  final List<_FinanceCategoryTotal> categoryExpenseShares;
  final int outflowTransactionCount;
  final List<int>? hourlyNetExpenseMinor;
  final FinanceTransaction? maxExpenseTransaction;
  final int? previousPeriodNetExpenseMinor;
  final Map<String?, int> paymentMethodExpenseTotals;

  const _FinanceOverviewAnalytics({
    required this.topExpenseCategories,
    required this.categoryExpenseShares,
    required this.outflowTransactionCount,
    required this.hourlyNetExpenseMinor,
    this.maxExpenseTransaction,
    this.previousPeriodNetExpenseMinor,
    this.paymentMethodExpenseTotals = const {},
  });

  bool get hasOutflowTransactions => outflowTransactionCount > 0;
}

class _FinanceCategoryTotal {
  final String? categoryUuid;
  final int value;

  const _FinanceCategoryTotal({
    required this.categoryUuid,
    required this.value,
  });
}

class _PaymentMethodSpendingItem {
  final FinancePaymentMethod? paymentMethod;
  final String name;
  final String icon;
  final int amountMinor;

  const _PaymentMethodSpendingItem({
    this.paymentMethod,
    required this.name,
    required this.icon,
    required this.amountMinor,
  });
}

class _UpcomingCommitmentItem {
  final FinanceRecurringRule rule;
  final DateTime dueDate;

  const _UpcomingCommitmentItem({required this.rule, required this.dueDate});
}

const List<double> financeCuratedHues = [
  205.0, // 晨空蓝
  155.0, // 翡翠青
  38.0, // 暖琥珀
  342.0, // 柔珊瑚
  268.0, // 罗兰紫
  182.0, // 薄荷绿
  18.0, // 陶土暖橘
  295.0, // 丁香紫
  85.0, // 橄榄暖绿
  232.0, // 暮海靛
];

Color financeCategoryColor({
  required ColorScheme colorScheme,
  int? customColorValue,
  required int index,
}) {
  if (customColorValue != null) return Color(customColorValue);
  final isDark = colorScheme.brightness == Brightness.dark;
  final baseHue =
      (financeCuratedHues[index % financeCuratedHues.length] +
          (index ~/ financeCuratedHues.length) * 19.0) %
      360.0;
  return HSLColor.fromAHSL(
    1.0,
    baseHue,
    isDark ? 0.62 : 0.52,
    isDark ? 0.68 : 0.50,
  ).toColor();
}

class FinanceDonutSlice {
  final String? categoryUuid;
  final int value;
  final Color color;
  final String label;
  final String? icon;

  const FinanceDonutSlice({
    required this.categoryUuid,
    required this.value,
    required this.color,
    required this.label,
    this.icon,
  });
}

class _FinanceCumulativeBalanceTrendPainter extends CustomPainter {
  final List<FinanceCumulativeBalancePoint> points;
  final int selectedIndex;
  final ColorScheme colorScheme;

  static final Paint _gridPaint = Paint()..strokeWidth = 1;
  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _linePaint = Paint()
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  static final Paint _pointSurfacePaint = Paint()..style = PaintingStyle.fill;
  static final Paint _pointPrimaryPaint = Paint()..style = PaintingStyle.fill;
  static final Path _fillPath = Path();
  static final Path _linePath = Path();

  const _FinanceCumulativeBalanceTrendPainter({
    required this.points,
    required this.selectedIndex,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    const leftInset = 18.0;
    const rightInset = 18.0;
    const topInset = 10.0;
    const bottomInset = 28.0;
    final plot = Rect.fromLTRB(
      leftInset,
      topInset,
      size.width - rightInset,
      size.height - bottomInset,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    var minimum = points.first.balanceMinor;
    var maximum = minimum;
    for (final point in points.skip(1)) {
      minimum = math.min(minimum, point.balanceMinor);
      maximum = math.max(maximum, point.balanceMinor);
    }
    minimum = math.min(minimum, 0);
    maximum = math.max(maximum, 0);

    double xFor(int index) => points.length == 1
        ? plot.center.dx
        : plot.left + plot.width * index / (points.length - 1);

    double yFor(int value) {
      if (minimum == maximum) return plot.center.dy;
      return plot.top + (maximum - value) / (maximum - minimum) * plot.height;
    }

    _gridPaint.color = colorScheme.outlineVariant.withValues(alpha: 0.45);
    canvas.drawLine(plot.topLeft, plot.topRight, _gridPaint);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, _gridPaint);
    if (minimum <= 0 && maximum >= 0) {
      final zeroY = yFor(0);
      canvas.drawLine(
        Offset(plot.left, zeroY),
        Offset(plot.right, zeroY),
        _gridPaint,
      );
    }

    const baselineValue = 0;
    final fillPath = _fillPath;
    fillPath.reset();
    fillPath.moveTo(xFor(0), yFor(baselineValue));
    final linePath = _linePath;
    linePath.reset();
    linePath.moveTo(xFor(0), yFor(points.first.balanceMinor));
    for (var index = 1; index < points.length; index++) {
      final point = points[index];
      final x = xFor(index);
      final y = yFor(point.balanceMinor);
      linePath.lineTo(x, y);
      fillPath.lineTo(x, y);
    }
    fillPath
      ..lineTo(xFor(points.length - 1), yFor(baselineValue))
      ..close();
    _fillPaint.color = colorScheme.primary.withValues(alpha: 0.09);
    canvas.drawPath(fillPath, _fillPaint);

    _linePaint.color = colorScheme.primary;
    canvas.drawPath(linePath, _linePaint);

    _pointSurfacePaint.color = colorScheme.surface;
    _pointPrimaryPaint.color = colorScheme.primary;

    final labelPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    final labelStyle = TextStyle(
      fontSize: 10,
      color: colorScheme.onSurfaceVariant,
    );
    try {
      for (var index = 0; index < points.length; index++) {
        final center = Offset(xFor(index), yFor(points[index].balanceMinor));
        if (index == selectedIndex) {
          canvas.drawCircle(center, 6, _pointSurfacePaint);
          canvas.drawCircle(center, 5, _pointPrimaryPaint);
        } else {
          canvas.drawCircle(center, 3.25, _pointPrimaryPaint);
        }

        final showLabel =
            index.isEven ||
            index == points.length - 1 ||
            index == selectedIndex;
        if (!showLabel) continue;
        labelPainter
          ..text = TextSpan(
            text: '${points[index].month.month}月',
            style: labelStyle,
          )
          ..layout(maxWidth: 34);
        final labelX = (center.dx - labelPainter.width / 2).clamp(
          0.0,
          size.width - labelPainter.width,
        );
        labelPainter.paint(
          canvas,
          Offset(labelX, size.height - labelPainter.height),
        );
      }
    } finally {
      labelPainter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _FinanceCumulativeBalanceTrendPainter old) =>
      old.points != points ||
      old.selectedIndex != selectedIndex ||
      old.colorScheme.primary != colorScheme.primary ||
      old.colorScheme.surface != colorScheme.surface ||
      old.colorScheme.outlineVariant != colorScheme.outlineVariant ||
      old.colorScheme.onSurfaceVariant != colorScheme.onSurfaceVariant;
}

class FinanceDonutPainter extends CustomPainter {
  final List<FinanceDonutSlice> slices;
  final int total;
  final String? selectedCategoryUuid;
  final double sweepProgress;
  final Animation<double>? sweepAnimation;
  final Color emptyColor;
  final bool isDark;

  static final Paint _emptyPaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  static final Paint _slicePaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  const FinanceDonutPainter({
    required this.slices,
    required this.total,
    required this.selectedCategoryUuid,
    required this.sweepProgress,
    this.sweepAnimation,
    required this.emptyColor,
    required this.isDark,
  }) : super(repaint: sweepAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final isLarge = size.width >= 160.0;
    final baseRadius = size.width / 2 - (isLarge ? 18.0 : 14.0);
    final normalStrokeWidth = isLarge ? 20.0 : 15.0;
    final selectedStrokeWidth = isLarge ? 26.0 : 20.0;

    if (total <= 0 || slices.isEmpty) {
      _emptyPaint
        ..strokeWidth = normalStrokeWidth
        ..color = emptyColor.withValues(alpha: isDark ? 0.25 : 0.16);
      canvas.drawCircle(center, baseRadius, _emptyPaint);
      return;
    }

    final effectiveSweepProgress = sweepAnimation?.value ?? sweepProgress;
    final maxSweepAngle = 2 * math.pi * effectiveSweepProgress.clamp(0.0, 1.0);
    var currentAngle = -math.pi / 2;

    if (slices.length == 1) {
      final slice = slices.first;
      final isSelected =
          selectedCategoryUuid != null &&
          selectedCategoryUuid == slice.categoryUuid;
      _slicePaint
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = isSelected ? selectedStrokeWidth : normalStrokeWidth
        ..color = slice.color;
      final rect = Rect.fromCircle(
        center: center,
        radius: isSelected ? baseRadius + 3.0 : baseRadius,
      );
      canvas.drawArc(rect, currentAngle, maxSweepAngle, false, _slicePaint);
      return;
    }

    _slicePaint.strokeCap = StrokeCap.round;
    for (final slice in slices) {
      if (currentAngle >= -math.pi / 2 + maxSweepAngle) break;

      final sliceFullSweep = 2 * math.pi * (slice.value / total);
      final isSelected =
          selectedCategoryUuid != null &&
          selectedCategoryUuid == slice.categoryUuid;

      final effectiveGap = math.min(0.045, sliceFullSweep * 0.35);
      final rawVisibleSweep = math.max(0.015, sliceFullSweep - effectiveGap);

      final sweepRemaining =
          (-math.pi / 2 + maxSweepAngle) - (currentAngle + effectiveGap / 2);
      if (sweepRemaining <= 0) {
        currentAngle += sliceFullSweep;
        continue;
      }
      final sweepToDraw = math.min(rawVisibleSweep, sweepRemaining);

      final hasSelection = selectedCategoryUuid != null;
      final Color sliceColor;
      if (hasSelection) {
        sliceColor = isSelected
            ? slice.color
            : slice.color.withValues(alpha: isDark ? 0.28 : 0.20);
      } else {
        sliceColor = slice.color;
      }

      final radius = isSelected
          ? (isLarge ? baseRadius + 4.5 : baseRadius + 3.0)
          : baseRadius;
      final strokeWidth = isSelected ? selectedStrokeWidth : normalStrokeWidth;

      _slicePaint
        ..strokeWidth = strokeWidth
        ..color = sliceColor;

      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        currentAngle + effectiveGap / 2,
        sweepToDraw,
        false,
        _slicePaint,
      );

      currentAngle += sliceFullSweep;
    }
  }

  @override
  bool shouldRepaint(covariant FinanceDonutPainter oldDelegate) {
    if (oldDelegate.total != total ||
        oldDelegate.selectedCategoryUuid != selectedCategoryUuid ||
        oldDelegate.sweepProgress != sweepProgress ||
        oldDelegate.sweepAnimation != sweepAnimation ||
        oldDelegate.isDark != isDark ||
        oldDelegate.emptyColor != emptyColor ||
        oldDelegate.slices.length != slices.length) {
      return true;
    }
    for (var i = 0; i < slices.length; i++) {
      if (oldDelegate.slices[i].value != slices[i].value ||
          oldDelegate.slices[i].color != slices[i].color ||
          oldDelegate.slices[i].categoryUuid != slices[i].categoryUuid) {
        return true;
      }
    }
    return false;
  }
}

String _formatFinanceDateRange(DateTime from, DateTime to) {
  final lastDay = financeCalendarDayOffset(to, -1);
  if (from.year == lastDay.year && from.month == lastDay.month) {
    return '${from.month}月${from.day}日 - ${lastDay.day}日';
  }
  if (from.year == lastDay.year) {
    return '${from.month}月${from.day}日 - '
        '${lastDay.month}月${lastDay.day}日';
  }
  return '${dateKey(from)} - ${dateKey(lastDay)}';
}

class _FinanceDayGroup {
  final String date;
  final List<FinanceTransaction> transactions;
  final int expenseMinor;
  final int refundMinor;
  final int incomeMinor;
  final int plannedExpenseMinor;
  final int plannedRefundMinor;
  final int plannedIncomeMinor;

  const _FinanceDayGroup({
    required this.date,
    required this.transactions,
    required this.expenseMinor,
    required this.refundMinor,
    required this.incomeMinor,
    required this.plannedExpenseMinor,
    required this.plannedRefundMinor,
    required this.plannedIncomeMinor,
  });

  int get netExpenseMinor => expenseMinor - refundMinor;
  int get plannedNetExpenseMinor => plannedExpenseMinor - plannedRefundMinor;
}

class _FinanceLedgerRow {
  final _FinanceDayGroup? group;
  final FinanceTransaction? transaction;
  final bool isSpacer;

  const _FinanceLedgerRow.header(this.group)
    : transaction = null,
      isSpacer = false;

  const _FinanceLedgerRow.transaction(this.transaction)
    : group = null,
      isSpacer = false;

  const _FinanceLedgerRow.spacer()
    : group = null,
      transaction = null,
      isSpacer = true;
}

List<_FinanceDayGroup> _groupFinanceTransactionsByDay(
  Iterable<_FinanceLedgerOrderEntry> entries, {
  required int asOfAt,
}) {
  final grouped = <String, List<FinanceTransaction>>{};
  final totalsByDate = <String, List<int>>{};
  for (final entry in entries) {
    final transaction = entry.transaction;
    final date = transaction.transactionDate;
    final eventAt = entry.eventAt;
    grouped.putIfAbsent(date, () => []).add(transaction);

    final totals = totalsByDate.putIfAbsent(date, () => List<int>.filled(6, 0));
    final metricOffset = eventAt > asOfAt ? 3 : 0;
    final metricIndex = switch (transaction.type) {
      FinanceTransactionType.expense => metricOffset,
      FinanceTransactionType.refund => metricOffset + 1,
      FinanceTransactionType.income => metricOffset + 2,
      FinanceTransactionType.transfer => metricOffset + 3,
    };
    totals[metricIndex] += transaction.amountMinor;
  }

  final result = <_FinanceDayGroup>[];
  for (final entry in grouped.entries) {
    final date = entry.key;
    final totals = totalsByDate[date]!;
    result.add(
      _FinanceDayGroup(
        date: date,
        transactions: entry.value,
        expenseMinor: totals[0],
        refundMinor: totals[1],
        incomeMinor: totals[2],
        plannedExpenseMinor: totals[3],
        plannedRefundMinor: totals[4],
        plannedIncomeMinor: totals[5],
      ),
    );
  }
  return result;
}

String _formatFinanceDayLabel(String value) {
  final date = dateFromKey(value);
  const weekdays = <String>['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final weekday = date.weekday >= 1 && date.weekday <= 7
      ? ' ${weekdays[date.weekday]}'
      : '';
  return '${date.month}月${date.day}日$weekday';
}

final _financeFullChineseDatePattern = RegExp(
  r'^(\d{4})年(\d{1,2})月(\d{1,2})日?$',
);
final _financeChineseYearMonthPattern = RegExp(r'^(\d{4})年(\d{1,2})月$');
final _financeChineseMonthDayPattern = RegExp(r'^(\d{1,2})月(\d{1,2})日?$');
final _financeChineseMonthPattern = RegExp(r'^(\d{1,2})月$');
final _financeSlashMonthDayPattern = RegExp(r'^(\d{1,2})/(\d{1,2})$');

bool _matchesFinanceLedgerDate(String value, String query) {
  if (value.contains(query)) return true;
  if (!isFinanceDateKey(value)) return false;
  final date = DateTime.parse(value);

  final fullChineseDate = _financeFullChineseDatePattern.firstMatch(query);
  if (fullChineseDate != null) {
    return int.parse(fullChineseDate.group(1)!) == date.year &&
        int.parse(fullChineseDate.group(2)!) == date.month &&
        int.parse(fullChineseDate.group(3)!) == date.day;
  }
  final chineseYearMonth = _financeChineseYearMonthPattern.firstMatch(query);
  if (chineseYearMonth != null) {
    return int.parse(chineseYearMonth.group(1)!) == date.year &&
        int.parse(chineseYearMonth.group(2)!) == date.month;
  }
  final chineseMonthDay = _financeChineseMonthDayPattern.firstMatch(query);
  if (chineseMonthDay != null) {
    return int.parse(chineseMonthDay.group(1)!) == date.month &&
        int.parse(chineseMonthDay.group(2)!) == date.day;
  }
  final chineseMonth = _financeChineseMonthPattern.firstMatch(query);
  if (chineseMonth != null) {
    return int.parse(chineseMonth.group(1)!) == date.month;
  }
  final slashMonthDay = _financeSlashMonthDayPattern.firstMatch(query);
  if (slashMonthDay != null) {
    return int.parse(slashMonthDay.group(1)!) == date.month &&
        int.parse(slashMonthDay.group(2)!) == date.day;
  }
  return _formatFinanceDayLabel(value).toLowerCase().contains(query);
}
