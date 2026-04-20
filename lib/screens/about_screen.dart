import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:convert';
import '../../utils/page_transitions.dart';
import 'settings/device_version_detail_page.dart';
import 'login_screen.dart';
import '../storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String? _privacyPolicyContent;
  String? _privacyPolicyDate;
  bool _isLoadingPrivacy = true;
  String _deviceArch = '加载中...';
  String _deviceModel = '';
  String _osVersion = '';

  static const String PRIVACY_RAW_URL =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _fetchReleases();
    _fetchPrivacyPolicy();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        if (mounted) {
          setState(() {
            _deviceArch = androidInfo.supportedAbis.join(', ');
            _deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
            _osVersion =
                'Android ${androidInfo.version.release} (API ${androidInfo.version.sdkInt})';
          });
        }
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        if (mounted) {
          setState(() {
            _deviceArch = 'Windows';
            _deviceModel = windowsInfo.computerName;
            _osVersion =
                'Windows ${windowsInfo.majorVersion}.${windowsInfo.minorVersion}';
          });
        }
      }
    } catch (e) {
      debugPrint('获取设备信息失败: $e');
    }
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

  Future<void> _fetchPrivacyPolicy() async {
    try {
      final response = await http.get(Uri.parse(PRIVACY_RAW_URL));
      if (response.statusCode == 200) {
        final content = response.body;
        String? date;
        final dateMatch = RegExp(r'\*\*版本日期：(.+?)\*\*').firstMatch(content);
        if (dateMatch != null) {
          date = dateMatch.group(1)?.trim();
        }
        if (mounted) {
          setState(() {
            _privacyPolicyContent = content;
            _privacyPolicyDate = date;
            _isLoadingPrivacy = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingPrivacy = false);
      }
    } catch (e) {
      debugPrint('获取隐私政策失败: $e');
      if (mounted) setState(() => _isLoadingPrivacy = false);
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

  Future<void> _showPrivacyPolicyPage() async {
    await Navigator.push(
      context,
      PageTransitions.slideHorizontal(
        PrivacyPolicyPage(
          content: _privacyPolicyContent,
          date: _privacyPolicyDate,
          isLoading: _isLoadingPrivacy,
        ),
      ),
    );
  }

  Future<void> _showWithdrawConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回隐私同意'),
        content: const Text(
          '撤回同意后，将退出当前账号并清除本地所有数据。\n\n已收集的个人信息将在合理期限内删除或匿名化处理。\n\n是否确认撤回？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认撤回'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _withdrawAndLogout();
    }
  }

  Future<void> _withdrawAndLogout() async {
    await StorageService.withdrawPrivacyAgreement();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
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
              '版本 $_version',
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
            _buildDeviceCard(context),
            const SizedBox(height: 16),
            _buildPrivacyCard(context),
            const SizedBox(height: 16),
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

  Widget _buildPrivacyCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.privacy_tip_outlined,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('隐私政策'),
              subtitle: _privacyPolicyDate != null
                  ? Text('版本日期：$_privacyPolicyDate')
                  : const Text('查看我们如何收集、使用和保护您的个人信息'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showPrivacyPolicyPage,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.do_not_disturb_on_outlined,
                  color: Colors.orange),
              title: const Text('撤回隐私同意'),
              subtitle: const Text('撤回后将退出账号并清除本地数据'),
              onTap: _showWithdrawConfirmation,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context) {
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
                  Icon(Icons.devices,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('设备信息',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 12),
              _buildInfoRow('设备型号', _deviceModel),
              const SizedBox(height: 8),
              _buildInfoRow('操作系统', _osVersion),
              const SizedBox(height: 8),
              _buildInfoRow('CPU 架构', _deviceArch),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
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

class PrivacyPolicyPage extends StatelessWidget {
  final String? content;
  final String? date;
  final bool isLoading;

  const PrivacyPolicyPage({
    super.key,
    this.content,
    this.date,
    this.isLoading = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私政策'),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : content == null
              ? const Center(child: Text('加载失败，请检查网络连接'))
              : Markdown(
                  data: content!,
                  padding: const EdgeInsets.all(16),
                  styleSheet: MarkdownStyleSheet(
                    h1: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    h2: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    h3: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    p: const TextStyle(fontSize: 14, height: 1.6),
                    listBullet: const TextStyle(fontSize: 14),
                    blockquote: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    code:
                        const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    codeblockDecoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
    );
  }
}
