import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/pomodoro_sync_service.dart';
import '../models.dart';
import 'dart:ui';

class TeamMessageCenterScreen extends StatefulWidget {
  final List<Team> managedTeams;
  const TeamMessageCenterScreen({Key? key, required this.managedTeams}) : super(key: key);

  @override
  _TeamMessageCenterScreenState createState() => _TeamMessageCenterScreenState();
}

class _TeamMessageCenterScreenState extends State<TeamMessageCenterScreen> {
  bool _isLoading = true;
  List<dynamic> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadAllMessages();
  }

  Future<void> _loadAllMessages() async {
    setState(() => _isLoading = true);
    List<dynamic> allMessages = [];
    try {
      for (var team in widget.managedTeams) {
        final res = await ApiService.fetchTeamSystemMessages(team.uuid);
        if (res['success'] == true) {
          // 注入团队名称以便显示
          final msgs = res['messages'] as List;
          for (var m in msgs) {
            m['team_name'] = team.name;
          }
          allMessages.addAll(msgs);
        }
      }
      // 按时间倒序排列
      allMessages.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
      
      if (mounted) {
        setState(() {
          _messages = allMessages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
          Icon(Icons.mail_outline_rounded, size: 64, color: Colors.grey.withOpacity(0.3)),
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
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
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
                      if (type == 'JOIN_REQUEST') ...[
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
                        )
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
      _loadAllMessages();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['error'] ?? '操作失败'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }
}
