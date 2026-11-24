import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models.dart';
import '../services/api_service.dart';
import '../services/pomodoro_sync_service.dart';
import '../utils/app_dialogs.dart';

import 'package:intl/intl.dart';

import './unified_waterfall_screen.dart';
import './conflict_inbox_screen.dart';
import './team_message_center_screen.dart';
import './team_announcement_screen.dart';
import './team_share_manage_screen.dart';
import '../storage_service.dart';
import '../services/course_service.dart';
import '../services/ai_todo_chat_launcher.dart';
import '../services/ai_todo_action_executor.dart';
import '../services/pomodoro_service.dart';
import '../services/conflict_visibility_service.dart';
import '../services/database_helper.dart';
import '../utils/page_transitions.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/optional_liquid_glass_surface.dart';

part 'team_management/team_management_data_and_dialogs.dart';
part 'team_management/team_management_list_views.dart';
part 'team_management/team_management_cards_and_actions.dart';
part 'team_management/team_management_sub_views.dart';

final Map<String, _TeamManagementSnapshot> _cachedSnapshots = {};

final Map<(String?, String), DateFormat> _teamManagementDateFormats = {};

DateFormat _teamManagementDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _teamManagementDateFormats.putIfAbsent((
    locale,
    pattern,
  ), () => DateFormat(pattern, locale));
}

final RegExp _teamInviteCopyCodePattern = RegExp(r'邀请码：\[([a-zA-Z0-9]+)\]');

String? normalizeInviteCode(String? code) {
  final value = code?.trim();
  if (value == null || value.isEmpty || value.toLowerCase() == 'null') {
    return null;
  }
  return value.toUpperCase();
}

class TeamManagementScreen extends StatefulWidget {
  final String username;
  final String? initialTarget; // 🚀 新增：跳转目标
  const TeamManagementScreen({
    super.key,
    required this.username,
    this.initialTarget,
  });

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen>
    with WidgetsBindingObserver {
  StreamSubscription? _wsSub;
  Team? _selectedTeam;
  List<Team> _teams = [];
  List<dynamic> _myInvitations = [];
  Map<String, int> _teamPendingCounts = {};
  Map<String, int> _teamConflictCounts = {};
  int _totalConflictCount = 0;
  bool _isLoading = true;
  bool _isCheckingClipboard = false;
  int _teamLoadGeneration = 0;
  String? _activeCacheOwnerKey;
  Animation<double>? _routeAnimation;
  void Function(AnimationStatus)? _routeAnimationListener;
  final GlobalKey _panoramaActionKey = GlobalKey();
  final GlobalKey _conflictActionKey = GlobalKey();
  final GlobalKey _messageCenterActionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.scopedDataRefreshNotifier.addListener(_onDataRefreshed);
    _activeCacheOwnerKey = _cacheOwnerKey;
    _restoreCachedSnapshot();
    _setupWsListener();
    _schedulePostTransitionInit();
  }

  void _schedulePostTransitionInit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.isCompleted) {
        _runPostTransitionInit();
        return;
      }
      _routeAnimation = animation;
      _routeAnimationListener = (status) {
        if (status == AnimationStatus.completed) {
          _clearRouteAnimationListener();
          if (mounted) {
            _runPostTransitionInit();
          }
        }
      };
      animation.addStatusListener(_routeAnimationListener!);
    });
  }

  void _clearRouteAnimationListener() {
    if (_routeAnimation != null && _routeAnimationListener != null) {
      _routeAnimation!.removeStatusListener(_routeAnimationListener!);
    }
    _routeAnimation = null;
    _routeAnimationListener = null;
  }

  void _runPostTransitionInit() {
    _loadTeams(isSilent: _hasCachedSnapshot);
    _checkClipboardForInvite();
  }

  @override
  void didUpdateWidget(covariant TeamManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerKey = _cacheOwnerKey;
    if (_activeCacheOwnerKey == ownerKey) return;

    _activeCacheOwnerKey = ownerKey;
    _teamLoadGeneration++;
    _selectedTeam = null;
    _teams = [];
    _myInvitations = [];
    _teamPendingCounts = {};
    _teamConflictCounts = {};
    _totalConflictCount = 0;
    _isLoading = true;
    _restoreCachedSnapshot();
    _loadTeams(isSilent: _hasCachedSnapshot);
  }

  String? get _cacheOwnerKey {
    final token = ApiService.getToken();
    if (token == null || token.isEmpty) return null;
    final tokenDigest = sha256.convert(utf8.encode(token));
    return '${ApiService.syncServerKey}:$tokenDigest:${widget.username.trim()}';
  }

  _TeamManagementSnapshot? get _cachedSnapshot {
    final ownerKey = _cacheOwnerKey;
    return ownerKey == null ? null : _cachedSnapshots[ownerKey];
  }

  bool get _hasCachedSnapshot {
    final snapshot = _cachedSnapshot;
    return snapshot != null &&
        (snapshot.teams.isNotEmpty || snapshot.invitations.isNotEmpty);
  }

  void _restoreCachedSnapshot() {
    if (!_hasCachedSnapshot) return;
    final snapshot = _cachedSnapshot!;
    _teams = List<Team>.from(snapshot.teams);
    _myInvitations = List<dynamic>.from(snapshot.invitations);
    _teamPendingCounts = Map<String, int>.from(snapshot.pendingCounts);
    _teamConflictCounts = Map<String, int>.from(snapshot.conflictCounts);
    _totalConflictCount = snapshot.totalConflictCount;
    _selectedTeam = _selectedTeam != null
        ? _teams.where((t) => t.uuid == _selectedTeam!.uuid).firstOrNull
        : (_teams.isNotEmpty ? _teams.first : null);
    _isLoading = false;
  }

  void _onDataRefreshed() {
    if (!mounted) return;
    final signal = StorageService.scopedDataRefreshNotifier.value;
    const relevantDomains = {
      DataRefreshDomain.teams,
      DataRefreshDomain.todos,
      DataRefreshDomain.todoGroups,
      DataRefreshDomain.countdowns,
      DataRefreshDomain.habits,
    };
    if (!signal.domains.contains(DataRefreshDomain.all) &&
        signal.domains.intersection(relevantDomains).isEmpty) {
      return;
    }
    _loadTeams(isSilent: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForInvite();
    }
  }

  void _setupWsListener() {
    _wsSub = PomodoroSyncService.instance.onStateChanged.listen((state) {
      if (state.action == 'NEW_INVITATION' ||
          state.action == 'NEW_JOIN_REQUEST' ||
          state.action == 'PENDING_COUNTS' ||
          state.action == 'JOIN_REQUEST_APPROVED' ||
          state.action == 'TEAM_MEMBER_JOINED' ||
          state.action == 'NEW_ANNOUNCEMENT' ||
          state.action == 'TEAM_REMOVED') {
        _loadTeams(isSilent: true); // 🚀 收到通知，静默刷新
      }
    });
  }

  @override
  void dispose() {
    _clearRouteAnimationListener();
    WidgetsBinding.instance.removeObserver(this);
    StorageService.scopedDataRefreshNotifier.removeListener(_onDataRefreshed);
    _wsSub?.cancel();
    super.dispose();
  }

  // 🚀 安全提取首字符工具函数（完美解决 Emoji 切割导致 UTF-16 崩溃的 Bug）

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FA);

    if (isWide) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Row(
          children: [
            // 左侧侧边栏 (Master)
            SizedBox(
              width: 380,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: _buildMasterList(isDark),
              ),
            ),
            // 右侧详情区 (Detail)
            Expanded(
              child: _selectedTeam == null
                  ? _buildDetailEmptyState(isDark)
                  : _TeamDetailView(
                      team: _selectedTeam!,
                      onRefresh: _loadTeams,
                      username: widget.username,
                      copyInviteText: _copyTeamInviteText,
                      copyInviteCode: _copyInviteCode,
                      onDeleteTeam: _confirmDeleteTeam,
                      onLeaveTeam: _confirmLeaveTeam,
                      key: ValueKey(_selectedTeam!.uuid), // 强制刷新
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingGlassActionButton.small(
          backgroundColor: Theme.of(context).colorScheme.secondary,
          onPressed: _showSpeedDialMenu,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      );
    }

    // 手机端原始布局
    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          _buildSliverAppBar(isDark),
          FloatingGlassSliverContentFadeGroup(
            topBarHeight: floatingGlassTopBarHeight(context),
            slivers: [
              SliverToBoxAdapter(child: _buildScanProgressBanner()),
              _buildQuickActionsSliver(isWide),
              if (_myInvitations.isNotEmpty)
                SliverToBoxAdapter(child: _buildInvitationsSection()),
              if (_isLoading && _teams.isEmpty && _myInvitations.isEmpty)
                _buildInitialLoadingState(isDark)
              else if (_teams.isEmpty && _myInvitations.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(isDark),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildTeamCard(_teams[index], isDark),
                      findChildIndexCallback: (Key key) {
                        if (key is ValueKey<String>) {
                          final uuid = key.value;
                          final index = _teams.indexWhere(
                            (t) => t.uuid == uuid,
                          );
                          return index != -1 ? index : null;
                        }
                        return null;
                      },
                      childCount: _teams.length,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: _buildSpeedDial(context, isDark),
    );
  }
}
