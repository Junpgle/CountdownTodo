part of '../time_log_screen.dart';

// ══════════════════════════════════════════════════════════
// 标签详情面板相关 (模型、图表容器、图表画笔)
// ══════════════════════════════════════════════════════════

class _TagRecord {
  final bool isPomodoro;
  final String title, id, timeRangeLabel;
  final int startTime, endTime, durationMin;
  final bool isCompleted;
  const _TagRecord({
    required this.isPomodoro,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.durationMin,
    required this.id,
    required this.timeRangeLabel,
    this.isCompleted = false,
  });
}

String _tagMonthDay(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

String _tagClockTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _tagDateTimeRange(DateTime start, DateTime end) =>
    '${_tagMonthDay(start)} ${_tagClockTime(start)} → ${_tagClockTime(end)}';

String _tagChartMonth(DateTime date) =>
    '${(date.year % 100).toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

class _TagDetailSheet extends StatefulWidget {
  final PomodoroTag tag;
  final List<TimeLogItem> logs;
  final List<PomodoroRecord> pomodoros;
  final void Function(String) onDelete;
  const _TagDetailSheet({
    required this.tag,
    required this.logs,
    this.pomodoros = const [],
    required this.onDelete,
  });

  @override
  State<_TagDetailSheet> createState() => _TagDetailSheetState();
}

enum _ChartScale { session, day, week, month }

class _TagDetailSheetState extends State<_TagDetailSheet> {
  int _chartType = 0; // 0: 时长, 1: 开始时间, 2: 结束时间
  _ChartScale _scale = _ChartScale.session;
  List<_TagRecord> _allRecs = const [];
  List<_TagRecord> _recentRecs = const [];
  List<int> _chartData = const [];
  List<String> _xLabels = const [];
  String Function(int) _formatLabel = _formatChartDuration;
  int _totalMin = 0;
  int _avgMin = 0;
  int _maxMin = 0;
  late Color _tagColor;

  @override
  void initState() {
    super.initState();
    _tagColor = hexColor(widget.tag.color);
    _rebuildRecordCache();
    _rebuildChartCache();
  }

  @override
  void didUpdateWidget(covariant _TagDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tagChanged =
        oldWidget.tag.uuid != widget.tag.uuid ||
        oldWidget.tag.name != widget.tag.name ||
        oldWidget.tag.color != widget.tag.color;
    if (tagChanged ||
        !identical(oldWidget.logs, widget.logs) ||
        !identical(oldWidget.pomodoros, widget.pomodoros)) {
      _tagColor = hexColor(widget.tag.color);
      _rebuildRecordCache();
      _rebuildChartCache();
    }
  }

  void _rebuildRecordCache() {
    final records = <_TagRecord>[];
    for (final log in widget.logs) {
      if (!log.tagUuids.contains(widget.tag.uuid)) continue;
      final start = DateTime.fromMillisecondsSinceEpoch(log.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(log.endTime);
      records.add(
        _TagRecord(
          isPomodoro: false,
          title: log.title.isNotEmpty ? log.title : widget.tag.name,
          startTime: log.startTime,
          endTime: log.endTime,
          durationMin: (log.endTime - log.startTime) ~/ 60000,
          id: log.id,
          timeRangeLabel: _tagDateTimeRange(start, end),
        ),
      );
    }
    for (final pomodoro in widget.pomodoros) {
      if (!pomodoro.tagUuids.contains(widget.tag.uuid)) continue;
      final endTime =
          pomodoro.endTime ??
          (pomodoro.startTime + pomodoro.effectiveDuration * 1000);
      final start = DateTime.fromMillisecondsSinceEpoch(pomodoro.startTime);
      final end = DateTime.fromMillisecondsSinceEpoch(endTime);
      records.add(
        _TagRecord(
          isPomodoro: true,
          title: (pomodoro.todoTitle?.isNotEmpty ?? false)
              ? pomodoro.todoTitle!
              : widget.tag.name,
          startTime: pomodoro.startTime,
          endTime: endTime,
          durationMin: pomodoro.effectiveDuration ~/ 60,
          id: pomodoro.uuid,
          timeRangeLabel: _tagDateTimeRange(start, end),
          isCompleted: pomodoro.isCompleted,
        ),
      );
    }
    records.sort((a, b) => a.startTime.compareTo(b.startTime));
    _allRecs = List<_TagRecord>.unmodifiable(records);
    _recentRecs = List<_TagRecord>.unmodifiable(records.reversed);

    var total = 0;
    var longest = records.isEmpty ? 0 : records.first.durationMin;
    for (final record in records) {
      total += record.durationMin;
      if (record.durationMin > longest) longest = record.durationMin;
    }
    _totalMin = total;
    _avgMin = records.isEmpty ? 0 : total ~/ records.length;
    _maxMin = longest;
  }

  void _rebuildChartCache() {
    if (_scale == _ChartScale.session) {
      final firstIndex = max(0, _allRecs.length - 30);
      final chartRecords = _allRecs.skip(firstIndex);
      if (_chartType == 0) {
        _chartData = List<int>.unmodifiable(
          chartRecords.map((record) => record.durationMin),
        );
        _formatLabel = _formatChartDuration;
      } else {
        _chartData = List<int>.unmodifiable(
          chartRecords.map((record) {
            final timestamp = _chartType == 1
                ? record.startTime
                : record.endTime;
            final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
            return date.hour * 60 + date.minute;
          }),
        );
        _formatLabel = _formatChartClockTime;
      }
      _xLabels = List<String>.unmodifiable(
        chartRecords.map(
          (record) => _tagMonthDay(
            DateTime.fromMillisecondsSinceEpoch(record.startTime),
          ),
        ),
      );
      return;
    }

    // Numeric keys preserve chronological ordering without allocating and
    // formatting a date string for every record on each chart interaction.
    final grouped = <int, int>{};
    for (final record in _allRecs) {
      final date = DateTime.fromMillisecondsSinceEpoch(record.startTime);
      final key = switch (_scale) {
        _ChartScale.day => DateTime(
          date.year,
          date.month,
          date.day,
        ).millisecondsSinceEpoch,
        _ChartScale.week => DateTime(
          date.year,
          date.month,
          date.day - date.weekday + 1,
        ).millisecondsSinceEpoch,
        _ChartScale.month => date.year * 12 + date.month - 1,
        _ChartScale.session => throw StateError('session chart handled above'),
      };
      grouped.update(
        key,
        (value) => value + record.durationMin,
        ifAbsent: () => record.durationMin,
      );
    }
    final keys = grouped.keys.toList()..sort();
    if (keys.length > 20) keys.removeRange(0, keys.length - 20);
    _chartData = List<int>.unmodifiable(keys.map((key) => grouped[key]!));
    _xLabels = List<String>.unmodifiable(
      keys.map((key) {
        if (_scale == _ChartScale.month) {
          return _tagChartMonth(DateTime(key ~/ 12, key % 12 + 1));
        }
        final date = DateTime.fromMillisecondsSinceEpoch(key);
        final label = _tagMonthDay(date);
        return _scale == _ChartScale.week ? 'W$label' : label;
      }),
    );
    _formatLabel = _formatChartDuration;
  }

  void _selectChartType(int index) {
    if (_chartType == index) return;
    setState(() {
      _chartType = index;
      _rebuildChartCache();
    });
  }

  void _selectChartScale(_ChartScale scale) {
    if (_scale == scale) return;
    setState(() {
      _scale = scale;
      if (scale != _ChartScale.session) _chartType = 0;
      _rebuildChartCache();
    });
  }

  static String _formatChartDuration(int value) => '${value}m';

  static String _formatChartClockTime(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

  Widget _buildChartTab(String title, int index, Color color) {
    final isSel = _chartType == index;
    return GestureDetector(
      onTap: () => _selectChartType(index),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: isSel ? color : _TC.textSub(context),
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildScaleTab(String title, _ChartScale scale, Color color) {
    final isSel = _scale == scale;
    return GestureDetector(
      onTap: () => _selectChartScale(scale),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? color : _TC.inputFill(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSel ? color : _TC.divider(context),
            width: 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 10,
            color: isSel ? Colors.white : _TC.textSub(context),
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _tagColor;

    return OptionalLiquidGlassSheet(
      topRadius: 24,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      fallbackDecoration: BoxDecoration(
        color: _TC.card(context),
        border: Border(
          top: BorderSide(color: c.withValues(alpha: 0.35), width: 1.5),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c, blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.tag.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _TC.text(context),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  border: Border.all(color: c.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(_totalMin / 60).toStringAsFixed(1)}h 累计',
                  style: TextStyle(
                    fontSize: 11,
                    color: c,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: _TC.textHint(context), size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatCard(label: '记录次数', value: '${_allRecs.length}次', color: c),
              const SizedBox(width: 10),
              _StatCard(label: '平均时长', value: '${_avgMin}min', color: c),
              const SizedBox(width: 10),
              _StatCard(label: '最长一次', value: '${_maxMin}min', color: c),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'DIMENSIONS',
                style: TextStyle(
                  fontSize: 9,
                  color: _TC.textHint(context),
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _buildScaleTab('按次', _ChartScale.session, c),
              _buildScaleTab('日', _ChartScale.day, c),
              _buildScaleTab('周', _ChartScale.week, c),
              _buildScaleTab('月', _ChartScale.month, c),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'TRENDS',
                style: TextStyle(
                  fontSize: 9,
                  color: _TC.textHint(context),
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _buildChartTab('时长', 0, c),
              if (_scale == _ChartScale.session) ...[
                _buildChartTab('开始', 1, c),
                _buildChartTab('结束', 2, c),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (_chartData.length >= 2)
            RepaintBoundary(
              child: _MiniLineChart(
                data: _chartData,
                xLabels: _xLabels,
                color: c,
                height: 130,
                formatLabel: _formatLabel,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '数据采集中...',
                  style: TextStyle(fontSize: 11, color: _TC.textHint(context)),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'RECENT RECORDS',
            style: TextStyle(
              fontSize: 9,
              color: _TC.textHint(context),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              findItemIndexCallback: (Key key) {
                if (key is ValueKey<String>) {
                  final id = key.value;
                  final idx = _recentRecs.indexWhere((r) => r.id == id);
                  return idx != -1 ? idx : null;
                }
                return null;
              },
              itemCount: _recentRecs.length,
              primary: false,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final r = _recentRecs[i];
                final colorScheme = Theme.of(ctx).colorScheme;
                return RepaintBoundary(
                  key: ValueKey<String>(r.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _TC.inputFill(ctx),
                      border: Border(
                        left: BorderSide(
                          color: r.isPomodoro ? colorScheme.cdtFocus : c,
                          width: 3,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        if (r.isPomodoro) ...[
                          Icon(
                            Icons.timer_outlined,
                            size: 12,
                            color: colorScheme.cdtFocus.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _TC.text(ctx),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                r.timeRangeLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _TC.textHint(ctx),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${r.durationMin}min',
                          style: TextStyle(
                            fontSize: 13,
                            color: r.isPomodoro ? colorScheme.cdtFocus : c,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!r.isPomodoro)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: colorScheme.error.withValues(alpha: 0.55),
                              size: 18,
                            ),
                            onPressed: () => widget.onDelete(r.id),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        else
                          const SizedBox(width: 40),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
        ],
      ),
    );
  }
}
