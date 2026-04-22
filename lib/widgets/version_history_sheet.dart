import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class VersionHistorySheet extends StatefulWidget {
  final String uuid;
  final String table;
  final String title;

  const VersionHistorySheet({
    super.key,
    required this.uuid,
    required this.table,
    required this.title,
  });

  static void show(BuildContext context, String uuid, String table, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VersionHistorySheet(uuid: uuid, table: table, title: title),
    );
  }

  @override
  State<VersionHistorySheet> createState() => _VersionHistorySheetState();
}

class _VersionHistorySheetState extends State<VersionHistorySheet> {
  List<dynamic> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await ApiService.fetchItemHistory(widget.uuid, widget.table);
    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRollback(int logId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认回滚'),
        content: const Text('确定要将该项恢复至此历史版本吗？回滚操作将同步至所有设备。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认回滚')),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await ApiService.rollbackItem(logId);
      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已成功回滚版本'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('回滚失败: ${res['error']}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.history, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('版本记录', style: Theme.of(context).textTheme.titleLarge),
                          Text(widget.title, 
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadHistory,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _history.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _history.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = _history[index];
                              return _buildHistoryItem(item);
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text('暂无修改记录', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(dynamic item) {
    final colorScheme = Theme.of(context).colorScheme;
    final timestamp = DateTime.fromMillisecondsSinceEpoch(item['timestamp']);
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
    final opType = item['op_type'];
    final operator = item['operator_name'] ?? '系统';

    Color opColor;
    IconData opIcon;
    switch (opType) {
      case 'INSERT':
        opColor = Colors.green;
        opIcon = Icons.add_circle_outline;
        break;
      case 'UPDATE':
        opColor = Colors.blue;
        opIcon = Icons.edit_note;
        break;
      case 'ROLLBACK':
        opColor = Colors.orange;
        opIcon = Icons.restore;
        break;
      default:
        opColor = Colors.grey;
        opIcon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(opIcon, size: 16, color: opColor),
              const SizedBox(width: 8),
              Text(opType, style: TextStyle(color: opColor, fontWeight: FontWeight.bold, fontSize: 12)),
              const Spacer(),
              Text(timeStr, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(operator.substring(0, 1), style: TextStyle(fontSize: 10, color: colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 8),
              Text(operator, style: const TextStyle(fontWeight: FontWeight.w500)),
              const Spacer(),
              if (opType != 'INSERT' && index != 0) // 第一个记录或新增记录通常不回滚
                TextButton.icon(
                  onPressed: () => _handleRollback(item['id']),
                  icon: const Icon(Icons.settings_backup_restore, size: 14),
                  label: const Text('还原此版本', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          if (item['after_data'] != null) ...[
            const SizedBox(height: 8),
            _buildDataDiff(item['before_data'], item['after_data']),
          ],
        ],
      ),
    );
  }

  Widget _buildDataDiff(dynamic before, dynamic after) {
    if (after == null) return const SizedBox();
    
    // 提取关键变化（如标题、状态）
    final List<Widget> changes = [];
    
    void addChange(String label, dynamic bVal, dynamic aVal) {
      if (bVal != aVal) {
        changes.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text('$bVal', style: const TextStyle(fontSize: 12, decoration: TextDecoration.lineThrough)),
              const Icon(Icons.arrow_right_alt, size: 14, color: Colors.grey),
              Text('$aVal', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ));
      }
    }

    if (widget.table == 'todos') {
      addChange('内容', before?['content'] ?? '空', after['content']);
      if (before?['is_completed'] != after['is_completed']) {
        addChange('状态', (before?['is_completed'] == 1) ? '已完成' : '待办', (after['is_completed'] == 1) ? '已完成' : '待办');
      }
    } else if (widget.table == 'countdowns') {
      addChange('标题', before?['title'] ?? '空', after['title']);
    }

    if (changes.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16),
        ...changes,
      ],
    );
  }
  
  int get index => _history.indexOf(_history.firstWhere((element) => true)); // Helper to find index in itemBuilder
}
