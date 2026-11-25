part of '../habit_calendar_tab.dart';

extension _HabitCalendarShared on _HabitCalendarTabState {
  Widget _buildResponsiveCalendarView({
    required bool isWide,
    required double bottomPadding,
    required List<Widget> calendarChildren,
    required Widget detailSection,
    required double narrowDetailSpacing,
  }) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: RefreshIndicator(
              edgeOffset: widget.topPadding,
              onRefresh: _loadData,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.topPadding + 12,
                  16,
                  bottomPadding,
                ),
                children: calendarChildren,
              ),
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: 0.35),
          ),
          Expanded(
            flex: 4,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                widget.topPadding + 12,
                16,
                bottomPadding,
              ),
              children: [detailSection],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      edgeOffset: widget.topPadding,
      onRefresh: _loadData,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          widget.topPadding + 12,
          16,
          bottomPadding,
        ),
        children: [
          ...calendarChildren,
          SizedBox(height: narrowDetailSpacing),
          detailSection,
        ],
      ),
    );
  }

  Widget _buildMonthDayGrid({
    required Widget Function(
      DateTime date,
      int day,
      bool isToday,
      bool isSelected,
      bool isFuture,
    )
    cellBuilder,
  }) {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1;

    final cells = <Widget>[];
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isToday =
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isSelected =
          date.year == _selectedDay.year &&
          date.month == _selectedDay.month &&
          date.day == _selectedDay.day;
      final isFuture = date.isAfter(today);
      cells.add(cellBuilder(date, day, isToday, isSelected, isFuture));
    }

    return GridView.count(
      padding: EdgeInsets.zero,
      primary: false,
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.84,
      children: cells,
    );
  }

  Widget _buildCalendarDayCellShell({
    required Key key,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color borderColor,
    required double borderWidth,
    Widget? backgroundOverlay,
    required List<Widget> contentChildren,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Container(color: backgroundColor),
              ?backgroundOverlay,
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: contentChildren,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(
    ColorScheme colorScheme,
    Color color,
    String label, {
    Widget? icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          icon
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  String _formatSelectedDayLabel(DateTime day) {
    return '${day.month} 月 ${day.day} 日'
        ' · 周${'一二三四五六日'[day.weekday - 1]}';
  }

  Widget _buildEmptyDayDetailCard(ColorScheme colorScheme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
