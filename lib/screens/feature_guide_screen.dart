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
  static const platform =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');
  static const screenTimeChannel =
      MethodChannel('com.math_quiz_app/screen_time');

  // 从远端加载的数据
  String _currentVersion = '';
  List<ChangelogEntry> _changelogHistory = [];
  bool _loadingChangelog = true;
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
    _loadInfo();
    _checkPermissions();
    _loadGlobalSettings();
    if (Platform.isWindows) {
      _pagesBuilder = [
        _buildChangelogPage,
        _buildWinFeaturePage1,
        _buildWinFeaturePage2,
        _buildTaiSetupPage,
        _buildGlobalCourseSetupPage,
        _buildGlobalThemeSetupPage,
      ];
      _loadTaiConfig();
    } else {
      _pagesBuilder = [
        _buildChangelogPage,
        _buildAndroidFeaturePage1,
        _buildAndroidFeaturePage2,
        _buildAndroidFeaturePage3,
        _buildGlobalCourseSetupPage,
        _buildGlobalThemeSetupPage,
      ];
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

    try {
      final manifest = await UpdateService.checkManifest();
      if (manifest != null && mounted) {
        setState(() {
          _changelogHistory = manifest.changelogHistory;
          _loadingChangelog = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _changelogHistory = [];
        _loadingChangelog = false;
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

    if (widget.isManualReview) {
      Navigator.pop(context);
    } else {
      final username = widget.loggedInUser;
      final dest = (username != null && username.isNotEmpty)
          ? HomeDashboard(username: username)
          : const LoginScreen();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => dest),
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
            fit: BoxFit.contain), // 暂时用课程图片代替占位
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
              const SizedBox(height: 16),
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
        // Ensure the first frame is shown after the video is initialized
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
