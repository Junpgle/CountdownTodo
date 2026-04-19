import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import '../update_service.dart';
import 'login_screen.dart';
import 'home_dashboard.dart';
import '../services/tai_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import '../storage_service.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/page_transitions.dart';

/// 首次安装或重大版本升级引导页 (v1.9.4+)
class FeatureGuideScreen extends StatefulWidget {
  final String? loggedInUser;
  final bool isManualReview;

  const FeatureGuideScreen(
      {super.key, this.loggedInUser, this.isManualReview = false});

  static const String _guideKey = 'upgrade_guide_shown_version';

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
  State<FeatureGuideScreen> createState() => _FeatureGuideScreenState();
}

class _FeatureGuideScreenState extends State<FeatureGuideScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  // 标记是否为首次安装（用于决定引导结束后是否设置默认服务器）
  bool _isFirstLaunch = false;
  static const platform =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');
  static const screenTimeChannel =
      MethodChannel('com.math_quiz_app/screen_time');

  // 从远端加载的数据
  String _currentVersion = '';
  List<ChangelogEntry> _changelogHistory = [];
  bool _loadingChangelog = true;
  String? _changelogNotice;
  final Set<String> _expandedVersions = {};

  // 权限状态
  PermissionStatus? _notificationStatus;
  bool _hasUsageStats = false;
  bool _hasExactAlarm = false;
  bool _ignoringBatteryOptimizations = false;

  // Tai目录
  String _taiDbPath = '';

  // 全局设置状态
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;
  String _themeMode = 'system';

  late List<Widget Function()> _pagesBuilder;

  @override
  void initState() {
    super.initState();
    // 默认只放第一页（更新日志），防止异步加载前数组越界
    _pagesBuilder = [_buildChangelogPage];

    _loadInfo();
    _checkPermissions();
    _loadGlobalSettings();
    _setupPages(); // 🚀 核心逻辑：判断是首次启动还是仅仅更新
  }

  Future<void> _setupPages() async {
    final prefs = await SharedPreferences.getInstance();
    final shownVersion = prefs.getString(FeatureGuideScreen._guideKey);

    // 如果之前没有记录过版本号，则是首次安装；如果 isManualReview 为 true，则是用户在设置中主动要求查看
    final isFirstLaunch = shownVersion == null || shownVersion.isEmpty;
    // 保存到 state，供 _done 使用
    _isFirstLaunch = isFirstLaunch;

    List<Widget Function()> pages = [];

    // 无论如何，第一页永远是更新日志
    pages.add(_buildChangelogPage);

    // 🚀 Uni-Sync 4.0 特别逻辑：针对老用户升级后的数据迁移提示
    if (!isFirstLaunch && !widget.isManualReview) {
      pages.add(_buildUniSyncMigrationPage);
    }

    // 只有在首次启动，或者用户手动在设置中点击查看引导时，才展示完整特性引导
    if (isFirstLaunch || widget.isManualReview) {
      if (Platform.isWindows) {
        pages.addAll([
          _buildWinFeaturePage1,
          _buildWinFeaturePage2,
          _buildTaiSetupPage,
          _buildGlobalCourseSetupPage,
          _buildGlobalThemeSetupPage,
        ]);
        _loadTaiConfig();
      } else {
        pages.addAll([
          _buildAndroidFeaturePage1,
          _buildAndroidFeaturePage2,
          _buildAndroidFeaturePage3,
          _buildAndroidWidgetGuidePage, // ← 桌面小部件引导
          _buildGlobalCourseSetupPage,
          _buildGlobalThemeSetupPage,
        ]);
      }
    }

    if (mounted) {
      setState(() {
        _pagesBuilder = pages;
      });
    }
  }

  Future<void> _loadGlobalSettings() async {
    final start = await StorageService.getSemesterStart();
    final end = await StorageService.getSemesterEnd();
    final enabled = await StorageService.getSemesterEnabled();
    final theme = await StorageService.getThemeMode();
    if (mounted) {
      setState(() {
        _semesterStart = start;
        _semesterEnd = end;
        _semesterEnabled = enabled;
        _themeMode = theme;
      });
    }
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;

    final prefs = await SharedPreferences.getInstance();
    final shownVersion = prefs.getString(FeatureGuideScreen._guideKey) ?? '';
    // 仅在“更新后的第一次开屏”时优先联网，避免看到旧缓存更新日志。
    final isFirstSplashAfterUpdate =
        shownVersion.isNotEmpty && shownVersion != _currentVersion;

    try {
      final manifest = await UpdateService.checkManifest(
        preferCache: !isFirstSplashAfterUpdate,
        refreshInBackground: !isFirstSplashAfterUpdate,
      );
      if (manifest != null && mounted) {
        setState(() {
          _changelogHistory = manifest.changelogHistory;
          _loadingChangelog = false;
          _changelogNotice = null;
        });
        return;
      }

      // 更新后首次开屏若联网失败，立即回退到离线缓存并给出提示。
      if (isFirstSplashAfterUpdate) {
        final cachedManifest = await UpdateService.checkManifest(
          preferCache: true,
          refreshInBackground: true,
        );
        if (cachedManifest != null && mounted) {
          setState(() {
            _changelogHistory = cachedManifest.changelogHistory;
            _loadingChangelog = false;
            _changelogNotice = '当前显示离线缓存更新日志，网络恢复后会自动刷新。';
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _changelogHistory = [];
        _loadingChangelog = false;
        _changelogNotice = null;
      });
    }
  }

  Future<void> _loadTaiConfig() async {
    final path = await TaiService.getSavedDbPath() ??
        await TaiService.detectDefaultPath();
    if (path != null && mounted) {
      setState(() => _taiDbPath = path);
    }
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final notifStatus = await Permission.notification.status;

    bool hasUsage = false;
    bool hasExact = false;
    bool ignoringBattery = false;

    if (Platform.isAndroid) {
      try {
        hasUsage =
            await screenTimeChannel.invokeMethod('checkUsagePermission') ??
                false;
      } catch (_) {}
      try {
        hasExact =
            await platform.invokeMethod('checkExactAlarmPermission') ?? true;
      } catch (_) {}
      try {
        ignoringBattery = await Permission.ignoreBatteryOptimizations.isGranted;
      } catch (_) {}
    } else {
      hasUsage = true;
      hasExact = true;
      ignoringBattery = true;
    }

    if (mounted) {
      setState(() {
        _notificationStatus = notifStatus;
        _hasUsageStats = hasUsage;
        _hasExactAlarm = hasExact;
        _ignoringBatteryOptimizations = ignoringBattery;
      });
    }
  }

  void _nextPage() {
    if (_currentPage < _pagesBuilder.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _done() async {
    if (!widget.isManualReview) {
      await FeatureGuideScreen.markShown();
    }
    if (!mounted) return;

    // 如果是首次启动并且不是手动查看引导，且将要跳转到登录页，则把默认服务器切换为阿里云
    if (!widget.isManualReview && _isFirstLaunch) {
      // 只有在未传入已登录用户的情况下我们修改登录页的默认服务器
      final username = widget.loggedInUser;
      if (username == null || username.isEmpty) {
        await StorageService.saveServerChoice('aliyun');
        ApiService.setServerChoice('aliyun');
      }
    }

    if (widget.isManualReview) {
      Navigator.pop(context);
    } else {
      final username = widget.loggedInUser;
      final dest = (username != null && username.isNotEmpty)
          ? HomeDashboard(username: username)
          : const LoginScreen();
      Navigator.of(context).pushAndRemoveUntil(
        PageTransitions.fadeThrough(dest),
        (_) => false,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── 通用构建器 ──────────────────────────────────────────

  Widget _buildMediaAsset(String assetPath, {BoxFit fit = BoxFit.contain}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.45),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: assetPath.toLowerCase().endsWith('.mp4')
              ? AssetVideoPlayer(assetPath: assetPath)
              : Image.asset(assetPath, fit: fit),
        ),
      ),
    );
  }

  Widget _buildPageContainer({required Widget content}) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Column(children: [
      Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, size: 36, color: iconColor),
      ),
      const SizedBox(height: 16),
      Text(title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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

  // ── 页面 1: 更新日志 (基于原有旧代码迁移) ───────────────────

  Widget _buildChangelogPage() {
    final current =
        _changelogHistory.isNotEmpty ? _changelogHistory.first : null;
    final history = _changelogHistory.length > 1
        ? _changelogHistory.sublist(1)
        : <ChangelogEntry>[];
    final scheme = Theme.of(context).colorScheme;

    return _buildPageContainer(
        content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Row(children: [
            Icon(Icons.system_update_rounded, size: 28, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _loadingChangelog ? '版本更新 (Loading)' : 'v$_currentVersion 更新日志',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (_changelogNotice != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi_off, size: 16, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _changelogNotice!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        // 当前版本
        Container(
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
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('v${current?.versionName ?? _currentVersion}',
                      style: TextStyle(
                          color: scheme.onPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('NEW',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                if (current?.date.isNotEmpty == true)
                  Text(current!.date,
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.45))),
              ]),
              const SizedBox(height: 14),
              if (_loadingChangelog)
                const Center(child: CircularProgressIndicator(strokeWidth: 2))
              else if (current == null || current.items.isEmpty)
                Text('请联网后查看详细更新内容。',
                    style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.6)))
              else
                ...current.items.map((item) => _buildBulletItem(item, scheme)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 历史版本
        if (history.isNotEmpty) ...[
          Row(children: [
            Icon(Icons.history_rounded,
                size: 16, color: scheme.onSurface.withValues(alpha: 0.45)),
            const SizedBox(width: 6),
            Text('历史版本',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.45))),
          ]),
          const SizedBox(height: 8),
          ...history.map((e) => _buildHistoryVersionTile(e)),
        ],
      ],
    ));
  }

  Widget _buildBulletItem(String item, ColorScheme scheme,
      {double textAlpha = 0.75, double fontSize = 13.5}) {
    Color dotColor = scheme.onSurface.withValues(alpha: 0.4);
    if (item.startsWith('【新增】'))
      dotColor = Colors.green;
    else if (item.startsWith('【优化】'))
      dotColor = Colors.blue;
    else if (item.startsWith('【修复】'))
      dotColor = Colors.orange;
    else if (item.startsWith('【重构】'))
      dotColor = Colors.purple;
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
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(item,
                  style: TextStyle(
                      fontSize: fontSize,
                      color: scheme.onSurface.withValues(alpha: textAlpha),
                      height: 1.45))),
        ],
      ),
    );
  }

  Widget _buildHistoryVersionTile(ChangelogEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final isExpanded = _expandedVersions.contains(entry.versionName);
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isExpanded)
              _expandedVersions.remove(entry.versionName);
            else
              _expandedVersions.add(entry.versionName);
          }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Text('v${entry.versionName}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.75))),
              const SizedBox(width: 8),
              if (entry.date.isNotEmpty)
                Text(entry.date,
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.4))),
              const Spacer(),
              if (!isExpanded && entry.items.isNotEmpty)
                Flexible(
                    child: Text(entry.items.first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withValues(alpha: 0.35)))),
              const SizedBox(width: 4),
              Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.4)),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 2, bottom: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12)),
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

  // ── Android 特性及权限引导 ───────────────────────────────

  Widget _buildAndroidFeaturePage1() {
    return _buildPageContainer(
        content: Column(
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.bar_chart_outlined,
          iconColor: Colors.purple,
          title: '屏幕时间统计与时间全览',
          subtitle: '全天候统计你的手机使用情况，智能合并番茄钟与各 App 的使用时长，生成一目了然的时间网格。',
        ),
        _buildMediaAsset('assets/guide_media/android_lock_screen.png',
            fit: BoxFit.contain),
        const SizedBox(height: 24),
        _buildPermissionTile(
          title: '应用使用情况权限',
          subtitle: '用于记录你使用了哪些应用以进行时间分配分析',
          isGranted: _hasUsageStats,
          onRequest: () async {
            await screenTimeChannel.invokeMethod('openUsageSettings');
            await Future.delayed(const Duration(milliseconds: 500));
            _checkPermissions();
          },
        ),
      ],
    ));
  }

  Widget _buildAndroidFeaturePage2() {
    return _buildPageContainer(
        content: Column(
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.notifications_active_outlined,
          iconColor: Colors.blue,
          title: '精确保活的通知唤醒',
          subtitle: '不论是日程、倒计时、还是番茄钟，我们确保即使应用在后台，也会准时向您推送提醒。',
        ),
        _buildMediaAsset('assets/guide_media/android_notification.png',
            fit: BoxFit.contain),
        const SizedBox(height: 24),
        _buildPermissionTile(
          title: '通知权限',
          subtitle: '核心功能：用于提醒代办与专属通知栏状态',
          isGranted: _notificationStatus?.isGranted == true,
          onRequest: () async {
            await Permission.notification.request();
            _checkPermissions();
          },
        ),
        const SizedBox(height: 12),
        _buildPermissionTile(
          title: '精确闹钟权限',
          subtitle: '用于应用在指定秒数准时唤醒推送（如倒数结束）',
          isGranted: _hasExactAlarm,
          onRequest: () async {
            await platform.invokeMethod('openExactAlarmSettings');
            await Future.delayed(const Duration(milliseconds: 500));
            _checkPermissions();
          },
        ),
      ],
    ));
  }

  Widget _buildAndroidFeaturePage3() {
    return _buildPageContainer(
        content: Column(
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.battery_charging_full_outlined,
          iconColor: Colors.orange,
          title: '番茄钟与后台长驻',
          subtitle: '为了体验完美的番茄钟跨端同步（WebSocket）与避免锁屏后被系统盲目杀后台，我们需要调整电池优化。',
        ),
        _buildMediaAsset('assets/guide_media/android_return_desktop.mp4'),
        const SizedBox(height: 24),
        _buildPermissionTile(
          title: '忽略电池优化',
          subtitle: '提升进程优先级，避免长时间锁屏专注时被误杀',
          isGranted: _ignoringBatteryOptimizations,
          onRequest: () async {
            await platform.invokeMethod('openBatteryOptimizationSettings');
            await Future.delayed(const Duration(milliseconds: 500));
            _checkPermissions();
          },
          optional: true,
        ),
      ],
    ));
  }

  // ── 新增：Android 桌面小部件引导 ──────────────────────────

  Widget _buildAndroidWidgetGuidePage() {
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
        content: Column(
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.widgets_outlined,
          iconColor: Colors.indigo,
          title: '桌面小部件',
          subtitle: '无需打开应用，直接在桌面查看今日课程、待办任务与番茄钟状态。',
        ),
        _buildMediaAsset('assets/guide_media/android_widget_guide.mp4'),
        const SizedBox(height: 20),

        // 🚀 一键添加到桌面按钮 (Android 8.0+)
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              try {
                // 调用 MethodChannel (对应 MainActivity.kt 中的 requestPinWidget)
                final result = await platform.invokeMethod('requestPinWidget');
                if (result == false && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('您的系统/启动器不支持一键添加，请按下方步骤手动添加')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('自动添加失败，请手动添加')),
                  );
                }
              }
            },
            icon: const Icon(Icons.add_to_home_screen_rounded),
            label: const Text('一键添加到桌面',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 手动步骤说明卡片
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.indigo.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.touch_app_outlined,
                    size: 16, color: Colors.indigo.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
                Text('若一键添加失败，可手动添加',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.7))),
              ]),
              const SizedBox(height: 12),
              _buildWidgetStep(
                  '1', '长按手机桌面空白处', Icons.touch_app_rounded, Colors.indigo),
              const SizedBox(height: 8),
              _buildWidgetStep('2', '点击「小部件」或「Widget」选项',
                  Icons.grid_view_rounded, Colors.indigo),
              const SizedBox(height: 8),
              _buildWidgetStep(
                  '3', '找到本应用，选择想要的小部件样式', Icons.search_rounded, Colors.indigo),
              const SizedBox(height: 8),
              _buildWidgetStep('4', '拖拽到合适位置，松手即完成添加', Icons.open_with_rounded,
                  Colors.indigo),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 提示条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: Colors.indigo.withValues(alpha: 0.75)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '部分国产 ROM（如 MIUI、ColorOS）需在「负一屏」或「桌面设置」中单独开启小部件功能。',
                  style: TextStyle(fontSize: 12, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    ));
  }

  /// 桌面小部件引导的单步骤行
  Widget _buildWidgetStep(
      String stepNum, String desc, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(stepNum,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color.withValues(alpha: 0.9))),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 16, color: color.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(desc,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.75))),
        ),
      ],
    );
  }

  // ── Windows 特性及配置引导 ──────────────────────────────

  Widget _buildWinFeaturePage1() {
    return _buildPageContainer(
        content: Column(children: [
      const SizedBox(height: 16),
      _buildStepHeader(
        icon: Icons.timer_outlined,
        iconColor: Colors.redAccent,
        title: '全端番茄钟与大屏专注',
        subtitle: '在 Windows 桌面端享受沉浸式或浮窗式的番茄钟体验。而且，现在支持跨屏自动无缝流转同步！',
      ),
      _buildMediaAsset('assets/guide_media/windows_pomodoro.mp4'),
    ]));
  }

  Widget _buildWinFeaturePage2() {
    return _buildPageContainer(
        content: Column(children: [
      const SizedBox(height: 16),
      _buildStepHeader(
        icon: Icons.web_asset_rounded,
        iconColor: Colors.blueAccent,
        title: '无缝接入 Windows 屏幕时间',
        subtitle: '利用本地读取 Tai 软件（专业 Windows 时间追踪应用）的数据库，轻松在应用内部汇总双端时长。',
      ),
      _buildMediaAsset('assets/guide_media/windows_screen_time.mp4'),
    ]));
  }

  Widget _buildTaiSetupPage() {
    return _buildPageContainer(
        content: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.folder_special_outlined,
          iconColor: Colors.teal,
          title: '配置 Tai 数据库路径',
          subtitle: '如果要启用 Windows 的时常追踪聚合（可选），请指定已安装的 Tai 软件数据文件路径 (data.db)。',
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当数据库文件路径:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                _taiDbPath.isNotEmpty ? _taiDbPath : '未设置，功能无法生效',
                style: TextStyle(
                    color: _taiDbPath.isNotEmpty ? Colors.blue : Colors.red,
                    fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('手动选择 data.db 文件'),
                  onPressed: () async {
                    FilePickerResult? result =
                        await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['db'],
                      dialogTitle: '选择 Tai 的 data.db 文件',
                    );
                    if (result != null && result.files.single.path != null) {
                      String path = result.files.single.path!;
                      bool isValid = await TaiService.validateDb(path);
                      if (isValid) {
                        await TaiService.saveDbPath(path);
                        setState(() => _taiDbPath = path);
                      } else {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('⚠️ 选定的文件无效Tai数据库')));
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  icon: const Icon(Icons.flash_auto),
                  label: const Text('尝试自动检测默认安装路径'),
                  onPressed: () async {
                    final path = await TaiService.detectDefaultPath();
                    if (path != null) {
                      await TaiService.saveDbPath(path);
                      setState(() => _taiDbPath = path);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ 自动检测并绑定成功！')));
                    } else {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('⚠️ 未能找到默认路径，请确认是否安装或手动选择。')));
                    }
                  },
                ),
              ),
            ],
          ),
        )
      ],
    ));
  }

  // ── 全局通用配置引导 ──────────────────────────────

  Widget _buildGlobalCourseSetupPage() {
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
        content: Column(
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.calendar_month_outlined,
          iconColor: Colors.teal,
          title: '课表导入与学期同步',
          subtitle:
              '全平台均支持智能课表解析。你可以在首页设置中导入本地课表，或直接从云端同步。\n设置开学与放假日期，以开启学期进度条。',
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 1,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.linear_scale),
                title: const Text('首页学期进度条', style: TextStyle(fontSize: 14)),
                value: _semesterEnabled,
                onChanged: (val) {
                  setState(() => _semesterEnabled = val);
                  StorageService.saveAppSetting(
                      StorageService.KEY_SEMESTER_PROGRESS_ENABLED, val);
                },
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: const Text('开学日期', style: TextStyle(fontSize: 14)),
                trailing: Text(_semesterStart == null
                    ? "未设置"
                    : DateFormat('yyyy-MM-dd').format(_semesterStart!)),
                onTap: () => _pickSemesterDate(true),
              ),
              ListTile(
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: const Text('放假日期', style: TextStyle(fontSize: 14)),
                trailing: Text(_semesterEnd == null
                    ? "未设置"
                    : DateFormat('yyyy-MM-dd').format(_semesterEnd!)),
                onTap: () => _pickSemesterDate(false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withOpacity(0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '提示：进入应用后，请前往 设置 > 课程设置 导入或同步您的课表！',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    ));
  }

  Future<void> _pickSemesterDate(bool isStart) async {
    final DateTime initDate = isStart
        ? (_semesterStart ?? DateTime.now())
        : (_semesterEnd ?? DateTime.now().add(const Duration(days: 120)));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      if (!mounted) return;
      setState(() {
        if (isStart)
          _semesterStart = picked;
        else
          _semesterEnd = picked;
      });
      final prefs = await SharedPreferences.getInstance();
      if (isStart)
        await prefs.setString(
            StorageService.KEY_SEMESTER_START, picked.toIso8601String());
      else
        await prefs.setString(
            StorageService.KEY_SEMESTER_END, picked.toIso8601String());
    }
  }

  Widget _buildGlobalThemeSetupPage() {
    return _buildPageContainer(
        content: Column(
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.palette_outlined,
          iconColor: Colors.deepPurple,
          title: '个性化：模块排序与深色模式',
          subtitle:
              '你可以自由决定首页上哪个模块显示在最上面。进入设置找到 "模块管理" 即可自由拖拽模块进行排序。\n开启深色模式让你在夜晚操作更舒适。',
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 1,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('深色模式/主题', style: TextStyle(fontSize: 14)),
            trailing: DropdownButton<String>(
              value: _themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                DropdownMenuItem(value: 'light', child: Text('浅色')),
                DropdownMenuItem(value: 'dark', child: Text('深色')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _themeMode = val);
                  StorageService.saveAppSetting(
                      StorageService.KEY_THEME_MODE, val);
                  StorageService.themeNotifier.value = val;
                }
              },
            ),
          ),
        ),
      ],
    ));
  }

  // ── 辅助 UI 工具 ────────────────────────────────────────

  // ── 页面: Uni-Sync 4.0 迁移引导 (独立定义) ──────────────────

  Widget _buildUniSyncMigrationPage() {
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 24),
          _buildStepHeader(
            icon: Icons.storage_rounded,
            iconColor: Colors.teal,
            title: 'Uni-Sync 4.0 存储主权',
            subtitle: '您的数据已平稳降落。我们已完成从传统 JSON 向工业级 SQLite 存储引擎的跨代迁移。',
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
            ),
            child: const Column(
              children: [
                Icon(Icons.verified_user_rounded, color: Colors.teal, size: 48),
                SizedBox(height: 16),
                Text("本地数据迁移完成", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
                SizedBox(height: 8),
                Text("单一事实来源 (SSoT) 架构已激活", style: TextStyle(fontSize: 12, color: Colors.teal)),
              ],
            ),
          ),
          const SizedBox(height: 40),
          _buildMigrationPoint(Icons.bolt_rounded, "极致搜索性能", "基于 FTS5 全文索引，即便万条待办，检索只需毫秒。"),
          const SizedBox(height: 20),
          _buildMigrationPoint(Icons.offline_pin_rounded, "离线操作拦截", "内置 Oplog 离线记录仪，断网改动自动入库，联网秒速对齐。"),
          const SizedBox(height: 20),
          _buildMigrationPoint(Icons.security_rounded, "核心数据双活", "本地 SQL 与 Prefs 互为备份，最大限度抵御外部文件损毁风险。"),
        ],
      ),
    );
  }

  Widget _buildMigrationPoint(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.teal, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onRequest,
    bool optional = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isGranted
            ? Colors.green.withValues(alpha: 0.1)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isGranted
                ? Colors.green.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if (optional) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('强烈推荐',
                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                      )
                    ]
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7))),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (isGranted)
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                SizedBox(width: 4),
                Text('已授权',
                    style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            )
          else
            FilledButton.tonal(
              onPressed: onRequest,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('去开启'),
            )
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    // 🚀 当只有一页时，直接隐藏页面指示器
    if (_pagesBuilder.length <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pagesBuilder.length, (i) {
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

  // ── 布局搭建 ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        itemCount: _pagesBuilder.length,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemBuilder: (ctx, i) {
          return _pagesBuilder[i]();
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPageIndicator(),
              if (_pagesBuilder.length > 1) const SizedBox(height: 16),
              Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: OutlinedButton(
                          onPressed: _previousPage,
                          style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16)),
                          child: const Text('上一页'),
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _currentPage == _pagesBuilder.length - 1
                          ? _done
                          : _nextPage,
                      icon: Icon(_currentPage == _pagesBuilder.length - 1
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded),
                      // 🚀 动态判断按钮文字，只有一页时直接显示 "完成体验"
                      label: Text(_currentPage == _pagesBuilder.length - 1
                          ? '完成体验'
                          : '继续探索'),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
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

class AssetVideoPlayer extends StatefulWidget {
  final String assetPath;

  const AssetVideoPlayer({super.key, required this.assetPath});

  @override
  State<AssetVideoPlayer> createState() => _AssetVideoPlayerState();
}

class _AssetVideoPlayerState extends State<AssetVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.assetPath)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _initialized = true;
          });
          _controller.setLooping(true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized) {
      return AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      );
    } else {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
  }
}
