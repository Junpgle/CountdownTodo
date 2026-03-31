import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutSection extends StatefulWidget {
  final bool isCheckingUpdate;
  final VoidCallback onCheckUpdates;

  const AboutSection({
    Key? key,
    required this.isCheckingUpdate,
    required this.onCheckUpdates,
  }) : super(key: key);

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  String _version = '加载中...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = '${info.version} (Build ${info.buildNumber})';
      });
    }
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    }
  }

  void _showChangelogDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新日志'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('v2.4.0', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• 优化了系统性能和稳定性'),
              Text('• 修复了已知问题'),
              SizedBox(height: 16),
              Text('v2.3.0', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• 新增屏幕时间统计功能'),
              Text('• 新增番茄钟专注功能'),
              Text('• 优化了数据同步机制'),
              SizedBox(height: 16),
              Text('v2.2.0', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• 新增课程管理功能'),
              Text('• 新增学期进度显示'),
              Text('• 支持多设备数据同步'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showDeveloperContact() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开发者联系'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('邮箱'),
              subtitle: const Text('junpgle@example.com'),
              onTap: () {
                _launchURL('mailto:junpgle@example.com');
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('GitHub Issues'),
              subtitle: const Text('提交问题与建议'),
              onTap: () {
                _launchURL('https://github.com/Junpgle/math_quiz_app/issues');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text('关于此应用',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blue),
                title: const Text('软件介绍'),
                subtitle: const Text('CountDownTodo - 您的个人效率助手'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('软件介绍'),
                      content: const SingleChildScrollView(
                        child: Text(
                          'CountDownTodo 是一款集成了多种实用功能的个人效率管理应用，旨在帮助您更好地管理时间、任务和学习。\n\n'
                          '主要功能：\n'
                          '• 待办事项管理 - 轻松记录和跟踪日常任务\n'
                          '• 重要日倒计时 - 不错过任何重要日期\n'
                          '• 课程表管理 - 智能导入和提醒课程安排\n'
                          '• 屏幕使用时间 - 了解您的数字生活习惯\n'
                          '• 番茄钟专注 - 提高学习和工作效率\n'
                          '• 数学测验 - 趣味数学练习\n'
                          '• 多设备同步 - 数据云端备份，跨设备访问\n\n'
                          '我们致力于为用户提供简洁、高效、可靠的个人管理体验。',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.tag, color: Colors.green),
                title: const Text('当前版本'),
                subtitle: Text(_version),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _version));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('版本号已复制到剪贴板')),
                    );
                  },
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.system_update, color: Colors.orange),
                title: const Text('检查更新'),
                trailing: widget.isCheckingUpdate
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: widget.isCheckingUpdate ? null : widget.onCheckUpdates,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.description, color: Colors.purple),
                title: const Text('更新日志'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showChangelogDialog,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.code, color: Colors.black87),
                title: const Text('官方 GitHub'),
                subtitle: const Text('github.com/Junpgle/math_quiz_app'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  _launchURL('https://github.com/Junpgle/math_quiz_app');
                },
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.contact_support, color: Colors.teal),
                title: const Text('开发者联系'),
                subtitle: const Text('问题反馈与建议'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showDeveloperContact,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
