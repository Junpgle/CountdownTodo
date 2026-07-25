import 'package:flutter/material.dart';

import '../../../models.dart';
import '../../../storage_service.dart';

class RecurrenceSeriesMergePage extends StatefulWidget {
  final String username;
  final bool isEmbedded;

  const RecurrenceSeriesMergePage({
    super.key,
    required this.username,
    this.isEmbedded = false,
  });

  @override
  State<RecurrenceSeriesMergePage> createState() =>
      _RecurrenceSeriesMergePageState();
}

class _RecurrenceSeriesMergePageState extends State<RecurrenceSeriesMergePage> {
  final TextEditingController _searchController = TextEditingController();
  List<_RecurrenceSeriesSummary> _series = const [];
  final Set<String> _selectedSeriesIds = <String>{};
  String? _targetSeriesId;
  bool _isLoading = true;
  bool _isMerging = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    if (mounted) setState(() => _isLoading = true);
    final todos = await StorageService.getTodos(
      widget.username,
      includeDeleted: true,
    );
    final summaries = _buildSummaries(todos);
    if (!mounted) return;
    setState(() {
      _series = summaries;
      _selectedSeriesIds.removeWhere(
        (seriesId) => !summaries.any((summary) => summary.id == seriesId),
      );
      if (!_selectedSeriesIds.contains(_targetSeriesId)) {
        _targetSeriesId =
            _selectedSeriesIds.isEmpty ? null : _selectedSeriesIds.first;
      }
      _isLoading = false;
    });
  }

  static List<_RecurrenceSeriesSummary> _buildSummaries(
    List<TodoItem> todos,
  ) {
    final grouped = <String, List<TodoItem>>{};
    for (final todo in todos) {
      final seriesId = todo.recurrenceSeriesId;
      if (seriesId == null || seriesId.isEmpty) continue;
      grouped.putIfAbsent(seriesId, () => <TodoItem>[]).add(todo);
    }

    final summaries = <_RecurrenceSeriesSummary>[];
    for (final entry in grouped.entries) {
      final visible = entry.value.where((todo) => !todo.isDeleted).toList()
        ..sort((a, b) => (a.createdDate ?? a.createdAt)
            .compareTo(b.createdDate ?? b.createdAt));
      if (visible.isEmpty) continue;

      TodoItem representative = visible.last;
      for (final todo in visible.reversed) {
        if (todo.recurrence != RecurrenceType.none) {
          representative = todo;
          break;
        }
      }
      summaries.add(
        _RecurrenceSeriesSummary(
          id: entry.key,
          title: representative.title,
          firstStart: visible.first.createdDate ?? visible.first.createdAt,
          lastStart: visible.last.createdDate ?? visible.last.createdAt,
          occurrenceCount: visible.length,
          completedCount: visible.where((todo) => todo.isDone).length,
          conflictCount: visible.where((todo) => todo.hasConflict).length,
          hasActiveRule:
              visible.any((todo) => todo.recurrence != RecurrenceType.none),
        ),
      );
    }
    summaries.sort((a, b) {
      final titleCompare = a.title.compareTo(b.title);
      if (titleCompare != 0) return titleCompare;
      return a.firstStart.compareTo(b.firstStart);
    });
    return summaries;
  }

  void _toggleSeries(String seriesId, bool selected) {
    setState(() {
      if (selected) {
        _selectedSeriesIds.add(seriesId);
        _targetSeriesId ??= seriesId;
      } else {
        _selectedSeriesIds.remove(seriesId);
        if (_targetSeriesId == seriesId) {
          _targetSeriesId =
              _selectedSeriesIds.isEmpty ? null : _selectedSeriesIds.first;
        }
      }
    });
  }

  Future<void> _confirmMerge() async {
    final targetId = _targetSeriesId;
    if (_selectedSeriesIds.length < 2 || targetId == null || _isMerging) {
      return;
    }
    final target = _series.where((summary) => summary.id == targetId).first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('合并重复待办'),
        content: Text(
          '将 ${_selectedSeriesIds.length} 个系列合并为一个，并保留“${target.title}”所在系列为主系列。\n\n'
          '每期待办的独立 ID、完成状态、规划、专注记录和时间日志都会保留。同一天的重复实例会自动去重。\n\n'
          '主系列现有的重复规则优先保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.merge_type_rounded),
            label: const Text('确认合并'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isMerging = true);
    try {
      final changedCount = await StorageService.mergeRecurrenceSeries(
        widget.username,
        targetSeriesId: targetId,
        seriesIds: Set<String>.from(_selectedSeriesIds),
      );
      if (!mounted) return;
      if (changedCount == 0) {
        throw StateError('所选系列已经合并，或数据不足');
      }
      _selectedSeriesIds.clear();
      _targetSeriesId = null;
      await _loadSeries();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已合并循环系列，更新 $changedCount 个实例')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('合并失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _isMerging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filtered = _series.where((summary) {
      if (_query.isEmpty) return true;
      final query = _query.toLowerCase();
      return summary.title.toLowerCase().contains(query) ||
          summary.id.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(title: const Text('合并重复待办')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '选择两个或多个被拆分的循环系列，再指定一个主系列。不会按标题自动合并。',
                                style: TextStyle(
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _query = value.trim()),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: '搜索待办标题或系列 ID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _series.isEmpty ? '暂无可合并的重复待办' : '没有匹配的重复系列',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _buildSeriesCard(filtered[index]);
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _buildMergeBar(),
    );
  }

  Widget _buildSeriesCard(_RecurrenceSeriesSummary summary) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selectedSeriesIds.contains(summary.id);
    final isTarget = _targetSeriesId == summary.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.55)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _toggleSeries(summary.id, !selected),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) => _toggleSeries(summary.id, value ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (summary.hasActiveRule)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.repeat_rounded,
                              size: 17,
                              color: colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatRange(summary)} · ${summary.completedCount}/${summary.occurrenceCount} 期已完成'
                      '${summary.conflictCount > 0 ? ' · ${summary.conflictCount} 条冲突' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '系列 ${_shortSeriesId(summary.id)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                isTarget
                    ? Chip(
                        avatar: Icon(
                          Icons.flag_rounded,
                          size: 16,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        label: const Text('主系列'),
                        backgroundColor: colorScheme.primaryContainer,
                        side: BorderSide.none,
                      )
                    : TextButton(
                        onPressed: () =>
                            setState(() => _targetSeriesId = summary.id),
                        child: const Text('设为主系列'),
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildMergeBar() {
    if (_selectedSeriesIds.isEmpty) return null;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '已选 ${_selectedSeriesIds.length} 个系列'
                  '${_targetSeriesId == null ? '' : ' · 已指定主系列'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                onPressed: _selectedSeriesIds.length >= 2 && !_isMerging
                    ? _confirmMerge
                    : null,
                icon: _isMerging
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.merge_type_rounded),
                label: Text(_isMerging ? '正在合并' : '合并'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRange(_RecurrenceSeriesSummary summary) {
    final first = DateTime.fromMillisecondsSinceEpoch(
      summary.firstStart,
      isUtc: true,
    ).toLocal();
    final last = DateTime.fromMillisecondsSinceEpoch(
      summary.lastStart,
      isUtc: true,
    ).toLocal();
    final firstText = '${first.month}/${first.day}';
    final lastText = '${last.month}/${last.day}';
    return firstText == lastText ? firstText : '$firstText–$lastText';
  }

  static String _shortSeriesId(String seriesId) =>
      seriesId.length <= 8 ? seriesId : '${seriesId.substring(0, 8)}…';
}

class _RecurrenceSeriesSummary {
  final String id;
  final String title;
  final int firstStart;
  final int lastStart;
  final int occurrenceCount;
  final int completedCount;
  final int conflictCount;
  final bool hasActiveRule;

  const _RecurrenceSeriesSummary({
    required this.id,
    required this.title,
    required this.firstStart,
    required this.lastStart,
    required this.occurrenceCount,
    required this.completedCount,
    required this.conflictCount,
    required this.hasActiveRule,
  });
}
