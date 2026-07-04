import 'package:flutter/material.dart';
import '../models.dart';
import '../services/api_service.dart';
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
    _todos = rawTodos.map((t) => TodoItem(
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
      teamUuid: teamUuid,
      teamName: teamName,
    )).toList();

    // 解析分组
    final rawGroups = (result['groups'] as List?) ?? [];
    _todoGroups = rawGroups.map((g) => TodoGroup(
      id: g['uuid']?.toString(),
      name: g['name']?.toString() ?? '未命名分组',
      isExpanded: g['is_expanded'] == 1,
      teamUuid: teamUuid,
      teamName: teamName,
    )).toList();

    // 解析倒计时
    final rawCountdowns = (result['countdowns'] as List?) ?? [];
    _countdowns = rawCountdowns.map((c) => CountdownItem(
      id: c['uuid']?.toString(),
      title: c['title']?.toString() ?? '',
      targetDate: DateTime.fromMillisecondsSinceEpoch(
          (c['target_time'] as int?) ?? DateTime.now().millisecondsSinceEpoch),
      isCompleted: c['is_completed'] == 1,
      createdAt: c['created_at'] as int?,
      teamUuid: teamUuid,
      teamName: teamName,
    )).toList();
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

  // ==================== 首页布局，复用现有组件 ====================

  Widget _buildDashboard() {
    final teamName = _data!['team']?['name'] ?? '未知团队';
    final share = _data!['share'] ?? {};
    final announcements = (_data!['announcements'] as List?) ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLight = !isDark;
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFE8F4FD),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ── 顶部 AppBar ──
            SliverAppBar(
              expandedHeight: 160,
              floating: false,
              pinned: true,
              stretch: true,
              backgroundColor: isDark ? const Color(0xFF1E1E2E) : primary,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                title: Text(
                  share['title'] ?? teamName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

            // ── 公告 ──
            if (announcements.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildAnnouncementsSection(announcements, isDark),
              ),

            // ── 倒计时 ──
            if (_countdowns.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ShareCountdownSection(countdowns: _countdowns, isLight: isLight),
                ),
              ),

            // ── 待办 ──
            if (_todos.isNotEmpty || _todoGroups.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ShareTodoSection(todos: _todos, todoGroups: _todoGroups, isLight: isLight),
                ),
              ),

            // ── 空状态 ──
            if (_todos.isEmpty && _countdowns.isEmpty && announcements.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('暂无分享内容', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),

            // ── 底部留白 ──
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showJoinDialog,
        backgroundColor: secondary,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('申请加入团队', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ── 公告区域（HomeDashboard 风格）──
  Widget _buildAnnouncementsSection(List announcements, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.announcement_outlined,
                    size: 18, color: Colors.orangeAccent),
              ),
              const SizedBox(width: 10),
              const Text('团队公告',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.orangeAccent)),
            ],
          ),
          const SizedBox(height: 12),
          ...announcements.map((a) => _buildAnnouncementCard(a, isDark)),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> a, bool isDark) {
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

  String _fmtDateTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
