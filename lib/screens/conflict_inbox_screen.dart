import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage_service.dart';
import '../services/api_service.dart';
import '../services/course_service.dart';
import '../services/ai_todo_chat_launcher.dart';
import '../utils/app_dialogs.dart';
import '../services/ai_todo_action_executor.dart';
import '../services/pomodoro_service.dart';
import '../services/conflict_visibility_service.dart';
import '../services/todo_editor_save_service.dart';
import '../utils/page_transitions.dart';
import '../widgets/floating_glass_control.dart';

import '../widgets/todo_section_widget.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import '../features/habits/models/habit_goal.dart';
import '../features/habits/models/habit_goal_rule.dart';
import '../services/storage/habit_storage.dart';
import '../utils/json_value_parser.dart';

part 'conflict_inbox/conflict_inbox_layout.dart';
part 'conflict_inbox/conflict_inbox_cards_and_banners.dart';
part 'conflict_inbox/conflict_inbox_batch_actions.dart';
part 'conflict_inbox/conflict_inbox_schedule_resolution.dart';
part 'conflict_inbox/conflict_resolution_sheet.dart';

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
  List<dynamic> _timeConflictItems = [];
  List<dynamic> _otherConflictItems = [];
  List<dynamic> _ghostConflictItems = [];
  Map<String, Map<String, dynamic>> _syncConflictVersionsByItemId = {};
  bool _isLoading = true;
  bool _isScanning = false;
  bool _isApplyingScheduleFix = false;
  _ConflictFilter _selectedFilter = _ConflictFilter.all;
  dynamic _selectedItem; // 🚀 新增：当前选中的冲突项，用于桌面端双栏展示

  // 🚀 批量操作相关
  bool _isBatchMode = false;
  final Set<String> _selectedConflictIds = {};
  bool _isBatchApplying = false;
  int _loadGeneration = 0;

  bool get _isWide => MediaQuery.sizeOf(context).width > 900;

  String _getConflictId(dynamic item) {
    if (item is TodoItem) return 'todo_${item.id}';
    if (item is TodoGroup) return 'group_${item.id}';
    if (item is CountdownItem) return 'countdown_${item.id}';
    if (item is HabitGoal) return 'goal_${item.uuid}';
    if (item is HabitGoalRuleRevision) return 'rule_${item.uuid}';
    return '';
  }

  @override
  void initState() {
    super.initState();
    _cacheSyncConflictVersions();
    StorageService.scopedDataRefreshNotifier.addListener(_onDataRefreshed);
    _loadConflicts();
  }

  @override
  void didUpdateWidget(covariant ConflictInboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.syncConflicts, widget.syncConflicts)) {
      _cacheSyncConflictVersions();
      _ghostConflictItems = _collectGhostConflictItems(_conflictItems);
    }
  }

  void _cacheSyncConflictVersions() {
    final conflicts = widget.syncConflicts;
    if (conflicts == null || conflicts.isEmpty) {
      _syncConflictVersionsByItemId = {};
      return;
    }

    final versionsByItemId = <String, Map<String, dynamic>>{};
    for (final conflict in conflicts) {
      final itemId = conflict.item['uuid'] ?? conflict.item['id'];
      if (itemId is String && itemId.isNotEmpty) {
        versionsByItemId.putIfAbsent(itemId, () => conflict.conflictWith);
      }
    }
    _syncConflictVersionsByItemId = versionsByItemId;
  }

  @override
  void dispose() {
    StorageService.scopedDataRefreshNotifier.removeListener(_onDataRefreshed);
    super.dispose();
  }

  void _onDataRefreshed() {
    if (!mounted) return;
    final signal = StorageService.scopedDataRefreshNotifier.value;
    const relevantDomains = {
      DataRefreshDomain.todos,
      DataRefreshDomain.todoGroups,
      DataRefreshDomain.countdowns,
      DataRefreshDomain.habits,
    };
    if (!signal.domains.contains(DataRefreshDomain.all) &&
        signal.domains.intersection(relevantDomains).isEmpty) {
      return;
    }
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    final loadGeneration = ++_loadGeneration;
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        StorageService.getTodos(widget.username, includeDeleted: true),
        StorageService.getTodoGroups(widget.username, includeDeleted: true),
        StorageService.getCountdowns(widget.username, includeDeleted: true),
        HabitStorage.getHabitGoals(includeDeleted: true),
        HabitStorage.getRuleRevisions(includeDeleted: true),
      ]);

      final todos = results[0] as List<TodoItem>;
      final groups = results[1] as List<TodoGroup>;
      final countdowns = results[2] as List<CountdownItem>;
      final habitGoals = results[3] as List<HabitGoal>;
      final habitRules = results[4] as List<HabitGoalRuleRevision>;

      if (!mounted || loadGeneration != _loadGeneration) return;

      final List<dynamic> items = [];
      items.addAll(
        todos.where(ConflictVisibilityService.isVisibleTodoConflict),
      );
      items.addAll(
        groups.where(ConflictVisibilityService.isVisibleTodoGroupConflict),
      );
      items.addAll(
        countdowns.where(ConflictVisibilityService.isVisibleCountdownConflict),
      );
      items.addAll(
        habitGoals.where(ConflictVisibilityService.isVisibleHabitGoalConflict),
      );
      items.addAll(
        habitRules.where(ConflictVisibilityService.isVisibleHabitRuleConflict),
      );

      items.sort((a, b) {
        int timeA = (a is TodoItem)
            ? a.updatedAt
            : (a is TodoGroup)
            ? a.updatedAt
            : (a is CountdownItem)
            ? a.updatedAt
            : (a is HabitGoal)
            ? a.updatedAt
            : (a as HabitGoalRuleRevision).updatedAt;
        int timeB = (b is TodoItem)
            ? b.updatedAt
            : (b is TodoGroup)
            ? b.updatedAt
            : (b is CountdownItem)
            ? b.updatedAt
            : (b is HabitGoal)
            ? b.updatedAt
            : (b as HabitGoalRuleRevision).updatedAt;
        return timeB.compareTo(timeA);
      });

      final timeConflictItems = <dynamic>[];
      final otherConflictItems = <dynamic>[];
      for (final item in items) {
        if (_isLocalScheduleConflict(item)) {
          timeConflictItems.add(item);
        } else {
          otherConflictItems.add(item);
        }
      }
      final ghostConflictItems = _collectGhostConflictItems(items);

      if (mounted) {
        setState(() {
          _conflictItems = items;
          _timeConflictItems = timeConflictItems;
          _otherConflictItems = otherConflictItems;
          _ghostConflictItems = ghostConflictItems;
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('ConflictInbox load failed: $error');
      if (mounted && loadGeneration == _loadGeneration) {
        setState(() => _isLoading = false);
      }
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
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text('扫描完成：$total 项冲突，个人-个人 $pp，个人-团队 $pt，团队-团队 $tt'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
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
      if (ConflictVisibilityService.isVersionConflictData(persisted)) {
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
    if (item is HabitGoal &&
        item.conflictData != null &&
        item.conflictData!.isNotEmpty &&
        _sameItem(item.conflictData!, itemId)) {
      return item.conflictData;
    }
    if (item is HabitGoalRuleRevision &&
        item.conflictData != null &&
        item.conflictData!.isNotEmpty &&
        _sameItem(item.conflictData!, itemId)) {
      return item.conflictData;
    }

    return _syncConflictVersionsByItemId[itemId];
  }

  Map<String, dynamic>? _conflictData(dynamic item) {
    if (item is TodoItem) return item.serverVersionData;
    if (item is TodoGroup) return item.conflictData;
    if (item is CountdownItem) return item.conflictData;
    if (item is HabitGoal) return item.conflictData;
    if (item is HabitGoalRuleRevision) return item.conflictData;
    return null;
  }

  bool _isLocalScheduleConflict(dynamic item) {
    return ConflictVisibilityService.isLocalScheduleConflictData(
      _conflictData(item),
    );
  }

  String _conflictLabel(dynamic item) {
    return _isLocalScheduleConflict(item) ? '时间冲突' : '其他冲突';
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

  Map<String, dynamic> _visibleConflictItemsById() {
    final itemsById = <String, dynamic>{};
    for (final item in _visibleConflictItems) {
      itemsById.putIfAbsent(_getConflictId(item), () => item);
    }
    return itemsById;
  }

  List<dynamic> _collectGhostConflictItems(Iterable<dynamic> items) {
    final ghostItems = <dynamic>[];
    for (final item in items) {
      if (item is! TodoItem) continue;
      final data = _findServerVersion(item);
      if ((data == null || data.isEmpty) &&
          !ConflictVisibilityService.isLocalScheduleConflictData(
            _conflictData(item),
          )) {
        ghostItems.add(item);
      }
    }
    return ghostItems;
  }

  String? _itemId(dynamic item) {
    if (item is TodoItem) return item.id;
    if (item is TodoGroup) return item.id;
    if (item is CountdownItem) return item.id;
    if (item is HabitGoal) return item.uuid;
    if (item is HabitGoalRuleRevision) return item.uuid;
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
    if (item is HabitGoal) return 'habit_goals';
    if (item is HabitGoalRuleRevision) return 'habit_goal_rule_revisions';
    return '';
  }

  Map<String, dynamic> _itemToJson(dynamic item) {
    if (item is TodoItem) return item.toJson();
    if (item is TodoGroup) return item.toJson();
    if (item is CountdownItem) return item.toJson();
    if (item is HabitGoal) return item.toJson();
    if (item is HabitGoalRuleRevision) return item.toJson();
    return {};
  }

  Future<bool> _keepLocalAndQueueSync(
    dynamic item, {
    bool syncNow = true,
  }) async {
    final localJson = _itemToJson(item);
    final table = _resolveTable(item);
    final uuid = (localJson['uuid'] ?? localJson['id'] ?? '').toString();
    if (uuid.isEmpty || table.isEmpty) return false;

    final serverVersion = _findServerVersion(item);
    final serverVer = (serverVersion?['version'] as num?)?.toInt() ?? 0;
    final currentVer = (localJson['version'] as num?)?.toInt() ?? 1;
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
    } catch (e) {
      // debugPrint(
      //     'resolve_conflict keep_local API failed (will retry via oplog): $e');
    }

    if (syncNow) {
      Future.microtask(() => StorageService.syncData(widget.username));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: FloatingGlassScrollAware(
        child: Stack(
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
      ),
    );
  }

  void _mutateState(VoidCallback fn) => setState(fn);
}
