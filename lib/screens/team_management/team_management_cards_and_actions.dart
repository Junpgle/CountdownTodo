part of '../team_management_screen.dart';

extension _TeamManagementCardsActionsExt on _TeamManagementScreenState {
  Widget _buildTeamCard(Team team, bool isDark) {
    final pendingCount = _teamPendingCounts[team.uuid] ?? 0;
    final conflictCount = _teamConflictCounts[team.uuid] ?? 0;

    return RepaintBoundary(
      key: ValueKey<String>(team.uuid),
      child: OptionalLiquidGlassCard(
        margin: const EdgeInsets.only(bottom: 16),
        borderRadius: 28,
        highContrast: true,
        tint: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        fallbackDecoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.transparent,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          team.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (team.userRole == TeamRole.admin ||
                            conflictCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (team.userRole == TeamRole.admin)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '管理员',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (conflictCount > 0)
                                  _buildCountBadge(
                                    conflictCount,
                                    Colors.orangeAccent,
                                    icon: Icons.schedule_rounded,
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '创建于 ${_teamManagementDateFormat('yyyy年MM月dd日').format(DateTime.fromMillisecondsSinceEpoch(team.createdAt))}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTeamMoreMenu(team),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),

              // 中部：人数 + 邀请码
              Row(
                children: [
                  Icon(
                    Icons.people_alt_rounded,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${team.memberCount} 位成员',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => unawaited(_copyTeamInviteText(team)),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '邀请码: ${_normalizeInviteCode(team.inviteCode) ?? "尚未生成"}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.copy_rounded,
                            size: 12,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 底部操作区：两列网格比单行按钮更易扫读，也给中文标签留足空间。
              Text(
                '团队操作',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final actionWidth = (constraints.maxWidth - 10) / 2;
                  final actions = <Widget>[
                    _buildTeamActionTile(
                      label: pendingCount > 0 ? '审批申请' : '成员管理',
                      icon: pendingCount > 0
                          ? Icons.admin_panel_settings_rounded
                          : Icons.manage_accounts_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      badgeCount: pendingCount,
                      onTap: () => _showMembersSheet(team),
                    ),
                    _buildTeamActionTile(
                      label: '团队公告',
                      icon: Icons.campaign_rounded,
                      color: Colors.orangeAccent,
                      onTap: () => Navigator.push(
                        context,
                        PageTransitions.material(
                          builder: (_) => TeamAnnouncementScreen(team: team),
                        ),
                      ),
                    ),
                    _buildTeamActionTile(
                      label: '邀请加入',
                      icon: Icons.person_add_alt_1_rounded,
                      color: Theme.of(context).colorScheme.secondary,
                      emphasized: true,
                      onTap: () => _showInviteOptionsSheet(team),
                    ),
                    if (team.userRole == TeamRole.admin)
                      _buildTeamActionTile(
                        label: '分享',
                        icon: Icons.link_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        onTap: () => _openShareManage(team),
                      ),
                  ];

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: actions
                        .map(
                          (action) =>
                              SizedBox(width: actionWidth, child: action),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamActionTile({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
    bool emphasized = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: emphasized
                ? color.withValues(alpha: isDark ? 0.16 : 0.1)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.035)
                      : colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.42,
                        )),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: emphasized ? 0.42 : 0.2),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, color: color, size: 22),
                    if (badgeCount > 0)
                      Positioned(
                        right: -8,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            badgeCount > 9 ? '9+' : '$badgeCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamMoreMenu(Team team) {
    return PopupMenuButton<String>(
      tooltip: '更多团队操作',
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_horiz_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'share') {
          _handleGenerateCode(team);
        } else if (value == 'share_manage') {
          _openShareManage(team);
        } else if (value == 'leave') {
          _confirmLeaveTeam(team);
        } else if (value == 'delete') {
          _confirmDeleteTeam(team);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share_rounded, size: 18),
              SizedBox(width: 12),
              Text('重置/生成邀请码'),
            ],
          ),
        ),
        if (team.userRole == TeamRole.admin)
          const PopupMenuItem(
            value: 'share_manage',
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 18),
                SizedBox(width: 12),
                Text('分享管理'),
              ],
            ),
          ),
        if (team.userRole == TeamRole.admin)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_forever_rounded, size: 18, color: Colors.red),
                SizedBox(width: 12),
                Text('解散团队', style: TextStyle(color: Colors.red)),
              ],
            ),
          )
        else
          const PopupMenuItem(
            value: 'leave',
            child: Row(
              children: [
                Icon(Icons.exit_to_app_rounded, size: 18, color: Colors.orange),
                SizedBox(width: 12),
                Text('退出团队', style: TextStyle(color: Colors.orange)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTeamAvatar(Team team) {
    final colors = [
      Theme.of(context).colorScheme.secondary,
      Colors.purpleAccent,
      Colors.orangeAccent,
      Colors.teal,
      Colors.indigo,
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
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // 🚀 新增：邀请选项弹窗
  void _showInviteOptionsSheet(Team team) {
    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => OptionalLiquidGlassSheet(
        topRadius: 32,
        padding: const EdgeInsets.only(
          top: 12,
          bottom: 32,
          left: 24,
          right: 24,
        ),
        fallbackDecoration: BoxDecoration(
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '邀请新成员',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildInviteOption(
              icon: Icons.copy_all_rounded,
              title: '分享邀请码',
              subtitle: '复制邀请话术发送给好友，点击自动申请',
              color: Theme.of(context).colorScheme.secondary,
              onTap: () {
                Navigator.pop(context);
                unawaited(_copyTeamInviteText(team));
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

  Widget _buildInviteOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
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
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
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
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
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
    showAppModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => OptionalLiquidGlassSheet(
          topRadius: 32,
          fallbackDecoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: _TeamMembersView(
            team: team,
            scrollController: scrollController,
            onRefresh: _loadTeams,
          ),
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

  void _openShareManage(Team team) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamShareManageScreen(team: team),
      ),
    );
  }

  void _confirmLeaveTeam(Team team) {
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出团队'),
        content: Text('确定要退出「${team.name}」吗？退出后将无法查看该团队的协作任务。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
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
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解散团队'),
        content: Text('警告：此操作不可逆！解散「${team.name}」将删除所有团队数据并移除所有成员。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
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
    return FloatingGlassActionButton.small(
      backgroundColor: Theme.of(context).colorScheme.secondary,
      onPressed: () {
        showAppModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => OptionalLiquidGlassSheet(
            topRadius: 32,
            padding: const EdgeInsets.only(
              top: 12,
              bottom: 32,
              left: 24,
              right: 24,
            ),
            fallbackDecoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '团队操作',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary
                            .withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    title: const Text(
                      '创建新团队',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('开启一个全新的协作项目'),
                    onTap: () {
                      Navigator.pop(context);
                      _showCreateTeamDialog();
                    },
                  ),
                ),
                const Divider(),
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.link_rounded,
                        color: Colors.orangeAccent,
                      ),
                    ),
                    title: const Text(
                      '加入已有团队',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('通过邀请码加入其他协作小组'),
                    onTap: () {
                      Navigator.pop(context);
                      _showJoinTeamDialog();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
    );
  }
}
