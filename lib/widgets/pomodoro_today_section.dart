import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/course_screens.dart';
import '../services/pomodoro_service.dart';
import '../utils/page_transitions.dart';
import '../utils/theme_color_tokens.dart';

// ============================================================
// 首页最近专注统计卡片
// ============================================================
class PomodoroTodaySection extends StatefulWidget {
  final String username;
  final bool isLight;

  /// 每次自增时触发重新加载（由首页 resumed 回调驱动）
  final int refreshTrigger;

  /// 点击整个卡片时的回调（跳转统计看板）
  final VoidCallback? onTap;

  const PomodoroTodaySection({
    super.key,
    required this.username,
    this.isLight = false,
    this.refreshTrigger = 0,
    this.onTap,
  });

  @override
  State<PomodoroTodaySection> createState() => _PomodoroTodaySectionState();
}

class _PomodoroTodaySectionState extends State<PomodoroTodaySection>
    with SingleTickerProviderStateMixin {
  List<PomodoroRecord> _records = [];
  bool _loading = true;
  bool _collapsed = false;
  bool _isToday = true;
  late AnimationController _chartAnimationController;

  @override
  void initState() {
    super.initState();
    _chartAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadData();
  }

  @override
  void didUpdateWidget(PomodoroTodaySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _chartAnimationController.dispose();
    super.dispose();
  }

  /// 只读本地数据（云端同步已由首页 _handleManualSync / _checkAutoSync 统一负责）
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final result = await PomodoroService.getRecentRecords();
    if (mounted) {
      setState(() {
        _records = result.records;
        _isToday = result.isToday;
        _loading = false;
      });
      _chartAnimationController.forward(from: 0.0);
    }
  }

  int get _totalSeconds => _records.fold(0, (s, r) => s + r.effectiveDuration);

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isLight ? Colors.white : null;
    final subColor = widget.isLight
        ? Colors.white.withValues(alpha: 0.7)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 标题行 ──
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
                  child: Icon(Icons.bar_chart_rounded,
                      size: 20,
                      color: widget.isLight
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  '最近专注',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: textColor),
                ),
                const SizedBox(width: 8),
                // 今日 / 昨日 标签
                if (!_loading)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.isLight
                          ? Colors.white.withValues(alpha: 0.2)
                          : Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isToday ? '今日' : '昨日',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.isLight
                            ? Colors.white
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (!_loading && _records.isNotEmpty)
                  Text(
                    PomodoroService.formatDuration(_totalSeconds),
                    style: TextStyle(
                        fontSize: 15,
                        color: widget.isLight
                            ? Colors.white.withValues(alpha: 0.9)
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800),
                  ),
                const Spacer(),
                // 跳转箭头
                if (widget.onTap != null)
                  Icon(Icons.chevron_right, size: 20, color: subColor),
                if (_records.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _collapsed = !_collapsed),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        _collapsed
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: subColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── 统计视图 ──
          if (_loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(30),
                    child: CircularProgressIndicator()))
          else if (_records.isEmpty)
            RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 24, horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.isLight
                          ? Colors.white.withValues(alpha: 0.15)
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: widget.isLight ? 0.1 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                      border: Border.all(
                          color: widget.isLight
                              ? Colors.white.withValues(alpha: 0.2)
                              : Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 32, color: subColor.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text('暂无专注记录，开始你的第一个番茄钟吧！',
                            style: TextStyle(
                                color: subColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (!_collapsed)
            Column(
              children: [
                _buildHourlyChart(subColor),
                const SizedBox(height: 12),
                _buildRecordsList(),
              ],
            ),
        ],
      ),
    );
  }

  // ==========================================
  // 24小时分布条形图
  // ==========================================
  Widget _buildHourlyChart(Color? subColor) {
    List<int> hourlySeconds = List.filled(24, 0);
    for (var r in _records) {
      final startLocal =
          DateTime.fromMillisecondsSinceEpoch(r.startTime, isUtc: true)
              .toLocal();
      hourlySeconds[startLocal.hour] += r.effectiveDuration;
    }

    final maxSeconds = hourlySeconds.reduce(max);
    final primaryColor =
        widget.isLight ? Colors.white : Theme.of(context).colorScheme.primary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: widget.isLight
                ? Colors.white.withValues(alpha: 0.15)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withValues(alpha: widget.isLight ? 0.1 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
            border: widget.isLight
                ? Border.all(color: Colors.white.withValues(alpha: 0.2))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('时段分布',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: widget.isLight
                          ? Colors.white70
                          : Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 16),
              SizedBox(
                height: 90,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(24, (index) {
                    final sec = hourlySeconds[index];
                    final factor = maxSeconds == 0 ? 0.0 : sec / maxSeconds;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: AnimatedBuilder(
                                animation: _chartAnimationController,
                                builder: (context, child) {
                                  final animatedFactor =
                                      factor * _chartAnimationController.value;
                                  return Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: animatedFactor > 0
                                          ? max(animatedFactor, 0.05)
                                          : 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: animatedFactor > 0
                                              ? LinearGradient(
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                  colors: [
                                                      primaryColor.withValues(
                                                          alpha: 0.5),
                                                      primaryColor,
                                                    ])
                                              : null,
                                          color: animatedFactor > 0
                                              ? null
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (index % 6 == 0)
                              Text(
                                '$index',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: subColor?.withValues(alpha: 0.6)),
                              )
                            else
                              const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 番茄钟记录列表
  // ==========================================
  Widget _buildRecordsList() {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isLight
                ? Colors.white.withValues(alpha: 0.15)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withValues(alpha: widget.isLight ? 0.1 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
            border: widget.isLight
                ? Border.all(color: Colors.white.withValues(alpha: 0.2))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '专注记录',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: widget.isLight
                      ? Colors.white70
                      : colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              ..._records.map((record) => _buildRecordItem(record)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordItem(PomodoroRecord record) {
    final colorScheme = Theme.of(context).colorScheme;
    final startLocal =
        DateTime.fromMillisecondsSinceEpoch(record.startTime, isUtc: true)
            .toLocal();
    final durationMin = record.effectiveDuration ~/ 60;
    final statusIcon =
        record.isCompleted ? Icons.check_circle_rounded : Icons.timer_off_rounded;
    final statusColor = record.isCompleted
        ? (widget.isLight ? Colors.greenAccent : colorScheme.cdtSuccess)
        : (widget.isLight ? Colors.amber : colorScheme.cdtWarning);
    final hasPause = (record.totalPauseSeconds ?? 0) > 0;
    final cardKey = GlobalKey();

    return Padding(
      key: ValueKey(record.uuid),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            PageTransitions.pushFromRect(
              context: context,
              page: PomodoroDetailScreen(
                record: record,
                tags: [],
              ),
              sourceKey: cardKey,
              sourceBorderRadius: const BorderRadius.all(Radius.circular(12)),
            );
          },
          child: Container(
            key: cardKey,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(statusIcon, size: 18, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${DateFormat('HH:mm').format(startLocal)} · $durationMin 分钟',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: widget.isLight
                              ? Colors.white
                              : colorScheme.onSurface,
                        ),
                      ),
                      if (record.todoTitle != null &&
                          record.todoTitle!.isNotEmpty)
                        Text(
                          record.todoTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.isLight
                                ? Colors.white70
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasPause)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (widget.isLight
                              ? Colors.orange
                              : colorScheme.cdtWarning)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '暂停 ${formatDurationChinese(record.totalPauseSeconds ?? 0)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: widget.isLight
                            ? Colors.orange
                            : colorScheme.cdtWarning,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: widget.isLight
                      ? Colors.white38
                      : colorScheme.onSurface.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
