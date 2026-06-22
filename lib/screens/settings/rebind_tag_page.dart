import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models.dart';
import '../../services/pomodoro_service.dart';
import '../../storage_service.dart';

class RebindTagPage extends StatefulWidget {
  final String username;

  const RebindTagPage({
    super.key,
    required this.username,
  });

  @override
  State<RebindTagPage> createState() => _RebindTagPageState();
}

class _RebindTagPageState extends State<RebindTagPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  List<PomodoroTag> _allTags = []; // 包括已删除的标签
  List<PomodoroTag> _activeTags = []; // 未删除的标签
  List<PomodoroRecord> _allPomodoros = [];
  List<TimeLogItem> _allTimeLogs = [];

  // 选中要替换的旧标签UUID
  final Set<String> _selectedOldTagUuids = {};

  // 选中要替换为的新标签UUID
  String? _selectedNewTagUuid;

  // 筛选状态
  DateTimeRange? _dateRange;
  String _searchQuery = '';

  // 选中的记录
  final Set<String> _selectedPomodoros = {};
  final Set<String> _selectedTimeLogs = {};

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
      PomodoroService.getAllTagsIncludingDeleted(),
      PomodoroService.getTags(),
      PomodoroService.getRecords(),
      StorageService.getTimeLogs(widget.username),
    ]);

    if (!mounted) return;

    setState(() {
      _allTags = results[0] as List<PomodoroTag>;
      _activeTags = results[1] as List<PomodoroTag>;
      _allPomodoros = (results[2] as List<PomodoroRecord>)
          .where((p) => !p.isDeleted)
          .toList();
      _allTimeLogs = (results[3] as List<TimeLogItem>)
          .where((l) => !l.isDeleted)
          .toList();
      _isLoading = false;
    });
  }

  /// 获取已删除的标签列表
  List<PomodoroTag> get _deletedTags {
    return _allTags.where((t) => t.isDeleted).toList();
  }

  /// 获取包含已删除标签的记录
  List<PomodoroRecord> get _pomodorosWithDeletedTags {
    if (_selectedOldTagUuids.isEmpty) return [];

    var list = _allPomodoros.where((p) {
      return p.tagUuids.any((uuid) => _selectedOldTagUuids.contains(uuid));
    }).toList();

    // 筛选时间范围
    if (_dateRange != null) {
      final startMs = _dateRange!.start.millisecondsSinceEpoch;
      final endMs =
          _dateRange!.end.add(const Duration(days: 1)).millisecondsSinceEpoch;
      list = list.where((p) => p.startTime >= startMs && p.startTime < endMs)
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

  /// 获取包含已删除标签的时间日志
  List<TimeLogItem> get _timeLogsWithDeletedTags {
    if (_selectedOldTagUuids.isEmpty) return [];

    var list = _allTimeLogs.where((l) {
      return l.tagUuids.any((uuid) => _selectedOldTagUuids.contains(uuid));
    }).toList();

    // 筛选时间范围
    if (_dateRange != null) {
      final startMs = _dateRange!.start.millisecondsSinceEpoch;
      final endMs =
          _dateRange!.end.add(const Duration(days: 1)).millisecondsSinceEpoch;
      list = list.where((l) => l.startTime >= startMs && l.startTime < endMs)
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
        final filtered = _pomodorosWithDeletedTags;
        if (_selectedPomodoros.length == filtered.length) {
          _selectedPomodoros.clear();
        } else {
          _selectedPomodoros.clear();
          _selectedPomodoros.addAll(filtered.map((p) => p.uuid));
        }
      } else {
        final filtered = _timeLogsWithDeletedTags;
        if (_selectedTimeLogs.length == filtered.length) {
          _selectedTimeLogs.clear();
        } else {
          _selectedTimeLogs.clear();
          _selectedTimeLogs.addAll(filtered.map((l) => l.id));
        }
      }
    });
  }

  Future<void> _applyRebind() async {
    if (_selectedOldTagUuids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要替换的旧标签')),
      );
      return;
    }

    if (_selectedNewTagUuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要替换为的新标签')),
      );
      return;
    }

    final pomodoroCount = _selectedPomodoros.length;
    final timeLogCount = _selectedTimeLogs.length;

    if (pomodoroCount == 0 && timeLogCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要重新绑定标签的记录')),
      );
      return;
    }

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认重新绑定'),
        content: Text(
            '将为 $pomodoroCount 条番茄钟记录和 $timeLogCount 条时间日志重新绑定标签'),
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
            // 移除旧标签
            for (final oldTagUuid in _selectedOldTagUuids) {
              if (pom.tagUuids.contains(oldTagUuid)) {
                pom.tagUuids.remove(oldTagUuid);
                changed = true;
              }
            }
            // 添加新标签（如果不存在）
            if (!pom.tagUuids.contains(_selectedNewTagUuid)) {
              pom.tagUuids.add(_selectedNewTagUuid!);
              changed = true;
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
            // 移除旧标签
            for (final oldTagUuid in _selectedOldTagUuids) {
              if (log.tagUuids.contains(oldTagUuid)) {
                log.tagUuids.remove(oldTagUuid);
                changed = true;
              }
            }
            // 添加新标签（如果不存在）
            if (!log.tagUuids.contains(_selectedNewTagUuid)) {
              log.tagUuids.add(_selectedNewTagUuid!);
              changed = true;
            }
            if (changed) {
              log.markAsChanged();
            }
          }
        }
        await StorageService.saveTimeLogs(
            widget.username, _allTimeLogs,
            sync: true);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '成功为 $pomodoroCount 条番茄钟和 $timeLogCount 条时间日志重新绑定标签'),
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
        title: const Text('重新绑定标签'),
        actions: [
          if (_selectedOldTagUuids.isNotEmpty && _selectedNewTagUuid != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '替换 ${_selectedOldTagUuids.length} 个旧标签 → 1 个新标签',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '番茄钟'),
            Tab(text: '时间日志'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 旧标签选择区域
                _buildOldTagSelector(colorScheme),

                // 新标签选择区域
                _buildNewTagSelector(colorScheme),

                // 筛选工具栏
                _buildFilterToolbar(colorScheme),

                // 记录列表
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPomodoroList(colorScheme),
                      _buildTimeLogList(colorScheme),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: (_selectedOldTagUuids.isNotEmpty &&
              _selectedNewTagUuid != null &&
              (_selectedPomodoros.isNotEmpty || _selectedTimeLogs.isNotEmpty))
          ? FloatingActionButton.extended(
              onPressed: _applyRebind,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('重新绑定'),
            )
          : null,
    );
  }

  Widget _buildOldTagSelector(ColorScheme colorScheme) {
    final deletedTags = _deletedTags;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
              const SizedBox(width: 8),
              Text(
                '选择要替换的旧标签（已删除）',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (deletedTags.isEmpty)
            Text(
              '没有已删除的标签',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: deletedTags.map((tag) {
                final isSelected = _selectedOldTagUuids.contains(tag.uuid);
                return FilterChip(
                  label: Text(tag.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedOldTagUuids.add(tag.uuid);
                      } else {
                        _selectedOldTagUuids.remove(tag.uuid);
                      }
                      // 清空记录选择
                      _selectedPomodoros.clear();
                      _selectedTimeLogs.clear();
                    });
                  },
                  selectedColor: colorScheme.errorContainer,
                  checkmarkColor: colorScheme.onErrorContainer,
                  avatar: isSelected
                      ? Icon(Icons.check,
                          size: 16, color: colorScheme.onErrorContainer)
                      : null,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildNewTagSelector(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '选择要替换为的新标签',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_activeTags.isEmpty)
            Text(
              '没有可用的标签',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _activeTags.map((tag) {
                final isSelected = _selectedNewTagUuid == tag.uuid;
                return ChoiceChip(
                  label: Text(tag.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedNewTagUuid = selected ? tag.uuid : null;
                      // 清空记录选择
                      _selectedPomodoros.clear();
                      _selectedTimeLogs.clear();
                    });
                  },
                  selectedColor: colorScheme.primaryContainer,
                  checkmarkColor: colorScheme.onPrimaryContainer,
                  avatar: isSelected
                      ? Icon(Icons.check,
                          size: 16, color: colorScheme.onPrimaryContainer)
                      : null,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 日期范围
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: _dateRange,
                );
                if (range != null) {
                  setState(() => _dateRange = range);
                }
              },
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                _dateRange != null
                    ? '${DateFormat('MM/dd').format(_dateRange!.start)} - ${DateFormat('MM/dd').format(_dateRange!.end)}'
                    : '时间范围',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_dateRange != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => setState(() => _dateRange = null),
            ),
          const SizedBox(width: 8),
          // 搜索
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索标题/备注...',
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
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPomodoroList(ColorScheme colorScheme) {
    final records = _pomodorosWithDeletedTags;

    if (_selectedOldTagUuids.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '请先选择要替换的旧标签',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '没有找到包含已删除标签的番茄钟记录',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 全选按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: _selectedPomodoros.length == records.length &&
                    records.isNotEmpty,
                tristate: true,
                onChanged: (value) => _toggleSelectAll(true),
              ),
              Text(
                '全选 (${_selectedPomodoros.length}/${records.length})',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        // 记录列表
        Expanded(
          child: ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              final isSelected = _selectedPomodoros.contains(record.uuid);

              // 获取记录中的旧标签名称
              final oldTagNames = record.tagUuids
                  .where((uuid) => _selectedOldTagUuids.contains(uuid))
                  .map((uuid) {
                final tag = _allTags.firstWhere(
                  (t) => t.uuid == uuid,
                  orElse: () => PomodoroTag(
                    uuid: uuid,
                    name: '未知',
                    color: '#9E9E9E',
                    isDeleted: true,
                    version: 0,
                    createdAt: 0,
                    updatedAt: 0,
                  ),
                );
                return tag.name;
              }).toList();

              return ListTile(
                leading: Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedPomodoros.add(record.uuid);
                      } else {
                        _selectedPomodoros.remove(record.uuid);
                      }
                    });
                  },
                ),
                title: Text(
                  record.todoTitle ?? '专注',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('yyyy-MM-dd HH:mm')
                          .format(DateTime.fromMillisecondsSinceEpoch(
                              record.startTime)),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (oldTagNames.isNotEmpty)
                      Text(
                        '旧标签: ${oldTagNames.join(', ')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.error,
                        ),
                      ),
                  ],
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${record.plannedDuration ~/ 60}分钟',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimeLogList(ColorScheme colorScheme) {
    final logs = _timeLogsWithDeletedTags;

    if (_selectedOldTagUuids.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '请先选择要替换的旧标签',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '没有找到包含已删除标签的时间日志',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 全选按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: _selectedTimeLogs.length == logs.length && logs.isNotEmpty,
                tristate: true,
                onChanged: (value) => _toggleSelectAll(false),
              ),
              Text(
                '全选 (${_selectedTimeLogs.length}/${logs.length})',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        // 记录列表
        Expanded(
          child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final isSelected = _selectedTimeLogs.contains(log.id);

              // 获取记录中的旧标签名称
              final oldTagNames = log.tagUuids
                  .where((uuid) => _selectedOldTagUuids.contains(uuid))
                  .map((uuid) {
                final tag = _allTags.firstWhere(
                  (t) => t.uuid == uuid,
                  orElse: () => PomodoroTag(
                    uuid: uuid,
                    name: '未知',
                    color: '#9E9E9E',
                    isDeleted: true,
                    version: 0,
                    createdAt: 0,
                    updatedAt: 0,
                  ),
                );
                return tag.name;
              }).toList();

              final duration =
                  DateTime.fromMillisecondsSinceEpoch(log.endTime)
                      .difference(
                          DateTime.fromMillisecondsSinceEpoch(log.startTime))
                      .inMinutes;

              return ListTile(
                leading: Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedTimeLogs.add(log.id);
                      } else {
                        _selectedTimeLogs.remove(log.id);
                      }
                    });
                  },
                ),
                title: Text(
                  log.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('yyyy-MM-dd HH:mm')
                          .format(DateTime.fromMillisecondsSinceEpoch(
                              log.startTime)),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (oldTagNames.isNotEmpty)
                      Text(
                        '旧标签: ${oldTagNames.join(', ')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.error,
                        ),
                      ),
                  ],
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$duration分钟',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}