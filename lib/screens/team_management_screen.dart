import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:async';
import '../models.dart';
import '../services/api_service.dart';
import '../services/pomodoro_sync_service.dart';
import 'package:intl/intl.dart';
import './unified_waterfall_screen.dart';
import './conflict_inbox_screen.dart';
import './team_message_center_screen.dart';
import './team_announcement_screen.dart';
import '../storage_service.dart';

class TeamManagementScreen extends StatefulWidget {
  final String username;
  final String? initialTarget; // 🚀 新增：跳转目标
  const TeamManagementScreen(
      {super.key, required this.username, this.initialTarget});

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
  bool _isLoading = true;
  bool _isCheckingClipboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.dataRefreshNotifier.addListener(_onDataRefreshed);
    _loadTeams();
    _setupWsListener();
    _checkClipboardForInvite();
  }

  void _onDataRefreshed() {
    if (!mounted) return;
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
    WidgetsBinding.instance.removeObserver(this);
    StorageService.dataRefreshNotifier.removeListener(_onDataRefreshed);
    _wsSub?.cancel();
    super.dispose();
  }

  // 🚀 安全提取首字符工具函数（完美解决 Emoji 切割导致 UTF-16 崩溃的 Bug）
  String _safeFirstChar(String? s) {
    if (s == null || s.trim().isEmpty) return '?';
    final str = s.trim();
    if (str.runes.isEmpty) return '?';
    return String.fromCharCode(str.runes.first).toUpperCase();
  }

  Future<void> _checkClipboardForInvite() async {
    if (_isCheckingClipboard) return;
    _isCheckingClipboard = true;

    try {
      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        String text = data.text!;
        // 匹配格式：邀请您加入「XXX」团队。复制此消息后打开App即可加入。邀请码：[ABCDEF]
        RegExp regExp = RegExp(r'邀请码：\[([a-zA-Z0-9]+)\]');
        Match? match = regExp.firstMatch(text);

        if (match != null && match.groupCount >= 1) {
          String inviteCode = match.group(1)!;

          // 获取当前剪贴板内容后，清空剪贴板，避免每次打开都弹窗
          await Clipboard.setData(const ClipboardData(text: ''));

          if (mounted) {
            _showAutoJoinDialog(inviteCode);
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking clipboard: $e');
    } finally {
      _isCheckingClipboard = false;
    }
  }

  void _showAutoJoinDialog(String inviteCode) {
    bool isProcessing = false;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.blueAccent),
            ),
            const SizedBox(width: 12),
            const Text('发现团队邀请',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('检测到您复制了团队邀请口令，是否立即申请加入？'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('邀请码: $inviteCode',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            )
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('忽略', style: TextStyle(color: Colors.grey.shade600)),
          ),
          StatefulBuilder(builder: (ctx, setDialogState) {
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: isProcessing
                  ? null
                  : () async {
                      setDialogState(() => isProcessing = true);
                      try {
                        final res =
                            await ApiService.requestJoinTeam(inviteCode);
                        if (res['success'] == true) {
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          _loadTeams();
                          _showSuccessToast('申请已提交，请等待管理员审核 ⏳');
                        } else {
                          _showErrorToast(
                              res['error'] ?? res['message'] ?? '加入失败');
                        }
                      } finally {
                        if (ctx.mounted) {
                          setDialogState(() => isProcessing = false);
                        }
                      }
                    },
              child: isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('立即申请',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _loadTeams({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);
    try {
      // 🚀 核心优化：并发加载团队列表和我的邀请
      final teamsFuture = ApiService.fetchTeams();
      final invitationsFuture = ApiService.fetchMyInvitations();
      final localTodosFuture =
          StorageService.getTodos(widget.username, includeDeleted: false);

      final rawTeams = await teamsFuture;
      final invitations = await invitationsFuture;
      final localTodos = await localTodosFuture;

      // 并发加载所有管理团队的待处理请求数
      final adminTeamUuids = rawTeams
          .where((t) => t['role'] == 0)
          .map((t) => t['uuid'] as String)
          .toList();

      Map<String, int> pendingCounts = {};
      if (adminTeamUuids.isNotEmpty) {
        final pendingResults = await Future.wait(adminTeamUuids
            .map((uuid) => ApiService.fetchPendingRequests(uuid)));
        for (int i = 0; i < adminTeamUuids.length; i++) {
          pendingCounts[adminTeamUuids[i]] = pendingResults[i].length;
        }
      }

      final conflictCounts = <String, int>{};
      for (final todo in localTodos) {
        final teamUuid = todo.teamUuid;
        if (teamUuid != null && teamUuid.isNotEmpty && todo.hasConflict) {
          conflictCounts[teamUuid] = (conflictCounts[teamUuid] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _teams = rawTeams.map((t) => Team.fromJson(t)).toList();
          _myInvitations = invitations;
          _teamPendingCounts = pendingCounts;
          _teamConflictCounts = conflictCounts;
          _isLoading = false;
          // 🚀 默认选中第一个
          if (_selectedTeam == null && _teams.isNotEmpty) {
            _selectedTeam = _teams.first;
          } else if (_selectedTeam != null) {
            // 同步更新已选中的团队数据
            try {
              _selectedTeam =
                  _teams.firstWhere((t) => t.uuid == _selectedTeam!.uuid);
            } catch (_) {
              _selectedTeam = _teams.isNotEmpty ? _teams.first : null;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }

    // 🚀 核心：处理搜索直达逻辑
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleInitialTarget(widget.initialTarget!);
      });
    }
  }

  void _handleInitialTarget(String target) {
    if (!mounted) return;

    switch (target) {
      case 'messages':
        final managedTeams =
            _teams.where((t) => t.userRole == TeamRole.admin).toList();
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    TeamMessageCenterScreen(managedTeams: managedTeams)));
        break;
      case 'create':
        _showCreateTeamDialog();
        break;
      case 'announcements':
        if (_teams.isNotEmpty) {
          // 如果只有一个团队，直接进入公告；否则可能需要更复杂的选择逻辑，这里默认选第一个
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TeamAnnouncementScreen(team: _teams.first)));
        }
        break;
      case 'members':
        if (_teams.isNotEmpty) {
          _showMembersSheet(_teams.first);
        }
        break;
    }
  }

  // ============== 弹窗操作 ==============
  void _showCreateTeamDialog() {
    final controller = TextEditingController();
    _showCustomDialog(
      title: '创建协作团队',
      icon: Icons.group_add_rounded,
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: '输入一个响亮的团队名称...',
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800]
              : Colors.grey[100],
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        autofocus: true,
      ),
      actionText: '创建',
      onAction: (setDialogState) async {
        final name = controller.text.trim();
        if (name.isEmpty) return;
        setDialogState(() => true); // loading
        try {
          final navigator = Navigator.of(context);
          final res = await ApiService.createTeam(name);
          if (res['success'] == true) {
            if (!mounted) return;
            navigator.pop();
            _loadTeams();
            _showSuccessToast('团队创建成功 ✨');
          } else {
            _showErrorToast(res['error'] ?? res['message'] ?? '创建失败');
          }
        } finally {
          if (mounted) setDialogState(() => false);
        }
      },
    );
  }

  void _showJoinTeamDialog() {
    final controller = TextEditingController();
    _showCustomDialog(
      title: '加入协作团队',
      icon: Icons.link_rounded,
      content: TextField(
        controller: controller,
        onChanged: (text) {
          // 🚀 实时监听：如果用户直接粘贴了整段邀请长文案，自动提取并替换为纯邀请码
          RegExp regExp = RegExp(r'邀请码：\[([a-zA-Z0-9]+)\]');
          Match? match = regExp.firstMatch(text);
          if (match != null && match.groupCount >= 1) {
            final extractedCode = match.group(1)!;
            controller.value = TextEditingValue(
              text: extractedCode,
              selection: TextSelection.collapsed(offset: extractedCode.length),
            );
          }
        },
        decoration: InputDecoration(
          hintText: '请输入团队邀请码...',
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800]
              : Colors.grey[100],
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        autofocus: true,
      ),
      actionText: '提交申请',
      onAction: (setDialogState) async {
        String code = controller.text.trim();
        if (code.isEmpty) return;

        // 🚀 双重防线：提交前再次确保提取的是纯邀请码
        RegExp regExp = RegExp(r'邀请码：\[([a-zA-Z0-9]+)\]');
        Match? match = regExp.firstMatch(code);
        if (match != null && match.groupCount >= 1) {
          code = match.group(1)!;
        }

        setDialogState(() => true); // loading
        try {
          final navigator = Navigator.of(context);
          final res = await ApiService.requestJoinTeam(code);
          if (res['success'] == true) {
            if (!mounted) return;
            navigator.pop();
            _loadTeams();
            _showSuccessToast('申请已提交，请等待管理员审核 ⏳');
          } else {
            _showErrorToast(res['error'] ?? res['message'] ?? '加入失败');
          }
        } finally {
          if (mounted) setDialogState(() => false);
        }
      },
    );
  }

  void _showCustomDialog({
    required String title,
    required IconData icon,
    required Widget content,
    required String actionText,
    required Future<void> Function(
            void Function(bool Function()) setDialogState)
        onAction,
  }) {
    bool isProcessing = false;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.blueAccent),
            ),
            const SizedBox(width: 12),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: content,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          StatefulBuilder(builder: (ctx, setDialogState) {
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: isProcessing
                  ? null
                  : () async {
                      await onAction((updateLoading) {
                        setDialogState(() {
                          isProcessing = updateLoading();
                        });
                      });
                    },
              child: isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(actionText,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
            );
          }),
        ],
      ),
    );
  }

  void _showSuccessToast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating));
  void _showErrorToast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating));

  Widget _buildMessageCenterAction() {
    int totalPending =
        _teamPendingCounts.values.fold(0, (sum, count) => sum + count);
    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: '消息中心',
            onPressed: () {
              final managedTeams =
                  _teams.where((t) => t.userRole == TeamRole.admin).toList();
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          TeamMessageCenterScreen(managedTeams: managedTeams)));
            },
          ),
          if (totalPending > 0)
            Positioned(
              right: 8,
              top: 12,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.redAccent, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  totalPending > 9 ? '9+' : totalPending.toString(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============== 核心页面构建 ==============
  Widget _buildCountBadge(int count, Color color, {IconData? icon}) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: icon == null ? 6 : 8, vertical: 5),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            count > 99 ? '99+' : count.toString(),
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
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
                              : Colors.black.withValues(alpha: 0.05))),
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
                      key: ValueKey(_selectedTeam!.uuid), // 强制刷新
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.blueAccent,
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
            parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          _buildSliverAppBar(isDark),
          if (_isLoading)
            _buildTeamSkeleton(isDark)
          else ...[
            _buildQuickActionsSliver(isWide),
            if (_myInvitations.isNotEmpty)
              SliverToBoxAdapter(child: _buildInvitationsSection()),
            if (_teams.isEmpty && _myInvitations.isEmpty)
              SliverFillRemaining(
                  hasScrollBody: false, child: _buildEmptyState(isDark))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildTeamCard(_teams[index], isDark),
                    childCount: _teams.length,
                  ),
                ),
              ),
          ],
        ],
      ),
      floatingActionButton: _buildSpeedDial(context, isDark),
    );
  }

  Widget _buildSliverAppBar(bool isDark) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 60,
      elevation: 0,
      backgroundColor: isDark
          ? Colors.black.withValues(alpha: 0.65)
          : Colors.white.withValues(alpha: 0.65),
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(color: Colors.transparent),
        ),
      ),
      title: const Text('团队协作',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      centerTitle: false,
      actions: [_buildMessageCenterAction()],
    );
  }

  Widget _buildQuickActionsSliver(bool isWide) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            _buildQuickActionCard(
              title: "全景汇聚",
              desc: isWide ? "汇集所有团队任务的时间轴展示" : "所有团队任务时间轴",
              icon: Icons.waterfall_chart_rounded,
              color: Colors.blueAccent,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          UnifiedWaterfallScreen(username: widget.username))),
            ),
            const SizedBox(width: 12),
            _buildQuickActionCard(
              title: "冲突中心",
              desc: isWide ? "处理多终端同步产生的数据争议" : "解决多端同步冲突",
              icon: Icons.verified_user_rounded,
              color: Colors.orangeAccent,
              badgeCount:
                  _teamConflictCounts.values.fold(0, (sum, count) => sum + count),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ConflictInboxScreen(username: widget.username))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterList(bool isDark) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: const Text('团队列表',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          actions: [_buildMessageCenterAction()],
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        _buildQuickActionsSliver(true), // 🚀 新增：宽屏模式下显示全景汇聚和冲突中心
        if (_myInvitations.isNotEmpty)
          SliverToBoxAdapter(child: _buildInvitationsSection()),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final team = _teams[index];
                final isSelected = _selectedTeam?.uuid == team.uuid;
                final pendingCount = _teamPendingCounts[team.uuid] ?? 0;
                final conflictCount = _teamConflictCounts[team.uuid] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => setState(() => _selectedTeam = team),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blueAccent.withValues(alpha: 0.1)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.white),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isSelected
                                ? Colors.blueAccent.withValues(alpha: 0.3)
                                : Colors.transparent),
                      ),
                      child: Row(
                        children: [
                          _buildTeamAvatar(team),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(team.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                    overflow: TextOverflow.ellipsis),
                                Text('${team.memberCount} 位成员',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          if (conflictCount > 0) ...[
                            _buildCountBadge(conflictCount, Colors.orangeAccent,
                                icon: Icons.schedule_rounded),
                            const SizedBox(width: 6),
                          ],
                          if (pendingCount > 0)
                            _buildCountBadge(pendingCount, Colors.redAccent),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: _teams.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dashboard_customize_rounded,
              size: 80, color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('请从左侧选择一个团队进行管理', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  void _showSpeedDialMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSpeedDial(
          context, Theme.of(context).brightness == Brightness.dark),
    );
  }

  // ============== 组件构建 ==============
  Widget _buildEmptyState(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.05),
              shape: BoxShape.circle),
          child: Icon(Icons.groups_2_rounded,
              size: 72, color: Colors.blueAccent.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 24),
        Text('还没加入任何团队哦',
            style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('创建或加入团队，开启高效协作之旅',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: _showCreateTeamDialog,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('创建团队',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blueAccent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                side:
                    BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              onPressed: _showJoinTeamDialog,
              icon: const Icon(Icons.link_rounded, size: 20),
              label: const Text('加入团队',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildInvitationsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Icon(Icons.mark_email_unread_rounded,
                  size: 18, color: Colors.blueAccent),
              const SizedBox(width: 8),
              const Text('待处理的邀请',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.blueAccent)),
            ],
          ),
        ),
        ..._myInvitations.map((inv) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.blueAccent.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                            color: Colors.blueAccent.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                      backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                      child: const Icon(Icons.groups_rounded,
                          color: Colors.blueAccent)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize:
                          MainAxisSize.min, // 🚀 避免 RenderFlex OVERFLOWING
                      children: [
                        Text(inv['team_name'] ?? '未知团队',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('来自 ${inv['inviter_name']} 的邀请',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.grey.withValues(alpha: 0.1)),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () =>
                            _handleInvitation(inv['team_uuid'], 'decline'),
                        tooltip: '忽略',
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.blueAccent.withValues(alpha: 0.1)),
                        icon: const Icon(Icons.check_rounded,
                            size: 18, color: Colors.blueAccent),
                        onPressed: () =>
                            _handleInvitation(inv['team_uuid'], 'accept'),
                        tooltip: '加入',
                      ),
                    ],
                  )
                ],
              ),
            )),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _handleInvitation(String teamUuid, String action) async {
    final res = await ApiService.respondToInvitation(teamUuid, action);
    if (res['success'] == true) {
      _loadTeams();
      _showSuccessToast(action == 'accept' ? '已成功加入团队 ✨' : '已忽略该邀请');
    } else {
      _showErrorToast(res['error'] ?? '操作失败');
    }
  }

  Widget _buildQuickActionCard(
      {required String title,
      required String desc,
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
      int badgeCount = 0}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? color.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.2 : 0.1)),
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(desc,
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white70 : Colors.black54),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (badgeCount > 0)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    badgeCount > 9 ? '9+' : badgeCount.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamCard(Team team, bool isDark) {
    final pendingCount = _teamPendingCounts[team.uuid] ?? 0;
    final conflictCount = _teamConflictCounts[team.uuid] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部：Avatar + 标题 + 角色
            Row(
              children: [
                _buildTeamAvatar(team),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize:
                        MainAxisSize.min, // 🚀 避免 RenderFlex OVERFLOWING
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(team.name,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1)),
                          if (team.userRole == TeamRole.admin)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color:
                                      Colors.blueAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Text('管理员',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blueAccent,
                                      fontWeight: FontWeight.bold)),
                            ),
                          if (conflictCount > 0) ...[
                            const SizedBox(width: 6),
                            _buildCountBadge(conflictCount, Colors.orangeAccent,
                                icon: Icons.schedule_rounded),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                          '创建于 ${DateFormat('yyyy年MM月dd日').format(DateTime.fromMillisecondsSinceEpoch(team.createdAt))}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),

            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1)),

            // 中部：人数 + 邀请码
            Row(
              children: [
                Icon(Icons.people_alt_rounded,
                    size: 16, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text('${team.memberCount} 位成员',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                if (team.inviteCode != null)
                  InkWell(
                    onTap: () {
                      final inviteText =
                          '邀请您加入「${team.name}」团队进行协作。复制此消息后打开App即可自动申请加入。\n\n邀请码：[${team.inviteCode}]';
                      Clipboard.setData(ClipboardData(text: inviteText));
                      _showSuccessToast('邀请文案已复制，快去分享吧 📋');
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Text('邀请码: ${team.inviteCode}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          Icon(Icons.copy_rounded,
                              size: 12, color: Colors.grey.shade500),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // 底部操作栏
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      side:
                          BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    onPressed: () => _showMembersSheet(team),
                    icon: pendingCount > 0
                        ? Badge(
                            label: Text('$pendingCount'),
                            child: const Icon(
                                Icons.admin_panel_settings_rounded,
                                size: 18),
                          )
                        : const Icon(Icons.manage_accounts_rounded, size: 18),
                    label: Text(pendingCount > 0 ? '审批申请' : '成员管理',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(
                          color: Colors.orangeAccent.withValues(alpha: 0.2)),
                    ),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                TeamAnnouncementScreen(team: team))),
                    icon: const Icon(Icons.campaign_rounded, size: 18),
                    label: const Text('团队公告', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                      foregroundColor: Colors.blueAccent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () =>
                        _showInviteOptionsSheet(team), // 🚀 修改点：点击后弹出选择框
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('邀请加入',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                // 更多菜单
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded,
                      color: Colors.grey.shade600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  onSelected: (value) {
                    if (value == 'share') {
                      _handleGenerateCode(team);
                    } else if (value == 'leave') {
                      _confirmLeaveTeam(team);
                    } else if (value == 'delete') {
                      _confirmDeleteTeam(team);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'share',
                        child: Row(children: [
                          Icon(Icons.share_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('重置/生成邀请码')
                        ])),
                    if (team.userRole == TeamRole.admin)
                      const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_forever_rounded,
                                size: 18, color: Colors.red),
                            SizedBox(width: 12),
                            Text('解散团队', style: TextStyle(color: Colors.red))
                          ]))
                    else
                      const PopupMenuItem(
                          value: 'leave',
                          child: Row(children: [
                            Icon(Icons.exit_to_app_rounded,
                                size: 18, color: Colors.orange),
                            SizedBox(width: 12),
                            Text('退出团队', style: TextStyle(color: Colors.orange))
                          ])),
                  ],
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTeamAvatar(Team team) {
    final colors = [
      Colors.blueAccent,
      Colors.purpleAccent,
      Colors.orangeAccent,
      Colors.teal,
      Colors.indigo
    ];
    final color = colors[team.uuid.hashCode % colors.length];
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.1)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
      ),
      child: Center(
        child: Text(
          _safeFirstChar(team.name), // 🚀 修复 UTF-16 切片奔溃 Bug
          style: TextStyle(
              color: color, fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // 🚀 新增：邀请选项弹窗
  void _showInviteOptionsSheet(Team team) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding:
            const EdgeInsets.only(top: 12, bottom: 32, left: 24, right: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text('邀请新成员',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _buildInviteOption(
              icon: Icons.copy_all_rounded,
              title: '分享邀请码',
              subtitle: '复制邀请话术发送给好友，点击自动申请',
              color: Colors.blueAccent,
              onTap: () {
                Navigator.pop(context);
                final inviteText =
                    '邀请您加入「${team.name}」团队进行协作。复制此消息后打开App即可自动申请加入。\n\n邀请码：[${team.inviteCode}]';
                Clipboard.setData(ClipboardData(text: inviteText));
                _showSuccessToast('邀请文案已复制 📋');
              },
            ),
            const SizedBox(height: 12),
            _buildInviteOption(
              icon: Icons.alternate_email_rounded,
              title: '邮件邀请',
              subtitle: '直接通过账号邮箱添加，无需审核',
              color: Colors.purpleAccent,
              onTap: () {
                Navigator.pop(context);
                _showAddMemberDialog(team);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteOption(
      {required IconData icon,
      required String title,
      required String subtitle,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(20),
          color: color.withValues(alpha: 0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _showAddMemberDialog(Team team) {
    final controller = TextEditingController();
    _showCustomDialog(
      title: '添加团队成员',
      icon: Icons.person_add_rounded,
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: '输入对方的注册邮箱...',
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800]
              : Colors.grey[100],
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
      ),
      actionText: '添加',
      onAction: (setDialogState) async {
        final email = controller.text.trim();
        if (email.isEmpty) return;
        setDialogState(() => true);
        try {
          final navigator = Navigator.of(context);
          final res = await ApiService.addTeamMemberByEmail(team.uuid, email);
          if (res['success'] == true) {
            if (!mounted) return;
            navigator.pop();
            _loadTeams();
            _showSuccessToast('成员添加成功 ✨');
          } else {
            _showErrorToast(res['error'] ?? res['message'] ?? '添加失败');
          }
        } finally {
          if (mounted) setDialogState(() => false);
        }
      },
    );
  }

  void _showMembersSheet(Team team) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: _TeamMembersView(
              team: team,
              scrollController: scrollController,
              onRefresh: _loadTeams),
        ),
      ),
    );
  }

  void _handleGenerateCode(Team team) async {
    final res = await ApiService.generateInviteCode(team.uuid);
    if (res['success'] == true) {
      _loadTeams();
      _showSuccessToast('邀请码已更新 ✨');
    }
  }

  void _confirmLeaveTeam(Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出团队'),
        content: Text('确定要退出「${team.name}」吗？退出后将无法查看该团队的协作任务。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.leaveTeam(team.uuid);
              if (res['success'] == true) {
                // 🚀 核心修复：立即清理本地缓存的该团队数据，触发首页刷新
                await StorageService.clearTeamItems(team.uuid);
                _loadTeams();
                _showSuccessToast('已退出团队');
              } else {
                _showErrorToast(res['error'] ?? '退出失败');
              }
            },
            child: const Text('确定退出', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTeam(Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解散团队'),
        content: Text('警告：此操作不可逆！解散「${team.name}」将删除所有团队数据并移除所有成员。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.deleteTeam(team.uuid);
              if (res['success'] == true) {
                // 🚀 核心修复：立即清理本地缓存的该团队数据，触发首页刷新
                await StorageService.clearTeamItems(team.uuid);
                _loadTeams();
                _showSuccessToast('团队已解散');
              } else {
                _showErrorToast(res['error'] ?? '解散失败');
              }
            },
            child: const Text('确定解散', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedDial(BuildContext context, bool isDark) {
    return FloatingActionButton(
      backgroundColor: Colors.blueAccent,
      onPressed: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            padding:
                const EdgeInsets.only(top: 12, bottom: 32, left: 24, right: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 24),
                const Text('团队操作',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                ListTile(
                  leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.blueAccent)),
                  title: const Text('创建新团队',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('开启一个全新的协作项目'),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateTeamDialog();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.link_rounded,
                          color: Colors.orangeAccent)),
                  title: const Text('加入已有团队',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('通过邀请码加入其他协作小组'),
                  onTap: () {
                    Navigator.pop(context);
                    _showJoinTeamDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
    );
  }

  // 🚀 团队协作骨架屏
  Widget _buildTeamSkeleton(bool isDark) {
    final baseColor =
        isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              // 快速操作入口骨架
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  children: [
                    Expanded(
                        child: Container(
                            height: 80,
                            decoration: BoxDecoration(
                                color: baseColor,
                                borderRadius: BorderRadius.circular(24)))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Container(
                            height: 80,
                            decoration: BoxDecoration(
                                color: baseColor,
                                borderRadius: BorderRadius.circular(24)))),
                  ],
                ),
              );
            }
            // 团队卡片骨架
            return Container(
              height: 100,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: baseColor, borderRadius: BorderRadius.circular(20)),
            );
          },
          childCount: 5,
        ),
      ),
    );
  }
}

// ============== 团队详情看板 (Master-Detail Detail) ==============
class _TeamDetailView extends StatefulWidget {
  final Team team;
  final VoidCallback onRefresh;
  final String username;
  const _TeamDetailView(
      {super.key,
      required this.team,
      required this.onRefresh,
      required this.username});

  @override
  State<_TeamDetailView> createState() => _TeamDetailViewState();
}

class _TeamDetailViewState extends State<_TeamDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;

    return Column(
      children: [
        // 头部概览
        Container(
          padding: const EdgeInsets.all(24),
          color: cardColor,
          child: Column(
            children: [
              Row(
                children: [
                  _buildTeamAvatarLarge(widget.team),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.team.name,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                            '创建于 ${DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(widget.team.createdAt))}',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 13)),
                      ],
                    ),
                  ),
                  _buildHeaderActions(),
                ],
              ),
              const SizedBox(height: 24),
              TabBar(
                controller: _tabController,
                isScrollable: false,
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.blueAccent,
                unselectedLabelColor: Colors.grey,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: '公告动态'),
                  Tab(text: '成员管理'),
                  Tab(text: '设置与管理'),
                ],
              ),
            ],
          ),
        ),
        // 内容区
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: 公告
              _TeamAnnouncementView(team: widget.team),
              // Tab 2: 成员
              _TeamMembersView(
                  team: widget.team,
                  scrollController: ScrollController(),
                  onRefresh: widget.onRefresh),
              // Tab 3: 管理
              _TeamSettingsView(team: widget.team, onRefresh: widget.onRefresh),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTeamAvatarLarge(Team team) {
    final colors = [
      Colors.blueAccent,
      Colors.purpleAccent,
      Colors.orangeAccent,
      Colors.teal,
      Colors.indigo
    ];
    final color = colors[team.uuid.hashCode % colors.length];
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          color.withValues(alpha: 0.4),
          color.withValues(alpha: 0.1)
        ]),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.5), width: 3),
      ),
      child: Center(
        child: Text(
          team.name.isNotEmpty ? team.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: color, fontSize: 32, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildHeaderActions() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: widget.onRefresh,
          tooltip: '刷新数据',
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          onPressed: () {
            Clipboard.setData(ClipboardData(
                text:
                    '邀请您加入「${widget.team.name}」团队，邀请码：[${widget.team.inviteCode}]'));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('邀请码已复制 📋')));
          },
          icon: const Icon(Icons.person_add_rounded, size: 20),
          label: const Text('复制邀请码',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ============== 公告内嵌视图 ==============
class _TeamAnnouncementView extends StatefulWidget {
  final Team team;
  const _TeamAnnouncementView({required this.team});

  @override
  State<_TeamAnnouncementView> createState() => _TeamAnnouncementViewState();
}

class _TeamAnnouncementViewState extends State<_TeamAnnouncementView> {
  List<dynamic> _announcements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.fetchTeamAnnouncements(widget.team.uuid);
      if (mounted) {
        setState(() {
          _announcements = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_announcements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined,
                size: 64, color: Colors.grey.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('暂无团队公告', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _announcements.length,
      itemBuilder: (context, index) {
        final ann = _announcements[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          color: Theme.of(context).cardColor.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign_rounded,
                        color: Colors.orangeAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(ann['title'] ?? '未命名公告',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16))),
                    Builder(builder: (context) {
                      DateTime date;
                      final rawDate = ann['created_at'];
                      if (rawDate is int) {
                        date = DateTime.fromMillisecondsSinceEpoch(rawDate);
                      } else {
                        date = DateTime.tryParse(rawDate?.toString() ?? '') ??
                            DateTime.now();
                      }
                      return Text(DateFormat('MM-dd HH:mm').format(date),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500));
                    }),
                  ],
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider()),
                Text(ann['content'] ?? '',
                    style: const TextStyle(fontSize: 14, height: 1.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============== 团队设置内嵌视图 ==============
class _TeamSettingsView extends StatelessWidget {
  final Team team;
  final VoidCallback onRefresh;
  const _TeamSettingsView({required this.team, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isAdmin = team.userRole == TeamRole.admin;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('通用信息',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey,
                letterSpacing: 1.2)),
        const SizedBox(height: 16),
        _buildSettingItem(
          context,
          icon: Icons.vpn_key_rounded,
          color: Colors.blueAccent,
          title: '团队邀请码',
          subtitle: team.inviteCode ?? '尚未生成',
          trailing:
              const Icon(Icons.copy_rounded, size: 18, color: Colors.grey),
          onTap: () {
            Clipboard.setData(ClipboardData(text: team.inviteCode ?? ''));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('邀请码已复制')));
          },
        ),
        if (isAdmin) ...[
          const SizedBox(height: 32),
          const Text('管理操作',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.redAccent,
                  letterSpacing: 1.2)),
          const SizedBox(height: 16),
          _buildSettingItem(
            context,
            icon: Icons.refresh_rounded,
            color: Colors.blueAccent,
            title: '重置邀请码',
            subtitle: '旧的邀请码将立即失效',
            onTap: () async {
              await ApiService.generateInviteCode(team.uuid);
              onRefresh();
            },
          ),
          const SizedBox(height: 12),
          _buildSettingItem(
            context,
            icon: Icons.delete_forever_rounded,
            color: Colors.redAccent,
            title: '解散团队',
            subtitle: '删除所有团队任务与成员，此操作不可逆',
            onTap: () {
              // 触发解散弹窗
            },
          ),
        ] else ...[
          const SizedBox(height: 32),
          _buildSettingItem(
            context,
            icon: Icons.exit_to_app_rounded,
            color: Colors.orange,
            title: '退出团队',
            subtitle: '退出后将不再接收此团队的任务同步',
            onTap: () {
              // 触发退出弹窗
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSettingItem(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      Widget? trailing,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ============== 成员列表子视图 ==============
class _TeamMembersView extends StatefulWidget {
  final Team team;
  final ScrollController scrollController;
  final VoidCallback onRefresh;
  const _TeamMembersView(
      {required this.team,
      required this.scrollController,
      required this.onRefresh});

  @override
  __TeamMembersViewState createState() => __TeamMembersViewState();
}

class __TeamMembersViewState extends State<_TeamMembersView> {
  List<dynamic> _members = [];
  List<dynamic> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final members = await ApiService.fetchTeamMembers(widget.team.uuid);
    List<dynamic> requests = [];
    if (widget.team.userRole == TeamRole.admin) {
      requests = await ApiService.fetchPendingRequests(widget.team.uuid);
    }
    setState(() {
      _members = members;
      _requests = requests;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Icon(Icons.manage_accounts_rounded,
                  color: Colors.blueAccent),
              const SizedBox(width: 12),
              Text('成员管理 - ${widget.team.name}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (!_loading)
                Text('${_members.length} 人',
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (_requests.isNotEmpty) ...[
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Text('待审批申请',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent)),
                      ),
                      ..._requests.map((r) => _buildRequestItem(r)),
                      const SizedBox(height: 16),
                      const Divider(),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Text('团队成员',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ..._members.map((m) => _buildMemberItem(m)),
                    const SizedBox(height: 40),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildRequestItem(dynamic r) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.1))),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
              child: Text(r['username']?[0]?.toUpperCase() ?? '?',
                  style: const TextStyle(color: Colors.blueAccent))),
          const SizedBox(width: 12),
          Expanded(
              child: Text(r['username'] ?? '未知用户',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          TextButton(
              onPressed: () => _handleRequest(r, 'reject'),
              child: const Text('拒绝', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => _handleRequest(r, 'approve'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('同意'),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberItem(dynamic m) {
    final bool isAdmin = m['role'] == 0;
    final bool isMe = m['is_me'] == true || m['id'] == ApiService.currentUserId;

    return ListTile(
      leading: CircleAvatar(
          backgroundColor: isAdmin
              ? Colors.blueAccent.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          child: Text(m['username']?[0]?.toUpperCase() ?? '?',
              style:
                  TextStyle(color: isAdmin ? Colors.blueAccent : Colors.grey))),
      title: Text('${m['username']}${isMe ? ' (我)' : ''}',
          style: TextStyle(
              fontWeight: isMe ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(isAdmin ? '管理员' : '成员',
          style: TextStyle(
              fontSize: 12, color: isAdmin ? Colors.blueAccent : Colors.grey)),
      trailing: (widget.team.userRole == TeamRole.admin && !isAdmin)
          ? IconButton(
              icon: const Icon(Icons.person_remove_rounded,
                  color: Colors.redAccent, size: 20),
              onPressed: () => _confirmRemoveMember(m),
            )
          : null,
    );
  }

  Future<void> _handleRequest(dynamic r, String action) async {
    final res = await ApiService.processJoinRequest(
        widget.team.uuid, r['user_id'], action);
    if (res['success'] == true) {
      _loadData();
      widget.onRefresh();
    }
  }

  void _confirmRemoveMember(dynamic m) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定要将「${m['username']}」从团队中移除吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.removeTeamMember(
                  widget.team.uuid, m['user_id']);
              if (res['success'] == true) {
                _loadData();
                widget.onRefresh();
              }
            },
            child: const Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

