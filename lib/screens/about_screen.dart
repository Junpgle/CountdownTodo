import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../utils/page_transitions.dart';
import 'settings/device_version_detail_page.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '加载中...';
  String _buildNumber = '';
  List<dynamic> _releases = [];
  bool _isLoadingReleases = true;
  bool _versionExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _fetchReleases();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  Future<void> _fetchReleases() async {
    const String releasesUrl =
        'https://api.github.com/repos/Junpgle/math_quiz_app/releases';
    try {
      final response = await http.get(
        Uri.parse(releasesUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _releases = data;
            _isLoadingReleases = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingReleases = false);
        }
      }
    } catch (e) {
      debugPrint('获取更新日志失败: $e');
      if (mounted) {
        setState(() => _isLoadingReleases = false);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于此应用'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 32),
            // 应用图标和名称
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.checklist_rounded,
                size: 60,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'CountDownTodo',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '版本 $_version (Build $_buildNumber)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '您的个人效率助手',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),

            // 软件介绍卡片
            _buildInfoCard(
              context,
              title: '软件介绍',
              icon: Icons.info_outline,
              child: const Text(
                'CountDownTodo 是一款集成了多种实用功能的个人效率管理应用，旨在帮助您更好地管理时间、任务和学习。\n\n'
                '主要功能：待办事项管理、重要日倒计时、课程表管理、屏幕使用时间、番茄钟专注、数学测验、多设备同步等。',
                style: TextStyle(fontSize: 14),
              ),
            ),

            const SizedBox(height: 16),

            // 功能链接卡片
            _buildLinkCard(
              context,
              items: [
                _LinkItem(
                  icon: Icons.code,
                  title: '官方 GitHub',
                  subtitle: 'github.com/Junpgle/math_quiz_app',
                  onTap: () =>
                      _launchURL('https://github.com/Junpgle/math_quiz_app'),
                ),
                _LinkItem(
                  icon: Icons.bug_report_outlined,
                  title: '问题反馈',
                  subtitle: '在 GitHub 提交 Issues',
                  onTap: () => _launchURL(
                      'https://github.com/Junpgle/math_quiz_app/issues'),
                ),
                _LinkItem(
                  icon: Icons.devices_other_outlined,
                  title: '设备版本明细',
                  subtitle: '查看在线设备与历史版本分布',
                  onTap: () {
                    Navigator.push(
                      context,
                      PageTransitions.slideHorizontal(
                        const DeviceVersionDetailPage(),
                      ),
                    );
                  },
                ),
                _LinkItem(
                  icon: Icons.email_outlined,
                  title: '联系开发者',
                  subtitle: 'junpgle@qq.com',
                  onTap: () => _launchURL('mailto:junpgle@qq.com'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 更新日志卡片
            _buildChangelogCard(context),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkCard(BuildContext context,
      {required List<_LinkItem> items}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Column(
              children: [
                ListTile(
                  leading: Icon(item.icon,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text(item.title),
                  subtitle:
                      Text(item.subtitle, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: item.onTap,
                ),
                if (index < items.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildChangelogCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('更新日志',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: () => _launchURL(
                        'https://github.com/Junpgle/math_quiz_app/releases'),
                    tooltip: '查看全部',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _isLoadingReleases
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _releases.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('暂无更新日志'),
                          ),
                        )
                      : Column(
                          children: [
                            InkWell(
                              onTap: () => setState(
                                  () => _versionExpanded = !_versionExpanded),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      _versionExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 20,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _versionExpanded ? '收起' : '展开',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedCrossFade(
                              firstChild: const SizedBox.shrink(),
                              secondChild: Column(
                                children:
                                    _releases.take(5).map<Widget>((release) {
                                  final tagName = release['tag_name'] ?? '';
                                  final body = release['body'] ?? '暂无更新说明';
                                  final publishedAt =
                                      release['published_at'] ?? '';
                                  String dateStr = '';
                                  if (publishedAt.isNotEmpty) {
                                    try {
                                      final date = DateTime.parse(publishedAt);
                                      dateStr =
                                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                                    } catch (_) {}
                                  }

                                  return ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            tagName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (dateStr.isNotEmpty)
                                          Text(
                                            dateStr,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey),
                                          ),
                                      ],
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            left: 8, right: 8, bottom: 12),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            body,
                                            style:
                                                const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                              crossFadeState: _versionExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 300),
                            ),
                          ],
                        ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _LinkItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
