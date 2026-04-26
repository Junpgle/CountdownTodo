import 'package:flutter/material.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';

class ConflictInboxScreen extends StatefulWidget {
  final String username;
  final List<ConflictInfo>? syncConflicts;

  const ConflictInboxScreen({
    super.key,
    required this.username,
    this.syncConflicts,
  });

  @override
  State<ConflictInboxScreen> createState() => _ConflictInboxScreenState();
}

class _ConflictInboxScreenState extends State<ConflictInboxScreen> {
  List<dynamic> _conflictItems = [];
  bool _isLoading = true;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    StorageService.dataRefreshNotifier.addListener(_onDataRefreshed);
    _loadConflicts();
  }

  @override
  void dispose() {
    StorageService.dataRefreshNotifier.removeListener(_onDataRefreshed);
    super.dispose();
  }

  void _onDataRefreshed() {
    if (!mounted) return;
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      StorageService.getTodos(widget.username, includeDeleted: true),
      StorageService.getTodoGroups(widget.username, includeDeleted: true),
      StorageService.getCountdowns(widget.username),
    ]);

    final todos = results[0] as List<TodoItem>;
    final groups = results[1] as List<TodoGroup>;
    final countdowns = results[2] as List<CountdownItem>;

    final List<dynamic> items = [];
    items.addAll(todos.where((t) => t.hasConflict));
    items.addAll(groups.where((g) => g.hasConflict));
    items.addAll(countdowns.where((c) => c.hasConflict));

    items.sort((a, b) {
      int timeA = (a is TodoItem)
          ? a.updatedAt
          : (a is TodoGroup ? a.updatedAt : (a as CountdownItem).updatedAt);
      int timeB = (b is TodoItem)
          ? b.updatedAt
          : (b is TodoGroup ? b.updatedAt : (b as CountdownItem).updatedAt);
      return timeB.compareTo(timeA);
    });

    if (mounted) {
      setState(() {
        _conflictItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _scanAllTodoConflicts() async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    try {
      final result = await StorageService.scanAllTodoConflicts(widget.username);
      await _loadConflicts();
      if (!mounted) return;
      final total = result['total'] ?? 0;
      final pp = result['personal_personal'] ?? 0;
      final pt = result['personal_team'] ?? 0;
      final tt = result['team_team'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('扫描完成：$total 项冲突，个人-个人 $pp，个人-团队 $pt，团队-团队 $tt'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Find the sync conflict info that matches this item.
  Map<String, dynamic>? _findServerVersion(dynamic item) {
    final itemId = _itemId(item);
    if (itemId == null || itemId.isEmpty) return null;

    // 优先使用本地持久化的 conflict_data，避免页面只在“刚同步后”才能看到服务器版本。
    if (item is TodoItem &&
        item.serverVersionData != null &&
        item.serverVersionData!.isNotEmpty &&
        _sameItem(item.serverVersionData!, itemId)) {
      return item.serverVersionData;
    }
    if (item is TodoGroup &&
        item.conflictData != null &&
        item.conflictData!.isNotEmpty &&
        _sameItem(item.conflictData!, itemId)) {
      return item.conflictData;
    }
    if (item is CountdownItem &&
        item.conflictData != null &&
        item.conflictData!.isNotEmpty &&
        _sameItem(item.conflictData!, itemId)) {
      return item.conflictData;
    }

    if (widget.syncConflicts == null) return null;

    for (final c in widget.syncConflicts!) {
      final conflictItemId = c.item['uuid'] ?? c.item['id'] ?? '';
      if (conflictItemId == itemId) {
        return c.conflictWith;
      }
    }
    return null;
  }

  Map<String, dynamic>? _conflictData(dynamic item) {
    if (item is TodoItem) return item.serverVersionData;
    if (item is TodoGroup) return item.conflictData;
    if (item is CountdownItem) return item.conflictData;
    return null;
  }

  bool _isLocalScheduleConflict(dynamic item) {
    final data = _conflictData(item);
    if (data == null) return false;
    return data['conflict_type'] == 'local_schedule_conflict' ||
        data['source'] == 'local_detector';
  }

  String _conflictLabel(dynamic item) {
    return _isLocalScheduleConflict(item) ? '时间重叠' : '版本争议';
  }

  String? _relationType(dynamic item) {
    final data = _conflictData(item);
    if (data == null || data.isEmpty) return null;

    final direct = data['relation_type']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;

    if (_isLocalScheduleConflict(item)) {
      final peers = _conflictPeers(item);
      final itemIsTeam = _isTeamScopedData(_itemToJson(item));
      final hasTeamPeer = peers.any(_isTeamScopedData);
      final hasPersonalPeer = peers.any((peer) => !_isTeamScopedData(peer));
      if ((itemIsTeam && hasPersonalPeer) || (!itemIsTeam && hasTeamPeer)) {
        return 'personal_team';
      }
      return itemIsTeam ? 'team_team' : 'personal_personal';
    }

    final localIsTeam = _isTeamScopedData(_itemToJson(item));
    final server = _findServerVersion(item);
    final remoteIsTeam = server != null && _isTeamScopedData(server);
    if (localIsTeam != remoteIsTeam) return 'personal_team';
    return localIsTeam ? 'team_team' : 'personal_personal';
  }

  bool _isTeamScopedData(Map<String, dynamic>? data) {
    final teamUuid = data?['team_uuid']?.toString() ?? data?['teamUuid']?.toString();
    return teamUuid != null && teamUuid.isNotEmpty;
  }

  String _relationLabel(dynamic item) {
    switch (_relationType(item)) {
      case 'personal_personal':
        return '个人-个人';
      case 'personal_team':
        return '个人-团队';
      case 'team_team':
        return '团队-团队';
      default:
        return _isLocalScheduleConflict(item) ? '待办冲突' : '版本冲突';
    }
  }

  String _scheduleScopeLabel(Map<String, dynamic> data) {
    final scope = data['schedule_scope']?.toString();
    if (scope == 'team') return '团队待办';
    if (scope == 'personal') return '个人待办';
    final teamUuid = data['team_uuid']?.toString();
    return (teamUuid != null && teamUuid.isNotEmpty) ? '团队待办' : '个人待办';
  }

  Color _conflictColor(dynamic item) {
    return _isLocalScheduleConflict(item) ? Colors.orangeAccent : Colors.amber;
  }

  IconData _conflictIcon(dynamic item) {
    return _isLocalScheduleConflict(item)
        ? Icons.schedule_rounded
        : Icons.warning_amber_rounded;
  }

  String _itemTitle(Map<String, dynamic> data) {
    return data['content'] ??
        data['title'] ??
        data['courseName'] ??
        data['course_name'] ??
        data['name'] ??
        '未命名';
  }

  List<Map<String, dynamic>> _conflictPeers(dynamic item) {
    final peers = <Map<String, dynamic>>[];
    final data = _conflictData(item);
    if (data != null && data['conflict_with'] is List) {
      for (final peer in data['conflict_with'] as List) {
        if (peer is Map) peers.add(Map<String, dynamic>.from(peer));
      }
    }

    final serverVersion = _findServerVersion(item);
    if (serverVersion != null && serverVersion.isNotEmpty) {
      peers.add(serverVersion);
    }

    final itemId = _itemId(item);
    peers.removeWhere((peer) {
      final peerId = (peer['uuid'] ?? peer['id'] ?? '').toString();
      return peerId.isNotEmpty && peerId == itemId;
    });

    final deduped = <String, Map<String, dynamic>>{};
    for (final peer in peers) {
      final peerId = (peer['uuid'] ?? peer['id'] ?? '').toString();
      final title = _itemTitle(peer);
      final key = peerId.isNotEmpty ? peerId : title;
      if (key.isNotEmpty) deduped[key] = peer;
    }
    return deduped.values.toList();
  }

  String _conflictSummary(dynamic item) {
    final peers = _conflictPeers(item);
    if (peers.isEmpty) return '';
    final titles = peers.map(_itemTitle).where((t) => t.isNotEmpty).toList();
    if (titles.isEmpty) return '';
    final head = titles.take(3).join('、');
    final extra = titles.length > 3 ? ' 等 ${titles.length} 项' : '';
    return '${_conflictLabel(item)}：$head$extra';
  }

  String? _itemId(dynamic item) {
    if (item is TodoItem) return item.id;
    if (item is TodoGroup) return item.id;
    if (item is CountdownItem) return item.id;
    return null;
  }

  bool _sameItem(Map<String, dynamic> data, String itemId) {
    final dataId = (data['uuid'] ?? data['id'] ?? '').toString();
    return dataId.isNotEmpty && dataId == itemId;
  }

  String _resolveTable(dynamic item) {
    if (item is TodoItem) return 'todos';
    if (item is TodoGroup) return 'todo_groups';
    if (item is CountdownItem) return 'countdowns';
    return '';
  }

  Map<String, dynamic> _itemToJson(dynamic item) {
    if (item is TodoItem) return item.toJson();
    if (item is TodoGroup) return item.toJson();
    if (item is CountdownItem) return item.toJson();
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('数据冲突对齐中心',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar_rounded, size: 20),
            tooltip: '扫描全部待办冲突',
            onPressed: _isScanning ? null : _scanAllTodoConflicts,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, size: 20),
            onPressed: _showConflictHelp,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadConflicts,
          ),
        ],
      ),
      body: _isLoading
          ? _buildSkeleton()
          : _conflictItems.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _conflictItems.length,
                  itemBuilder: (context, index) {
                    return _buildConflictCard(_conflictItems[index]);
                  },
                ),
    );
  }

  void _showConflictHelp() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("什么是数据冲突？",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildHelpItem(Icons.devices_rounded, "多端编辑争议",
                "当你在不同设备上同时修改同一个任务，且系统无法判定哪个版本更新时，会标记为冲突。"),
            _buildHelpItem(Icons.history_rounded, "版本回退",
                "如果你的本地版本低于云端，但你强行进行了覆盖，系统会保留云端备份并提示争议。"),
            _buildHelpItem(Icons.sync_problem_rounded, "逻辑冲突",
                "如多个人同时预约了同一个时间段的日程，系统会标记该日程存在冲突。"),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("知道了"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                Text(desc,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_rounded,
              size: 80, color: Colors.green.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          const Text("所有数据已完全对齐",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const Text("目前没有任何待解决的同步冲突",
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildConflictCard(dynamic item) {
    String title = "";
    String subtitle = "";
    int timestamp = 0;
    IconData icon = Icons.help_outline;

    if (item is TodoItem) {
      title = item.title;
      subtitle = item.remark ?? "待办任务";
      timestamp = item.updatedAt;
      icon = Icons.check_circle_outline;
    } else if (item is TodoGroup) {
      title = item.name;
      subtitle = "分组/文件夹";
      timestamp = item.updatedAt;
      icon = Icons.folder_open;
    } else if (item is CountdownItem) {
      title = item.title;
      subtitle = "倒计时项";
      timestamp = item.updatedAt;
      icon = Icons.event;
    }
    final conflictColor = _conflictColor(item);
    final conflictIcon = _conflictIcon(item);
    final conflictLabel = _conflictLabel(item);
    final relationLabel = _relationLabel(item);
    final conflictSummary = _conflictSummary(item);
    final conflictPeers = _conflictPeers(item);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _resolveConflict(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: conflictColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        Icon(conflictIcon, size: 12, color: conflictColor),
                        const SizedBox(width: 4),
                        Text(conflictLabel,
                            style: TextStyle(
                                fontSize: 10,
                                color: conflictColor,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(relationLabel,
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('MM-dd HH:mm')
                        .format(DateTime.fromMillisecondsSinceEpoch(timestamp)),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    child: Icon(icon, size: 18, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              if (conflictSummary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  conflictSummary,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.3,
                  ),
                ),
              ],
              if (conflictPeers.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: conflictPeers.take(4).map((peer) {
                    final peerData = Map<String, dynamic>.from(peer);
                    final scope = _scheduleScopeLabel(peerData);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.orangeAccent.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_itemTitle(peerData),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(scope,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _resolveConflict(item),
                    icon: Icon(
                        _isLocalScheduleConflict(item)
                            ? Icons.visibility_rounded
                            : Icons.compare_arrows_rounded,
                        size: 16),
                    label: Text(
                        _isLocalScheduleConflict(item) ? "查看冲突" : "对比并解决",
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _resolveConflict(dynamic item) {
    if (_isLocalScheduleConflict(item)) {
      _showLocalScheduleConflict(item);
      return;
    }

    final serverVersion = _findServerVersion(item);
    final localJson = _itemToJson(item);
    final table = _resolveTable(item);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ConflictResolutionSheet(
        localItem: localJson,
        serverItem: serverVersion,
        table: table,
        username: widget.username,
        onResolved: () {
          _loadConflicts();
        },
      ),
    );
  }

  void _showLocalScheduleConflict(dynamic item) {
    final data = _conflictData(item) ?? {};
    final peers = data['conflict_with'] is List
        ? data['conflict_with'] as List
        : const [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('时间重叠',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_relationLabel(item),
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('调整其中一个任务的时间后，冲突会在下次同步或刷新时自动解除。',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            _buildScheduleConflictRow('当前任务', data),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: peers.length,
                itemBuilder: (context, index) {
                  final peer = peers[index] is Map
                      ? Map<String, dynamic>.from(peers[index] as Map)
                      : <String, dynamic>{};
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildScheduleConflictRow('冲突对象', peer),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleConflictRow(String label, Map<String, dynamic> data) {
    final title = data['content'] ?? data['title'] ?? '未命名任务';
    final start = _parseMs(data['start_time'] ??
        data['startTime'] ??
        data['created_date'] ??
        data['createdDate']);
    final end = _parseMs(data['end_time'] ??
        data['endTime'] ??
        data['due_date'] ??
        data['dueDate']);
    final time = start > 0 && end > 0
        ? '${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(start))} ~ ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(end))}'
        : '时间未知';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded,
              color: Colors.orangeAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(title.toString(),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(time,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _parseMs(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _buildSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        height: 160,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// Bottom sheet for comparing local vs server versions and choosing resolution.
class _ConflictResolutionSheet extends StatefulWidget {
  final Map<String, dynamic> localItem;
  final Map<String, dynamic>? serverItem;
  final String table;
  final String username;
  final VoidCallback onResolved;

  const _ConflictResolutionSheet({
    required this.localItem,
    required this.serverItem,
    required this.table,
    required this.username,
    required this.onResolved,
  });

  @override
  State<_ConflictResolutionSheet> createState() =>
      _ConflictResolutionSheetState();
}

class _ConflictResolutionSheetState extends State<_ConflictResolutionSheet> {
  bool _isResolving = false;

  bool get _hasServerData =>
      widget.serverItem != null && widget.serverItem!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text("冲突对比",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            "请选择保留哪个版本的数据",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // Local version card
          _buildVersionCard(
            label: "本地版本",
            icon: Icons.phone_android_rounded,
            color: Colors.blue,
            data: widget.localItem,
          ),
          const SizedBox(height: 12),

          // Server version card
          if (_hasServerData)
            _buildVersionCard(
              label: "服务器版本",
              icon: Icons.cloud_rounded,
              color: Colors.green,
              data: widget.serverItem!,
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "服务器版本数据暂不可用\n请同步后重试",
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isResolving ? null : _keepLocal,
                  icon: const Icon(Icons.phone_android_rounded, size: 18),
                  label: const Text("保留本地"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isResolving ? null : _acceptServer,
                  icon: const Icon(Icons.cloud_done_rounded, size: 18),
                  label: const Text("采用服务器"),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          if (_isResolving) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildVersionCard({
    required String label,
    required IconData icon,
    required Color color,
    required Map<String, dynamic> data,
  }) {
    final title = data['content'] ?? data['title'] ?? data['name'] ?? '未命名';
    final isDeleted = data['is_deleted'] == 1 || data['is_deleted'] == true;
    final version = data['version'] ?? '?';
    final isCompleted =
        data['is_completed'] == 1 || data['is_completed'] == true;

    String? timeStr;
    final start = data['start_time'] ??
        data['startTime'] ??
        data['created_date'] ??
        data['createdDate'];
    final end = data['end_time'] ??
        data['endTime'] ??
        data['due_date'] ??
        data['dueDate'];
    final targetTime = data['target_time'] ?? data['targetTime'];
    if (start != null && end != null) {
      final startMs =
          start is int ? start : int.tryParse(start.toString()) ?? 0;
      final endMs = end is int ? end : int.tryParse(end.toString()) ?? 0;
      if (startMs > 0 && endMs > 0) {
        final sf = DateFormat('MM-dd HH:mm');
        timeStr =
            '${sf.format(DateTime.fromMillisecondsSinceEpoch(startMs))} ~ ${sf.format(DateTime.fromMillisecondsSinceEpoch(endMs))}';
      }
    } else if (targetTime != null) {
      final tMs = targetTime is int
          ? targetTime
          : int.tryParse(targetTime.toString()) ?? 0;
      if (tMs > 0) {
        timeStr = DateFormat('MM-dd HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(tMs));
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold, color: color)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: Text("v$version",
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildFieldRow("标题", title),
          if (isDeleted) _buildFieldRow("状态", "已删除", valueColor: Colors.red),
          if (isCompleted) _buildFieldRow("完成", "是"),
          if (timeStr != null) _buildFieldRow("时间", timeStr),
          if (data['remark'] != null && data['remark'].toString().isNotEmpty)
            _buildFieldRow("备注", data['remark'].toString()),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: valueColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _keepLocal() async {
    setState(() => _isResolving = true);
    try {
      final uuid = widget.localItem['uuid'] ?? widget.localItem['id'] ?? '';

      // Bump version above server version and clear conflict flag locally,
      // then re-upload via op_logs so the server picks it up.
      final serverVersion = widget.serverItem?['version'] as int? ?? 0;
      final currentVersion = widget.localItem['version'] as int? ?? 1;
      final newVersion = serverVersion > currentVersion
          ? serverVersion + 1
          : currentVersion + 1;
      final now = DateTime.now().millisecondsSinceEpoch;

      widget.localItem['version'] = newVersion;
      widget.localItem['updated_at'] = now;
      widget.localItem['has_conflict'] = 0;

      // Persist locally and create oplog to push bumped version to server
      await StorageService.resolveConflictLocally(
        uuid: uuid,
        table: widget.table,
        resolvedData: widget.localItem,
        createOplog: true,
      );

      // Also tell the server to clear the conflict flag
      try {
        await ApiService.resolveConflict(
          uuid: uuid,
          table: widget.table,
          resolution: 'keep_local',
          bumpedVersion: newVersion,
          data: widget.localItem,
        );
      } catch (_) {
        // Server call is best-effort; local resolution is what matters
      }

      if (mounted) {
        widget.onResolved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('已保留本地版本，冲突已解决'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Future<void> _acceptServer() async {
    if (!_hasServerData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('服务器版本数据不可用，请先同步'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isResolving = true);
    try {
      final uuid = widget.localItem['uuid'] ?? widget.localItem['id'] ?? '';

      // Overwrite local with server version, clear conflict flag
      widget.serverItem!['has_conflict'] = 0;

      // Overwrite local with server version, no oplog needed
      await StorageService.resolveConflictLocally(
        uuid: uuid,
        table: widget.table,
        resolvedData: widget.serverItem!,
        createOplog: false,
      );

      // Notify server
      try {
        await ApiService.resolveConflict(
          uuid: uuid,
          table: widget.table,
          resolution: 'accept_server',
        );
      } catch (_) {}

      if (mounted) {
        widget.onResolved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('已采用服务器版本，冲突已解决'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }
}
