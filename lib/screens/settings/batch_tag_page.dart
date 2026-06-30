import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../services/pomodoro_service.dart';
import '../../storage_service.dart';
import '../../utils/app_color_utils.dart';

class BatchTagPage extends StatefulWidget {
  final String username;
  final bool isEmbedded;

  const BatchTagPage({
    super.key,
    required this.username,
    this.isEmbedded = false,
  });

  @override
  State<BatchTagPage> createState() => _BatchTagPageState();
}

class _BatchTagPageState extends State<BatchTagPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  List<PomodoroTag> _tags = [];
  List<PomodoroRecord> _allPomodoros = [];
  List<TimeLogItem> _allTimeLogs = [];

  // 筛选状态
  bool _showOnlyUntagged = true;
  DateTimeRange? _dateRange;
  String _searchQuery = '';

  // 选中状态
  final Set<String> _selectedPomodoros = {};
  final Set<String> _selectedTimeLogs = {};

  // 待添加的标签（支持多选）
  final Set<String> _targetTagUuids = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      PomodoroService.getTags(),
      PomodoroService.getRecords(),
      StorageService.getTimeLogs(widget.username),
    ]);

    if (!mounted) return;

    setState(() {
      _tags = (results[0] as List<PomodoroTag>)
          .where((t) => !t.isDeleted && !t.isArchived)
          .toList();
      _allPomodoros = (results[1] as List<PomodoroRecord>)
          .where((p) => !p.isDeleted)
          .toList();
      _allTimeLogs =
          (results[2] as List<TimeLogItem>).where((l) => !l.isDeleted).toList();
      _isLoading = false;
    });
  }

  List<PomodoroRecord> get _filteredPomodoros {
    var list = _allPomodoros;

    // 筛选未标签
    if (_showOnlyUntagged) {
      list = list.where((p) => p.tagUuids.isEmpty).toList();
    }

    // 筛选时间范围
    if (_dateRange != null) {
      final startMs = _dateRange!.start.millisecondsSinceEpoch;
      final endMs =
          _dateRange!.end.add(const Duration(days: 1)).millisecondsSinceEpoch;
      list = list
          .where((p) => p.startTime >= startMs && p.startTime < endMs)
          .toList();
    }

    // 搜索
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((p) {
        final title = (p.todoTitle ?? '').toLowerCase();
        final note = (p.note ?? '').toLowerCase();
        return title.contains(query) || note.contains(query);
      }).toList();
    }

    // 按时间倒序
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  List<TimeLogItem> get _filteredTimeLogs {
    var list = _allTimeLogs;

    // 筛选未标签
    if (_showOnlyUntagged) {
      list = list.where((l) => l.tagUuids.isEmpty).toList();
    }

    // 筛选时间范围
    if (_dateRange != null) {
      final startMs = _dateRange!.start.millisecondsSinceEpoch;
      final endMs =
          _dateRange!.end.add(const Duration(days: 1)).millisecondsSinceEpoch;
      list = list
          .where((l) => l.startTime >= startMs && l.startTime < endMs)
          .toList();
    }

    // 搜索
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((l) {
        final title = l.title.toLowerCase();
        final remark = (l.remark ?? '').toLowerCase();
        return title.contains(query) || remark.contains(query);
      }).toList();
    }

    // 按时间倒序
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  void _toggleSelectAll(bool isPomodoro) {
    setState(() {
      if (isPomodoro) {
        final filtered = _filteredPomodoros;
        if (_selectedPomodoros.length == filtered.length) {
          _selectedPomodoros.clear();
        } else {
          _selectedPomodoros.clear();
          _selectedPomodoros.addAll(filtered.map((p) => p.uuid));
        }
      } else {
        final filtered = _filteredTimeLogs;
        if (_selectedTimeLogs.length == filtered.length) {
          _selectedTimeLogs.clear();
        } else {
          _selectedTimeLogs.clear();
          _selectedTimeLogs.addAll(filtered.map((l) => l.id));
        }
      }
    });
  }

  Future<void> _applyTag() async {
    if (_targetTagUuids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要添加的标签')),
      );
      return;
    }

    final pomodoroCount = _selectedPomodoros.length;
    final timeLogCount = _selectedTimeLogs.length;
    final tagCount = _targetTagUuids.length;

    if (pomodoroCount == 0 && timeLogCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要添加标签的记录')),
      );
      return;
    }

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认添加'),
        content: Text(
            '将为 $pomodoroCount 条番茄钟记录和 $timeLogCount 条时间日志添加 $tagCount 个标签'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      // 更新番茄钟记录
      if (_selectedPomodoros.isNotEmpty) {
        for (final pom in _allPomodoros) {
          if (_selectedPomodoros.contains(pom.uuid)) {
            bool changed = false;
            for (final tagUuid in _targetTagUuids) {
              if (!pom.tagUuids.contains(tagUuid)) {
                pom.tagUuids.add(tagUuid);
                changed = true;
              }
            }
            if (changed) {
              pom.markAsChanged();
              await PomodoroService.updateRecord(pom);
            }
          }
        }
      }

      // 更新时间日志
      if (_selectedTimeLogs.isNotEmpty) {
        for (final log in _allTimeLogs) {
          if (_selectedTimeLogs.contains(log.id)) {
            bool changed = false;
            for (final tagUuid in _targetTagUuids) {
              if (!log.tagUuids.contains(tagUuid)) {
                log.tagUuids.add(tagUuid);
                changed = true;
              }
            }
            if (changed) {
              log.markAsChanged();
            }
          }
        }
        await StorageService.saveTimeLogs(widget.username, _allTimeLogs,
            sync: true);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功为 $pomodoroCount 条番茄钟和 $timeLogCount 条时间日志添加标签'),
        ),
      );

      // 清空选择
      setState(() {
        _selectedPomodoros.clear();
        _selectedTimeLogs.clear();
      });

      // 重新加载数据
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isEmbedded,
        toolbarHeight: widget.isEmbedded ? 0 : null,
        title: widget.isEmbedded ? null : const Text('批量添加标签'),
        actions: widget.isEmbedded
            ? null
            : [
                if (_targetTagUuids.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '已选 ${_targetTagUuids.length} 个标签',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '番茄钟', icon: Icon(Icons.timer_outlined)),
            Tab(text: '时间日志', icon: Icon(Icons.schedule_outlined)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterBar(),
                _buildTagSelector(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPomodoroList(),
                      _buildTimeLogList(),
                    ],
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Row(
            children: [
              // 搜索框
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: '搜索标题...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 日期筛选
              FilterChip(
                label: Text(
                  _dateRange != null
                      ? '${DateFormat('MM/dd').format(_dateRange!.start)}-${DateFormat('MM/dd').format(_dateRange!.end)}'
                      : '时间',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: _dateRange != null,
                onSelected: (_) async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: _dateRange,
                  );
                  if (range != null) {
                    setState(() => _dateRange = range);
                  }
                },
                avatar: const Icon(Icons.date_range, size: 16),
              ),
              const SizedBox(width: 8),
              // 未标签筛选
              FilterChip(
                label: const Text('未标签', style: TextStyle(fontSize: 12)),
                selected: _showOnlyUntagged,
                onSelected: (v) => setState(() => _showOnlyUntagged = v),
                avatar: const Icon(Icons.label_off, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagSelector() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tags.length,
        itemBuilder: (ctx, i) {
          final tag = _tags[i];
          final color =
              AppColorUtils.hexToColor(tag.color, fallback: Colors.grey);
          final isSelected = _targetTagUuids.contains(tag.uuid);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _targetTagUuids.remove(tag.uuid);
                  } else {
                    _targetTagUuids.add(tag.uuid);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.2)
                      : color.withValues(alpha: 0.05),
                  border: Border.all(
                    color: isSelected ? color : color.withValues(alpha: 0.3),
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected)
                      Icon(Icons.check, size: 14, color: color)
                    else
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      tag.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPomodoroList() {
    final filtered = _filteredPomodoros;

    if (filtered.isEmpty) {
      return const Center(
        child: Text('没有符合条件的番茄钟记录', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
        _buildSelectAllBar(true, filtered.length),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final pom = filtered[i];
              final isSelected = _selectedPomodoros.contains(pom.uuid);
              final startTime =
                  DateTime.fromMillisecondsSinceEpoch(pom.startTime);
              final endTime = pom.endTime != null
                  ? DateTime.fromMillisecondsSinceEpoch(pom.endTime!)
                  : startTime.add(Duration(seconds: pom.effectiveDuration));
              final duration = pom.effectiveDuration ~/ 60;

              return ListTile(
                leading: Checkbox(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedPomodoros.add(pom.uuid);
                      } else {
                        _selectedPomodoros.remove(pom.uuid);
                      }
                    });
                  },
                ),
                title: Text(
                  pom.todoTitle ?? '番茄钟',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${DateFormat('MM/dd HH:mm').format(startTime)} → ${DateFormat('HH:mm').format(endTime)}  ${duration}min',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: pom.tagUuids.isNotEmpty
                    ? _buildTagChips(pom.tagUuids)
                    : const Text('无标签',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimeLogList() {
    final filtered = _filteredTimeLogs;

    if (filtered.isEmpty) {
      return const Center(
        child: Text('没有符合条件的时间日志', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
        _buildSelectAllBar(false, filtered.length),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final log = filtered[i];
              final isSelected = _selectedTimeLogs.contains(log.id);
              final startTime =
                  DateTime.fromMillisecondsSinceEpoch(log.startTime);
              final endTime = DateTime.fromMillisecondsSinceEpoch(log.endTime);
              final duration = (log.endTime - log.startTime) ~/ 60000;

              return ListTile(
                leading: Checkbox(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedTimeLogs.add(log.id);
                      } else {
                        _selectedTimeLogs.remove(log.id);
                      }
                    });
                  },
                ),
                title: Text(
                  log.title.isNotEmpty ? log.title : '时间日志',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${DateFormat('MM/dd HH:mm').format(startTime)} → ${DateFormat('HH:mm').format(endTime)}  ${duration}min',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: log.tagUuids.isNotEmpty
                    ? _buildTagChips(log.tagUuids)
                    : const Text('无标签',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelectAllBar(bool isPomodoro, int totalCount) {
    final selectedCount =
        isPomodoro ? _selectedPomodoros.length : _selectedTimeLogs.length;
    final allSelected = selectedCount == totalCount && totalCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            tristate: true,
            onChanged: (_) => _toggleSelectAll(isPomodoro),
          ),
          Text(
            '已选 $selectedCount / $totalCount',
            style: const TextStyle(fontSize: 12),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => _toggleSelectAll(isPomodoro),
            child: Text(allSelected ? '取消全选' : '全选'),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChips(List<String> tagUuids) {
    return SizedBox(
      width: 80,
      child: Wrap(
        spacing: 2,
        children: tagUuids.take(2).map((uuid) {
          final tag = _tags.cast<PomodoroTag?>().firstWhere(
                (t) => t?.uuid == uuid,
                orElse: () => null,
              );
          if (tag == null) return const SizedBox();
          final color =
              AppColorUtils.hexToColor(tag.color, fallback: Colors.grey);
          return Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomBar() {
    final totalSelected = _selectedPomodoros.length + _selectedTimeLogs.length;
    final selectedTagNames = _tags
        .where((t) => _targetTagUuids.contains(t.uuid))
        .map((t) => t.name)
        .toList();

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '已选择 $totalSelected 条记录',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (selectedTagNames.isNotEmpty)
                  Text(
                    '将添加: ${selectedTagNames.join(", ")}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: totalSelected > 0 ? _applyTag : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加标签'),
          ),
        ],
      ),
    );
  }
}

extension on PomodoroRecord {
  void markAsChanged() {
    version++;
    updatedAt = DateTime.now().millisecondsSinceEpoch;
  }
}
