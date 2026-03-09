import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../storage_service.dart';
import '../update_service.dart';
import 'login_screen.dart';
import 'home_dashboard.dart';

/// 重大版本升级引导页
/// - 首次打开新版本时展示更新日志
/// - 仅 v1.7.7 额外展示数据清洗引导步骤
class UpgradeGuideScreen extends StatefulWidget {
  final String? loggedInUser;

  const UpgradeGuideScreen({super.key, this.loggedInUser});

  static const String _guideKey = 'upgrade_guide_shown_version';
  // 需要数据清洗引导的版本
  static const String _dataMigrationVersion = '1.7.7';

  /// 返回是否应该展示引导页（当前版本与上次展示版本不同时）
  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getString(_guideKey) ?? '';
    final info = await PackageInfo.fromPlatform();
    return shown != info.version;
  }

  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    await prefs.setString(_guideKey, info.version);
  }

  @override
  State<UpgradeGuideScreen> createState() => _UpgradeGuideScreenState();
}

class _UpgradeGuideScreenState extends State<UpgradeGuideScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _step1Done = false;
  bool _isClearing = false;

  // 从远端加载的数据
  String _currentVersion = '';
  String _changelogTitle = '';
  List<ChangelogEntry> _changelogHistory = [];
  bool _loadingChangelog = true;
  bool _needsMigration = false; // 是否是需要数据清洗的版本
  // 控制历史版本展开/折叠（key = version_name）
  final Set<String> _expandedVersions = {};

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    _needsMigration = _currentVersion == UpgradeGuideScreen._dataMigrationVersion;

    try {
      final manifest = await UpdateService.checkManifest();
      if (manifest != null && mounted) {
        setState(() {
          _changelogTitle = manifest.updateInfo.title.isNotEmpty
              ? manifest.updateInfo.title
              : 'v$_currentVersion 更新日志';
          _changelogHistory = manifest.changelogHistory;
          _loadingChangelog = false;
        });
        return;
      }
    } catch (_) {}

    // 网络失败兜底
    if (mounted) {
      setState(() {
        _changelogTitle = 'v$_currentVersion 更新日志';
        _changelogHistory = [];
        _loadingChangelog = false;
      });
    }
  }

  void _nextPage() {
    if (_currentPage < (_needsMigration ? 2 : 0)) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _clearLocalData() async {
    setState(() => _isClearing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = widget.loggedInUser ?? '';
      await prefs.remove('${StorageService.KEY_TODOS}_$username');
      await prefs.remove('${StorageService.KEY_COUNTDOWNS}_$username');
      await prefs.remove('last_sync_time_$username');
      setState(() { _step1Done = true; _isClearing = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ 本地数据已清除，下次同步将从云端重新拉取'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      setState(() => _isClearing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清除失败：$e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _logoutAndLogin() async {
    await StorageService.clearLoginSession();
    await UpgradeGuideScreen.markShown();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _done() async {
    await UpgradeGuideScreen.markShown();
    if (!mounted) return;
    // 引导页是路由根（home），不能 pop，必须 pushAndRemoveUntil
    final username = widget.loggedInUser;
    final dest = (username != null && username.isNotEmpty)
        ? HomeDashboard(username: username)
        : const LoginScreen();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => dest),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ─── 更新日志页 ───────────────────────────────────────────
  Widget _buildChangelogPage() {
    // 当前版本条目（从历史记录中找，或兜底空列表）
    final current = _changelogHistory.isNotEmpty
        ? _changelogHistory.first
        : null;
    // 历史版本（当前版本之外的所有条目）
    final history = _changelogHistory.length > 1
        ? _changelogHistory.sublist(1)
        : <ChangelogEntry>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 当前版本卡片 ──────────────────────────────────
          _buildCurrentVersionCard(current),

          // ── 历史版本折叠列表 ──────────────────────────────
          if (history.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(children: [
              Icon(Icons.history_rounded,
                  size: 16,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45)),
              const SizedBox(width: 6),
              Text(
                '历史版本',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            ...history.map((e) => _buildHistoryVersionTile(e)),
          ],

          if (_loadingChangelog)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 当前版本高亮卡片（带 "NEW" 徽章）
  Widget _buildCurrentVersionCard(ChangelogEntry? entry) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 版本号 + NEW 徽章 + 日期
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v${entry?.versionName ?? _currentVersion}',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('NEW',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            if (entry?.date.isNotEmpty == true)
              Text(
                entry!.date,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          if (_loadingChangelog)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (entry == null || entry.items.isEmpty)
            Text(
              '请联网后查看详细更新内容。',
              style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.6)),
            )
          else
            ...entry.items.map((item) => _buildBulletItem(item, scheme)),

          // v1.7.7 额外警告
          if (_needsMigration) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本版本需要清除本地数据并重新登录，点击下一步了解详情。',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 历史版本折叠 Tile
  Widget _buildHistoryVersionTile(ChangelogEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final isExpanded = _expandedVersions.contains(entry.versionName);
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isExpanded) {
              _expandedVersions.remove(entry.versionName);
            } else {
              _expandedVersions.add(entry.versionName);
            }
          }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Text(
                'v${entry.versionName}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(width: 8),
              if (entry.date.isNotEmpty)
                Text(
                  entry.date,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              const Spacer(),
              // 摘要（折叠时显示第一条）
              if (!isExpanded && entry.items.isNotEmpty)
                Flexible(
                  child: Text(
                    entry.items.first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.35)),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ]),
          ),
        ),
        // 展开内容
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 2, bottom: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entry.items
                  .map((item) => _buildBulletItem(item, scheme,
                      textAlpha: 0.65, fontSize: 12.5))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildBulletItem(String item, ColorScheme scheme,
      {double textAlpha = 0.75, double fontSize = 13.5}) {
    // 根据前缀选择颜色和图标
    Color dotColor = scheme.onSurface.withValues(alpha: 0.4);
    if (item.startsWith('【新增】')) dotColor = Colors.green;
    else if (item.startsWith('【优化】')) dotColor = Colors.blue;
    else if (item.startsWith('【修复】')) dotColor = Colors.orange;
    else if (item.startsWith('【重构】')) dotColor = Colors.purple;
    else if (item.startsWith('⚠️')) dotColor = Colors.red;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item,
              style: TextStyle(
                fontSize: fontSize,
                color: scheme.onSurface.withValues(alpha: textAlpha),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 步骤 1：清除本地数据（仅 v1.7.7）─────────────────────
  Widget _buildStep1Page() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _stepHeader(
            step: 1,
            icon: Icons.delete_sweep_rounded,
            iconColor: Colors.orange,
            title: '清除本地旧数据',
            subtitle: '为彻底解决日期丢失的顽疾，必须丢弃本地受污染的缓存。\n点击下方按钮清除，重新登录后应用将自动从云端拉取全新、正确的数据。',
          ),
          const SizedBox(height: 32),
          _infoCard(
            icon: Icons.cloud_done_rounded,
            color: Colors.blue,
            title: '云端数据安全',
            content: '你在云端存储的所有待办、重要日数据完整保留，不会受到影响。',
          ),
          const SizedBox(height: 12),
          _infoCard(
            icon: Icons.phone_android_rounded,
            color: Colors.orange,
            title: '本地数据将被清除',
            content: '仅清除本设备的本地缓存，清除后通过同步可以从云端完整恢复。',
          ),
          const Spacer(),
          if (_step1Done)
            _successBadge('本地数据已清除')
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isClearing ? null : _clearLocalData,
                icon: _isClearing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.delete_sweep_rounded),
                label: Text(_isClearing ? '正在清除…' : '清除本地数据'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _step1Done ? _nextPage : null,
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('下一步'),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 步骤 2：退出并重新登录（仅 v1.7.7）───────────────────
  Widget _buildStep2Page() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _stepHeader(
            step: 2,
            icon: Icons.login_rounded,
            iconColor: Colors.green,
            title: '退出账号并重新登录',
            subtitle: '为激活最新的账户统计接口，你需要重新登录来获取最新的安全令牌。',
          ),
          const SizedBox(height: 32),
          _infoCard(
            icon: Icons.sync_rounded,
            color: Colors.blue,
            title: '重新登录后',
            content: '登录成功后，应用会立刻开始全量同步，把云端数据完好无损地拉取回设备。',
          ),
          const SizedBox(height: 12),
          _infoCard(
            icon: Icons.lock_reset_rounded,
            color: Colors.green,
            title: '密码不需要修改',
            content: '你的账号密码没有任何变化，直接使用原来的邮箱和密码登录即可。',
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _step1Done ? _logoutAndLogin : null,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('退出账号并前往登录'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (!_step1Done) ...[
            const SizedBox(height: 8),
            Text('请先完成步骤 1',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.45))),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: _done,
            child: Text('跳过（极其不推荐）',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ─── 通用子组件 ───────────────────────────────────────────
  Widget _stepHeader({
    required int step,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Column(children: [
      Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 36, color: iconColor),
          ),
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
            child: Center(
              child: Text('$step',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text(title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Text(subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
              height: 1.5)),
    ]);
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13, color: color)),
                const SizedBox(height: 4),
                Text(content,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _successBadge(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: Colors.green, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isActive = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 6,
          width: isActive ? 24 : 8,
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 非 v1.7.7：只有更新日志一页；v1.7.7：更新日志 + 2 个迁移步骤
    final pages = _needsMigration
        ? [_buildChangelogPage(), _buildStep1Page(), _buildStep2Page()]
        : [_buildChangelogPage()];
    final pageLabels = _needsMigration
        ? ['更新日志', '步骤 1 / 2', '步骤 2 / 2']
        : ['更新日志'];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          Icon(Icons.system_update_rounded,
              size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            _loadingChangelog
                ? '版本更新'
                : 'v$_currentVersion 版本更新',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                pageLabels[_currentPage],
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
        bottom: pages.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildPageIndicator(pages.length),
                ),
              )
            : null,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _currentPage = i),
        children: pages,
      ),
      // 更新日志页底部按钮
      bottomNavigationBar: _currentPage == 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: _needsMigration
                    // v1.7.7：进入迁移流程
                    ? FilledButton.icon(
                        onPressed: _nextPage,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('开始迁移并清洗'),
                        style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14)),
                      )
                    // 其他版本：知道了，直接关闭
                    : FilledButton.icon(
                        onPressed: _loadingChangelog ? null : _done,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('知道了'),
                        style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14)),
                      ),
              ),
            )
          : null,
    );
  }
}

