import 'dart:async';

import '../widgets/floating_glass_control.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../storage_service.dart';
import '../services/todo_recurrence_restore_service.dart';
import '../services/todo_recurrence_series_edit_service.dart';
import '../services/todo_trash_multi_restore_service.dart';
import '../services/todo_trash_purge_service.dart';
import '../widgets/management_page.dart';
import '../utils/app_dialogs.dart';

class _HistoricalTodoDateHeader {
  const _HistoricalTodoDateHeader(this.date, this.count);

  final String date;
  final int count;
}

class _HistoricalTodoSectionHeader {
  const _HistoricalTodoSectionHeader(this.title, this.count);

  final String title;
  final int count;
}

class _HistoricalTodoSeriesGroup {
  const _HistoricalTodoSeriesGroup({
    required this.seriesId,
    required this.items,
    required this.visibleItems,
    required this.preview,
    required this.occurrenceCount,
    required this.completedCount,
    required this.skippedCount,
    required this.firstDate,
    required this.lastDate,
  });

  final String seriesId;
  final List<TodoItem> items;
  final List<TodoItem> visibleItems;
  final TodoRecurrenceRestorePreview? preview;
  final int occurrenceCount;
  final int completedCount;
  final int skippedCount;
  final DateTime firstDate;
  final DateTime lastDate;
}

class _HistoricalTodoSeriesMemberRow {
  const _HistoricalTodoSeriesMemberRow(this.seriesId, this.item);

  final String seriesId;
  final TodoItem item;
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
  final Future<void> Function(String username, TodoTrashMultiRestorePlan plan)?
  restoreTrashSelection;
  final Future<void> Function(String username, String seriesId)?
  restoreRecurringSeries;
  final Future<TodoTrashPurgePlan> Function(String username, String uuid)?
  previewTrashItemPurge;
  final Future<TodoTrashPurgePlan> Function(String username, String seriesId)?
  previewTrashSeriesPurge;
  final Future<TodoTrashPurgePlan> Function(String username)? previewTrashClear;
  final Future<TodoTrashPurgeResult> Function(
    String username,
    TodoTrashPurgePlan plan,
  )?
  purgeTrash;
  const HistoricalTodosScreen({
    super.key,
    required this.username,
    this.loadTodos,
    this.loadGroups,
    this.loadTodoById,
    this.saveTodo,
    this.restoreTrashSelection,
    this.restoreRecurringSeries,
    this.previewTrashItemPurge,
    this.previewTrashSeriesPurge,
    this.previewTrashClear,
    this.purgeTrash,
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
  Set<String> _activeGroupIds = {};
  final Set<String> _expandedSeriesIds = {};
  final Map<String, TodoItem> _loadedTodoById = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreTodoPages = false;
  bool _loadFailed = false;
  bool _isTrashSelectionMode = false;
  bool _isLoadingSeriesSelection = false;
  final Map<String, TodoItem> _selectedTrashTodos = {};
  final Set<String> _fullySelectedTrashSeriesIds = {};
  String? _busyId;
  int _loadGeneration = 0;
  int _trashSelectionGeneration = 0;
  int _nextTodoOffset = 0;
  int _lastTabIndex = 0;
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
    _tabController.addListener(_handleTabChanged);
    _loadData();
  }

  void _handleTabChanged() {
    final nextIndex = _tabController.index;
    if (_lastTabIndex == nextIndex) return;
    _lastTabIndex = nextIndex;
    if (_isTrashSelectionMode) {
      _trashSelectionGeneration++;
      setState(() {
        _isTrashSelectionMode = false;
        _selectedTrashTodos.clear();
        _fullySelectedTrashSeriesIds.clear();
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
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
        _activeGroupIds = activeGroupIds;

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

    if (section == 1) {
      final rows = _buildDeletedTodoRows(matchingItems, query);
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

  List<Object> _buildDeletedTodoRows(
    List<TodoItem> matchingItems,
    String query,
  ) {
    final allSeriesMembers = <String, List<TodoItem>>{};
    for (final todo in _loadedTodoById.values) {
      final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(todo);
      if (seriesId == null) continue;
      allSeriesMembers.putIfAbsent(seriesId, () => []).add(todo);
    }

    final matchingSeries = <String, List<TodoItem>>{};
    final singleItems = <TodoItem>[];
    for (final todo in matchingItems) {
      final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(todo);
      if (seriesId == null) {
        singleItems.add(todo);
      } else {
        matchingSeries.putIfAbsent(seriesId, () => []).add(todo);
      }
    }

    final seriesGroups = <_HistoricalTodoSeriesGroup>[];
    for (final entry in matchingSeries.entries) {
      final members = allSeriesMembers[entry.key] ?? entry.value;
      final deletedMembers = members.where((todo) => todo.isDeleted).toList()
        ..sort(_compareTodoDates);
      if (deletedMembers.isEmpty) continue;
      final memberIds = deletedMembers.map((todo) => todo.id).toSet();
      final visibleMembers =
          query.isEmpty
                ? deletedMembers
                : entry.value
                      .where((todo) => memberIds.contains(todo.id))
                      .toList()
            ..sort(_compareTodoDates);
      final plan = TodoRecurrenceRestoreService.tryPlan(
        todos: members,
        seriesId: entry.key,
        activeGroupIds: _activeGroupIds,
      );
      final periods = <String, List<TodoItem>>{};
      for (final member in deletedMembers) {
        final date = _todoLocalDate(member);
        periods.putIfAbsent(_todoDayKey(date), () => []).add(member);
      }
      final dates =
          periods.values.map((period) => _todoLocalDate(period.first)).toList()
            ..sort();
      seriesGroups.add(
        _HistoricalTodoSeriesGroup(
          seriesId: entry.key,
          items: deletedMembers,
          visibleItems: visibleMembers,
          preview: plan?.preview,
          occurrenceCount: periods.length,
          completedCount: periods.values
              .where((period) => period.any((todo) => todo.isDone))
              .length,
          skippedCount: periods.values
              .where((period) => period.any((todo) => todo.isSkipped))
              .length,
          firstDate: dates.first,
          lastDate: dates.last,
        ),
      );
    }
    seriesGroups.sort((a, b) {
      final aUpdated = a.items
          .map((todo) => todo.updatedAt)
          .reduce((left, right) => left > right ? left : right);
      final bUpdated = b.items
          .map((todo) => todo.updatedAt)
          .reduce((left, right) => left > right ? left : right);
      return bUpdated.compareTo(aUpdated);
    });

    final rows = <Object>[];
    if (seriesGroups.isNotEmpty) {
      rows.add(_HistoricalTodoSectionHeader('重复系列', seriesGroups.length));
      for (final group in seriesGroups) {
        rows.add(group);
        if (_expandedSeriesIds.contains(group.seriesId)) {
          rows.addAll(
            group.visibleItems.map(
              (todo) => _HistoricalTodoSeriesMemberRow(group.seriesId, todo),
            ),
          );
        }
      }
    }

    if (singleItems.isNotEmpty) {
      final groups = <String, List<TodoItem>>{};
      for (final item in singleItems) {
        final date = _dateLabelFor(item);
        groups.putIfAbsent(date, () => []).add(item);
      }
      for (final group in groups.entries) {
        rows.add(_HistoricalTodoDateHeader(group.key, group.value.length));
        rows.addAll(group.value);
      }
    }
    return rows;
  }

  int _compareTodoDates(TodoItem left, TodoItem right) =>
      (left.createdDate ?? left.createdAt).compareTo(
        right.createdDate ?? right.createdAt,
      );

  DateTime _todoLocalDate(TodoItem todo) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _todoDayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

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

  Future<List<TodoItem>> _loadAllTodosForSelection() async =>
      widget.loadTodos?.call() ??
      StorageService.getTodos(widget.username, includeDeleted: true);

  void _toggleTrashSelectionMode() {
    if (_busyId != null) return;
    if (_isTrashSelectionMode) _trashSelectionGeneration++;
    setState(() {
      _isTrashSelectionMode = !_isTrashSelectionMode;
      if (!_isTrashSelectionMode) {
        _selectedTrashTodos.clear();
        _fullySelectedTrashSeriesIds.clear();
      }
    });
  }

  void _toggleSelectedTrashTodo(TodoItem todo) {
    setState(() {
      final seriesId = TodoRecurrenceSeriesEditService.seriesIdFor(todo);
      if (seriesId != null) _fullySelectedTrashSeriesIds.remove(seriesId);
      if (_selectedTrashTodos.containsKey(todo.id)) {
        _selectedTrashTodos.remove(todo.id);
      } else if (todo.isDeleted) {
        _selectedTrashTodos[todo.id] = todo.detachedCopy();
      }
    });
  }

  Future<void> _toggleSelectedTrashSeries(
    _HistoricalTodoSeriesGroup group,
  ) async {
    if (_isLoadingSeriesSelection || _busyId != null) return;
    final selectionGeneration = _trashSelectionGeneration;
    setState(() => _isLoadingSeriesSelection = true);
    try {
      final todos = await _loadAllTodosForSelection();
      final members = todos
          .where(
            (todo) =>
                todo.isDeleted &&
                TodoRecurrenceSeriesEditService.seriesIdFor(todo) ==
                    group.seriesId,
          )
          .toList(growable: false);
      if (!mounted ||
          !_isTrashSelectionMode ||
          _tabController.index != 1 ||
          selectionGeneration != _trashSelectionGeneration) {
        return;
      }
      if (members.isEmpty) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('该系列已变化，请刷新回收站')),
        );
        return;
      }
      final allSelected = members.every(
        (todo) => _selectedTrashTodos.containsKey(todo.id),
      );
      setState(() {
        if (allSelected) {
          for (final member in members) {
            _selectedTrashTodos.remove(member.id);
          }
          _fullySelectedTrashSeriesIds.remove(group.seriesId);
        } else {
          for (final member in members) {
            _selectedTrashTodos[member.id] = member.detachedCopy();
          }
          _fullySelectedTrashSeriesIds.add(group.seriesId);
        }
      });
    } catch (_) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('读取系列期次失败，请刷新后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingSeriesSelection = false);
    }
  }

  Future<bool> _confirmTrashMultiRestore(TodoTrashMultiRestorePlan plan) async {
    final preview = plan.preview;
    final dateFormat = _historicalTodoDateFormat(
      Intl.defaultLocale,
      pattern: 'yyyy/M/d',
    );
    final dateRange = preview.firstDate == preview.lastDate
        ? dateFormat.format(preview.firstDate)
        : '${dateFormat.format(preview.firstDate)} – '
              '${dateFormat.format(preview.lastDate)}';
    final scheme = Theme.of(context).colorScheme;
    return await showAppDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            icon: const Icon(Icons.restore_rounded),
            title: const Text('恢复选中的待办？'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '恢复 ${preview.recordCount} 条待办，涉及 ${preview.seriesCount} 个重复系列。',
                ),
                const SizedBox(height: 8),
                Text('日期范围：$dateRange'),
                if (preview.completedCount > 0 || preview.skippedCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${preview.completedCount} 条已完成 · '
                    '${preview.skippedCount} 条已跳过，状态会保留。',
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '只恢复勾选的记录；未选期次、重复规则和规划内容保持原样。',
                  style: Theme.of(dialogContext).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('confirm_restore_selected_trash_todos'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('恢复所选'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _refreshSelectedTrashSnapshots() async {
    try {
      final todos = await _loadAllTodosForSelection();
      final deletedById = {
        for (final todo in todos.where((todo) => todo.isDeleted)) todo.id: todo,
      };
      if (!mounted) return;
      setState(() {
        _fullySelectedTrashSeriesIds.clear();
        for (final id in _selectedTrashTodos.keys.toList()) {
          final current = deletedById[id];
          if (current == null) {
            _selectedTrashTodos.remove(id);
          } else {
            _selectedTrashTodos[id] = current.detachedCopy();
          }
        }
      });
    } catch (_) {
      // Keep the previous selection if the latest snapshot is unavailable.
    }
    await _loadData();
  }

  Future<void> _restoreSelectedTrashTodos() async {
    if (_busyId != null || _selectedTrashTodos.isEmpty) return;
    final plan = TodoTrashMultiRestoreService.tryPlan(
      todos: _selectedTrashTodos.values,
      selectedTodoIds: _selectedTrashTodos.keys,
      activeGroupIds: _activeGroupIds,
    );
    if (plan == null) {
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('选择内容已变化，请刷新回收站后重试')),
      );
      return;
    }
    if (!await _confirmTrashMultiRestore(plan) || !mounted) return;

    await _runAction('restore-trash-selection', () async {
      try {
        final restore = widget.restoreTrashSelection;
        if (restore != null) {
          await restore(widget.username, plan);
        } else {
          await StorageService.restoreTodoTrashSelection(widget.username, plan);
        }
      } on StateError {
        await _refreshSelectedTrashSnapshots();
        throw StateError('选中待办已变化，整批未恢复。列表已刷新，请检查选择后重试。');
      }
      if (!mounted) return;
      setState(() {
        _isTrashSelectionMode = false;
        _selectedTrashTodos.clear();
        _fullySelectedTrashSeriesIds.clear();
      });
      await _loadData();
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('已恢复 ${plan.preview.recordCount} 条待办')),
        );
      }
    });
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

  Future<bool> _confirmPermanentDelete(
    TodoTrashPurgePlan plan, {
    String? itemTitle,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final preview = plan.preview;
    final title = switch (plan.scope) {
      TodoTrashPurgeScope.item => '彻底删除这条待办？',
      TodoTrashPurgeScope.series =>
        preview.hasActiveSeriesMembers ? '清理该系列回收站记录？' : '删除该系列全部现存记录？',
      TodoTrashPurgeScope.recycleBin => '清空全部回收站？',
    };
    final dateFormat = _historicalTodoDateFormat(
      Intl.defaultLocale,
      pattern: 'yyyy/M/d',
    );
    final firstDate = preview.firstDate;
    final lastDate = preview.lastDate;
    final dateRange = firstDate == null || lastDate == null
        ? null
        : firstDate == lastDate
        ? dateFormat.format(firstDate)
        : '${dateFormat.format(firstDate)} – ${dateFormat.format(lastDate)}';
    final description = <Widget>[
      if (itemTitle != null) Text('“$itemTitle”'),
      Text(
        '将永久删除 ${preview.recordCount} 条待办，覆盖 '
        '${preview.occurrenceCount} 期。',
      ),
      if (dateRange != null) Text('日期范围：$dateRange'),
      if (preview.completedCount > 0 || preview.skippedCount > 0)
        Text(
          '${preview.completedCount} 期已完成 · '
          '${preview.skippedCount} 期已跳过。',
        ),
      if (plan.scope == TodoTrashPurgeScope.series &&
          preview.hasActiveSeriesMembers)
        const Text('只清理回收站中的期次；活动期次和重复规则会保留。'),
      if (plan.scope == TodoTrashPurgeScope.series &&
          !preview.hasActiveSeriesMembers)
        const Text('该系列当前所有现存期次均在回收站，将全部删除。'),
      if (plan.scope == TodoTrashPurgeScope.recycleBin)
        const Text('范围为整个回收站，包括搜索隐藏和未加载的待办。'),
      const Text('删除后无法恢复。'),
    ];
    return await showAppDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < description.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  description[index],
                ],
              ],
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
    } catch (error) {
      if (mounted) {
        final detail = error is StateError ? error.message : null;
        final message = detail is String && detail.trim().isNotEmpty
            ? detail
            : '操作失败，请稍后重试';
        AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _clearRecycleBin() async {
    if (_busyId != null) return;
    await _confirmAndPurge(
      'clear',
      () =>
          widget.previewTrashClear?.call(widget.username) ??
          StorageService.previewClearTodoRecycleBin(widget.username),
    );
  }

  Future<void> _confirmDeleteItem(TodoItem item) async {
    if (_busyId != null) return;
    await _confirmAndPurge(
      item.id,
      () =>
          widget.previewTrashItemPurge?.call(widget.username, item.id) ??
          StorageService.previewPermanentTodoDelete(widget.username, item.id),
      itemTitle: item.title,
    );
  }

  Future<void> _confirmPurgeSeries(_HistoricalTodoSeriesGroup group) async {
    if (_busyId != null) return;
    await _confirmAndPurge(
      'purge-series:${group.seriesId}',
      () =>
          widget.previewTrashSeriesPurge?.call(
            widget.username,
            group.seriesId,
          ) ??
          StorageService.previewPermanentTodoSeriesDelete(
            widget.username,
            group.seriesId,
          ),
    );
  }

  Future<void> _confirmAndPurge(
    String busyId,
    Future<TodoTrashPurgePlan> Function() loadPlan, {
    String? itemTitle,
  }) async {
    await _runAction(busyId, () async {
      try {
        final plan = await loadPlan();
        if (!mounted ||
            !await _confirmPermanentDelete(plan, itemTitle: itemTitle) ||
            !mounted) {
          return;
        }
        final result =
            await (widget.purgeTrash?.call(widget.username, plan) ??
                StorageService.purgeTodoTrash(widget.username, plan));
        await _loadData();
        if (!mounted) return;
        final message = _resultMessage(plan, result);
        AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
      } catch (_) {
        await _loadData();
        rethrow;
      }
    });
  }

  String _resultMessage(
    TodoTrashPurgePlan plan,
    TodoTrashPurgeResult result,
  ) {
    final success = switch (plan.scope) {
      TodoTrashPurgeScope.item => '已彻底删除',
      TodoTrashPurgeScope.series => '已清理该系列 ${result.deletedCount} 条回收站记录',
      TodoTrashPurgeScope.recycleBin => '已清空回收站，共删除 ${result.deletedCount} 条待办',
    };
    if (!result.cacheCleared) return '$success；本机缓存清理失败，请刷新页面';
    if (!result.conflictsRefreshed) return '$success；日程冲突刷新失败，请刷新页面';
    return success;
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
          if (section == 1 &&
              !_isTrashSelectionMode &&
              (items.isNotEmpty || _hasMoreTodoPages))
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
            if (row is _HistoricalTodoSectionHeader) {
              return Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 10),
                child: Text(
                  '${row.title} · ${row.count}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            if (row is _HistoricalTodoSeriesGroup) {
              return _buildSeriesGroupCard(row);
            }
            if (row is _HistoricalTodoSeriesMemberRow) {
              return _buildCard(row.item, 1, indented: true);
            }
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

  Widget _buildSeriesGroupCard(_HistoricalTodoSeriesGroup group) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expanded = _expandedSeriesIds.contains(group.seriesId);
    final busy =
        _busyId == 'series:${group.seriesId}' ||
        _busyId == 'purge-series:${group.seriesId}';
    final enabled = _busyId == null;
    final selectedCount = group.items
        .where((todo) => _selectedTrashTodos.containsKey(todo.id))
        .length;
    final bool? seriesSelection = selectedCount == 0
        ? false
        : _fullySelectedTrashSeriesIds.contains(group.seriesId)
        ? true
        : null;
    final countParts = <String>['${group.occurrenceCount} 期'];
    if (group.items.length != group.occurrenceCount) {
      countParts.add('${group.items.length} 条记录');
    }
    if (group.completedCount > 0) {
      countParts.add('${group.completedCount} 期已完成');
    }
    if (group.skippedCount > 0) {
      countParts.add('${group.skippedCount} 期已跳过');
    }
    final rangeFormat = _historicalTodoDateFormat(
      Intl.defaultLocale,
      pattern: 'yyyy/M/d',
    );
    final dateRange = group.firstDate == group.lastDate
        ? rangeFormat.format(group.firstDate)
        : '${rangeFormat.format(group.firstDate)} – ${rangeFormat.format(group.lastDate)}';

    return ManagementCard(
      key: ValueKey('trash-series-${group.seriesId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isTrashSelectionMode)
                Semantics(
                  label:
                      '选择“${group.items.last.title}”系列全部回收站待办，包含搜索隐藏和未加载分页的期次',
                  child: Checkbox(
                    key: ValueKey('select_trash_series_${group.seriesId}'),
                    tristate: true,
                    value: seriesSelection,
                    onChanged: enabled && !_isLoadingSeriesSelection
                        ? (_) => unawaited(_toggleSelectedTrashSeries(group))
                        : null,
                  ),
                )
              else
                Icon(Icons.repeat_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.items.last.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      countParts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      dateRange,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isTrashSelectionMode && group.seriesId.trim().isNotEmpty)
                PopupMenuButton<String>(
                  key: ValueKey('trash_series_more_${group.seriesId}'),
                  enabled: enabled,
                  tooltip: '更多系列操作',
                  onSelected: (value) async {
                    if (value == 'purge') await _confirmPurgeSeries(group);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'purge',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_forever_outlined,
                            color: scheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '清理该系列回收站记录',
                            style: TextStyle(color: scheme.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 8),
          ManagementActionBar(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: enabled
                    ? () {
                        setState(() {
                          if (expanded) {
                            _expandedSeriesIds.remove(group.seriesId);
                          } else {
                            _expandedSeriesIds.add(group.seriesId);
                          }
                          _listProjections.remove(1);
                        });
                      }
                    : null,
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  expanded
                      ? '收起期次'
                      : '展开${group.visibleItems.length == group.items.length ? '' : '匹配的'}期次',
                ),
              ),
              if (!_isTrashSelectionMode && group.preview != null)
                FilledButton.tonalIcon(
                  key: ValueKey('restore_recurrence_series_${group.seriesId}'),
                  onPressed: enabled
                      ? () => _confirmRestoreSeries(group)
                      : null,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: Text('恢复整组（${group.preview!.occurrenceCount} 期）'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRestoreSeries(_HistoricalTodoSeriesGroup group) async {
    if (_busyId != null) return;
    final plan = TodoRecurrenceRestoreService.tryPlan(
      todos: _loadedTodoById.values,
      seriesId: group.seriesId,
      activeGroupIds: _activeGroupIds,
    );
    if (plan == null) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('系列状态已变化，请重新扫描后再试')),
        );
      }
      await _loadData();
      return;
    }
    if (!mounted) return;

    final dateFormat = _historicalTodoDateFormat(
      Intl.defaultLocale,
      pattern: 'yyyy/M/d',
    );
    final dateRange = plan.preview.firstDate == plan.preview.lastDate
        ? dateFormat.format(plan.preview.firstDate)
        : '${dateFormat.format(plan.preview.firstDate)} – ${dateFormat.format(plan.preview.lastDate)}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复整组重复待办？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.items.last.title),
            const SizedBox(height: 8),
            Text(
              '恢复回收站中的全部 ${plan.preview.recordCount} 条记录，覆盖 '
              '$dateRange，共 ${plan.preview.occurrenceCount} 期。',
            ),
            if (plan.preview.completedCount > 0 ||
                plan.preview.skippedCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${plan.preview.completedCount} 期已完成 · '
                '${plan.preview.skippedCount} 期已跳过，状态会保留。',
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '原重复规则会继续生效；已彻底删除的期次无法恢复。',
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm_restore_recurrence_series'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('恢复整组'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runAction('series:${group.seriesId}', () async {
      final restore = widget.restoreRecurringSeries;
      if (restore != null) {
        await restore(widget.username, group.seriesId);
      } else {
        await StorageService.restoreRecurringTodoSeries(
          widget.username,
          group.seriesId,
        );
      }
      await _loadData();
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('已恢复 ${plan.preview.occurrenceCount} 个期次')),
        );
      }
    });
  }

  Widget _buildCard(TodoItem item, int section, {bool indented = false}) {
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
      margin: EdgeInsets.only(
        left: indented ? 18 : 0,
        bottom: indented ? 8 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section == 1 && _isTrashSelectionMode)
                Semantics(
                  label: '选择回收站待办：${item.title}',
                  child: Checkbox(
                    key: ValueKey('select_trash_todo_${item.id}'),
                    value: _selectedTrashTodos.containsKey(item.id),
                    onChanged: enabled
                        ? (_) => _toggleSelectedTrashTodo(item)
                        : null,
                  ),
                )
              else
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
          if (!(section == 1 && _isTrashSelectionMode))
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
                        ? () => _runAction(
                            item.id,
                            () => _restoreDeletedItem(item),
                          )
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
                        ? () => _runAction(
                            item.id,
                            () => _restoreSkippedItem(item),
                          )
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

  Widget _buildTrashSelectionBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedCount = _selectedTrashTodos.length;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '已选 $selectedCount 项',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _busyId == null && !_isLoadingSeriesSelection
                  ? _toggleTrashSelectionMode
                  : null,
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('restore_selected_trash_todos'),
              onPressed:
                  selectedCount > 0 &&
                      _busyId == null &&
                      !_isLoadingSeriesSelection
                  ? _restoreSelectedTrashTodos
                  : null,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('恢复所选'),
            ),
          ],
        ),
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
          if (_tabController.index == 1)
            IconButton(
              icon: Icon(
                _isTrashSelectionMode
                    ? Icons.close_rounded
                    : Icons.checklist_rounded,
              ),
              tooltip: _isTrashSelectionMode ? '退出选择' : '选择待办',
              onPressed: _busyId != null || _isLoadingSeriesSelection
                  ? null
                  : _toggleTrashSelectionMode,
            ),
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
      bottomNavigationBar: _tabController.index == 1 && _isTrashSelectionMode
          ? _buildTrashSelectionBar()
          : null,
    );
  }
}
