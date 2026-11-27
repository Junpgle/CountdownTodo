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

import '../utils/time_utils.dart';

import '../services/api_service.dart';
import '../utils/app_platform.dart';
import '../utils/page_transitions.dart';
import 'course_screens.dart';
import 'personal_timeline_screen.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/global_search_overlay.dart';
import 'settings/pages/preference_settings_page.dart';
import '../services/course_service.dart';
import '../course_import/course_schedule_semantics.dart';
import '../services/permission_request_coordinator.dart';
import '../services/minor_mode_service.dart';
import '../services/liquid_glass_effect_service.dart';
import '../models/minor_mode_state.dart';
import '../models.dart';
import '../features/finance/screens/finance_home_screen.dart';
import '../features/habits/screens/habit_center_screen.dart';
import '../features/thirty_day_challenge/screens/challenge_center_screen.dart';
import '../widgets/app_settings_widgets.dart';
import '../widgets/changelog_bullet_item.dart';
import '../widgets/floating_bottom_bar.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import 'animation_settings_page.dart';
import '../services/device_calendar_read_service.dart';
import 'settings/device_calendar_read_page.dart';
import '../utils/app_dialogs.dart';
import 'ai_assistant_tutorial_screen.dart';
import 'help/feature_explorer_screen.dart';
import 'historical_todos_screen.dart';
import 'pomodoro_screen.dart';
import 'todo_plan_screen.dart';

part 'feature_guide/feature_guide_data.dart';
part 'feature_guide/feature_guide_changelog_and_platform_pages.dart';
part 'feature_guide/feature_guide_setup_pages.dart';
part 'feature_guide/feature_guide_widgets.dart';

const MethodChannel _featureGuidePlatform = MethodChannel(
  'com.math_quiz.junpgle.com.math_quiz_app/notifications',
);
const MethodChannel _featureGuideScreenTimeChannel = MethodChannel(
  'com.math_quiz_app/screen_time',
);

/// 控制功能页的入口展示范围。
enum FeatureGuideMode { automatic, changelog, guide }

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
  late final PermissionRequestCoordinator _permissionCoordinator;

  // 从远端加载的数据
  String _currentVersion = '';
  String _previousShownVersion = '';
  List<ChangelogEntry> _changelogHistory = [];
  bool _loadingChangelog = true;
  bool _changelogFetchFailed = false; // 🚀 区分"无网络"和"本版本无更新日志"
  String? _changelogNotice;
  final Set<String> _expandedVersions = {};

  // 权限状态
  PermissionStatus? _notificationStatus;
  bool _hasUsageStats = false;
  bool _hasExactAlarm = false;
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

  /// 手机日历读取开关只在自动版本引导中主动提供一次。
  bool _deviceCalendarReadGuideOffered = false;
  bool _deviceCalendarReadSetupPageIncluded = false;

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

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _permissionCoordinator = PermissionRequestCoordinator(
      context: context,
      platformChannel: _featureGuidePlatform,
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
      if (_deviceCalendarReadSetupPageIncluded) {
        await DeviceCalendarReadService.markGuideOffered();
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
      Navigator.of(context)
          .pushAndRemoveUntil(PageTransitions.fadeThrough(dest), (_) => false);
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
          maxHeight: MediaQuery.sizeOf(context).height * 0.45,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.3),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child:
              assetPath.toLowerCase().endsWith('.mp4') ||
                  assetPath.toLowerCase().endsWith('.webm')
              ? AssetVideoPlayer(assetPath: assetPath)
              : Image.asset(assetPath, fit: fit, cacheWidth: 1080),
        ),
      ),
    );
  }

  Widget _buildPageContainer({required Widget content}) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
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
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 36, color: iconColor),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.6),
            height: 1.5,
          ),
        ),
      ],
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
                : Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSinglePage = _pagesBuilder.length == 1;
    final isFirstPage = _currentPage == 0;
    final isLastPage = _currentPage == _pagesBuilder.length - 1;
    // Each action is a standalone lens. There is intentionally no parent
    // glass shell; dark mode uses a clean material surface to avoid muddy
    // refraction around the action area.
    final useActionGlass =
        Theme.of(context).colorScheme.brightness != Brightness.dark;
    final primaryAction = _buildLiquidGlassAction(
      onPressed: isLastPage ? _done : _nextPage,
      icon: isLastPage ? Icons.check_rounded : Icons.arrow_forward_rounded,
      label: isLastPage ? '完成体验' : '继续探索',
      useGlass: useActionGlass,
      width: isSinglePage ? 212 : null,
    );
    final previousAction = _buildLiquidGlassAction(
      onPressed: _previousPage,
      icon: Icons.arrow_back_rounded,
      label: '上一页',
      useGlass: useActionGlass,
    );
    final bottomActions = isFirstPage
        ? Center(child: primaryAction)
        : Row(
            children: [
              Expanded(child: previousAction),
              const SizedBox(width: 8),
              Expanded(child: primaryAction),
            ],
          );
    final guideBottomBarHorizontalPadding =
        floatingBottomBarShouldFloat(context)
        ? floatingBottomBarMarginFor(context).left
        : 16.0;
    final bottomBar = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          guideBottomBarHorizontalPadding,
          8,
          guideBottomBarHorizontalPadding,
          12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPageIndicator(),
            if (!isSinglePage) const SizedBox(height: 6),
            bottomActions,
          ],
        ),
      ),
    );

    return Scaffold(
      extendBody: floatingBottomBarShouldFloat(context),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _pagesBuilder.length,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemBuilder: (ctx, i) {
          return _pagesBuilder[i]();
        },
      ),
      bottomNavigationBar: isSinglePage
          ? SafeArea(
              top: false,
              child: SizedBox(height: 64, child: Center(child: primaryAction)),
            )
          : bottomBar,
    );
  }
}
