import 'package:flutter/material.dart';
import '../storage_service.dart';
import '../models.dart';
import 'package:intl/intl.dart';
import 'add_todo_screen.dart';
import '../utils/page_transitions.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/management_page.dart';
import '../utils/app_dialogs.dart';
import '../widgets/optional_liquid_glass_surface.dart';

class FolderManageScreen extends StatefulWidget {
  final String username;
  final List<TodoGroup> todoGroups;
  final ValueChanged<List<TodoGroup>> onGroupsChanged;

  final List<TodoItem> allTodos;
  final ValueChanged<List<TodoItem>> onTodosChanged;

  const FolderManageScreen({
    super.key,
    required this.username,
    required this.todoGroups,
    required this.onGroupsChanged,
    required this.allTodos,
    required this.onTodosChanged,
  });

  @override
  State<FolderManageScreen> createState() => _FolderManageScreenState();
}

class _FolderManageScreenState extends State<FolderManageScreen> {
  String _folderDisplayMode = 'inline';
  late List<TodoGroup> _groups;
  late List<TodoItem> _todos;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _groups = List.from(widget.todoGroups);
    _todos = List.from(widget.allTodos);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mode = await StorageService.getTodoFolderDisplayMode();
    if (!mounted) return;
    setState(() {
      _folderDisplayMode = mode;
    });
  }

  Future<void> _setFolderDisplayMode(String mode) async {
    await StorageService.setTodoFolderDisplayMode(mode);
    await StorageService.setTodoFoldersInline(mode != 'separate');
    if (!mounted) return;
    setState(() {
      _folderDisplayMode = mode;
    });
    widget.onGroupsChanged(_groups);
  }

  String _folderModeLabel(String mode) {
    switch (mode) {
      case 'inline':
        return '时间线内展开文件夹';
      case 'separate':
        return '文件夹单独显示';
      case 'urgentFirst':
        return '每个文件夹只展开最紧急待办';
      case 'hidden':
        return '不展示文件夹';
      default:
        return mode;
    }
  }

  String _folderModeSubtitle(String mode) {
    switch (mode) {
      case 'inline':
        return '文件夹与独立待办在主时间线一起排序展示';
      case 'separate':
        return '文件夹与独立待办分区展示，方便集中查看';
      case 'urgentFirst':
        return '文件夹卡片只展开 1 条最紧急未完成待办';
      case 'hidden':
        return '首页待办清单隐藏所有文件夹内容';
      default:
        return '';
    }
  }

  Future<void> _showCreateOrEditDialog([TodoGroup? existing]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FolderNameDialog(initialName: existing?.name),
    );
    if (name == null || !mounted) return;
    setState(() {
      if (existing == null) {
        _groups.insert(0, TodoGroup(name: name));
      } else {
        existing.name = name;
        existing.markAsChanged();
      }
      _searchController.clear();
    });
    StorageService.saveTodoGroups(widget.username, _groups);
    widget.onGroupsChanged(_groups);
  }

  void _deleteGroup(TodoGroup g) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散文件夹？'),
        content: Text('要删除文件夹 "${g.name}" 吗？其内部的待办会恢复成独立待办。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                final idx = _groups.indexWhere((x) => x.id == g.id);
                if (idx != -1) {
                  _groups[idx].isDeleted = true;
                  _groups[idx].markAsChanged();
                }
                // 同时更新本地 todos 状态
                for (var t in _todos) {
                  if (t.groupId == g.id) {
                    t.groupId = null;
                    t.version += 10;
                    t.updatedAt = DateTime.now().millisecondsSinceEpoch;
                  }
                }
              });
              await StorageService.deleteTodoGroupGlobally(
                  widget.username, g.id);
              widget.onGroupsChanged(_groups);
              widget.onTodosChanged(_todos);
            },
            child: Text('解散文件夹',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          )
        ],
      ),
    );
  }

  void _showAddTodoToFolderDialog(TodoGroup g) {
    // 找出所有未分类的待办
    final unassigned =
        _todos.where((t) => t.groupId == null && !t.isDeleted).toList();

    if (unassigned.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有待分配的独立待办')));
      return;
    }

    // 🚀 按照紧急程度排序
    unassigned.sort((a, b) {
      // 1. 未完成优先
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;

      // 2. 进度比较
      double getProgress(TodoItem t) {
        if (t.isDone) return 0.0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final start = t.createdDate ?? t.createdAt;
        final end = t.dueDate?.millisecondsSinceEpoch;
        if (end == null || end <= start) return 0.0;
        if (now >= end) return 1.0;
        if (now <= start) return 0.0;
        return (now - start) / (end - start);
      }

      final progressA = getProgress(a);
      final progressB = getProgress(b);
      if (progressA != progressB) return progressB.compareTo(progressA);

      // 3. 截止日期比较
      if (a.dueDate != null && b.dueDate != null) {
        return a.dueDate!.compareTo(b.dueDate!);
      }
      if (a.dueDate != null) return -1;
      if (b.dueDate != null) return 1;
      return 0;
    });

    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: OptionalLiquidGlassSheet(
            topRadius: 24,
            fallbackDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2))),
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('移动至此文件夹',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: unassigned.length,
                    itemBuilder: (context, index) {
                      final t = unassigned[index];
                      final startStr = t.createdDate != null
                          ? DateFormat('MM-dd HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  t.createdDate!))
                          : null;
                      final dueStr = t.dueDate != null
                          ? DateFormat('MM-dd HH:mm').format(t.dueDate!)
                          : null;

                      return OptionalLiquidGlassCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        borderRadius: 16,
                        fallbackDecoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: Icon(
                                t.isDone
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: t.isDone
                                    ? Colors.green
                                    : Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.5)),
                            title: Text(t.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: t.isDone ? Colors.grey : null,
                                  decoration: t.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                )),
                            subtitle: (startStr != null || dueStr != null)
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      "${startStr ?? '开始?'} → ${dueStr ?? '截止?'}",
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: t.isDone
                                              ? Colors.grey
                                              : Colors.blueGrey),
                                    ),
                                  )
                                : null,
                            onTap: () {
                              setState(() {
                                t.groupId = g.id;
                                t.version += 10;
                                t.updatedAt =
                                    DateTime.now().millisecondsSinceEpoch;
                              });
                              widget.onTodosChanged(_todos);
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateTodoInFolderScreen(TodoGroup g) {
    Navigator.of(context).push(
      PageTransitions.material(
        builder: (ctx) => AddTodoScreen(
          todoGroups: _groups,
          initialGroupId: g.id,
          onFixedScheduleAdded: (item) => StorageService.saveFixedSchedules(
            widget.username,
            [item],
          ),
          onTodoAdded: (todo) {
            setState(() {
              _todos.add(todo);
            });
            widget.onTodosChanged(_todos);
          },
          onTodosBatchAdded: (todos) {
            setState(() {
              _todos.addAll(todos);
            });
            widget.onTodosChanged(_todos);
          },
        ),
      ),
    );
  }

  void _removeTodoFromFolder(TodoItem t) {
    setState(() {
      t.groupId = null;
      t.version += 10;
      t.updatedAt = DateTime.now().millisecondsSinceEpoch;
    });
    widget.onTodosChanged(_todos);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = _groups.where((g) => !g.isDeleted).toList();
    final query = _searchController.text.trim().toLowerCase();
    final visible =
        active.where((g) => g.name.toLowerCase().contains(query)).toList();
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('文件夹管理'),
      ),
      body: ManagementPage(children: [
        const ManagementIntro(
            icon: Icons.folder_copy_outlined,
            title: '给待办一个位置',
            description: '按项目或生活场景整理待办，展开文件夹即可管理其中的任务。'),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainerLow,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ExpansionTile(
            shape: const Border(),
            leading: Icon(Icons.view_quilt_outlined, color: scheme.primary),
            title: const Text('首页展示方式'),
            subtitle: Text(_folderModeLabel(_folderDisplayMode)),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: [
              RadioGroup<String>(
                groupValue: _folderDisplayMode,
                onChanged: (value) {
                  if (value != null) _setFolderDisplayMode(value);
                },
                child: Column(
                    children: ['inline', 'separate', 'urgentFirst', 'hidden']
                        .map((mode) => RadioListTile<String>(
                              value: mode,
                              title: Text(_folderModeLabel(mode)),
                              subtitle: Text(_folderModeSubtitle(mode)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ))
                        .toList()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text('我的文件夹 · ${active.length}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              FilledButton.icon(
                  onPressed: () => _showCreateOrEditDialog(),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('新建文件夹')),
            ]),
        const SizedBox(height: 16),
        ManagementSearchField(
            controller: _searchController,
            hintText: '搜索文件夹名称',
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          ManagementEmptyState(
              icon: Icons.folder_open_rounded,
              title: query.isEmpty ? '暂无文件夹' : '没有找到匹配的文件夹',
              description:
                  query.isEmpty ? '新建一个文件夹，把相关待办放在一起。' : '试试其他名称，或清空搜索。'),
        ...visible.map((g) => _buildFolder(g, scheme)),
      ]),
    );
  }

  Widget _buildFolder(TodoGroup g, ColorScheme scheme) {
    final todos =
        _todos.where((t) => t.groupId == g.id && !t.isDeleted).toList();
    final pending = todos.where((t) => !t.isDone).length;
    return ManagementCard(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('folder-${g.id}'),
        shape: const Border(),
        leading: Icon(Icons.folder_outlined, color: scheme.primary),
        title:
            Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$pending 条待完成 · ${todos.length - pending} 条已完成'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          ManagementActionBar(
              alignment: WrapAlignment.start,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                    onPressed: () => _showCreateOrEditDialog(g),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('重命名')),
                TextButton.icon(
                    onPressed: () => _deleteGroup(g),
                    icon: const Icon(Icons.folder_delete_outlined, size: 18),
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    label: const Text('解散文件夹')),
              ]),
          if (todos.isEmpty)
            Padding(
                padding: const EdgeInsets.all(20),
                child: Text('文件夹还是空的，添加第一条待办吧。',
                    style: TextStyle(color: scheme.onSurfaceVariant))),
          ...todos.map((t) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(
                    t.isDone
                        ? Icons.check_circle_outline
                        : Icons.circle_outlined,
                    size: 20,
                    color: t.isDone ? scheme.primary : scheme.onSurfaceVariant),
                title: Text(t.title,
                    style: TextStyle(
                        color: t.isDone ? scheme.onSurfaceVariant : null,
                        decoration:
                            t.isDone ? TextDecoration.lineThrough : null)),
                trailing: IconButton(
                    tooltip: '移出文件夹',
                    onPressed: () => _removeTodoFromFolder(t),
                    icon: const Icon(Icons.drive_file_move_outlined, size: 20)),
              )),
          const SizedBox(height: 8),
          ManagementActionBar(alignment: WrapAlignment.start, children: [
            FilledButton.tonalIcon(
                onPressed: () => _showCreateTodoInFolderScreen(g),
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建待办')),
            OutlinedButton.icon(
                onPressed: () => _showAddTodoToFolderDialog(g),
                icon: const Icon(Icons.drive_file_move_outlined),
                label: const Text('移入独立待办')),
          ]),
        ],
      ),
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({this.initialName});
  final String? initialName;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _controller =
      TextEditingController(text: widget.initialName ?? '');
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    setState(() => _invalid = name.isEmpty);
    if (!_invalid) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.folder_outlined),
        title: Text(widget.initialName == null ? '新建文件夹' : '修改文件夹名称'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_invalid) setState(() => _invalid = false);
          },
          decoration: InputDecoration(
              labelText: '文件夹名称',
              hintText: '例如：工作项目、生活计划',
              errorText: _invalid ? '请输入文件夹名称' : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(onPressed: _submit, child: const Text('保存')),
        ],
      );
}
