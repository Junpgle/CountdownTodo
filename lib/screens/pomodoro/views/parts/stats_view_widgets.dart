part of '../stats_view.dart';

class ChartData {
  final String label;
  final int value;
  final bool isSelected;
  final DateTime date;
  ChartData(this.label, this.value, this.isSelected, this.date);
}

class PomodoroTrendChart extends StatelessWidget {
  final List<ChartData> data;
  final Function(DateTime) onSelect;

  const PomodoroTrendChart({
    super.key,
    required this.data,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxVal = data.fold(0, (max, d) => d.value > max ? d.value : max);
    final displayMax = maxVal == 0 ? 3600.0 : maxVal.toDouble();

    return OptionalLiquidGlassCard(
      height: 220,
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      borderRadius: 24,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final hFactor = d.value / displayMax;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(d.date),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          width: double.infinity,
                          height: hFactor * 160,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: d.isSelected
                                  ? [
                                      colorScheme.primary,
                                      colorScheme.primary.withValues(
                                        alpha: 0.7,
                                      ),
                                    ]
                                  : [
                                      colorScheme.secondary.withValues(
                                        alpha: 0.3,
                                      ),
                                      colorScheme.secondary.withValues(
                                        alpha: 0.1,
                                      ),
                                    ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: d.isSelected
                                ? [
                                    BoxShadow(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    d.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: d.isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: d.isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _MonthPickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _displayYear;

  @override
  void initState() {
    super.initState();
    _displayYear = widget.initialDate.year;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();

    final canGoPrev = _displayYear > widget.firstDate.year;
    final canGoNext = _displayYear < widget.lastDate.year;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: canGoPrev ? () => setState(() => _displayYear--) : null,
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final year = await showAppDialog<int>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  title: const Text('选择年份'),
                  content: SizedBox(
                    width: 300,
                    height: 320,
                    child: YearPicker(
                      firstDate: widget.firstDate,
                      lastDate: widget.lastDate,
                      selectedDate: DateTime(_displayYear),
                      onChanged: (d) => Navigator.pop(dialogCtx, d.year),
                    ),
                  ),
                ),
              );
              if (year != null && mounted) {
                setState(() => _displayYear = year);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_displayYear年',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoNext ? () => setState(() => _displayYear++) : null,
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        height: 240,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          findChildIndexCallback: (Key key) {
            if (key is ValueKey<int>) {
              final month = key.value;
              if (month >= 1 && month <= 12) return month - 1;
            }
            return null;
          },
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.8,
          ),
          itemCount: 12,
          itemBuilder: (context, index) {
            final month = index + 1;
            final isSelected =
                _displayYear == widget.initialDate.year &&
                month == widget.initialDate.month;
            final isCurrent = _displayYear == now.year && month == now.month;

            final monthDate = DateTime(_displayYear, month, 1);
            final isFuture = monthDate.isAfter(
              DateTime(now.year, now.month, 1),
            );

            return RepaintBoundary(
              key: ValueKey<int>(month),
              child: Material(
                color: isSelected
                    ? colorScheme.primary
                    : (isCurrent
                          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : Colors.transparent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: isCurrent && !isSelected
                      ? BorderSide(color: colorScheme.primary, width: 1.2)
                      : BorderSide(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                          width: 0.8,
                        ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: isFuture
                      ? null
                      : () {
                          Navigator.of(context)
                              .pop(DateTime(_displayYear, month, 1));
                        },
                  child: Center(
                    child: Text(
                      '$month月',
                      style: TextStyle(
                        color: isFuture
                            ? colorScheme.onSurface.withValues(alpha: 0.3)
                            : (isSelected
                                  ? colorScheme.onPrimary
                                  : (isCurrent
                                        ? colorScheme.primary
                                        : colorScheme.onSurface)),
                        fontWeight: isSelected || isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
