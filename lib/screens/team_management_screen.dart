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

class TeamManagementScreen extends StatefulWidget {
  final String username;
  const TeamManagementScreen({Key? key, required this.username}) : super(key: key);

  @override
  _TeamManagementScreenState createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> with WidgetsBindingObserver {
  StreamSubscription? _wsSub;
  List<Team> _teams = [];
  List<dynamic> _myInvitations = [];
  Map<String, int> _teamPendingCounts = {};
  bool _isLoading = true;
  bool _isCheckingClipboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTeams();
    _setupWsListener();
    _checkClipboardForInvite();
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
          state.action == 'TEAM_REMOVED') {
        _loadTeams(isSilent: true); // 🚀 收到通知，静默刷新
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.blueAccent),
            ),
            const SizedBox(width: 12),
            const Text('发现团队邀请', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('邀请码: $inviteCode', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
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
            bool isProcessing = false;
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: isProcessing ? null : () async {
                setDialogState(() => isProcessing = true);
                try {
                  final res = await ApiService.requestJoinTeam(inviteCode);
                  if (res['success'] == true) {
                    Navigator.pop(context);
                    _loadTeams();
                    _showSuccessToast('申请已提交，请等待管理员审核 ⏳');
                  } else {
                    _showErrorToast(res['error'] ?? res['message'] ?? '加入失败');
                  }
                } finally {
                  if (ctx.mounted) setDialogState(() => isProcessing = false);
                }
              },
              child: isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('立即申请', style: TextStyle(fontWeight: FontWeight.bold)),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _loadTeams({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);
    try {
      final rawTeams = await ApiService.fetchTeams();
      final invitations = await ApiService.fetchMyInvitations();

      Map<String, int> pendingCounts = {};
      for(var t in rawTeams) {
        if (t['role'] == 0) { // 管理员
          final requests = await ApiService.fetchPendingRequests(t['uuid']);
          pendingCounts[t['uuid']] = requests.length;
        }
      }

      if (mounted) {
        setState(() {
          _teams = rawTeams.map((t) => Team.fromJson(t)).toList();
          _myInvitations = invitations;
          _teamPendingCounts = pendingCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
          fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        autofocus: true,
      ),
      actionText: '创建',
      onAction: (setDialogState) async {
        final name = controller.text.trim();
        if (name.isEmpty) return;
        setDialogState(() => true); // loading
        try {
          final res = await ApiService.createTeam(name);
          if (res['success'] == true) {
            Navigator.pop(context);
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
          fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          final res = await ApiService.requestJoinTeam(code);
          if (res['success'] == true) {
            Navigator.pop(context);
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
    required Future<void> Function(void Function(bool Function()) setDialogState) onAction,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.blueAccent),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            bool isProcessing = false;
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: isProcessing ? null : () async {
                await onAction((updateLoading) {
                  setDialogState(() {
                    isProcessing = updateLoading();
                  });
                });
              },
              child: isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(actionText, style: const TextStyle(fontWeight: FontWeight.bold)),
            );
          }),
        ],
      ),
    );
  }

  void _showSuccessToast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green.shade600, behavior: SnackBarBehavior.floating));
  void _showErrorToast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));

  // ============== 核心页面构建 ==============
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FA);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            expandedHeight: 60,
            elevation: 0,
            backgroundColor: isDark ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.65),
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(color: Colors.transparent),
              ),
            ),
            title: const Text('团队协作', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            centerTitle: false,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '刷新数据',
                  onPressed: _loadTeams,
                ),
              ),
            ],
          ),

          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else ...[
            // 🚀 顶部业务入口区 (瀑布流 + 冲突中心)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    _buildQuickActionCard(
                      title: "全景汇聚",
                      desc: "所有团队任务时间轴",
                      icon: Icons.waterfall_chart_rounded,
                      color: Colors.blueAccent,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UnifiedWaterfallScreen(username: widget.username))),
                    ),
                    const SizedBox(width: 12),
                    _buildQuickActionCard(
                      title: "冲突中心",
                      desc: "解决多端同步冲突",
                      icon: Icons.verified_user_rounded,
                      color: Colors.orangeAccent,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConflictInboxScreen(username: widget.username))),
                    ),
                  ],
                ),
              ),
            ),

            // 🚀 邀请待办区
            if (_myInvitations.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildInvitationsSection(),
              ),

            // 🚀 团队列表区 / 空状态
            if (_teams.isEmpty && _myInvitations.isEmpty)
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

  // ============== 组件构建 ==============
  Widget _buildEmptyState(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.05), shape: BoxShape.circle),
          child: Icon(Icons.groups_2_rounded, size: 72, color: Colors.blueAccent.withOpacity(0.5)),
        ),
        const SizedBox(height: 24),
        Text('还没加入任何团队哦', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('创建或加入团队，开启高效协作之旅', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: _showCreateTeamDialog,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('创建团队', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: BorderSide(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              onPressed: _showJoinTeamDialog,
              icon: const Icon(Icons.link_rounded, size: 20),
              label: const Text('加入团队', style: TextStyle(fontWeight: FontWeight.bold)),
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
              Icon(Icons.mark_email_unread_rounded, size: 18, color: Colors.blueAccent),
              const SizedBox(width: 8),
              const Text('待处理的邀请', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueAccent)),
            ],
          ),
        ),
        ..._myInvitations.map((inv) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.blueAccent.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.blueAccent.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: Colors.blueAccent.withOpacity(0.1), child: const Icon(Icons.groups_rounded, color: Colors.blueAccent)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // 🚀 避免 RenderFlex OVERFLOWING
                  children: [
                    Text(inv['team_name'] ?? '未知团队', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('来自 ${inv['inviter_name']} 的邀请', style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.grey.withOpacity(0.1)),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => _handleInvitation(inv['team_uuid'], 'decline'),
                    tooltip: '忽略',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.1)),
                    icon: const Icon(Icons.check_rounded, size: 18, color: Colors.blueAccent),
                    onPressed: () => _handleInvitation(inv['team_uuid'], 'accept'),
                    tooltip: '加入',
                  ),
                ],
              )
            ],
          ),
        )).toList(),
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

  Widget _buildQuickActionCard({required String title, required String desc, required IconData icon, required Color color, required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? color.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(isDark ? 0.2 : 0.1)),
            boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // 🚀 避免 RenderFlex OVERFLOWING
                  children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(desc, style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamCard(Team team, bool isDark) {
    final pendingCount = _teamPendingCounts[team.uuid] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.04),
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
                    mainAxisSize: MainAxisSize.min, // 🚀 避免 RenderFlex OVERFLOWING
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(team.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1)),
                          if (team.userRole == TeamRole.admin)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: const Text('管理员', style: TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('创建于 ${DateFormat('yyyy年MM月dd日').format(DateTime.fromMillisecondsSinceEpoch(team.createdAt))}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),

            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),

            // 中部：人数 + 邀请码
            Row(
              children: [
                Icon(Icons.people_alt_rounded, size: 16, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text('${team.memberCount} 位成员', style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (team.inviteCode != null)
                  InkWell(
                    onTap: () {
                      final inviteText = '邀请您加入「${team.name}」团队进行协作。复制此消息后打开App即可自动申请加入。\n\n邀请码：[${team.inviteCode}]';
                      Clipboard.setData(ClipboardData(text: inviteText));
                      _showSuccessToast('邀请文案已复制，快去分享吧 📋');
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Text('邀请码: ${team.inviteCode}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          Icon(Icons.copy_rounded, size: 12, color: Colors.grey.shade500),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                    ),
                    onPressed: () => _showMembersSheet(team),
                    icon: pendingCount > 0
                        ? Badge(
                      label: Text('$pendingCount'),
                      child: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                    )
                        : const Icon(Icons.manage_accounts_rounded, size: 18),
                    label: Text(pendingCount > 0 ? '审批申请' : '成员管理', style: const TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withOpacity(0.1),
                      foregroundColor: Colors.blueAccent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _showInviteOptionsSheet(team), // 🚀 修改点：点击后弹出选择框
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('邀请加入', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                // 更多菜单
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded, color: Colors.grey.shade600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share_rounded, size: 18), SizedBox(width: 12), Text('重置/生成邀请码')])),
                    if (team.userRole == TeamRole.admin)
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_forever_rounded, size: 18, color: Colors.red), SizedBox(width: 12), Text('解散团队', style: TextStyle(color: Colors.red))]))
                    else
                      const PopupMenuItem(value: 'leave', child: Row(children: [Icon(Icons.exit_to_app_rounded, size: 18, color: Colors.orange), SizedBox(width: 12), Text('退出团队', style: TextStyle(color: Colors.orange))])),
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
    final colors = [Colors.blueAccent, Colors.purpleAccent, Colors.orangeAccent, Colors.teal, Colors.indigo];
    final color = colors[team.uuid.hashCode % colors.length];
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5), width: 2),
      ),
      child: Center(
        child: Text(
          _safeFirstChar(team.name), // 🚀 修复 UTF-16 切片奔溃 Bug
          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold),
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
        padding: const EdgeInsets.only(top: 12, bottom: 32, left: 24, right: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 5,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const Text('邀请新成员', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.copy_rounded, color: Colors.green),
              ),
              title: const Text('复制邀请口令', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text('发送给微信/QQ好友，对方打开App可自动识别', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                Navigator.pop(context);
                if (team.inviteCode != null && team.inviteCode!.isNotEmpty) {
                  final inviteText = '邀请您加入「${team.name}」团队进行协作。复制此消息后打开App即可自动申请加入。\n\n邀请码：[${team.inviteCode}]';
                  Clipboard.setData(ClipboardData(text: inviteText));
                  _showSuccessToast('邀请文案已复制，快去分享吧 📋');
                } else {
                  await _handleGenerateCode(team);
                }
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.email_rounded, color: Colors.blueAccent),
              ),
              title: const Text('通过邮箱邀请', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text('直接向对方的注册邮箱发送系统邀请', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
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

  Future<void> _handleGenerateCode(Team team) async {
    final res = await ApiService.generateInviteCode(team.uuid);
    if (res['success'] == true) {
      final inviteText = '邀请您加入「${team.name}」团队进行协作。复制此消息后打开App即可自动申请加入。\n\n邀请码：[${res['code']}]';
      Clipboard.setData(ClipboardData(text: inviteText));
      _showSuccessToast('新邀请码 ${res['code']} 已生成，包含邀请文案已复制');
      _loadTeams(); // 刷新数据以显示新邀请码
    } else {
      _showErrorToast('生成邀请码失败');
    }
  }

  void _confirmDeleteTeam(Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.red), SizedBox(width: 8), Text('解散团队')]),
        content: Text('确定要解散 "${team.name}" 吗？\n\n此操作不可恢复，所有关联的团队任务将转为个人的私有任务。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, elevation: 0),
            onPressed: () async {
              Navigator.pop(context);
              _showProcessingDialog();
              final res = await ApiService.deleteTeam(team.uuid);
              Navigator.pop(context);
              if (res['success'] == true) {
                _loadTeams();
                _showSuccessToast('团队已解散');
              } else {
                _showErrorToast(res['error'] ?? '解散失败');
              }
            },
            child: const Text('确认解散'),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveTeam(Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [Icon(Icons.exit_to_app_rounded, color: Colors.orange), SizedBox(width: 8), Text('退出团队')]),
        content: Text('确定要退出 "${team.name}" 吗？退出后将无法查看该团队的数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, elevation: 0),
            onPressed: () async {
              Navigator.pop(context);
              _showProcessingDialog();
              final res = await ApiService.leaveTeam(team.uuid);
              Navigator.pop(context);
              if (res['success'] == true) {
                _loadTeams();
                _showSuccessToast('已成功退出团队');
              } else {
                _showErrorToast(res['error'] ?? '退出失败');
              }
            },
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
  }

  void _showProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }

  // ============== 成员与审批底部抽屉 ==============
  void _showMembersSheet(Team team) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) {
          return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))],
              ),
              child: Column(
                children: [
                  // 顶部拖拽指示器
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const Text('团队管理', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(team.name, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700)),
                        ),
                        const Spacer(),
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.grey.withOpacity(0.1)),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMemberSheetTabs(team, scrollController),
                ],
              )
          );
        },
      ),
    );
  }

  Widget _buildMemberSheetTabs(Team team, ScrollController scrollController) {
    final pendingCount = _teamPendingCounts[team.uuid] ?? 0;

    return Expanded(
      child: DefaultTabController(
        length: team.userRole == TeamRole.admin ? 2 : 1,
        child: Column(
          children: [
            TabBar(
              labelColor: Colors.blueAccent,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blueAccent,
              dividerColor: Colors.grey.withOpacity(0.1),
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                const Tab(text: '所有成员'),
                if (team.userRole == TeamRole.admin)
                  Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('入队申请'),
                          if (pendingCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                              child: Text('$pendingCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          ]
                        ],
                      )
                  ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildMembersList(team, scrollController),
                  if (team.userRole == TeamRole.admin) _buildRequestsList(team, scrollController),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersList(Team team, ScrollController scrollController) {
    return FutureBuilder<List<dynamic>>(
      future: ApiService.fetchTeamMembers(team.uuid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final members = snapshot.data?.map((m) => TeamMember.fromJson(m)).toList() ?? [];
        if (members.isEmpty) return Center(child: Text('暂无成员', style: TextStyle(color: Colors.grey.shade500)));

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
            final isAdmin = member.role == TeamRole.admin;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: Colors.blueAccent.withOpacity(0.1),
                foregroundColor: Colors.blueAccent,
                child: Text(_safeFirstChar(member.username)), // 🚀 修复 UTF-16 切片奔溃 Bug
              ),
              title: Text(member.username ?? '匿名用户', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('加入于 ${DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(member.joinedAt))}', style: const TextStyle(fontSize: 12)),
              trailing: isAdmin
                  ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text('管理员', style: TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
              )
                  : (team.userRole == TeamRole.admin)
                  ? IconButton(
                  icon: const Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 20),
                  tooltip: '移除成员',
                  onPressed: () => _confirmRemoveMember(team, member)
              )
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsList(Team team, ScrollController scrollController) {
    return FutureBuilder<List<dynamic>>(
      future: ApiService.fetchPendingRequests(team.uuid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('当前没有待处理的申请', style: TextStyle(color: Colors.grey.shade500)),
                ],
              )
          );
        }

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: Colors.orangeAccent.withOpacity(0.1),
                    foregroundColor: Colors.orangeAccent,
                    child: Text(_safeFirstChar(req['username'])) // 🚀 修复 UTF-16 切片奔溃 Bug
                ),
                title: Text(req['username'] ?? '未知用户', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(req['message'] != null && req['message'].isNotEmpty ? '留言: ${req['message']}' : '申请加入团队', style: const TextStyle(fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1)),
                      icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                      onPressed: () => _handleProcessRequest(team.uuid, req['user_id'], 'reject'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.1)),
                      icon: const Icon(Icons.check_rounded, color: Colors.green, size: 18),
                      onPressed: () => _handleProcessRequest(team.uuid, req['user_id'], 'approve'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleProcessRequest(String teamUuid, int userId, String action) async {
    final res = await ApiService.processJoinRequest(teamUuid, userId, action);
    if (res['success'] == true) {
      _loadTeams();
      Navigator.pop(context); // Close sheet
      _showSuccessToast(action == 'approve' ? '已同意该用户加入团队' : '已拒绝该申请');
    } else {
      _showErrorToast(res['error'] ?? '操作失败');
    }
  }

  void _confirmRemoveMember(Team team, TeamMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('移除成员'),
        content: Text('确定要将 "${member.username}" 移出团队吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, elevation: 0),
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              _showProcessingDialog();
              final res = await ApiService.removeTeamMember(team.uuid, member.userId);
              Navigator.pop(context); // Close processing
              if (res['success'] == true) {
                Navigator.pop(context); // Close sheet
                _loadTeams();
                _showSuccessToast('已将该成员移出团队');
              } else {
                _showErrorToast(res['error'] ?? '移除失败');
              }
            },
            child: const Text('确定移除'),
          ),
        ],
      ),
    );
  }

  void _showAddMemberDialog(Team team) {
    final controller = TextEditingController();
    _showCustomDialog(
      title: '邀请新成员',
      icon: Icons.person_add_rounded,
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: '请输入对方登录邮箱...',
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        keyboardType: TextInputType.emailAddress,
        autofocus: true,
      ),
      actionText: '发送邀请',
      onAction: (setDialogState) async {
        final email = controller.text.trim();
        if (email.isEmpty) return;
        setDialogState(() => true);
        try {
          final res = await ApiService.addTeamMemberByEmail(team.uuid, email);
          if (res['success'] == true) {
            Navigator.pop(context);
            _loadTeams();
            _showSuccessToast('入队邀请已成功发送 ✨');
          } else {
            _showErrorToast(res['error'] ?? res['message'] ?? '邀请失败');
          }
        } finally {
          if (mounted) setDialogState(() => false);
        }
      },
    );
  }

  // ============== 悬浮菜单 ==============
  Widget _buildSpeedDial(BuildContext context, bool isDark) {
    return FloatingActionButton.extended(
      elevation: 4,
      backgroundColor: Colors.blueAccent,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            padding: const EdgeInsets.only(top: 12, bottom: 32, left: 24, right: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 5,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Text('管理团队', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.group_add_rounded, color: Colors.blueAccent),
                  ),
                  title: const Text('创建新团队', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: const Text('成为管理员，邀请他人加入协作', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateTeamDialog();
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.orangeAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.link_rounded, color: Colors.orangeAccent),
                  ),
                  title: const Text('使用邀请码加入', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: const Text('输入由其他人分享的邀请码加入团队', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded),
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
      icon: const Icon(Icons.add_rounded),
      label: const Text('新建 / 加入', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }
}