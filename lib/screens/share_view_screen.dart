import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
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
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
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
                backgroundColor:
                    Theme.of(context).colorScheme.secondary,
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
    return _buildHome();
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
                child:
                    Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              ),
              const SizedBox(height: 20),
              Text(_errorMessage,
                  style: TextStyle(
                      fontSize: 16, color: Colors.grey.shade600),
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
                    size: 48,
                    color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 20),
              const Text('需要密码验证',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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

  // ==================== 首页布局 ====================

  Widget _buildHome() {
    final teamName = _data!['team']?['name'] ?? '未知团队';
    final share = _data!['share'] ?? {};
    final todos = (_data!['todos'] as List?) ?? [];
    final groups = (_data!['groups'] as List?) ?? [];
    final countdowns = (_data!['countdowns'] as List?) ?? [];
    final announcements = (_data!['announcements'] as List?) ?? [];

    final groupMap = <String, String>{};
    for (final g in groups) {
      groupMap[g['uuid']] = g['name'] ?? '未命名分组';
    }

    final doneTodos = todos.where((t) => t['is_completed'] == 1).length;
    final pendingTodos = todos.where((t) => t['is_completed'] != 1).toList();
    final completedTodos = todos.where((t) => t['is_completed'] == 1).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FA),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ── 顶部 AppBar ──
            SliverAppBar(
              expandedHeight: 160,
              floating: false,
              pinned: true,
              stretch: true,
              backgroundColor:
                  isDark ? const Color(0xFF1E1E2E) : primary,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding:
                    const EdgeInsets.only(left: 20, bottom: 16),
                title: Text(
                  share['title'] ?? teamName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [const Color(0xFF1E1E2E), const Color(0xFF2D2D44)]
                          : [primary, primary.withValues(alpha: 0.8)],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 56),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (share['description'] != null)
                            Text(share['description'],
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
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

            // ── 统计栏 ──
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2))
                        ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                        '待办', '$doneTodos/${todos.length}', Icons.check_circle_outline, primary),
                    _buildDivider(),
                    _buildStatItem(
                        '倒计时', '${countdowns.length}', Icons.timer_outlined, secondary),
                    _buildDivider(),
                    _buildStatItem(
                        '公告', '${announcements.length}', Icons.announcement_outlined,
                        Colors.orangeAccent),
                  ],
                ),
              ),
            ),

            // ── 公告区域 ──
            if (announcements.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('团队公告', Icons.announcement_outlined,
                          Colors.orangeAccent),
                      const SizedBox(height: 12),
                      ...announcements
                          .map((a) => _buildAnnouncementCard(a, isDark)),
                    ],
                  ),
                ),
              ),

            // ── 待办事项 ──
            if (todos.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(
                          '待办事项', Icons.check_circle_outline, primary),
                      const SizedBox(height: 12),
                      // 未完成
                      if (pendingTodos.isNotEmpty) ...[
                        ...pendingTodos.map((t) => _buildTodoCard(t, groupMap, false, isDark, primary)),
                      ],
                      // 已完成
                      if (completedTodos.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Text('已完成 ($doneTodos)',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500)),
                        ),
                        ...completedTodos.map((t) => _buildTodoCard(t, groupMap, true, isDark, primary)),
                      ],
                    ],
                  ),
                ),
              ),

            // ── 倒计时 ──
            if (countdowns.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(
                          '倒计时', Icons.timer_outlined, secondary),
                      const SizedBox(height: 12),
                      ...countdowns.map((c) => _buildCountdownCard(c, isDark, secondary)),
                    ],
                  ),
                ),
              ),

            // ── 空状态 ──
            if (todos.isEmpty && countdowns.isEmpty && announcements.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('暂无分享内容',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),

            // ── 底部留白 ──
            const SliverToBoxAdapter(
                child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showJoinDialog,
        backgroundColor: secondary,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('申请加入团队',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ==================== 组件 ====================

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
        height: 36, width: 1, color: Colors.grey.withValues(alpha: 0.15));
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color)),
      ],
    );
  }

  Widget _buildAnnouncementCard(
      Map<String, dynamic> a, bool isDark) {
    final isPriority =
        a['is_priority'] == 1 || a['is_priority'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isPriority
            ? Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.3),
                width: 1.5)
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isPriority) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('置顶',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(a['title'] ?? '',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(a['content'] ?? '',
                style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? Colors.grey.shade300
                        : Colors.grey.shade700,
                    height: 1.5)),
            const SizedBox(height: 10),
            Text(
              [
                if (a['creator_name'] != null) a['creator_name'],
                if (a['created_at'] != null)
                  _fmtDateTime(a['created_at'] as int),
              ].join(' · '),
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoCard(Map<String, dynamic> t,
      Map<String, String> groupMap, bool isDone, bool isDark, Color primary) {
    final title = t['content'] ?? '';
    final dueDate = t['due_date'];
    final collabType = t['collab_type'];
    final groupId = t['group_id'];
    final groupName = groupId != null ? groupMap[groupId] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 1))
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? Colors.green : Colors.transparent,
                border: Border.all(
                    color: isDone
                        ? Colors.green
                        : Colors.grey.shade400,
                    width: 2),
              ),
              child: isDone
                  ? const Icon(Icons.check,
                      size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isDone ? FontWeight.normal : FontWeight.w500,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey.shade500 : null,
                      )),
                  if (groupName != null ||
                      dueDate != null ||
                      collabType == 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          if (groupName != null)
                            _buildMiniTag(
                                groupName, primary.withValues(alpha: 0.1), primary),
                          if (dueDate != null)
                            _buildMiniTag(
                                '截止 ${_fmtDate(dueDate)}',
                                Colors.blue.withValues(alpha: 0.1),
                                Colors.blue),
                          if (collabType == 1)
                            _buildMiniTag('各自独立',
                                Colors.purple.withValues(alpha: 0.1),
                                Colors.purple),
                        ],
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

  Widget _buildMiniTag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: fg)),
    );
  }

  Widget _buildCountdownCard(
      Map<String, dynamic> c, bool isDark, Color secondary) {
    final title = c['title'] ?? '';
    final targetTime = c['target_time'] as int?;
    final now = DateTime.now().millisecondsSinceEpoch;
    final days = targetTime != null
        ? ((targetTime - now) / (1000 * 60 * 60 * 24)).ceil()
        : 0;
    final isPast = days < 0;
    final isToday = days == 0;

    String daysText;
    Color badgeColor;
    if (isPast) {
      daysText = '已过 ${days.abs()} 天';
      badgeColor = Colors.grey.shade500;
    } else if (isToday) {
      daysText = '今天';
      badgeColor = Colors.orange;
    } else {
      daysText = '$days 天';
      badgeColor = secondary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isPast ? Colors.grey.shade500 : null,
                  )),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(daysText,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: badgeColor)),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _fmtDateTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
