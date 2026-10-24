import 'package:flutter/material.dart';

import '../models.dart';
import '../storage_service.dart';
import '../utils/time_utils.dart';

/// Multi-select editor for the IDs stored in FixedScheduleItem.relatedTodoIds.
/// Changes stay local until the user taps Apply.
class FixedScheduleRelatedTodoPickerScreen extends StatefulWidget {
  const FixedScheduleRelatedTodoPickerScreen({
    super.key,
    required this.username,
    required this.teamUuid,
    required this.initialSelectedIds,
    this.loadTodos,
  });

  final String username;
  final String? teamUuid;
  final Set<String> initialSelectedIds;
  final Future<List<TodoItem>> Function(String username)? loadTodos;

  @override
  State<FixedScheduleRelatedTodoPickerScreen> createState() =>
      _FixedScheduleRelatedTodoPickerScreenState();
}

class _FixedScheduleRelatedTodoPickerScreenState
    extends State<FixedScheduleRelatedTodoPickerScreen> {
  late final TextEditingController _searchController;
  late Set<String> _selectedIds;
  List<TodoItem> _todos = [];
  bool _loading = true;
  Object? _loadError;

  String? get _normalizedTeamUuid {
    final value = widget.teamUuid?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
    _loadTodos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTodos() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final todos =
          await (widget.loadTodos ??
              StorageService.getTodosForFixedScheduleRelations)(
            widget.username,
          );
      if (!mounted) return;
      final byId = <String, TodoItem>{};
      for (final todo in todos) {
        if (todo.id.trim().isNotEmpty) byId[todo.id] = todo;
      }
      setState(() {
        _todos = byId.values.toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _todos = [];
        _loadError = error;
        _loading = false;
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
      } else if (canAdd) {
        _selectedIds.add(id);
      }
    });
  }

  List<_RelatedTodoRow> _rows() {
    final todosById = {for (final todo in _todos) todo.id: todo};
    final rows = <_RelatedTodoRow>[];
    final includedIds = <String>{};

    for (final todo in _todos) {
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
      final todo = todosById[id];
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

    rows.sort((left, right) {
      final leftSelected = _selectedIds.contains(left.id);
      final rightSelected = _selectedIds.contains(right.id);
      if (leftSelected != rightSelected) return leftSelected ? -1 : 1;
      return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    });

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
                    onChanged: (_) => setState(() {}),
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
                                setState(() {});
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
                onPressed: _loadTodos,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) {
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
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
