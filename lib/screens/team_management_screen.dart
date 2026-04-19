import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../models.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import './unified_waterfall_screen.dart';
import './conflict_inbox_screen.dart';

class TeamManagementScreen extends StatefulWidget {
  final String username;
  const TeamManagementScreen({Key? key, required this.username}) : super(key: key);

  @override
  _TeamManagementScreenState createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  List<Team> _teams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() => _isLoading = true);
    final rawTeams = await ApiService.fetchTeams();
    setState(() {
      _teams = rawTeams.map((t) => Team.fromJson(t)).toList();
      _isLoading = false;
    });
  }

  void _showCreateTeamDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('创建协作团队'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '团队名称',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
          StatefulBuilder(builder: (ctx, setDialogState) {
            bool isProcessing = false;
            return ElevatedButton(
              onPressed: isProcessing ? null : () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                setDialogState(() => isProcessing = true);
                try {
                  final res = await ApiService.createTeam(name);
                  if (res['success'] == true) {
                    Navigator.pop(context);
                    _loadTeams();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('团队创建成功 ✨')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? res['message'] ?? '创建失败')));
                  }
                } finally {
                  if (ctx.mounted) setDialogState(() => isProcessing = false);
                }
              },
              child: isProcessing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('创建'),
            );
          }),
        ],
      ),
    );
  }

  void _showJoinTeamDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('加入协作团队'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '请输入邀请码',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
          StatefulBuilder(builder: (ctx, setDialogState) {
            bool isProcessing = false;
            return ElevatedButton(
              onPressed: isProcessing ? null : () async {
                final code = controller.text.trim();
                if (code.isEmpty) return;
                setDialogState(() => isProcessing = true);
                try {
                  final res = await ApiService.joinTeamByCode(code);
                  if (res['success'] == true) {
                    Navigator.pop(context);
                    _loadTeams();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('成功加入团队 🚀')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? res['message'] ?? '加入失败')));
                  }
                } finally {
                  if (ctx.mounted) setDialogState(() => isProcessing = false);
                }
              },
              child: isProcessing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('加入'),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // 背景装饰
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.blue.withOpacity(0.3), Colors.purple.withOpacity(0.2)],
                ),
              ),
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text('团队协作', style: TextStyle(fontWeight: FontWeight.bold)),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark 
                          ? [Colors.blueGrey[900]!, Colors.black] 
                          : [Colors.blue[50]!, Colors.white],
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: _loadTeams,
                  ),
                ],
              ),
              if (_isLoading)
                SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else ...[
                // 🚀 Uni-Sync 4.0: 协作功能中心 (全景时间轴 + 冲突解决)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        _buildQuickActionCard(
                          title: "全景汇聚",
                          desc: "时间轴对齐",
                          icon: Icons.waterfall_chart_rounded,
                          color: Colors.blueAccent,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UnifiedWaterfallScreen(username: widget.username))),
                        ),
                        const SizedBox(width: 12),
                        _buildQuickActionCard(
                          title: "冲突中心",
                          desc: "数据对齐",
                          icon: Icons.verified_user_rounded,
                          color: Colors.orangeAccent,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ConflictInboxScreen(username: widget.username))),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_teams.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.group_off_outlined, size: 80, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('尚未加入任何团队', style: TextStyle(color: Colors.grey, fontSize: 16)),
                        SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _showCreateTeamDialog,
                              icon: Icon(Icons.add),
                              label: Text('创建团队'),
                            ),
                            SizedBox(width: 16),
                            OutlinedButton.icon(
                              onPressed: _showJoinTeamDialog,
                              icon: Icon(Icons.link),
                              label: Text('加入团队'),
                            ),
                          ],
                        )
                      ],
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildTeamCard(_teams[index]),
                        childCount: _teams.length,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
      floatingActionButton: _teams.isNotEmpty ? _buildSpeedDial(context) : null,
    );
  }

  Widget _buildQuickActionCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.2), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamCard(Team team) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.all(20),
            color: Theme.of(context).cardColor.withOpacity(0.8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildTeamAvatar(team),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(team.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Text('${team.memberCount} 位成员', style: TextStyle(color: Colors.grey, fontSize: 13)),
                              if (team.inviteCode != null) ...[
                                SizedBox(width: 8),
                                Container(width: 1, height: 10, color: Colors.grey.withOpacity(0.3)),
                                SizedBox(width: 8),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: team.inviteCode!));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('邀请码已复制 📋')));
                                  },
                                  child: Row(
                                    children: [
                                      Text('邀请码: ${team.inviteCode}', 
                                        style: TextStyle(
                                          color: Colors.blueAccent, 
                                          fontSize: 13, 
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'monospace'
                                        )
                                      ),
                                      SizedBox(width: 4),
                                      Icon(Icons.copy, size: 12, color: Colors.blueAccent),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (team.userRole == TeamRole.admin)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('管理员', style: TextStyle(fontSize: 10, color: Colors.blue)),
                      ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('创建于 ${DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(team.createdAt))}',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    _buildTeamActions(team),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamAvatar(Team team) {
    final colors = [Colors.blue, Colors.purple, Colors.orange, Colors.green, Colors.teal];
    final color = colors[team.uuid.hashCode % colors.length];
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          team.name.substring(0, 1).toUpperCase(),
          style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildTeamActions(Team team) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.share_outlined, size: 20),
          onPressed: () async {
            final res = await ApiService.generateInviteCode(team.uuid);
            if (res['success'] == true) {
              Clipboard.setData(ClipboardData(text: res['code']));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已生成邀请码并复制: ${res['code']}')),
              );
            }
          },
        ),
        IconButton(
          icon: Icon(Icons.people_outline, size: 20),
          onPressed: () => _showMembersSheet(team),
          tooltip: '查看成员',
        ),
        IconButton(
          icon: Icon(Icons.person_add_outlined, size: 20),
          onPressed: () => _showAddMemberDialog(team),
          tooltip: '邀请成员',
        ),
        if (team.userRole == TeamRole.admin)
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
            onPressed: () => _confirmDeleteTeam(team),
            tooltip: '解散团队',
          )
        else
          IconButton(
            icon: Icon(Icons.exit_to_app, size: 20, color: Colors.orange),
            onPressed: () => _confirmLeaveTeam(team),
            tooltip: '退出团队',
          ),
      ],
    );
  }

  void _confirmDeleteTeam(Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('解散团队'),
        content: Text('确定要解散团队 "${team.name}" 吗？此操作不可恢复，关联的群组任务将转为个人私有。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _showProcessingDialog();
              final res = await ApiService.deleteTeam(team.uuid);
              Navigator.pop(context); // Close processing
              if (res['success'] == true) {
                _loadTeams();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('团队已解散')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? '解散失败')));
              }
            },
            child: Text('解散', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveTeam(Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('退出团队'),
        content: Text('确定要退出团队 "${team.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _showProcessingDialog();
              final res = await ApiService.leaveTeam(team.uuid);
              Navigator.pop(context); // Close processing
              if (res['success'] == true) {
                _loadTeams();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已退出团队')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? '退出失败')));
              }
            },
            child: Text('退出'),
          ),
        ],
      ),
    );
  }

  void _showProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );
  }

  void _showMembersSheet(Team team) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return FutureBuilder<List<dynamic>>(
            future: ApiService.fetchTeamMembers(team.uuid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text('加载失败: ${snapshot.error}', style: TextStyle(color: Colors.red)),
                ));
              }
              final members = snapshot.data?.map((m) => TeamMember.fromJson(m)).toList() ?? [];
              
              return Column(
                children: [
                  Container(
                    margin: EdgeInsets.symmetric(vertical: 12),
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('团队成员 (${members.length})', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(team.name, style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  Divider(),
                  if (members.isEmpty)
                    Expanded(child: Center(child: Text('暂无成员', style: TextStyle(color: Colors.grey))))
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final isAdmin = member.role == TeamRole.admin;
                          final isMe = member.userId == _getCurrentUserId();

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.withOpacity(0.1),
                              child: Text(member.username?.substring(0,1).toUpperCase() ?? '?'),
                            ),
                            title: Text(member.username ?? '匿名用户'),
                            subtitle: Text('加入于 ${DateFormat('MM-dd').format(DateTime.fromMillisecondsSinceEpoch(member.joinedAt))}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAdmin)
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                    child: Text('管理员', style: TextStyle(fontSize: 10, color: Colors.blue)),
                                  ),
                                if (team.userRole == TeamRole.admin && !isAdmin)
                                  IconButton(
                                    icon: Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                    onPressed: () => _confirmRemoveMember(team, member),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _confirmRemoveMember(Team team, TeamMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除成员'),
        content: Text('确定要将 "${member.username}" 移出团队吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              _showProcessingDialog();
              final res = await ApiService.removeTeamMember(team.uuid, member.userId);
              Navigator.pop(context); // Close processing
              if (res['success'] == true) {
                Navigator.pop(context); // Close sheet
                _loadTeams();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成员已移除')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? '移除失败')));
              }
            },
            child: Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  int _getCurrentUserId() {
    // 简单实现：从 ApiService 获取 (通常是在登录时保存过的)
    return ApiService.currentUserId; 
  }

  void _showAddMemberDialog(Team team) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('邀请成员'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '对方登录邮箱',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
          StatefulBuilder(builder: (ctx, setDialogState) {
            bool isProcessing = false;
            return ElevatedButton(
              onPressed: isProcessing ? null : () async {
                final email = controller.text.trim();
                if (email.isEmpty) return;
                setDialogState(() => isProcessing = true);
                try {
                  final res = await ApiService.addTeamMemberByEmail(team.uuid, email);
                  if (res['success'] == true) {
                    Navigator.pop(context);
                    _loadTeams();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('邀请已发出 📧')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? res['message'] ?? '邀请失败')));
                  }
                } finally {
                  if (ctx.mounted) setDialogState(() => isProcessing = false);
                }
              },
              child: isProcessing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('发送'),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSpeedDial(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (context) => Container(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: CircleAvatar(child: Icon(Icons.add)),
                  title: Text('创建新团队'),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateTeamDialog();
                  },
                ),
                ListTile(
                  leading: CircleAvatar(child: Icon(Icons.link)),
                  title: Text('使用邀请码加入'),
                  onTap: () {
                    Navigator.pop(context);
                    _showJoinTeamDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
      icon: Icon(Icons.people),
      label: Text('管理团队'),
    );
  }
}
