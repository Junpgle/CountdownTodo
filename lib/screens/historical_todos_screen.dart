import '../widgets/floating_glass_control.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../storage_service.dart';
import '../widgets/management_page.dart';
import '../utils/app_dialogs.dart';

class _HistoricalTodoDateHeader {
  const _HistoricalTodoDateHeader(this.date, this.count);

  final String date;
  final int count;
}

class _HistoricalTodoListProjection {
  const _HistoricalTodoListProjection({
    required this.source,
    required this.query,
    required this.matchingItems,
    required this.visibleCount,
    required this.rows,
  });

  final List<TodoItem> source;
  final String query;
  final List<TodoItem> matchingItems;
  final int visibleCount;
  final List<Object> rows;
}

class _HistoricalTodoSearchFields {
  const _HistoricalTodoSearchFields({
    required this.sourceTitle,
    required this.sourceRemark,
    required this.title,
    required this.remark,
  });

  final String sourceTitle;
  final String? sourceRemark;
  final String title;
  final String remark;
}

class _HistoricalTodoDateLabel {
  const _HistoricalTodoDateLabel({
    required this.updatedAt,
    required this.locale,
    required this.value,
  });

  final int updatedAt;
  final String? locale;
  final String value;
}

final Map<(String?, String), DateFormat> _historicalTodoDateFormats = {};

DateFormat _historicalTodoDateFormat(
  String? locale, {
  String pattern = 'yyyy-MM-dd',
}) => _historicalTodoDateFormats.putIfAbsent((
  locale,
  pattern,
), () => DateFormat(pattern, locale));

class HistoricalTodosScreen extends StatefulWidget {
  final String username;
  final Future<List<TodoItem>> Function()? loadTodos;
  final Future<List<TodoGroup>> Function()? loadGroups;
  final Future<TodoItem?> Function(String username, String uuid)? loadTodoById;
  final Future<void> Function(String username, TodoItem todo)? saveTodo;
  const HistoricalTodosScreen({
    super.key,
    required this.username,
    this.loadTodos,
    this.loadGroups,
    this.loadTodoById,
    this.saveTodo,
  });

  @override
  State<HistoricalTodosScreen> createState() => _HistoricalTodosScreenState();
}

class _HistoricalTodosScreenState extends State<HistoricalTodosScreen>
    with SingleTickerProviderStateMixin {
  static const int _todoPageSize = 120;
  List<TodoItem> _history = [];
  List<TodoItem> _skippedTodos = [];
  List<TodoItem> _deletedTodos = [];
  List<TodoItem> _orphanTodos = [];
  final Map<String, TodoItem> _loadedTodoById = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreTodoPages = false;
  bool _loadFailed = false;
  String? _busyId;
  int _loadGeneration = 0;
  int _nextTodoOffset = 0;
  final Map<int, _HistoricalTodoListProjection> _listProjections = {};
  final Expando<_HistoricalTodoSearchFields> _searchFields =
      Expando<_HistoricalTodoSearchFields>('historical todo search fields');
  final Expando<_HistoricalTodoDateLabel> _dateLabels =
      Expando<_HistoricalTodoDateLabel>('historical todo date label');
  final _searchController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _isHistorical(TodoItem t, DateTime today) {
    if (!t.isDone) return false;

    if (t.dueDate != null) {
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return d.isBefore(today);
    } else {
      return (t.createdDate ?? t.createdAt) < today.millisecondsSinceEpoch;
    }
  }

  Future<void> _loadData({bool loadMore = false}) async {
    if (!mounted) return;
    if (loadMore &&
        (!_hasMoreTodoPages ||
            _isLoadingMore ||
            _isLoading ||
            _busyId != null)) {
      return;
    }
    final generation = ++_loadGeneration;
    final offset = loadMore ? _nextTodoOffset : 0;
    if (!loadMore) _loadedTodoById.clear();
    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        _isLoadingMore = false;
        _hasMoreTodoPages = false;
        _nextTodoOffset = 0;
        _history = [];
        _skippedTodos = [];
        _deletedTodos = [];
        _orphanTodos = [];
      }
    });
    try {
      // 🚀 核心优化：并发加载待办和分组
      final results = await Future.wait([
        widget.loadTodos?.call() ??
            StorageService.getTodos(
              widget.username,
              includeDeleted: true,
              limit: _todoPageSize,
              offset: offset,
            ),
        widget.loadGroups?.call() ??
            StorageService.getTodoGroups(widget.username, includeDeleted: true),
      ]);

      if (!mounted || generation != _loadGeneration) return;
      final pageTodos = results[0] as List<TodoItem>;
      for (final todo in pageTodos) {
        final previous = _loadedTodoById[todo.id];
        if (previous == null || todo.updatedAt > previous.updatedAt) {
          _loadedTodoById[todo.id] = todo;
        }
      }
      final allTodos = _loadedTodoById.values.toList();
      final groups = results[1] as List<TodoGroup>;
      final activeGroupIds = groups
          .where((g) => !g.isDeleted)
          .map((g) => g.id)
          .toSet();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final historyTodos = <TodoItem>[];
      final skippedTodos = <TodoItem>[];
      final deletedTodos = <TodoItem>[];
      final orphanTodos = <TodoItem>[];
      for (final todo in allTodos) {
        if (todo.isDeleted) {
          deletedTodos.add(todo);
          continue;
        }
        if (todo.isSkipped) {
          skippedTodos.add(todo);
          continue;
        }
        if (todo.isDone) {
          if (_isHistorical(todo, today)) historyTodos.add(todo);
          continue;
        }
        final groupId = todo.groupId;
        if (groupId != null &&
            (groupId.isEmpty || !activeGroupIds.contains(groupId))) {
          orphanTodos.add(todo);
        }
      }
      historyTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      skippedTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      deletedTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      orphanTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      setState(() {
        // 1. 历史记录：已完成、日期在今天之前、未被逻辑删除
        _history = historyTodos;
        _skippedTodos = skippedTodos;

        // 2. 回收站：逻辑删除的数据
        _deletedTodos = deletedTodos;

        // 3. 孤儿待办：未删除、未完成，且符合以下任一可见性异常条件的：
        _orphanTodos = orphanTodos;

        _nextTodoOffset = offset + _todoPageSize;
        _hasMoreTodoPages =
            widget.loadTodos == null && pageTodos.length >= _todoPageSize;
        _isLoading = false;
        _isLoadingMore = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _loadFailed = !loadMore;
      });
      if (loadMore) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('加载更多待办失败，请重试')),
        );
      }
    }
  }

  _HistoricalTodoListProjection _projectList(
    List<TodoItem> items,
    int section,
    String query,
  ) {
    final cached = _listProjections[section];
    if (cached != null &&
        identical(cached.source, items) &&
        cached.query == query) {
      return cached;
    }

    final candidates =
        cached != null &&
            identical(cached.source, items) &&
            query.startsWith(cached.query)
        ? cached.matchingItems
        : items;
    final List<TodoItem> matchingItems;
    if (query.isEmpty) {
      matchingItems = candidates;
    } else {
      matchingItems = <TodoItem>[];
      for (final item in candidates) {
        final fields = _searchFieldsFor(item);
        if (fields.title.contains(query) || fields.remark.contains(query)) {
          matchingItems.add(item);
        }
      }
    }

    final groups = <String, List<TodoItem>>{};
    for (final item in matchingItems) {
      final date = _dateLabelFor(item);
      groups.putIfAbsent(date, () => []).add(item);
    }

    final rows = <Object>[];
    for (final group in groups.entries) {
      rows.add(_HistoricalTodoDateHeader(group.key, group.value.length));
      rows.addAll(group.value);
    }

    final projection = _HistoricalTodoListProjection(
      source: items,
      query: query,
      matchingItems: matchingItems,
      visibleCount: matchingItems.length,
      rows: rows,
    );
    _listProjections[section] = projection;
    return projection;
  }

  _HistoricalTodoSearchFields _searchFieldsFor(TodoItem item) {
    final title = item.title;
    final remark = item.remark;
    final cached = _searchFields[item];
    if (cached != null &&
        identical(cached.sourceTitle, title) &&
        identical(cached.sourceRemark, remark)) {
      return cached;
    }

    final fields = _HistoricalTodoSearchFields(
      sourceTitle: title,
      sourceRemark: remark,
      title: title.toLowerCase(),
      remark: (remark ?? '').toLowerCase(),
    );
    _searchFields[item] = fields;
    return fields;
  }

  String _dateLabelFor(TodoItem item) {
    final updatedAt = item.updatedAt;
    final locale = Intl.defaultLocale;
    final cached = _dateLabels[item];
    if (cached != null &&
        cached.updatedAt == updatedAt &&
        cached.locale == locale) {
      return cached.value;
    }

    final value = _historicalTodoDateFormat(locale)
        .format(DateTime.fromMillisecondsSinceEpoch(updatedAt).toLocal());
    _dateLabels[item] = _HistoricalTodoDateLabel(
      updatedAt: updatedAt,
      locale: locale,
      value: value,
    );
    return value;
  }

  Future<void> _deleteItem(TodoItem item) async {
    try {
      final current = await StorageService.getTodoByUuid(
        widget.username,
        item.id,
      );
      if (current == null) throw StateError('待办已不存在');
      current.isDeleted = true;
      current.markAsChanged();
      await StorageService.updateSingleTodo(widget.username, current);
      await _loadData();
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('已移至回收站')),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('删除失败，请稍后再试')),
        );
      }
    }
  }

  Future<void> _uncheckItem(TodoItem item) async {
    final current = await StorageService.getTodoByUuid(
      widget.username,
      item.id,
    );
    if (current == null) throw StateError('待办已不存在');
    current.isDone = false;
    current.markAsChanged();
    await StorageService.updateSingleTodo(widget.username, current);
    await _loadData();
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('待办已取消完成，并退回主页清单')),
      );
    }
  }

  Future<void> _restoreSkippedItem(TodoItem item) async {
    final current =
        await (widget.loadTodoById?.call(widget.username, item.id) ??
            StorageService.getTodoByUuid(widget.username, item.id));
    if (current == null || current.isDeleted || !current.isSkipped) {
      throw StateError('本期待办状态已变化，请重新加载');
    }
    current.isSkipped = false;
    current.isDone = false;
    current.isSkippedSyncPending = true;
    current.markAsChanged();
    await (widget.saveTodo?.call(widget.username, current) ??
        StorageService.updateSingleTodo(widget.username, current));
    await _loadData();
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('已恢复本期待办，后续期次不变')),
      );
    }
  }

  Future<void> _restoreDeletedItem(TodoItem item) async {
    final current =
        await (widget.loadTodoById?.call(widget.username, item.id) ??
            StorageService.getTodoByUuid(widget.username, item.id));
    if (current == null) throw StateError('待办已不存在');
    current.isDeleted = false;
    current.markAsChanged();

    // 🚀 核心修复：自动检测并修复“孤儿”状态
    // 如果该待办所属的分组已不存在，则将其设为未分组，确保其能直接在首页主列表显示
    final groups =
        await (widget.loadGroups?.call() ??
            StorageService.getTodoGroups(widget.username));
    final activeGroupIds = groups
        .where((group) => !group.isDeleted)
        .map((group) => group.id)
        .toSet();

    if (current.groupId != null &&
        current.groupId!.isNotEmpty &&
        !activeGroupIds.contains(current.groupId)) {
      current.groupId = null;
    }

    await (widget.saveTodo?.call(widget.username, current) ??
        StorageService.updateSingleTodo(widget.username, current));
    await _loadData();
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('待办已成功恢复，并退回首页清单')),
      );
    }
  }

  Future<void> _permanentlyDeleteItem(TodoItem item) async {
    await StorageService.permanentlyDeleteTodo(widget.username, item.id);
    await _loadData();
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('已彻底删除')),
      );
    }
  }

  Future<void> _fixOrphan(TodoItem item) async {
    final current = await StorageService.getTodoByUuid(
      widget.username,
      item.id,
    );
    if (current == null) throw StateError('待办已不存在');
    current.groupId = null; // 解绑无效的分组，让它回到首页主列表
    current.markAsChanged();
    await StorageService.updateSingleTodo(widget.username, current);
    await _loadData();
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('已修复！待办已回到首页清单')),
      );
    }
  }

  Future<bool> _confirmPermanentDelete({TodoItem? item}) async {
    final scheme = Theme.of(context).colorScheme;
    return await showAppDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: Text(item == null ? '清空全部回收站？' : '彻底删除这条待办？'),
            content: Text(
              item == null
                  ? _hasMoreTodoPages
                        ? '将永久删除回收站中的全部待办（当前已加载 ${_deletedTodos.length} 条，仍可能有尚未加载的记录），删除后无法恢复。'
                        : '将永久删除回收站中的全部 ${_deletedTodos.length} 条待办（包括未显示的搜索结果），删除后无法恢复。'
                  : '“${item.title}”将被永久删除，删除后无法恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                child: const Text('确认删除'),
              ),
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
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('操作失败，请稍后重试')),
        );
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

  Widget _buildList(List<TodoItem> items, int section, double topPadding) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final projection = _projectList(items, section, query);
    final visibleCount = projection.visibleCount;
    final rows = projection.rows;
    const titles = ['完成的事，值得回顾', '删除后，仍有找回的机会', '让待办回到清单', '重复待办的已跳过期次'];
    const descriptions = [
      '查看以前完成的待办，可取消完成或移至回收站。',
      '恢复误删的待办；彻底删除和清空操作无法撤销。',
      '这些待办关联的文件夹已失效。修复后将解除关联，作为独立待办显示。',
      '这里只记录被跳过的具体期次。恢复后本期重新进入待办，后续重复规则不变。',
    ];
    const icons = [
      Icons.task_alt_rounded,
      Icons.restore_from_trash_outlined,
      Icons.folder_off_outlined,
      Icons.skip_next_rounded,
    ];
    final headerChildren = <Widget>[
      ManagementIntro(
        icon: icons[section],
        title: titles[section],
        description: descriptions[section],
      ),
      ManagementSearchField(
        controller: _searchController,
        hintText: '搜索待办名称或备注',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            query.isEmpty
                ? _hasMoreTodoPages
                      ? '已加载 ${items.length} 条待办'
                      : '共 ${items.length} 条待办'
                : '找到 $visibleCount 条待办${_hasMoreTodoPages ? '（当前已加载）' : ''}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (section == 1 && items.isNotEmpty)
            TextButton.icon(
              onPressed: _busyId != null ? null : _clearRecycleBin,
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('清空全部'),
            ),
        ],
      ),
      if (visibleCount == 0)
        ManagementEmptyState(
          icon: icons[section],
          title: query.isNotEmpty
              ? '没有找到匹配的待办'
              : ['没有历史待办', '回收站空空如也', '没有需要修复的待办', '没有已跳过期次'][section],
          description: query.isNotEmpty
              ? '试试其他关键词，或清空搜索。'
              : [
                  '以前完成的待办会出现在这里。',
                  '已删除的待办会保留在这里，供你恢复。',
                  '当前未发现文件夹关联异常。',
                  '已跳过的重复待办期次会显示在这里。',
                ][section],
        ),
    ];
    final hasFooter = _isLoadingMore || _hasMoreTodoPages;
    return RefreshIndicator(
      onRefresh: () => _loadData(),
      child: ManagementPage.builder(
        key: PageStorageKey('todo-history-$section'),
        maxWidth: 900,
        topPadding: topPadding,
        itemCount: headerChildren.length + rows.length + (hasFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < headerChildren.length) return headerChildren[index];
          final rowIndex = index - headerChildren.length;
          if (rowIndex < rows.length) {
            final row = rows[rowIndex];
            if (row is _HistoricalTodoDateHeader) {
              return Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 10),
                child: Text(
                  '${row.date} · ${row.count} 条',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return _buildCard(row as TodoItem, section);
          }
          if (_isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: TextButton.icon(
                onPressed: _isLoading || _busyId != null
                    ? null
                    : () => _loadData(loadMore: true),
                icon: const Icon(Icons.expand_more_rounded),
                label: const Text('加载更多待办'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(TodoItem item, int section) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = _busyId == item.id;
    final enabled = _busyId == null;
    final time = _historicalTodoDateFormat(
      Intl.defaultLocale,
      pattern: 'HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(item.updatedAt).toLocal());
    return ManagementCard(
      key: ValueKey(item.id),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                section == 0
                    ? Icons.check_circle_outline_rounded
                    : section == 1
                    ? Icons.delete_outline_rounded
                    : section == 2
                    ? Icons.folder_off_outlined
                    : Icons.skip_next_rounded,
                color: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      section == 2
                          ? '所属文件夹已失效'
                          : section == 3
                          ? item.isSkippedSyncPending
                                ? '跳过状态尚未同步；连接支持的服务端后会自动补传'
                                : '已跳过本期 · 后续期次仍会继续'
                          : '最近更新 · $time',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (item.remark?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.remark!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          ManagementActionBar(
            children: [
              if (section == 0) ...[
                TextButton.icon(
                  onPressed: enabled
                      ? () => _runAction(item.id, () => _deleteItem(item))
                      : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('移至回收站'),
                ),
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () => _runAction(item.id, () => _uncheckItem(item))
                      : null,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('取消完成'),
                ),
              ] else if (section == 1) ...[
                TextButton.icon(
                  onPressed: enabled ? () => _confirmDeleteItem(item) : null,
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('彻底删除'),
                ),
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () =>
                            _runAction(item.id, () => _restoreDeletedItem(item))
                      : null,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('恢复待办'),
                ),
              ] else if (section == 2)
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () => _runAction(item.id, () => _fixOrphan(item))
                      : null,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: const Text('恢复到独立待办'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () =>
                            _runAction(item.id, () => _restoreSkippedItem(item))
                      : null,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('恢复本期'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topBarHeight = floatingGlassTopBarHeight(context) + kTextTabBarHeight;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('待办深度清理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新扫描',
            onPressed: _isLoading || _busyId != null ? null : () => _loadData(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: '历史记录 ${_history.length}'),
            Tab(text: '回收站 ${_deletedTodos.length}'),
            Tab(text: '待修复 ${_orphanTodos.length}'),
            Tab(text: '已跳过 ${_skippedTodos.length}'),
          ],
        ),
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
            ? ManagementPage(
                topPadding: topBarHeight,
                children: [
                  ManagementLoadError(
                    title: '暂时无法加载待办',
                    description: '请重试，已保存的待办不会受影响。',
                    onRetry: () => _loadData(),
                  ),
                ],
              )
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_history, 0, topBarHeight),
                  _buildList(_deletedTodos, 1, topBarHeight),
                  _buildList(_orphanTodos, 2, topBarHeight),
                  _buildList(_skippedTodos, 3, topBarHeight),
                ],
              ),
      ),
    );
  }
}
