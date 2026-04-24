import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models.dart';

class TeamMessageCenterScreen extends StatefulWidget {
  final List<Team> managedTeams;
  const TeamMessageCenterScreen({super.key, required this.managedTeams});

  @override
  _TeamMessageCenterScreenState createState() => _TeamMessageCenterScreenState();
}

class _TeamMessageCenterScreenState extends State<TeamMessageCenterScreen> {
  bool _isLoading = true;
  List<dynamic> _messages = [];
  final Set<String> _handledJoinRequestKeys = <String>{};
  final Set<String> _processingJoinRequestKeys = <String>{};
  int _loadGeneration = 0;

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
    final Set<String> seenMessageKeys = <String>{};
    try {
      for (var team in widget.managedTeams) {
        final res = await ApiService.fetchTeamSystemMessages(team.uuid);
        if (res['success'] == true) {
          final msgs = List<dynamic>.from(res['messages'] as List? ?? const []);
          for (var m in msgs) {
            if (m is! Map) continue;
            final msg = Map<String, dynamic>.from(m);
            msg['team_name'] = team.name;

            final messageKey = _messageKey(msg);
            if (!seenMessageKeys.add(messageKey)) {
              continue;
            }
            allMessages.add(msg);
          }
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
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && loadGeneration == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('消息中心', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAllMessages,
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _messages.isEmpty 
          ? _buildEmptyState(isDark)
          : RefreshIndicator(
              onRefresh: _loadAllMessages,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length,
                itemBuilder: (context, index) => _buildMessageCard(_messages[index], isDark),
              ),
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mail_outline_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('暂无系统消息', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildMessageCard(dynamic msg, bool isDark) {
    final type = msg['type'];
    final timeStr = DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(msg['timestamp']));
    
    IconData icon;
    Color color;
    String title = "";
    
    switch(type) {
      case 'JOIN_REQUEST':
        icon = Icons.person_add_rounded;
        color = Colors.blueAccent;
        title = "入队申请";
        break;
      case 'MEMBER_EXIT':
        icon = Icons.exit_to_app_rounded;
        color = Colors.orangeAccent;
        title = "成员退出";
        break;
      case 'MEMBER_REMOVED':
        icon = Icons.person_remove_rounded;
        color = Colors.redAccent;
        title = "成员移出";
        break;
      default:
        icon = Icons.notifications_rounded;
        color = Colors.grey;
        title = "系统通知";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 16, color: color),
                              const SizedBox(width: 8),
                              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
                            ],
                          ),
                          Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        msg['message'] ?? "",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.groups_rounded, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(msg['team_name'] ?? "", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          if (msg['username'] != null) ...[
                            const SizedBox(width: 8),
                            const Text("·", style: TextStyle(color: Colors.grey)),
                            const SizedBox(width: 8),
                            Text(msg['username'], style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
                          ]
                        ],
                      ),
                        if (msg['request_status'] == 0) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _handleJoinRequest(msg, 'reject'),
                                child: const Text('拒绝', style: TextStyle(color: Colors.redAccent)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => _handleJoinRequest(msg, 'approve'),
                                child: const Text('同意'),
                              ),
                            ],
                          ),
                        ] else if (msg['request_status'] != null) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (msg['request_status'] == 1 ? Colors.green : Colors.grey).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  msg['request_status'] == 1 ? '已同意' : '已拒绝',
                                  style: TextStyle(
                                    color: msg['request_status'] == 1 ? Colors.green : Colors.grey.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ]
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

    final res = await ApiService.processJoinRequest(
      msg['team_uuid'],
      msg['user_id'],
      action
    );
    
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(action == 'approve' ? '已批准入队' : '已拒绝申请'),
        backgroundColor: Colors.green,
      ));
      await _loadAllMessages();
    } else {
      // 🚀 Uni-Sync 4.0: 处理 409 冲突（已在其他设备处理过）
      final isHandled = res['error']?.toString().contains('已处理') == true || 
                        res['error']?.toString().contains('并行处理') == true;
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['error'] ?? '操作失败'),
        backgroundColor: isHandled ? Colors.orange : Colors.redAccent,
      ));

      if (isHandled) {
        await _loadAllMessages();
      }
    }

    if (mounted) {
      setState(() {
        _processingJoinRequestKeys.remove(key);
      });
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
