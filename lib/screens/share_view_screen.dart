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

  void _showJoinRequestDialog() {
    final emailController = TextEditingController();
    final messageController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.person_add_rounded,
                      color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 12),
                  const Text('申请加入团队'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '填写你的邮箱，管理员审批后你将收到通知。',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: '邮箱',
                        hintText: '请输入你的注册邮箱',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        labelText: '备注（可选）',
                        hintText: '简单介绍一下自己',
                        prefixIcon: const Icon(Icons.message_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          if (email.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请输入邮箱')),
                            );
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          final result =
                              await ApiService.requestJoinViaShare(
                            shareCode: widget.shareCode,
                            email: email,
                            message: messageController.text.trim(),
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['success'] == true
                                  ? '申请已提交，请等待管理员审批'
                                  : result['error'] ?? '提交失败'),
                              backgroundColor: result['success'] == true
                                  ? Colors.green
                                  : null,
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('提交申请'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? _buildLoading()
          : _hasError
              ? _buildError()
              : _needsPassword
                  ? _buildPasswordInput()
                  : _buildContent(),
      floatingActionButton: (_data != null && !_isLoading && !_hasError)
          ? FloatingActionButton.extended(
              onPressed: _showJoinRequestDialog,
              backgroundColor: Theme.of(context).colorScheme.secondary,
              icon: const Icon(Icons.person_add_rounded, color: Colors.white),
              label: const Text('申请加入团队',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('加载中...'),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordInput() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 48,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text(
              '需要密码验证',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '此分享链接设置了访问密码',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '请输入密码',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _verifyPassword(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _verifying ? null : _verifyPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _verifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('验证'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final teamName = _data!['team']?['name'] ?? '未知团队';
    final share = _data!['share'] ?? {};
    final todos = (_data!['todos'] as List?) ?? [];
    final groups = (_data!['groups'] as List?) ?? [];
    final countdowns = (_data!['countdowns'] as List?) ?? [];
    final announcements = (_data!['announcements'] as List?) ?? [];

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 140,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(
              share['title'] ?? teamName,
              style: const TextStyle(fontSize: 16),
            ),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      teamName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    if (share['description'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          share['description'],
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (share['share_todos'] == true && todos.isNotEmpty)
          _buildTodosSection(todos, groups),
        if (share['share_countdowns'] == true && countdowns.isNotEmpty)
          _buildCountdownsSection(countdowns),
        if (share['share_announcements'] == true && announcements.isNotEmpty)
          _buildAnnouncementsSection(announcements),
        if (todos.isEmpty && countdowns.isEmpty && announcements.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                '暂无分享内容',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '由 CountDownTodo 提供支持',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTodosSection(List todos, List groups) {
    final groupMap = <String, Map<String, dynamic>>{};
    for (final g in groups) {
      groupMap[g['uuid']] = Map<String, dynamic>.from(g);
    }

    final groupedTodos = <String, List<Map<String, dynamic>>>{};
    final ungrouped = <Map<String, dynamic>>[];

    for (final t in todos) {
      final todo = Map<String, dynamic>.from(t);
      final gid = todo['group_id'];
      if (gid != null && groupMap.containsKey(gid)) {
        groupedTodos.putIfAbsent(gid, () => []).add(todo);
      } else {
        ungrouped.add(todo);
      }
    }

    final doneCount = todos.where((t) => t['is_completed'] == 1).length;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '待办事项',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '$doneCount / ${todos.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...groupedTodos.entries.map((entry) {
              final groupName = groupMap[entry.key]?['name'] ?? '未命名分组';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      groupName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  ...entry.value.map((t) => _buildTodoItem(t)),
                ],
              );
            }),
            if (ungrouped.isNotEmpty) ...ungrouped.map((t) => _buildTodoItem(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoItem(Map<String, dynamic> todo) {
    final isDone = todo['is_completed'] == 1;
    final title = todo['content'] ?? '';
    final dueDate = todo['due_date'];
    final collabType = todo['collab_type'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? Colors.green
                  : Colors.transparent,
              border: Border.all(
                color: isDone ? Colors.green : Colors.grey.shade400,
                width: 2,
              ),
            ),
            child: isDone
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone ? Colors.grey.shade500 : null,
                  ),
                ),
                if (dueDate != null || collabType == 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        if (dueDate != null)
                          Text(
                            '截止 ${_formatDate(dueDate)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        if (collabType == 1) ...[
                          if (dueDate != null)
                            Text(' · ', style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                          Text(
                            '各自独立',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownsSection(List countdowns) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 20, color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 8),
                Text(
                  '倒计时',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...countdowns.map((c) => _buildCountdownItem(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownItem(Map<String, dynamic> countdown) {
    final title = countdown['title'] ?? '';
    final targetTime = countdown['target_time'] as int?;
    final days = targetTime != null
        ? (targetTime - DateTime.now().millisecondsSinceEpoch) ~/
            (1000 * 60 * 60 * 24)
        : 0;

    final daysText = days > 0
        ? '剩余 $days 天'
        : days == 0
            ? '今天'
            : '已过 ${days.abs()} 天';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 15)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: days < 0
                  ? Colors.grey.shade200
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              daysText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: days < 0
                    ? Colors.grey.shade600
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsSection(List announcements) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.announcement_outlined,
                    size: 20, color: Colors.orangeAccent),
                const SizedBox(width: 8),
                const Text(
                  '团队公告',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.orangeAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...announcements.map((a) => _buildAnnouncementItem(a)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementItem(Map<String, dynamic> announcement) {
    final title = announcement['title'] ?? '';
    final content = announcement['content'] ?? '';
    final creatorName = announcement['creator_name'];
    final createdAt = announcement['created_at'] as int?;
    final isPriority = announcement['is_priority'] == 1 ||
        announcement['is_priority'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPriority
            ? BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.3))
            : BorderSide.none,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '置顶',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (creatorName != null) creatorName,
                if (createdAt != null) _formatDateTime(createdAt),
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${_formatDate(timestamp)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
