import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage_service.dart';
import '../utils/time_utils.dart';

typedef FixedScheduleRelatedTodoPageLoader =
    Future<({List<TodoItem> todos, bool hasMore})> Function(
      String username, {
      required String? teamUuid,
      required String query,
      required int limit,
      required int offset,
    });

typedef FixedScheduleRelatedTodoIdsLoader = Future<List<TodoItem>> Function(
  String username,
  Set<String> todoIds,
);

/// Multi-select editor for the IDs stored in FixedScheduleItem.relatedTodoIds.
/// Changes stay local until the user taps Apply.
class FixedScheduleRelatedTodoPickerScreen extends StatefulWidget {
  const FixedScheduleRelatedTodoPickerScreen({
    super.key,
    required this.username,
    required this.teamUuid,
    required this.initialSelectedIds,
    this.loadTodoPage,
    this.loadSelectedTodos,
  });

  final String username;
  final String? teamUuid;
  final Set<String> initialSelectedIds;
  final FixedScheduleRelatedTodoPageLoader? loadTodoPage;
  final FixedScheduleRelatedTodoIdsLoader? loadSelectedTodos;

  @override
  State<FixedScheduleRelatedTodoPickerScreen> createState() =>
      _FixedScheduleRelatedTodoPickerScreenState();
}

class _FixedScheduleRelatedTodoPickerScreenState
    extends State<FixedScheduleRelatedTodoPickerScreen> {
  static const int _pageSize = 50;

  late final TextEditingController _searchController;
  late Set<String> _selectedIds;
  final Map<String, TodoItem> _todosById = {};
  List<String> _pageTodoIds = [];
  final Set<String> _pageTodoIdSet = {};
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  Object? _loadError;
  Object? _loadMoreError;
  int _nextOffset = 0;
  int _loadGeneration = 0;
  Timer? _searchDebounce;

  String? get _normalizedTeamUuid {
    final value = widget.teamUuid?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedIds = widget.initialSelectedIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    _loadPage(reset: true, loadSelectedTodos: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<({List<TodoItem> todos, bool hasMore})> _fetchPage({
    required int offset,
  }) =>
      (widget.loadTodoPage ??
      StorageService.getTodosForFixedScheduleRelationPage)(
        widget.username,
        teamUuid: widget.teamUuid,
        query: _searchController.text.trim(),
        limit: _pageSize,
        offset: offset,
      );

  Future<List<TodoItem>> _fetchSelectedTodos() {
    if (_selectedIds.isEmpty) return Future.value(const <TodoItem>[]);
    return (widget.loadSelectedTodos ??
        StorageService.getTodosForFixedScheduleRelationIds)(
      widget.username,
      _selectedIds,
    );
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _loadGeneration++;
    setState(() {
      _loading = true;
      _isLoadingMore = false;
      _hasMore = false;
      _loadError = null;
      _loadMoreError = null;
      _nextOffset = 0;
      _pageTodoIds = [];
      _pageTodoIdSet.clear();
      _todosById.removeWhere((id, _) => !_selectedIds.contains(id));
    });
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadPage(reset: true, loadSelectedTodos: true);
    });
  }

  Future<void> _loadPage({
    required bool reset,
    bool loadSelectedTodos = false,
  }) async {
    if (!reset && (!_hasMore || _isLoadingMore || _loading)) return;

    final generation = reset ? ++_loadGeneration : _loadGeneration;
    final offset = reset ? 0 : _nextOffset;
    if (reset) {
      setState(() {
        _loading = true;
        _isLoadingMore = false;
        _loadError = null;
        _loadMoreError = null;
        _hasMore = false;
        _nextOffset = 0;
        _pageTodoIds = [];
        _pageTodoIdSet.clear();
        _todosById.removeWhere((id, _) => !_selectedIds.contains(id));
      });
    } else {
      setState(() {
        _isLoadingMore = true;
        _loadMoreError = null;
      });
    }

    try {
      final pageFuture = _fetchPage(offset: offset);
      final selectedFuture = loadSelectedTodos
          ? _fetchSelectedTodos()
          : Future.value(const <TodoItem>[]);
      final page = await pageFuture;
      final selectedTodos = await selectedFuture;
      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        for (final todo in selectedTodos) {
          final id = todo.id.trim();
          if (id.isNotEmpty) _todosById[id] = todo;
        }
        for (final todo in page.todos) {
          final id = todo.id.trim();
          if (id.isEmpty) continue;
          _todosById[id] = todo;
          if (_pageTodoIdSet.add(id)) _pageTodoIds.add(id);
        }
        _nextOffset = offset + page.todos.length;
        _hasMore = page.hasMore;
        _loading = false;
        _isLoadingMore = false;
        _loadError = null;
        _loadMoreError = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        if (reset) {
          _loadError = error;
        } else {
          _loadMoreError = error;
        }
      });
    }
  }

  bool _sameVisibility(TodoItem todo) =>
      (todo.teamUuid?.trim().isNotEmpty == true
          ? todo.teamUuid!.trim()
          : null) ==
      _normalizedTeamUuid;

  bool _canAdd(TodoItem todo) => !todo.isDeleted && _sameVisibility(todo);

  String _statusLabel(TodoItem todo) {
    if (todo.isDeleted) return '已删除';
    if (todo.isDone) return '已完成';
    if (todo.isSkipped) return '已跳过';
    if (todo.hasConflict) return '存在同步冲突';
    return '待完成';
  }

  String _subtitle(TodoItem todo) {
    final status = _statusLabel(todo);
    final dueDate = todo.dueDate?.toLocal();
    if (dueDate == null) return status;
    final date = AppTimeFormats.format(dueDate, 'M月d日');
    final time = todo.isDateOnly ? '' : ' ${AppTimeFormats.clock(dueDate)}';
    return '$status · $date$time';
  }

  void _toggle(String id, {required bool canAdd}) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (!_pageTodoIdSet.contains(id)) _todosById.remove(id);
      } else if (canAdd) {
        _selectedIds.add(id);
      }
    });
  }

  List<_RelatedTodoRow> _rows() {
    final rows = <_RelatedTodoRow>[];
    final includedIds = <String>{};

    for (final id in _pageTodoIds) {
      final todo = _todosById[id];
      if (todo == null) continue;
      if (!_canAdd(todo)) continue;
      rows.add(
        _RelatedTodoRow(
          id: todo.id,
          title: todo.title.trim().isEmpty ? '未命名待办' : todo.title.trim(),
          subtitle: _subtitle(todo),
          canAdd: true,
          todo: todo,
        ),
      );
      includedIds.add(todo.id);
    }

    for (final id in _selectedIds) {
      if (includedIds.contains(id)) continue;
      final todo = _todosById[id];
      final title = todo != null && _sameVisibility(todo)
          ? (todo.title.trim().isEmpty ? '未命名待办' : todo.title.trim())
          : '关联待办不可用';
      final status = todo == null || !_sameVisibility(todo)
          ? '已删除或当前日程不可见'
          : _statusLabel(todo);
      rows.add(
        _RelatedTodoRow(
          id: id,
          title: title,
          subtitle: status,
          canAdd: false,
          todo: todo,
        ),
      );
    }

    rows.sort(_compareRows);

    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows
        .where(
          (row) =>
              row.title.toLowerCase().contains(query) ||
              row.subtitle.toLowerCase().contains(query),
        )
        .toList();
  }

  int _compareRows(_RelatedTodoRow left, _RelatedTodoRow right) {
    int statusOrder(_RelatedTodoRow row) {
      final todo = row.todo;
      if (todo == null || todo.isDeleted || !_sameVisibility(todo)) return 2;
      if (todo.isDone || todo.isSkipped) return 1;
      return 0;
    }

    final statusCompare = statusOrder(left).compareTo(statusOrder(right));
    if (statusCompare != 0) return statusCompare;

    final leftDue = left.todo?.dueDate?.millisecondsSinceEpoch;
    final rightDue = right.todo?.dueDate?.millisecondsSinceEpoch;
    if (leftDue == null && rightDue != null) return 1;
    if (leftDue != null && rightDue == null) return -1;
    if (leftDue != null && rightDue != null && leftDue != rightDue) {
      return leftDue.compareTo(rightDue);
    }

    final titleCompare = left.title.toLowerCase().compareTo(
      right.title.toLowerCase(),
    );
    return titleCompare != 0 ? titleCompare : left.id.compareTo(right.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows();

    return Scaffold(
      appBar: AppBar(
        title: const Text('关联待办'),
        leading: IconButton(
          tooltip: '取消',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _normalizedTeamUuid == null
                        ? '选择仅自己可见的待办。关联只建立联系，不会修改待办状态或期限。'
                        : '选择同一团队可见的待办，避免把个人待办信息带入团队日程。',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: '搜索待办',
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildList(context, rows)),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('apply-related-todos'),
                  onPressed: _loading || _loadError != null
                      ? null
                      : () => Navigator.of(context).pop(_selectedIds),
                  icon: const Icon(Icons.check_rounded),
                  label: Text('应用 ${_selectedIds.length} 项'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<_RelatedTodoRow> rows) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, color: scheme.error, size: 32),
              const SizedBox(height: 12),
              const Text('待办读取失败，当前选择没有应用'),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () =>
                    _loadPage(reset: true, loadSelectedTodos: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      final canLoadMore = _hasMore || _isLoadingMore || _loadMoreError != null;
      if (canLoadMore) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _searchController.text.trim().isEmpty
                      ? '没有可关联的待办'
                      : '当前页没有匹配项',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            _buildPageFooter(context, scheme),
          ],
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchController.text.trim().isEmpty ? '没有可关联的待办' : '没有匹配的待办',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final hasFooter = _hasMore || _isLoadingMore || _loadMoreError != null;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: rows.length + (hasFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        if (index == rows.length) return _buildPageFooter(context, scheme);
        final row = rows[index];
        final selected = _selectedIds.contains(row.id);
        final disabled = !row.canAdd && !selected;
        return Card(
          color: selected
              ? scheme.secondaryContainer.withValues(alpha: 0.55)
              : scheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            key: ValueKey('related-todo-${row.id}'),
            value: selected,
            onChanged: disabled
                ? null
                : (_) => _toggle(row.id, canAdd: row.canAdd),
            title: Text(
              row.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(row.subtitle),
            secondary: Icon(
              row.todo?.isDone == true
                  ? Icons.task_alt_rounded
                  : row.todo?.isSkipped == true
                  ? Icons.skip_next_rounded
                  : row.canAdd
                  ? Icons.checklist_rounded
                  : Icons.link_off_rounded,
              color: row.canAdd ? scheme.primary : scheme.onSurfaceVariant,
            ),
            controlAffinity: ListTileControlAffinity.trailing,
          ),
        );
      },
    );
  }

  Widget _buildPageFooter(BuildContext context, ColorScheme scheme) {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton.icon(
            onPressed: () => _loadPage(reset: false),
            icon: const Icon(Icons.refresh_rounded),
            label: Text('加载失败，重试', style: TextStyle(color: scheme.error)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: TextButton.icon(
          onPressed: () => _loadPage(reset: false),
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('加载更多待办'),
        ),
      ),
    );
  }
}

class _RelatedTodoRow {
  const _RelatedTodoRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.canAdd,
    required this.todo,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool canAdd;
  final TodoItem? todo;
}
