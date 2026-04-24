import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models.dart';

class TeamAnnouncementScreen extends StatefulWidget {
  final Team team;
  const TeamAnnouncementScreen({super.key, required this.team});

  @override
  _TeamAnnouncementScreenState createState() => _TeamAnnouncementScreenState();
}

class _TeamAnnouncementScreenState extends State<TeamAnnouncementScreen> {
  bool _isLoading = true;
  List<TeamAnnouncement> _announcements = [];

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService.fetchTeamAnnouncements(widget.team.uuid);
      if (mounted) {
        setState(() {
          _announcements = list.map((e) => TeamAnnouncement.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String uuid) async {
    final res = await ApiService.markAnnouncementAsRead(uuid);
    if (res['success'] == true) {
      _loadAnnouncements();
    }
  }

  Future<void> _deleteAnnouncement(String uuid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认撤回'),
        content: const Text('确定要撤回这条公告吗？撤回后所有成员将无法查看。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定撤回', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await ApiService.deleteTeamAnnouncement(uuid);
      if (res['success'] == true) {
        _loadAnnouncements();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('公告已撤回')));
      }
    }
  }

  void _showCreateAnnouncementDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    bool isPosting = false;
    bool isPriority = false;
    int? selectedExpiryHours; // null means never

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 24,
            left: 24,
            right: 24,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.campaign_rounded, color: Colors.blueAccent),
                      ),
                      const SizedBox(width: 12),
                      const Text('发布新公告', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('重要置顶', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                      Switch(
                        value: isPriority,
                        activeThumbColor: Colors.orange,
                        onChanged: (val) => setModalState(() => isPriority = val),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('有效期设置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('永久'), selected: selectedExpiryHours == null, onSelected: (s) => setModalState(() => selectedExpiryHours = null)),
                  ChoiceChip(label: const Text('1天'), selected: selectedExpiryHours == 24, onSelected: (s) => setModalState(() => selectedExpiryHours = 24)),
                  ChoiceChip(label: const Text('3天'), selected: selectedExpiryHours == 72, onSelected: (s) => setModalState(() => selectedExpiryHours = 72)),
                  ChoiceChip(label: const Text('7天'), selected: selectedExpiryHours == 168, onSelected: (s) => setModalState(() => selectedExpiryHours = 168)),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: '公告标题',
                  hintText: '输入一个吸引人的标题...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.05),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: '公告内容',
                  hintText: '详细描述公告信息...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: Colors.grey.withOpacity(0.05),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPriority ? Colors.orange : Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: isPosting ? null : () async {
                    if (titleController.text.isEmpty || contentController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标题和内容不能为空')));
                      return;
                    }
                    setModalState(() => isPosting = true);
                    int? expiresAt;
                    if (selectedExpiryHours != null) {
                      expiresAt = DateTime.now().add(Duration(hours: selectedExpiryHours!)).millisecondsSinceEpoch;
                    }
                    final res = await ApiService.createTeamAnnouncement(
                      widget.team.uuid,
                      titleController.text,
                      contentController.text,
                      isPriority: isPriority,
                      expiresAt: expiresAt,
                    );
                    if (res['success'] == true) {
                      Navigator.pop(context);
                      _loadAnnouncements();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('公告已发布 🚀'), backgroundColor: Colors.green));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? '发布失败')));
                      setModalState(() => isPosting = false);
                    }
                  },
                  child: isPosting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(isPriority ? '发布重要公告' : '立即发布', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnnouncementStats(TeamAnnouncement announcement) async {
    showDialog(
      context: context,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    
    final res = await ApiService.fetchAnnouncementStats(announcement.uuid);
    Navigator.pop(context); // close loading

    if (res['success'] == true) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('阅读率统计', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('已读人数', '${res['read_count']}'),
                  _buildStatItem('总人数', '${res['total_members']}'),
                  _buildStatItem('阅读率', '${(res['read_rate'] * 100).toStringAsFixed(1)}%'),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text('已读成员列表', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: (res['read_members'] as List).length,
                  itemBuilder: (context, index) {
                    final member = res['read_members'][index];
                    final time = DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(member['read_at']));
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person, size: 16)),
                      title: Text(member['username']),
                      trailing: Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = widget.team.userRole == TeamRole.admin;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text('${widget.team.name} 公告', style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadAnnouncements),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _announcements.isEmpty
              ? _buildEmptyState(isDark)
              : RefreshIndicator(
                  onRefresh: _loadAnnouncements,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _announcements.length,
                    itemBuilder: (context, index) => _buildAnnouncementCard(_announcements[index], isDark, isAdmin),
                  ),
                ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateAnnouncementDialog,
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('发布公告'),
            )
          : null,
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.campaign_outlined, size: 64, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('暂无团队公告', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(TeamAnnouncement ann, bool isDark, bool isAdmin) {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ann.createdAt));
    final expiryStr = ann.expiresAt != null ? DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ann.expiresAt!)) : '永久';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: ann.isPriority ? Border.all(color: Colors.orange.withOpacity(0.5), width: 2) : null,
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (ann.isPriority)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                                child: const Text('重要', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              ann.title,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!ann.isRead)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Text('未读', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person_rounded, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(ann.creatorName ?? '管理员', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(width: 12),
                    Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(timeStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    if (ann.expiresAt != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.timer_off_outlined, size: 14, color: Colors.orange.shade300),
                      const SizedBox(width: 4),
                      Text('到期: $expiryStr', style: TextStyle(fontSize: 12, color: Colors.orange.shade300)),
                    ]
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                Text(
                  ann.content,
                  style: TextStyle(fontSize: 15, color: isDark ? Colors.white70 : Colors.black87, height: 1.5),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isAdmin) ...[
                  TextButton.icon(
                    onPressed: () => _showAnnouncementStats(ann),
                    icon: const Icon(Icons.bar_chart_rounded, size: 18),
                    label: const Text('统计'),
                    style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _deleteAnnouncement(ann.uuid),
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    label: const Text('撤回'),
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  ),
                ],
                const Spacer(),
                if (!ann.isRead)
                  ElevatedButton.icon(
                    onPressed: () => _markAsRead(ann.uuid),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('确认已读'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withOpacity(0.1),
                      foregroundColor: Colors.blueAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.green),
                    label: const Text('已读', style: TextStyle(color: Colors.green)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
