import 'package:flutter/material.dart';
import '../models.dart';
import '../storage_service.dart';
import 'package:intl/intl.dart';

class ConflictInboxScreen extends StatefulWidget {
  final String username;
  const ConflictInboxScreen({super.key, required this.username});

  @override
  State<ConflictInboxScreen> createState() => _ConflictInboxScreenState();
}

class _ConflictInboxScreenState extends State<ConflictInboxScreen> {
  List<TodoItem> _conflictTodos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    final todos = await StorageService.getTodos(widget.username);
    if (mounted) {
      setState(() {
        _conflictTodos = todos.where((t) => t.hasConflict).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('数据冲突对齐中心', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conflictTodos.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _conflictTodos.length,
                  itemBuilder: (context, index) {
                    final todo = _conflictTodos[index];
                    return _buildConflictCard(todo);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_rounded, size: 64, color: Colors.green.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text("所有数据已完全对齐", style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildConflictCard(TodoItem todo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(4)),
                  child: Text("版本争议", style: TextStyle(fontSize: 10, color: Colors.amber[900], fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(todo.updatedAt)),
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            Text(todo.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            if (todo.remark != null && todo.remark!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(todo.remark!, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    // TODO: 跳转至详细 Diff对比页
                  },
                  child: const Text("查看差异并解决", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
