import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/timeline_service.dart';
import '../screens/personal_timeline_screen.dart';
import '../utils/page_transitions.dart';

class PersonalTimelineSection extends StatefulWidget {
  final String username;
  final bool isLight;
  final int refreshTrigger;

  const PersonalTimelineSection({
    super.key,
    required this.username,
    this.isLight = false,
    this.refreshTrigger = 0,
  });

  @override
  State<PersonalTimelineSection> createState() =>
      _PersonalTimelineSectionState();
}

class _PersonalTimelineSectionState extends State<PersonalTimelineSection> {
  TimelineSummary? _summary;
  bool _isLoading = true;
  final GlobalKey _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(PersonalTimelineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final summary =
        await TimelineService.instance.getTodaySummary(widget.username);
    if (mounted) {
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isLight ? Colors.white : null;
    final subColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.7)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.isLight
                      ? Colors.white.withValues(alpha: 0.15)
                      : Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.timeline_rounded,
                    size: 20,
                    color: widget.isLight
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Text(
                '个人时间轴',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: textColor),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 20, color: subColor),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          key: _cardKey,
          onTap: () => PageTransitions.pushFromRect(
            context: context,
            page: PersonalTimelineScreen(username: widget.username),
            sourceKey: _cardKey,
            sourceColor: widget.isLight
                ? Colors.white.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surface,
            sourceBorderRadius: BorderRadius.circular(24),
          ).then((_) => _loadData()),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.isLight
                  ? Colors.white.withValues(alpha: 0.1)
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: widget.isLight
                  ? []
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
              border: Border.all(
                color: widget.isLight
                    ? Colors.white12
                    : Theme.of(context).dividerColor.withValues(alpha: 0.05),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _isLoading
                  ? Center(
                      key: const ValueKey('loading'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: widget.isLight
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  : Container(
                      key: ValueKey(_summaryContentKey()),
                      child: _buildSummaryGrid(subColor, textColor),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryGrid(Color subColor, Color? textColor) {
    if (_summary == null) return const SizedBox.shrink();

    final rows = <Widget>[];

    // 1. 搜索
    if (_summary!.searchCount > 0) {
      rows.add(_buildSummaryRow(
        icon: Icons.search_rounded,
        color: Colors.teal,
        title: '搜索记录',
        content:
            '搜索了 ${_summary!.searchCount} 次${_summary!.lastSearchTime != null ? '，最近 ${DateFormat('HH:mm').format(_summary!.lastSearchTime!)}' : ''}',
        subColor: subColor,
        textColor: textColor,
      ));
    }

    // 2. 待办事项
    if (_summary!.todoCreatedCount > 0 || _summary!.todoEditedCount > 0 || _summary!.todoCompletedCount > 0) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 24, thickness: 0.5));
      final parts = <String>[];
      if (_summary!.todoCreatedCount > 0) parts.add('新增 ${_summary!.todoCreatedCount} 个');
      if (_summary!.todoEditedCount > 0) parts.add('编辑 ${_summary!.todoEditedCount} 个');
      if (_summary!.todoCompletedCount > 0) parts.add('完成 ${_summary!.todoCompletedCount} 个');
      rows.add(_buildSummaryRow(
        icon: Icons.task_alt_rounded,
        color: Colors.blue,
        title: '待办事项',
        content: parts.join('、'),
        subColor: subColor,
        textColor: textColor,
      ));
    }

    // 3. 倒计时
    if (_summary!.countdownCreatedCount > 0 || _summary!.countdownEditedCount > 0 || _summary!.countdownCompletedCount > 0) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 24, thickness: 0.5));
      final parts = <String>[];
      if (_summary!.countdownCreatedCount > 0) parts.add('新增 ${_summary!.countdownCreatedCount} 个');
      if (_summary!.countdownEditedCount > 0) parts.add('编辑 ${_summary!.countdownEditedCount} 个');
      if (_summary!.countdownCompletedCount > 0) parts.add('完成 ${_summary!.countdownCompletedCount} 个');
      rows.add(_buildSummaryRow(
        icon: Icons.timer_outlined,
        color: Colors.redAccent,
        title: '倒计时',
        content: parts.join('、'),
        subColor: subColor,
        textColor: textColor,
      ));
    }

    // 4. 今日课程
    if (_summary!.attendedCourses.isNotEmpty) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 24, thickness: 0.5));
      rows.add(_buildSummaryRow(
        icon: Icons.school_outlined,
        color: Colors.indigo,
        title: '今日课程',
        content: '已上过：${_summary!.attendedCourses.join("、")}',
        subColor: subColor,
        textColor: textColor,
      ));
    }

    // 5. 番茄专注
    if (_summary!.pomodoroCount > 0) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 24, thickness: 0.5));
      rows.add(_buildSummaryRow(
        icon: Icons.local_fire_department_rounded,
        color: Colors.orange,
        title: '番茄专注',
        content: '今日已专注 ${_summary!.pomodoroCount} 次',
        subColor: subColor,
        textColor: textColor,
      ));
    }

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(Icons.history_toggle_off_rounded,
                  size: 32, color: subColor.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text('今日暂无变动，开启高效一天吧',
                  style: TextStyle(color: subColor, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  String _summaryContentKey() {
    final summary = _summary;
    if (summary == null) return 'content-empty';
    return [
      summary.searchCount,
      summary.todoCreatedCount,
      summary.todoEditedCount,
      summary.todoCompletedCount,
      summary.countdownCreatedCount,
      summary.countdownEditedCount,
      summary.countdownCompletedCount,
      summary.pomodoroCount,
      summary.attendedCourses.join('|'),
      summary.lastSearchTime?.millisecondsSinceEpoch ?? 0,
    ].join('_');
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required Color color,
    required String title,
    required String content,
    required Color subColor,
    required Color? textColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
