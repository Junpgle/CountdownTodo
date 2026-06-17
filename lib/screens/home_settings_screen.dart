import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';

import '../services/api_service.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../models.dart';
import '../utils/page_transitions.dart';
import '../services/reminder_schedule_service.dart';
import '../services/course_service.dart';

import 'animation_settings_page.dart';
import 'login_screen.dart';
import 'about_screen.dart';
import 'settings/widgets/account_section.dart';
import 'settings/widgets/sync_settings_section.dart';
import 'settings/notification_settings_page.dart';
import 'settings/dialogs/change_password_dialog.dart';

import 'settings/pages/preference_settings_page.dart';
import 'settings/pages/course_settings_page.dart';
import 'settings/pages/interconnect_settings_page.dart';
import 'settings/pages/platform_specific_settings_page.dart';
import 'settings/pages/permission_settings_page.dart';
import 'settings/llm_config_page.dart';

class SettingsPage extends StatefulWidget {
  final String? initialTarget;
  const SettingsPage({super.key, this.initialTarget});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _username = "加载中...";
  int? _userId;
  String _userTier = "加载中...";
  double _syncProgress = 0.0;
  bool _isLoadingStatus = true;
  bool _isInitialLoading = true;

  List<Announcement> _settingsAnnouncements = [];
  bool _isLoadingAnnouncements = true;
  bool _announcementLoadFailed = false;
  bool _announcementExpanded = false;

  String? _selectedPaneId;
  Widget Function()? _selectedRightPaneBuilder;
  
  GlobalKey<NavigatorState> _nestedNavigatorKey = GlobalKey<NavigatorState>();
  List<String> _nestedRouteNames = [];
  late _BreadcrumbObserver _breadcrumbObserver;

  @override
  void initState() {
    super.initState();
    _breadcrumbObserver = _createObserver();
    _loadAllData();

    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleInitialTarget(widget.initialTarget!);
      });
    } else {
      // 默认选中项
      _selectedPaneId = 'account';
      _selectedRightPaneBuilder = _buildAccountAndAnnouncementsPane;
    }
  }

  void _handleInitialTarget(String target) {
    String paneId;
    Widget Function() paneBuilder;

    final accountTargets = ['sync_interval', 'conflict_detection', 'server_choice'];
    final preferenceTargets = ['theme', 'theme_color', 'wallpaper', 'home_text'];
    final courseTargets = ['no_course_behavior', 'webview_import', 'smart_import', 'course_sync', 'course_upload', 'course_adapt', 'course_calendar_adjustment', 'semester_progress', 'semester_start', 'semester_end', 'semester_sync'];
    final interconnectTargets = ['lan_sync', 'band_sync', 'calendar_sync'];
    final advancedTargets = ['llm_config', 'llm_retry', 'migration', 'cache', 'storage', 'update', 'feature_guide'];
    final platformTargets = ['float_window_style', 'force_refresh', 'island_priority', 'tai_db', 'live_updates', 'island_support', 'test_notification'];

    if (accountTargets.contains(target)) {
      paneId = 'account';
      paneBuilder = _buildAccountAndAnnouncementsPane;
    } else if (preferenceTargets.contains(target)) {
      paneId = 'preference';
      paneBuilder = () => PreferenceSettingsPage(initialTarget: target, isEmbedded: true);
    } else if (courseTargets.contains(target)) {
      paneId = 'course';
      paneBuilder = () => CourseSettingsPage(initialTarget: target, isEmbedded: true);
    } else if (interconnectTargets.contains(target)) {
      paneId = 'interconnect';
      paneBuilder = () => InterconnectSettingsPage(initialTarget: target, isEmbedded: true);
    } else if (advancedTargets.contains(target)) {
      paneId = 'preference'; // merged into preference
      paneBuilder = () => PreferenceSettingsPage(initialTarget: target, isEmbedded: true);
    } else if (target == 'llm_config') {
      paneId = 'llm_config';
      paneBuilder = () => const LLMConfigPage(isEmbedded: true);
    } else if (target == 'animation') {
      paneId = 'animation';
      paneBuilder = () => const AnimationSettingsPage(isEmbedded: true);
    } else if (platformTargets.contains(target)) {
      paneId = 'platform';
      paneBuilder = () => PlatformSpecificSettingsPage(initialTarget: target, isEmbedded: true);
    } else if (target == 'permissions') {
      paneId = 'permissions';
      paneBuilder = () => const PermissionSettingsPage(isEmbedded: true);
    } else if (target == 'notifications') {
      paneId = 'notifications';
      paneBuilder = () => const NotificationSettingsPage(isEmbedded: true);
    } else if (target == 'about') {
      paneId = 'about';
      paneBuilder = () => const AboutScreen(isEmbedded: true);
    } else {
      return; // unknown target
    }

    final isWide = MediaQuery.of(context).size.width >= 800;
    if (isWide) {
      setState(() {
        _selectedPaneId = paneId;
        _selectedRightPaneBuilder = paneBuilder;
      });
    } else {
      // 窄屏下，需要重新构建一个非 embedded 的页面来 push
      Widget pushWidget;
      if (paneId == 'preference') pushWidget = PreferenceSettingsPage(initialTarget: target);
      else if (paneId == 'course') pushWidget = CourseSettingsPage(initialTarget: target);
      else if (paneId == 'interconnect') pushWidget = InterconnectSettingsPage(initialTarget: target);
      else if (paneId == 'llm_config') pushWidget = const LLMConfigPage();
      else if (paneId == 'animation') pushWidget = const AnimationSettingsPage();
      else if (paneId == 'platform') pushWidget = PlatformSpecificSettingsPage(initialTarget: target);
      else if (paneId == 'permissions') pushWidget = const PermissionSettingsPage();
      else if (paneId == 'notifications') pushWidget = const NotificationSettingsPage();
      else pushWidget = const AboutScreen();
      
      Navigator.push(context, PageTransitions.slideHorizontal(pushWidget));
    }
  }

  void _loadAllData() {
    _loadSettings().then((_) async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) setState(() => _isInitialLoading = false);
      _fetchAccountStatus();
    });
    _loadSettingsAnnouncements();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? "未登录";
      _userId = prefs.getInt('current_user_id');
    });
  }

  Future<void> _fetchAccountStatus() async {
    if (_userId == null) {
      if (mounted) {
        setState(() {
          _userTier = "离线";
          _syncProgress = 0.0;
          _isLoadingStatus = false;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = 'account_status_cache_$_userId';
    final String timeKey = 'account_status_time_$_userId';

    final String? cachedDataStr = prefs.getString(cacheKey);
    final int? lastSyncTime = prefs.getInt(timeKey);

    bool useCache = false;
    if (cachedDataStr != null && lastSyncTime != null) {
      final DateTime lastSync =
          DateTime.fromMillisecondsSinceEpoch(lastSyncTime, isUtc: true).toLocal();
      if (DateTime.now().difference(lastSync).inMinutes < 5) {
        useCache = true;
        try {
          final data = jsonDecode(cachedDataStr);
          if (mounted) {
            setState(() {
              _userTier = data['tier'] ?? 'Free';
              int count = data['sync_count'] ?? 0;
              int limit = data['sync_limit'] ?? 50;
              _syncProgress = limit > 0 ? (count / limit).clamp(0.0, 1.0) : 0.0;
              _isLoadingStatus = false;
            });
          }
        } catch (e) {
          useCache = false;
        }
      }
    }

    if (useCache) return;

    try {
      final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/api/user/status?user_id=$_userId'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        await prefs.setString(cacheKey, response.body);
        await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);

        if (mounted) {
          setState(() {
            _userTier = data['tier'] ?? 'Free';
            int count = data['sync_count'] ?? 0;
            int limit = data['sync_limit'] ?? 50;
            _syncProgress = limit > 0 ? (count / limit).clamp(0.0, 1.0) : 0.0;
            _isLoadingStatus = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _userTier = "Free";
            _isLoadingStatus = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userTier = "未知";
          _isLoadingStatus = false;
        });
      }
    }
  }

  Future<void> _loadSettingsAnnouncements() async {
    if (mounted) {
      setState(() {
        _isLoadingAnnouncements = true;
        _announcementLoadFailed = false;
      });
    }

    final announcements = await UpdateService.getAnnouncementsForSettings();
    if (!mounted) return;

    if (announcements == null) {
      setState(() {
        _isLoadingAnnouncements = false;
        _announcementLoadFailed = true;
        _settingsAnnouncements = [];
      });
      return;
    }

    setState(() {
      _isLoadingAnnouncements = false;
      _announcementLoadFailed = false;
      _settingsAnnouncements = announcements;
    });
  }

  Widget _buildAnnouncementPanel() {
    Widget content;
    if (_isLoadingAnnouncements) {
      content = Card(
        key: const ValueKey('loading'),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const ListTile(
          leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('公告加载中...'),
          subtitle: Text('正在获取最新公告内容'),
        ),
      );
    } else if (_announcementLoadFailed) {
      content = Card(
        key: const ValueKey('failed'),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.orange),
          title: const Text('公告加载失败'),
          subtitle: const Text('点击重试获取最新公告'),
          trailing: TextButton(
            onPressed: _loadSettingsAnnouncements,
            child: const Text('重试'),
          ),
        ),
      );
    } else if (_settingsAnnouncements.isEmpty) {
      content = const SizedBox.shrink();
    } else {
      final latest = _settingsAnnouncements.first;
      final others = _settingsAnnouncements.skip(1).toList();

      content = Card(
        key: const ValueKey('data'),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.campaign, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      latest.title.isEmpty ? '最新公告' : latest.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                latest.content.isEmpty ? '暂无内容' : latest.content,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
            if (others.isNotEmpty) ...[
              const Divider(height: 1),
              ExpansionTile(
                key: const PageStorageKey('settings_announcement_expansion'),
                title: Text('其他公告 (${others.length})'),
                initiallyExpanded: _announcementExpanded,
                onExpansionChanged: (expanded) {
                  setState(() => _announcementExpanded = expanded);
                },
                children: [
                  ...others.map(
                    (ann) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.announcement_outlined, size: 18),
                      title: Text(ann.title.isEmpty ? '未命名公告' : ann.title),
                      subtitle: Text(
                        ann.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: content,
    );
  }

  Widget _buildAccountAndAnnouncementsPane() {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildAnnouncementPanel(),
            const SizedBox(height: 16),
            AccountSection(
              username: _username,
              userId: _userId,
              userTier: _userTier,
              syncProgress: _syncProgress,
              isLoadingStatus: _isLoadingStatus,
              onRefreshStatus: _fetchAccountStatus,
              onForceFullSync: _forceFullSync,
              onLogout: () => _handleLogout(force: false),
              onChangePassword: _showChangePasswordDialog,
            ),
            SyncSettingsSection(username: _username),
          ],
        ),
      ),
    );
  }

  Future<void> _rescheduleReminders() async {
    if (_username.isEmpty || _username == "未登录" || _username == "加载中...") {
      return;
    }
    try {
      final todos = await StorageService.getTodos(_username);
      final courses = await CourseService.getAllCourses(_username);
      await ReminderScheduleService.scheduleAll(todos: todos, courses: courses);
    } catch (e) {}
  }

  Future<void> _forceFullSync() async {
    if (_username.isEmpty || _userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录账号')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('强制全量同步'),
        content: const Text(
          '这将重置本地同步记录，从云端拉取所有最新数据。\n\n本地未同步的数据会先上传，再合并云端数据。\n\n是否继续？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (confirm != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔄 正在全量同步...'), duration: Duration(seconds: 10)),
    );

    try {
      await StorageService.resetSyncTime(_username);
      final syncResult = await StorageService.syncData(_username, forceFullSync: true);

      if (syncResult['success'] != true) {
        throw Exception(syncResult['error'] ?? '同步未执行，请稍后重试');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        StorageService.triggerRefresh();
        _rescheduleReminders();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 全量同步完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 同步失败: $e')),
        );
      }
    }
  }

  Future<void> _handleLogout({bool force = false}) async {
    bool confirm = force;
    if (!force) {
      confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("退出账号"),
              content: const Text("确定要退出当前账号吗？"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("取消")),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("退出"),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (confirm) {
      await StorageService.clearLoginSession();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false);
      }
    }
  }

  void _showChangePasswordDialog() {
    if (_userId == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ChangePasswordDialog(
        userId: _userId!,
        onLogout: (force) => _handleLogout(force: force),
      ),
    );
  }

  _BreadcrumbObserver _createObserver() {
    return _BreadcrumbObserver(
      onRoutesChanged: (routes) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _nestedRouteNames = routes);
        });
      },
    );
  }

  String _getPaneTitle() {
    switch (_selectedPaneId) {
      case 'account': return '账号与系统公告';
      case 'preference': return '系统与外观';
      case 'animation': return '动画与特效';
      case 'course': return '课表与学期';
      case 'interconnect': return '数据与互联';
      case 'llm_config': return 'AI 助手配置';
      case 'platform': return Platform.isWindows ? 'Windows 专属' : (Platform.isAndroid ? 'Android 专属' : '平台专属');
      case 'notifications': return '通知管理';
      case 'permissions': return '权限管理';
      case 'about': return '关于此应用';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    final paneTitle = _getPaneTitle();
    
    // 构建面包屑标题组件
    Widget titleWidget;
    if (isWide && paneTitle.isNotEmpty) {
      List<Widget> breadcrumbs = [
        InkWell(
          onTap: () {
            // 点击根节点，清空嵌套路由
            _nestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          },
          child: Text('设置 > $paneTitle', style: const TextStyle(fontSize: 18)),
        ),
      ];
      for (int i = 0; i < _nestedRouteNames.length; i++) {
        breadcrumbs.add(const Text(' > ', style: TextStyle(fontSize: 18, color: Colors.grey)));
        breadcrumbs.add(
          InkWell(
            onTap: () {
              // 返回到对应层级
              int popsNeeded = _nestedRouteNames.length - 1 - i;
              for (int j = 0; j < popsNeeded; j++) {
                _nestedNavigatorKey.currentState?.pop();
              }
            },
            child: Text(_nestedRouteNames[i], style: const TextStyle(fontSize: 18)),
          ),
        );
      }
      titleWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: breadcrumbs,
      );
    } else {
      titleWidget = const Text('设置');
    }

    return Scaffold(
      appBar: AppBar(
        title: titleWidget, 
        centerTitle: true,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _isInitialLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 800) {
                    return _buildWideLayout();
                  }
                  return _buildNarrowLayout();
                },
              ),
      ),
    );
  }

  // ===== macOS 风格双栏布局 =====
  Widget _buildWideLayout() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧导航栏 (模仿 macOS 系统设置侧边栏)
        Container(
          width: 280,
          color: isDark ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 账号与公告栏 (可点击)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (_selectedPaneId != 'account') {
                        setState(() {
                          _selectedPaneId = 'account';
                          _selectedRightPaneBuilder = _buildAccountAndAnnouncementsPane;
                          _nestedRouteNames.clear();
                          _nestedNavigatorKey = GlobalKey<NavigatorState>();
                          _breadcrumbObserver = _createObserver();
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedPaneId == 'account' ? theme.colorScheme.primary.withValues(alpha: 0.1) : (isDark ? Colors.white10 : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: _selectedPaneId == 'account' ? Border.all(color: theme.colorScheme.primary, width: 2) : Border.all(color: Colors.transparent, width: 2),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                            child: Text(_username.isNotEmpty ? _username[0].toUpperCase() : '?', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                                Text(_userTier, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // 导航菜单
                _buildMacSidebarItem(
                  id: 'preference',
                  icon: Icons.palette,
                  color: Colors.indigo,
                  title: '系统与外观',
                  widgetBuilder: () => const PreferenceSettingsPage(isEmbedded: true),
                ),
                _buildMacSidebarItem(
                  id: 'animation',
                  icon: Icons.animation,
                  color: Colors.pinkAccent,
                  title: '动画与特效',
                  widgetBuilder: () => const AnimationSettingsPage(isEmbedded: true),
                ),
                _buildMacSidebarItem(
                  id: 'course',
                  icon: Icons.school,
                  color: Colors.teal,
                  title: '课表与学期',
                  widgetBuilder: () => const CourseSettingsPage(isEmbedded: true),
                ),
                _buildMacSidebarItem(
                  id: 'interconnect',
                  icon: Icons.devices,
                  color: Colors.blue,
                  title: '数据与互联',
                  widgetBuilder: () => const InterconnectSettingsPage(isEmbedded: true),
                ),
                _buildMacSidebarItem(
                  id: 'llm_config',
                  icon: Icons.psychology_outlined,
                  color: Colors.deepPurple,
                  title: 'AI 助手配置',
                  widgetBuilder: () => const LLMConfigPage(isEmbedded: true),
                ),
                
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                
                _buildMacSidebarItem(
                  id: 'platform',
                  icon: Icons.stars_rounded,
                  color: Colors.deepPurple,
                  title: Platform.isWindows ? 'Windows 专属' : (Platform.isAndroid ? 'Android 专属' : '平台专属'),
                  widgetBuilder: () => const PlatformSpecificSettingsPage(isEmbedded: true),
                ),
                _buildMacSidebarItem(
                  id: 'notifications',
                  icon: Icons.notifications,
                  color: Colors.amber,
                  title: '通知管理',
                  widgetBuilder: () => const NotificationSettingsPage(isEmbedded: true),
                ),
                _buildMacSidebarItem(
                  id: 'permissions',
                  icon: Icons.security,
                  color: Colors.red,
                  title: '权限管理',
                  widgetBuilder: () => const PermissionSettingsPage(isEmbedded: true),
                ),
                _buildMacSidebarItem(
                  id: 'about',
                  icon: Icons.info,
                  color: Colors.grey,
                  title: '关于此应用',
                  widgetBuilder: () => const AboutScreen(isEmbedded: true),
                ),
              ],
            ),
          ),
        ),
        
        const VerticalDivider(width: 1, thickness: 1),
        
        // 右侧详情页
        Expanded(
          child: Container(
            color: theme.colorScheme.surface,
            child: ClipRRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Navigator(
                  key: _nestedNavigatorKey,
                  observers: [_breadcrumbObserver],
                  onGenerateRoute: (settings) {
                    return MaterialPageRoute(
                      settings: const RouteSettings(name: '/'),
                      builder: (context) {
                        return _selectedRightPaneBuilder?.call() ?? const Center(child: Text('请在左侧选择设置项'));
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMacSidebarItem({
    required String id,
    required IconData icon,
    required Color color,
    required String title,
    required Widget Function() widgetBuilder,
  }) {
    final bool isSelected = _selectedPaneId == id;
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? theme.colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (_selectedPaneId != id) {
              setState(() {
                _selectedPaneId = id;
                _selectedRightPaneBuilder = widgetBuilder;
                _nestedRouteNames.clear();
                _nestedNavigatorKey = GlobalKey<NavigatorState>();
                _breadcrumbObserver = _createObserver();
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.transparent : color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon, 
                    size: 16, 
                    color: isSelected ? theme.colorScheme.onPrimary : color
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? theme.colorScheme.onPrimary : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== 窄屏单栏布局 (原版) =====
  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAnnouncementPanel(),
          const SizedBox(height: 16),
          AccountSection(
            username: _username,
            userId: _userId,
            userTier: _userTier,
            syncProgress: _syncProgress,
            isLoadingStatus: _isLoadingStatus,
            onRefreshStatus: _fetchAccountStatus,
            onForceFullSync: _forceFullSync,
            onLogout: () => _handleLogout(force: false),
            onChangePassword: _showChangePasswordDialog,
          ),
          SyncSettingsSection(username: _username),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
            child: Text('核心设置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined, color: Colors.indigo),
                  title: const Text('系统与外观'),
                  subtitle: const Text('主题、动画、存储清理、数据迁移与高级选项'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const PreferenceSettingsPage())),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.animation_outlined, color: Colors.pinkAccent),
                  title: const Text('动画与特效'),
                  subtitle: const Text('页面切换动画、过渡效果及性能选项'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const AnimationSettingsPage())),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.school_outlined, color: Colors.teal),
                  title: const Text('课表与学期'),
                  subtitle: const Text('教务导入、上课时间、学期进度条等'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const CourseSettingsPage())),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.devices_outlined, color: Colors.blue),
                  title: const Text('数据与互联'),
                  subtitle: const Text('局域网同步、手环、日历双向同步'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const InterconnectSettingsPage())),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.psychology_outlined, color: Colors.deepPurple),
                  title: const Text('AI 助手配置'),
                  subtitle: const Text('大模型 API 及智能解析配置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const LLMConfigPage())),
                ),
              ],
            ),
          ),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.stars_rounded, color: Colors.deepPurple),
                  title: Text(Platform.isWindows ? 'Windows 专属设置' : (Platform.isAndroid ? 'Android 专属设置' : '平台专属设置')),
                  subtitle: Text(Platform.isWindows ? '悬浮窗、屏幕时间、灵动岛' : '活动提醒、权限优化等'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const PlatformSpecificSettingsPage())),
                ),

                ListTile(
                  leading: const Icon(Icons.notifications_outlined, color: Colors.amber),
                  title: const Text('通知管理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const NotificationSettingsPage())),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.security_outlined, color: Colors.red),
                  title: const Text('权限管理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const PermissionSettingsPage())),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.grey),
                  title: const Text('关于此应用'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, PageTransitions.slideHorizontal(const AboutScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _BreadcrumbObserver extends NavigatorObserver {
  final Function(List<String>) onRoutesChanged;
  final List<String> _routeNames = [];

  _BreadcrumbObserver({required this.onRoutesChanged});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != null && route.settings.name != '/') {
      _routeNames.add(route.settings.name!);
      onRoutesChanged(List.from(_routeNames));
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != null && route.settings.name != '/') {
      if (_routeNames.isNotEmpty) {
        _routeNames.removeLast();
      }
      onRoutesChanged(List.from(_routeNames));
    }
  }
}
