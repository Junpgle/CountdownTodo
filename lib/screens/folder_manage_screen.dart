import 'package:flutter/material.dart';
import '../storage_service.dart';
import '../models.dart';
import 'package:intl/intl.dart';
import 'add_todo_screen.dart';

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
  _FolderManageScreenState createState() => _FolderManageScreenState();
}

class _FolderManageScreenState extends State<FolderManageScreen> {
  bool _inlineFolders = true;
  late List<TodoGroup> _groups;
  late List<TodoItem> _todos;

  @override
  void initState() {
    super.initState();
    _groups = List.from(widget.todoGroups);
    _todos = List.from(widget.allTodos);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final inline = await StorageService.getTodoFoldersInline();
    setState(() {
      _inlineFolders = inline;
    });
  }

  Future<void> _toggleInline(bool val) async {
    await StorageService.setTodoFoldersInline(val);
    setState(() {
      _inlineFolders = val;
    });
    // Call onGroupsChanged to trigger UI rebuild in parent
    widget.onGroupsChanged(_groups);
  }

  void _showCreateOrEditDialog([TodoGroup? existing]) {
    final TextEditingController ctrl = TextEditingController(text: existing?.name ?? "");
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(existing == null ? '新建文件夹' : '修改文件夹名称'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入文件夹名称',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final txt = ctrl.text.trim();
                if (txt.isNotEmpty) {
                  Navigator.pop(ctx);
                  if (existing == null) {
                    final newGroup = TodoGroup(name: txt);
                    setState(() {
                      _groups.insert(0, newGroup);
                    });
                    StorageService.saveTodoGroups(widget.username, _groups);
                    widget.onGroupsChanged(_groups);
                  } else {
                    setState(() {
                      existing.name = txt;
                      existing.markAsChanged();
                    });
                    StorageService.saveTodoGroups(widget.username, _groups);
                    widget.onGroupsChanged(_groups);
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _deleteGroup(TodoGroup g) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散文件夹？'),
        content: Text('要删除文件夹 "${g.name}" 吗？其内部的待办会恢复成独立待办。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
              await StorageService.deleteTodoGroupGlobally(widget.username, g.id);
              widget.onGroupsChanged(_groups);
              widget.onTodosChanged(_todos);
            },
            child: const Text('确认删除', style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );
  }

  void _showAddTodoToFolderDialog(TodoGroup g) {
    // 找出所有未分类的待办
    final unassigned = _todos.where((t) => t.groupId == null && !t.isDeleted).toList();
    
    if (unassigned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有待分配的独立待办')));
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
      if (a.dueDate != null && b.dueDate != null) return a.dueDate!.compareTo(b.dueDate!);
      if (a.dueDate != null) return -1;
      if (b.dueDate != null) return 1;
      return 0;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text('移动至此文件夹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: unassigned.length,
                  itemBuilder: (context, index) {
                    final t = unassigned[index];
                    final startStr = t.createdDate != null ? DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(t.createdDate!)) : null;
                    final dueStr = t.dueDate != null ? DateFormat('MM-dd HH:mm').format(t.dueDate!) : null;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Icon(t.isDone ? Icons.check_circle : Icons.circle_outlined, 
                          color: t.isDone ? Colors.green : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                        title: Text(t.title, style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: t.isDone ? Colors.grey : null,
                          decoration: t.isDone ? TextDecoration.lineThrough : null,
                        )),
                        subtitle: (startStr != null || dueStr != null) 
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                "${startStr ?? '开始?'} → ${dueStr ?? '截止?'}",
                                style: TextStyle(fontSize: 11, color: t.isDone ? Colors.grey : Colors.blueGrey),
                              ),
                            )
                          : null,
                        onTap: () {
                          setState(() {
                            t.groupId = g.id;
                            t.version += 10;
                            t.updatedAt = DateTime.now().millisecondsSinceEpoch;
                          });
                          widget.onTodosChanged(_todos);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateTodoInFolderScreen(TodoGroup g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => AddTodoScreen(
          todoGroups: _groups,
          initialGroupId: g.id,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件夹管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateOrEditDialog(),
          ),
        ],
      ),
      body: ListView(
        children: [
          // Setting Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: const Text('文件夹与待办在一起混合排序', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('关闭后，文件夹将被提取出主列表并置顶独立排列。'),
                value: _inlineFolders,
                onChanged: _toggleInline,
              ),
            ),
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
            child: Text('所有文件夹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
          ),
          
          if (_groups.where((g) => !g.isDeleted).isEmpty)
             const Padding(
               padding: EdgeInsets.all(32.0),
               child: Center(child: Text("暂无文件夹")),
             ),

          ..._groups.where((g) => !g.isDeleted).map((g) {
            final gTodos = _todos.where((t) => t.groupId == g.id && !t.isDeleted).toList();
            return Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(Icons.folder, color: Colors.amber),
                title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${gTodos.length} 条待办 · 创建于 ${DateFormat('MM-dd').format(DateTime.fromMillisecondsSinceEpoch(g.createdAt))}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showCreateOrEditDialog(g)),
                    IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent), onPressed: () => _deleteGroup(g)),
                  ],
                ),
                children: [
                  ...gTodos.map((t) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 48, right: 16),
                    leading: Icon(t.isDone ? Icons.check_circle : Icons.circle_outlined, size: 18, 
                      color: t.isDone ? Colors.green : Colors.grey),
                    title: Text(t.title, style: TextStyle(
                      color: t.isDone ? Colors.grey : null,
                      decoration: t.isDone ? TextDecoration.lineThrough : null,
                    )),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.orange),
                      onPressed: () => _removeTodoFromFolder(t),
                      tooltip: '移出文件夹',
                    ),
                  )),
                  Padding(
                    padding: const EdgeInsets.only(left: 48, bottom: 12, top: 4),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        // 🚀 已优化：直接打开完整的添加页面
                        InkWell(
                          onTap: () => _showCreateTodoInFolderScreen(g),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, size: 16, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 4),
                                Text('创建新待办', style: TextStyle(
                                  fontSize: 13, 
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                )),
                              ],
                            ),
                          ),
                        ),
                        // 原有：移动独立待办
                        InkWell(
                          onTap: () => _showAddTodoToFolderDialog(g),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.drive_file_move_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 4),
                                Text('添加独立待办至此', style: TextStyle(
                                  fontSize: 13, 
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                )),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
