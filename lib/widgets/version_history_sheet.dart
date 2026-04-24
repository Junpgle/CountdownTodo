import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../storage_service.dart';

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

class _VersionHistorySheetState extends State<VersionHistorySheet>
    with SingleTickerProviderStateMixin {
  List<dynamic> _history = [];
  bool _isLoading = true;
  late final TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      if (_currentTabIndex != _tabController.index) {
        setState(() => _currentTabIndex = _tabController.index);
      }
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  Future<void> _handleRollback(dynamic logId, {bool isLocal = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isLocal ? '确认本地回滚' : '确认云端回滚'),
        content: Text(isLocal ? '确定要恢复至本地暂存的此版本吗？' : '确定要将该项恢复至此历史版本吗？回滚操作将同步至所有设备。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认回滚')),
        ],
      ),
    );

    if (confirmed == true) {
      final username = await StorageService.getCurrentUsername();
      final res = await ApiService.rollbackItem(
        logId, 
        isLocal: isLocal,
        table: widget.table,
        username: username,
      );

      if (res['success'] == true) {
        // 🚀 Uni-Sync 4.0: 回滚成功后立即触发本地刷新与同步
        if (username != null) {
          await StorageService.syncData(username);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? '已成功回滚版本'), backgroundColor: Colors.green),
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
    final localHistory = _history.where((item) => item['is_local'] == true).toList();
    final cloudHistory = _history.where((item) => item['is_local'] != true).toList();

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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: '本地 (${localHistory.length})'),
                    Tab(text: '云端 (${cloudHistory.length})'),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildHistoryList(
                            history: localHistory,
                            emptyLabel: '暂无本地修改记录',
                            scrollController: _currentTabIndex == 0 ? scrollController : null,
                          ),
                          _buildHistoryList(
                            history: cloudHistory,
                            emptyLabel: '暂无云端修改记录',
                            scrollController: _currentTabIndex == 1 ? scrollController : null,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState([String message = '暂无修改记录']) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildHistoryList({
    required List<dynamic> history,
    required String emptyLabel,
    ScrollController? scrollController,
  }) {
    if (history.isEmpty) {
      return _buildEmptyState(emptyLabel);
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = history[index];
        return _buildHistoryItem(item, index);
      },
    );
  }

  Widget _buildHistoryItem(dynamic item, int index) {
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
              if (item['is_local'] == true)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('本地', style: TextStyle(fontSize: 9, color: colorScheme.onSecondaryContainer)),
                ),
              const Spacer(),
              // 🚀 核心修复：只有非第一项（非当前最新版）才显示还原按钮
              if (index != 0) 
                TextButton.icon(
                  onPressed: () => _handleRollback(item['id'], isLocal: item['is_local'] == true),
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
    
    final List<Widget> changes = [];
    
    String formatTime(dynamic val) {
      if (val == null || val == 0) return '无';
      try {
        final dt = DateTime.fromMillisecondsSinceEpoch(val is String ? int.parse(val) : val);
        return DateFormat('MM-dd HH:mm').format(dt);
      } catch (_) { return val.toString(); }
    }

    String getRecurrenceName(int index) {
      const names = ['不重复', '每天', '自定义天数', '每周', '每月', '每年', '工作日'];
      if (index >= 0 && index < names.length) return names[index];
      return '未知';
    }
    
    void addChange(String label, dynamic bVal, dynamic aVal, {String Function(dynamic, dynamic)? contextFormatter}) {
      final formattedB = contextFormatter != null ? contextFormatter(bVal, before) : (bVal?.toString() ?? '无');
      final formattedA = contextFormatter != null ? contextFormatter(aVal, after) : (aVal?.toString() ?? '无');

      if (formattedB != formattedA) {
        changes.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(formattedB, 
                      style: const TextStyle(fontSize: 12, decoration: TextDecoration.lineThrough, color: Colors.grey),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const Icon(Icons.arrow_right_alt, size: 14, color: Colors.grey),
                  Expanded(
                    child: Text(formattedA, 
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
          ),
        ));
      }
    }

    if (widget.table == 'todos') {
      addChange('内容', before?['content'], after['content']);
      addChange('备注', before?['remark'], after['remark']);
      addChange('截止时间', before?['due_date'], after['due_date'], contextFormatter: (v, ctx) => formatTime(v));
      addChange('开始时间', before?['created_date'], after['created_date'], contextFormatter: (v, ctx) => formatTime(v));
      addChange('重复规则', before?['recurrence'] ?? 0, after['recurrence'] ?? 0, contextFormatter: (v, ctx) => getRecurrenceName(v as int));
      addChange('全天事件', before?['is_all_day'] ?? 0, after['is_all_day'] ?? 0, contextFormatter: (v, ctx) => v == 1 ? '是' : '否');
      
      // 🚀 新增：显示循环截止时间的变更
      addChange('循环截止时间', before?['recurrence_end_date'], after['recurrence_end_date'], 
        contextFormatter: (v, ctx) => formatTime(v));
      
      // 🚀 新增：显示自定义循环间隔的变更
      addChange('循环间隔', before?['custom_interval_days'], after['custom_interval_days'], 
        contextFormatter: (v, ctx) => v == null ? '无' : '每$v天');
      
      // 🚀 新增：显示提醒时间的变更
      addChange('提醒时间', before?['reminder_minutes'] ?? -1, after['reminder_minutes'] ?? -1, 
        contextFormatter: (v, ctx) {
          if (v == null || v == -1) return '无';
          return '提前$v分钟';
        });
      
      // 🚀 优化：使用 context 准确获取对应快照中的名称
      addChange('文件夹', before?['group_id'], after['group_id'], 
        contextFormatter: (v, ctx) => (v == null || v == '') ? '未分组' : (ctx?['group_name'] ?? v.toString()));
      
      addChange('团队归属', before?['team_uuid'], after['team_uuid'], 
        contextFormatter: (v, ctx) => (v == null || v == '') ? '个人' : (ctx?['team_name'] ?? v.toString()));
        
      addChange('协作方式', before?['collab_type'] ?? 0, after['collab_type'] ?? 0, 
        contextFormatter: (v, ctx) => v == 1 ? '每个人独立完成' : '全员共同协作');

      if (before?['is_completed'] != after['is_completed']) {
        addChange('状态', before?['is_completed'], after['is_completed'], contextFormatter: (v, ctx) => v == 1 ? '已完成' : '待办');
      }
      if (before?['is_deleted'] != after['is_deleted']) {
        addChange('删除状态', before?['is_deleted'], after['is_deleted'], contextFormatter: (v, ctx) => v == 1 ? '已删除' : '正常');
      }
    } else if (widget.table == 'countdowns') {
      addChange('标题', before?['title'], after['title']);
      addChange('目标时间', before?['target_time'], after['target_time'], contextFormatter: (v, ctx) => formatTime(v));
    }

    if (changes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('数据无实质性变更', style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        ...changes,
      ],
    );
  }
}
