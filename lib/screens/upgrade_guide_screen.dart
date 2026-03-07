import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage_service.dart';
import 'login_screen.dart';

/// 重大版本升级引导页
/// 当检测到新版本首次启动时强制展示，引导用户完成迁移步骤
class UpgradeGuideScreen extends StatefulWidget {
  final String? loggedInUser; // 当前登录用户（可能为 null）

  const UpgradeGuideScreen({super.key, this.loggedInUser});

  // ── 公有静态成员，供 main.dart 调用 ──
  // 🚀 升级到 1.7.7，确保之前看过 1.7.6 的用户能再次看到并执行数据清洗
  static const String targetVersion = '1.7.7';
  static const String _guideKey = 'upgrade_guide_shown_version';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getString(_guideKey) ?? '';
    return shown != targetVersion;
  }

  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_guideKey, targetVersion);
  }

  @override
  State<UpgradeGuideScreen> createState() => _UpgradeGuideScreenState();
}

class _UpgradeGuideScreenState extends State<UpgradeGuideScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _step1Done = false; // 清除本地数据
  bool _isClearing = false;

  void _nextPage() {
    if (_currentPage < 2) {
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

      // 清除本地待办与倒计时数据
      await prefs.remove('${StorageService.KEY_TODOS}_$username');
      await prefs.remove('${StorageService.KEY_COUNTDOWNS}_$username');
      // 重置同步水位线，强制下次同步拉取全量数据
      await prefs.remove('last_sync_time_$username');

      setState(() {
        _step1Done = true;
        _isClearing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 本地数据已清除，下次同步将从云端重新拉取'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isClearing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败：$e'), backgroundColor: Colors.red),
        );
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

  Future<void> _skipGuide() async {
    await UpgradeGuideScreen.markShown();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ─── 更新日志页 ───────────────────────────────────────────
  Widget _buildChangelogPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // 版本徽章
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v${UpgradeGuideScreen.targetVersion} 重大更新',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          _changelogSection(
            icon: Icons.sync_problem_rounded,
            iconColor: Colors.blue,
            title: '🔄 云端同步引擎彻底修复',
            items: const [
              '修复清除任务日期后，被云端旧数据强制覆盖的 Bug',
              '修复新设备拉取旧数据时，浮点时间戳解析失败导致日期丢失的问题',
              '引入绝对信任客户端日期的全量同步策略',
            ],
          ),

          _changelogSection(
            icon: Icons.security_rounded,
            iconColor: Colors.green,
            title: '🛡️ 账户与额度系统升级',
            items: const [
              '修复同步次数永远为 0（不走字）的数据库类型匹配异常',
              '修复每日同步额度在早上 8 点才刷新的时区偏差，现已回归零点准时刷新',
              '设置页现已支持精准显示账户等级与今日真实同步次数',
            ],
          ),

          _changelogSection(
            icon: Icons.data_usage_rounded,
            iconColor: Colors.orange,
            title: '⚠️ 为什么需要清洗数据？',
            items: const [
              '由于之前云端下发了部分丢失日期的脏数据，本次升级需强制清洗本地缓存。',
              '清除后，应用将重新拉取你云端最完整、正确的最新数据。',
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _changelogSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<String> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
                (item) => Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(item,
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.75),
                            height: 1.4)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 步骤 1：清除本地数据 ─────────────────────────────────
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

          // 说明卡片
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
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
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
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('下一步'),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 步骤 2：退出并重新登录 ───────────────────────────────
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
            Text(
              '请先完成步骤 1',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45)),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: _skipGuide,
            child: Text(
              '跳过（极其不推荐）',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.4),
                  fontSize: 13),
            ),
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
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: iconColor),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$step',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              height: 1.5),
        ),
      ],
    );
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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
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
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: color)),
                const SizedBox(height: 4),
                Text(content,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
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
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.4)),
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

  // ─── 底部页面指示器 ────────────────────────────────────────
  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final isActive = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 6,
          width: isActive ? 24 : 8,
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pageLabels = ['更新日志', '步骤 1 / 2', '步骤 2 / 2'];

    return Scaffold(
      // 不允许返回（必须完成引导或主动跳过）
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Icon(Icons.system_update_rounded,
                size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'v${UpgradeGuideScreen.targetVersion} 升级引导',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
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
                        .withOpacity(0.5)),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildPageIndicator(),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // 禁止手势滑动，必须按按钮
        onPageChanged: (i) => setState(() => _currentPage = i),
        children: [
          _buildChangelogPage(),
          _buildStep1Page(),
          _buildStep2Page(),
        ],
      ),
      // 更新日志页底部的"开始迁移"按钮
      bottomNavigationBar: _currentPage == 0
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: FilledButton.icon(
            onPressed: _nextPage,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('开始迁移并清洗'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      )
          : null,
    );
  }
}