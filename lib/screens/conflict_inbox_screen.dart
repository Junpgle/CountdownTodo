import 'dart:convert';
import 'package:flutter/material.dart';
import '../models.dart';
import '../storage_service.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import '../widgets/todo_section_widget.dart';

enum _ConflictFilter { all, time, other }

enum _ScheduleResolutionMode { recommend, group, manual }

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
  bool _isApplyingScheduleFix = false;
  _ConflictFilter _selectedFilter = _ConflictFilter.all;
  dynamic _selectedItem; // 🚀 新增：当前选中的冲突项，用于桌面端双栏展示
  
  // 🚀 批量操作相关
  bool _isBatchMode = false;
  final Set<String> _selectedConflictIds = {};
  bool _isBatchApplying = false;

  bool get _isWide => MediaQuery.of(context).size.width > 900;
  
  String _getConflictId(dynamic item) {
    if (item is TodoItem) return 'todo_${item.id}';
    if (item is TodoGroup) return 'group_${item.id}';
    if (item is CountdownItem) return 'countdown_${item.id}';
    return '';
  }

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
    items.addAll(todos.where((t) {
      if (!t.hasConflict) return false;
      if (_isAllDayTask(t.toJson())) return false;

      // 如果有详细的冲突数据，检查其冲突对象是否全是全天任务
      final data = t.serverVersionData;
      if (data != null &&
          (data['type'] == 'schedule' || data['conflict_with'] != null)) {
        final peers = data['conflict_with'];
        if (peers is List) {
          final validPeers = peers.where(
              (p) => p is Map && !_isAllDayTask(Map<String, dynamic>.from(p)));
          if (validPeers.isEmpty) return false;
        }
      }
      return true;
    }));
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
    if (itemId == null || itemId.isEmpty) {
      return _conflictData(item);
    }

    final persisted = _conflictData(item);
    if (persisted != null && persisted.isNotEmpty) {
      final conflictType = persisted['conflict_type']?.toString();
      final conflictKind = persisted['conflict_kind']?.toString();
      final source = persisted['source']?.toString();
      final isPersistedVersionConflict = conflictType == 'version_conflict' ||
          conflictKind == 'version' ||
          (conflictType != 'local_schedule_conflict' &&
              source != 'local_detector');
      if (isPersistedVersionConflict) {
        return persisted;
      }
    }

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
    return _isLocalScheduleConflict(item) ? '时间冲突' : '其他冲突';
  }

  bool _hasServerSnapshot(dynamic item) {
    final data = _findServerVersion(item);
    return data != null && data.isNotEmpty;
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
    final teamUuid =
        data?['team_uuid']?.toString() ?? data?['teamUuid']?.toString();
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

  List<dynamic> get _timeConflictItems =>
      _conflictItems.where(_isLocalScheduleConflict).toList();

  List<dynamic> get _otherConflictItems =>
      _conflictItems.where((item) => !_isLocalScheduleConflict(item)).toList();

  List<dynamic> get _visibleConflictItems {
    switch (_selectedFilter) {
      case _ConflictFilter.time:
        return _timeConflictItems;
      case _ConflictFilter.other:
        return _otherConflictItems;
      case _ConflictFilter.all:
        return _conflictItems;
    }
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
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 🚀 1. 现代沉浸式背景
          _buildModernBackground(isDark),

          // 🚀 2. 主内容区域
          SafeArea(
            child: Column(
              children: [
                _buildModernAppBar(isDark),
                _buildScanProgressBanner(),
                _buildGhostConflictBanner(),
                if (!_isLoading) _buildConflictStats(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 900) {
                        return _buildWideLayout(isDark);
                      }
                      return _buildMobileLayout(isDark);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernBackground(bool isDark) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    );
  }

  Widget _buildModernAppBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (_isBatchMode) ...[
            IconButton(
              onPressed: () => setState(() {
                _isBatchMode = false;
                _selectedConflictIds.clear();
              }),
              icon: const Icon(Icons.close_rounded),
              color: isDark ? Colors.white70 : Colors.blueGrey.shade700,
              tooltip: '取消批量模式',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '已选择 ${_selectedConflictIds.length} 项',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.blueGrey.shade900,
                ),
              ),
            ),
          ] else ...[
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: isDark ? Colors.white70 : Colors.blueGrey.shade700,
              tooltip: '返回',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '冲突对齐中心',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.blueGrey.shade900,
                    ),
                  ),
                  Text(
                    'Uni-Sync 4.0 智能数据对齐引擎',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.blueGrey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 16),
          if (!_isBatchMode) ...[
            _buildAppBarAction(
              icon: _isScanning ? null : Icons.radar_rounded,
              loading: _isScanning,
              onTap: _isScanning ? null : _scanAllTodoConflicts,
              tooltip: '扫描全部冲突',
            ),
            const SizedBox(width: 12),
            _buildAppBarAction(
              icon: Icons.refresh_rounded,
              onTap: _loadConflicts,
              tooltip: '刷新列表',
            ),
            const SizedBox(width: 12),
            _buildAppBarAction(
              icon: Icons.help_outline_rounded,
              onTap: _showConflictHelp,
              tooltip: '查看帮助',
            ),
            const SizedBox(width: 12),
            _buildAppBarAction(
              icon: Icons.checklist_rounded,
              onTap: _conflictItems.isNotEmpty ? () => setState(() => _isBatchMode = true) : null,
              tooltip: '批量管理',
            ),
          ] else ...[
            _buildAppBarAction(
              icon: Icons.select_all_rounded,
              onTap: _selectedConflictIds.length == _visibleConflictItems.length
                  ? () => setState(() => _selectedConflictIds.clear())
                  : () => setState(() {
                        _selectedConflictIds.clear();
                        for (final item in _visibleConflictItems) {
                          _selectedConflictIds.add(_getConflictId(item));
                        }
                      }),
              tooltip: _selectedConflictIds.length == _visibleConflictItems.length ? '取消全选' : '全选',
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildAppBarAction({
    IconData? icon,
    bool loading = false,
    VoidCallback? onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 20),
        ),
      ),
    );
  }

  Widget _buildWideLayout(bool isDark) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              // 左栏：列表
              SizedBox(
                width: 380,
                child: _buildConflictList(isDark),
              ),
              // 分割线
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? Colors.white10 : Colors.black12,
              ),
              // 右栏：详情
              Expanded(
                child: _buildDetailPane(isDark),
              ),
            ],
          ),
        ),
        if (_isBatchMode && _selectedConflictIds.isNotEmpty)
          _buildBatchActionBarWide(isDark),
      ],
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return Column(
      children: [
        Expanded(child: _buildConflictList(isDark)),
        if (_isBatchMode && _selectedConflictIds.isNotEmpty)
          _buildBatchActionBar(isDark),
      ],
    );
  }

  Widget _buildConflictList(bool isDark) {
    if (_isLoading) return _buildSkeleton();
    if (_visibleConflictItems.isEmpty) return _buildEmptyState();

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _visibleConflictItems.length,
      itemBuilder: (context, index) {
        final item = _visibleConflictItems[index];
        final isSelected = _selectedItem == item;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildModernConflictCard(item, isSelected, isDark),
        );
      },
    );
  }

  Widget _buildDetailPane(bool isDark) {
    if (_selectedItem == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_motion_rounded,
              size: 64,
              color: isDark ? Colors.white10 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              '请选择一个冲突项进行对齐',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.black38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // 根据选中的项目类型渲染不同的详情视图
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(_itemId(_selectedItem)),
        child: _buildEmbeddedResolutionUI(_selectedItem, isDark),
      ),
    );
  }

  Widget _buildLocalScheduleDetail(dynamic item, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailHeader(
            icon: Icons.schedule_rounded,
            title: '时间冲突排查',
            subtitle: '该待办与已有日程在时间上存在重叠，请调整其时间。',
            isDark: isDark,
          ),
          const SizedBox(height: 32),
          _buildLocalScheduleCard(item, isDark),
        ],
      ),
    );
  }

  Widget _buildMissingSnapshotDetail(dynamic item, bool isDark) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailHeader(
              icon: Icons.auto_fix_high_rounded,
              title: '云端快照同步异常',
              subtitle: '本地标记了冲突但未找到云端备份，可能是同步链路中断导致。建议执行一键修复。',
              isDark: isDark,
              center: true,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: () => _batchResolveGhostConflicts([item]),
                icon: const Icon(Icons.flash_on_rounded),
                label: const Text('立即修复并同步',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    bool center = false,
  }) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.blue, size: 32),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.blueGrey.shade900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: isDark ? Colors.white54 : Colors.blueGrey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmbeddedResolutionUI(dynamic item, bool isDark) {
    if (_isLocalScheduleConflict(item)) {
      return _buildLocalScheduleDetail(item, isDark);
    }

    final serverVersion = _findServerVersion(item);
    if (serverVersion == null || serverVersion.isEmpty) {
      return _buildMissingSnapshotDetail(item, isDark);
    }

    final localJson = _itemToJson(item);
    final table = _resolveTable(item);

    return _ConflictResolutionSheet(
      localItem: localJson,
      serverItem: serverVersion,
      table: table,
      username: widget.username,
      isEmbedded: true,
      onResolved: () {
        setState(() => _selectedItem = null);
        _loadConflicts();
      },
    );
  }

  Widget _buildModernConflictCard(dynamic item, bool isSelected, bool isDark) {
    String title = "";
    if (item is TodoItem)
      title = item.title;
    else if (item is TodoGroup)
      title = item.name;
    else if (item is CountdownItem) title = item.title;

    final conflictColor = _conflictColor(item);
    final isTodo = item is TodoItem;
    final itemId = _getConflictId(item);
    final isBatchSelected = _selectedConflictIds.contains(itemId);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelected || isBatchSelected
            ? (isDark
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.blue.withValues(alpha: 0.1))
            : (isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected || isBatchSelected
              ? Colors.blue
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05)),
          width: isSelected || isBatchSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isBatchMode) {
            setState(() {
              if (isBatchSelected) {
                _selectedConflictIds.remove(itemId);
              } else {
                _selectedConflictIds.add(itemId);
              }
            });
          } else if (_isWide) {
            setState(() => _selectedItem = item);
          } else {
            _resolveConflict(item);
          }
        },
        onLongPress: _isBatchMode ? null : () {
          setState(() {
            _isBatchMode = true;
            _selectedConflictIds.add(itemId);
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_isBatchMode) ...[
                Checkbox(
                  value: isBatchSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedConflictIds.add(itemId);
                      } else {
                        _selectedConflictIds.remove(itemId);
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: conflictColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isSelected || isBatchSelected ? FontWeight.bold : FontWeight.w500,
                              color: isDark ? Colors.white : Colors.blueGrey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildMiniBadge(_conflictLabel(item),
                            conflictColor.withValues(alpha: 0.1), conflictColor),
                        _buildMiniBadge(_relationLabel(item),
                            Colors.blue.withValues(alpha: 0.1), Colors.blue),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildBatchActionBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: const Text('推荐方案'),
                  onPressed: _isBatchApplying ? null : _batchApplyRecommended,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.phone_android_rounded, size: 18),
                  label: const Text('保留本地'),
                  onPressed: _isBatchApplying ? null : _batchKeepLocal,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.cloud_done_rounded, size: 18),
                  label: const Text('使用服务器'),
                  onPressed: _isBatchApplying ? null : _batchAcceptServer,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isBatchApplying) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildBatchActionBarWide(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '已选择 ${_selectedConflictIds.length} 项冲突',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('推荐方案'),
                onPressed: _isBatchApplying ? null : _batchApplyRecommended,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.phone_android_rounded, size: 18),
                label: const Text('保留本地'),
                onPressed: _isBatchApplying ? null : _batchKeepLocal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.cloud_done_rounded, size: 18),
                label: const Text('使用服务器'),
                onPressed: _isBatchApplying ? null : _batchAcceptServer,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          if (_isBatchApplying) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildScanProgressBanner() {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: StorageService.conflictScanNotifier,
      builder: (context, scanState, _) {
        final isScanning = scanState['isScanning'] == true;
        if (!isScanning) return const SizedBox.shrink();
        final progress = (scanState['progress'] as int?) ?? 0;
        final current = (scanState['current'] as int?) ?? 0;
        final total = (scanState['total'] as int?) ?? 0;
        final message = scanState['message']?.toString() ?? '正在扫描冲突';
        return Container(
          margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: Colors.orangeAccent.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.radar_rounded,
                        size: 20, color: Colors.orangeAccent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('已扫描 $current / $total',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Text('$progress%',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.orangeAccent)),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress <= 0 ? null : progress / 100,
                  minHeight: 8,
                  backgroundColor: Colors.orangeAccent.withValues(alpha: 0.12),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGhostConflictBanner() {
    final ghostItems = _conflictItems.where((item) {
      if (item is! TodoItem) return false;
      final data = _findServerVersion(item);
      return (data == null || data.isEmpty) &&
          !(_conflictData(item)?['type'] == 'schedule');
    }).toList();

    if (ghostItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade400, Colors.pink.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "发现 ${ghostItems.length} 项损坏的冲突（无云端快照）",
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => _batchResolveGhostConflicts(ghostItems),
            child: const Text("一键修复"),
          ),
        ],
      ),
    );
  }

  Future<void> _batchResolveGhostConflicts(List<dynamic> items) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("一键修复"),
        content: Text("将强制保留这 ${items.length} 项任务的本地版本并清除冲突标记。确认继续？"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("取消")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("确认修复")),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      // 1. 一次性获取所有数据源
      final results = await Future.wait([
        StorageService.getTodos(widget.username, includeDeleted: true),
        StorageService.getTodoGroups(widget.username, includeDeleted: true),
        StorageService.getCountdowns(widget.username),
      ]);

      final allTodos = results[0] as List<TodoItem>;
      final allGroups = results[1] as List<TodoGroup>;
      final allCountdowns = results[2] as List<CountdownItem>;

      bool todosChanged = false;
      bool groupsChanged = false;
      bool countdownsChanged = false;

      // 2. 在内存中批量处理
      for (final ghost in items) {
        final id = _itemId(ghost);
        if (id == null) continue;

        if (ghost is TodoItem) {
          final idx = allTodos.indexWhere((t) => t.id == id);
          if (idx != -1) {
            final item = allTodos[idx];
            // 🚀 精准清理：根据归属权决定动作
            if (item.teamUuid != null && item.teamUuid!.isNotEmpty) {
              // A. 团队项 -> 加入忽略表并物理删除
              await StorageService.ignoreRemoteItem(
                  table: 'todos', uuid: item.id, teamUuid: item.teamUuid);
              // 🚀 核心加固：同时同步给服务端，防止其他设备同步时拉回
              ApiService.ignoreRemoteItem(
                  uuid: item.id, table: 'todos', teamUuid: item.teamUuid);
              allTodos.removeAt(idx);
            } else {
              // B. 个人项 -> 软删除 + 版本跃迁
              item.isDeleted = true;
              item.hasConflict = false;
              item.serverVersionData = null;
              item.updatedAt = DateTime.now().millisecondsSinceEpoch + 60000;
              item.version = item.version + 1000;
              item.markAsChanged();
            }
            todosChanged = true;
          }
        } else if (ghost is TodoGroup) {
          final idx = allGroups.indexWhere((g) => g.id == id);
          if (idx != -1) {
            final item = allGroups[idx];
            if (item.teamUuid != null && item.teamUuid!.isNotEmpty) {
              await StorageService.ignoreRemoteItem(
                  table: 'todo_groups', uuid: item.id, teamUuid: item.teamUuid);
              ApiService.ignoreRemoteItem(
                  uuid: item.id, table: 'todo_groups', teamUuid: item.teamUuid);
              allGroups.removeAt(idx);
            } else {
              item.isDeleted = true;
              item.hasConflict = false;
              item.conflictData = null;
              item.updatedAt = DateTime.now().millisecondsSinceEpoch + 60000;
              item.version = item.version + 1000;
              item.markAsChanged();
            }
            groupsChanged = true;
          }
        } else if (ghost is CountdownItem) {
          final idx = allCountdowns.indexWhere((c) => c.id == id);
          if (idx != -1) {
            final item = allCountdowns[idx];
            if (item.teamUuid != null && item.teamUuid!.isNotEmpty) {
              await StorageService.ignoreRemoteItem(
                  table: 'countdowns', uuid: item.id, teamUuid: item.teamUuid);
              ApiService.ignoreRemoteItem(
                  uuid: item.id, table: 'countdowns', teamUuid: item.teamUuid);
              allCountdowns.removeAt(idx);
            } else {
              item.isDeleted = true;
              item.hasConflict = false;
              item.conflictData = null;
              item.updatedAt = DateTime.now().millisecondsSinceEpoch + 60000;
              item.version = item.version + 1000;
              item.markAsChanged();
            }
            countdownsChanged = true;
          }
        }
      }

      // 3. 批量持久化（每种类型仅写入一次）
      final saves = <Future>[];
      if (todosChanged)
        saves.add(StorageService.saveTodos(widget.username, allTodos));
      if (groupsChanged)
        saves.add(StorageService.saveTodoGroups(widget.username, allGroups));
      if (countdownsChanged)
        saves
            .add(StorageService.saveCountdowns(widget.username, allCountdowns));

      if (saves.isNotEmpty) await Future.wait(saves);
    } catch (e) {
      debugPrint("批量修复失败: $e");
    }

    // 4. 统一刷新界面
    await _loadConflicts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("损坏的冲突已批量修复")),
      );
    }
  }

  Widget _buildConflictStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _buildModernStatCard(
            label: '全部冲突',
            count: _conflictItems.length,
            icon: Icons.all_inbox_rounded,
            color: Colors.blue,
            isSelected: _selectedFilter == _ConflictFilter.all,
            onTap: () => setState(() => _selectedFilter = _ConflictFilter.all),
          ),
          _buildModernStatCard(
            label: '排程冲突',
            count: _timeConflictItems.length,
            icon: Icons.schedule_rounded,
            color: Colors.orange,
            isSelected: _selectedFilter == _ConflictFilter.time,
            onTap: () => setState(() => _selectedFilter = _ConflictFilter.time),
          ),
          _buildModernStatCard(
            label: '内容版本',
            count: _otherConflictItems.length,
            icon: Icons.difference_rounded,
            color: Colors.indigo,
            isSelected: _selectedFilter == _ConflictFilter.other,
            onTap: () =>
                setState(() => _selectedFilter = _ConflictFilter.other),
          ),
        ],
      ),
    );
  }

  Widget _buildModernStatCard({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isSelected ? color : Colors.grey),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalScheduleCard(dynamic item, bool isDark) {
    final conflictWith = _conflictData(item)?['conflict_with'];
    final peers = conflictWith is List ? conflictWith : [];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color:
                isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("受影响的项目",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildScheduleItemRow(item, isMain: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child:
                Icon(Icons.link_rounded, color: Colors.orangeAccent, size: 20),
          ),
          ...peers.map((p) => _buildScheduleItemRow(p)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _resolveConflict(item),
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text("进入时间对齐助手",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleItemRow(dynamic data, {bool isMain = false}) {
    final Map<String, dynamic> map = data is Map
        ? Map<String, dynamic>.from(data)
        : (data as TodoItem).toJson();
    final title = map['content'] ?? map['title'] ?? '未命名任务';
    final start = _parseMs(map['created_date'] ??
        map['createdDate'] ??
        map['start_time'] ??
        map['startTime']);
    final end = _parseMs(
        map['due_date'] ?? map['dueDate'] ?? map['end_time'] ?? map['endTime']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMain
            ? Colors.orangeAccent.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isMain
                ? Colors.orangeAccent.withValues(alpha: 0.2)
                : Colors.transparent),
      ),
      child: Row(
        children: [
          Icon(isMain ? Icons.warning_amber_rounded : Icons.event_note_rounded,
              color: isMain ? Colors.orangeAccent : Colors.blue, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(start))} ~ ${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(end))}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required int count,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.45)
                : color.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
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
    final hasAnyConflicts = _conflictItems.isNotEmpty;
    final title = hasAnyConflicts ? '当前筛选下没有冲突' : '所有数据已完全对齐';
    final subtitle =
        hasAnyConflicts ? '可以切换到“全部”或其他分类查看待处理项' : '目前没有任何待解决的同步冲突';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_rounded,
              size: 80, color: Colors.green.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
    final hasServerSnapshot = _hasServerSnapshot(item);

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
                            : (hasServerSnapshot
                                ? Icons.compare_arrows_rounded
                                : Icons.info_outline_rounded),
                        size: 16),
                    label: Text(
                        _isLocalScheduleConflict(item)
                            ? "查看冲突"
                            : (hasServerSnapshot ? "对比并解决" : "查看说明"),
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
    if (serverVersion == null || serverVersion.isEmpty) {
      _showMissingServerSnapshot(item);
      return;
    }

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

  void _showMissingServerSnapshot(dynamic item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
            const Text('暂无云端版本快照',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '当前条目标记为${_conflictLabel(item)}，但本地没有保存可对比的服务器版本内容。',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              '这通常表示当前只有本地冲突标记，或者版本冲突发生时服务器快照尚未落盘。',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _resolveGhostConflict(item);
                    },
                    child: const Text('强制保留本地'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _batchKeepLocal() async {
    if (_selectedConflictIds.isEmpty) return;
    setState(() => _isBatchApplying = true);
    
    try {
      int successCount = 0;
      final ids = _selectedConflictIds.toList();
      
      for (final itemId in ids) {
        try {
          // 根据 ID 格式查找对应的冲突项
          final conflictItem = _visibleConflictItems.firstWhere(
            (item) => _getConflictId(item) == itemId,
            orElse: () => null,
          );
          if (conflictItem == null) continue;
          
          // 对于有服务器版本的冲突，使用 _ConflictResolutionSheet 的逻辑
          final serverVersion = _findServerVersion(conflictItem);
          if (serverVersion != null && serverVersion.isNotEmpty) {
            final localJson = _itemToJson(conflictItem);
            final table = _resolveTable(conflictItem);
            
            final uuid = localJson['uuid'] ?? localJson['id'] ?? '';
            final serverVer = serverVersion['version'] as int? ?? 0;
            final currentVer = localJson['version'] as int? ?? 1;
            final newVersion = serverVer > currentVer ? serverVer + 1 : currentVer + 1;
            final now = DateTime.now().millisecondsSinceEpoch;
            
            localJson['version'] = newVersion;
            localJson['updated_at'] = now;
            localJson['has_conflict'] = 0;
            localJson.remove('conflict_data');
            localJson.remove('serverVersionData');
            
            await StorageService.resolveConflictLocally(
              uuid: uuid,
              table: table,
              resolvedData: localJson,
              createOplog: true,
            );
            
            try {
              await ApiService.resolveConflict(
                uuid: uuid,
                table: table,
                resolution: 'keep_local',
                bumpedVersion: newVersion,
                data: localJson,
              );
            } catch (_) {}
            
            successCount++;
          } else {
            // 对于没有服务器版本的冲突，使用强制保留本地
            await _resolveGhostConflict(conflictItem, refresh: false);
            successCount++;
          }
        } catch (e) {
          debugPrint('批量保留本地失败 $itemId: $e');
        }
      }
      
      if (mounted) {
        _selectedConflictIds.clear();
        _isBatchMode = false;
        await _loadConflicts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保留本地版本，成功处理 $successCount 项冲突'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchApplying = false);
    }
  }

  Future<void> _batchAcceptServer() async {
    if (_selectedConflictIds.isEmpty) return;
    setState(() => _isBatchApplying = true);
    
    try {
      int successCount = 0;
      final ids = _selectedConflictIds.toList();
      
      for (final itemId in ids) {
        try {
          final conflictItem = _visibleConflictItems.firstWhere(
            (item) => _getConflictId(item) == itemId,
            orElse: () => null,
          );
          if (conflictItem == null) continue;
          
          final serverVersion = _findServerVersion(conflictItem);
          if (serverVersion == null || serverVersion.isEmpty) continue;
          
          final localJson = _itemToJson(conflictItem);
          final table = _resolveTable(conflictItem);
          final uuid = localJson['uuid'] ?? localJson['id'] ?? '';
          
          serverVersion['has_conflict'] = 0;
          
          await StorageService.resolveConflictLocally(
            uuid: uuid,
            table: table,
            resolvedData: serverVersion,
            createOplog: false,
            touchUpdatedAt: false,
          );
          
          try {
            await ApiService.resolveConflict(
              uuid: uuid,
              table: table,
              resolution: 'accept_server',
            );
          } catch (_) {}
          
          successCount++;
        } catch (e) {
          debugPrint('批量采用服务器版本失败 $itemId: $e');
        }
      }
      
      if (mounted) {
        _selectedConflictIds.clear();
        _isBatchMode = false;
        await _loadConflicts();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已采用服务器版本，成功处理 $successCount 项冲突'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchApplying = false);
    }
  }

  Future<void> _batchApplyRecommended() async {
    if (_selectedConflictIds.isEmpty) return;
    
    _showBatchResolutionDialog();
  }

  void _showBatchResolutionDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
            const Text('批量推荐方案',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '该操作将对选中的 ${_selectedConflictIds.length} 项冲突应用推荐的解决方案。',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '推荐方案将根据时间冲突自动调整任务时间，或选择最合适的版本。',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _batchApplyRecommendedExecute();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: const Text('应用推荐方案'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _batchApplyRecommendedExecute() async {
    setState(() => _isBatchApplying = true);
    
    try {
      int successCount = 0;
      int schedulerCount = 0;
      final ids = _selectedConflictIds.toList();
      
      for (final itemId in ids) {
        try {
          final conflictItem = _visibleConflictItems.firstWhere(
            (item) => _getConflictId(item) == itemId,
            orElse: () => null,
          );
          if (conflictItem == null) continue;
          
          // 对于时间冲突，使用推荐时间调整
          if (_isLocalScheduleConflict(conflictItem) && conflictItem is TodoItem) {
            final peers = _conflictPeers(conflictItem);
            final recommendedWindow = _suggestPreferredWindow(conflictItem, peers);
            if (recommendedWindow != null) {
              final allTodos =
                  await StorageService.getTodos(widget.username, includeDeleted: true);
              final idx = allTodos.indexWhere((t) => t.id == conflictItem.id);
              if (idx != -1) {
                allTodos[idx].createdDate = recommendedWindow.start.millisecondsSinceEpoch;
                allTodos[idx].dueDate = recommendedWindow.end;
                allTodos[idx].markAsChanged();
                await StorageService.saveTodos(widget.username, allTodos);
                schedulerCount++;
              }
            }
          } else {
            // 对于版本冲突，保留本地版本
            final serverVersion = _findServerVersion(conflictItem);
            if (serverVersion != null && serverVersion.isNotEmpty) {
              final localJson = _itemToJson(conflictItem);
              final table = _resolveTable(conflictItem);
              
              final uuid = localJson['uuid'] ?? localJson['id'] ?? '';
              final serverVer = serverVersion['version'] as int? ?? 0;
              final currentVer = localJson['version'] as int? ?? 1;
              final newVersion = serverVer > currentVer ? serverVer + 1 : currentVer + 1;
              final now = DateTime.now().millisecondsSinceEpoch;
              
              localJson['version'] = newVersion;
              localJson['updated_at'] = now;
              localJson['has_conflict'] = 0;
              localJson.remove('conflict_data');
              localJson.remove('serverVersionData');
              
              await StorageService.resolveConflictLocally(
                uuid: uuid,
                table: table,
                resolvedData: localJson,
                createOplog: true,
              );
              
              try {
                await ApiService.resolveConflict(
                  uuid: uuid,
                  table: table,
                  resolution: 'keep_local',
                  bumpedVersion: newVersion,
                  data: localJson,
                );
              } catch (_) {}
              
              successCount++;
            }
          }
        } catch (e) {
          debugPrint('批量推荐方案失败 $itemId: $e');
        }
      }
      
      if (mounted) {
        _selectedConflictIds.clear();
        _isBatchMode = false;
        await _loadConflicts();
        final message = schedulerCount > 0 && successCount > 0
            ? '已应用推荐方案，调整时间 $schedulerCount 项，版本冲突 $successCount 项'
            : schedulerCount > 0
                ? '已应用推荐方案，调整时间 $schedulerCount 项'
                : '已应用推荐方案，成功处理 $successCount 项冲突';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchApplying = false);
    }
  }

  Future<void> _resolveGhostConflict(dynamic item,
      {bool refresh = true}) async {
    if (item is TodoItem) {
      final all =
          await StorageService.getTodos(widget.username, includeDeleted: true);
      final idx = all.indexWhere((t) => t.id == item.id);
      if (idx != -1) {
        all[idx].hasConflict = false;
        all[idx].serverVersionData = null;
        all[idx].updatedAt = DateTime.now().millisecondsSinceEpoch + 60000;
        all[idx].version = (all[idx].version ?? 1) + 1000;
        all[idx].markAsChanged();
        await StorageService.saveTodos(widget.username, all);
      }
    } else if (item is TodoGroup) {
      final all = await StorageService.getTodoGroups(widget.username,
          includeDeleted: true);
      final idx = all.indexWhere((g) => g.id == item.id);
      if (idx != -1) {
        all[idx].hasConflict = false;
        all[idx].conflictData = null;
        all[idx].updatedAt = DateTime.now().millisecondsSinceEpoch + 60000;
        all[idx].version = (all[idx].version ?? 1) + 1000;
        all[idx].markAsChanged();
        await StorageService.saveTodoGroups(widget.username, all);
      }
    } else if (item is CountdownItem) {
      final all = await StorageService.getCountdowns(widget.username);
      final idx = all.indexWhere((c) => c.id == item.id);
      if (idx != -1) {
        all[idx].hasConflict = false;
        all[idx].conflictData = null;
        all[idx].updatedAt = DateTime.now().millisecondsSinceEpoch + 60000;
        all[idx].version = (all[idx].version ?? 1) + 1000;
        all[idx].markAsChanged();
        await StorageService.saveCountdowns(widget.username, all);
      }
    }

    if (refresh) {
      await _loadConflicts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("已强制保留本地并清除冲突标记")),
        );
      }
    }
  }

  Future<void> _showLocalScheduleConflict(dynamic item) async {
    final data = _conflictData(item) ?? {};
    final peers = (data['conflict_with'] is List
            ? data['conflict_with'] as List
            : const [])
        .where((p) => p is Map && !_isAllDayTask(Map<String, dynamic>.from(p)))
        .toList();

    // 如果过滤掉全天任务后不再冲突，则不显示详情（或提示已解决）
    if (peers.isEmpty && (item is TodoItem)) {
      // 这里的逻辑可以根据需要调整，目前保持能打开但列表为空
    }

    final allTodos = item is TodoItem
        ? await StorageService.getTodos(widget.username, includeDeleted: true)
        : const <TodoItem>[];
    if (!mounted) return;
    final recommendedWindow =
        item is TodoItem ? _suggestPreferredWindow(item, peers) : null;
    final recommendedLabel = item is TodoItem && recommendedWindow != null
        ? _buildRecommendedResolutionLabel(item, recommendedWindow)
        : null;
    final recommendedUpdates = item is TodoItem && recommendedWindow != null
        ? <String, ({DateTime start, DateTime end})>{
            item.id: (
              start: recommendedWindow.start,
              end: recommendedWindow.end,
            ),
          }
        : <String, ({DateTime start, DateTime end})>{};
    final groupUpdates = item is TodoItem
        ? _buildGroupScheduleUpdates(item, peers, allTodos)
        : <String, ({DateTime start, DateTime end})>{};
    var selectedMode = item is TodoItem && recommendedUpdates.isNotEmpty
        ? _ScheduleResolutionMode.recommend
        : _ScheduleResolutionMode.manual;
    var selectedIdToEdit = _itemId(item);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selectedUpdates = switch (selectedMode) {
            _ScheduleResolutionMode.recommend => recommendedUpdates,
            _ScheduleResolutionMode.group => groupUpdates,
            _ScheduleResolutionMode.manual =>
              <String, ({DateTime start, DateTime end})>{},
          };
          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.88),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(sheetContext).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(
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
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_relationLabel(item),
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                      selectedMode == _ScheduleResolutionMode.manual
                          ? '手动模式：点击上方卡片可选中任一冲突任务进行编辑。'
                          : '先横向查看当前任务和冲突任务，再选择处理方式。执行前会先给出预览。',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  if (recommendedLabel != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.auto_fix_high_rounded,
                              size: 18, color: Colors.green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              recommendedLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildHorizontalConflictGallery(
                    data,
                    peers,
                    selectedUpdates,
                    mode: selectedMode,
                    selectedIdToEdit: selectedIdToEdit,
                    onSelect: (id) =>
                        setSheetState(() => selectedIdToEdit = id),
                  ),
                  const SizedBox(height: 16),
                  if (item is TodoItem) ...[
                    _buildResolutionModeSelector(
                      selectedMode: selectedMode,
                      recommendedEnabled: recommendedUpdates.isNotEmpty,
                      groupEnabled: groupUpdates.isNotEmpty,
                      onChanged: (mode) =>
                          setSheetState(() => selectedMode = mode),
                    ),
                    if (_isApplyingScheduleFix) ...[
                      const SizedBox(height: 12),
                      const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isApplyingScheduleFix ||
                                    (selectedMode !=
                                            _ScheduleResolutionMode.manual &&
                                        selectedUpdates.isEmpty)
                                ? null
                                : () async {
                                    if (selectedMode ==
                                        _ScheduleResolutionMode.manual) {
                                      final target = allTodos
                                          .cast<TodoItem?>()
                                          .firstWhere(
                                            (todo) =>
                                                todo?.id == selectedIdToEdit,
                                            orElse: () => null,
                                          );
                                      if (target != null) {
                                        Navigator.pop(sheetContext);
                                        await _openTodoEditor(target);
                                      }
                                      return;
                                    }
                                    if (selectedUpdates.isEmpty) return;
                                    final successMessage = selectedMode ==
                                            _ScheduleResolutionMode.recommend
                                        ? '已按预览结果调整当前任务'
                                        : '已按预览结果顺排冲突链';
                                    await _persistResolvedTodos(
                                      selectedUpdates,
                                      successMessage: successMessage,
                                      popContext: sheetContext,
                                    );
                                  },
                            child: Text(
                              selectedMode == _ScheduleResolutionMode.manual
                                  ? '进入编辑'
                                  : '确认应用',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('知道了'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalConflictGallery(
    Map<String, dynamic> data,
    List peers,
    Map<String, ({DateTime start, DateTime end})> updates, {
    required _ScheduleResolutionMode mode,
    String? selectedIdToEdit,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("冲突对比 (横向滑动)",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SizedBox(
          height: 145,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildScheduleConflictCard(
                Map<String, dynamic>.from(data)..['is_primary'] = true,
                updates,
                mode: mode,
                isSelectedForEdit: selectedIdToEdit == _itemIdFromData(data),
                onSelect: onSelect,
              ),
              if (peers.isEmpty)
                _buildScheduleConflictEmpty()
              else
                ...peers.map<Widget>((peer) {
                  final Map<String, dynamic> peerMap = peer is Map
                      ? Map<String, dynamic>.from(peer)
                      : <String, dynamic>{};
                  final peerId = _itemIdFromData(peerMap);
                  return _buildScheduleConflictCard(
                    peerMap,
                    updates,
                    mode: mode,
                    isSelectedForEdit:
                        peerId != null && selectedIdToEdit == peerId,
                    onSelect: onSelect,
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleConflictEmpty() {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: const Center(
        child:
            Text("无其他冲突对象", style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    );
  }

  Widget _buildScheduleConflictCard(
    Map<String, dynamic> data,
    Map<String, ({DateTime start, DateTime end})> updates, {
    required _ScheduleResolutionMode mode,
    bool isSelectedForEdit = false,
    required ValueChanged<String> onSelect,
  }) {
    final isPrimary = data['is_primary'] == true;
    final id = _itemIdFromData(data);
    final update = id != null ? updates[id] : null;
    final isManualMode = mode == _ScheduleResolutionMode.manual;

    final title = _itemTitle(data);
    final start = _parseMs(data['start_time'] ??
        data['startTime'] ??
        data['created_date'] ??
        data['createdDate']);
    final end = _parseMs(data['end_time'] ??
        data['endTime'] ??
        data['due_date'] ??
        data['dueDate']);

    final sf = DateFormat('HH:mm');
    final originalTime = start > 0 && end > 0
        ? '${sf.format(DateTime.fromMillisecondsSinceEpoch(start))} ~ ${sf.format(DateTime.fromMillisecondsSinceEpoch(end))}'
        : '时间未知';

    return GestureDetector(
      onTap: isManualMode && id != null ? () => onSelect(id) : null,
      child: Container(
        width: 190,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelectedForEdit
              ? Colors.blue.withValues(alpha: 0.1)
              : (isPrimary
                  ? Colors.orangeAccent.withValues(alpha: 0.08)
                  : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelectedForEdit
                ? Colors.blue
                : (isPrimary
                    ? Colors.orangeAccent.withValues(alpha: 0.25)
                    : Colors.grey.withValues(alpha: 0.15)),
            width: isSelectedForEdit || isPrimary ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelectedForEdit
                      ? Icons.check_circle_rounded
                      : (isPrimary
                          ? Icons.push_pin_rounded
                          : Icons.schedule_rounded),
                  size: 14,
                  color: isSelectedForEdit
                      ? Colors.blue
                      : (isPrimary ? Colors.orangeAccent : Colors.grey),
                ),
                const SizedBox(width: 4),
                Text(
                  isPrimary ? "当前任务" : "冲突任务",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelectedForEdit
                        ? Colors.blue
                        : (isPrimary ? Colors.orangeAccent : Colors.grey),
                  ),
                ),
                if (update != null) ...[
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text("待调",
                        style: TextStyle(
                            fontSize: 9,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            _buildMiniInfoChip(_scheduleScopeLabel(data),
                isPrimary ? Colors.orangeAccent : Colors.blue),
            const SizedBox(height: 6),
            if (update == null)
              Text(
                originalTime,
                style: TextStyle(
                    fontSize: 11,
                    color: isSelectedForEdit
                        ? Colors.blue
                        : (isPrimary
                            ? Colors.orangeAccent
                            : Colors.grey.shade600),
                    fontWeight: isSelectedForEdit || isPrimary
                        ? FontWeight.w600
                        : FontWeight.normal),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    originalTime,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade400,
                      decoration: TextDecoration.lineThrough,
                      height: 1.1,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.arrow_right_alt_rounded,
                          size: 14, color: Colors.blue),
                      const SizedBox(width: 2),
                      Text(
                        '${sf.format(update.start)}~${sf.format(update.end)}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolutionModeSelector({
    required _ScheduleResolutionMode selectedMode,
    required bool recommendedEnabled,
    required bool groupEnabled,
    required ValueChanged<_ScheduleResolutionMode> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("处理方式",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildModeChip(
              mode: _ScheduleResolutionMode.recommend,
              label: "推荐调整",
              icon: Icons.auto_awesome_rounded,
              selected: selectedMode == _ScheduleResolutionMode.recommend,
              enabled: recommendedEnabled,
              onTap: () => onChanged(_ScheduleResolutionMode.recommend),
            ),
            const SizedBox(width: 10),
            _buildModeChip(
              mode: _ScheduleResolutionMode.group,
              label: "整组顺排",
              icon: Icons.account_tree_rounded,
              selected: selectedMode == _ScheduleResolutionMode.group,
              enabled: groupEnabled,
              onTap: () => onChanged(_ScheduleResolutionMode.group),
            ),
            const SizedBox(width: 10),
            _buildModeChip(
              mode: _ScheduleResolutionMode.manual,
              label: "手动编辑",
              icon: Icons.edit_calendar_rounded,
              selected: selectedMode == _ScheduleResolutionMode.manual,
              enabled: true,
              onTap: () => onChanged(_ScheduleResolutionMode.manual),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeChip({
    required _ScheduleResolutionMode mode,
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final color =
        selected ? Colors.blue : (enabled ? Colors.grey : Colors.grey.shade300);
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? Colors.blue : Colors.grey.withValues(alpha: 0.2),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  int _parseMs(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTimeRange? _suggestPreferredWindow(TodoItem item, List peers) {
    final startMs = item.createdDate ?? item.createdAt;
    final endMs = item.dueDate?.millisecondsSinceEpoch ?? 0;
    if (startMs <= 0 || endMs <= 0 || endMs <= startMs) return null;

    final durationMs = endMs - startMs;
    var candidateStart = startMs;
    var candidateEnd = candidateStart + durationMs;
    final busyRanges = peers
        .whereType<Map>()
        .map((peer) => Map<String, dynamic>.from(peer))
        .map((peer) => (
              start: _parseMs(peer['start_time'] ?? peer['startTime']),
              end: _parseMs(peer['end_time'] ?? peer['endTime']),
            ))
        .where((range) => range.start > 0 && range.end > range.start)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    for (final range in busyRanges) {
      if (!_rangesOverlap(
          candidateStart, candidateEnd, range.start, range.end)) {
        continue;
      }
      candidateStart = range.end + const Duration(minutes: 5).inMilliseconds;
      candidateEnd = candidateStart + durationMs;
    }

    if (candidateStart == startMs) return null;
    return DateTimeRange(
      start: DateTime.fromMillisecondsSinceEpoch(candidateStart),
      end: DateTime.fromMillisecondsSinceEpoch(candidateEnd),
    );
  }

  String _buildRecommendedResolutionLabel(
    TodoItem item,
    DateTimeRange recommendedWindow,
  ) {
    final startMs = item.createdDate ?? item.createdAt;
    final endMs = item.dueDate?.millisecondsSinceEpoch ?? 0;
    final durationMinutes = startMs > 0 && endMs > startMs
        ? ((endMs - startMs) / const Duration(minutes: 1).inMilliseconds)
            .round()
        : 0;
    final shiftedMinutes =
        ((recommendedWindow.start.millisecondsSinceEpoch - startMs) /
                const Duration(minutes: 1).inMilliseconds)
            .round();
    return '推荐：仅移动开始时间，保留 $durationMinutes 分钟时长。新时间为 '
        '${DateFormat('MM-dd HH:mm').format(recommendedWindow.start)} ~ '
        '${DateFormat('HH:mm').format(recommendedWindow.end)}'
        '${shiftedMinutes > 0 ? '，整体后移 $shiftedMinutes 分钟' : ''}。';
  }

  bool _rangesOverlap(int startA, int endA, int startB, int endB) {
    return startA < endB && endA > startB;
  }

  Map<String, ({DateTime start, DateTime end})> _buildGroupScheduleUpdates(
    TodoItem seed,
    List peers,
    List<TodoItem> allTodos,
  ) {
    final conflictChain = _buildDirectConflictItems(seed, peers, allTodos);
    if (conflictChain.length <= 1) return {};

    conflictChain.sort((a, b) {
      final byStart = _todoStartMs(a).compareTo(_todoStartMs(b));
      if (byStart != 0) return byStart;
      return _todoEndMs(a).compareTo(_todoEndMs(b));
    });

    final updates = <String, ({DateTime start, DateTime end})>{};
    var anchorEnd = 0;
    for (var i = 0; i < conflictChain.length; i++) {
      final todo = conflictChain[i];
      final startMs = _todoStartMs(todo);
      final endMs = _todoEndMs(todo);
      if (startMs <= 0 || endMs <= startMs) continue;

      final durationMs = endMs - startMs;
      if (i == 0) {
        anchorEnd = endMs;
        continue;
      }

      final minStart = anchorEnd + const Duration(minutes: 5).inMilliseconds;
      if (startMs < minStart) {
        updates[todo.id] = (
          start: DateTime.fromMillisecondsSinceEpoch(minStart),
          end: DateTime.fromMillisecondsSinceEpoch(minStart + durationMs),
        );
        anchorEnd = minStart + durationMs;
      } else {
        anchorEnd = endMs;
      }
    }
    return updates;
  }

  List<TodoItem> _buildDirectConflictItems(
    TodoItem seed,
    List peers,
    List<TodoItem> allTodos,
  ) {
    final seedStart = _todoStartMs(seed);
    final matched = <TodoItem>[seed];

    for (final peer in peers.whereType<Map>()) {
      final peerData = Map<String, dynamic>.from(peer);
      final peerId = _itemIdFromData(peerData);
      final peerStart = _parseMs(peerData['start_time'] ??
          peerData['startTime'] ??
          peerData['created_date'] ??
          peerData['createdDate']);
      final peerEnd = _parseMs(peerData['end_time'] ??
          peerData['endTime'] ??
          peerData['due_date'] ??
          peerData['dueDate']);

      final todo = allTodos.cast<TodoItem?>().firstWhere(
            (candidate) =>
                candidate != null &&
                !candidate.isDeleted &&
                !candidate.isAllDay &&
                !_isAllDayTask(candidate.toJson()) &&
                _todoEndMs(candidate) > _todoStartMs(candidate) &&
                _isSameLocalDayMs(_todoStartMs(candidate), seedStart) &&
                ((peerId != null && candidate.id == peerId) ||
                    (_itemTitle(peerData) == candidate.title &&
                        _todoStartMs(candidate) == peerStart &&
                        _todoEndMs(candidate) == peerEnd)),
            orElse: () => null,
          );
      if (todo != null && !matched.any((existing) => existing.id == todo.id)) {
        matched.add(todo);
      }
    }

    return matched
        .where((todo) => _isSameLocalDayMs(_todoStartMs(todo), seedStart))
        .toList();
  }

  bool _isSameLocalDayMs(int leftMs, int rightMs) {
    final left = DateTime.fromMillisecondsSinceEpoch(leftMs);
    final right = DateTime.fromMillisecondsSinceEpoch(rightMs);
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String? _itemIdFromData(Map<String, dynamic> data) {
    return (data['uuid'] ?? data['id'] ?? data['id_todo'])?.toString();
  }

  bool _isAllDayTask(Map<String, dynamic> data) {
    if (data['is_all_day'] == 1 ||
        data['is_all_day'] == true ||
        data['isAllDay'] == true) return true;
    final startMs = _parseMs(data['start_time'] ??
        data['startTime'] ??
        data['created_date'] ??
        data['createdDate']);
    final endMs = _parseMs(data['end_time'] ??
        data['endTime'] ??
        data['due_date'] ??
        data['dueDate']);
    if (startMs <= 0 || endMs <= startMs) return false;

    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(endMs);

    // 判定为全天任务：时间正好跨越 00:00 到 23:59 或次日 00:00
    if (start.hour == 0 && start.minute == 0) {
      if ((end.hour == 23 && end.minute == 59) ||
          (end.hour == 0 && end.minute == 0 && end.isAfter(start))) {
        return true;
      }
    }

    // 跨度超过 23.5 小时也视为全天
    if (endMs - startMs >=
        const Duration(hours: 23, minutes: 30).inMilliseconds) {
      return true;
    }

    return false;
  }

  int _todoStartMs(TodoItem item) => item.createdDate ?? item.createdAt;

  int _todoEndMs(TodoItem item) => item.dueDate?.millisecondsSinceEpoch ?? 0;

  Widget _buildMiniInfoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _openTodoEditor(TodoItem item) async {
    final allTodos =
        await StorageService.getTodos(widget.username, includeDeleted: true);
    final allGroups = await StorageService.getTodoGroups(widget.username,
        includeDeleted: true);
    final target = allTodos.cast<TodoItem?>().firstWhere(
          (todo) => todo?.id == item.id,
          orElse: () => null,
        );
    if (!mounted || target == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodoEditScreen(
          todo: target,
          todos: allTodos,
          onTodosChanged: (updatedTodos) {
            StorageService.saveTodos(widget.username, updatedTodos);
          },
          todoGroups: allGroups,
          onGroupsChanged: (updatedGroups) {
            StorageService.saveTodoGroups(widget.username, updatedGroups);
          },
          username: widget.username,
        ),
      ),
    );
    if (!mounted) return;
    await _loadConflicts();
  }

  Future<void> _persistResolvedTodos(
    Map<String, ({DateTime start, DateTime end})> updates, {
    required String successMessage,
    BuildContext? popContext,
  }) async {
    if (updates.isEmpty) return;
    setState(() => _isApplyingScheduleFix = true);
    try {
      final allTodos =
          await StorageService.getTodos(widget.username, includeDeleted: true);
      var appliedCount = 0;
      for (final todo in allTodos) {
        final update = updates[todo.id];
        if (update == null) continue;
        todo.createdDate = update.start.millisecondsSinceEpoch;
        todo.dueDate = update.end;
        todo.markAsChanged();
        appliedCount++;
      }
      if (appliedCount == 0) return;
      await StorageService.saveTodos(widget.username, allTodos);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (popContext != null && popContext.mounted) {
        Navigator.pop(popContext);
      } else if (mounted) {
        Navigator.pop(context);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      await _loadConflicts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('处理失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isApplyingScheduleFix = false);
    }
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

  final bool isEmbedded;

  const _ConflictResolutionSheet({
    required this.localItem,
    required this.serverItem,
    required this.table,
    required this.username,
    required this.onResolved,
    this.isEmbedded = false,
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
    if (widget.isEmbedded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildContent(context),
        ),
      );
    }

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
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
            ..._buildContent(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    final diffs = _buildDiffFields(widget.localItem, widget.serverItem);

    return [
      const Text("版本对齐建议",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(
        "检测到两端内容存在差异，请选择权威版本进行保留。",
        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
      ),
      if (diffs.isNotEmpty) ...[
        const SizedBox(height: 16),
        _buildDiffSummary(diffs),
      ] else ...[
        const SizedBox(height: 16),
        _buildDiffFallbackHint(),
      ],
      const SizedBox(height: 32),

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
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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
    ];
  }

  Widget _buildDiffSummary(List<_ConflictFieldDiff> diffs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                '差异字段',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${diffs.length} 项',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: diffs
                .map(
                  (diff) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diff.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '本地: ${diff.localValue}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '服务器: ${diff.serverValue}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffFallbackHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前没有匹配到可见字段差异。可能是其它隐藏字段、归一化值，或者服务端只保留了冲突标记。',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade700, height: 1.4),
            ),
          ),
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

  List<_ConflictFieldDiff> _buildDiffFields(
      Map<String, dynamic> local, Map<String, dynamic>? server) {
    if (server == null || server.isEmpty) return const [];

    final fields = <_ConflictFieldSpec>[
      _ConflictFieldSpec(
        label: '标题',
        keys: const ['content', 'title', 'name', 'courseName', 'course_name'],
      ),
      _ConflictFieldSpec(
        label: '备注',
        keys: const ['remark'],
      ),
      _ConflictFieldSpec(
        label: '完成状态',
        keys: const ['is_completed', 'isCompleted'],
      ),
      _ConflictFieldSpec(
        label: '删除状态',
        keys: const ['is_deleted', 'isDeleted'],
      ),
      _ConflictFieldSpec(
        label: '版本号',
        keys: const ['version'],
      ),
      _ConflictFieldSpec(
        label: '更新时间',
        keys: const ['updated_at', 'updatedAt'],
        formatter: _formatTimestamp,
      ),
      _ConflictFieldSpec(
        label: '创建时间',
        keys: const ['created_at', 'createdAt'],
        formatter: _formatTimestamp,
      ),
      _ConflictFieldSpec(
        label: '分组',
        keys: const ['group_id', 'groupId'],
      ),
      _ConflictFieldSpec(
        label: '团队',
        keys: const ['team_uuid', 'teamUuid'],
      ),
      _ConflictFieldSpec(
        label: '分类',
        keys: const ['category_id', 'categoryId'],
      ),
      _ConflictFieldSpec(
        label: '开始时间',
        keys: const ['start_time', 'startTime', 'created_date', 'createdDate'],
        formatter: _formatDateTimeMs,
      ),
      _ConflictFieldSpec(
        label: '结束/截止',
        keys: const [
          'end_time',
          'endTime',
          'due_date',
          'dueDate',
          'target_time',
          'targetTime'
        ],
        formatter: _formatDateTimeMs,
      ),
      _ConflictFieldSpec(
        label: '循环',
        keys: const ['recurrence'],
      ),
      _ConflictFieldSpec(
        label: '全天',
        keys: const ['is_all_day', 'isAllDay'],
      ),
      _ConflictFieldSpec(
        label: '协作类型',
        keys: const ['collab_type', 'collabType'],
      ),
      _ConflictFieldSpec(
        label: '提醒',
        keys: const ['reminder_minutes', 'reminderMinutes'],
      ),
      _ConflictFieldSpec(
        label: '星期',
        keys: const ['weekday'],
      ),
      _ConflictFieldSpec(
        label: '周次',
        keys: const ['week_index', 'weekIndex'],
      ),
      _ConflictFieldSpec(
        label: '地点',
        keys: const ['room_name', 'roomName'],
      ),
      _ConflictFieldSpec(
        label: '教师',
        keys: const ['teacher_name', 'teacherName'],
      ),
      _ConflictFieldSpec(
        label: '课名',
        keys: const ['course_name', 'courseName'],
      ),
    ];

    final diffs = <_ConflictFieldDiff>[];
    for (final field in fields) {
      final localValue = _extractFieldValue(local, field.keys);
      final serverValue = _extractFieldValue(server, field.keys);
      if (!_valuesEqual(localValue, serverValue)) {
        diffs.add(
          _ConflictFieldDiff(
            label: field.label,
            localValue: _formatFieldValue(localValue, field.formatter),
            serverValue: _formatFieldValue(serverValue, field.formatter),
          ),
        );
      }
    }

    return diffs;
  }

  dynamic _extractFieldValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) return data[key];
    }
    return null;
  }

  bool _valuesEqual(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return _normalizeComparableValue(a) == _normalizeComparableValue(b);
  }

  String _normalizeComparableValue(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? '1' : '0';
    if (value is num) return value.toString();
    if (value is Map || value is List) return jsonEncode(value);
    return value.toString().trim();
  }

  String _formatFieldValue(
      dynamic value, String Function(dynamic value)? formatter) {
    if (formatter != null) {
      return formatter(value);
    }
    final normalized = _normalizeComparableValue(value);
    return normalized.isEmpty ? '空' : normalized;
  }

  String _formatTimestamp(dynamic value) {
    final ms = _toMillis(value);
    if (ms == null || ms <= 0) return '空';
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  String _formatDateTimeMs(dynamic value) {
    final ms = _toMillis(value);
    if (ms == null || ms <= 0) return '空';
    return DateFormat('MM-dd HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  int? _toMillis(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
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
      widget.localItem.remove('conflict_data');
      widget.localItem.remove('serverVersionData');

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
        final messenger = ScaffoldMessenger.of(context);
        widget.onResolved();
        if (!widget.isEmbedded) {
          Navigator.pop(context);
        }
        messenger.showSnackBar(
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
        touchUpdatedAt: false,
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
        final messenger = ScaffoldMessenger.of(context);
        widget.onResolved();
        if (!widget.isEmbedded) {
          Navigator.pop(context);
        }
        messenger.showSnackBar(
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

class _ConflictFieldSpec {
  final String label;
  final List<String> keys;
  final String Function(dynamic value)? formatter;

  const _ConflictFieldSpec({
    required this.label,
    required this.keys,
    this.formatter,
  });
}

class _ConflictFieldDiff {
  final String label;
  final String localValue;
  final String serverValue;

  const _ConflictFieldDiff({
    required this.label,
    required this.localValue,
    required this.serverValue,
  });
}
