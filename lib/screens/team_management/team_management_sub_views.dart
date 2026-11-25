part of '../team_management_screen.dart';

class _TeamManagementSnapshot {
  const _TeamManagementSnapshot({
    required this.teams,
    required this.invitations,
    required this.pendingCounts,
    required this.conflictCounts,
    required this.totalConflictCount,
  });

  final List<Team> teams;
  final List<dynamic> invitations;
  final Map<String, int> pendingCounts;
  final Map<String, int> conflictCounts;
  final int totalConflictCount;
}

// ============== 团队详情看板 (Master-Detail Detail) ==============
class _TeamDetailView extends StatefulWidget {
  final Team team;
  final VoidCallback onRefresh;
  final String username;
  final Future<void> Function(Team team) copyInviteText;
  final Future<void> Function(Team team) copyInviteCode;
  final void Function(Team team) onDeleteTeam;
  final void Function(Team team) onLeaveTeam;
  const _TeamDetailView({
    super.key,
    required this.team,
    required this.onRefresh,
    required this.username,
    required this.copyInviteText,
    required this.copyInviteCode,
    required this.onDeleteTeam,
    required this.onLeaveTeam,
  });

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
                        Text(
                          widget.team.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '创建于 ${AppTimeFormats.dateFormatter('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(widget.team.createdAt))}',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
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
                indicatorColor: Theme.of(context).colorScheme.secondary,
                labelColor: Theme.of(context).colorScheme.secondary,
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
                onRefresh: widget.onRefresh,
              ),
              // Tab 3: 管理
              _TeamSettingsView(
                team: widget.team,
                onRefresh: widget.onRefresh,
                copyInviteCode: widget.copyInviteCode,
                onDeleteTeam: widget.onDeleteTeam,
                onLeaveTeam: widget.onLeaveTeam,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTeamAvatarLarge(Team team) {
    final colors = [
      Theme.of(context).colorScheme.secondary,
      Colors.purpleAccent,
      Colors.orangeAccent,
      Colors.teal,
      Colors.indigo,
    ];
    final color = colors[team.uuid.hashCode % colors.length];
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0.1)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.5), width: 3),
      ),
      child: Center(
        child: Text(
          team.name.isNotEmpty ? team.name[0].toUpperCase() : '?',
          style: TextStyle(
            color: color,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderActions() {
    final isAdmin = widget.team.userRole == TeamRole.admin;
    final colorScheme = Theme.of(context).colorScheme;
    final actionShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    const actionPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    const actionMinimumSize = Size(0, 48);

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: widget.onRefresh,
          tooltip: '刷新数据',
        ),
        const SizedBox(width: 8),
        if (isAdmin)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              padding: actionPadding,
              minimumSize: actionMinimumSize,
              shape: actionShape,
              side: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeamShareManageScreen(team: widget.team),
              ),
            ),
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('分享'),
          ),
        const SizedBox(width: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: actionPadding,
            minimumSize: actionMinimumSize,
            shape: actionShape,
          ),
          onPressed: () => unawaited(widget.copyInviteText(widget.team)),
          icon: const Icon(Icons.person_add_rounded, size: 20),
          label: const Text(
            '复制邀请码',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
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
            Icon(
              Icons.campaign_outlined,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            const Text('暂无团队公告', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final id = key.value;
          final index = _announcements.indexWhere(
            (a) => (a is Map ? (a['uuid'] ?? a['id']) : null)?.toString() == id,
          );
          return index != -1 ? index : null;
        }
        return null;
      },
      itemCount: _announcements.length,
      itemBuilder: (context, index) {
        final ann = _announcements[index];
        final annKey =
            (ann is Map ? (ann['uuid'] ?? ann['id']) : null)?.toString() ??
            '$index';
        return RepaintBoundary(
          key: ValueKey<String>(annKey),
          child: OptionalLiquidGlassCard(
            key: ValueKey<String>(annKey),
            margin: const EdgeInsets.only(bottom: 16),
            borderRadius: 16,
            highContrast: true,
            tint: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
            fallbackDecoration: BoxDecoration(
              color: Theme.of(context).cardColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.fromBorderSide(
                BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.campaign_rounded,
                        color: Colors.orangeAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ann['title'] ?? '未命名公告',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Builder(
                        builder: (context) {
                          DateTime date;
                          final rawDate = ann['created_at'];
                          if (rawDate is int) {
                            date = DateTime.fromMillisecondsSinceEpoch(rawDate);
                          } else {
                            date =
                                DateTime.tryParse(rawDate?.toString() ?? '') ??
                                DateTime.now();
                          }
                          return Text(
                            AppTimeFormats.dateFormatter('MM-dd HH:mm')
                                .format(date),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  Text(
                    ann['content'] ?? '',
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
              ),
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
  final Future<void> Function(Team team) copyInviteCode;
  final void Function(Team team) onDeleteTeam;
  final void Function(Team team) onLeaveTeam;
  const _TeamSettingsView({
    required this.team,
    required this.onRefresh,
    required this.copyInviteCode,
    required this.onDeleteTeam,
    required this.onLeaveTeam,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = team.userRole == TeamRole.admin;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          '通用信息',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        _buildSettingItem(
          context,
          icon: Icons.vpn_key_rounded,
          color: Theme.of(context).colorScheme.secondary,
          title: '团队邀请码',
          subtitle: normalizeInviteCode(team.inviteCode) ?? '尚未生成',
          trailing: const Icon(
            Icons.copy_rounded,
            size: 18,
            color: Colors.grey,
          ),
          onTap: () => unawaited(copyInviteCode(team)),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 32),
          const Text(
            '管理操作',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.redAccent,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          _buildSettingItem(
            context,
            icon: Icons.refresh_rounded,
            color: Theme.of(context).colorScheme.secondary,
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
            icon: Icons.link_rounded,
            color: Theme.of(context).colorScheme.primary,
            title: '分享管理',
            subtitle: '创建和管理团队只读分享链接',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeamShareManageScreen(team: team),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildSettingItem(
            context,
            icon: Icons.delete_forever_rounded,
            color: Colors.redAccent,
            title: '解散团队',
            subtitle: '删除所有团队任务与成员，此操作不可逆',
            onTap: () => onDeleteTeam(team),
          ),
        ] else ...[
          const SizedBox(height: 32),
          _buildSettingItem(
            context,
            icon: Icons.exit_to_app_rounded,
            color: Colors.orange,
            title: '退出团队',
            subtitle: '退出后将不再接收此团队的任务同步',
            onTap: () => onLeaveTeam(team),
          ),
        ],
      ],
    );
  }

  Widget _buildSettingItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
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
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
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
/// Full-page entry used by search so opening and closing the member list uses
/// the same container transform as the search result card.
class TeamMembersSearchScreen extends StatefulWidget {
  const TeamMembersSearchScreen({super.key, required this.team});

  final Team team;

  @override
  State<TeamMembersSearchScreen> createState() =>
      _TeamMembersSearchScreenState();
}

class _TeamMembersSearchScreenState extends State<TeamMembersSearchScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: FloatingGlassAppBar(title: Text('${widget.team.name} · 团队成员')),
    body: _TeamMembersView(
      team: widget.team,
      scrollController: _scrollController,
      onRefresh: () {},
    ),
  );
}

class _TeamMembersView extends StatefulWidget {
  final Team team;
  final ScrollController scrollController;
  final VoidCallback onRefresh;
  const _TeamMembersView({
    required this.team,
    required this.scrollController,
    required this.onRefresh,
  });

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
    final requestCount = _requests.length;
    final hasRequests = requestCount > 0;
    final memberHeaderIndex = hasRequests ? requestCount + 3 : 0;
    final memberStartIndex = memberHeaderIndex + 1;
    final listItemCount = memberStartIndex + _members.length + 1;

    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(
                Icons.manage_accounts_rounded,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Text(
                '成员管理 - ${widget.team.name}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (!_loading)
                Text(
                  '${_members.length} 人',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  findChildIndexCallback: (Key key) {
                    if (key is ValueKey<String>) {
                      final keyVal = key.value;
                      if (keyVal.startsWith('team-req-')) {
                        final id = keyVal.substring('team-req-'.length);
                        final idx = _requests.indexWhere(
                          (r) => '${r['id'] ?? r['user_id']}' == id,
                        );
                        if (idx != -1) return idx + 1;
                      } else if (keyVal.startsWith('team-mem-')) {
                        final id = keyVal.substring('team-mem-'.length);
                        final idx = _members.indexWhere(
                          (m) => '${m['id'] ?? m['user_id']}' == id,
                        );
                        if (idx != -1) return idx + memberStartIndex;
                      }
                    }
                    return null;
                  },
                  itemCount: listItemCount,
                  itemBuilder: (context, index) {
                    if (hasRequests) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Text(
                            '待审批申请',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        );
                      }
                      if (index <= requestCount) {
                        final req = _requests[index - 1];
                        return RepaintBoundary(
                          key: ValueKey<String>(
                            'team-req-${req['id'] ?? req['user_id']}',
                          ),
                          child: _buildRequestItem(req),
                        );
                      }
                      if (index == requestCount + 1) {
                        return const SizedBox(height: 16);
                      }
                      if (index == requestCount + 2) {
                        return const Divider();
                      }
                    }

                    if (index == memberHeaderIndex) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Text(
                          '团队成员',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }
                    final memberIndex = index - memberStartIndex;
                    if (memberIndex < _members.length) {
                      final mem = _members[memberIndex];
                      return RepaintBoundary(
                        key: ValueKey<String>(
                          'team-mem-${mem['id'] ?? mem['user_id']}',
                        ),
                        child: _buildMemberItem(mem),
                      );
                    }
                    return const SizedBox(height: 40);
                  },
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
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondary
                .withValues(alpha: 0.1),
            child: Text(
              r['username']?[0]?.toUpperCase() ?? '?',
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              r['username'] ?? '未知用户',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => _handleRequest(r, 'reject'),
            child: const Text('拒绝', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => _handleRequest(r, 'approve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('同意'),
          ),
        ],
      ),
    );
  }

  String _formatMemberVersion(dynamic rawVersion) {
    final version = rawVersion?.toString().trim();
    if (version == null || version.isEmpty || version == 'unknown') {
      return '版本未知';
    }
    return version.startsWith('v') ? version : 'v$version';
  }

  String _formatLastOnline(bool isOnline, dynamic rawTimestamp) {
    if (isOnline) return '当前在线';
    final ms = rawTimestamp is int
        ? rawTimestamp
        : int.tryParse(rawTimestamp?.toString() ?? '');
    if (ms == null || ms <= 0) return '暂无上线记录';

    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚在线';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前上线';
    if (diff.inHours < 24) return '${diff.inHours}小时前上线';
    if (diff.inDays < 7) return '${diff.inDays}天前上线';
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    if (dt.year != now.year) {
      return '${dt.year}-$mm-$dd $hh:$min';
    }
    return '$mm-$dd $hh:$min';
  }

  Widget _buildMemberItem(dynamic m) {
    final bool isAdmin = m['role'] == 0;
    final bool isMe = m['is_me'] == true || m['id'] == ApiService.currentUserId;
    final bool viewerIsAdmin = widget.team.userRole == TeamRole.admin;
    final bool isOnline = m['is_online'] == true;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isAdmin
              ? colorScheme.secondary.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          child: Text(
            m['username']?[0]?.toUpperCase() ?? '?',
            style: TextStyle(
              color: isAdmin ? colorScheme.secondary : Colors.grey,
            ),
          ),
        ),
        title: Text(
          '${m['username']}${isMe ? ' (我)' : ''}',
          style: TextStyle(
            fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isAdmin ? '管理员' : '成员',
              style: TextStyle(
                fontSize: 12,
                color: isAdmin ? colorScheme.secondary : Colors.grey,
              ),
            ),
            if (viewerIsAdmin) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (isOnline) ...[
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  Flexible(
                    child: Text(
                      '${_formatLastOnline(isOnline, m['last_online_at'])} · ${_formatMemberVersion(m['app_version'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isOnline
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: (viewerIsAdmin && !isAdmin)
            ? IconButton(
                icon: const Icon(
                  Icons.person_remove_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: () => _confirmRemoveMember(m),
              )
            : null,
      ),
    );
  }

  Future<void> _handleRequest(dynamic r, String action) async {
    final res = await ApiService.processJoinRequest(
      widget.team.uuid,
      r['user_id'],
      action,
    );
    if (res['success'] == true) {
      _loadData();
      widget.onRefresh();
    }
  }

  void _confirmRemoveMember(dynamic m) {
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定要将「${m['username']}」从团队中移除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.removeTeamMember(
                widget.team.uuid,
                m['user_id'],
              );
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
