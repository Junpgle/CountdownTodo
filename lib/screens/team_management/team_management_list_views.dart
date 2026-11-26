part of '../team_management_screen.dart';

extension _TeamManagementListViewsExt on _TeamManagementScreenState {
  Widget _buildSliverAppBar(bool isDark) {
    return FloatingGlassSliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 60,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: const FloatingGlassTopBarBackground(),
      title: const Text(
        '团队协作',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.smart_toy_outlined),
          tooltip: 'AI协作助手',
          onPressed: _openAiAssistant,
        ),
        _buildMessageCenterAction(),
      ],
    );
  }

  Future<void> _openAiAssistant() async {
    try {
      final results = await Future.wait<dynamic>([
        StorageService.getTodos(widget.username),
        StorageService.getTodoGroups(widget.username),
        CourseService.getAllCourses(widget.username),
        StorageService.getTimeLogs(widget.username),
        PomodoroService.getRecords(),
      ]);
      if (!mounted) return;
      await AiTodoChatLauncher.open(
        context,
        username: widget.username,
        todos: (results[0] as List<TodoItem>)
            .where(
              (todo) =>
                  !todo.isDeleted &&
                  (_selectedTeam == null ||
                      todo.teamUuid == _selectedTeam!.uuid),
            )
            .toList(),
        todoGroups: (results[1] as List<TodoGroup>)
            .where((g) => !g.isDeleted)
            .toList(),
        courses: (results[2] as List<CourseItem>)
            .where((c) => !c.isDeleted)
            .toList(),
        timeLogs: (results[3] as List<TimeLogItem>)
            .where((l) => !l.isDeleted)
            .toList(),
        pomodoroRecords: (results[4] as List<PomodoroRecord>)
            .where((r) => !r.isDeleted)
            .toList(),
        teams: _teams,
        onTodosBatchAction:
            (
              inserted,
              updated, {
              expectedTodoBaselines,
              expectedSeriesMembership,
            }) async {
              final allTodos = await StorageService.getTodos(widget.username);
              final merged = AiTodoActionExecutor.mergeTodoUpdates(
                allTodos,
                inserted,
                updated,
              );
              await StorageService.saveTodos(
                widget.username,
                merged,
                expectedTodoBaselines: expectedTodoBaselines,
                expectedSeriesMembership: expectedSeriesMembership,
              );
            },
      );
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('打开AI助手失败: $e')),
        );
      }
    }
  }

  Widget _buildInitialLoadingState(bool isDark) {
    return const SliverToBoxAdapter(
      child: AppSkeletonListPage(
        shrinkWrap: true,
        itemCount: 4,
        itemHeight: 112,
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.radar_rounded,
                      size: 18,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '$progress%',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress <= 0 ? null : progress / 100,
                    minHeight: 6,
                    backgroundColor: Colors.orangeAccent.withValues(
                      alpha: 0.12,
                    ),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.orangeAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '已扫描 $current / $total',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionsSliver(bool isWide) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            _buildQuickActionCard(
              key: _panoramaActionKey,
              title: "全景汇聚",
              desc: isWide ? "汇集所有团队任务的时间轴展示" : "所有团队任务时间轴",
              icon: Icons.waterfall_chart_rounded,
              color: Colors.blueAccent,
              onTap: () {
                unawaited(_openPanorama());
              },
            ),
            const SizedBox(width: 12),
            _buildQuickActionCard(
              key: _conflictActionKey,
              title: "冲突中心",
              desc: isWide ? "处理多终端同步产生的数据争议" : "解决多端同步冲突",
              icon: Icons.verified_user_rounded,
              color: Colors.orangeAccent,
              badgeCount: _totalConflictCount,
              onTap: () {
                unawaited(_openConflictCenter());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPanorama() async {
    await PageTransitions.pushFromRect(
      context: context,
      page: UnifiedWaterfallScreen(username: widget.username),
      sourceKey: _panoramaActionKey,
      sourceColor: Theme.of(context).colorScheme.surface,
      sourceBorderRadius: BorderRadius.circular(24),
      placeholderIcon: Icons.waterfall_chart_rounded,
    );
  }

  Future<void> _openConflictCenter() async {
    await PageTransitions.pushFromRect(
      context: context,
      page: ConflictInboxScreen(username: widget.username),
      sourceKey: _conflictActionKey,
      sourceColor: Theme.of(context).colorScheme.surface,
      sourceBorderRadius: BorderRadius.circular(24),
      placeholderIcon: Icons.verified_user_rounded,
    );
    if (mounted) {
      _loadTeams(isSilent: true); // 🚀 返回后强制刷新，确保红点消失
    }
  }

  Widget _buildMasterList(bool isDark) {
    return CustomScrollView(
      slivers: [
        FloatingGlassSliverAppBar(
          pinned: true,
          title: const Text(
            '团队列表',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [_buildMessageCenterAction()],
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const FloatingGlassTopBarBackground(),
        ),
        FloatingGlassSliverContentFadeGroup(
          topBarHeight: floatingGlassTopBarHeight(context),
          slivers: [
            _buildQuickActionsSliver(true),
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
                    return RepaintBoundary(
                      key: ValueKey<String>(team.uuid),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => _mutateState(() => _selectedTeam = team),
                          borderRadius: BorderRadius.circular(20),
                          child: OptionalLiquidGlassCard(
                            padding: const EdgeInsets.all(16),
                            borderRadius: 20,
                            highContrast: true,
                            fallbackDecoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.secondary
                                        .withValues(alpha: 0.1)
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.white),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.secondary
                                          .withValues(alpha: 0.3)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildTeamAvatar(team),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        team.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${team.memberCount} 位成员',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (conflictCount > 0) ...[
                                  _buildCountBadge(
                                    conflictCount,
                                    Colors.orangeAccent,
                                    icon: Icons.schedule_rounded,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (pendingCount > 0)
                                  _buildCountBadge(
                                    pendingCount,
                                    Colors.redAccent,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  findChildIndexCallback: (Key key) {
                    if (key is ValueKey<String>) {
                      final uuid = key.value;
                      final index = _teams.indexWhere((t) => t.uuid == uuid);
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
    );
  }

  Widget _buildDetailEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dashboard_customize_rounded,
            size: 80,
            color: Colors.grey.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text('请从左侧选择一个团队进行管理', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  void _showSpeedDialMenu() {
    showAppModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSpeedDial(
        context,
        Theme.of(context).brightness == Brightness.dark,
      ),
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
            color: Theme.of(context).colorScheme.secondary
                .withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.groups_2_rounded,
            size: 72,
            color: Theme.of(context).colorScheme.secondary
                .withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '还没加入任何团队哦',
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '创建或加入团队，开启高效协作之旅',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: _showCreateTeamDialog,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                '创建团队',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.secondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.secondary
                      .withValues(alpha: 0.3),
                ),
              ),
              onPressed: _showJoinTeamDialog,
              icon: const Icon(Icons.link_rounded, size: 20),
              label: const Text(
                '加入团队',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
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
              Icon(
                Icons.mark_email_unread_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                '待处理的邀请',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
        ),
        ..._myInvitations.map(
          (inv) => OptionalLiquidGlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            highContrast: true,
            tint: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
            fallbackDecoration: BoxDecoration(
              color: isDark
                  ? Theme.of(context).colorScheme.secondary
                        .withValues(alpha: 0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.secondary
                    .withValues(alpha: 0.2),
              ),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.secondary
                            .withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.secondary
                      .withValues(alpha: 0.1),
                  child: Icon(
                    Icons.groups_rounded,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize:
                        MainAxisSize.min, // 🚀 避免 RenderFlex OVERFLOWING
                    children: [
                      Text(
                        inv['team_name'] ?? '未知团队',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '来自 ${inv['inviter_name']} 的邀请',
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
                Row(
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withValues(alpha: 0.1),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () =>
                          _handleInvitation(inv['team_uuid'], 'decline'),
                      tooltip: '忽略',
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary
                            .withValues(alpha: 0.1),
                      ),
                      icon: Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      onPressed: () =>
                          _handleInvitation(inv['team_uuid'], 'accept'),
                      tooltip: '加入',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

  Widget _buildQuickActionCard({
    required GlobalKey key,
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            OptionalLiquidGlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 24,
              highContrast: true,
              tint: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.16),
              fallbackDecoration: BoxDecoration(
                color: isDark ? color.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
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
}
