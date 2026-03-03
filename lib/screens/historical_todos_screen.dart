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

class _HistoricalTodosScreenState extends State<HistoricalTodosScreen> {
  List<TodoItem> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 判断是否属于历史待办（已完成 且 过了截止日期 / 无截止日期的早前待办）
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
    setState(() {
      _history = allTodos.where((t) => _isHistorical(t)).toList();
      _history.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated)); // 最近更新的在最上面
      _isLoading = false;
    });
  }

  Future<void> _deleteItem(TodoItem item) async {
    setState(() => _history.remove(item));
    final allTodos = await StorageService.getTodos(widget.username);
    allTodos.removeWhere((t) => t.id == item.id);
    await StorageService.saveTodos(widget.username, allTodos);
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
    _loadData(); // 重新加载，该项会被移出历史并回到主页
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('待办已取消完成，并退回主页清单')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史待办')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? const Center(child: Text("暂无历史待办", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
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
      ),
    );
  }
}