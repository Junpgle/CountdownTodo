import 'package:flutter/material.dart';
import '../../storage_service.dart';
import '../../models.dart';
import '../../services/course_service.dart';
import '../../services/reminder_schedule_service.dart';
import '../../services/notification_service.dart';
import 'package:intl/intl.dart';

class NotificationSettingsPage extends StatefulWidget {
  final bool isEmbedded;
  const NotificationSettingsPage({super.key, this.isEmbedded = false});

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
  bool _todoLiveEnabled = true;

  bool _pomodoroEndEnabled = true;
  bool _reminderEnabled = true;

  int _courseReminderMinutes = 15;
  List<TodoGroup> _todoGroups = [];
  Map<String, int> _categoryReminderMinutes = {};
  String? _username;

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
    final todoLiveEnabled =
        await StorageService.isTodoLiveNotificationEnabled();
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
      _todoLiveEnabled = todoLiveEnabled;
      _pomodoroEndEnabled = pomodoroEndEnabled;
      _reminderEnabled = reminderEnabled;
      _courseReminderMinutes = reminderMinutes;
    });

    final username = await StorageService.getLoginSession();
    if (username != null) {
      final groups = await StorageService.getTodoGroups(username);
      final catReminders =
          await StorageService.getCategoryReminderMinutes(username);
      setState(() {
        _username = username;
        _todoGroups = groups.where((g) => !g.isDeleted).toList();
        _categoryReminderMinutes = catReminders;
      });
    }
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
        _todoLiveEnabled = false;
      }
    });
    if (enabled) {
      await StorageService.setCourseNotificationEnabled(true);
      await StorageService.setQuizNotificationEnabled(true);
      await StorageService.setTodoSummaryNotificationEnabled(true);
      await StorageService.setSpecialTodoNotificationEnabled(true);
      await StorageService.setPomodoroNotificationEnabled(true);
      await StorageService.setTodoRecognizeNotificationEnabled(true);
      await StorageService.setTodoLiveNotificationEnabled(true);
    } else {
      await StorageService.setCourseNotificationEnabled(false);
      await StorageService.setQuizNotificationEnabled(false);
      await StorageService.setTodoSummaryNotificationEnabled(false);
      await StorageService.setSpecialTodoNotificationEnabled(false);
      await StorageService.setPomodoroNotificationEnabled(false);
      await StorageService.setTodoRecognizeNotificationEnabled(false);
      await StorageService.setTodoLiveNotificationEnabled(false);
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
    final courses = await CourseService.getAllCourses(username);
    await ReminderScheduleService.scheduleAll(todos: todos, courses: courses);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(
        title: const Text('通知与提醒设置'),
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
              _buildSwitchTile(
                title: '待办实时通知',
                subtitle: '由闹钟触发，实时显示即将开始的待办进度',
                icon: Icons.event_available,
                value: _todoLiveEnabled,
                onChanged: (v) => _toggleSubNotification(
                  'todo_live',
                  v,
                  (val) => _todoLiveEnabled = val,
                  StorageService.setTodoLiveNotificationEnabled,
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
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade900 : Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.transparent, width: 1.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _showScheduledReminders,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.manage_search, color: Colors.teal, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '定时闹钟管理',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '查看当前已注册到系统的精确闹钟提醒',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
          if (_reminderEnabled && _todoGroups.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCategoryRemindersSection(),
          ],
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
      elevation: 0,
      margin: EdgeInsets.zero,
      color: value ? color.withValues(alpha: 0.1) : (Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade900 : Colors.grey.shade100),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: value ? color.withValues(alpha: 0.5) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubSection({
    required bool enabled,
    required List<Widget> children,
  }) {
    return AnimatedCrossFade(
      firstChild: const SizedBox(width: double.infinity, height: 0),
      secondChild: Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
        child: GridView.extent(
          maxCrossAxisExtent: 220,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.95,
          children: children,
        ),
      ),
      crossFadeState:
          enabled ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 300),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.grey.shade900 
          : Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: value 
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5) 
              : Colors.transparent,
          width: 1.5,
        )
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: value 
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) 
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: value ? Theme.of(context).colorScheme.primary : Colors.grey, size: 24),
                  ),
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.2),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseReminderTile() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).brightness == Brightness.dark 
          ? Colors.grey.shade900 
          : Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.transparent, width: 1.5)
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _showReminderTimePicker,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.timer, color: Colors.blue, size: 24),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_courseReminderMinutes 分钟',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '课程提醒时间',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  '距上课提前 $_courseReminderMinutes 分钟提醒',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.2),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
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

  void _showScheduledReminders() async {
    final reminders = await NotificationService.getScheduledReminders();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '已注册的提醒',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await NotificationService.scheduleReminders([],
                              clearFirst: true);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('已清除所有系统闹钟')),
                          );
                        },
                        icon: const Icon(Icons.delete_sweep, color: Colors.red),
                        label:
                            const Text('清除全部', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: reminders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.alarm_off,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('暂无预约的提醒',
                                  style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: reminders.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final r = reminders[index];
                            final triggerAt = DateTime.fromMillisecondsSinceEpoch(
                                r['triggerAtMs']);
                            final isPast = triggerAt.isBefore(DateTime.now());

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isPast
                                    ? Colors.grey[200]
                                    : Colors.blue[50],
                                child: Icon(
                                  isPast ? Icons.history : Icons.alarm,
                                  color: isPast ? Colors.grey : Colors.blue,
                                ),
                              ),
                              title: Text(r['title'] ?? '未命名提醒'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r['text'] ?? ''),
                                  Text(
                                    DateFormat('MM-dd HH:mm').format(triggerAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          isPast ? Colors.red : Colors.grey[600],
                                      fontWeight: isPast ? FontWeight.bold : null,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () async {
                                  await NotificationService.cancelReminder(
                                      r['notifId']);
                                  Navigator.pop(context);
                                  _showScheduledReminders();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryRemindersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4.0, bottom: 8.0, top: 8.0),
          child: Text(
            '分类默认提醒时间',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        GridView.extent(
          maxCrossAxisExtent: 220,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: _todoGroups.map((group) {
            final mins = _categoryReminderMinutes[group.id] ?? 5;
            return Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey.shade900 
                  : Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.transparent, width: 1.5)
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showCategoryReminderPicker(group),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.folder, color: Colors.teal, size: 24),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              mins == 0 ? '准时' : '提前 $mins分',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        group.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          '点击设置该分类下的待办默认提前提醒时间',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showCategoryReminderPicker(TodoGroup group) {
    final options = [0, 5, 10, 15, 20, 30, 45, 60, 120, 1440];
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
              Text(
                '设置 "${group.name}" 的默认提醒',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final mins = options[index];
                    final currentMins = _categoryReminderMinutes[group.id] ?? 5;
                    return ListTile(
                      title: Text(mins == 0
                          ? '准时提醒'
                          : mins >= 60
                              ? (mins >= 1440 ? '提前 1 天' : '提前 ${mins ~/ 60} 小时')
                              : '提前 $mins 分钟'),
                      trailing: currentMins == mins
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () async {
                        if (_username != null) {
                          final newData = Map<String, int>.from(_categoryReminderMinutes);
                          newData[group.id] = mins;
                          await StorageService.saveCategoryReminderMinutes(
                              _username!, newData);
                          setState(() {
                            _categoryReminderMinutes = newData;
                          });
                        }
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
