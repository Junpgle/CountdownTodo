import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/share_readonly_widgets.dart';

class ShareViewScreen extends StatefulWidget {
  final String shareCode;
  const ShareViewScreen({super.key, required this.shareCode});

  @override
  State<ShareViewScreen> createState() => _ShareViewScreenState();
}

class _ShareViewScreenState extends State<ShareViewScreen> {
  bool _isLoading = true;
  bool _needsPassword = false;
  bool _hasError = false;
  String _errorMessage = '';
  String? _accessToken;
  Map<String, dynamic>? _data;
  final _passwordController = TextEditingController();
  bool _verifying = false;

  // 转换后的模型数据
  List<TodoItem> _todos = [];
  List<TodoGroup> _todoGroups = [];
  List<CountdownItem> _countdowns = [];
  List<FixedScheduleItem> _schedules = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    final result = await ApiService.fetchShareData(
      widget.shareCode,
      token: _accessToken,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      _parseData(result);
      setState(() {
        _data = result;
        _isLoading = false;
        _needsPassword = false;
      });
    } else if (result['error'] == 'Password required') {
      setState(() {
        _needsPassword = true;
        _isLoading = false;
      });
    } else {
      setState(() {
        _hasError = true;
        _errorMessage = result['error'] ?? '加载失败';
        _isLoading = false;
      });
    }
  }

  void _parseData(Map<String, dynamic> result) {
    final teamUuid = result['team']?['uuid']?.toString();
    final teamName = result['team']?['name']?.toString();

    // 解析待办
    final rawTodos = (result['todos'] as List?) ?? [];
    _todos = rawTodos
        .map((t) => TodoItem(
              id: t['uuid']?.toString(),
              title: t['content']?.toString() ?? '',
              isDone: t['is_completed'] == 1,
              dueDate: t['due_date'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(t['due_date'] as int)
                  : null,
              createdDate: t['created_date'] as int?,
              createdAt: t['created_at'] as int?,
              collabType: t['collab_type'] ?? 0,
              groupId: t['group_id']?.toString(),
              isAllDay: t['is_all_day'] == 1 || t['isAllDay'] == true,
              teamUuid: teamUuid,
              teamName: teamName,
            ))
        .toList();

    // 解析分组
    final rawGroups = (result['groups'] as List?) ?? [];
    _todoGroups = rawGroups
        .map((g) => TodoGroup(
              id: g['uuid']?.toString(),
              name: g['name']?.toString() ?? '未命名分组',
              isExpanded: g['is_expanded'] == 1,
              teamUuid: teamUuid,
              teamName: teamName,
            ))
        .toList();

    // 解析倒计时
    final rawCountdowns = (result['countdowns'] as List?) ?? [];
    _countdowns = rawCountdowns
        .map((c) => CountdownItem(
              id: c['uuid']?.toString(),
              title: c['title']?.toString() ?? '',
              targetDate: DateTime.fromMillisecondsSinceEpoch(
                  (c['target_time'] as int?) ??
                      DateTime.now().millisecondsSinceEpoch),
              isCompleted: c['is_completed'] == 1,
              createdAt: c['created_at'] as int?,
              teamUuid: teamUuid,
              teamName: teamName,
            ))
        .toList();

    // 日程在新版数据结构中独立于待办返回。兼容后端可能使用的两种命名，
    // 在服务器还未返回该字段时保持空列表，不影响旧分享链接。
    final rawSchedules = _readFirstList(result, const [
      'schedules',
      'fixed_schedules',
      'fixedSchedules',
    ]);
    _schedules = rawSchedules
        .whereType<Map>()
        .map((raw) {
          final json = Map<String, dynamic>.from(raw);
          // 兼容 Dart/JSON 风格的驼峰字段。
          json['uuid'] ??= json['id'];
          json['start_time'] ??= json['startTime'];
          json['end_time'] ??= json['endTime'];
          final schedule = FixedScheduleItem.fromJson(json);
          schedule.teamUuid ??= teamUuid;
          return schedule;
        })
        .where((schedule) => !schedule.isDeleted)
        .toList();
  }

  List<dynamic> _readFirstList(
      Map<String, dynamic> data, List<String> candidateKeys) {
    for (final key in candidateKeys) {
      final value = data[key];
      if (value is List) return value;
    }
    return const [];
  }

  Future<void> _verifyPassword() async {
    final pwd = _passwordController.text.trim();
    if (pwd.isEmpty) return;
    setState(() => _verifying = true);
    final result = await ApiService.verifyShareCode(widget.shareCode, pwd);
    if (!mounted) return;
    if (result['success'] == true && result['requires_password'] != true) {
      _accessToken = result['access_token'];
      await _loadData();
    } else {
      setState(() => _verifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'] ?? '密码错误')),
      );
    }
  }

  void _showJoinDialog() {
    final emailCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    bool submitting = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(Icons.person_add_rounded,
                color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 12),
            const Text('申请加入团队'),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('填写你的邮箱，管理员审批后你将收到通知。',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: '邮箱',
                    hintText: '请输入你的注册邮箱',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgCtrl,
                  decoration: InputDecoration(
                    labelText: '备注（可选）',
                    hintText: '简单介绍一下自己',
                    prefixIcon: const Icon(Icons.message_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入邮箱')));
                        return;
                      }
                      setDState(() => submitting = true);
                      final res = await ApiService.requestJoinViaShare(
                        shareCode: widget.shareCode,
                        email: email,
                        message: msgCtrl.text.trim(),
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(res['success'] == true
                            ? '申请已提交，请等待管理员审批'
                            : res['error'] ?? '提交失败'),
                        backgroundColor:
                            res['success'] == true ? Colors.green : null,
                      ));
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('提交申请'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoading();
    if (_hasError) return _buildError();
    if (_needsPassword) return _buildPasswordInput();
    return _buildDashboard();
  }

  Widget _buildLoading() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text('加载中...',
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline,
                    size: 48, color: Colors.red.shade300),
              ),
              const SizedBox(height: 20),
              Text(_errorMessage,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordInput() {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline,
                    size: 48, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 20),
              const Text('需要密码验证',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('此分享链接设置了访问密码',
                  style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 28),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '请输入密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => _verifyPassword(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _verifying ? null : _verifyPassword,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('验证',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 分享页响应式布局 ====================

  Widget _buildDashboard() {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 900;
    final teamName = _displayValue(_data!['team']?['name'], '未知团队');
    final share = _data!['share'] is Map
        ? Map<String, dynamic>.from(_data!['share'] as Map)
        : <String, dynamic>{};
    final shareTitle = _displayValue(share['title'], teamName);
    final announcements = (_data!['announcements'] as List?) ?? [];
    final isLight = Theme.of(context).brightness == Brightness.light;
    final contentWidth = math.min(
      size.width - (isDesktop ? 48 : 32),
      1240.0,
    );
    final hasContent = _todos.isNotEmpty ||
        _schedules.isNotEmpty ||
        _countdowns.isNotEmpty ||
        announcements.isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: RefreshIndicator(
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            FloatingGlassSliverAppBar(
              expandedHeight: isDesktop ? 236 : 204,
              floating: false,
              pinned: true,
              stretch: true,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              actionsIconTheme: IconThemeData(color: colorScheme.onPrimary),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                titlePadding:
                    const EdgeInsets.only(left: 20, right: 64, bottom: 16),
                title: Text(
                  shareTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Keep the branded hero visible while adding the same soft
                // status-bar fade used by the rest of the app.
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildHeroBackground(
                      teamName: teamName,
                      shareCode: widget.shareCode,
                      contentWidth: contentWidth,
                      colorScheme: colorScheme,
                    ),
                    Positioned.fill(
                      child: FloatingGlassTopBarBackground(
                        tint: colorScheme.primary,
                        isDark: !isLight,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadData,
                  tooltip: '刷新',
                ),
              ],
            ),
            FloatingGlassSliverContentFadeGroup(
              topBarHeight: floatingGlassTopBarHeight(context),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildCenteredContent(
                    _buildSummaryCard(
                      teamName: teamName,
                      announcementsCount: announcements.length,
                      isDesktop: isDesktop,
                      colorScheme: colorScheme,
                    ),
                    contentWidth: contentWidth,
                    top: isDesktop ? 24 : 16,
                  ),
                ),
                if (hasContent)
                  SliverToBoxAdapter(
                    child: _buildCenteredContent(
                      isDesktop
                          ? _buildDesktopSections(
                              announcements: announcements,
                              isLight: isLight,
                            )
                          : _buildMobileSections(
                              announcements: announcements,
                              isLight: isLight,
                            ),
                      contentWidth: contentWidth,
                      top: 16,
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: _buildCenteredContent(
                      _buildEmptyPanel(colorScheme),
                      contentWidth: contentWidth,
                      top: 16,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingGlassActionButton.extended(
        onPressed: _showJoinDialog,
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
        icon: const Icon(Icons.person_add_rounded),
        label:
            const Text('申请加入团队', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHeroBackground({
    required String teamName,
    required String shareCode,
    required double contentWidth,
    required ColorScheme colorScheme,
  }) {
    final heroForeground = colorScheme.onPrimary;
    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary,
              Color.alphaBlend(
                colorScheme.secondary.withValues(alpha: 0.28),
                colorScheme.primary,
              ),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -78,
              right: -32,
              child: _buildHeroOrb(
                size: 250,
                color: heroForeground.withValues(alpha: 0.08),
              ),
            ),
            Positioned(
              bottom: 26,
              right: 18,
              child: _buildHeroOrb(
                size: 94,
                color: heroForeground.withValues(alpha: 0.08),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 76),
                    child: Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: heroForeground.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: heroForeground.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Icon(Icons.groups_rounded,
                              size: 34, color: heroForeground),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                teamName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: heroForeground,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.public_rounded,
                                      size: 14,
                                      color: heroForeground.withValues(
                                          alpha: 0.72)),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      '团队公开分享 · 可实时查看内容',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: heroForeground.withValues(
                                            alpha: 0.72),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (contentWidth >= 680) ...[
                                    const SizedBox(width: 14),
                                    Flexible(
                                      child: Text(
                                        '分享码 ${shareCode.substring(0, math.min(8, shareCode.length))}…',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: heroForeground.withValues(
                                              alpha: 0.58),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroOrb({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildCenteredContent(
    Widget child, {
    required double contentWidth,
    required double top,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Center(
        child: SizedBox(width: contentWidth, child: child),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String teamName,
    required int announcementsCount,
    required bool isDesktop,
    required ColorScheme colorScheme,
  }) {
    final metrics = [
      (
        icon: Icons.checklist_rounded,
        value: _todos.length.toString(),
        label: '待办事项',
        color: colorScheme.primary,
      ),
      (
        icon: Icons.timer_outlined,
        value: _countdowns.length.toString(),
        label: '重要日',
        color: colorScheme.secondary,
      ),
      (
        icon: Icons.event_available_outlined,
        value: _schedules.length.toString(),
        label: '日程',
        color: colorScheme.tertiary,
      ),
      (
        icon: Icons.campaign_outlined,
        value: announcementsCount.toString(),
        label: '团队公告',
        color: colorScheme.error,
      ),
    ];

    return _buildSurfacePanel(
      colorScheme: colorScheme,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: 16,
      ),
      child: Row(
        children: [
          if (isDesktop) ...[
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('分享概览',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 4),
                  Text(teamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      )),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 42,
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 24),
          ],
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(width: 12),
              Container(
                width: 1,
                height: 34,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _buildSummaryMetric(
                icon: metrics[i].icon,
                value: metrics[i].value,
                label: metrics[i].label,
                color: metrics[i].color,
                colorScheme: colorScheme,
                isDesktop: isDesktop,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryMetric({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required ColorScheme colorScheme,
    required bool isDesktop,
  }) {
    final iconContainer = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 19, color: color),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1,
                )),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
            )),
      ],
    );

    if (isDesktop) {
      return Row(children: [iconContainer, const SizedBox(width: 10), text]);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconContainer,
        const SizedBox(height: 7),
        Center(child: text),
      ],
    );
  }

  Widget _buildDesktopSections({
    required List announcements,
    required bool isLight,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final todoPanel = _todos.isNotEmpty || _todoGroups.isNotEmpty
        ? _buildSurfacePanel(
            colorScheme: colorScheme,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: ShareTodoSection(
                todos: _todos, todoGroups: _todoGroups, isLight: isLight),
          )
        : null;
    final sideSections = <Widget>[];
    if (announcements.isNotEmpty) {
      sideSections.add(_buildAnnouncementsSection(announcements));
    }
    if (_countdowns.isNotEmpty) {
      sideSections.add(
        _buildSurfacePanel(
          colorScheme: colorScheme,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child:
              ShareCountdownSection(countdowns: _countdowns, isLight: isLight),
        ),
      );
    }

    final schedulePanel = _schedules.isNotEmpty
        ? _buildSurfacePanel(
            colorScheme: colorScheme,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: ShareScheduleSection(
              schedules: _schedules,
              isLight: isLight,
            ),
          )
        : null;

    final sidePanel = sideSections.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sideSections.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                sideSections[i],
              ],
            ],
          );

    if (todoPanel == null && sidePanel == null && schedulePanel == null) {
      return _buildEmptyPanel(colorScheme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (schedulePanel != null) schedulePanel,
        if (schedulePanel != null && (todoPanel != null || sidePanel != null))
          const SizedBox(height: 16),
        if (todoPanel != null || sidePanel != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (todoPanel != null) Expanded(flex: 7, child: todoPanel),
              if (todoPanel != null && sidePanel != null)
                const SizedBox(width: 20),
              if (sidePanel != null) Expanded(flex: 4, child: sidePanel),
            ],
          ),
      ],
    );
  }

  Widget _buildMobileSections({
    required List announcements,
    required bool isLight,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final sections = <Widget>[];
    if (_schedules.isNotEmpty) {
      sections.add(
        _buildSurfacePanel(
          colorScheme: colorScheme,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ShareScheduleSection(
            schedules: _schedules,
            isLight: isLight,
          ),
        ),
      );
    }
    if (announcements.isNotEmpty) {
      sections.add(_buildAnnouncementsSection(announcements));
    }
    if (_countdowns.isNotEmpty) {
      sections.add(
        _buildSurfacePanel(
          colorScheme: colorScheme,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child:
              ShareCountdownSection(countdowns: _countdowns, isLight: isLight),
        ),
      );
    }
    if (_todos.isNotEmpty || _todoGroups.isNotEmpty) {
      sections.add(
        _buildSurfacePanel(
          colorScheme: colorScheme,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: ShareTodoSection(
              todos: _todos, todoGroups: _todoGroups, isLight: isLight),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          sections[i],
        ],
      ],
    );
  }

  Widget _buildSurfacePanel({
    required ColorScheme colorScheme,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 16, 20, 20),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildEmptyPanel(ColorScheme colorScheme) {
    return _buildSurfacePanel(
      colorScheme: colorScheme,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.inbox_outlined,
                size: 34, color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 16),
          Text('暂无分享内容',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('团队还没有公开待办、日程、倒计时或公告',
              style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  String _displayValue(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  // ── 公告区域 ──
  Widget _buildAnnouncementsSection(List announcements) {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSurfacePanel(
      colorScheme: colorScheme,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            icon: Icons.campaign_outlined,
            title: '团队公告',
            subtitle: '最新团队动态',
            color: colorScheme.tertiary,
          ),
          const SizedBox(height: 14),
          ...announcements.map((a) =>
              _buildAnnouncementCard(Map<String, dynamic>.from(a as Map))),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> a) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPriority = a['is_priority'] == 1 || a['is_priority'] == true;
    final creator = a['creator_name']?.toString();
    final createdAt = a['created_at'];
    final meta = [
      if (creator != null && creator.isNotEmpty) creator,
      if (createdAt is int) _fmtDateTime(createdAt),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isPriority
            ? colorScheme.tertiaryContainer.withValues(alpha: 0.65)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPriority
              ? colorScheme.tertiary.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isPriority ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPriority) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('置顶',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onTertiary,
                        fontWeight: FontWeight.w700,
                      )),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  a['title']?.toString() ?? '',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            a['content']?.toString() ?? '',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(meta,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fmtDateTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
