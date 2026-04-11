import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models.dart';
import '../../../storage_service.dart';
import '../../../services/pomodoro_service.dart';
import '../pomodoro_utils.dart';

class PomodoroStats extends StatefulWidget {
  final String username;
  final bool isCompact;
  const PomodoroStats(
      {super.key, required this.username, this.isCompact = false});

  @override
  State<PomodoroStats> createState() => PomodoroStatsState();
}

class PomodoroStatsState extends State<PomodoroStats> {
  int _dimension = 0; // 0: Day, 1: Week, 2: Month, 3: Year
  DateTime _selected = DateTime.now();
  List<PomodoroSession> _sessions = [];
  List<PomodoroTag> _tags = [];
  List<TodoItem> _todos = [];
  bool _loading = true;
  bool _syncing = false;
  bool _showDimensionPicker = false;
  List<PomodoroSession> _chartSessions = [];

  @override
  void initState() {
    super.initState();
    _loadLocal().then((_) => _syncIfDue());
  }

  void reload() {
    _loadLocal().then((_) => _syncAndRefresh());
  }

  Future<void> _syncIfDue() async {
    final interval = await StorageService.getSyncInterval();
    if (interval == 0) return;
    final lastSync = await StorageService.getLastAutoSyncTime();
    final now = DateTime.now();
    bool due = false;
    if (lastSync == null) {
      due = true;
    } else {
      switch (interval) {
        case 1: due = true; break;
        case 2: due = now.difference(lastSync).inMinutes >= 30; break;
        case 3: due = now.difference(lastSync).inHours >= 1; break;
        case 4: due = now.difference(lastSync).inHours >= 24; break;
        default: due = false;
      }
    }
    if (due) _syncAndRefresh();
  }

  Future<void> _syncAndRefresh() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    try {
      await PomodoroService.syncTagsFromCloud();
      await PomodoroService.syncRecordsFromCloud();
    } catch (e) {
      debugPrint('[PomodoroStats] _syncAndRefresh error: $e');
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    await _loadLocal();
  }

  Future<void> _fullPull() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await PomodoroService.syncTagsFromCloud();
      await PomodoroService.syncRecordsFromCloud(fromMs: 0);
    } catch (_) {}
    await _loadLocal();
  }

  Future<void> _loadLocal() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final tags = await PomodoroService.getTags();
    final todos = await StorageService.getTodos(widget.username);
    
    // Fetch chart range data
    final chartRange = _getChartRange();
    final allSessions = await PomodoroService.getSessionsInRange(chartRange.start, chartRange.end);

    // Filter for current detail view
    final detailRange = _getRange();
    final sessions = allSessions.where((s) {
      return s.startTime >= detailRange.start.millisecondsSinceEpoch &&
             s.startTime < detailRange.end.millisecondsSinceEpoch;
    }).toList();

    if (!mounted) return;
    setState(() {
      _tags = tags;
      _todos = todos.where((t) => !t.isDeleted).toList();
      _chartSessions = allSessions;
      _sessions = sessions;
      _loading = false;
    });
  }

  DateTimeRange _getRange() {
    if (_dimension == 0) {
      final d = DateTime(_selected.year, _selected.month, _selected.day);
      return DateTimeRange(start: d, end: d.add(const Duration(days: 1)));
    } else if (_dimension == 1) {
      final base = DateTime(_selected.year, _selected.month, _selected.day);
      int weekday = base.weekday;
      final monday = base.subtract(Duration(days: weekday - 1));
      final nextMonday = monday.add(const Duration(days: 7));
      return DateTimeRange(start: monday, end: nextMonday);
    } else if (_dimension == 2) {
      final start = DateTime(_selected.year, _selected.month, 1);
      final end = DateTime(_selected.year, _selected.month + 1, 1);
      return DateTimeRange(start: start, end: end);
    } else {
      final start = DateTime(_selected.year, 1, 1);
      final end = DateTime(_selected.year + 1, 1, 1);
      return DateTimeRange(start: start, end: end);
    }
  }

  DateTimeRange _getChartRange() {
    if (_dimension == 0) {
      final base = DateTime(_selected.year, _selected.month, _selected.day);
      final start = base.subtract(const Duration(days: 5));
      final end = base.add(const Duration(days: 2)); // exclusive, so includes selected + next day
      return DateTimeRange(start: start, end: end);
    } else if (_dimension == 1) {
      final range = _getRange();
      final start = range.start.subtract(const Duration(days: 5 * 7));
      final end = range.start.add(const Duration(days: 2 * 7));
      return DateTimeRange(start: start, end: end);
    } else if (_dimension == 2) {
      final start = DateTime(_selected.year, _selected.month - 5, 1);
      final end = DateTime(_selected.year, _selected.month + 2, 1);
      return DateTimeRange(start: start, end: end);
    } else {
      final start = DateTime(_selected.year - 5, 1, 1);
      final end = DateTime(_selected.year + 2, 1, 1);
      return DateTimeRange(start: start, end: end);
    }
  }

  String _rangeLabel() {
    if (_dimension == 0) return DateFormat('yyyy年MM月dd日').format(_selected);
    if (_dimension == 1) {
      final range = _getRange();
      final startStr = DateFormat('MM/dd').format(range.start);
      final endStr = DateFormat('MM/dd').format(range.end.subtract(const Duration(seconds: 1)));
      return '$startStr - $endStr';
    }
    if (_dimension == 2) return DateFormat('yyyy年MM月').format(_selected);
    return '${_selected.year}年';
  }

  void _prev() {
    setState(() {
      if (_dimension == 0) {
        _selected = _selected.subtract(const Duration(days: 1));
      } else if (_dimension == 1) {
        _selected = _selected.subtract(const Duration(days: 7));
      } else if (_dimension == 2) {
        _selected = DateTime(_selected.year, _selected.month - 1, 1);
      } else {
        _selected = DateTime(_selected.year - 1, 1, 1);
      }
    });
    _loadLocal();
  }

  void _next() {
    setState(() {
      if (_dimension == 0) {
        _selected = _selected.add(const Duration(days: 1));
      } else if (_dimension == 1) {
        _selected = _selected.add(const Duration(days: 7));
      } else if (_dimension == 2) {
        _selected = DateTime(_selected.year, _selected.month + 1, 1);
      } else {
        _selected = DateTime(_selected.year + 1, 1, 1);
      }
    });
    _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final totalSecs = PomodoroService.totalFocusSeconds(_sessions);
    final byTag = PomodoroService.focusByTag(_sessions);
    final completedCount = _sessions.where((s) => s.isCompleted).length;

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(widget.isCompact ? 16 : 20, 
            widget.isCompact ? 4 : 12, widget.isCompact ? 16 : 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.isCompact &&
                (Theme.of(context).platform == TargetPlatform.windows ||
                    Theme.of(context).platform == TargetPlatform.linux ||
                    Theme.of(context).platform == TargetPlatform.macOS))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    const Text('专注统计',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

            // Navigation Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(
                    visualDensity: widget.isCompact ? VisualDensity.compact : null,
                    icon: Icon(Icons.chevron_left, size: widget.isCompact ? 18 : 24),
                    onPressed: _prev),
                InkWell(
                  onTap: () => setState(() => _showDimensionPicker = !_showDimensionPicker),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_rangeLabel(),
                            style: TextStyle(
                                fontSize: widget.isCompact ? 14 : 18,
                                fontWeight: FontWeight.bold)),
                        if (widget.isCompact) ...[
                          const SizedBox(width: 4),
                          Icon(
                            _showDimensionPicker
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                IconButton.filledTonal(
                    visualDensity: widget.isCompact ? VisualDensity.compact : null,
                    icon: Icon(Icons.chevron_right, size: widget.isCompact ? 18 : 24),
                    onPressed: _next),
              ],
            ),

            if (!widget.isCompact || _showDimensionPicker) ...[
              const SizedBox(height: 12),
              Center(
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Padding(padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 4 : 12), child: const Text('日'))),
                    ButtonSegment(value: 1, label: Padding(padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 4 : 8), child: const Text('周'))),
                    ButtonSegment(value: 2, label: Padding(padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 4 : 12), child: const Text('月'))),
                    ButtonSegment(value: 3, label: Padding(padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 4 : 12), child: const Text('年'))),
                  ],
                  selected: {_dimension},
                  onSelectionChanged: (s) {
                    setState(() {
                      _dimension = s.first;
                      if (widget.isCompact) _showDimensionPicker = false;
                    });
                    _loadLocal();
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),
            
            // --- Trend Chart ---
            _buildTrendChart(),
            
            const SizedBox(height: 20),

            _buildSummaryCard(totalSecs, completedCount),

            const SizedBox(height: 20),
            const Text('标签分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildTagDistribution(byTag, totalSecs),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('详细记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (_syncing)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else if (!widget.isCompact)
                  TextButton.icon(
                    onPressed: _syncAndRefresh,
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('同步'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ..._buildSessionList(),
            
            if (!widget.isCompact) ...[
               const SizedBox(height: 40),
               Center(
                 child: TextButton(
                   onPressed: _fullPull,
                   child: const Text('拉取全部历史记录'),
                 ),
               ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart() {
    // Generate 7 data points for the last 7 units
    List<ChartData> dataPoints = [];
    final chartRange = _getChartRange();
    
    for (int i = 0; i < 7; i++) {
        DateTime start, end;
        String label;
        bool isSelected = false;

        if (_dimension == 0) { // Day
            start = chartRange.start.add(Duration(days: i));
            end = start.add(const Duration(days: 1));
            label = DateFormat('MM/dd').format(start);
            isSelected = start.year == _selected.year && start.month == _selected.month && start.day == _selected.day;
        } else if (_dimension == 1) { // Week
            start = chartRange.start.add(Duration(days: i * 7));
            end = start.add(const Duration(days: 7));
            label = DateFormat('MM/dd').format(start);
            final selRange = _getRange();
            isSelected = start.isAtSameMomentAs(selRange.start);
        } else if (_dimension == 2) { // Month
            start = DateTime(chartRange.start.year, chartRange.start.month + i, 1);
            end = DateTime(start.year, start.month + 1, 1);
            label = DateFormat('MM月').format(start);
            isSelected = start.year == _selected.year && start.month == _selected.month;
        } else { // Year
            start = DateTime(chartRange.start.year + i, 1, 1);
            end = DateTime(start.year + 1, 1, 1);
            label = '${start.year}';
            isSelected = start.year == _selected.year;
        }

        final periodSessions = _chartSessions.where((s) => s.startTime >= start.millisecondsSinceEpoch && s.startTime < end.millisecondsSinceEpoch);
        final focusSecs = periodSessions.fold(0, (sum, s) => sum + s.effectiveDuration);
        dataPoints.add(ChartData(label, focusSecs, isSelected, start));
    }

    return PomodoroTrendChart(
        data: dataPoints,
        onSelect: (date) {
            setState(() {
                _selected = date;
            });
            _loadLocal();
        },
    );
  }

  Widget _buildSummaryCard(int totalSecs, int completedCount) {
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primaryContainer, colorScheme.surfaceContainerHighest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('总专注时长', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(text: '$h'),
                      const TextSpan(text: ' 小时 ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal)),
                      TextSpan(text: '$m'),
                      const TextSpan(text: ' 分钟', style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('$completedCount', style: TextStyle(color: colorScheme.primary, fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('完成番茄', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagDistribution(Map<String, int> byTag, int totalSecs) {
    if (byTag.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('本期暂无数据', style: TextStyle(color: Colors.grey)),
      );
    }

    final sorted = byTag.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    
    return Column(
      children: sorted.map((e) {
        final tag = _tags.cast<PomodoroTag?>().firstWhere((t) => t?.uuid == e.key, orElse: () => null);
        final name = tag?.name ?? '未知';
        final color = hexToColor(tag?.color ?? '#9E9E9E');
        final pct = totalSecs > 0 ? e.value / totalSecs : 0.0;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(PomodoroService.formatDuration(e.value), style: const TextStyle(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: color.withOpacity(0.1),
                  color: color,
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _buildSessionList() {
    final sorted = List<PomodoroSession>.from(_sessions)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    if (_dimension == 0) {
      return sorted.map((s) => _buildSessionCard(s, showDate: false)).toList();
    }

    final Map<String, List<PomodoroSession>> groups = {};
    for (final s in sorted) {
      final local = DateTime.fromMillisecondsSinceEpoch(s.startTime, isUtc: true).toLocal();
      final key = DateFormat('yyyy-MM-dd').format(local);
      groups.putIfAbsent(key, () => []).add(s);
    }
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final widgets = <Widget>[];
    for (final key in sortedKeys) {
      final dayDate = DateTime.parse(key);
      final dayLabel = (_dimension == 1 || _dimension == 2)
          ? DateFormat('MM月dd日').format(dayDate) : DateFormat('yyyy年MM月dd日').format(dayDate);
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(dayLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ));
      for (final s in groups[key]!) {
        widgets.add(_buildSessionCard(s, showDate: false));
      }
    }
    return widgets;
  }

  Widget _buildSessionCard(PomodoroSession s, {required bool showDate}) {
    final startLocal = DateTime.fromMillisecondsSinceEpoch(s.startTime, isUtc: true).toLocal();
    final tagNames = s.tagUuids.isNotEmpty
        ? s.tagUuids.map((uuid) => _tags.cast<PomodoroTag?>().firstWhere((t) => t?.uuid == uuid, orElse: () => null)?.name ?? uuid).join(', ')
        : null;
    final timeLabel = showDate ? DateFormat('MM-dd HH:mm').format(startLocal) : DateFormat('HH:mm').format(startLocal);

    final content = widget.isCompact
        ? Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: s.isCompleted ? const Color(0xFF4ECDC4).withValues(alpha: 0.2) : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(s.isCompleted ? Icons.check_circle_rounded : Icons.timer_off_rounded, color: s.isCompleted ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B), size: 14),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(s.todoTitle ?? '自由专注', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Row(children: [
                Text(timeLabel, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                if (tagNames != null) ...[const SizedBox(width: 6), Flexible(child: Text(tagNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.grey)))],
              ]),
            ])),
            const SizedBox(width: 8),
            Text(PomodoroService.formatDuration(s.effectiveDuration), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            IconButton(icon: const Icon(Icons.more_vert, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _editSession(s)),
          ])
        : ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: s.isCompleted ? const Color(0xFF4ECDC4).withValues(alpha: 0.2) : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(s.isCompleted ? Icons.check_circle_rounded : Icons.timer_off_rounded, color: s.isCompleted ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B)),
            ),
            title: Text(s.todoTitle ?? '自由专注', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Text(timeLabel, style: const TextStyle(fontSize: 13)),
                if (tagNames != null) ...[const SizedBox(width: 8), Flexible(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                  child: Text(tagNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ))],
              ]),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(PomodoroService.formatDuration(s.effectiveDuration), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.more_vert, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _editSession(s)),
            ]),
          );

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.isCompact ? 12 : 16)),
      child: Padding(padding: widget.isCompact ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8) : EdgeInsets.zero, child: content),
    );
  }

  Future<void> _editSession(PomodoroSession session) async {
    List<String> editTags = List.from(session.tagUuids);
    String? editTodoUuid = session.todoUuid;
    String? editTodoTitle = session.todoTitle;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sd) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('编辑专注记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async { Navigator.pop(ctx); await _deleteSession(session); }),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                const Text('专注开始时间', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(session.startTime, isUtc: true).toLocal())),
                const SizedBox(height: 16),
                const Text('专注结束时间', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final currentEnd = DateTime.fromMillisecondsSinceEpoch(session.endTime ?? session.startTime, isUtc: true).toLocal();
                    final pickedTime = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(currentEnd));
                    if (pickedTime != null) {
                      final newEnd = DateTime(currentEnd.year, currentEnd.month, currentEnd.day, pickedTime.hour, pickedTime.minute);
                      if (newEnd.millisecondsSinceEpoch <= session.startTime) {
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
                        return;
                      }
                      sd(() { session.endTime = newEnd.toUtc().millisecondsSinceEpoch; session.actualDuration = ((session.endTime! - session.startTime) / 1000).round(); });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.access_time, size: 18),
                      const SizedBox(width: 8),
                      Text(DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(session.endTime ?? session.startTime, isUtc: true).toLocal())),
                      const Spacer(),
                      const Icon(Icons.edit_outlined, size: 18),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('绑定任务', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showDialog<TodoItem?>(
                      context: ctx,
                      builder: (dctx) => AlertDialog(
                        title: const Text('选择任务'),
                        content: SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: [
                          ListTile(title: const Text('自由专注（无绑定）'), leading: const Icon(Icons.clear), onTap: () => Navigator.pop(dctx, null)),
                          const Divider(),
                          ..._todos.map((t) => ListTile(title: Text(t.title), subtitle: t.remark != null ? Text(t.remark!) : null, leading: Icon(t.isDone ? Icons.check_circle_outline : Icons.radio_button_unchecked), onTap: () => Navigator.pop(dctx, t))),
                        ])),
                      ),
                    );
                    if (picked != null) { sd(() { editTodoUuid = picked.id; editTodoTitle = picked.title; }); }
                    else if (picked == null && (editTodoUuid != null)) { sd(() { editTodoUuid = null; editTodoTitle = null; }); }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.task_alt_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(editTodoTitle ?? '自由专注（点击选择）'),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 18),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('标签', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_tags.isEmpty) const Text('暂无标签', style: TextStyle(color: Colors.grey))
                else Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _tags.map((tag) {
                    final sel = editTags.contains(tag.uuid);
                    final color = hexToColor(tag.color);
                    return FilterChip(
                      label: Text(tag.name, style: const TextStyle(fontSize: 13)),
                      selected: sel, showCheckmark: false, selectedColor: color.withValues(alpha: 0.2),
                      side: BorderSide(color: sel ? color : Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      onSelected: (v) => sd(() { if (v) { editTags.add(tag.uuid); } else { editTags.remove(tag.uuid); } }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final updated = PomodoroSession(
                        uuid: session.uuid, todoUuid: editTodoUuid, todoTitle: editTodoTitle, tagUuids: editTags,
                        startTime: session.startTime, endTime: session.endTime, plannedDuration: session.plannedDuration,
                        actualDuration: session.actualDuration, status: session.status, deviceId: session.deviceId,
                        isDeleted: session.isDeleted, version: session.version + 1, createdAt: session.createdAt,
                        updatedAt: DateTime.now().millisecondsSinceEpoch,
                      );
                      await PomodoroService.updateSession(updated);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) await _loadLocal();
                    },
                    child: const Text('保存'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteSession(PomodoroSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条专注记录吗？'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      await PomodoroService.deleteSession(session.uuid);
      _loadLocal();
    }
  }
}

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

    const PomodoroTrendChart({super.key, required this.data, required this.onSelect});

    @override
    Widget build(BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        final maxVal = data.fold(0, (max, d) => d.value > max ? d.value : max);
        final displayMax = maxVal == 0 ? 3600.0 : maxVal.toDouble();

        return Container(
            height: 220,
            padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
            decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
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
                                                                ? [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.7)]
                                                                : [colorScheme.secondary.withValues(alpha: 0.3), colorScheme.secondary.withValues(alpha: 0.1)],
                                                            begin: Alignment.topCenter,
                                                            end: Alignment.bottomCenter,
                                                        ),
                                                        borderRadius: BorderRadius.circular(8),
                                                        boxShadow: d.isSelected ? [
                                                            BoxShadow(color: colorScheme.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
                                                        ] : null,
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
                                            fontWeight: d.isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: d.isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
