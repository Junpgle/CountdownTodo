import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'dart:isolate';
import '../services/tai_service.dart';
import '../storage_service.dart';
import '../update_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/page_transitions.dart';
import 'feature_guide_screen.dart';
import '../services/course_service.dart';
import '../services/reminder_schedule_service.dart';
import '../services/float_window_service.dart';
import '../services/island_data_provider.dart';
import '../windows_island/island_manager.dart';

// 引入拆分的设置组件
import 'settings/widgets/account_section.dart';
import 'settings/widgets/course_section.dart';
import 'settings/widgets/semester_section.dart';
import 'settings/server_choice_page.dart';
import 'settings/widgets/preference_section.dart';
import 'settings/widgets/permission_section.dart';
import 'settings/widgets/advanced_section.dart';
import 'settings/widgets/system_section.dart';
import 'settings/notification_settings_page.dart';
import 'about_screen.dart';
import 'animation_settings_page.dart';
import 'band_sync_screen.dart';
import 'settings/lan_sync_screen.dart';

// 引入拆分的弹窗组件
import 'settings/dialogs/change_password_dialog.dart';
import 'settings/dialogs/home_section_manager_dialog.dart';
import 'settings/dialogs/migration_dialog.dart';
import 'settings/dialogs/island_priority_dialog.dart';

// 引入逻辑处理器
import 'settings/handlers/course_import_handler.dart';
import 'settings/handlers/permission_handler.dart';
import 'settings/handlers/storage_management_handler.dart';
import '../services/animation_config_service.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send =
      IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const platform =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');
  final ReceivePort _port = ReceivePort();

  String _islandStatus = "点击检测设备是否支持";
  String _liveUpdatesStatus = "点击检测或去开启 (Android 16+)";
  bool _isCheckingUpdate = false;
  String _taiDbPath = '';
  int _floatWindowStyle = 0; // 0: 经典, 1: 灵动岛, 2: 关闭

  // 逻辑处理器
  late CourseImportHandler _courseImportHandler;
  late PermissionHandler _permissionHandler;
  late StorageManagementHandler _storageManagementHandler;

  // 用户与偏好设置状态
  String _username = "加载中...";
  int? _userId;
  int _syncInterval = 0;
  String _themeMode = 'system';
  String _noCourseBehavior = 'keep';
  String _serverChoice = 'aliyun';
  int _llmRetryCount = 3;

  // 学期进度状态
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  // 账户状态：等级与同步额度
  String _userTier = "加载中...";
  double _syncProgress = 0.0;
  bool _isLoadingStatus = true;

  // 分区展开/折叠状态
  bool _accountExpanded = true;
  bool _courseExpanded = true;
  bool _semesterExpanded = true;
  bool _preferenceExpanded = true;
  bool _notificationExpanded = true;
  bool _permissionExpanded = true;
  bool _advancedExpanded = true;
  bool _systemExpanded = true;
  bool _aboutExpanded = true;
  bool _animationExpanded = true;

  // 动画设置状态
  bool _animationsEnabled = true;
  bool _motionBlurEnabled = false;
  bool _layerBlurEnabled = false;
  bool _lazyLoadEnabled = true;
  bool _screenRadiusEnabled = true;
  bool _predictiveBackEnabled = true;
  int _animationDuration = 350;

  // 处理器状态代理
  String _cacheSizeStr = "计算中...";
  final Map<String, PermissionStatus?> _permissionStatuses = {};
  bool _isCheckingPermissions = false;

  @override
  void initState() {
    super.initState();
    _courseImportHandler = CourseImportHandler(
      context: context,
      semesterStart: _semesterStart,
      onRescheduleReminders: _rescheduleReminders,
      showMessage: (msg) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg))),
    );
    _permissionHandler = PermissionHandler(
      context: context,
      platform: platform,
      onUpdateChecking: (val) => setState(() => _isCheckingPermissions = val),
      onUpdateStatuses: (results) {
        setState(() {
          for (final entry in results.entries) {
            _permissionStatuses[entry.key] = entry.value;
          }
        });
      },
    );
    _storageManagementHandler = StorageManagementHandler(
      context: context,
      onUpdateCacheSize: (val) {
        if (mounted) {
          setState(() => _cacheSizeStr = val);
        }
      },
      showLoading: (msg) => _showLoadingDialog(context, msg),
      closeLoading: () => _closeLoadingDialog(context),
      showMessage: (msg) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg))),
    );

    _loadSettings().then((_) {
      _fetchAccountStatus();
      // 在加载完设置后同步更新 handler 的 semesterStart
      _courseImportHandler = CourseImportHandler(
        context: context,
        semesterStart: _semesterStart,
        onRescheduleReminders: _rescheduleReminders,
        showMessage: (msg) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg))),
      );
    });
    _setupDownloadListener();
    _storageManagementHandler.calculateCacheSize();
    _permissionHandler.checkAllPermissions();
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close();
    super.dispose();
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
          DateTime.fromMillisecondsSinceEpoch(lastSyncTime, isUtc: true)
              .toLocal();
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
        if (mounted)
          setState(() {
            _userTier = "Free";
            _isLoadingStatus = false;
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _userTier = "未知";
          _isLoadingStatus = false;
        });
    }
  }

  void _setupDownloadListener() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');

    _port.listen((dynamic data) {
      String id = data[0];
      DownloadTaskStatus status = DownloadTaskStatus.fromInt(data[1]);

      if (status == DownloadTaskStatus.complete) {
        _handleDownloadCompleted(id);
      }
    });

    FlutterDownloader.registerCallback(downloadCallback);
  }

  Future<void> _handleDownloadCompleted(String taskId) async {
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks == null) return;
    try {
      final task = tasks.firstWhere((t) => t.taskId == taskId);
      if (task.filename != null) {
        final String fullPath = "${task.savedDir}/${task.filename}";
        await Future.delayed(const Duration(milliseconds: 1500));
        await UpdateService.installPackage(fullPath);
      }
    } catch (e) {}
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    int interval = await StorageService.getSyncInterval();
    String theme = await StorageService.getThemeMode();
    String serverUrlChoice = await StorageService.getServerChoice();
    int llmRetryCount = await StorageService.getLLMRetryCount();

    bool sEnabled = await StorageService.getSemesterEnabled();
    DateTime? sStart = await StorageService.getSemesterStart();
    DateTime? sEnd = await StorageService.getSemesterEnd();

    String? noCourseBehaviorPref = prefs.getString('no_course_behavior');
    int style = prefs.getInt('float_window_style') ?? 0;

    final animationsEnabled =
        await AnimationConfigService.isAnimationsEnabled();
    final motionBlurEnabled =
        await AnimationConfigService.isMotionBlurEnabled();
    final layerBlurEnabled = await AnimationConfigService.isLayerBlurEnabled();
    final lazyLoadEnabled = await AnimationConfigService.isLazyLoadEnabled();
    final screenRadiusEnabled =
        await AnimationConfigService.isScreenRadiusEnabled();
    final predictiveBackEnabled =
        await AnimationConfigService.isPredictiveBackEnabled();
    final animationDuration =
        await AnimationConfigService.getAnimationDuration();

    setState(() {
      _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? "未登录";
      _userId = prefs.getInt('current_user_id');
      _syncInterval = interval;
      _themeMode = theme;
      _serverChoice = serverUrlChoice;
      _llmRetryCount = llmRetryCount;
      _semesterEnabled = sEnabled;
      _semesterStart = sStart;
      _semesterEnd = sEnd;
      if (noCourseBehaviorPref != null) {
        _noCourseBehavior = noCourseBehaviorPref;
      }
      _floatWindowStyle = style;
      _animationsEnabled = animationsEnabled;
      _motionBlurEnabled = motionBlurEnabled;
      _layerBlurEnabled = layerBlurEnabled;
      _lazyLoadEnabled = lazyLoadEnabled;
      _screenRadiusEnabled = screenRadiusEnabled;
      _predictiveBackEnabled = predictiveBackEnabled;
      _animationDuration = animationDuration;
    });
    if (Platform.isWindows) {
      final taiPath = await TaiService.getSavedDbPath() ??
          await TaiService.detectDefaultPath();
      if (taiPath != null) await TaiService.saveDbPath(taiPath);
      setState(() => _taiDbPath = taiPath ?? '');
    }
  }

  Future<void> _pickSemesterDate(bool isStart) async {
    DateTime initialDate =
        (isStart ? _semesterStart : _semesterEnd) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: isStart ? "选择开学日期" : "选择放假日期",
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _semesterStart = picked;
          StorageService.saveAppSetting(
              StorageService.KEY_SEMESTER_START, picked.toIso8601String());
        } else {
          _semesterEnd = picked;
          StorageService.saveAppSetting(
              StorageService.KEY_SEMESTER_END, picked.toIso8601String());
        }
      });
      if (_userId != null) {
        final startMs = _semesterStart != null
            ? DateTime(_semesterStart!.year, _semesterStart!.month,
                    _semesterStart!.day)
                .millisecondsSinceEpoch
            : null;
        final endMs = _semesterEnd != null
            ? DateTime(
                    _semesterEnd!.year, _semesterEnd!.month, _semesterEnd!.day)
                .millisecondsSinceEpoch
            : null;
        ApiService.uploadUserSettings(
            semesterStartMs: startMs, semesterEndMs: endMs);
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

  void _showHomeSectionManager() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const HomeSectionManagerDialog(),
    );
    if (result == true) {
      _loadSettings();
    }
  }

  void _showIslandPriorityDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => const IslandPriorityDialog(),
    );
    if (changed == true) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✅ 灵动岛优先级已更新')));
      }
      FloatWindowService
          .invalidateCache(); // invalidate all caches including priority
      FloatWindowService.update(forceReset: true); // trigger a re-render
    }
  }

  Future<void> _checkAndOpenLiveUpdates() async {
    try {
      final bool hasPermission =
          await platform.invokeMethod('checkLiveUpdatesPermission') ?? true;
      if (!hasPermission) {
        setState(() => _liveUpdatesStatus = "权限未开启，尝试跳转设置...");
        final bool opened =
            await platform.invokeMethod('openLiveUpdatesSettings') ?? false;

        if (opened) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('请在设置中打开"推广的通知/实时更新"权限'),
                duration: Duration(seconds: 3)),
          );
        } else {
          setState(() => _liveUpdatesStatus = "跳转失败，设备可能不是 Android 16+");
        }
      } else {
        setState(() => _liveUpdatesStatus = "✅ 已拥有实时通知权限");
      }
    } on PlatformException catch (e) {
      setState(() => _liveUpdatesStatus = "检测失败: '${e.message}'.");
    }
  }

  Future<void> _checkIslandSupport() async {
    try {
      final bool result = await platform.invokeMethod('checkIslandSupport');
      setState(() {
        if (result) {
          _islandStatus = "✅ 设备已支持超级岛！";
        } else {
          _islandStatus = "❌ 不支持，或未开启状态栏显示权限";
        }
      });
    } on PlatformException catch (e) {
      setState(() => _islandStatus = "检测失败: '${e.message}'.");
    }
  }

  Future<void> _testCourseNotification() async {
    final dashboardData = await CourseService.getDashboardCourses();
    List<CourseItem> courses =
        (dashboardData['courses'] as List?)?.cast<CourseItem>() ?? [];

    CourseItem? testCourse;
    if (courses.isNotEmpty) {
      testCourse = courses.first;
    } else {
      final allCourses = await CourseService.getAllCourses();
      if (allCourses.isNotEmpty) {
        testCourse = allCourses.first;
      }
    }

    if (testCourse != null) {
      NotificationService.showCourseLiveActivity(
        courseName: testCourse.courseName,
        room: testCourse.roomName,
        timeStr:
            '${testCourse.formattedStartTime} - ${testCourse.formattedEndTime}',
        teacher: testCourse.teacherName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('✅ 已发送测试实时通知，请查看状态栏')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 尚未导入课表数据，请先在"课程设置"中导入')));
      }
    }
  }

  Future<void> _forceFullSync() async {
    if (_username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录账号')),
      );
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认')),
        ],
      ),
    );
    if (confirm != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('🔄 正在全量同步...'), duration: Duration(seconds: 10)),
    );

    try {
      await StorageService.resetSyncTime(_username);
      await StorageService.syncData(_username, forceFullSync: true);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        _rescheduleReminders(); // 🐘 新增：全量同步后重新调度闹钟
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

  Future<void> _uploadCoursesToCloud() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录账号')),
      );
      return;
    }

    final allCourses = await CourseService.getAllCourses();
    if (allCourses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有课表数据可上传')),
      );
      return;
    }

    bool confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("上传课表到云端"),
            content: const Text("这将覆盖你云端的所有课表数据。\n\n用于与电脑或其他设备同步。\n\n是否继续？"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("取消")),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("上传")),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    _showLoadingDialog(context, "正在同步到云端...");

    final result = await CourseService.syncCoursesToCloud(_userId!);

    if (result['success'] == true) {
      final startMs = _semesterStart != null
          ? DateTime(_semesterStart!.year, _semesterStart!.month,
                  _semesterStart!.day)
              .millisecondsSinceEpoch
          : null;
      final endMs = _semesterEnd != null
          ? DateTime(_semesterEnd!.year, _semesterEnd!.month, _semesterEnd!.day)
              .millisecondsSinceEpoch
          : null;
      await ApiService.uploadUserSettings(
          semesterStartMs: startMs, semesterEndMs: endMs);
    }

    if (!mounted) return;
    _closeLoadingDialog(context);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 课表已成功同步到云端')),
      );
      _fetchAccountStatus();
    } else if (result['isLimitExceeded'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? '今日同步次数已达上限')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? '同步失败')),
      );
    }
  }

  Future<void> _fetchCoursesFromCloud() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录账号')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端获取课表'),
        content: const Text('这将用云端课表数据覆盖本地课表。\n\n本地已有的课表数据将被替换。\n\n是否继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('获取')),
        ],
      ),
    );
    if (confirm != true) return;

    _showLoadingDialog(context, "正在获取云端数据...");

    try {
      // 🚀 1. 并发拉取：同时获取【学期设置】和【课表数据】
      final userSettingsFuture = ApiService.fetchUserSettings();
      final coursesFuture = ApiService.fetchCourses(_userId!);

      final results = await Future.wait([userSettingsFuture, coursesFuture]);
      final Map<String, dynamic>? userSettings =
          results[0] as Map<String, dynamic>?;
      final List<dynamic> data = results[1] as List<dynamic>;

      if (!mounted) return;

      // 🚀 2. 如果云端有学期设置，优先同步并覆盖到本地
      if (userSettings != null) {
        final prefs = await SharedPreferences.getInstance();

        if (userSettings['semester_start'] != null) {
          _semesterStart = DateTime.fromMillisecondsSinceEpoch(
              userSettings['semester_start']);
          await prefs.setString(StorageService.KEY_SEMESTER_START,
              _semesterStart!.toIso8601String());
        }
        if (userSettings['semester_end'] != null) {
          _semesterEnd =
              DateTime.fromMillisecondsSinceEpoch(userSettings['semester_end']);
          await prefs.setString(
              StorageService.KEY_SEMESTER_END, _semesterEnd!.toIso8601String());
        }

        // 刷新页面状态，让 UI 立刻响应云端拉取下来的新日期
        setState(() {});
      }

      _closeLoadingDialog(context);

      if (data.isNotEmpty) {
        // 🚀 3. 再次校验：如果同步了设置后，_semesterStart 依然为空（说明云端和本地都没配过），再进行拦截
        if (_semesterStart == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ 云端与本地均未配置开学日期，无法计算课表具体日期')),
          );
          return;
        }

        final DateTime semesterMonday = _semesterStart!.subtract(
          Duration(days: _semesterStart!.weekday - 1),
        );

        final courses = data.map<CourseItem>((c) {
          final int weekIndex = (c['week_index'] as num?)?.toInt() ?? 1;
          final int weekday = (c['weekday'] as num?)?.toInt() ?? 1;

          final DateTime courseDate = semesterMonday
              .add(Duration(days: (weekIndex - 1) * 7 + (weekday - 1)));
          final String dateStr = DateFormat('yyyy-MM-dd').format(courseDate);

          return CourseItem(
            courseName: c['course_name'] ?? '',
            roomName: c['room_name'] ?? '',
            teacherName: c['teacher_name'] ?? '',
            startTime: (c['start_time'] as num?)?.toInt() ?? 0,
            endTime: (c['end_time'] as num?)?.toInt() ?? 0,
            weekday: weekday,
            weekIndex: weekIndex,
            lessonType: c['lesson_type'] ?? '',
            date: dateStr,
          );
        }).toList();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'course_schedule_json',
          jsonEncode(courses.map((c) => c.toJson()).toList()),
        );

        if (mounted) {
          _rescheduleReminders(); // 🐘 新增：拉取后重新调度闹钟
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ 成功从云端同步 ${courses.length} 条课程与学期设置')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 获取失败，云端暂无课表数据')),
        );
      }
    } catch (e) {
      if (mounted) {
        _closeLoadingDialog(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 发生错误: $e')),
        );
      }
    }
  }

  // Removed unused _getAuthToken helper

  Future<void> _checkUpdatesAndNotices() async {
    setState(() => _isCheckingUpdate = true);
    await UpdateService.checkUpdateAndPrompt(context, isManual: true);
    if (mounted) setState(() => _isCheckingUpdate = false);
  }

  Future<void> _pickTaiDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite'],
      dialogTitle: '选择 Tai 数据库文件',
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final valid = await TaiService.validateDb(path);

    if (!valid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 无效的 Tai 数据库文件')),
        );
      }
      return;
    }

    await TaiService.saveDbPath(path);
    setState(() => _taiDbPath = path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 数据库路径已保存')),
      );
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
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("取消")),
                FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: Colors.redAccent),
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

  // Helper method to show a persistent loading dialog
  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
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
  }

  // Helper method to close the loading dialog
  void _closeLoadingDialog(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ─── 重新调度所有保活提醒 ──────────────────────────────────────
  Future<void> _rescheduleReminders() async {
    if (_username.isEmpty || _username == "未登录") return;
    try {
      final todos = await StorageService.getTodos(_username);
      final courses = await CourseService.getAllCourses();
      await ReminderScheduleService.scheduleAll(todos: todos, courses: courses);
    } catch (e) {}
  }

  // ─── 一键迁移弹窗逻辑 ──────────────────────────────────────
  Future<void> _showMigrationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MigrationDialog(
        onSuccess: () => _fetchAccountStatus(),
      ),
    );
  }

  // ─── 动画设置区块 ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 宽屏阈值：768px 以上切换为双栏布局
          final bool isWide = constraints.maxWidth >= 768;

          if (isWide) {
            return _buildWideLayout();
          } else {
            return _buildNarrowLayout();
          }
        },
      ),
    );
  }

  // ─── 窄屏：单列 ListView（原始布局）───────────────────────────────
  Widget _buildNarrowLayout() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildExpandableSection(
          title: '账户管理',
          icon: Icons.person_outline,
          expanded: _accountExpanded,
          onToggle: () => setState(() => _accountExpanded = !_accountExpanded),
          child: AccountSection(
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
        ),
        _buildExpandableSection(
          title: '课程管理',
          icon: Icons.school_outlined,
          expanded: _courseExpanded,
          onToggle: () => setState(() => _courseExpanded = !_courseExpanded),
          child: CourseSection(
            onUploadCourses: _uploadCoursesToCloud,
            onSmartImport: _courseImportHandler.smartImportCourse,
            onWebViewImport: _courseImportHandler.importFromWebView,
            onFetchFromCloud: _fetchCoursesFromCloud,
            noCourseBehavior: _noCourseBehavior,
            onNoCourseBehaviorChanged: (val) {
              if (val != null) {
                setState(() => _noCourseBehavior = val);
                SharedPreferences.getInstance().then(
                    (prefs) => prefs.setString('no_course_behavior', val));
              }
            },
          ),
        ),
        _buildExpandableSection(
          title: '学期设置',
          icon: Icons.date_range_outlined,
          expanded: _semesterExpanded,
          onToggle: () =>
              setState(() => _semesterExpanded = !_semesterExpanded),
          child: SemesterSection(
            semesterEnabled: _semesterEnabled,
            onSemesterEnabledChanged: (val) {
              setState(() => _semesterEnabled = val);
              StorageService.saveAppSetting(
                  StorageService.KEY_SEMESTER_PROGRESS_ENABLED, val);
            },
            semesterStart: _semesterStart,
            semesterEnd: _semesterEnd,
            onPickSemesterDate: _pickSemesterDate,
            onFetchFromCloud: _fetchCoursesFromCloud,
          ),
        ),
        _buildExpandableSection(
          title: '偏好设置',
          icon: Icons.settings_outlined,
          expanded: _preferenceExpanded,
          onToggle: () =>
              setState(() => _preferenceExpanded = !_preferenceExpanded),
          child: PreferenceSection(
            onManageHomeSections: _showHomeSectionManager,
            syncInterval: _syncInterval,
            onSyncIntervalChanged: (val) {
              if (val != null) {
                setState(() => _syncInterval = val);
                StorageService.saveAppSetting(
                    StorageService.KEY_SYNC_INTERVAL, val);
              }
            },
            serverChoice: _serverChoice,
            onServerChoiceTap: () {
              Navigator.push(
                context,
                PageTransitions.slideHorizontal(
                  ServerChoicePage(
                    initialServerChoice: _serverChoice,
                  ),
                ),
              );
            },
            themeMode: _themeMode,
            onThemeModeChanged: (val) {
              if (val != null) {
                setState(() => _themeMode = val);
                StorageService.saveAppSetting(
                    StorageService.KEY_THEME_MODE, val);
                StorageService.themeNotifier.value = val;
              }
            },
            taiDbPath: _taiDbPath,
            onPickTaiDatabase: _pickTaiDatabase,
            floatWindowStyle: _floatWindowStyle,
            onFloatWindowStyleChanged: Platform.isWindows
                ? (val) async {
                    if (val == null) return;
                    setState(() => _floatWindowStyle = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('float_window_style', val);
                    if (val == 2) {
                      try {
                        IslandDataProvider().invalidateCache();
                        IslandManager().clearIslandCache('island-1');
                      } catch (e) {}
                    } else {
                      debugPrint('[Settings] Creating island (ON)');
                      try {
                        IslandDataProvider().invalidateCache();
                        IslandManager().clearIslandCache('island-1');
                        final winId =
                            await IslandManager().createIsland('island-1');
                        debugPrint('[Settings] Island created, winId: $winId');
                      } catch (e) {
                        debugPrint('[Settings] Create error: $e');
                      }
                      try {
                        await FloatWindowService.update(forceReset: true);
                        debugPrint(
                            '[Settings] FloatWindowService.update called');
                      } catch (e) {
                        debugPrint('[Settings] Update error: $e');
                      }
                    }
                  }
                : null,
            onForceRefreshPressed: Platform.isWindows
                ? () async {
                    try {
                      await StorageService.saveIslandBounds('island-1', {});
                    } catch (_) {}
                    try {
                      IslandDataProvider().invalidateCache();
                    } catch (_) {}
                    try {
                      IslandManager().clearIslandCache('island-1');
                    } catch (_) {}
                    try {
                      await FloatWindowService.update(forceReset: true);
                    } catch (_) {}
                  }
                : null,
            onIslandPriorityPressed:
                Platform.isWindows ? _showIslandPriorityDialog : null,
            llmRetryCount: _llmRetryCount,
            onLLMRetryCountChanged: (val) {
              if (val != null) {
                setState(() => _llmRetryCount = val);
                StorageService.setLLMRetryCount(val);
              }
            },
          ),
        ),
        _buildExpandableSection(
          title: '动画设置',
          icon: Icons.animation_outlined,
          expanded: _animationExpanded,
          onToggle: () =>
              setState(() => _animationExpanded = !_animationExpanded),
          child: Card(
            elevation: 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.animation_outlined, color: Colors.blue),
              title: const Text('动画设置',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('页面切换动画、Container Transform、性能选项'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(
                    const AnimationSettingsPage(),
                  ),
                );
              },
            ),
          ),
        ),
        _buildExpandableSection(
          title: '通知管理',
          icon: Icons.notifications_outlined,
          expanded: _notificationExpanded,
          onToggle: () =>
              setState(() => _notificationExpanded = !_notificationExpanded),
          child: Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined,
                  color: Colors.blueAccent),
              title: const Text('通知管理',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('管理实时活动通知和普通通知的开启/关闭'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(
                    const NotificationSettingsPage(),
                  ),
                );
              },
            ),
          ),
        ),
        _buildExpandableSection(
          title: '权限管理',
          icon: Icons.security_outlined,
          expanded: _permissionExpanded,
          onToggle: () =>
              setState(() => _permissionExpanded = !_permissionExpanded),
          child: PermissionSection(
            permissionDefs: PermissionHandler.permissionDefs,
            permissionStatuses: _permissionStatuses,
            isCheckingPermissions: _isCheckingPermissions,
            onCheckAllPermissions: _permissionHandler.checkAllPermissions,
            onRequestOrOpenPermission:
                _permissionHandler.requestOrOpenPermission,
          ),
        ),
        _buildExpandableSection(
          title: '高级设置',
          icon: Icons.tune_outlined,
          expanded: _advancedExpanded,
          onToggle: () =>
              setState(() => _advancedExpanded = !_advancedExpanded),
          child: AdvancedSection(
            onShowMigrationDialog: _showMigrationDialog,
            onTestCourseNotification: _testCourseNotification,
            liveUpdatesStatus: _liveUpdatesStatus,
            onCheckAndOpenLiveUpdates: _checkAndOpenLiveUpdates,
            islandStatus: _islandStatus,
            onCheckIslandSupport: _checkIslandSupport,
            onOpenBandSync: Platform.isAndroid
                ? () {
                    Navigator.push(
                      context,
                      PageTransitions.slideHorizontal(
                        const BandSyncScreen(),
                      ),
                    );
                  }
                : null,
            onOpenLanSync: () {
              Navigator.push(
                context,
                PageTransitions.slideHorizontal(
                  const LanSyncScreen(),
                ),
              );
            },
          ),
        ),
        _buildExpandableSection(
          title: '系统设置',
          icon: Icons.devices_outlined,
          expanded: _systemExpanded,
          onToggle: () => setState(() => _systemExpanded = !_systemExpanded),
          child: SystemSection(
            onOpenFeatureGuide: () {
              Navigator.push(
                context,
                PageTransitions.slideHorizontal(
                  const FeatureGuideScreen(isManualReview: true),
                ),
              );
            },
            cacheSizeStr: _cacheSizeStr,
            onClearCache: _storageManagementHandler.clearCache,
            onShowStorageAnalysis:
                _storageManagementHandler.showStorageAnalysis,
            isCheckingUpdate: _isCheckingUpdate,
            onCheckUpdates: _checkUpdatesAndNotices,
            onLogout: () => _handleLogout(force: false),
          ),
        ),
        _buildExpandableSection(
          title: '关于此应用',
          icon: Icons.info_outline,
          expanded: _aboutExpanded,
          onToggle: () => setState(() => _aboutExpanded = !_aboutExpanded),
          child: Card(
            elevation: 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.blue),
              title: const Text('关于此应用'),
              subtitle: const Text('版本信息、更新日志、联系我们'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(const AboutScreen()),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildExpandableSection({
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(icon, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: const Icon(Icons.expand_more,
                      size: 20, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: child,
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
          firstCurve: Curves.easeInOut,
          secondCurve: Curves.easeInOut,
          sizeCurve: Curves.easeInOut,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ─── 宽屏：双栏布局 ───────────────────────────────────────────────
  // 左栏：账户、课程、学期
  // 右栏：偏好、权限、高级、系统
  Widget _buildWideLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 左栏 ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                CourseSection(
                  onUploadCourses: _uploadCoursesToCloud,
                  onSmartImport: _courseImportHandler.smartImportCourse,
                  onWebViewImport: Platform.isWindows ? null : _courseImportHandler.importFromWebView,
                  onFetchFromCloud: _fetchCoursesFromCloud,
                  noCourseBehavior: _noCourseBehavior,
                  onNoCourseBehaviorChanged: (val) {
                    if (val != null) {
                      setState(() => _noCourseBehavior = val);
                      SharedPreferences.getInstance().then((prefs) =>
                          prefs.setString('no_course_behavior', val));
                    }
                  },
                ),
                SemesterSection(
                  semesterEnabled: _semesterEnabled,
                  onSemesterEnabledChanged: (val) {
                    setState(() => _semesterEnabled = val);
                    StorageService.saveAppSetting(
                        StorageService.KEY_SEMESTER_PROGRESS_ENABLED, val);
                  },
                  semesterStart: _semesterStart,
                  semesterEnd: _semesterEnd,
                  onPickSemesterDate: _pickSemesterDate,
                  onFetchFromCloud: _fetchCoursesFromCloud,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // ── 右栏 ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PreferenceSection(
                  onManageHomeSections: _showHomeSectionManager,
                  syncInterval: _syncInterval,
                  onSyncIntervalChanged: (val) {
                    if (val != null) {
                      setState(() => _syncInterval = val);
                      StorageService.saveAppSetting(
                          StorageService.KEY_SYNC_INTERVAL, val);
                    }
                  },
                  serverChoice: _serverChoice,
                  onServerChoiceTap: () {
                    Navigator.push(
                      context,
                      PageTransitions.slideHorizontal(
                        ServerChoicePage(
                          initialServerChoice: _serverChoice,
                        ),
                      ),
                    );
                  },
                  themeMode: _themeMode,
                  onThemeModeChanged: (val) {
                    if (val != null) {
                      setState(() => _themeMode = val);
                      StorageService.saveAppSetting(
                          StorageService.KEY_THEME_MODE, val);
                      StorageService.themeNotifier.value = val;
                    }
                  },
                  taiDbPath: _taiDbPath,
                  onPickTaiDatabase: _pickTaiDatabase,
                  floatWindowStyle: _floatWindowStyle,
                  onFloatWindowStyleChanged: Platform.isWindows
                      ? (val) async {
                          if (val == null) return;
                          debugPrint(
                              '[Settings] Float window style changed: $val');
                          setState(() => _floatWindowStyle = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('float_window_style', val);
                          if (val == 2) {
                            debugPrint('[Settings] Disabling island (OFF)');
                            try {
                              IslandDataProvider().invalidateCache();
                              IslandManager().clearIslandCache('island-1');
                            } catch (e) {
                              debugPrint('[Settings] Clear error: $e');
                            }
                          } else {
                            debugPrint('[Settings] Creating island (ON)');
                            try {
                              IslandDataProvider().invalidateCache();
                              IslandManager().clearIslandCache('island-1');
                              final winId = await IslandManager()
                                  .createIsland('island-1');
                              debugPrint(
                                  '[Settings] Island created, winId: $winId');
                            } catch (e) {
                              debugPrint('[Settings] Create error: $e');
                            }
                            try {
                              await FloatWindowService.update(forceReset: true);
                            } catch (e) {
                              debugPrint('[Settings] Update error: $e');
                            }
                          }
                        }
                      : null,
                  onForceRefreshPressed: Platform.isWindows
                      ? () async {
                          debugPrint('[Settings] Force refresh pressed');
                          try {
                            await StorageService.saveIslandBounds(
                                'island-1', {});
                          } catch (_) {}
                          try {
                            IslandDataProvider().invalidateCache();
                          } catch (_) {}
                          try {
                            IslandManager().clearIslandCache('island-1');
                          } catch (_) {}
                          try {
                            await FloatWindowService.update(forceReset: true);
                            debugPrint('[Settings] Force refresh done');
                          } catch (_) {}
                        }
                      : null,
                  onIslandPriorityPressed:
                      Platform.isWindows ? _showIslandPriorityDialog : null,
                  llmRetryCount: _llmRetryCount,
                  onLLMRetryCountChanged: (val) {
                    if (val != null) {
                      setState(() => _llmRetryCount = val);
                      StorageService.setLLMRetryCount(val);
                    }
                  },
                ),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.animation_outlined,
                        color: Colors.blue),
                    title: const Text('动画设置',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('页面切换动画、Container Transform、性能选项'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        PageTransitions.slideHorizontal(
                          const AnimationSettingsPage(),
                        ),
                      );
                    },
                  ),
                ),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.notifications_outlined,
                        color: Colors.blueAccent),
                    title: const Text('通知管理',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('管理实时活动通知和普通通知的开启/关闭'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        PageTransitions.slideHorizontal(
                          const NotificationSettingsPage(),
                        ),
                      );
                    },
                  ),
                ),
                PermissionSection(
                  permissionDefs: PermissionHandler.permissionDefs,
                  permissionStatuses: _permissionStatuses,
                  isCheckingPermissions: _isCheckingPermissions,
                  onCheckAllPermissions: _permissionHandler.checkAllPermissions,
                  onRequestOrOpenPermission:
                      _permissionHandler.requestOrOpenPermission,
                ),
                AdvancedSection(
                  onShowMigrationDialog: _showMigrationDialog,
                  onTestCourseNotification: _testCourseNotification,
                  liveUpdatesStatus: _liveUpdatesStatus,
                  onCheckAndOpenLiveUpdates: _checkAndOpenLiveUpdates,
                  islandStatus: _islandStatus,
                  onCheckIslandSupport: _checkIslandSupport,
                  onOpenLanSync: () {
                    Navigator.push(
                      context,
                      PageTransitions.slideHorizontal(
                        const LanSyncScreen(),
                      ),
                    );
                  },
                ),
                SystemSection(
                  onOpenFeatureGuide: () {
                    Navigator.push(
                      context,
                      PageTransitions.slideHorizontal(
                        const FeatureGuideScreen(isManualReview: true),
                      ),
                    );
                  },
                  cacheSizeStr: _cacheSizeStr,
                  onClearCache: _storageManagementHandler.clearCache,
                  onShowStorageAnalysis:
                      _storageManagementHandler.showStorageAnalysis,
                  isCheckingUpdate: _isCheckingUpdate,
                  onCheckUpdates: _checkUpdatesAndNotices,
                  onLogout: () => _handleLogout(force: false),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.info_outline, color: Colors.blue),
                    title: const Text('关于此应用'),
                    subtitle: const Text('版本信息、更新日志、联系我们'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        PageTransitions.slideHorizontal(const AboutScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
