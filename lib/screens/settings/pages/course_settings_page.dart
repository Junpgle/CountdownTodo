import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/course_service.dart';
import '../../../services/database_helper.dart';
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
    'semester_management': GlobalKey(), // 新增：学期管理
  };

  bool _isLoading = true;
  String? _highlightTarget;

  String _username = '';
  int? _userId;

  String _noCourseBehavior = 'keep';
  bool _semesterEnabled = false;
  DateTime? _semesterStart;
  DateTime? _semesterEnd;

  // 多学期支持
  List<SemesterInfo> _semesters = [];
  String _activeSemesterId = 'default';

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

    // 加载多学期数据
    _semesters = await StorageService.getSemesters();
    _activeSemesterId = await StorageService.getActiveSemesterId();

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
      useRootNavigator: true,
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
      
      // 准备多学期数据
      final semestersData = _semesters.map((s) => s.toCloudJson()).toList();
      
      await ApiService.uploadUserSettings(
          semesterStartMs: startMs, semesterEndMs: endMs, semesters: semestersData);
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
        
        // 处理多学期数据
        if (userSettings['semesters'] != null && userSettings['semesters'] is List) {
          final semestersList = userSettings['semesters'] as List;
          final cloudSemesters = semestersList
              .map((s) => SemesterInfo.fromCloudJson(Map<String, dynamic>.from(s)))
              .toList();
          
          if (cloudSemesters.isNotEmpty) {
            await StorageService.saveSemesters(cloudSemesters);
            setState(() {
              _semesters = cloudSemesters;
            });
          }
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
            semesterId: _activeSemesterId, // 设置当前活跃学期ID
          );
        }).toList();

        // 检测冲突并让用户选择导入模式
        final conflicts =
            await CourseService.detectTimeConflicts(_username, courses);
        final ImportMode? mode =
            await _askCloudImportMode(courses, conflicts);
        if (mode == null) return;

        if (mode == ImportMode.merge) {
          await CourseService.mergeCoursesToSql(_username, courses);
        } else {
          await CourseService.saveCourses(_username, courses);
        }

        if (mounted) {
          _rescheduleReminders();
          final modeText = mode == ImportMode.merge ? '合并' : '同步';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ 成功从云端$modeText ${courses.length} 条课程与学期设置')));
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

  /// 云端获取时的导入模式选择
  Future<ImportMode?> _askCloudImportMode(
      List<CourseItem> newCourses, List<CourseItem> conflicts) async {
    if (conflicts.isNotEmpty) {
      // 有冲突：提示用户
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final conflictSummary = <String, int>{};
          for (final c in conflicts) {
            final key = '${c.courseName} (${c.teacherName})';
            conflictSummary[key] = (conflictSummary[key] ?? 0) + 1;
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Text('检测到时间冲突'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '以下 ${conflictSummary.length} 门课程与云端课表存在时间冲突，导入后将被覆盖：',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ...conflictSummary.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.circle,
                                size: 8, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${e.key}${e.value > 1 ? " (${e.value}节)" : ""}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 12),
                  const Text(
                    '不冲突的课程将保留。',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续导入'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return null;
      return ImportMode.merge;
    } else {
      // 无冲突：让用户选择
      final mode = await showDialog<ImportMode>(
        context: context,
        builder: (ctx) {
          final colorScheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.cloud_download_outlined),
                SizedBox(width: 10),
                Text('选择获取方式'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, ImportMode.replace),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz_rounded,
                            color: colorScheme.secondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('替换本地课表',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(
                                '清除本地课表，仅保留云端数据',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, ImportMode.merge),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.primary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.merge_rounded,
                            color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('与本地课表共存',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary)),
                              const SizedBox(height: 4),
                              Text(
                                '合并云端和本地课表，适用于不同学期',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          );
        },
      );

      return mode;
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

      // 同步更新学期管理中的对应学期
      if (!isStart && _semesterStart != null) {
        // 找到当前学期（开学日期匹配的学期）
        final currentSemesterIndex = _semesters.indexWhere((s) =>
            s.startDate.year == _semesterStart!.year &&
            s.startDate.month == _semesterStart!.month &&
            s.startDate.day == _semesterStart!.day);
        
        if (currentSemesterIndex != -1) {
          // 更新该学期的结束日期
          final updatedSemester = SemesterInfo(
            id: _semesters[currentSemesterIndex].id,
            name: _semesters[currentSemesterIndex].name,
            startDate: _semesters[currentSemesterIndex].startDate,
            endDate: picked,
            isCurrent: _semesters[currentSemesterIndex].isCurrent,
          );
          
          final updatedSemesters = List<SemesterInfo>.from(_semesters);
          updatedSemesters[currentSemesterIndex] = updatedSemester;
          
          await StorageService.saveSemesters(updatedSemesters);
          setState(() {
            _semesters = updatedSemesters;
          });
          
          debugPrint("✅ [Settings] 同步更新学期放假时间: ${updatedSemester.name} -> ${DateFormat('yyyy/MM/dd').format(picked)}");
        }
      }

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
            child: Text('学期管理',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          _buildTile(
            targetId: 'semester_management',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 学期列表
                if (_semesters.isNotEmpty)
                  ..._semesters.map((semester) => _buildSemesterTile(semester)),
                // 添加新学期按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
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

  Widget _buildSemesterTile(SemesterInfo semester) {
    final isActive = semester.id == _activeSemesterId;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive 
              ? colorScheme.primary.withValues(alpha: 0.5) 
              : theme.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: isActive 
            ? colorScheme.primary.withValues(alpha: 0.1) 
            : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () {
            if (!isActive) _activateSemester(semester);
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive 
                  ? colorScheme.primary.withValues(alpha: 0.2) 
                  : Colors.grey.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.check_circle : Icons.school_outlined,
              color: isActive ? colorScheme.primary : Colors.grey.shade600,
              size: 22,
            ),
          ),
          title: Text(
            semester.name,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
              fontSize: 16,
              color: isActive ? colorScheme.primary : null,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      '开学: ${DateFormat('yyyy/MM/dd').format(semester.startDate)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                if (semester.endDate != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.flight_takeoff_outlined, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Text(
                        '放假: ${DateFormat('yyyy/MM/dd').format(semester.endDate!)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final now = DateTime.now();
                      final start = DateTime(semester.startDate.year, semester.startDate.month, semester.startDate.day);
                      final end = DateTime(semester.endDate!.year, semester.endDate!.month, semester.endDate!.day, 23, 59, 59);
                      
                      double progress = 0.0;
                      if (now.isAfter(end)) {
                        progress = 1.0;
                      } else if (now.isAfter(start)) {
                        final total = end.difference(start).inMilliseconds;
                        final elapsed = now.difference(start).inMilliseconds;
                        progress = (elapsed / total).clamp(0.0, 1.0);
                      }
                      
                      final percent = (progress * 100).toInt();
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '学期进度',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Text(
                                '$percent%',
                                style: TextStyle(
                                  fontSize: 11, 
                                  color: progress == 1.0 ? Colors.green : (isActive ? colorScheme.primary : Colors.grey.shade600), 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: Colors.grey.withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress == 1.0 
                                  ? Colors.green 
                                  : (isActive ? colorScheme.primary : Colors.blue.shade400),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ]
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑',
                onPressed: () => _editSemester(semester),
              ),
              if (!isActive)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '删除',
                  onPressed: () => _deleteSemester(semester),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _activateSemester(SemesterInfo semester) async {
    // 更新所有学期的 isCurrent 状态
    final updatedSemesters = _semesters.map((s) {
      if (s.id == semester.id) {
        return SemesterInfo(
          id: s.id,
          name: s.name,
          startDate: s.startDate,
          endDate: s.endDate,
          isCurrent: true,
        );
      } else if (s.isCurrent) {
        return SemesterInfo(
          id: s.id,
          name: s.name,
          startDate: s.startDate,
          endDate: s.endDate,
          isCurrent: false,
        );
      }
      return s;
    }).toList();

    await StorageService.saveSemesters(updatedSemesters);
    await StorageService.setActiveSemesterId(semester.id);

    setState(() {
      _semesters = updatedSemesters;
      _activeSemesterId = semester.id;
      _semesterStart = semester.startDate;
      _semesterEnd = semester.endDate;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到: ${semester.name}')),
      );
    }
  }

  Future<void> _editSemester(SemesterInfo semester) async {
    final nameController = TextEditingController(text: semester.name);
    DateTime? startDate = semester.startDate;
    DateTime? endDate = semester.endDate;

    final result = await showDialog<SemesterInfo>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('编辑学期'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '学期名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                            '开学日期: ${DateFormat('yyyy/MM/dd').format(startDate!)}'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate!,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => startDate = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                          endDate != null
                              ? '放假日期: ${DateFormat('yyyy/MM/dd').format(endDate!)}'
                              : '选择放假日期 (可选)',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: endDate ??
                                startDate!.add(const Duration(days: 120)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => endDate = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.isEmpty || startDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请填写学期名称和开学日期')),
                      );
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      SemesterInfo(
                        id: semester.id,
                        name: nameController.text,
                        startDate: startDate!,
                        endDate: endDate,
                        isCurrent: semester.isCurrent,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final updatedSemesters = _semesters.map((s) {
        if (s.id == result.id) return result;
        return s;
      }).toList();

      await StorageService.saveSemesters(updatedSemesters);

      setState(() {
        _semesters = updatedSemesters;
        if (result.isCurrent) {
          _semesterStart = result.startDate;
          _semesterEnd = result.endDate;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学期已更新')),
        );
      }
    }
  }

  Future<void> _deleteSemester(SemesterInfo semester) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除学期'),
        content: Text('确定要删除 "${semester.name}" 吗？\n\n该学期下的课程数据不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final updatedSemesters = _semesters.where((s) => s.id != semester.id).toList();
      await StorageService.saveSemesters(updatedSemesters);

      setState(() {
        _semesters = updatedSemesters;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除: ${semester.name}')),
        );
      }
    }
  }

  /// 根据开学日期自动生成学期名称
  String _generateSemesterName(DateTime startDate) {
    final year = startDate.year;
    final month = startDate.month;
    
    // 3月-5月：春季
    // 6月-8月：夏季
    // 9月-11月：秋季
    // 12月-次年2月：冬季
    if (month >= 3 && month <= 5) {
      return '${year}年春季';
    } else if (month >= 6 && month <= 8) {
      return '${year}年夏季';
    } else if (month >= 9 && month <= 11) {
      return '${year}年秋季';
    } else {
      // 12月、1月、2月
      if (month == 12) {
        return '${year}年冬季';
      } else {
        return '${year}年冬季';
      }
    }
  }

  Future<void> _showAddSemesterDialog() async {
    final nameController = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;

    final result = await showDialog<SemesterInfo>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('添加新学期'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: Text(
                          startDate != null
                              ? '开学日期: ${DateFormat('yyyy/MM/dd').format(startDate!)}'
                              : '选择开学日期',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            helpText: '选择开学日期',
                          );
                          if (picked != null) {
                            setState(() {
                              startDate = picked;
                              // 自动生成学期名称
                              nameController.text = _generateSemesterName(picked);
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                          endDate != null
                              ? '放假日期: ${DateFormat('yyyy/MM/dd').format(endDate!)}'
                              : '选择放假日期 (可选)',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                startDate?.add(const Duration(days: 120)) ??
                                    DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            helpText: '选择放假日期',
                          );
                          if (picked != null) {
                            setState(() => endDate = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '学期名称',
                        hintText: '自动生成，可手动修改',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.isEmpty || startDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请选择开学日期')),
                      );
                      return;
                    }
                    final id =
                        'semester_${startDate!.millisecondsSinceEpoch}';
                    Navigator.pop(
                      ctx,
                      SemesterInfo(
                        id: id,
                        name: nameController.text,
                        startDate: startDate!,
                        endDate: endDate,
                      ),
                    );
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final updatedSemesters = [..._semesters, result];
      await StorageService.saveSemesters(updatedSemesters);

      setState(() {
        _semesters = updatedSemesters;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加: ${result.name}')),
        );
      }
    }
  }

  Future<void> _showClearSemesterCoursesDialog() async {
    if (_semesters.isEmpty) return;

    // 显示学期选择对话框
    final selectedSemester = await showDialog<SemesterInfo>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.delete_sweep_outlined, color: Colors.red),
              const SizedBox(width: 10),
              const Text('清除学期课程数据'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '选择要清除课程数据的学期：',
                  style: TextStyle(
                      fontSize: 14, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ..._semesters.map((semester) => InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(ctx, semester),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.school_outlined,
                                color: colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    semester.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '开学: ${DateFormat('yyyy/MM/dd').format(semester.startDate)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    if (selectedSemester == null) return;

    // 确认删除
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认清除'),
        content: Text(
            '确定要清除 "${selectedSemester.name}" 的所有课程数据吗？\n\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 执行清除
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        'courses',
        where: 'semester_id = ?',
        whereArgs: [selectedSemester.id],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 "${selectedSemester.name}" 的课程数据')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
      }
    }
  }
}
