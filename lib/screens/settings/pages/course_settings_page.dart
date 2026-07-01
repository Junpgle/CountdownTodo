import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/course_service.dart';
import '../../../services/reminder_schedule_service.dart';
import '../../../storage_service.dart';
import '../../../services/api_service.dart';
import '../../../course_import/handlers/course_import_handler.dart';
import '../../../course_import/widgets/course_adaptation_screen.dart';
import '../../course_calendar_adjustment_screen.dart';
import '../../../models.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/page_transitions.dart';

class CourseSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const CourseSettingsPage(
      {super.key, this.initialTarget, this.isEmbedded = false});

  @override
  State<CourseSettingsPage> createState() => _CourseSettingsPageState();
}

class _CourseSettingsPageState extends State<CourseSettingsPage> {
  final Map<String, GlobalKey> _itemKeys = {
    'no_course_behavior': GlobalKey(),
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
  };

  bool _isLoading = true;
  String? _highlightTarget;

  String _username = '';
  int? _userId;

  String _noCourseBehavior = 'keep';
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  late CourseImportHandler _courseImportHandler;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget(widget.initialTarget!);
      });
    }
  }

  void _scrollToTarget(String target) {
    final key = _itemKeys[target];
    if (key?.currentContext != null) {
      setState(() => _highlightTarget = target);
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) setState(() => _highlightTarget = null);
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
    _userId = prefs.getInt('current_user_id');

    bool sEnabled = await StorageService.getSemesterEnabled();
    DateTime? sStart = await StorageService.getSemesterStart();
    DateTime? sEnd = await StorageService.getSemesterEnd();

    String? noCourseBehaviorPref;
    if (_username.isNotEmpty) {
      noCourseBehaviorPref = prefs.getString('no_course_behavior_$_username');
    }
    noCourseBehaviorPref ??= prefs.getString('no_course_behavior') ?? 'keep';

    _courseImportHandler = CourseImportHandler(
      context: context,
      username: _username,
      semesterStart: sStart,
      onRescheduleReminders: _rescheduleReminders,
      showMessage: (msg) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg))),
      onSemesterStartChanged: (date) {
        if (mounted) setState(() => _semesterStart = date);
      },
    );

    if (mounted) {
      setState(() {
        _semesterEnabled = sEnabled;
        _semesterStart = sStart;
        _semesterEnd = sEnd;
        _noCourseBehavior = noCourseBehaviorPref!;
        _isLoading = false;
      });
    }
  }

  Future<void> _rescheduleReminders() async {
    if (_username.isEmpty || _username == "未登录" || _username == "加载中...")
      return;
    try {
      final todos = await StorageService.getTodos(_username);
      final courses = await CourseService.getAllCourses(_username);
      await ReminderScheduleService.scheduleAll(todos: todos, courses: courses);
    } catch (e) {}
  }

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

  void _closeLoadingDialog(BuildContext context) {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _uploadCoursesToCloud() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录账号')));
      return;
    }

    final allCourses = await CourseService.getAllCourses(_username);
    if (allCourses.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有课表数据可上传')));
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

    final result = await CourseService.syncCoursesToCloud(_username, _userId!);

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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ 课表已成功同步到云端')));
    } else if (result['isLimitExceeded'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? '今日同步次数已达上限')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result['message'] ?? '同步失败')));
    }
  }

  Future<void> _fetchCoursesFromCloud() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录账号')));
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
      final userSettingsFuture = ApiService.fetchUserSettings();
      final coursesFuture = ApiService.fetchCourses(_userId!);

      final results = await Future.wait([userSettingsFuture, coursesFuture]);
      final Map<String, dynamic>? userSettings =
          results[0] as Map<String, dynamic>?;
      final List<dynamic> data = results[1] as List<dynamic>;

      if (!mounted) return;

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
        setState(() {});
      }

      _closeLoadingDialog(context);

      if (data.isNotEmpty) {
        if (_semesterStart == null) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('⚠️ 云端与本地均未配置开学日期，无法计算课表具体日期')));
          return;
        }

        final DateTime semesterMonday = _semesterStart!
            .subtract(Duration(days: _semesterStart!.weekday - 1));

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

        await CourseService.saveCourses(_username, courses);

        if (mounted) {
          _rescheduleReminders();
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('✅ 成功从云端同步 ${courses.length} 条课程与学期设置')));
        }
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('❌ 获取失败，云端暂无课表数据')));
      }
    } catch (e) {
      if (mounted) {
        _closeLoadingDialog(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('❌ 发生错误: $e')));
      }
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

      _courseImportHandler = CourseImportHandler(
        context: context,
        username: _username,
        semesterStart: _semesterStart,
        onRescheduleReminders: _rescheduleReminders,
        showMessage: (msg) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg))),
        onSemesterStartChanged: (date) {
          if (mounted) setState(() => _semesterStart = date);
        },
      );

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

  Widget _buildTile({required String targetId, required Widget child}) {
    final bool isHighlighted = _highlightTarget == targetId;
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
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('课表与学期'),
            ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 16.0),
            child: Text('学期设置',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          _buildTile(
            targetId: 'semester_progress',
            child: SwitchListTile(
              secondary: const Icon(Icons.linear_scale),
              title: const Text('首页学期进度条'),
              value: _semesterEnabled,
              onChanged: (val) {
                setState(() => _semesterEnabled = val);
                StorageService.saveAppSetting(
                    StorageService.KEY_SEMESTER_PROGRESS_ENABLED, val);
              },
            ),
          ),
          _buildTile(
            targetId: 'semester_start', // Keep target ID for scrolling
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: _buildDateCard(
                      title: '开学日期',
                      date: _semesterStart,
                      icon: Icons.school_outlined,
                      color: Colors.blue,
                      onTap: () => _pickSemesterDate(true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.0),
                    child:
                        Icon(Icons.arrow_forward, color: Colors.grey, size: 20),
                  ),
                  Expanded(
                    child: _buildDateCard(
                      title: '放假日期',
                      date: _semesterEnd,
                      icon: Icons.flight_takeoff_outlined,
                      color: Colors.orange,
                      onTap: () => _pickSemesterDate(false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'course_calendar_adjustment',
            child: ListTile(
              leading: const Icon(Icons.event_repeat_outlined,
                  color: Colors.deepPurple),
              title: const Text('放假与调休'),
              subtitle: const Text('设置停课日期，以及补哪一天的课'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(
                    CourseCalendarAdjustmentScreen(
                        isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '校历偏移动态调整'),
                  ),
                );
                _rescheduleReminders();
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
            child: Text('课程导入与同步',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _buildActionCard(
                  id: 'webview_import',
                  icon: isWeb ? Icons.open_in_browser : Icons.language_outlined,
                  title: isWeb ? '打开教务网页' : '在线教务导入',
                  subtitle: isWeb ? '导出文件后导入' : '推荐方式',
                  color: Colors.teal,
                  onTap: _courseImportHandler.importFromWebView,
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
            child: Text('无课时板块行为',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          _buildTile(
            targetId: 'no_course_behavior',
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _buildBehaviorCard('keep', '保持原位',
                              Icons.align_vertical_top_outlined)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildBehaviorCard('bottom', '排到最后',
                              Icons.align_vertical_bottom_outlined)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildBehaviorCard(
                              'hide', '自动隐藏', Icons.visibility_off_outlined)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
            child: Text('请求课表适配',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          _buildTile(
            targetId: 'course_adapt',
            child: ListTile(
              leading: const Icon(Icons.auto_awesome, color: Colors.orange),
              title: const Text('我要请求开发者适配！'),
              subtitle: const Text('如果没有你的学校，点此申请'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('推荐',
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(
                    CourseAdaptationScreen(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '课程表适配机制'),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDateCard(
      {required String title,
      required DateTime? date,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              date == null ? "未设置" : DateFormat('yyyy/MM/dd').format(date),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: date == null ? Colors.grey : null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
      {required String id,
      required IconData icon,
      required String title,
      required String subtitle,
      required Color color,
      required VoidCallback onTap}) {
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
            border:
                Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
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
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBehaviorCard(String value, String title, IconData icon) {
    final isSelected = _noCourseBehavior == value;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        setState(() => _noCourseBehavior = value);
        SharedPreferences.getInstance().then((prefs) {
          if (_username.isNotEmpty) {
            prefs.setString('no_course_behavior_$_username', value);
          }
          prefs.setString('no_course_behavior', value);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.1)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey.shade900
                  : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected ? colorScheme.primary : Colors.grey,
                size: 24),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color:
                      isSelected ? colorScheme.primary : Colors.grey.shade600,
                )),
          ],
        ),
      ),
    );
  }
}
