import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/pomodoro_service.dart';
import '../../storage_service.dart';
import '../../widgets/floating_glass_control.dart';
import '../../utils/app_dialogs.dart';
import 'widgets/tag_batch_shared.dart';

class RebindTagPage extends StatefulWidget {
  final String username;

  const RebindTagPage({super.key, required this.username});

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
    return filterTagBatchPomodoros(
      _allPomodoros,
      dateRange: _dateRange,
      searchQuery: _searchQuery,
      extraPredicate: (p) =>
          p.tagUuids.any((uuid) => _selectedOldTagUuids.contains(uuid)),
    );
  }

  /// 获取包含已删除标签的时间日志
  List<TimeLogItem> get _timeLogsWithDeletedTags {
    if (_selectedOldTagUuids.isEmpty) return [];
    return filterTagBatchTimeLogs(
      _allTimeLogs,
      dateRange: _dateRange,
      searchQuery: _searchQuery,
      extraPredicate: (l) =>
          l.tagUuids.any((uuid) => _selectedOldTagUuids.contains(uuid)),
    );
  }

  void _toggleSelectAll(bool isPomodoro) {
    setState(() {
      if (isPomodoro) {
        toggleSelectAllRecordIds(
          _selectedPomodoros,
          _pomodorosWithDeletedTags.map((p) => p.uuid),
        );
      } else {
        toggleSelectAllRecordIds(
          _selectedTimeLogs,
          _timeLogsWithDeletedTags.map((l) => l.id),
        );
      }
    });
  }

  Future<void> _applyRebind() async {
    if (_selectedOldTagUuids.isEmpty) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请先选择要替换的旧标签')),
      );
      return;
    }

    if (_selectedNewTagUuid == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请先选择要替换为的新标签')),
      );
      return;
    }

    final pomodoroCount = _selectedPomodoros.length;
    final timeLogCount = _selectedTimeLogs.length;

    if (pomodoroCount == 0 && timeLogCount == 0) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('请先选择要重新绑定标签的记录')),
      );
      return;
    }

    // 确认对话框
    final confirmed = await AppDialogs.confirm(
      context,
      title: '确认重新绑定',
      message: '将为 $pomodoroCount 条番茄钟记录和 $timeLogCount 条时间日志重新绑定标签',
    );

    if (!confirmed) return;

    setState(() => _isLoading = true);

    try {
      // 更新番茄钟记录
      if (_selectedPomodoros.isNotEmpty) {
        for (final pom in _allPomodoros) {
          if (_selectedPomodoros.contains(pom.uuid)) {
            if (mutateRecordTagUuids(
              pom.tagUuids,
              remove: _selectedOldTagUuids,
              add: [_selectedNewTagUuid!],
            )) {
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
            if (mutateRecordTagUuids(
              log.tagUuids,
              remove: _selectedOldTagUuids,
              add: [_selectedNewTagUuid!],
            )) {
              log.markAsChanged();
            }
          }
        }
        await StorageService.saveTimeLogs(
          widget.username,
          _allTimeLogs,
          sync: true,
        );
      }

      if (!mounted) return;

      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text('成功为 $pomodoroCount 条番茄钟和 $timeLogCount 条时间日志重新绑定标签'),
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
      AppSnackBars.showSnackBar(context, SnackBar(content: Text('保存失败: $e')));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('重新绑定标签'),
        actions: [
          if (_selectedOldTagUuids.isNotEmpty && _selectedNewTagUuid != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
      body: floatingGlassSettingsBody(
        context,
        standalone: true,
        topBarHeight: kToolbarHeight + kTextTabBarHeight,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: EdgeInsets.only(
                  top:
                      floatingGlassSettingsContentTopInset(context) +
                      kTextTabBarHeight,
                ),
                child: Column(
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
              ),
      ),
      floatingActionButton:
          (_selectedOldTagUuids.isNotEmpty &&
              _selectedNewTagUuid != null &&
              (_selectedPomodoros.isNotEmpty || _selectedTimeLogs.isNotEmpty))
          ? FloatingGlassActionButton.extended(
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
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: colorScheme.onErrorContainer,
                        )
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
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: colorScheme.onPrimaryContainer,
                        )
                      : null,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterToolbar(ColorScheme colorScheme) {
    final dateFormat = AppTimeFormats.dateFormatter('MM/dd');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 日期范围
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final range = await showAppDateRangePicker(
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
                    ? '${dateFormat.format(_dateRange!.start)} - ${dateFormat.format(_dateRange!.end)}'
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
            child: TagBatchRecordSearchField(
              controller: _searchController,
              query: _searchQuery,
              hintText: '搜索标题/备注...',
              borderRadius: 8,
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
              onClear: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordEmptyState(
    ColorScheme colorScheme,
    IconData icon,
    String message,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
          ),
        ],
      ),
    );
  }

  List<String> _resolveSelectedOldTagNames(List<String> tagUuids) {
    return tagUuids.where((uuid) => _selectedOldTagUuids.contains(uuid)).map((
      uuid,
    ) {
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
  }

  Widget _buildRebindRecordList<T>({
    required ColorScheme colorScheme,
    required List<T> items,
    required String emptyMessage,
    required bool isPomodoro,
    required Set<String> selectedIds,
    required String Function(T item) idOf,
    required String Function(T item) titleOf,
    required int Function(T item) startTimeOf,
    required List<String> Function(T item) tagUuidsOf,
    required int Function(T item) durationMinutesOf,
  }) {
    if (_selectedOldTagUuids.isEmpty) {
      return _buildRecordEmptyState(
        colorScheme,
        Icons.touch_app,
        '请先选择要替换的旧标签',
      );
    }

    if (items.isEmpty) {
      return _buildRecordEmptyState(
        colorScheme,
        Icons.check_circle_outline,
        emptyMessage,
      );
    }

    final recordDateFormat = AppTimeFormats.dateFormatter('yyyy-MM-dd HH:mm');

    return TagBatchRecordListView<T>(
      items: items,
      idOf: idOf,
      selectedIds: selectedIds,
      onToggleItem: (id, selected) {
        setState(() {
          if (selected) {
            selectedIds.add(id);
          } else {
            selectedIds.remove(id);
          }
        });
      },
      selectAllHeader: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: selectedIds.length == items.length && items.isNotEmpty,
              tristate: true,
              onChanged: (value) => _toggleSelectAll(isPomodoro),
            ),
            Text(
              '全选 (${selectedIds.length}/${items.length})',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      itemTitle: (item) =>
          Text(titleOf(item), maxLines: 1, overflow: TextOverflow.ellipsis),
      itemSubtitle: (item) {
        final oldTagNames = _resolveSelectedOldTagNames(tagUuidsOf(item));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recordDateFormat.format(
                DateTime.fromMillisecondsSinceEpoch(startTimeOf(item)),
              ),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (oldTagNames.isNotEmpty)
              Text(
                '旧标签: ${oldTagNames.join(', ')}',
                style: TextStyle(fontSize: 11, color: colorScheme.error),
              ),
          ],
        );
      },
      itemTrailing: (item) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${durationMinutesOf(item)}分钟',
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildPomodoroList(ColorScheme colorScheme) {
    return _buildRebindRecordList<PomodoroRecord>(
      colorScheme: colorScheme,
      items: _pomodorosWithDeletedTags,
      emptyMessage: '没有找到包含已删除标签的番茄钟记录',
      isPomodoro: true,
      selectedIds: _selectedPomodoros,
      idOf: (record) => record.uuid,
      titleOf: (record) => record.todoTitle ?? '专注',
      startTimeOf: (record) => record.startTime,
      tagUuidsOf: (record) => record.tagUuids,
      durationMinutesOf: (record) => record.plannedDuration ~/ 60,
    );
  }

  Widget _buildTimeLogList(ColorScheme colorScheme) {
    return _buildRebindRecordList<TimeLogItem>(
      colorScheme: colorScheme,
      items: _timeLogsWithDeletedTags,
      emptyMessage: '没有找到包含已删除标签的时间日志',
      isPomodoro: false,
      selectedIds: _selectedTimeLogs,
      idOf: (log) => log.id,
      titleOf: (log) => log.title,
      startTimeOf: (log) => log.startTime,
      tagUuidsOf: (log) => log.tagUuids,
      durationMinutesOf: (log) =>
          DateTime.fromMillisecondsSinceEpoch(log.endTime)
              .difference(DateTime.fromMillisecondsSinceEpoch(log.startTime))
              .inMinutes,
    );
  }
}
