import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../storage_service.dart';

class HistoricalTodosScreen extends StatefulWidget {
  final String username;
  const HistoricalTodosScreen({Key? key, required this.username}) : super(key: key);

  @override
  State<HistoricalTodosScreen> createState() => _HistoricalTodosScreenState();
}

class _HistoricalTodosScreenState extends State<HistoricalTodosScreen> with SingleTickerProviderStateMixin {
  List<TodoItem> _history = [];
  List<TodoItem> _deletedTodos = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 判断是否属于历史待办 (只有已完成且在今天之前的，才算历史)
  bool _isHistorical(TodoItem t) {
    if (!t.isDone) return false;
    DateTime today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);

    if (t.dueDate != null) {
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return d.isBefore(today);
    } else {
      // 🚀 修复：createdAt 现在是 int 毫秒时间戳，需要先转换为 DateTime
      // 🚀 修正：优先使用 createdDate，兼容旧数据 fallback 到 createdAt
      DateTime cDate = DateTime.fromMillisecondsSinceEpoch(t.createdDate ?? t.createdAt);
      DateTime c = DateTime(cDate.year, cDate.month, cDate.day);
      return c.isBefore(today);
    }
  }

  // 🚀 核心重构：回收站直接源于全局列表的逻辑删除标记
  Future<void> _loadData() async {
    final allTodos = await StorageService.getTodos(widget.username);

    setState(() {
      // 历史记录：已完成、是历史日期，并且【未被删除】
      _history = allTodos.where((t) => _isHistorical(t) && !t.isDeleted).toList();
      // 🚀 修复：使用 updatedAt 进行排序
      _history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // 回收站：直接筛选逻辑删除的数据
      _deletedTodos = allTodos.where((t) => t.isDeleted).toList();
      // 🚀 修复：使用 updatedAt 进行排序
      _deletedTodos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _isLoading = false;
    });
  }

  Future<void> _deleteItem(TodoItem item) async {
    try {
      // 1️⃣ 先调用服务器逻辑删除
      await StorageService.deleteTodoGlobally(widget.username, item.id);

      // 2️⃣ 本地标记删除
      final allTodos = await StorageService.getTodos(widget.username);
      final index = allTodos.indexWhere((t) => t.id == item.id);

      if (index != -1) {
        allTodos[index].isDeleted = true;
        allTodos[index].markAsChanged(); // 更新 updatedAt

        await StorageService.saveTodos(widget.username, allTodos, sync: true);
      }

      // 3️⃣ 更新 UI
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
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('待办已取消完成，并退回主页清单')));
    }
  }

  // 🚀 从回收站恢复 (取消逻辑删除标记)
  Future<void> _restoreDeletedItem(TodoItem item) async {
    final allTodos = await StorageService.getTodos(widget.username);
    int idx = allTodos.indexWhere((t) => t.id == item.id);
    if (idx != -1) {
      allTodos[idx].isDeleted = false; // 取消删除标记
      allTodos[idx].markAsChanged();   // 升级版本号
      await StorageService.saveTodos(widget.username, allTodos, sync: true); // 触发同步，让云端也恢复
    }

    _loadData(); // 重新加载分类数据

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('待办已成功恢复')));
    }
  }

  // 🚀 从回收站彻底删除 (本地物理删除)
  Future<void> _permanentlyDeleteItem(TodoItem item) async {
    final allTodos = await StorageService.getTodos(widget.username);
    allTodos.removeWhere((t) => t.id == item.id);
    // 物理删除不需要同步，因为远端已经是 isDeleted = 1 状态
    await StorageService.saveTodos(widget.username, allTodos, sync: false);

    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已彻底删除')));
    }
  }

  // 🚀 一键清空回收站
  Future<void> _clearRecycleBin() async {
    bool confirm = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("清空回收站"),
          content: const Text("确定要彻底清空回收站吗？清空后将无法恢复。"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("取消")),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("清空")
            ),
          ],
        )
    ) ?? false;

    if (confirm) {
      final allTodos = await StorageService.getTodos(widget.username);
      allTodos.removeWhere((t) => t.isDeleted);
      await StorageService.saveTodos(widget.username, allTodos, sync: false);
      _loadData();
    }
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return const Center(child: Text("暂无历史待办", style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final todo = _history[index];
        return Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Checkbox(
              value: todo.isDone,
              onChanged: (val) => _uncheckItem(todo),
            ),
            title: Text(
              todo.title,
              style: TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            subtitle: Text(
              "完成于: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.updatedAt))}",
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _deleteItem(todo),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecycleBinTab() {
    if (_deletedTodos.isEmpty) {
      return const Center(child: Text("回收站为空", style: TextStyle(color: Colors.grey)));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("共 ${_deletedTodos.length} 条已删除待办", style: const TextStyle(color: Colors.grey, fontSize: 13)),
              TextButton.icon(
                  onPressed: _clearRecycleBin,
                  icon: const Icon(Icons.delete_sweep, size: 18, color: Colors.redAccent),
                  label: const Text("清空", style: TextStyle(color: Colors.redAccent))
              )
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _deletedTodos.length,
            itemBuilder: (context, index) {
              final todo = _deletedTodos[index];
              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(todo.title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  subtitle: Text(
                    "删除于: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.updatedAt))}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: "恢复",
                        icon: const Icon(Icons.restore, color: Colors.green),
                        onPressed: () => _restoreDeletedItem(todo),
                      ),
                      IconButton(
                        tooltip: "彻底删除",
                        icon: const Icon(Icons.close, color: Colors.redAccent),
                        onPressed: () => _permanentlyDeleteItem(todo),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史与回收站'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '历史待办'),
            Tab(text: '回收站'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryTab(),
          _buildRecycleBinTab(),
        ],
      ),
    );
  }
}