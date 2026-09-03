import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/management_page.dart';

class TeamMessageCenterScreen extends StatefulWidget {
  final List<Team> managedTeams;
  final Future<Map<String, dynamic>> Function(String)? fetchMessages;
  final Future<Map<String, dynamic>> Function(String, int, String)?
      processRequest;
  const TeamMessageCenterScreen(
      {super.key,
      required this.managedTeams,
      this.fetchMessages,
      this.processRequest});

  @override
  State<TeamMessageCenterScreen> createState() =>
      _TeamMessageCenterScreenState();
}

class _TeamMessageCenterScreenState extends State<TeamMessageCenterScreen> {
  bool _isLoading = true;
  List<dynamic> _messages = [];
  final Set<String> _processingJoinRequestKeys = <String>{};
  int _loadGeneration = 0;
  String? _loadError;
  bool _pendingOnly = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isPending(dynamic msg) =>
      msg['type'] == 'JOIN_REQUEST' &&
      msg['request_status'] != null &&
      _asInt(msg['request_status']) == 0;

  @override
  void initState() {
    super.initState();
    _loadAllMessages();
  }

  Future<void> _loadAllMessages() async {
    final int loadGeneration = ++_loadGeneration;
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final List<dynamic> allMessages = [];
    var failedTeams = 0;
    final Set<String> seenMessageKeys = <String>{};
    try {
      // 🚀 核心优化：并发加载所有管理团队的消息
      final results = await Future.wait(widget.managedTeams.map((team) =>
          (widget.fetchMessages ??
              ApiService.fetchTeamSystemMessages)(team.uuid)));

      for (int i = 0; i < widget.managedTeams.length; i++) {
        final team = widget.managedTeams[i];
        final res = results[i];

        if (res['success'] == true) {
          final msgs = List<dynamic>.from(res['messages'] as List? ?? const []);
          for (var m in msgs) {
            if (m is! Map) continue;
            final msg = Map<String, dynamic>.from(m);
            msg['team_name'] = team.name;
            msg['team_uuid'] ??= team.uuid;

            final messageKey = _messageKey(msg);
            if (!seenMessageKeys.add(messageKey)) {
              continue;
            }
            allMessages.add(msg);
          }
        } else {
          failedTeams++;
        }
      }
      // 按时间倒序排列
      allMessages.sort((a, b) {
        final int aTs = _asInt(a['timestamp']);
        final int bTs = _asInt(b['timestamp']);
        return bTs.compareTo(aTs);
      });

      if (mounted && loadGeneration == _loadGeneration) {
        setState(() {
          _messages = allMessages;
          _loadError = failedTeams == 0 ? null : '$failedTeams 个团队的消息加载失败，请重试。';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && loadGeneration == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _loadError = '消息加载失败，请检查网络后重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final pending = _messages.where(_isPending).length;
    final visible = _messages.where((msg) {
      if (_pendingOnly && !_isPending(msg)) return false;
      return ['message', 'team_name', 'username'].any(
          (key) => (msg[key]?.toString() ?? '').toLowerCase().contains(query));
    }).toList();
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: FloatingGlassAppBar(
        title: const Text('消息中心'),
        flexibleSpace: const FloatingGlassTopBarBackground(),
        actions: [
          IconButton(
              tooltip: '刷新消息',
              onPressed: _isLoading ? null : _loadAllMessages,
              icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllMessages,
              child: ManagementPage(maxWidth: 900, children: [
                const ManagementIntro(
                    icon: Icons.forum_outlined,
                    title: '团队动态，一处处理',
                    description: '查看所管理团队的系统消息，及时处理入队申请。'),
                if (_loadError != null) ...[
                  ManagementLoadError(
                      inline: true,
                      title: _loadError!,
                      onRetry: _loadAllMessages),
                ],
                ManagementSearchField(
                    controller: _searchController,
                    hintText: '搜索消息、团队或成员',
                    onChanged: (_) => setState(() {})),
                const SizedBox(height: 14),
                ManagementFilterBar<bool>(
                    value: _pendingOnly,
                    onChanged: (value) => setState(() => _pendingOnly = value),
                    options: [
                      ManagementFilterOption(
                          value: false, label: '全部 ${_messages.length}'),
                      ManagementFilterOption(value: true, label: '待处理 $pending')
                    ]),
                const SizedBox(height: 16),
                if (visible.isEmpty && _loadError == null)
                  ManagementEmptyState(
                    icon: _pendingOnly
                        ? Icons.task_alt_rounded
                        : Icons.mark_email_read_outlined,
                    title: query.isNotEmpty
                        ? '没有找到匹配的消息'
                        : _pendingOnly
                            ? '暂时没有待处理申请'
                            : '暂无系统消息',
                    description: query.isNotEmpty
                        ? '试试其他关键词，或清空搜索。'
                        : _pendingOnly
                            ? '新的入队申请会显示在这里。'
                            : '团队申请和成员变动会汇总在这里。',
                  ),
                ...visible.map(_buildMessageCard),
              ]),
            ),
    );
  }

  Widget _buildMessageCard(dynamic msg) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = DateFormat('yyyy-MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(_asInt(msg['timestamp'])));
    final (icon, title) = switch (msg['type']) {
      'JOIN_REQUEST' => (Icons.person_add_outlined, '入队申请'),
      'MEMBER_EXIT' => (Icons.logout_rounded, '成员退出'),
      'MEMBER_REMOVED' => (Icons.person_remove_outlined, '成员移出'),
      _ => (Icons.notifications_outlined, '系统通知'),
    };
    final pending = _isPending(msg);
    final processing =
        _processingJoinRequestKeys.contains(_joinRequestKey(msg));
    return ManagementCard(
      key: ValueKey(_messageKey(msg)),
      borderColor: pending ? scheme.primary.withValues(alpha: 0.45) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: scheme.primary)),
              ]),
              Text(time,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
        const SizedBox(height: 12),
        Text(msg['message']?.toString() ?? '',
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.groups_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg['team_name']?.toString() ?? '',
                  style: TextStyle(color: scheme.onSurfaceVariant))),
        ]),
        if (msg['username'] != null) ...[
          const SizedBox(height: 6),
          Text('成员 · ${msg['username']}',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
        if (msg['type'] == 'JOIN_REQUEST' && msg['request_status'] != null) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (pending)
            ManagementActionBar(children: [
              TextButton(
                  onPressed: processing
                      ? null
                      : () => _handleJoinRequest(msg, 'reject'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: const Text('拒绝')),
              FilledButton.icon(
                  onPressed: processing
                      ? null
                      : () => _handleJoinRequest(msg, 'approve'),
                  icon: processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(processing ? '处理中…' : '同意入队')),
            ])
          else
            Align(
                alignment: Alignment.centerRight,
                child: Text(_asInt(msg['request_status']) == 1 ? '已同意' : '已拒绝',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant))),
        ],
      ]),
    );
  }

  Future<void> _handleJoinRequest(dynamic msg, String action) async {
    final key = _joinRequestKey(msg);
    if (_processingJoinRequestKeys.contains(key)) return;

    if (mounted) {
      setState(() {
        _processingJoinRequestKeys.add(key);
      });
    }

    try {
      final res =
          await (widget.processRequest ?? ApiService.processJoinRequest)(
              msg['team_uuid'], _asInt(msg['user_id']), action);
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(action == 'approve' ? '已批准入队' : '已拒绝申请')));
        await _loadAllMessages();
      } else {
        final isHandled = res['error']?.toString().contains('已处理') == true ||
            res['error']?.toString().contains('并行处理') == true;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['error']?.toString() ?? '操作失败')));
        if (isHandled) await _loadAllMessages();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('处理失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _processingJoinRequestKeys.remove(key));
    }
  }

  String _joinRequestKey(dynamic msg) {
    return '${msg['team_uuid'] ?? ''}:${msg['user_id'] ?? ''}';
  }

  String _messageKey(dynamic msg) {
    return '${msg['type'] ?? ''}:${msg['team_uuid'] ?? ''}:${msg['user_id'] ?? ''}:${_asInt(msg['timestamp'])}:${msg['message'] ?? ''}';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
