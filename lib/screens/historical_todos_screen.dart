import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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

  // 判断是否属于历史待办
  bool _isHistorical(TodoItem t) {
    if (!t.isDone) return false;
    DateTime today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);

    if (t.dueDate != null) {
      DateTime d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return d.isBefore(today);
    } else {
      DateTime c = DateTime(t.createdAt.year, t.createdAt.month, t.createdAt.day);
      return c.isBefore(today);
    }
  }

  Future<void> _loadData() async {
    final allTodos = await StorageService.getTodos(widget.username);

    // 独立读取回收站数据
    final prefs = await SharedPreferences.getInstance();
    final String key = 'deleted_todos_${widget.username}';
    final String? deletedStr = prefs.getString(key);
    List<TodoItem> deleted = [];
    if (deletedStr != null) {
      try {
        Iterable decoded = jsonDecode(deletedStr);
        deleted = decoded.map((e) => TodoItem.fromJson(e)).toList();
      } catch (e) {
        debugPrint("解析回收站数据失败: $e");
      }
    }

    setState(() {
      _history = allTodos.where((t) => _isHistorical(t)).toList();
      _history.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

      _deletedTodos = deleted;
      _deletedTodos.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

      _isLoading = false;
    });
  }

  Future<void> _saveDeletedTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String key = 'deleted_todos_${widget.username}';
    final String encoded = jsonEncode(_deletedTodos.map((e) => e.toJson()).toList());
    await prefs.setString(key, encoded);
  }

  Future<void> _deleteItem(TodoItem item) async {
    // 从当前列表移除
    setState(() => _history.remove(item));

    // 从主数据库彻底移除
    final allTodos = await StorageService.getTodos(widget.username);
    allTodos.removeWhere((t) => t.id == item.id);
    await StorageService.saveTodos(widget.username, allTodos);

    // 🚀 核心：移入回收站
    item.lastUpdated = DateTime.now(); // 记录被删除的时间
    setState(() => _deletedTodos.insert(0, item));
    await _saveDeletedTodos();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移至回收站')));
    }
  }

  Future<void> _uncheckItem(TodoItem item) async {
    item.isDone = false;
    item.lastUpdated = DateTime.now();

    final allTodos = await StorageService.getTodos(widget.username);
    int idx = allTodos.indexWhere((t) => t.id == item.id);
    if (idx != -1) {
      allTodos[idx] = item;
      await StorageService.saveTodos(widget.username, allTodos);
    }
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('待办已取消完成，并退回主页清单')));
    }
  }

  // 🚀 从回收站恢复
  Future<void> _restoreDeletedItem(TodoItem item) async {
    setState(() => _deletedTodos.remove(item));
    await _saveDeletedTodos();

    final allTodos = await StorageService.getTodos(widget.username);
    allTodos.add(item);
    await StorageService.saveTodos(widget.username, allTodos);

    _loadData(); // 重新加载分类数据

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('待办已成功恢复')));
    }
  }

  // 🚀 从回收站彻底删除
  Future<void> _permanentlyDeleteItem(TodoItem item) async {
    setState(() => _deletedTodos.remove(item));
    await _saveDeletedTodos();
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
      setState(() => _deletedTodos.clear());
      await _saveDeletedTodos();
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
              "完成于: ${DateFormat('yyyy-MM-dd HH:mm').format(todo.lastUpdated)}",
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
                    "删除于: ${DateFormat('yyyy-MM-dd HH:mm').format(todo.lastUpdated)}",
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