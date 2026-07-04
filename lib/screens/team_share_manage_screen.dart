import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../models.dart';
import '../services/api_service.dart';

class TeamShareManageScreen extends StatefulWidget {
  final Team team;

  const TeamShareManageScreen({super.key, required this.team});

  @override
  State<TeamShareManageScreen> createState() => _TeamShareManageScreenState();
}

class _TeamShareManageScreenState extends State<TeamShareManageScreen> {
  List<TeamShare> _shares = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  Future<void> _loadShares() async {
    setState(() => _isLoading = true);
    try {
      final sharesData = await ApiService.fetchTeamShares(widget.team.uuid);
      setState(() {
        _shares = sharesData.map((s) => TeamShare.fromJson(s)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showCreateShareDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _CreateShareScreen(
          team: widget.team,
          onCreated: () {
            _loadShares();
          },
        ),
      ),
    );
  }

  Future<void> _deleteShare(TeamShare share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分享'),
        content: Text('确定删除分享链接「${share.title ?? share.shareCode}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await ApiService.deleteTeamShare(share.shareCode);
      if (result['success'] == true) {
        _loadShares();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('分享链接已删除')),
          );
        }
      }
    }
  }

  Future<void> _toggleShare(TeamShare share) async {
    final result = await ApiService.updateTeamShare(
      shareCode: share.shareCode,
      isActive: !share.isActive,
    );
    if (result['success'] == true) {
      _loadShares();
    }
  }

  void _copyShareLink(TeamShare share) {
    final url = share.shareUrl ?? 'https://api-cdt.junpgle.me/share/${share.shareCode}';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('链接已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.team.name} · 分享管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadShares,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shares.isEmpty
              ? _buildEmptyState()
              : _buildSharesList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateShareDialog,
        icon: const Icon(Icons.add_link),
        label: const Text('创建分享'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.link_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无分享链接',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            '创建分享链接，让其他人以网页形式查看团队事项',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSharesList() {
    return RefreshIndicator(
      onRefresh: _loadShares,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _shares.length,
        itemBuilder: (context, index) => _buildShareCard(_shares[index]),
      ),
    );
  }

  Widget _buildShareCard(TeamShare share) {
    final isExpired = share.isExpired;
    final isInactive = !share.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.link,
                  color: isExpired || isInactive
                      ? Colors.grey
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        share.title ?? '分享链接',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (share.description != null)
                        Text(
                          share.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: share.isActive,
                  onChanged: (value) => _toggleShare(share),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.access_time,
              '创建于 ${_formatDate(share.createdAt)}',
            ),
            if (share.expiresAt != null)
              _buildInfoRow(
                Icons.event,
                isExpired ? '已过期' : '过期时间 ${_formatDate(share.expiresAt!)}',
                color: isExpired ? Colors.red : null,
              ),
            _buildInfoRow(
              Icons.visibility,
              '浏览 ${share.viewCount} 次',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (share.shareTodos)
                  _buildTag('待办事项', Icons.check_circle_outline),
                if (share.shareCountdowns)
                  _buildTag('倒计时', Icons.timer_outlined),
                if (share.shareAnnouncements)
                  _buildTag('团队公告', Icons.announcement_outlined),
                if (share.hasPassword)
                  _buildTag('密码保护', Icons.lock_outline),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyShareLink(share),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制链接'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteShare(share),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? Colors.grey.shade500),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color ?? Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _CreateShareScreen extends StatefulWidget {
  final Team team;
  final VoidCallback onCreated;

  const _CreateShareScreen({required this.team, required this.onCreated});

  @override
  State<_CreateShareScreen> createState() => _CreateShareScreenState();
}

class _CreateShareScreenState extends State<_CreateShareScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _shareTodos = true;
  bool _shareCountdowns = true;
  bool _shareAnnouncements = true;
  bool _usePassword = false;
  int? _expiresHours;
  bool _isCreating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createShare() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);

    try {
      final result = await ApiService.createTeamShare(
        teamUuid: widget.team.uuid,
        title: _titleController.text.isNotEmpty ? _titleController.text : null,
        description: _descController.text.isNotEmpty ? _descController.text : null,
        shareTodos: _shareTodos,
        shareCountdowns: _shareCountdowns,
        shareAnnouncements: _shareAnnouncements,
        password: _usePassword ? _passwordController.text : null,
        expiresHours: _expiresHours,
      );

      if (result['success'] == true) {
        final shareUrl = result['share_url'] ?? '';
        if (mounted) {
          widget.onCreated();

          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('分享创建成功'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('分享链接已生成，复制后发送给其他人即可查看：'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      shareUrl,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: shareUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('链接已复制')),
                    );
                  },
                  child: const Text('复制链接'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          );

          if (mounted) Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? '创建失败')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建分享链接'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: '标题（可选）',
                hintText: '例如：项目进度',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: '描述（可选）',
                hintText: '简要说明分享内容',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            const Text(
              '分享内容',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('待办事项'),
              value: _shareTodos,
              onChanged: (v) => setState(() => _shareTodos = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text('倒计时'),
              value: _shareCountdowns,
              onChanged: (v) => setState(() => _shareCountdowns = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text('团队公告'),
              value: _shareAnnouncements,
              onChanged: (v) => setState(() => _shareAnnouncements = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 32),
            SwitchListTile(
              title: const Text('密码保护'),
              subtitle: const Text('访问者需要输入密码才能查看'),
              value: _usePassword,
              onChanged: (v) => setState(() => _usePassword = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_usePassword) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '设置密码',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                obscureText: true,
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              '过期时间',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildExpiryChip('1 天', 24),
                _buildExpiryChip('7 天', 168),
                _buildExpiryChip('30 天', 720),
                _buildExpiryChip('永不过期', null),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_shareTodos || _shareCountdowns || _shareAnnouncements) && !_isCreating
                    ? _createShare
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('生成分享链接'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiryChip(String label, int? hours) {
    final isSelected = _expiresHours == hours;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _expiresHours = selected ? hours : null);
      },
    );
  }
}
