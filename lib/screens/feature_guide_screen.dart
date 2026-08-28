import 'dart:async';
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
import '../utils/app_platform.dart';
import '../utils/page_transitions.dart';
import 'course_screens.dart';
import 'personal_timeline_screen.dart';
import '../widgets/global_search_overlay.dart';
import 'settings/pages/preference_settings_page.dart';
import '../services/course_service.dart';
import '../services/permission_request_coordinator.dart';
import '../services/minor_mode_service.dart';
import '../services/liquid_glass_effect_service.dart';
import '../models/minor_mode_state.dart';
import '../models.dart';
import '../features/habits/screens/habit_center_screen.dart';
import '../features/thirty_day_challenge/screens/thirty_day_challenge_screen.dart';
import '../widgets/app_settings_widgets.dart';
import '../widgets/floating_bottom_bar.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import 'animation_settings_page.dart';

/// 控制功能页的入口展示范围。
enum FeatureGuideMode {
  automatic,
  changelog,
  guide,
}

/// 首次安装或重大版本升级引导页 (v1.9.4+)
class FeatureGuideScreen extends StatefulWidget {
  final String? loggedInUser;
  final FeatureGuideMode mode;
  // 保留旧参数，避免其它入口在迁移期间改变自动启动行为。
  final bool isManualReview;
  final bool isEmbedded;

  const FeatureGuideScreen({
    super.key,
    this.loggedInUser,
    this.mode = FeatureGuideMode.automatic,
    this.isManualReview = false,
    this.isEmbedded = false,
  });

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
  bool get _isManualReview =>
      widget.isManualReview || widget.mode != FeatureGuideMode.automatic;
  bool get _isChangelogOnly => widget.mode == FeatureGuideMode.changelog;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  // 标记是否为首次安装（用于决定引导结束后是否设置默认服务器）
  bool _isFirstLaunch = false;
  static const platform =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');
  static const screenTimeChannel =
      MethodChannel('com.math_quiz_app/screen_time');
  late final PermissionRequestCoordinator _permissionCoordinator;

  // 从远端加载的数据
  String _currentVersion = '';
  String _previousShownVersion = '';
  List<ChangelogEntry> _changelogHistory = [];
  bool _loadingChangelog = true;
  bool _changelogFetchFailed = false; // 🚀 区分"无网络"和"本版本无更新日志"
  String? _changelogNotice;
  final Set<String> _expandedVersions = {};

  // 🚀 最近更新功能数据 —— 每次发版只改这里
  List<_RecentFeature> get _recentFeatures {
    final scheme = Theme.of(context).colorScheme;
    if (AppPlatform.isWeb) {
      return [
        _RecentFeature(
          Icons.blur_on_rounded,
          scheme.primary,
          'Liquid Glass 视觉升级',
          '设置->动画设置->Liquid Glass',
          destinationBuilder: () => const AnimationSettingsPage(),
        ),
        _RecentFeature(
          Icons.animation_rounded,
          scheme.secondary,
          '动效性能与速度预设',
          '设置->动画设置->性能预设 / 动画速度',
          destinationBuilder: () => const AnimationSettingsPage(),
        ),
        _RecentFeature(
          Icons.auto_awesome_rounded,
          scheme.primary,
          '30天找到全新自我',
          '设置->帮助与反馈->30天找到全新自我',
          destinationBuilder: () => const ThirtyDayChallengeScreen(),
        ),
        _RecentFeature(
          Icons.track_changes_rounded,
          scheme.tertiary,
          '习惯中心',
          '打卡·历史·统计·归档·同步',
          destinationBuilder: () =>
              HabitCenterScreen(username: widget.loggedInUser ?? ''),
        ),
        _RecentFeature(
          Icons.install_desktop_rounded,
          scheme.primary,
          'PWA 网页应用',
          '浏览器->安装应用',
        ),
        _RecentFeature(
          Icons.view_week_rounded,
          scheme.secondary,
          '周视图午休折叠',
          '课程->周视图',
          destinationBuilder: () =>
              WeeklyCourseScreen(username: widget.loggedInUser ?? ''),
        ),
        _RecentFeature(
          Icons.timeline_rounded,
          scheme.tertiary,
          '个人时间轴报表',
          '专注->个人时间轴',
          destinationBuilder: () =>
              PersonalTimelineScreen(username: widget.loggedInUser ?? ''),
        ),
        _RecentFeature(
          Icons.search_rounded,
          Colors.teal,
          '全局搜索',
          '首页->右上角搜索',
          destinationBuilder: () => const GlobalSearchOverlay(),
        ),
      ];
    }

    return [
      _RecentFeature(
        Icons.blur_on_rounded,
        scheme.primary,
        'Liquid Glass 视觉升级',
        '设置->动画设置->Liquid Glass',
        destinationBuilder: () => const AnimationSettingsPage(),
      ),
      _RecentFeature(
        Icons.animation_rounded,
        scheme.secondary,
        '动效性能与速度预设',
        '设置->动画设置->性能预设 / 动画速度',
        destinationBuilder: () => const AnimationSettingsPage(),
      ),
      _RecentFeature(
        Icons.auto_awesome_rounded,
        scheme.primary,
        '30天找到全新自我',
        '设置->帮助与反馈->30天找到全新自我',
        destinationBuilder: () => const ThirtyDayChallengeScreen(),
      ),
      _RecentFeature(
        Icons.track_changes_rounded,
        scheme.tertiary,
        '习惯中心',
        '打卡·历史·统计·归档·同步',
        destinationBuilder: () =>
            HabitCenterScreen(username: widget.loggedInUser ?? ''),
      ),
      _RecentFeature(
        Icons.view_week_rounded,
        scheme.primary,
        '周视图午休折叠',
        '课程->周视图',
        destinationBuilder: () =>
            WeeklyCourseScreen(username: widget.loggedInUser ?? ''),
      ),
      _RecentFeature(
        Icons.format_paint_rounded,
        Colors.indigo,
        '全局动态主题色彩',
        '设置->偏好设置',
        destinationBuilder: () =>
            const PreferenceSettingsPage(initialTarget: 'theme_color'),
      ),
      _RecentFeature(
        Icons.timeline_rounded,
        Colors.purple,
        '个人时间轴报表',
        '专注->个人时间轴',
        destinationBuilder: () =>
            PersonalTimelineScreen(username: widget.loggedInUser ?? ''),
      ),
      _RecentFeature(
        Icons.search_rounded,
        Colors.teal,
        '全局搜索',
        '首页->右上角搜索',
        destinationBuilder: () => const GlobalSearchOverlay(),
      ),
    ];
  }

  // 权限状态
  PermissionStatus? _notificationStatus;
  bool _hasUsageStats = false;
  bool _hasExactAlarm = false;
  bool _ignoringBatteryOptimizations = false;
  bool _showDatabaseUpdatePage = false;
  DateTime? _minorBirthDate;
  bool _minorBirthDateSaving = false;

  // Tai目录
  String _taiDbPath = '';

  // 全局设置状态
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  /// 液态玻璃选项是否已向该用户展示过（展示一次后不再重复）。
  bool _guideOffered = false;

  /// 本次引导是否包含外观设置页（用于完成时写入已展示标记）。
  bool _themeSetupPageIncluded = false;

  // 云端数据
  bool _checkingCloudData = false;
  bool _hasCloudCourses = false;
  bool _hasCloudSemester = false;
  List<CourseItem>? _cloudCourses;
  DateTime? _cloudSemesterStart;
  DateTime? _cloudSemesterEnd;
  bool _importingCourses = false;
  bool _importingSemester = false;

  late List<Widget Function()> _pagesBuilder;
  Future<void>? _guideConfigurationFuture;

  @override
  void initState() {
    super.initState();
    _permissionCoordinator = PermissionRequestCoordinator(
      context: context,
      platformChannel: platform,
      onResult: (_) => _checkPermissions(),
    );
    _guideConfigurationFuture = _loadGuideConfiguration();

    if (_isManualReview) {
      // 手动查看：直接同步设置页面，跳过自动启动逻辑。
      _isFirstLaunch = false;
      _pagesBuilder = _isChangelogOnly
          ? [_buildChangelogPage]
          : [_buildChangelogPage, ..._buildPlatformGuidePages()];
      _loadInfo();
    } else {
      // 默认只放第一页（更新日志），防止异步加载前数组越界
      _pagesBuilder = [_buildChangelogPage];
      _loadInfo();
      _setupPages();
    }
  }

  Future<void> _loadGuideConfiguration() async {
    final tasks = <Future<void>>[
      _checkPermissions(),
      _loadGlobalSettings(),
      _loadLiquidGlassState(),
      _loadMinorModeGuideState(),
    ];
    if (AppPlatform.isWindows) tasks.add(_loadTaiConfig());
    await Future.wait<void>(tasks);
  }

  Future<void> _loadLiquidGlassState() async {
    final offered = await LiquidGlassEffectService.isGuideOfferDone();
    if (mounted) setState(() => _guideOffered = offered);
  }

  Future<void> _setupPages() async {
    await _guideConfigurationFuture;
    final prefs = await SharedPreferences.getInstance();
    final shownVersion = prefs.getString(FeatureGuideScreen._guideKey);

    // 如果之前没有记录过版本号，则是首次安装。
    final isFirstLaunch = shownVersion == null || shownVersion.isEmpty;
    // 保存到 state，供 _done 使用
    _isFirstLaunch = isFirstLaunch;

    List<Widget Function()> pages = [];

    // 无论如何，第一页永远是更新日志
    pages.add(_buildChangelogPage);

    // 仅自动升级流程在本次版本范围内确实包含数据库/存储迁移相关变更时展示。
    if (!isFirstLaunch && !_isManualReview && _showDatabaseUpdatePage) {
      pages.add(_buildUniSyncMigrationPage);
    }

    final onlyUnconfigured = !isFirstLaunch && !_isManualReview;
    final platformGuidePages = _buildPlatformGuidePages(
      onlyUnconfigured: onlyUnconfigured,
    );
    final shouldShowGuide = widget.mode == FeatureGuideMode.guide ||
        (widget.mode == FeatureGuideMode.automatic &&
            (isFirstLaunch ||
                widget.isManualReview ||
                platformGuidePages.isNotEmpty));
    if (shouldShowGuide) {
      pages.addAll(platformGuidePages);
    }

    // 记录本次引导是否包含外观设置页：用户正常完成引导时写入
    // "已展示"标记，之后不再重复展示（用户可能不想要，不能反复打扰）。
    _themeSetupPageIncluded =
        shouldShowGuide && pages.contains(_buildGlobalThemeSetupPage);

    if (mounted) {
      setState(() {
        _pagesBuilder = pages;
      });
    }
  }

  List<Widget Function()> _buildPlatformGuidePages({
    bool onlyUnconfigured = false,
  }) {
    if (AppPlatform.isWeb) {
      if (!onlyUnconfigured) {
        return [
          _buildWebFeaturePage,
          _buildWebCapabilityPage,
          _buildGlobalCourseSetupPage,
          _buildGlobalThemeSetupPage,
        ];
      }
      return [
        if (!_semesterEnabled) _buildGlobalCourseSetupPage,
        // 未开启过液态玻璃的老用户，升级引导中也给出外观选择。
        if (!_guideOffered) _buildGlobalThemeSetupPage,
      ];
    }
    if (AppPlatform.isWindows) {
      if (!onlyUnconfigured) {
        return [
          _buildWinFeaturePage1,
          _buildWinFeaturePage2,
          _buildTaiSetupPage,
          _buildGlobalCourseSetupPage,
          _buildGlobalThemeSetupPage,
        ];
      }
      return [
        if (_taiDbPath.isEmpty) _buildTaiSetupPage,
        if (!_semesterEnabled) _buildGlobalCourseSetupPage,
        if (!_guideOffered) _buildGlobalThemeSetupPage,
      ];
    }
    if (!onlyUnconfigured) {
      return [
        _buildAndroidFeaturePage1,
        _buildAndroidFeaturePage2,
        _buildAndroidFeaturePage3,
        _buildAndroidWidgetGuidePage,
        _buildMinorModeGuidePage,
        _buildGlobalCourseSetupPage,
        _buildGlobalThemeSetupPage,
      ];
    }

    return [
      if (!_hasUsageStats) _buildAndroidFeaturePage1,
      if (_notificationStatus?.isGranted != true || !_hasExactAlarm)
        _buildAndroidFeaturePage2,
      if (!_ignoringBatteryOptimizations) _buildAndroidFeaturePage3,
      if (!_minorModeGuideConfigured) _buildMinorModeGuidePage,
      if (!_semesterEnabled) _buildGlobalCourseSetupPage,
      if (!_guideOffered) _buildGlobalThemeSetupPage,
    ];
  }

  bool get _minorModeGuideConfigured {
    final service = MinorModeService.instance;
    return service.policyState.systemEnabled || service.manualBirthDate != null;
  }

  Future<void> _loadGlobalSettings() async {
    final start = await StorageService.getSemesterStart();
    final end = await StorageService.getSemesterEnd();
    final enabled = await StorageService.getSemesterEnabled();
    if (mounted) {
      setState(() {
        _semesterStart = start;
        _semesterEnd = end;
        _semesterEnabled = enabled;
      });
    }
    unawaited(_checkCloudData());
  }

  Future<void> _checkCloudData() async {
    if (widget.loggedInUser == null || widget.loggedInUser!.isEmpty) return;
    if (mounted) setState(() => _checkingCloudData = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('current_user_id') ?? 0;
    if (userId == 0) {
      if (mounted) setState(() => _checkingCloudData = false);
      return;
    }

    final results = await Future.wait([
      ApiService.fetchCourses(userId),
      ApiService.fetchUserSettings(),
    ]).timeout(const Duration(seconds: 5), onTimeout: () => [null, null]);

    final cloudCoursesRaw = results[0] as List<dynamic>?;
    final cloudSettings = results[1] as Map<String, dynamic>?;

    List<CourseItem>? courses;
    if (cloudCoursesRaw != null && cloudCoursesRaw.isNotEmpty) {
      courses = cloudCoursesRaw
          .map((e) => CourseItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    DateTime? semStart;
    DateTime? semEnd;
    if (cloudSettings != null) {
      if (cloudSettings['semester_start'] != null) {
        semStart = DateTime.fromMillisecondsSinceEpoch(
            (cloudSettings['semester_start'] as num).toInt());
      }
      if (cloudSettings['semester_end'] != null) {
        semEnd = DateTime.fromMillisecondsSinceEpoch(
            (cloudSettings['semester_end'] as num).toInt());
      }
    }

    if (mounted) {
      setState(() {
        _checkingCloudData = false;
        _hasCloudCourses = courses != null && courses.isNotEmpty;
        _cloudCourses = courses;
        _hasCloudSemester = semStart != null && semEnd != null;
        _cloudSemesterStart = semStart;
        _cloudSemesterEnd = semEnd;
      });
    }
  }

  Future<void> _importCloudCourses() async {
    if (_cloudCourses == null || _cloudCourses!.isEmpty) return;
    setState(() => _importingCourses = true);
    try {
      await CourseService.saveCourses(widget.loggedInUser!, _cloudCourses!);
      if (mounted) {
        setState(() => _hasCloudCourses = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('课表已从云端导入成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importingCourses = false);
    }
  }

  Future<void> _importCloudSemester() async {
    if (_cloudSemesterStart == null || _cloudSemesterEnd == null) return;
    setState(() => _importingSemester = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(StorageService.keySemesterStart,
          _cloudSemesterStart!.toIso8601String());
      await prefs.setString(
          StorageService.keySemesterEnd, _cloudSemesterEnd!.toIso8601String());
      if (mounted) {
        setState(() {
          _semesterStart = _cloudSemesterStart;
          _semesterEnd = _cloudSemesterEnd;
          _hasCloudSemester = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('开学/放假时间已从云端同步'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importingSemester = false);
    }
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;

    final prefs = await SharedPreferences.getInstance();
    final shownVersion = prefs.getString(FeatureGuideScreen._guideKey) ?? '';
    _previousShownVersion = shownVersion;
    // 仅在“更新后的第一次开屏”时优先联网，避免看到旧缓存更新日志。
    final isFirstSplashAfterUpdate =
        shownVersion.isNotEmpty && shownVersion != _currentVersion;

    try {
      final manifest = await UpdateService.checkManifest(
        preferCache: !isFirstSplashAfterUpdate,
        refreshInBackground: !isFirstSplashAfterUpdate,
      );
      if (manifest != null && mounted) {
        final changelogHistory = await _resolveChangelogHistoryForGuide(
          manifest,
          shownVersion,
          preferArchiveCache: !isFirstSplashAfterUpdate,
        );
        final showDatabaseUpdatePage =
            _shouldShowDatabaseUpdatePage(changelogHistory);
        setState(() {
          _changelogHistory = changelogHistory;
          _showDatabaseUpdatePage = showDatabaseUpdatePage;
          _loadingChangelog = false;
          _changelogNotice = null;
        });
        if (!_isManualReview) await _setupPages();
        return;
      }

      // 更新后首次开屏若联网失败，立即回退到离线缓存并给出提示。
      if (isFirstSplashAfterUpdate) {
        final cachedManifest = await UpdateService.checkManifest(
          preferCache: true,
          refreshInBackground: true,
        );
        if (cachedManifest != null && mounted) {
          final changelogHistory = await _resolveChangelogHistoryForGuide(
            cachedManifest,
            shownVersion,
            preferArchiveCache: true,
          );
          final showDatabaseUpdatePage =
              _shouldShowDatabaseUpdatePage(changelogHistory);
          setState(() {
            _changelogHistory = changelogHistory;
            _showDatabaseUpdatePage = showDatabaseUpdatePage;
            _loadingChangelog = false;
            _changelogNotice = '当前显示离线缓存更新日志，网络恢复后会自动刷新。';
          });
          if (!_isManualReview) await _setupPages();
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _changelogHistory = [];
        _showDatabaseUpdatePage = false;
        _loadingChangelog = false;
        _changelogFetchFailed = true; // 🚀 标记为获取失败（通常是无网络）
        _changelogNotice = null;
      });
      if (!_isManualReview) await _setupPages();
    }
  }

  Future<List<ChangelogEntry>> _resolveChangelogHistoryForGuide(
    AppManifest manifest,
    String previousVersion, {
    required bool preferArchiveCache,
  }) async {
    final currentVersion = _normalizeVersion(_currentVersion);
    final previous = _normalizeVersion(previousVersion);
    final hasPrevious = previous.isNotEmpty;
    final isDowngrade =
        hasPrevious && _compareVersionNames(previous, currentVersion) > 0;

    final merged = <ChangelogEntry>[];
    final seen = <String>{};
    void addEntries(Iterable<ChangelogEntry> entries) {
      for (final entry in entries) {
        if (entry.versionName.isEmpty) continue;
        if (seen.add(_normalizeVersion(entry.versionName))) {
          merged.add(entry);
        }
      }
    }

    addEntries(manifest.changelogHistory);

    if (hasPrevious && !isDowngrade && manifest.changelogArchive.isAvailable) {
      try {
        final archive = await UpdateService.loadChangelogArchive(
          manifest: manifest,
          preferCache: preferArchiveCache,
        );
        addEntries(archive);
      } catch (_) {}
    }

    merged.sort((a, b) => _compareVersionNames(b.versionName, a.versionName));

    if (!hasPrevious || isDowngrade) {
      return _currentVersionOnly(merged);
    }

    final inRange = merged
        .where((entry) {
          final version = entry.versionName;
          return _compareVersionNames(version, previous) > 0 &&
              _compareVersionNames(version, currentVersion) <= 0;
        })
        .where((entry) => entry.items.isNotEmpty)
        .toList();

    return inRange.isNotEmpty ? inRange : _currentVersionOnly(merged);
  }

  List<ChangelogEntry> _currentVersionOnly(List<ChangelogEntry> entries) {
    final current = _normalizeVersion(_currentVersion);
    final currentEntries = entries
        .where((entry) => _compareVersionNames(entry.versionName, current) == 0)
        .where((entry) => entry.items.isNotEmpty)
        .take(1)
        .toList();
    if (currentEntries.isNotEmpty) return currentEntries;

    // 当前版本未发布更新日志时，展示清单中最近一个有内容的旧版本。
    return entries
        .where((entry) =>
            _compareVersionNames(entry.versionName, current) < 0 &&
            entry.items.isNotEmpty)
        .take(1)
        .toList();
  }

  String _normalizeVersion(String version) =>
      version.trim().split('+').first.split('-').first;

  int _compareVersionNames(String a, String b) {
    final left = _normalizeVersion(a)
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final right = _normalizeVersion(b)
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final maxLength = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < maxLength; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  bool _shouldShowDatabaseUpdatePage(List<ChangelogEntry> entries) {
    const databaseKeywords = [
      '数据库',
      'sqlite',
      'sql',
      '表结构',
      '字段',
      '存储引擎',
      '数据迁移',
      '迁移至',
      'migration',
      'schema',
    ];

    for (final entry in entries) {
      for (final item in entry.items) {
        final lower = item.toLowerCase();
        if (databaseKeywords.any(lower.contains)) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _loadTaiConfig() async {
    final path = await TaiService.getSavedDbPath() ??
        await TaiService.detectDefaultPath();
    if (path != null && mounted) {
      setState(() => _taiDbPath = path);
    }
  }

  Future<void> _checkPermissions() async {
    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) return;

    final notifStatus = await Permission.notification.status;

    bool hasUsage = false;
    bool hasExact = false;
    bool ignoringBattery = false;

    if (AppPlatform.isAndroid) {
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

  Future<void> _loadMinorModeGuideState() async {
    await MinorModeService.instance.initialize();
    final birthDate = MinorModeService.instance.manualBirthDate;
    if (mounted) {
      setState(() => _minorBirthDate = birthDate);
    }
  }

  Future<void> _pickMinorBirthDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final defaultDate = DateTime(today.year - 12, today.month, today.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _minorBirthDate ?? defaultDate,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: '选择出生日期',
      cancelText: '暂不设置',
      confirmText: '确定',
    );
    if (selected == null || !mounted) return;

    setState(() {
      _minorBirthDate = selected;
      _minorBirthDateSaving = true;
    });
    try {
      await MinorModeService.instance.setManualBirthDate(selected);
    } finally {
      if (mounted) setState(() => _minorBirthDateSaving = false);
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
    if (!_isManualReview) {
      await FeatureGuideScreen.markShown();
      // 本次引导包含液态玻璃选项且用户走完了流程 → 记为已展示。
      if (_themeSetupPageIncluded) {
        await LiquidGlassEffectService.markGuideOffered();
      }
    }
    if (!mounted) return;

    // 如果是首次启动并且不是手动查看引导，且将要跳转到登录页，则把默认服务器切换为阿里云
    if (!_isManualReview && _isFirstLaunch) {
      // 只有在未传入已登录用户的情况下我们修改登录页的默认服务器
      final username = widget.loggedInUser;
      if (username == null || username.isEmpty) {
        await StorageService.saveServerChoice('aliyun');
        ApiService.setServerChoice('aliyun');
      }
    }
    if (!mounted) return;

    if (_isManualReview) {
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
    _permissionCoordinator.dispose();
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
          child: assetPath.toLowerCase().endsWith('.mp4') ||
                  assetPath.toLowerCase().endsWith('.webm')
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
    final previous = _normalizeVersion(_previousShownVersion);
    final currentVersion = _normalizeVersion(_currentVersion);
    final displayVersion = current?.versionName ?? currentVersion;
    final showVersionRange = previous.isNotEmpty &&
        _compareVersionNames(previous, currentVersion) < 0 &&
        _changelogHistory.length > 1;

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
                _loadingChangelog ? '版本更新 (Loading)' : 'v$displayVersion 更新日志',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (showVersionRange) ...[
          Text(
            '从 v$previous 升级到 v$currentVersion，以下是本次跨版本变动。',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.65),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
        ],
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
        OptionalLiquidGlassCard(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          borderRadius: 16,
          highContrast: true,
          tint: scheme.primary.withValues(alpha: 0.16),
          fallbackDecoration: BoxDecoration(
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
              else if (_changelogFetchFailed)
                Text('请联网后查看详细更新内容。',
                    style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.6)))
              else if (current == null || current.items.isEmpty)
                Text('本版本暂无更新日志。',
                    style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.6)))
              else
                ...current.items.map((item) => _buildBulletItem(item, scheme)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 🚀 最近更新功能
        _buildRecentFeaturesSection(scheme),
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
    if (item.startsWith('【新增】')) {
      dotColor = Colors.green;
    } else if (item.startsWith('【优化】')) {
      dotColor = Theme.of(context).colorScheme.primary;
    } else if (item.startsWith('【修复】')) {
      dotColor = Colors.orange;
    } else if (item.startsWith('【重构】')) {
      dotColor = Colors.purple;
    } else if (item.startsWith('⚠️')) {
      dotColor = Colors.red;
    }

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
            if (isExpanded) {
              _expandedVersions.remove(entry.versionName);
            } else {
              _expandedVersions.add(entry.versionName);
            }
          }),
          borderRadius: BorderRadius.circular(12),
          child: OptionalLiquidGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            borderRadius: 12,
            highContrast: true,
            fallbackDecoration: BoxDecoration(
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
          secondChild: OptionalLiquidGlassCard(
            margin: const EdgeInsets.only(top: 2, bottom: 4),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            borderRadiusGeometry: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12)),
            highContrast: true,
            fallbackDecoration: BoxDecoration(
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

  Widget _buildRecentFeaturesSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded,
              size: 16, color: scheme.onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: 6),
          Text('最近更新功能',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.45))),
        ]),
        const SizedBox(height: 10),
        Column(
          children: _recentFeatures
              .map((feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildRecentFeatureCard(feature, scheme),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildRecentFeatureCard(_RecentFeature feature, ColorScheme scheme) {
    final canNavigate = !_isFirstLaunch && feature.destinationBuilder != null;
    return InkWell(
      onTap: () {
        if (canNavigate) {
          // 更新后查看：直接跳转
          Navigator.of(context, rootNavigator: true).push(
            PageTransitions.material(
                builder: (_) => feature.destinationBuilder!()),
          );
        } else {
          // 首次使用：仅提示位置
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📍 ${feature.title}：${feature.subtitle}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: OptionalLiquidGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: 14,
        highContrast: true,
        tint: feature.color.withValues(alpha: 0.16),
        fallbackDecoration: BoxDecoration(
          color: feature.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: feature.color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: feature.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(feature.icon, size: 25, color: feature.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feature.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    feature.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '立即体验',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: feature.color,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: feature.color),
          ],
        ),
      ),
    );
  }

  // ── Web 特性及能力取舍 ─────────────────────────────────

  Widget _buildWebFeaturePage() {
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.web_asset_rounded,
            iconColor: scheme.primary,
            title: '网页版 Beta',
            subtitle:
                '无需安装即可在浏览器中使用待办、倒数日、番茄钟、课表和同步。首次加载资源较多，安装为 PWA 后再次打开会更快。',
          ),
          const SizedBox(height: 28),
          _buildWebCapabilityTile(
            icon: Icons.task_alt_rounded,
            title: '核心数据与同步可用',
            subtitle: '待办、倒数日、番茄钟、课表、个人时间轴和云端同步均可在网页端运行。',
            color: scheme.primary,
          ),
          const SizedBox(height: 12),
          _buildWebCapabilityTile(
            icon: Icons.install_desktop_rounded,
            title: '支持 PWA 安装',
            subtitle: '在支持的浏览器中可安装到桌面/启动台，并缓存 Flutter 引擎、字体和离线资源。',
            color: scheme.secondary,
          ),
          const SizedBox(height: 12),
          _buildWebCapabilityTile(
            icon: Icons.folder_open_rounded,
            title: '文件流程改为浏览器模式',
            subtitle: '导入使用浏览器文件选择，导出和壁纸下载会触发浏览器下载。',
            color: scheme.tertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildWebCapabilityPage() {
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
      content: Column(
        children: [
          const SizedBox(height: 16),
          _buildStepHeader(
            icon: Icons.tune_rounded,
            iconColor: scheme.error,
            title: '网页版功能取舍',
            subtitle: '浏览器无法提供完整系统权限，因此部分原生能力会隐藏、降级或改用网页替代方案。',
          ),
          const SizedBox(height: 28),
          _buildWebCapabilityTile(
            icon: Icons.notifications_off_outlined,
            title: '系统级通知与后台保活受限',
            subtitle: '网页端不提供 Android 精确闹钟、电池优化、锁屏常驻通知等系统级引导。',
            color: scheme.error,
            isLimited: true,
          ),
          const SizedBox(height: 12),
          _buildWebCapabilityTile(
            icon: Icons.desktop_windows_outlined,
            title: '桌面原生能力不可用',
            subtitle: 'Windows 悬浮窗、托盘、Island、Tai 数据库读取和系统窗口控制仅在桌面端提供。',
            color: scheme.error,
            isLimited: true,
          ),
          const SizedBox(height: 12),
          _buildWebCapabilityTile(
            icon: Icons.widgets_outlined,
            title: '移动端小组件不可用',
            subtitle: 'Android 桌面小部件、手环同步和原生分享入口不在网页版引导中展示。',
            color: scheme.error,
            isLimited: true,
          ),
        ],
      ),
    );
  }

  Widget _buildWebCapabilityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool isLimited = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return OptionalLiquidGlassCard(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      highContrast: true,
      tint: color.withValues(alpha: 0.16),
      fallbackDecoration: BoxDecoration(
        color: color.withValues(alpha: isLimited ? 0.07 : 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    if (isLimited)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '暂不支持',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.onSurface.withValues(alpha: 0.64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
        _buildMediaAsset('assets/guide_media/android_lock_screen.webp',
            fit: BoxFit.contain),
        const SizedBox(height: 24),
        _buildPermissionTile(
          title: '应用使用情况权限',
          subtitle: '用于记录你使用了哪些应用以进行时间分配分析',
          isGranted: _hasUsageStats,
          onRequest: () async {
            await _permissionCoordinator.request(
              AppPermissionKind.usageStats,
            );
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
          iconColor: Theme.of(context).colorScheme.primary,
          title: '精确保活的通知唤醒',
          subtitle: '不论是日程、倒计时、还是番茄钟，我们确保即使应用在后台，也会准时向您推送提醒。',
        ),
        _buildMediaAsset('assets/guide_media/android_notification.webp',
            fit: BoxFit.contain),
        const SizedBox(height: 24),
        _buildPermissionTile(
          title: '通知权限',
          subtitle: '核心功能：用于提醒代办与专属通知栏状态',
          isGranted: _notificationStatus?.isGranted == true,
          onRequest: () async {
            await _permissionCoordinator.request(
              AppPermissionKind.notification,
            );
          },
        ),
        const SizedBox(height: 12),
        _buildPermissionTile(
          title: '精确闹钟权限',
          subtitle: '用于应用在指定秒数准时唤醒推送（如倒数结束）',
          isGranted: _hasExactAlarm,
          onRequest: () async {
            await _permissionCoordinator.request(
              AppPermissionKind.exactAlarm,
            );
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
        _buildMediaAsset('assets/guide_media/android_return_desktop.webm'),
        const SizedBox(height: 24),
        _buildPermissionTile(
          title: '忽略电池优化',
          subtitle: '提升进程优先级，避免长时间锁屏专注时被误杀',
          isGranted: _ignoringBatteryOptimizations,
          onRequest: () async {
            await _permissionCoordinator.request(
              AppPermissionKind.batteryOptimization,
            );
          },
          optional: true,
        ),
      ],
    ));
  }

  Widget _buildMinorModeGuidePage() {
    final scheme = Theme.of(context).colorScheme;
    final ageBand = _minorBirthDate == null
        ? MinorAgeBand.unknown
        : MinorAgeBandSystemMapping.fromBirthDate(_minorBirthDate!);
    final selectedDateLabel = _minorBirthDate == null
        ? '未设置'
        : '${_minorBirthDate!.year.toString().padLeft(4, '0')}-'
            '${_minorBirthDate!.month.toString().padLeft(2, '0')}-'
            '${_minorBirthDate!.day.toString().padLeft(2, '0')}';

    return ValueListenableBuilder<MinorModeState>(
      valueListenable: MinorModeService.instance.stateNotifier,
      builder: (context, state, _) {
        return _buildPageContainer(
          content: Column(
            children: [
              const SizedBox(height: 16),
              _buildStepHeader(
                icon: Icons.shield_outlined,
                iconColor: scheme.primary,
                title: '未成年人模式',
                subtitle: '选择出生日期，自动匹配适龄保护策略。出生日期仅保存在本机，不会上传。',
              ),
              const SizedBox(height: 24),
              OptionalLiquidGlassCard(
                margin: EdgeInsets.zero,
                borderRadius: 12,
                highContrast: true,
                fallbackDecoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: Icon(
                      state.systemEnabled
                          ? Icons.phonelink_lock_outlined
                          : Icons.cake_outlined,
                      color: scheme.primary,
                    ),
                    title: Text(
                      state.systemEnabled ? '已跟随手机系统开启' : '设置出生日期',
                    ),
                    subtitle: Text(
                      state.systemEnabled
                          ? '系统年龄范围：${state.ageBand.label}；由系统管理，应用内无法绕过。'
                          : '用于开启 App 未成年人模式并应用适龄策略',
                    ),
                    trailing: state.systemEnabled
                        ? null
                        : OutlinedButton(
                            onPressed: _minorBirthDateSaving
                                ? null
                                : _pickMinorBirthDate,
                            child: Text(
                              _minorBirthDate == null ? '选择' : '修改',
                            ),
                          ),
                  ),
                ),
              ),
              if (!state.systemEnabled) ...[
                const SizedBox(height: 16),
                AppSettingsSection(
                  title: '当前选择',
                  children: [
                    ListTile(
                      leading: Icon(Icons.calendar_month_outlined,
                          color: scheme.primary),
                      title: const Text('出生日期'),
                      trailing: Text(
                        selectedDateLabel,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(Icons.groups_2_outlined,
                          color: scheme.onSurfaceVariant),
                      title: const Text('年龄段'),
                      trailing: Text(
                        ageBand.label,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OptionalLiquidGlassCard(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  borderRadius: 12,
                  highContrast: true,
                  tint: scheme.primary.withValues(alpha: 0.16),
                  fallbackDecoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _minorBirthDate == null
                        ? '可以跳过，之后在 设置 > 未成年人模式 中补充。'
                        : ageBand == MinorAgeBand.adult
                            ? '当前年龄段为成人，App 未成年人模式不会开启。'
                            : '当前年龄段为${ageBand.label}，App 未成年人模式已按年龄策略准备。',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
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
        _buildMediaAsset('assets/guide_media/android_widget_guide.webm'),
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
        OptionalLiquidGlassCard(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          borderRadius: 14,
          highContrast: true,
          tint: Colors.indigo.withValues(alpha: 0.16),
          fallbackDecoration: BoxDecoration(
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
      _buildMediaAsset('assets/guide_media/windows_pomodoro.webm'),
    ]));
  }

  Widget _buildWinFeaturePage2() {
    return _buildPageContainer(
        content: Column(children: [
      const SizedBox(height: 16),
      _buildStepHeader(
        icon: Icons.web_asset_rounded,
        iconColor: Theme.of(context).colorScheme.secondary,
        title: '无缝接入 Windows 屏幕时间',
        subtitle: '利用本地读取 Tai 软件（专业 Windows 时间追踪应用）的数据库，轻松在应用内部汇总双端时长。',
      ),
      _buildMediaAsset('assets/guide_media/windows_screen_time.webm'),
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
        OptionalLiquidGlassCard(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          borderRadius: 12,
          highContrast: true,
          fallbackDecoration: BoxDecoration(
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
                    color: _taiDbPath.isNotEmpty
                        ? Theme.of(context).colorScheme.primary
                        : Colors.red,
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
    final isWeb = AppPlatform.isWeb;
    return _buildPageContainer(
        content: Column(
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.calendar_month_outlined,
          iconColor: Colors.teal,
          title: '课表导入与学期同步',
          subtitle: isWeb
              ? '网页版支持浏览器文件导入、云端课表同步和学期进度设置。\n受浏览器限制，教务 WebView 导入和系统本地路径能力会降级。'
              : '全平台均支持智能课表解析。你可以在首页设置中导入本地课表，或直接从云端同步。\n设置开学与放假日期，以开启学期进度条。',
        ),
        const SizedBox(height: 24),
        OptionalLiquidGlassCard(
          margin: EdgeInsets.zero,
          borderRadius: 12,
          highContrast: true,
          fallbackDecoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.linear_scale),
                  title: const Text('首页学期进度条', style: TextStyle(fontSize: 14)),
                  value: _semesterEnabled,
                  onChanged: (val) {
                    setState(() => _semesterEnabled = val);
                    StorageService.saveAppSetting(
                        StorageService.keySemesterProgressEnabled, val);
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
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isWeb
                      ? '提示：网页版请使用浏览器文件选择或云端同步导入课表。'
                      : '提示：进入应用后，请前往 设置 > 课程设置 导入或同步您的课表！',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        if (_checkingCloudData) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ] else if (_hasCloudCourses || _hasCloudSemester) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.cloud_sync_rounded,
                  size: 16, color: scheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Text('检测到云端数据',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.5))),
            ],
          ),
          const SizedBox(height: 10),
          if (_hasCloudCourses)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _importingCourses ? null : _importCloudCourses,
                icon: _importingCourses
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.calendar_month_rounded, size: 20),
                label: Text(_importingCourses ? '正在导入...' : '从云端同步课表'),
              ),
            ),
          if (_hasCloudCourses && _hasCloudSemester) const SizedBox(height: 8),
          if (_hasCloudSemester)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _importingSemester ? null : _importCloudSemester,
                icon: _importingSemester
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.date_range_rounded, size: 20),
                label: Text(_importingSemester ? '正在同步...' : '从云端同步开学/放假时间'),
              ),
            ),
        ],
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
        if (isStart) {
          _semesterStart = picked;
        } else {
          _semesterEnd = picked;
        }
      });
      final prefs = await SharedPreferences.getInstance();
      if (isStart) {
        await prefs.setString(
            StorageService.keySemesterStart, picked.toIso8601String());
      } else {
        await prefs.setString(
            StorageService.keySemesterEnd, picked.toIso8601String());
      }
    }
  }

  Widget _buildGlobalThemeSetupPage() {
    final isWeb = AppPlatform.isWeb;
    final scheme = Theme.of(context).colorScheme;
    return _buildPageContainer(
        content: Column(
      children: [
        const SizedBox(height: 16),
        _buildStepHeader(
          icon: Icons.palette_outlined,
          iconColor: Colors.deepPurple,
          title: '个性化：模块排序与主题',
          subtitle: isWeb
              ? '你可以自由决定首页模块顺序，选择跟随系统、浅色或深色主题，还可以开启液态玻璃效果。'
              : '你可以自由决定首页上哪个模块显示在最上面。进入设置找到 "模块管理" 即可自由拖拽模块进行排序。\n开启深色模式让你在夜晚操作更舒适，也可以打开下方的液态玻璃效果。',
        ),
        const SizedBox(height: 24),
        const GuideAppearanceOptions(),
        if (isWeb) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: scheme.secondary.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: scheme.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '网页版的跟随系统会读取浏览器/操作系统的亮暗偏好，浏览器偏好变化后界面会随应用主题刷新。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                Text("本地数据迁移完成",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal)),
                SizedBox(height: 8),
                Text("单一事实来源 (SSoT) 架构已激活",
                    style: TextStyle(fontSize: 12, color: Colors.teal)),
              ],
            ),
          ),
          const SizedBox(height: 40),
          _buildMigrationPoint(
              Icons.bolt_rounded, "极致搜索性能", "基于 FTS5 全文索引，即便万条待办，检索只需毫秒。"),
          const SizedBox(height: 20),
          _buildMigrationPoint(Icons.offline_pin_rounded, "离线操作拦截",
              "内置 Oplog 离线记录仪，断网改动自动入库，联网秒速对齐。"),
          const SizedBox(height: 20),
          _buildMigrationPoint(Icons.security_rounded, "核心数据双活",
              "本地 SQL 与 Prefs 互为备份，最大限度抵御外部文件损毁风险。"),
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
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(desc,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[600], height: 1.4)),
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
    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 12,
      highContrast: true,
      tint: isGranted ? Colors.green.withValues(alpha: 0.16) : null,
      fallbackDecoration: BoxDecoration(
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
                            color: Colors.grey.withValues(alpha: 0.2),
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
      bottomNavigationBar: FloatingBottomBar(
        height: 136,
        child: SafeArea(
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
      ),
    );
  }
}

class _RecentFeature {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget Function()? destinationBuilder; // null = 不支持跳转（首次引导）
  const _RecentFeature(this.icon, this.color, this.title, this.subtitle,
      {this.destinationBuilder});
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

/// 引导页外观选项区：深色模式 + 液态玻璃开关。
///
/// 独立成组件便于复用与测试；选择立即持久化。
class GuideAppearanceOptions extends StatefulWidget {
  const GuideAppearanceOptions({super.key});

  @override
  State<GuideAppearanceOptions> createState() => _GuideAppearanceOptionsState();
}

class _GuideAppearanceOptionsState extends State<GuideAppearanceOptions> {
  String _themeMode = 'system';
  bool _liquidGlassEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final theme = await StorageService.getThemeMode();
    final glass = await LiquidGlassEffectService.loadEnabled();
    if (!mounted) return;
    setState(() {
      if (const {'system', 'light', 'dark'}.contains(theme)) {
        _themeMode = theme;
      }
      _liquidGlassEnabled = glass;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        OptionalLiquidGlassCard(
          margin: EdgeInsets.zero,
          borderRadius: 12,
          highContrast: true,
          fallbackDecoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            type: MaterialType.transparency,
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
                        StorageService.keyThemeMode, val);
                    StorageService.themeNotifier.value = val;
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OptionalLiquidGlassCard(
          key: const ValueKey('guide-liquid-glass-card'),
          margin: EdgeInsets.zero,
          borderRadius: 12,
          highContrast: true,
          tint: _liquidGlassEnabled
              ? scheme.primary.withValues(alpha: 0.16)
              : null,
          fallbackDecoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('guide-liquid-glass-switch'),
              value: _liquidGlassEnabled,
              secondary: const Icon(Icons.blur_on_rounded),
              title: const Text('液态玻璃效果', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '全局磨砂质感与折射视觉，可在"动效设置"中调整模式',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              onChanged: (val) {
                setState(() => _liquidGlassEnabled = val);
                LiquidGlassEffectService.setEnabled(val);
              },
            ),
          ),
        ),
      ],
    );
  }
}
