part of '../team_management_screen.dart';

extension _TeamManagementDataDialogsExt on _TeamManagementScreenState {
  String _safeFirstChar(String? s) {
    if (s == null || s.trim().isEmpty) return '?';
    final str = s.trim();
    if (str.runes.isEmpty) return '?';
    return String.fromCharCode(str.runes.first).toUpperCase();
  }

  String? _normalizeInviteCode(String? code) {
    final value = code?.trim();
    if (value == null || value.isEmpty || value.toLowerCase() == 'null') {
      return null;
    }
    return value.toUpperCase();
  }

  String _buildInviteText(Team team, String inviteCode) {
    return '邀请您加入「${team.name}」团队进行协作。复制此消息后打开App即可自动申请加入。\n\n邀请码：[$inviteCode]';
  }

  Future<String?> _ensureInviteCode(Team team) async {
    final existingCode = _normalizeInviteCode(team.inviteCode);
    if (existingCode != null) return existingCode;

    final res = await ApiService.generateInviteCode(team.uuid);
    if (res['success'] == true) {
      final generatedCode = _normalizeInviteCode(res['code']?.toString());
      await _loadTeams(isSilent: true);
      if (generatedCode != null) return generatedCode;

      final refreshedTeam = _teams
          .where((t) => t.uuid == team.uuid)
          .firstOrNull;
      final refreshedCode = _normalizeInviteCode(refreshedTeam?.inviteCode);
      if (refreshedCode != null) return refreshedCode;
    }

    if (mounted) {
      _showErrorToast(res['error'] ?? res['message'] ?? '邀请码生成失败');
    }
    return null;
  }

  Future<void> _copyTeamInviteText(Team team) async {
    final inviteCode = await _ensureInviteCode(team);
    if (inviteCode == null || !mounted) return;

    await Clipboard.setData(
      ClipboardData(text: _buildInviteText(team, inviteCode)),
    );
    _showSuccessToast('邀请文案已复制，快去分享吧 📋');
  }

  Future<void> _copyInviteCode(Team team) async {
    final inviteCode = await _ensureInviteCode(team);
    if (inviteCode == null || !mounted) return;

    await Clipboard.setData(ClipboardData(text: inviteCode));
    _showSuccessToast('邀请码已复制');
  }

  Future<void> _checkClipboardForInvite() async {
    if (_isCheckingClipboard) return;
    _isCheckingClipboard = true;

    try {
      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        String text = data.text!;
        // 匹配格式：邀请您加入「XXX」团队。复制此消息后打开App即可加入。邀请码：[ABCDEF]
        Match? match = _teamInviteCopyCodePattern.firstMatch(text);

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
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '发现团队邀请',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
              child: Text(
                '邀请码: $inviteCode',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('忽略', style: TextStyle(color: Colors.grey.shade600)),
          ),
          StatefulBuilder(
            builder: (ctx, setDialogState) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: isProcessing
                    ? null
                    : () async {
                        setDialogState(() => isProcessing = true);
                        try {
                          final res = await ApiService.requestJoinTeam(
                            inviteCode,
                          );
                          if (res['success'] == true) {
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            _loadTeams();
                            _showSuccessToast('申请已提交，请等待管理员审核 ⏳');
                          } else {
                            _showErrorToast(
                              res['error'] ?? res['message'] ?? '加入失败',
                            );
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
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '立即申请',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadTeams({bool isSilent = false}) async {
    final loadGeneration = ++_teamLoadGeneration;
    final ownerKey = _cacheOwnerKey;
    final hasLocalContent = _teams.isNotEmpty || _myInvitations.isNotEmpty;
    if (!isSilent && !hasLocalContent) {
      _mutateState(() => _isLoading = true);
    }
    try {
      // 🚀 核心优化：并发加载团队列表和我的邀请
      final teamsFuture = ApiService.fetchTeams();
      final invitationsFuture = ApiService.fetchMyInvitations();

      final rawTeams = await teamsFuture;
      final invitations = await invitationsFuture;

      // 并发加载所有管理团队的待处理请求数
      final adminTeamUuids = rawTeams
          .where((t) => t['role'] == 0)
          .map((t) => t['uuid'] as String)
          .toList();

      Map<String, int> pendingCounts = {};
      if (adminTeamUuids.isNotEmpty) {
        final pendingResults = await Future.wait(
          adminTeamUuids.map((uuid) => ApiService.fetchPendingRequests(uuid)),
        );
        if (!mounted ||
            loadGeneration != _teamLoadGeneration ||
            ownerKey != _cacheOwnerKey) {
          return;
        }
        for (int i = 0; i < adminTeamUuids.length; i++) {
          pendingCounts[adminTeamUuids[i]] = pendingResults[i].length;
        }
      }

      if (!mounted ||
          loadGeneration != _teamLoadGeneration ||
          ownerKey != _cacheOwnerKey) {
        return;
      }
      _mutateState(() {
        _teams = rawTeams.map((t) => Team.fromJson(t)).toList();
        _myInvitations = invitations;
        _teamPendingCounts = pendingCounts;
        _isLoading = false;
        // 🚀 默认选中第一个
        if (_selectedTeam == null && _teams.isNotEmpty) {
          _selectedTeam = _teams.first;
        } else if (_selectedTeam != null) {
          // 同步更新已选中的团队数据
          try {
            _selectedTeam = _teams.firstWhere(
              (t) => t.uuid == _selectedTeam!.uuid,
            );
          } catch (_) {
            _selectedTeam = _teams.isNotEmpty ? _teams.first : null;
          }
        }
      });
      _cacheSnapshot();

      unawaited(_loadTeamConflictCounts(loadGeneration, ownerKey));
    } catch (e) {
      if (mounted &&
          loadGeneration == _teamLoadGeneration &&
          ownerKey == _cacheOwnerKey) {
        _mutateState(() => _isLoading = false);
      }
    }

    // 🚀 核心：处理搜索直达逻辑
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleInitialTarget(widget.initialTarget!);
      });
    }
  }

  Future<void> _loadTeamConflictCounts(
    int loadGeneration,
    String? ownerKey,
  ) async {
    try {
      final db = await DatabaseHelper.instance.databaseForUser(widget.username);
      const activeConflictWhere =
          'has_conflict = 1 AND COALESCE(is_deleted, 0) = 0';

      final todoRowsFuture = DatabaseHelper.instance.getTodoMaps(
        where: 't.has_conflict = 1 AND COALESCE(t.is_deleted, 0) = 0',
        includeConflictData: true,
        databaseOverride: db,
      );
      final groupRowsFuture = db.query(
        'todo_groups',
        columns: const ['team_uuid'],
        where: activeConflictWhere,
      );
      final countdownRowsFuture = db.query(
        'countdowns',
        columns: const ['team_uuid'],
        where: activeConflictWhere,
      );
      final habitGoalCountFuture = db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM habit_goals WHERE $activeConflictWhere',
      );
      final habitRuleCountFuture = db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM habit_goal_rule_revisions WHERE $activeConflictWhere',
      );

      final results = await Future.wait([
        todoRowsFuture,
        groupRowsFuture,
        countdownRowsFuture,
        habitGoalCountFuture,
        habitRuleCountFuture,
      ]);

      final todoRows = results[0];
      final groupRows = results[1];
      final countdownRows = results[2];
      final habitGoalRows = results[3];
      final habitRuleRows = results[4];

      final conflictCounts = <String, int>{};
      int total = 0;

      for (final row in todoRows) {
        final todo = TodoItem.fromSql(row);
        if (!ConflictVisibilityService.isVisibleTodoConflict(todo)) continue;
        total++;
        final teamUuid = todo.teamUuid;
        if (ConflictVisibilityService.hasTeamUuid(teamUuid)) {
          conflictCounts[teamUuid!] = (conflictCounts[teamUuid] ?? 0) + 1;
        }
      }

      for (final row in [...groupRows, ...countdownRows]) {
        total++;
        final teamUuid = row['team_uuid']?.toString();
        if (ConflictVisibilityService.hasTeamUuid(teamUuid)) {
          conflictCounts[teamUuid!] = (conflictCounts[teamUuid] ?? 0) + 1;
        }
      }

      // 冲突中心内部还会展示习惯目标和规则，入口角标必须使用同一口径。
      total += (habitGoalRows.firstOrNull?['cnt'] as num?)?.toInt() ?? 0;
      total += (habitRuleRows.firstOrNull?['cnt'] as num?)?.toInt() ?? 0;

      if (!mounted ||
          loadGeneration != _teamLoadGeneration ||
          ownerKey != _cacheOwnerKey) {
        return;
      }
      _mutateState(() {
        _teamConflictCounts = conflictCounts;
        _totalConflictCount = total;
      });
      _cacheSnapshot();
    } catch (_) {}
  }

  void _cacheSnapshot() {
    final ownerKey = _cacheOwnerKey;
    if (ownerKey == null) return;
    _cachedSnapshots[ownerKey] = _TeamManagementSnapshot(
      teams: List<Team>.from(_teams),
      invitations: List<dynamic>.from(_myInvitations),
      pendingCounts: Map<String, int>.from(_teamPendingCounts),
      conflictCounts: Map<String, int>.from(_teamConflictCounts),
      totalConflictCount: _totalConflictCount,
    );
  }

  void _handleInitialTarget(String target) {
    if (!mounted) return;

    switch (target) {
      case 'messages':
        final managedTeams = _teams
            .where((t) => t.userRole == TeamRole.admin)
            .toList();
        Navigator.push(
          context,
          PageTransitions.material(
            builder: (_) => TeamMessageCenterScreen(managedTeams: managedTeams),
          ),
        );
        break;
      case 'create':
        _showCreateTeamDialog();
        break;
      case 'announcements':
        if (_teams.isNotEmpty) {
          // 如果只有一个团队，直接进入公告；否则可能需要更复杂的选择逻辑，这里默认选第一个
          Navigator.push(
            context,
            PageTransitions.material(
              builder: (_) => TeamAnnouncementScreen(team: _teams.first),
            ),
          );
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
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
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
          Match? match = _teamInviteCopyCodePattern.firstMatch(text);
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
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        autofocus: true,
      ),
      actionText: '提交申请',
      onAction: (setDialogState) async {
        String code = controller.text.trim();
        if (code.isEmpty) return;

        // 🚀 双重防线：提交前再次确保提取的是纯邀请码
        Match? match = _teamInviteCopyCodePattern.firstMatch(code);
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
      void Function(bool Function()) setDialogState,
    )
    onAction,
  }) {
    bool isProcessing = false;
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.secondary),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: content,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          StatefulBuilder(
            builder: (ctx, setDialogState) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
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
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        actionText,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showSuccessToast(String msg) => AppSnackBars.showSnackBar(
    context,
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
    ),
  );
  void _showErrorToast(String msg) => AppSnackBars.showSnackBar(
    context,
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ),
  );

  Widget _buildMessageCenterAction() {
    int totalPending = _teamPendingCounts.values.fold(
      0,
      (sum, count) => sum + count,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            key: _messageCenterActionKey,
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: '消息中心',
            onPressed: _openMessageCenter,
          ),
          if (totalPending > 0)
            Positioned(
              right: 8,
              top: 12,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  totalPending > 9 ? '9+' : totalPending.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openMessageCenter() async {
    final managedTeams = _teams
        .where((t) => t.userRole == TeamRole.admin)
        .toList();
    await PageTransitions.pushFromRect<void>(
      context: context,
      page: TeamMessageCenterScreen(managedTeams: managedTeams),
      sourceKey: _messageCenterActionKey,
      sourceColor: Theme.of(context).colorScheme.surface,
      sourceBorderRadius: BorderRadius.circular(24),
      placeholderIcon: Icons.notifications_none_rounded,
    );
  }

  // ============== 核心页面构建 ==============
  Widget _buildCountBadge(int count, Color color, {IconData? icon}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? 6 : 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
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
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
