import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../utils/page_transitions.dart';
import '../utils/app_performance_monitor.dart';
import '../utils/app_platform.dart';
import '../utils/app_dialogs.dart';
import 'settings/device_version_detail_page.dart';
import 'login_screen.dart';
import '../storage_service.dart';
import '../update_service.dart';
import 'dart:async';
import '../services/local_migration_service.dart';
import '../services/database_helper.dart';
import '../services/database_schema_history.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/github_resource_service.dart';
import '../widgets/floating_glass_control.dart';
import '../widgets/optional_liquid_glass_surface.dart';

class AboutScreen extends StatefulWidget {
  final bool isEmbedded;
  const AboutScreen({super.key, this.isEmbedded = false});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _appIconAsset = 'assets/icon/app_icon.png';
  static final GitHubResourceService _resourceService = GitHubResourceService();
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
  List<Map<String, dynamic>> _syncFailures = [];

  static const String privacyRawUrl =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadChangelog();
    _fetchPrivacyPolicy();
    _loadDeviceInfo();
    _loadDatabaseVersion();
    _checkMigration();
    _loadSyncFailures();
    AppPerformanceMonitor.setCurrentScreen('关于此应用');
    AppPerformanceMonitor.loadSettings();
  }

  void _checkMigration() async {
    final needs = await LocalMigrationService.needsMigration();
    if (mounted) {
      setState(() => _needsMigration = needs);
    }
  }

  Future<void> _loadSyncFailures() async {
    final failures = await StorageService.getSyncFailures();
    if (mounted) {
      setState(() => _syncFailures = failures);
    }
  }

  @override
  void dispose() {
    _migrationSub?.cancel();
    super.dispose();
  }

  void _startMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_user') ?? '';

    setState(() {
      _isMigrating = true;
      _migrationProgress = 0.0;
      _migrationStage = '启动迁移...';
    });

    _migrationSub =
        LocalMigrationService.performMigration(username).listen((p) {
      if (mounted) {
        setState(() {
          _migrationProgress = p.progress;
          _migrationStage = p.stage;
          _migrationErrors = p.errors;
          _migrationSuccessCount = p.totalSuccess;
          if (p.isCompleted) {
            _migrationCompleted = true;
            _isMigrating = false;
            _needsMigration = false;
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
          manifest: manifest, preferCache: true);
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
          isEmbedded: widget.isEmbedded,
        ),
        settings: const RouteSettings(name: '隐私政策'),
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
        PageTransitions.material(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _runDeduplication() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('课程去重'),
        content: const Text(
            '系统将扫描数据库中重复的课程记录（名称、时间、周次、地点均相同），并自动清理多余项。此操作将保留最新的一份，并将清理记录同步到云端。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始清理')),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('正在执行数据库深度清理...')));

      final count = await DatabaseHelper.instance.deduplicateCourses();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('清理完成'),
            content: Text('成功清理了 $count 条重复课程记录。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
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
            child: SingleChildScrollView(
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
                          fit: BoxFit.cover,
                          semanticLabel: 'CountDownTodo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'CountDownTodo',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '版本 $_version',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
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
        // 右侧滚动区域
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
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
                                'https://github.com/Junpgle/math_quiz_app'),
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
                                  DeviceVersionDetailPage(
                                      isEmbedded: widget.isEmbedded),
                                  settings: const RouteSettings(name: '设备版本明细'),
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
                      if (_needsMigration ||
                          _isMigrating ||
                          _migrationCompleted)
                        _buildMigrationPanel(context),
                      if (_syncFailures.isNotEmpty)
                        _buildSyncIssueCenter(context),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context, {
    required bool standalone,
  }) {
    return SingleChildScrollView(
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
                fit: BoxFit.cover,
                semanticLabel: 'CountDownTodo',
              ),
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
                      DeviceVersionDetailPage(isEmbedded: widget.isEmbedded),
                      settings: const RouteSettings(name: '设备版本明细'),
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
          if (_needsMigration || _isMigrating || _migrationCompleted)
            _buildMigrationPanel(context),
          if (_syncFailures.isNotEmpty) _buildSyncIssueCenter(context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSyncIssueCenter(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync_problem_rounded,
                    color: colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Text(
                  '同步异常中心 (${_syncFailures.length})',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final username = prefs.getString('current_user') ?? '';
                    await StorageService.syncData(username,
                        forceFullSync: true);
                    _loadSyncFailures();
                  },
                  child: const Text('重试全部'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _syncFailures.length > 5 ? 5 : _syncFailures.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final failure = _syncFailures[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${failure['target_table']} | ${failure['op_type']}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      failure['sync_error'] ?? '原因未知',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                  );
                },
              ),
            ),
            if (_syncFailures.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: Text(
                    '还有 ${_syncFailures.length - 5} 条异常未列出',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceCard(BuildContext context) {
    if (!AppPerformanceMonitor.isAvailable) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<int>(
      valueListenable: AppPerformanceMonitor.changes,
      builder: (context, _, __) {
        final monitor = AppPerformanceMonitor.snapshot;
        final colorScheme = Theme.of(context).colorScheme;
        final events = monitor.events.take(8).toList();

        return _buildInfoCard(
          context,
          title: '帧性能测试器（调试）',
          icon: Icons.speed_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用帧性能记录'),
                subtitle: const Text('仅 Debug/Profile 构建可见，记录超过阈值的帧'),
                value: AppPerformanceMonitor.isEnabled,
                onChanged: AppPerformanceMonitor.setEnabled,
              ),
              if (AppPerformanceMonitor.isEnabled) ...[
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('触发阈值'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: monitor.thresholdMilliseconds,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: AppPerformanceMonitor.availableThresholds
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value ms'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          AppPerformanceMonitor.setThresholdMilliseconds(value);
                        }
                      },
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: AppPerformanceMonitor.clear,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const Text('清空'),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('记录触发界面'),
                  subtitle: const Text('在每条超时帧后显示当前页面名称'),
                  value: AppPerformanceMonitor.isScreenTrackingEnabled,
                  onChanged: AppPerformanceMonitor.setScreenTrackingEnabled,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPerformanceMetric(
                        context, '采样帧', '${monitor.frameCount}'),
                    _buildPerformanceMetric(
                        context, '超阈值', '${monitor.overThresholdCount}'),
                    _buildPerformanceMetric(
                        context, '慢构建', '${monitor.slowBuildCount}'),
                    _buildPerformanceMetric(
                        context, '慢光栅', '${monitor.slowRasterCount}'),
                    _buildPerformanceMetric(
                      context,
                      '最大耗时',
                      _formatPerformanceDuration(monitor.maxFrameSpan),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('最近触发记录', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (events.isEmpty)
                  Text(
                    monitor.frameCount == 0
                        ? '操作应用中的页面后，这里会显示详细帧耗时。'
                        : '当前采样帧均未超过 ${monitor.thresholdMilliseconds} ms。',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  )
                else
                  ...events.map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatPerformanceTime(event.observedAt)}  ·  ${_formatPerformanceDuration(event.totalSpan)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'build ${_formatPerformanceDuration(event.buildDuration)}  ·  '
                              'raster ${_formatPerformanceDuration(event.rasterDuration)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '触发界面：${event.screen}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildPerformanceMetric(
    BuildContext context,
    String label,
    String value,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label $value'),
    );
  }

  String _formatPerformanceDuration(Duration duration) {
    if (duration == Duration.zero) return '0.0 ms';
    return '${(duration.inMicroseconds / 1000).toStringAsFixed(1)} ms';
  }

  String _formatPerformanceTime(DateTime time) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    String threeDigits(int value) => value.toString().padLeft(3, '0');
    return '${twoDigits(time.hour)}:${twoDigits(time.minute)}:'
        '${twoDigits(time.second)}.${threeDigits(time.millisecond)}';
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
    bool compact = false,
  }) {
    return Card(
      elevation: compact ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: compact
          ? Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3)
          : null,
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: compact ? 18 : 20,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: compact ? 14 : 15)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
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

  Widget _buildDeviceCard(BuildContext context, {bool compact = false}) {
    return Card(
      elevation: compact ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: compact
          ? Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3)
          : null,
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices,
                    size: compact ? 18 : 20,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('设备信息',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: compact ? 14 : 15)),
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

  Widget _buildCleanupCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.cleaning_services_rounded,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('数据库清理'),
              subtitle: const Text('剔除重复课程数据，优化数据库体积'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _runDeduplication,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final version = _databaseVersion;
    final versionSubtitle = _databaseVersionLoadFailed
        ? '读取失败，可重试或直接查看架构日志'
        : version == null
            ? '正在读取本地 SQLite 架构版本…'
            : version == DatabaseSchemaHistory.currentVersion
                ? '本地 SQLite 架构已是最新版本'
                : '最新版本为 V${DatabaseSchemaHistory.currentVersion}';

    final Widget versionTrailing;
    if (_databaseVersionLoadFailed) {
      versionTrailing = IconButton(
        onPressed: _loadDatabaseVersion,
        icon: const Icon(Icons.refresh_rounded),
        tooltip: '重新读取',
      );
    } else if (version == null) {
      versionTrailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      versionTrailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'V$version',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                Icons.storage_rounded,
                color: colorScheme.primary,
              ),
              title: const Text('当前数据库版本'),
              subtitle: Text(versionSubtitle),
              trailing: versionTrailing,
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: Icon(
                Icons.manage_history_rounded,
                color: colorScheme.primary,
              ),
              title: const Text('数据库更新日志'),
              subtitle: Text(
                '查看 V1 至 V${DatabaseSchemaHistory.currentVersion} 的架构变更',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showDatabaseChangelog,
            ),
          ],
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
    final visibleEntries = _versionExpanded
        ? _changelogEntries
        : _changelogEntries.take(_pageSize).toList();
    final hasMore = _versionExpanded
        ? !_archiveLoaded
        : _changelogEntries.length > _pageSize;

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
                  if (_changelogEntries.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${_changelogEntries.length} 个版本',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              _isLoadingChangelog
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _changelogEntries.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('暂无更新日志'),
                          ),
                        )
                      : Column(
                          children: [
                            ...visibleEntries
                                .map((entry) => _buildChangelogEntry(entry)),
                            if (hasMore)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: TextButton.icon(
                                    onPressed: _isLoadingArchive
                                        ? null
                                        : () {
                                            if (!_versionExpanded) {
                                              // 第一次展开：显示更多近期版本
                                              setState(() =>
                                                  _versionExpanded = true);
                                              // 同时后台加载归档
                                              _loadArchive();
                                            } else if (!_archiveLoaded) {
                                              // 已展开但归档未加载：加载归档
                                              _loadArchive();
                                            }
                                          },
                                    icon: _isLoadingArchive
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(
                                            Icons.expand_more,
                                            size: 18,
                                          ),
                                    label: Text(
                                      _isLoadingArchive
                                          ? '加载中...'
                                          : _versionExpanded
                                              ? '加载更早版本'
                                              : '查看全部',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
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

  Widget _buildChangelogEntry(ChangelogEntry entry) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.versionName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (entry.date.isNotEmpty)
              Text(
                entry.date,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entry.items
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            item,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMigrationPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.4),
              colorScheme.secondaryContainer.withValues(alpha: 0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '升级至 Uni-Sync 4.0',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (_migrationCompleted)
                  const Icon(Icons.check_circle, color: Colors.green, size: 24),
              ],
            ),
            const SizedBox(height: 16),
            if (!_isMigrating && !_migrationCompleted) ...[
              const Text(
                '您的数据目前存储在旧版引擎中。升级到 Uni-Sync 4.0 (SQLite) 将获得极速搜索、离线同步和更稳定的数据保护。',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startMigration,
                  icon: const Icon(Icons.rocket_launch_rounded),
                  label: const Text('立即开始极速迁移'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ] else if (_isMigrating || _migrationCompleted) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _migrationStage,
                    style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '成功: $_migrationSuccessCount | 失败: ${_migrationErrors.length}',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _migrationProgress,
                  minHeight: 8,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                ),
              ),
              if (_migrationErrors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.orange, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '迁移发现 ${_migrationErrors.length} 条异常',
                            style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _migrationErrors.take(3).join('\n'),
                        style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontFamily: 'monospace'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_migrationErrors.length > 3)
                        const Text('...',
                            style: TextStyle(color: Colors.orange)),
                    ],
                  ),
                ),
              ],
              if (_migrationCompleted && _migrationErrors.isEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '数据已成功迁移至 SQLite 极速引擎！',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ],
          ],
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

class _DatabaseChangelogSheet extends StatelessWidget {
  final int? currentVersion;

  const _DatabaseChangelogSheet({required this.currentVersion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentLabel = currentVersion == null ? '未读取' : 'V$currentVersion';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.storage_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据库更新日志',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '当前 $currentLabel · 最新 V${DatabaseSchemaHistory.currentVersion}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                tooltip: '关闭',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '以下记录仅包含本地 SQLite 架构变更，不包含应用功能更新。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: DatabaseSchemaHistory.changes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = DatabaseSchemaHistory.changes[index];
              final isCurrent = entry.version == currentVersion;

              return OptionalLiquidGlassCard(
                margin: EdgeInsets.zero,
                borderRadius: 12,
                clipBehavior: Clip.antiAlias,
                highContrast: true,
                tint: isCurrent
                    ? colorScheme.primaryContainer.withValues(alpha: 0.16)
                    : null,
                fallbackDecoration: BoxDecoration(
                  color: isCurrent
                      ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                      : colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.fromBorderSide(
                    BorderSide(
                      color: isCurrent
                          ? colorScheme.primary.withValues(alpha: 0.35)
                          : colorScheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: PageStorageKey('database-version-${entry.version}'),
                      initiallyExpanded: isCurrent,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'V${entry.version}',
                              style: TextStyle(
                                color: colorScheme.onSecondaryContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 8),
                            Text(
                              '当前',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(entry.title),
                      ),
                      children: entry.changes
                          .map(
                            (change) => Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 7),
                                    child: Icon(
                                      Icons.circle,
                                      size: 5,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      change,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  final String? content;
  final String? date;
  final bool isLoading;
  final bool isEmbedded;

  const PrivacyPolicyPage({
    super.key,
    this.content,
    this.date,
    this.isLoading = true,
    this.isEmbedded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: !isEmbedded,
      appBar: isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('隐私政策'),
              centerTitle: true,
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !isEmbedded,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : content == null
                ? const Center(child: Text('加载失败，请检查网络连接'))
                : Markdown(
                    data: content!,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      isEmbedded
                          ? 16
                          : floatingGlassSettingsContentTopInset(context,
                              extra: 16),
                      16,
                      16,
                    ),
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
                      code: const TextStyle(
                          fontSize: 13, fontFamily: 'monospace'),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
      ),
    );
  }
}
