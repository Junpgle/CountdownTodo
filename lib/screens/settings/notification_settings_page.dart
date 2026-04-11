import 'package:flutter/material.dart';
import '../../storage_service.dart';
import '../../services/course_service.dart';
import '../../services/reminder_schedule_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _liveActivityEnabled = true;
  bool _normalEnabled = true;

  bool _courseEnabled = true;
  bool _quizEnabled = true;
  bool _todoSummaryEnabled = true;
  bool _specialTodoEnabled = true;
  bool _pomodoroEnabled = true;
  bool _todoRecognizeEnabled = true;

  bool _pomodoroEndEnabled = true;
  bool _reminderEnabled = true;

  int _courseReminderMinutes = 15;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final liveEnabled =
        await StorageService.isLiveActivityNotificationEnabled();
    final normalEnabled = await StorageService.isNormalNotificationEnabled();
    final courseEnabled = await StorageService.isCourseNotificationEnabled();
    final quizEnabled = await StorageService.isQuizNotificationEnabled();
    final todoSummaryEnabled =
        await StorageService.isTodoSummaryNotificationEnabled();
    final specialTodoEnabled =
        await StorageService.isSpecialTodoNotificationEnabled();
    final pomodoroEnabled =
        await StorageService.isPomodoroNotificationEnabled();
    final todoRecognizeEnabled =
        await StorageService.isTodoRecognizeNotificationEnabled();
    final pomodoroEndEnabled =
        await StorageService.isPomodoroEndNotificationEnabled();
    final reminderEnabled =
        await StorageService.isReminderNotificationEnabled();
    final reminderMinutes = await StorageService.getCourseReminderMinutes();

    setState(() {
      _liveActivityEnabled = liveEnabled;
      _normalEnabled = normalEnabled;
      _courseEnabled = courseEnabled;
      _quizEnabled = quizEnabled;
      _todoSummaryEnabled = todoSummaryEnabled;
      _specialTodoEnabled = specialTodoEnabled;
      _pomodoroEnabled = pomodoroEnabled;
      _todoRecognizeEnabled = todoRecognizeEnabled;
      _pomodoroEndEnabled = pomodoroEndEnabled;
      _reminderEnabled = reminderEnabled;
      _courseReminderMinutes = reminderMinutes;
    });
  }

  Future<void> _toggleLiveActivityMaster(bool? value) async {
    final enabled = value ?? false;
    await StorageService.setLiveActivityNotificationEnabled(enabled);
    setState(() {
      _liveActivityEnabled = enabled;
      if (!enabled) {
        _courseEnabled = false;
        _quizEnabled = false;
        _todoSummaryEnabled = false;
        _specialTodoEnabled = false;
        _pomodoroEnabled = false;
        _todoRecognizeEnabled = false;
      }
    });
    if (enabled) {
      await StorageService.setCourseNotificationEnabled(true);
      await StorageService.setQuizNotificationEnabled(true);
      await StorageService.setTodoSummaryNotificationEnabled(true);
      await StorageService.setSpecialTodoNotificationEnabled(true);
      await StorageService.setPomodoroNotificationEnabled(true);
      await StorageService.setTodoRecognizeNotificationEnabled(true);
    } else {
      await StorageService.setCourseNotificationEnabled(false);
      await StorageService.setQuizNotificationEnabled(false);
      await StorageService.setTodoSummaryNotificationEnabled(false);
      await StorageService.setSpecialTodoNotificationEnabled(false);
      await StorageService.setPomodoroNotificationEnabled(false);
      await StorageService.setTodoRecognizeNotificationEnabled(false);
    }
  }

  Future<void> _toggleNormalMaster(bool? value) async {
    final enabled = value ?? false;
    await StorageService.setNormalNotificationEnabled(enabled);
    setState(() {
      _normalEnabled = enabled;
      if (!enabled) {
        _pomodoroEndEnabled = false;
        _reminderEnabled = false;
      }
    });
    if (enabled) {
      await StorageService.setPomodoroEndNotificationEnabled(true);
      await StorageService.setReminderNotificationEnabled(true);
    } else {
      await StorageService.setPomodoroEndNotificationEnabled(false);
      await StorageService.setReminderNotificationEnabled(false);
    }
  }

  Future<void> _toggleSubNotification(String key, bool value,
      Function(bool) setStateCallback, Function(bool) storageCallback) async {
    await storageCallback(value);
    setState(() => setStateCallback(value));
    if (key == 'reminder') {
      _triggerReschedule();
    }
  }

  Future<void> _triggerReschedule() async {
    final username = await StorageService.getLoginSession();
    if (username == null) return;
    final todos = await StorageService.getTodos(username);
    final courses = await CourseService.getAllCourses();
    await ReminderScheduleService.scheduleAll(todos: todos, courses: courses);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知管理'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildMasterSwitch(
            title: '实时活动通知',
            subtitle: '在状态栏实时更新进度（课程、测验、待办、番茄钟等）',
            icon: Icons.notifications_active,
            color: Colors.blue,
            value: _liveActivityEnabled,
            onChanged: _toggleLiveActivityMaster,
          ),
          const SizedBox(height: 8),
          _buildSubSection(
            enabled: _liveActivityEnabled,
            children: [
              _buildSwitchTile(
                title: '课程实时通知',
                subtitle: '显示课程名称、教室、时间等信息',
                icon: Icons.school,
                value: _courseEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'course',
                  v,
                  (val) => _courseEnabled = val,
                  StorageService.setCourseNotificationEnabled,
                ),
              ),
              _buildSwitchTile(
                title: '测验进度通知',
                subtitle: '答题过程中显示当前进度和分数',
                icon: Icons.quiz,
                value: _quizEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'quiz',
                  v,
                  (val) => _quizEnabled = val,
                  StorageService.setQuizNotificationEnabled,
                ),
              ),
              _buildSwitchTile(
                title: '待办汇总通知',
                subtitle: '显示今日待办完成进度',
                icon: Icons.checklist,
                value: _todoSummaryEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'todo_summary',
                  v,
                  (val) => _todoSummaryEnabled = val,
                  StorageService.setTodoSummaryNotificationEnabled,
                ),
              ),
              _buildSwitchTile(
                title: '特殊待办通知',
                subtitle: '快递、奶茶、餐饮等类型待办提醒',
                icon: Icons.local_shipping,
                value: _specialTodoEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'special_todo',
                  v,
                  (val) => _specialTodoEnabled = val,
                  StorageService.setSpecialTodoNotificationEnabled,
                ),
              ),
              _buildSwitchTile(
                title: '番茄钟倒计时通知',
                subtitle: '专注/休息倒计时进度显示',
                icon: Icons.timer,
                value: _pomodoroEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'pomodoro',
                  v,
                  (val) => _pomodoroEnabled = val,
                  StorageService.setPomodoroNotificationEnabled,
                ),
              ),
              _buildSwitchTile(
                title: '图片识别通知',
                subtitle: '图片识别待办的进度、成功、失败通知',
                icon: Icons.image_search,
                value: _todoRecognizeEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'todo_recognize',
                  v,
                  (val) => _todoRecognizeEnabled = val,
                  StorageService.setTodoRecognizeNotificationEnabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildMasterSwitch(
            title: '普通通知',
            subtitle: '一次性触发的提醒通知（番茄钟结束、定时闹钟等）',
            icon: Icons.notifications,
            color: Colors.orange,
            value: _normalEnabled,
            onChanged: _toggleNormalMaster,
          ),
          const SizedBox(height: 8),
          _buildSubSection(
            enabled: _normalEnabled,
            children: [
              _buildSwitchTile(
                title: '番茄钟结束提醒',
                subtitle: '专注或休息阶段结束时提醒',
                icon: Icons.event_note,
                value: _pomodoroEndEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'pomodoro_end',
                  v,
                  (val) => _pomodoroEndEnabled = val,
                  StorageService.setPomodoroEndNotificationEnabled,
                ),
              ),
              _buildSwitchTile(
                title: '定时闹钟提醒',
                subtitle: '课程/待办的定时闹钟提醒',
                icon: Icons.alarm,
                value: _reminderEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'reminder',
                  v,
                  (val) => _reminderEnabled = val,
                  StorageService.setReminderNotificationEnabled,
                ),
              ),
              if (_reminderEnabled) ...[
                const Divider(height: 1, indent: 56),
                _buildCourseReminderTile(),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '关闭总开关将同时关闭该类别下所有子通知。单独开启某个子通知不会自动开启总开关。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterSwitch({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        secondary: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        value: value,
        activeThumbColor: color,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSubSection({
    required bool enabled,
    required List<Widget> children,
  }) {
    if (!enabled) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Center(
            child: Text(
              '已关闭所有通知',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      secondary: Icon(icon, size: 20, color: Colors.grey[700]),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      value: value,
      activeThumbColor: Colors.blue,
      onChanged: onChanged,
    );
  }

  Widget _buildCourseReminderTile() {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      leading: const SizedBox(width: 20, height: 20), // Placeholder for indent
      title: const Text('课程提醒时间', style: TextStyle(fontSize: 14)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '提前 $_courseReminderMinutes 分钟',
            style: TextStyle(fontSize: 13, color: Colors.blue[700]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ],
      ),
      onTap: _showReminderTimePicker,
    );
  }

  void _showReminderTimePicker() {
    final options = [0, 5, 10, 15, 20, 30, 45, 60];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '选择课程提醒时间',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final mins = options[index];
                    return ListTile(
                      title: Text(mins == 0 ? '准时提醒' : '提前 $mins 分钟'),
                      trailing: _courseReminderMinutes == mins
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () async {
                        await StorageService.setCourseReminderMinutes(mins);
                        setState(() {
                          _courseReminderMinutes = mins;
                        });
                        _triggerReschedule();
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
