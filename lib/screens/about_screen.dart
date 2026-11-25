import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../utils/page_transitions.dart';
import '../utils/app_performance_monitor.dart';
import '../utils/app_platform.dart';
import '../utils/settings_navigation.dart';
import '../utils/app_dialogs.dart';
import 'settings/device_version_detail_page.dart';
import 'settings/pages/sync_health_page.dart';
import 'login_screen.dart';
import '../storage_service.dart';
import '../update_service.dart';

import 'dart:async';

import '../services/local_migration_service.dart';
import '../services/database_helper.dart';
import '../services/database_schema_history.dart';
import '../services/sync_health_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/github_resource_service.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import '../services/app_memory_monitor.dart';
import '../utils/app_scroll_behavior.dart';

part 'about/about_screen_cards.dart';
part 'about/about_screen_sheets.dart';

class AboutScreen extends StatefulWidget {
  final bool isEmbedded;
  const AboutScreen({super.key, this.isEmbedded = false});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen>
    with SettingsNavigationMixin<AboutScreen> {
  static const _appIconAsset = 'assets/icon/app_icon.png';
  static final GitHubResourceService _resourceService = GitHubResourceService();
  static final RegExp _privacyDatePattern = RegExp(r'\*\*版本日期：(.+?)\*\*');
  String _version = '加载中...';
  List<ChangelogEntry> _changelogEntries = [];
  bool _isLoadingChangelog = true;
  bool _versionExpanded = false;
  bool _archiveLoaded = false;
  bool _isLoadingArchive = false;
  static const int _pageSize = 10;

  String? _privacyPolicyContent;
  String? _privacyPolicyDate;
  bool _isLoadingPrivacy = true;
  String _deviceArch = '加载中...';
  String _deviceModel = '';
  String _osVersion = '';
  int? _databaseVersion;
  bool _databaseVersionLoadFailed = false;

  // 🚀 Uni-Sync 4.0 迁移状态
  bool _needsMigration = false;
  bool _isMigrating = false;
  double _migrationProgress = 0.0;
  String _migrationStage = '';
  bool _migrationCompleted = false;
  List<String> _migrationErrors = [];
  int _migrationSuccessCount = 0;
  StreamSubscription? _migrationSub;
  SyncHealthSnapshot? _syncSummary;
  String? _syncUsername;
  bool _syncSummaryFailed = false;

  static const String privacyRawUrl =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';

  @override
  bool get isEmbeddedSettingsPage => widget.isEmbedded;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadChangelog();
    _fetchPrivacyPolicy();
    _loadDeviceInfo();
    _loadDatabaseVersion();
    _checkMigration();
    _loadSyncSummary();
    AppPerformanceMonitor.setCurrentScreen('关于此应用');
    AppPerformanceMonitor.loadSettings();
    AppMemoryMonitor.refresh();
  }

  void _checkMigration() async {
    final needs = await LocalMigrationService.needsMigration();
    if (mounted) {
      setState(() => _needsMigration = needs);
    }
  }

  Future<void> _loadSyncSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(StorageService.keyCurrentUser)?.trim();
    if (!mounted) return;
    if (username == null || username.isEmpty) {
      setState(() {
        _syncUsername = null;
        _syncSummaryFailed = false;
      });
      return;
    }
    try {
      final summary = await SyncHealthService.load(username);
      if (!mounted) return;
      setState(() {
        _syncUsername = username;
        _syncSummary = summary;
        _syncSummaryFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncUsername = username;
        _syncSummaryFailed = true;
      });
    }
  }

  @override
  void dispose() {
    AppMemoryMonitor.setAutoRefresh(false);
    _migrationSub?.cancel();
    super.dispose();
  }

  void _startMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(StorageService.keyCurrentUser) ?? '';
    if (!mounted) return;

    setState(() {
      _isMigrating = true;
      _migrationProgress = 0.0;
      _migrationStage = '启动迁移...';
    });

    _migrationSub = LocalMigrationService.performMigration(username)
        .listen((p) {
          if (mounted) {
            setState(() {
              _migrationProgress = p.progress;
              _migrationStage = p.stage;
              _migrationErrors = p.errors;
              _migrationSuccessCount = p.totalSuccess;
              if (p.isCompleted) {
                _isMigrating = false;
                _migrationCompleted = p.errors.isEmpty;
                _needsMigration = p.errors.isNotEmpty;
              }
            });
          }
        });
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (AppPlatform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        if (mounted) {
          setState(() {
            _deviceArch = androidInfo.supportedAbis.join(', ');
            _deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
            _osVersion =
                'Android ${androidInfo.version.release} (API ${androidInfo.version.sdkInt})';
          });
        }
      } else if (AppPlatform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        if (mounted) {
          setState(() {
            _deviceArch = 'Windows';
            _deviceModel = windowsInfo.computerName;
            _osVersion =
                'Windows ${windowsInfo.majorVersion}.${windowsInfo.minorVersion}';
          });
        }
      } else if (AppPlatform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        if (mounted) {
          setState(() {
            _deviceArch = macInfo.arch;
            _deviceModel = macInfo.model;
            _osVersion = 'macOS ${macInfo.osRelease}';
          });
        }
      }
    } catch (e) {
      // debugPrint('获取设备信息失败: $e');
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
      });
    }
  }

  Future<void> _loadDatabaseVersion() async {
    if (_databaseVersionLoadFailed && mounted) {
      setState(() {
        _databaseVersion = null;
        _databaseVersionLoadFailed = false;
      });
    }

    try {
      final database = await DatabaseHelper.instance.database;
      final versionRows = await database.rawQuery('PRAGMA user_version');
      if (versionRows.isEmpty || versionRows.first.values.first is! num) {
        throw const FormatException('无法读取数据库架构版本');
      }
      final version = (versionRows.first.values.first as num).toInt();
      if (mounted) {
        setState(() => _databaseVersion = version);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _databaseVersionLoadFailed = true);
      }
    }
  }

  Future<void> _showDatabaseChangelog() {
    return showAppModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _DatabaseChangelogSheet(currentVersion: _databaseVersion),
      ),
    );
  }

  Future<void> _loadChangelog() async {
    try {
      final manifest = await UpdateService.checkManifest(preferCache: true);
      final recent = manifest?.changelogHistory ?? [];
      if (mounted) {
        setState(() {
          _changelogEntries = recent;
          _isLoadingChangelog = false;
        });
      }
    } catch (e) {
      // debugPrint('获取更新日志失败: $e');
      if (mounted) {
        setState(() => _isLoadingChangelog = false);
      }
    }
  }

  Future<void> _loadArchive() async {
    if (_archiveLoaded || _isLoadingArchive) return;
    _isLoadingArchive = true;
    try {
      final manifest = await UpdateService.checkManifest(preferCache: true);
      final archive = await UpdateService.loadChangelogArchive(
        manifest: manifest,
        preferCache: true,
      );
      if (mounted) {
        setState(() {
          _changelogEntries = [..._changelogEntries, ...archive];
          _archiveLoaded = true;
          _isLoadingArchive = false;
        });
      }
    } catch (e) {
      // debugPrint('加载归档日志失败: $e');
      if (mounted) {
        setState(() => _isLoadingArchive = false);
      }
    }
  }

  Future<void> _fetchPrivacyPolicy() async {
    try {
      final response = await _resourceService.get(Uri.parse(privacyRawUrl));
      if (response.statusCode == 200) {
        final content = response.body;
        String? date;
        final dateMatch = _privacyDatePattern.firstMatch(content);
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
      // debugPrint('获取隐私政策失败: $e');
      if (mounted) setState(() => _isLoadingPrivacy = false);
    }
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    }
  }

  Future<void> _showPrivacyPolicyPage() async {
    await openSettingsPage(
      'privacy',
      PrivacyPolicyPage(
        content: _privacyPolicyContent,
        date: _privacyPolicyDate,
        isLoading: _isLoadingPrivacy,
        isEmbedded: widget.isEmbedded,
      ),
      settings: const RouteSettings(name: '隐私政策'),
    );
  }

  Future<void> _showWithdrawConfirmation() async {
    final confirmed = await showAppDialog<bool>(
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
        PageTransitions.material(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _runDeduplication() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('课程去重'),
        content: const Text(
          '系统将扫描数据库中重复的课程记录（名称、时间、周次、地点均相同），并自动清理多余项。此操作将保留最新的一份，并将清理记录同步到云端。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始清理'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('正在执行数据库深度清理...')),
      );

      final count = await DatabaseHelper.instance.deduplicateCourses();

      if (mounted) {
        showAppDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('清理完成'),
            content: Text('成功清理了 $count 条重复课程记录。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth > 800;
    final standalone = !widget.isEmbedded && !isWide;

    return Scaffold(
      extendBodyBehindAppBar: standalone,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('关于此应用'),
              centerTitle: true,
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: standalone,
        child: isWide
            ? _buildWideLayout(context)
            : _buildNarrowLayout(context, standalone: standalone),
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      children: [
        // 左侧固定面板
        SizedBox(
          width: 340,
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: RepaintBoundary(
              child: SingleChildScrollView(
                physics: const AppFluidScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            _appIconAsset,
                            width: 80,
                            height: 80,
                            cacheWidth: 240,
                            cacheHeight: 240,
                            fit: BoxFit.cover,
                            semanticLabel: 'CountDownTodo',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'CountDownTodo',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '版本 $_version',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '您的个人效率助手',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      _buildInfoCard(
                        context,
                        title: '软件介绍',
                        icon: Icons.info_outline,
                        compact: true,
                        child: const Text(
                          'CountDownTodo 是一款集成了多种实用功能的个人效率管理应用，旨在帮助您更好地管理时间、任务和学习。\n\n'
                          '主要功能：待办事项管理、重要日倒计时、课程表管理、屏幕使用时间、番茄钟专注、数学测验、多设备同步等。',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDeviceCard(context, compact: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // 右侧滚动区域
        Expanded(
          child: RepaintBoundary(
            child: SingleChildScrollView(
              physics: const AppFluidScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        _buildMemoryCard(context),
                        const SizedBox(height: 16),
                        _buildPerformanceCard(context),
                        const SizedBox(height: 16),
                        _buildDatabaseCard(context),
                        const SizedBox(height: 16),
                        _buildCleanupCard(context),
                        const SizedBox(height: 16),
                        _buildChangelogCard(context),
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
                              onTap: () => _launchURL(
                                'https://github.com/Junpgle/math_quiz_app',
                              ),
                            ),
                            _LinkItem(
                              icon: Icons.bug_report_outlined,
                              title: '问题反馈',
                              subtitle: '在 GitHub 提交 Issues',
                              onTap: () => _launchURL(
                                'https://github.com/Junpgle/math_quiz_app/issues',
                              ),
                            ),
                            _LinkItem(
                              sourceKey: settingsNavigationKey(
                                'device_versions',
                              ),
                              icon: Icons.devices_other_outlined,
                              title: '设备版本明细',
                              subtitle: '查看在线设备与历史版本分布',
                              onTap: () {
                                openSettingsPage(
                                  'device_versions',
                                  DeviceVersionDetailPage(
                                    isEmbedded: widget.isEmbedded,
                                  ),
                                  settings: const RouteSettings(name: '设备版本明细'),
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
                        if (_needsMigration ||
                            _isMigrating ||
                            _migrationCompleted)
                          _buildMigrationPanel(context),
                        if (_shouldShowSyncSummary)
                          _buildSyncIssueCenter(context),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(BuildContext context, {required bool standalone}) {
    return RepaintBoundary(
      child: SingleChildScrollView(
        physics: const AppFluidScrollPhysics(),
        child: Column(
          children: [
            SizedBox(
              height: standalone
                  ? floatingGlassSettingsContentTopInset(context, extra: 32)
                  : 32,
            ),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  _appIconAsset,
                  width: 100,
                  height: 100,
                  cacheWidth: 300,
                  cacheHeight: 300,
                  fit: BoxFit.cover,
                  semanticLabel: 'CountDownTodo',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'CountDownTodo',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '版本 $_version',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text('您的个人效率助手', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildInfoCard(
                context,
                title: '软件介绍',
                icon: Icons.info_outline,
                child: const Text(
                  'CountDownTodo 是一款集成了多种实用功能的个人效率管理应用，旨在帮助您更好地管理时间、任务和学习。\n\n'
                  '主要功能：待办事项管理、重要日倒计时、课程表管理、屏幕使用时间、番茄钟专注、数学测验、多设备同步等。',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildDeviceCard(context),
            ),
            const SizedBox(height: 16),
            _buildMemoryCard(context),
            const SizedBox(height: 16),
            _buildPerformanceCard(context),
            const SizedBox(height: 16),
            _buildDatabaseCard(context),
            const SizedBox(height: 16),
            _buildCleanupCard(context),
            const SizedBox(height: 16),
            _buildChangelogCard(context),
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
                    'https://github.com/Junpgle/math_quiz_app/issues',
                  ),
                ),
                _LinkItem(
                  sourceKey: settingsNavigationKey('device_versions'),
                  icon: Icons.devices_other_outlined,
                  title: '设备版本明细',
                  subtitle: '查看在线设备与历史版本分布',
                  onTap: () {
                    openSettingsPage(
                      'device_versions',
                      DeviceVersionDetailPage(isEmbedded: widget.isEmbedded),
                      settings: const RouteSettings(name: '设备版本明细'),
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
            if (_needsMigration || _isMigrating || _migrationCompleted)
              _buildMigrationPanel(context),
            if (_shouldShowSyncSummary) _buildSyncIssueCenter(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncIssueCenter(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = _syncSummary;
    final subtitle = _syncSummaryFailed
        ? '暂时无法读取同步状态，点击查看并重试读取'
        : summary == null
        ? '查看各模块的数据同步状态'
        : summary.totalConflictCount > 0
        ? '${summary.totalPendingCount} 项待处理 · ${summary.totalConflictCount} 项冲突需核对'
        : summary.totalPendingCount > 0
        ? '${summary.totalPendingCount} 项数据待处理 · 点击查看安全重试选项'
        : '当前没有待处理项目';

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        color: (summary?.totalConflictCount ?? 0) > 0
            ? colorScheme.errorContainer.withValues(alpha: 0.35)
            : null,
        child: ListTile(
          leading: Icon(
            _syncSummaryFailed
                ? Icons.sync_problem_rounded
                : Icons.cloud_sync_outlined,
            color: _syncSummaryFailed ? colorScheme.error : colorScheme.primary,
          ),
          title: const Text('同步状态'),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            openSettingsPage(
              'sync_health',
              SyncHealthPage(username: _syncUsername ?? ''),
              settings: const RouteSettings(name: '同步状态'),
            );
          },
        ),
      ),
    );
  }

  bool get _shouldShowSyncSummary =>
      _syncSummaryFailed || (_syncSummary?.hasAttention ?? false);

  void _mutateState(VoidCallback fn) => setState(fn);
}
