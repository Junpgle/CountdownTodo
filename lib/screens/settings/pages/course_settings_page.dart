import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/course_service.dart';
import '../../../services/reminder_schedule_service.dart';
import '../../../storage_service.dart';
import '../../../services/api_service.dart';
import '../../../course_import/handlers/course_import_handler.dart';
import '../../../course_import/course_import_preflight.dart';
import '../../../course_import/course_schedule_semantics.dart';
import '../../../course_import/widgets/course_adaptation_screen.dart';
import '../../../course_import/widgets/course_time_repair_dialog.dart';
import '../../course_calendar_adjustment_screen.dart';
import '../../../models.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/settings_navigation.dart';
import '../../../widgets/floating_glass_control.dart';
import '../../../widgets/settings_focus_page.dart';
import '../../../utils/app_dialogs.dart';
import '../../../utils/time_utils.dart';

part 'course_settings/course_settings_cloud.dart';
part 'course_settings/course_settings_semesters.dart';

class CourseSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const CourseSettingsPage({
    super.key,
    this.initialTarget,
    this.isEmbedded = false,
  });

  @override
  State<CourseSettingsPage> createState() => _CourseSettingsPageState();
}

class _CourseSettingsPageState extends State<CourseSettingsPage>
    with
        SettingsNavigationMixin<CourseSettingsPage>,
        SettingsTargetHighlightMixin<CourseSettingsPage> {
  final Map<String, GlobalKey> _itemKeys = {
    'webview_import': GlobalKey(),
    'smart_import': GlobalKey(),
    'course_sync': GlobalKey(),
    'course_upload': GlobalKey(),
    'course_adapt': GlobalKey(),
    'course_calendar_adjustment': GlobalKey(),
    'semester_progress': GlobalKey(),
    'semester_start': GlobalKey(),
    'semester_end': GlobalKey(),
    'semester_sync': GlobalKey(),
    'semester_management': GlobalKey(), // 新增：学期管理
  };

  bool _isLoading = true;
  bool _initialEditorOpened = false;

  String _username = '';
  int? _userId;

  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  // 多学期支持
  List<SemesterInfo> _semesters = [];
  String _activeSemesterId = 'default';

  late CourseImportHandler _courseImportHandler;

  bool _loadingDialogOpen = false;
  Route<void>? _loadingDialogRoute;
  Future<void>? _loadingDialogFuture;
  Future<void>? _loadingDialogReady;
  NavigatorState? _loadingDialogNavigator;

  void _mutateState(VoidCallback fn) => setState(fn);

  @override
  Map<String, GlobalKey> get settingsNavigationKeyStore => _itemKeys;

  @override
  bool get isEmbeddedSettingsPage => widget.isEmbedded;

  @override
  GlobalKey? resolveSettingsTargetKey(String target) => _itemKeys[target];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    scheduleInitialSettingsTarget(widget.initialTarget);
  }

  @override
  void dispose() {
    final route = _loadingDialogRoute;
    final navigator = _loadingDialogNavigator;
    if (route != null &&
        navigator != null &&
        navigator.mounted &&
        route.isActive) {
      navigator.removeRoute(route);
    }
    _loadingDialogOpen = false;
    _loadingDialogRoute = null;
    _loadingDialogFuture = null;
    _loadingDialogReady = null;
    _loadingDialogNavigator = null;
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString(StorageService.keyCurrentUser) ?? '';
    _userId = prefs.getInt('current_user_id');

    bool sEnabled = await StorageService.getSemesterEnabled();
    DateTime? sStart = await StorageService.getSemesterStart();
    DateTime? sEnd = await StorageService.getSemesterEnd();

    // 加载多学期数据
    _semesters = await StorageService.getSemesters();
    _activeSemesterId = await StorageService.getActiveSemesterId();

    if (!mounted) return;

    _courseImportHandler = CourseImportHandler(
      context: context,
      username: _username,
      onRescheduleReminders: _rescheduleReminders,
      showMessage: (msg) {
        if (!mounted) return;
        AppSnackBars.showSnackBar(context, SnackBar(content: Text(msg)));
      },
    );

    if (mounted) {
      setState(() {
        _semesterEnabled = sEnabled;
        _semesterStart = sStart;
        _semesterEnd = sEnd;
        _isLoading = false;
      });
      unawaited(_openInitialEditor());
    }
  }

  Future<void> _openInitialEditor() async {
    if (_initialEditorOpened ||
        !{
          'semester_start',
          'semester_end',
          'semester_name',
        }.contains(widget.initialTarget)) {
      return;
    }
    _initialEditorOpened = true;
    for (var attempt = 0; attempt < 90 && mounted; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null ||
          (route.isCurrent &&
              !route.offstage &&
              (route.animation == null ||
                  route.animation!.status == AnimationStatus.completed))) {
        break;
      }
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    final focusLabel = switch (widget.initialTarget) {
      'semester_end' => '放假日期:',
      'semester_name' => '学期名称',
      _ => '开学日期:',
    };
    if (_semesters.isEmpty) {
      await _showAddSemesterDialog(focusLabel: focusLabel);
    } else {
      final current =
          _semesters
              .where((item) => item.id == _activeSemesterId)
              .firstOrNull ??
          _semesters.first;
      await _editSemester(current, focusLabel: focusLabel);
    }
  }

  Future<void> _rescheduleReminders() async {
    if (_username.isEmpty || _username == "未登录" || _username == "加载中...") {
      return;
    }
    try {
      final todos = await StorageService.getTodos(_username);
      await ReminderScheduleService.scheduleAll(
        todos: todos,
        courses: const <CourseItem>[],
        loadCourses: (from, to) =>
            CourseService.getCoursesForDateRange(_username, from: from, to: to),
        expectedUsername: _username,
        force: true,
      );
    } catch (e) {
      debugPrint('[CourseSettings] 重新调度课程提醒失败: $e');
    }
  }

  void _showLoadingDialog(String message) {
    if (!mounted || _loadingDialogOpen) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );

    _loadingDialogOpen = true;
    _loadingDialogRoute = route;
    _loadingDialogNavigator = navigator;
    _loadingDialogReady = Future<void>.delayed(Duration.zero);
    final dialogFuture = navigator.push<void>(route);
    _loadingDialogFuture = dialogFuture;
    unawaited(_observeLoadingDialog(route, dialogFuture));
  }

  Future<void> _observeLoadingDialog(
    Route<void> route,
    Future<void> dialogFuture,
  ) async {
    try {
      await dialogFuture;
    } catch (error, stackTrace) {
      debugPrint('⚠️ 课表设置进度弹窗异常结束: $error\n$stackTrace');
    } finally {
      if (identical(_loadingDialogRoute, route)) {
        _loadingDialogOpen = false;
        _loadingDialogRoute = null;
        _loadingDialogFuture = null;
        _loadingDialogReady = null;
        _loadingDialogNavigator = null;
      }
    }
  }

  Future<void> _closeLoadingDialog() async {
    if (!_loadingDialogOpen) return;

    final route = _loadingDialogRoute;
    final dialogFuture = _loadingDialogFuture;
    final ready = _loadingDialogReady;
    if (route == null) return;
    if (ready != null) await ready;

    final navigator = _loadingDialogNavigator;
    if (identical(_loadingDialogRoute, route) &&
        navigator != null &&
        navigator.mounted &&
        route.isActive) {
      navigator.removeRoute(route);
    }

    if (dialogFuture != null) {
      try {
        await dialogFuture;
      } catch (_) {
        // The observer records unexpected route failures.
      }
    }
  }

  Widget _buildTile({required String targetId, required Widget child}) {
    final bool isHighlighted = highlightTarget == targetId;
    return Container(
      key: _itemKeys[targetId],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = AppPlatform.isWeb;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('课表与学期'),
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: ListView(
          padding: EdgeInsets.only(
            top: widget.isEmbedded
                ? 0
                : floatingGlassSettingsContentTopInset(context),
          ),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 16.0),
              child: Text(
                '学期管理',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            _buildTile(
              targetId: 'semester_management',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 学期列表
                  if (_semesters.isNotEmpty)
                    ..._semesters.map(
                      (semester) => _buildSemesterTile(semester),
                    ),
                  // 添加新学期按钮
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 6.0,
                    ),
                    child: OutlinedButton.icon(
                      onPressed: _showAddSemesterDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('添加新学期'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  // 清除学期课程数据按钮
                  if (_semesters.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: TextButton.icon(
                        onPressed: _showClearSemesterCoursesDialog,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('清除学期课程数据'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
              child: Text(
                '学期设置',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            _buildTile(
              targetId: 'semester_progress',
              child: LiquidGlassSwitchListTile(
                secondary: const Icon(Icons.linear_scale),
                title: const Text('首页学期进度条'),
                value: _semesterEnabled,
                onChanged: (val) {
                  setState(() => _semesterEnabled = val);
                  StorageService.saveAppSetting(
                    StorageService.keySemesterProgressEnabled,
                    val,
                  );
                },
              ),
            ),
            const Divider(height: 1, indent: 72),
            _buildTile(
              targetId: 'course_calendar_adjustment',
              child: ListTile(
                leading: const Icon(
                  Icons.event_repeat_outlined,
                  color: Colors.deepPurple,
                ),
                title: const Text('放假与调休'),
                subtitle: const Text('设置停课日期，以及补哪一天的课'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await openSettingsPage(
                    'course_calendar_adjustment',
                    CourseCalendarAdjustmentScreen(
                      isEmbedded: widget.isEmbedded,
                    ),
                    settings: const RouteSettings(name: '校历偏移动态调整'),
                  );
                  _rescheduleReminders();
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
              child: Text(
                '课程导入与同步',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                bottom: 8.0,
              ),
              child: GridView.count(
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.2,
                children: [
                  _buildActionCard(
                    id: 'webview_import',
                    icon: isWeb
                        ? Icons.open_in_browser
                        : Icons.language_outlined,
                    title: isWeb ? '打开教务网页' : '在线教务导入',
                    subtitle: isWeb ? '导出文件后导入' : '推荐方式',
                    color: Colors.teal,
                    onTap: () => _courseImportHandler.importFromWebView(
                      sourceKey: settingsNavigationKey('webview_import'),
                      isEmbedded: widget.isEmbedded,
                    ),
                  ),
                  _buildActionCard(
                    id: 'smart_import',
                    icon: Icons.file_upload_outlined,
                    title: '本地智能导入',
                    subtitle: '自动嗅探格式',
                    color: Colors.indigo,
                    onTap: _courseImportHandler.smartImportCourse,
                  ),
                  _buildActionCard(
                    id: 'course_sync',
                    icon: Icons.cloud_download_outlined,
                    title: '从云端获取',
                    subtitle: '覆盖本地课表',
                    color: Colors.green,
                    onTap: _fetchCoursesFromCloud,
                  ),
                  _buildActionCard(
                    id: 'course_upload',
                    icon: Icons.cloud_upload_outlined,
                    title: '上传到云端',
                    subtitle: '多端备份同步',
                    color: Theme.of(context).colorScheme.primary,
                    onTap: _uploadCoursesToCloud,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
              child: Text(
                '请求课表适配',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            _buildTile(
              targetId: 'course_adapt',
              child: ListTile(
                leading: const Icon(Icons.auto_awesome, color: Colors.orange),
                title: const Text('我要请求开发者适配！'),
                subtitle: const Text('如果没有你的学校，点此申请'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '推荐',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                onTap: () {
                  openSettingsPage(
                    'course_adapt',
                    CourseAdaptationScreen(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '课程表适配机制'),
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return _buildTile(
      targetId: id,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
