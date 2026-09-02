import '../widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';
import '../widgets/management_page.dart';

class HistoricalTodosScreen extends StatefulWidget {
  final String username;
  final Future<List<TodoItem>> Function()? loadTodos;
  final Future<List<TodoGroup>> Function()? loadGroups;
  const HistoricalTodosScreen(
      {super.key, required this.username, this.loadTodos, this.loadGroups});

  @override
  State<HistoricalTodosScreen> createState() => _HistoricalTodosScreenState();
}

class _HistoricalTodosScreenState extends State<HistoricalTodosScreen>
    with SingleTickerProviderStateMixin {
  List<TodoItem> _history = [];
  List<TodoItem> _deletedTodos = [];
  List<TodoItem> _orphanTodos = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  String? _busyId;
  int _loadGeneration = 0;
  final _searchController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _isHistorical(TodoItem t) {
    if (!t.isDone) return false;
    DateTime today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);

    if (t.dueDate != null) {
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return d.isBefore(today);
    } else {
      DateTime cDate = DateTime.fromMillisecondsSinceEpoch(
              t.createdDate ?? t.createdAt,
              isUtc: true)
          .toLocal();
      DateTime c = DateTime(cDate.year, cDate.month, cDate.day);
      return c.isBefore(today);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() => _isLoading = true);
    try {
      // 🚀 核心优化：并发加载待办和分组
      final results = await Future.wait([
        widget.loadTodos?.call() ??
            StorageService.getTodos(widget.username, includeDeleted: true),
        widget.loadGroups?.call() ??
            StorageService.getTodoGroups(widget.username, includeDeleted: true),
      ]);

      if (!mounted || generation != _loadGeneration) return;
      final allTodos = results[0] as List<TodoItem>;
      final groups = results[1] as List<TodoGroup>;
      final activeGroupIds =
          groups.where((g) => !g.isDeleted).map((g) => g.id).toSet();

      setState(() {
        // 1. 历史记录：已完成、日期在今天之前、未被逻辑删除
        _history =
            allTodos.where((t) => _isHistorical(t) && !t.isDeleted).toList();
        _history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        // 2. 回收站：逻辑删除的数据
        _deletedTodos = allTodos.where((t) => t.isDeleted).toList();
        _deletedTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        // 3. 孤儿待办：未删除、未完成，且符合以下任一可见性异常条件的：
        _orphanTodos = allTodos.where((t) {
          if (t.isDeleted || t.isDone) return false;
          if (t.groupId != null && t.groupId!.isEmpty) return true;
          if (t.groupId != null && !activeGroupIds.contains(t.groupId)) {
            return true;
          }
          return false;
        }).toList();
        _orphanTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        _isLoading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _deleteItem(TodoItem item) async {
    try {
      await StorageService.deleteTodoGlobally(widget.username, item.id);
      final allTodos = await StorageService.getTodos(widget.username);
      final index = allTodos.indexWhere((t) => t.id == item.id);
      if (index != -1) {
        allTodos[index].isDeleted = true;
        allTodos[index].markAsChanged();
        await StorageService.saveTodos(widget.username, allTodos, sync: true);
      }
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已移至回收站')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请稍后再试')),
        );
      }
    }
  }

  Future<void> _uncheckItem(TodoItem item) async {
    final allTodos = await StorageService.getTodos(widget.username);
    int idx = allTodos.indexWhere((t) => t.id == item.id);
    if (idx != -1) {
      allTodos[idx].isDone = false;
      allTodos[idx].markAsChanged();
      await StorageService.saveTodos(widget.username, allTodos, sync: true);
    }
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('待办已取消完成，并退回主页清单')));
    }
  }

  Future<void> _restoreDeletedItem(TodoItem item) async {
    item.isDeleted = false;
    item.markAsChanged();

    // 🚀 核心修复：自动检测并修复“孤儿”状态
    // 如果该待办所属的分组已不存在，则将其设为未分组，确保其能直接在首页主列表显示
    final groups = await StorageService.getTodoGroups(widget.username);
    final activeGroupIds = groups.map((g) => g.id).toSet();

    if (item.groupId != null &&
        item.groupId!.isNotEmpty &&
        !activeGroupIds.contains(item.groupId)) {
      item.groupId = null;
    }

    await StorageService.updateSingleTodo(widget.username, item);
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('待办已成功恢复，并退回首页清单')));
    }
  }

  Future<void> _permanentlyDeleteItem(TodoItem item) async {
    await StorageService.permanentlyDeleteTodo(widget.username, item.id);
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已彻底删除')));
    }
  }

  Future<void> _fixOrphan(TodoItem item) async {
    final allTodos = await StorageService.getTodos(widget.username);
    int idx = allTodos.indexWhere((t) => t.id == item.id);
    if (idx != -1) {
      allTodos[idx].groupId = null; // 解绑无效的分组，让它回到首页主列表
      allTodos[idx].markAsChanged();
      await StorageService.saveTodos(widget.username, allTodos, sync: true);
    }
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已修复！待办已回到首页清单')));
    }
  }

  Future<bool> _confirmPermanentDelete({TodoItem? item}) async {
    final scheme = Theme.of(context).colorScheme;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: Text(item == null ? '清空全部回收站？' : '彻底删除这条待办？'),
            content: Text(item == null
                ? '将永久删除回收站中的全部 ${_deletedTodos.length} 条待办（包括未显示的搜索结果），删除后无法恢复。'
                : '“${item.title}”将被永久删除，删除后无法恢复。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError),
                  child: const Text('确认删除')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runAction(String id, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() => _busyId = id);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _clearRecycleBin() async {
    if (_busyId != null) return;
    if (!await _confirmPermanentDelete() || !mounted) return;
    await _runAction('clear', () async {
      await StorageService.clearTodoRecycleBin(widget.username);
      await _loadData();
    });
  }

  Future<void> _confirmDeleteItem(TodoItem item) async {
    if (_busyId != null) return;
    if (!await _confirmPermanentDelete(item: item) || !mounted) return;
    await _runAction(item.id, () => _permanentlyDeleteItem(item));
  }

  Widget _buildList(List<TodoItem> items, int section) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final visible = items
        .where((item) =>
            item.title.toLowerCase().contains(query) ||
            (item.remark ?? '').toLowerCase().contains(query))
        .toList();
    final groups = <String, List<TodoItem>>{};
    for (final item in visible) {
      final date = DateFormat('yyyy-MM-dd').format(
          DateTime.fromMillisecondsSinceEpoch(item.updatedAt).toLocal());
      groups.putIfAbsent(date, () => []).add(item);
    }
    const titles = ['完成的事，值得回顾', '删除后，仍有找回的机会', '让待办回到清单'];
    const descriptions = [
      '查看以前完成的待办，可取消完成或移至回收站。',
      '恢复误删的待办；彻底删除和清空操作无法撤销。',
      '这些待办关联的文件夹已失效。修复后将解除关联，作为独立待办显示。',
    ];
    const icons = [
      Icons.task_alt_rounded,
      Icons.restore_from_trash_outlined,
      Icons.folder_off_outlined
    ];
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ManagementPage(
          key: PageStorageKey('todo-history-$section'),
          maxWidth: 900,
          children: [
            ManagementIntro(
                icon: icons[section],
                title: titles[section],
                description: descriptions[section]),
            ManagementSearchField(
                controller: _searchController,
                hintText: '搜索待办名称或备注',
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 16),
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                      query.isEmpty
                          ? '共 ${items.length} 条待办'
                          : '找到 ${visible.length} 条待办',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  if (section == 1 && items.isNotEmpty)
                    TextButton.icon(
                        onPressed: _busyId != null ? null : _clearRecycleBin,
                        style:
                            TextButton.styleFrom(foregroundColor: scheme.error),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('清空全部')),
                ]),
            if (visible.isEmpty)
              ManagementEmptyState(
                  icon: icons[section],
                  title: query.isNotEmpty
                      ? '没有找到匹配的待办'
                      : ['没有历史待办', '回收站空空如也', '没有需要修复的待办'][section],
                  description: query.isNotEmpty
                      ? '试试其他关键词，或清空搜索。'
                      : [
                          '以前完成的待办会出现在这里。',
                          '已删除的待办会保留在这里，供你恢复。',
                          '当前未发现文件夹关联异常。'
                        ][section]),
            for (final group in groups.entries) ...[
              Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 10),
                  child: Text('${group.key} · ${group.value.length} 条',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: scheme.onSurfaceVariant))),
              ...group.value.map((item) => _buildCard(item, section)),
            ],
          ]),
    );
  }

  Widget _buildCard(TodoItem item, int section) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = _busyId == item.id;
    final enabled = _busyId == null;
    final time = DateFormat('HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(item.updatedAt).toLocal());
    return ManagementCard(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
              section == 0
                  ? Icons.check_circle_outline_rounded
                  : section == 1
                      ? Icons.delete_outline_rounded
                      : Icons.folder_off_outlined,
              color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(section == 2 ? '所属文件夹已失效' : '最近更新 · $time',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                if (item.remark?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(item.remark!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ])),
        ]),
        const SizedBox(height: 12),
        if (busy) const LinearProgressIndicator(),
        ManagementActionBar(children: [
          if (section == 0) ...[
            TextButton.icon(
                onPressed: enabled
                    ? () => _runAction(item.id, () => _deleteItem(item))
                    : null,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('移至回收站')),
            FilledButton.tonalIcon(
                onPressed: enabled
                    ? () => _runAction(item.id, () => _uncheckItem(item))
                    : null,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('取消完成')),
          ] else if (section == 1) ...[
            TextButton.icon(
                onPressed: enabled ? () => _confirmDeleteItem(item) : null,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('彻底删除')),
            FilledButton.tonalIcon(
                onPressed: enabled
                    ? () => _runAction(item.id, () => _restoreDeletedItem(item))
                    : null,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('恢复待办')),
          ] else
            FilledButton.tonalIcon(
                onPressed: enabled
                    ? () => _runAction(item.id, () => _fixOrphan(item))
                    : null,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('恢复到独立待办')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: FloatingGlassAppBar(
          flexibleSpace: const FloatingGlassTopBarBackground(),
          title: const Text('待办深度清理'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '重新扫描',
                onPressed: _isLoading || _busyId != null ? null : _loadData)
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '历史记录 ${_history.length}'),
              Tab(text: '回收站 ${_deletedTodos.length}'),
              Tab(text: '待修复 ${_orphanTodos.length}')
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
                ? ManagementPage(children: [
                    ManagementLoadError(
                        title: '暂时无法加载待办',
                        description: '请重试，已保存的待办不会受影响。',
                        onRetry: _loadData),
                  ])
                : TabBarView(controller: _tabController, children: [
                    _buildList(_history, 0),
                    _buildList(_deletedTodos, 1),
                    _buildList(_orphanTodos, 2)
                  ]),
      );
}
