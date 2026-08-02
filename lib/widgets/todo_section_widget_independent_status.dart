part of 'todo_section_widget.dart';

/// 🚀 新增：独立任务状态弹窗组件，带局部刷新逻辑，提升网络不佳时的体验
class _IndependentStatusDialog extends StatefulWidget {
  final TodoItem todo;
  const _IndependentStatusDialog({required this.todo});

  @override
  State<_IndependentStatusDialog> createState() =>
      _IndependentStatusDialogState();
}

class _IndependentStatusDialogState extends State<_IndependentStatusDialog> {
  bool _isLoading = true;
  List<dynamic> _statusList = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getTodoStatus(widget.todo.id);
      if (mounted) {
        setState(() {
          _statusList = res['data'] ?? res['status'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("任务进度: ${widget.todo.title}"),
      content: SizedBox(
        width: double.maxFinite,
        height: 350,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null
                ? Center(child: Text("加载失败: $_error"))
                : (_statusList.isEmpty
                    ? const Center(child: Text("暂无成员进度数据"))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _statusList.length,
                        itemBuilder: (context, index) {
                          final s = _statusList[index];
                          final isDone = s['is_completed'] == 1;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isDone
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.1),
                              child: Text(
                                (s['username'] as String?)?.isNotEmpty == true
                                    ? s['username'][0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                    color: isDone ? Colors.green : Colors.grey),
                              ),
                            ),
                            title: Text(s['username']?.toString() ?? '未知用户',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              isDone ? "已完成" : "进行中",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDone ? Colors.green : Colors.grey),
                            ),
                            trailing: Icon(
                              isDone
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                              color: isDone ? Colors.green : Colors.grey,
                            ),
                          );
                        },
                      ))),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text("关闭")),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
