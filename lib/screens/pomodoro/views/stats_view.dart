import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models.dart';
import '../../../storage_service.dart';
import '../../../services/pomodoro_service.dart';
import '../pomodoro_utils.dart';

class PomodoroStats extends StatefulWidget {
  final String username;
  const PomodoroStats({super.key, required this.username});

  @override
  State<PomodoroStats> createState() => PomodoroStatsState();
}

class PomodoroStatsState extends State<PomodoroStats> {
  int _dimension = 1;
  DateTime _selected = DateTime.now();
  List<PomodoroSession> _sessions = [];
  List<PomodoroTag> _tags = [];
  List<TodoItem> _todos = [];
  bool _loading = true;
  bool _syncing = false;

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

  Future<void> _loadLocal() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final tags = await PomodoroService.getTags();
    final todos = await StorageService.getTodos(widget.username);
    final DateTimeRange range = _getRange();
    final sessions = await PomodoroService.getSessionsInRange(range.start, range.end);
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _todos = todos.where((t) => !t.isDeleted).toList();
      _sessions = sessions;
      _loading = false;
    });
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

  DateTimeRange _getRange() {
    if (_dimension == 0) {
      final d = DateTime(_selected.year, _selected.month, _selected.day);
      return DateTimeRange(start: d, end: d.add(const Duration(days: 1)));
    } else if (_dimension == 1) {
      final start = DateTime(_selected.year, _selected.month, 1);
      final end = DateTime(_selected.year, _selected.month + 1, 1);
      return DateTimeRange(start: start, end: end);
    } else {
      final start = DateTime(_selected.year, 1, 1);
      final end = DateTime(_selected.year + 1, 1, 1);
      return DateTimeRange(start: start, end: end);
    }
  }

  String _rangeLabel() {
    if (_dimension == 0) return DateFormat('yyyy年MM月dd日').format(_selected);
    if (_dimension == 1) return DateFormat('yyyy年MM月').format(_selected);
    return '${_selected.year}年';
  }

  Future<void> _editSession(PomodoroSession session) async {
    List<String> editTags = List.from(session.tagUuids);
    String? editTodoUuid = session.todoUuid;
    String? editTodoTitle = session.todoTitle;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sd) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('编辑专注记录',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _deleteSession(session);
                      },
                    ),
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
                    final pickedTime = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(currentEnd),
                    );
                    if (pickedTime != null) {
                      final newEnd = DateTime(currentEnd.year, currentEnd.month, currentEnd.day, pickedTime.hour, pickedTime.minute);
                      if (newEnd.millisecondsSinceEpoch <= session.startTime) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
                        }
                        return;
                      }
                      // 允许修改，但通常应该是早于或等于原始结束时间（由于是事后修正）
                      sd(() {
                        session.endTime = newEnd.toUtc().millisecondsSinceEpoch;
                        session.actualDuration = ((session.endTime! - session.startTime) / 1000).round();
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 18),
                        const SizedBox(width: 8),
                        Text(DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(session.endTime ?? session.startTime, isUtc: true).toLocal())),
                        const Spacer(),
                        const Icon(Icons.edit_outlined, size: 18),
                      ],
                    ),
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
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              ListTile(
                                title: const Text('自由专注（无绑定）'),
                                leading: const Icon(Icons.clear),
                                onTap: () => Navigator.pop(dctx, null),
                              ),
                              const Divider(),
                              ..._todos.map((t) => ListTile(
                                title: Text(t.title),
                                subtitle: t.remark != null ? Text(t.remark!) : null,
                                leading: Icon(t.isDone
                                    ? Icons.check_circle_outline
                                    : Icons.radio_button_unchecked),
                                onTap: () => Navigator.pop(dctx, t),
                              )),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (picked != null) {
                      sd(() {
                        editTodoUuid = picked.id;
                        editTodoTitle = picked.title;
                      });
                    } else if (picked == null &&
                        (editTodoUuid != null)) {
                      sd(() {
                        editTodoUuid = null;
                        editTodoTitle = null;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.task_alt_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(editTodoTitle ?? '自由专注（点击选择）'),
                        const Spacer(),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const Text('标签', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_tags.isEmpty)
                  const Text('暂无标签', style: TextStyle(color: Colors.grey))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tags.map((tag) {
                      final sel = editTags.contains(tag.uuid);
                      final color = hexToColor(tag.color);
                      return FilterChip(
                        label: Text(tag.name, style: const TextStyle(fontSize: 13)),
                        selected: sel,
                        showCheckmark: false,
                        selectedColor: color.withValues(alpha: 0.2),
                        side: BorderSide(color: sel ? color : Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        onSelected: (v) => sd(() {
                          if (v) {
                            editTags.add(tag.uuid);
                          } else {
                            editTags.remove(tag.uuid);
                          }
                        }),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final updated = PomodoroSession(
                        uuid: session.uuid,
                        todoUuid: editTodoUuid,
                        todoTitle: editTodoTitle,
                        tagUuids: editTags,
                        startTime: session.startTime,
                        endTime: session.endTime,
                        plannedDuration: session.plannedDuration,
                        actualDuration: session.actualDuration,
                        status: session.status,
                        deviceId: session.deviceId,
                        isDeleted: session.isDeleted,
                        version: session.version + 1,
                        createdAt: session.createdAt,
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
      final dayLabel = _dimension == 1
          ? DateFormat('MM月dd日').format(dayDate)
          : DateFormat('yyyy年MM月dd日').format(dayDate);
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          dayLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
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
        ? s.tagUuids
        .map((uuid) => _tags.cast<PomodoroTag?>()
        .firstWhere((t) => t?.uuid == uuid, orElse: () => null)
        ?.name ?? uuid)
        .join(', ')
        : null;
    final timeLabel = showDate
        ? DateFormat('MM-dd HH:mm').format(startLocal)
        : DateFormat('HH:mm').format(startLocal);

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: s.isCompleted
                ? const Color(0xFF4ECDC4).withValues(alpha: 0.2)
                : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            s.isCompleted ? Icons.check_circle_rounded : Icons.timer_off_rounded,
            color: s.isCompleted ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B),
          ),
        ),
        title: Text(s.todoTitle ?? '自由专注',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(timeLabel, style: const TextStyle(fontSize: 13)),
              if (tagNames != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tagNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              PomodoroService.formatDuration(s.effectiveDuration),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _editSession(s),
            ),
          ],
        ),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await PomodoroService.deleteSession(session.uuid);
      _loadLocal();
    }
  }

  void _prev() {
    setState(() {
      if (_dimension == 0) {
        _selected = _selected.subtract(const Duration(days: 1));
      } else if (_dimension == 1) {
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (Theme.of(context).platform == TargetPlatform.windows || 
                Theme.of(context).platform == TargetPlatform.linux || 
                Theme.of(context).platform == TargetPlatform.macOS)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    const Text('专注统计', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            Center(
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('日'))),
                  ButtonSegment(value: 1, label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('月'))),
                  ButtonSegment(value: 2, label: Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('年'))),
                ],
                selected: {_dimension},
                onSelectionChanged: (s) {
                  setState(() => _dimension = s.first);
                  _loadLocal();
                },
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filledTonal(icon: const Icon(Icons.chevron_left), onPressed: _prev),
                Text(_rangeLabel(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton.filledTonal(icon: const Icon(Icons.chevron_right), onPressed: _next),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_syncing)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 6),
                      Text('同步中...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  )
                else
                  TextButton.icon(
                    onPressed: _syncAndRefresh,
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('增量同步', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _syncing ? null : _fullPull,
                  icon: const Icon(Icons.cloud_download_outlined, size: 16),
                  label: const Text('全量拉取', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                StatCard(
                  label: '总专注时长',
                  value: PomodoroService.formatDuration(totalSecs),
                  icon: Icons.timer_rounded,
                  color: const Color(0xFFFF6B6B),
                ),
                const SizedBox(width: 16),
                StatCard(
                  label: '完成次数',
                  value: '$completedCount 次',
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF4ECDC4),
                ),
              ],
            ),
            const SizedBox(height: 32),

            if (byTag.isNotEmpty) ...[
              const Text('标签分布', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: byTag.entries.map((e) {
                    final tagUuid = e.key;
                    final secs = e.value;
                    final tag = tagUuid == '__none__'
                        ? null
                        : _tags.cast<PomodoroTag?>().firstWhere(
                            (t) => t?.uuid == tagUuid,
                        orElse: () => null);
                    final color = tag != null ? hexToColor(tag.color) : Colors.grey;
                    final ratio = totalSecs > 0 ? secs / totalSecs : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(radius: 6, backgroundColor: color),
                              const SizedBox(width: 8),
                              Text(tag?.name ?? '未分类', style: const TextStyle(fontWeight: FontWeight.w500)),
                              const Spacer(),
                              Text(PomodoroService.formatDuration(secs),
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 10,
                              backgroundColor: color.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 32),

            if (_sessions.isNotEmpty) ...[
              const Text('专注明细', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ..._buildSessionList(),
            ] else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.coffee_outlined, size: 64, color: Theme.of(context).colorScheme.surfaceContainerHighest),
                      const SizedBox(height: 16),
                      const Text('此时段暂无专注记录', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 16),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
