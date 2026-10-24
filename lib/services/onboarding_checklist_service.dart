import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feature_tip_service.dart';

class OnboardingTaskItem {
  final String id;
  final String title;
  final String subtitle;
  final String locationHint;
  final IconData icon;
  final bool isCompleted;

  const OnboardingTaskItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.locationHint,
    required this.icon,
    this.isCompleted = false,
  });

  OnboardingTaskItem copyWith({bool? isCompleted}) {
    return OnboardingTaskItem(
      id: id,
      title: title,
      subtitle: subtitle,
      locationHint: locationHint,
      icon: icon,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class OnboardingChecklistSnapshot {
  final List<OnboardingTaskItem> tasks;
  final bool isDismissed;
  final bool isExpanded;

  const OnboardingChecklistSnapshot({
    required this.tasks,
    required this.isDismissed,
    required this.isExpanded,
  });

  int get completedCount => tasks.where((t) => t.isCompleted).length;
  int get totalCount => tasks.length;
  double get progress => totalCount == 0 ? 0.0 : completedCount / totalCount;
  bool get isAllCompleted => totalCount > 0 && completedCount >= totalCount;
}

class OnboardingChecklistService {
  const OnboardingChecklistService._();

  static const String _taskPrefix = 'onboarding_task_done_';
  static const String _dismissedKey = 'onboarding_checklist_dismissed_v1';
  static const String _expandedKey = 'onboarding_checklist_expanded_v1';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const String taskCreateTodoOrCountdown = 'create_todo_or_countdown';
  static const String taskCourseOrSchedule = 'course_or_schedule';
  static const String taskPlanBlock = 'plan_block';
  static const String taskPomodoroFocus = 'pomodoro_focus';
  static const String taskAiOrQuickVoice = 'ai_or_quick_voice';
  static const String taskExploreFeatureHub = 'explore_feature_hub';

  static const List<OnboardingTaskItem> defaultTasks = [
    OnboardingTaskItem(
      id: taskCreateTodoOrCountdown,
      title: '记录第一条待办或倒计时',
      subtitle: '支持循环重复、文件夹分类与桌面小组件提醒',
      locationHint: '点击底部「+」按钮或首页卡片右上角',
      icon: Icons.task_alt_rounded,
    ),
    OnboardingTaskItem(
      id: taskCourseOrSchedule,
      title: '导入课程表或创建固定日程',
      subtitle: '教务课表一键导入，固定日程还能直接关联待办任务',
      locationHint: '底部导航「周视图」或「设置 > 课表与学期」',
      icon: Icons.calendar_month_rounded,
    ),
    OnboardingTaskItem(
      id: taskPlanBlock,
      title: '用「规划中心」安排今日时间块',
      subtitle: '把“要做什么”拖动到时间轴，支持智能拆分长任务',
      locationHint: '首页「今日日程与规划」卡片或侧边栏「规划中心」',
      icon: Icons.edit_calendar_rounded,
    ),
    OnboardingTaskItem(
      id: taskPomodoroFocus,
      title: '开启一次番茄钟专注或时间日志',
      subtitle: '多端实时同步专注状态，错过的时段可随时在时间日志补录',
      locationHint: '底部导航「番茄钟」或侧边栏「时间日志」',
      icon: Icons.timer_rounded,
    ),
    OnboardingTaskItem(
      id: taskAiOrQuickVoice,
      title: '体验 AI 助手或长按「+」语音速记',
      subtitle: '一句话创建日程、识别账单图片、拆解复杂任务',
      locationHint: '首页右上角机器人图标，或长按底部「+」按钮',
      icon: Icons.auto_awesome_rounded,
    ),
    OnboardingTaskItem(
      id: taskExploreFeatureHub,
      title: '逛逛「功能百宝箱」解锁隐藏技能',
      subtitle: '探索记账、习惯打卡、30天挑战、手环同步与隐藏手势',
      locationHint: '首页探索卡片、侧边栏或「设置 > 帮助与反馈」',
      icon: Icons.explore_rounded,
    ),
  ];

  static Future<OnboardingChecklistSnapshot> loadSnapshot({
    bool hasTodosOrCountdowns = false,
    bool hasCoursesOrSchedules = false,
    bool hasPlanBlocks = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final isDismissed = prefs.getBool(_dismissedKey) ?? false;
    final isExpanded = prefs.getBool(_expandedKey) ?? false;

    final autoCompleted = <String, bool>{
      taskCreateTodoOrCountdown: hasTodosOrCountdowns,
      taskCourseOrSchedule: hasCoursesOrSchedules,
      taskPlanBlock: hasPlanBlocks,
    };

    var mutated = false;
    final tasks = <OnboardingTaskItem>[];
    for (final template in defaultTasks) {
      final key = '$_taskPrefix${template.id}';
      var done = prefs.getBool(key) ?? false;
      if (!done && (autoCompleted[template.id] ?? false)) {
        done = true;
        await prefs.setBool(key, true);
        mutated = true;
      }
      tasks.add(template.copyWith(isCompleted: done));
    }

    if (mutated) {
      revision.value++;
    }

    return OnboardingChecklistSnapshot(
      tasks: tasks,
      isDismissed: isDismissed,
      isExpanded: isExpanded,
    );
  }

  static Future<void> markTaskCompleted(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_taskPrefix$taskId';
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    revision.value++;
    FeatureTipService.revision.value++;
  }

  static Future<void> setExpanded(bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expandedKey, expanded);
    revision.value++;
  }

  static Future<void> setDismissed(bool dismissed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, dismissed);
    revision.value++;
    FeatureTipService.revision.value++;
  }

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final task in defaultTasks) {
      await prefs.remove('$_taskPrefix${task.id}');
    }
    await prefs.remove(_dismissedKey);
    await prefs.setBool(_expandedKey, true);
    revision.value++;
    FeatureTipService.revision.value++;
  }
}
