import 'dart:math';
import 'package:flutter/material.dart';
import 'medal_bandit_service.dart';
import 'medal_feature_extractor.dart';
import 'timeline_service.dart';

/// 勋章信息定义
class MedalInfo {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String category; // 'focus', 'completion', 'persistence', 'efficiency', 'breadth'
  final int priority; // 1 (most motivating) to 5
  final bool isRepeatable;
  
  MedalInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.category,
    required this.priority,
    this.isRepeatable = false,
  });
}

/// 勋章进度信息
class MedalProgress {
  final MedalInfo medal;
  final double progress; // 0.0 to 1.0
  final bool earned;
  final String nextMilestone; // "还需要 X..." or "已获得"
  final int stepsRemaining; // 用于排序的步数，越小越容易
  final DateTime? earnedAt;
  final DateTime? firstEarnedAt;
  final int earnedCount;

  MedalProgress({
    required this.medal,
    required this.progress,
    required this.earned,
    required this.nextMilestone,
    required this.stepsRemaining,
    this.earnedAt,
    this.firstEarnedAt,
    this.earnedCount = 0,
  });
}

/// 勋章推荐结果
class MedalRecommendation {
  final List<MedalProgress> topRecommendations; // 前6个最容易达成的
  final List<MedalProgress> allMedals; // 所有勋章及进度
  final List<MedalProgress> earnedMedals; // 已获得的勋章
  final bool isML; // 是否使用了 ML 推荐
  final Map<String, String> recommendReasons; // medalId → 推荐理由

  MedalRecommendation({
    required this.topRecommendations,
    required this.allMedals,
    required this.earnedMedals,
    this.isML = false,
    this.recommendReasons = const {},
  });
}

class MedalRecommendationService {
  // 定义所有 50 个勋章
  static final List<MedalInfo> allMedals = [
    // === Focus Medals (专注相关) ===
    MedalInfo(
      id: 'focus_starter',
      title: '专注启动者',
      description: '记录第一次 Pomodoro',
      icon: Icons.play_circle_outline_rounded,
      color: Colors.green,
      category: 'focus',
      priority: 1,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'two_hour_guardian',
      title: '两小时守门员',
      description: '累计专注时长 120 分钟',
      icon: Icons.hourglass_bottom_rounded,
      color: Colors.blue,
      category: 'focus',
      priority: 2,
    ),
    MedalInfo(
      id: 'eight_hour_trek',
      title: '八小时长征',
      description: '累计专注时长 480 分钟',
      icon: Icons.terrain_rounded,
      color: Colors.brown,
      category: 'focus',
      priority: 3,
    ),
    MedalInfo(
      id: 'deep_worker',
      title: '深度工作者',
      description: '完成第一个深度专注（≥60分钟）',
      icon: Icons.diamond_outlined,
      color: Colors.purple,
      category: 'focus',
      priority: 2,
    ),
    MedalInfo(
      id: 'long_focus_specialist',
      title: '长专注选手',
      description: '单次专注达到 90 分钟',
      icon: Icons.workspace_premium_rounded,
      color: Colors.amber,
      category: 'focus',
      priority: 3,
    ),
    MedalInfo(
      id: 'stable_output',
      title: '稳定输出',
      description: '中断率 ≤10% 且至少 3 次专注',
      icon: Icons.shield_moon_rounded,
      color: Colors.indigoAccent,
      category: 'focus',
      priority: 2,
    ),

    // === Completion Medals (完成相关) ===
    MedalInfo(
      id: 'task_harvester',
      title: '任务收割者',
      description: '完成第一个任务',
      icon: Icons.task_alt_rounded,
      color: Colors.green,
      category: 'completion',
      priority: 1,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'plan_fulfiller',
      title: '计划兑现者',
      description: '任务完成率达到 80%',
      icon: Icons.fact_check_outlined,
      color: Colors.lightGreen,
      category: 'completion',
      priority: 2,
    ),
    MedalInfo(
      id: 'early_deliverer',
      title: '提前交付者',
      description: '至少提前完成 1 个任务',
      icon: Icons.rocket_launch_outlined,
      color: Colors.cyan,
      category: 'completion',
      priority: 2,
    ),
    MedalInfo(
      id: 'ddl_tamer',
      title: 'DDL 驯服者',
      description: '在截止前完成至少 1 个任务',
      icon: Icons.flag_outlined,
      color: Colors.redAccent,
      category: 'completion',
      priority: 3,
    ),

    // === Persistence Medals (坚持相关) ===
    MedalInfo(
      id: 'night_efficiency_king',
      title: '深夜效率王',
      description: '高效时段在夜间（20:00-05:00）',
      icon: Icons.nightlight_round,
      color: Colors.indigo,
      category: 'persistence',
      priority: 3,
    ),
    MedalInfo(
      id: 'golden_hour',
      title: '黄金时刻',
      description: '发现你的高效时间段',
      icon: Icons.wb_sunny_outlined,
      color: Colors.orange,
      category: 'persistence',
      priority: 2,
    ),
    MedalInfo(
      id: 'long_distance_runner',
      title: '长跑型选手',
      description: '连续活跃至少 3 天',
      icon: Icons.local_fire_department_outlined,
      color: Colors.deepOrange,
      category: 'persistence',
      priority: 2,
    ),

    // === Breadth Medals (广度相关) ===
    MedalInfo(
      id: 'learning_polymath',
      title: '学习多面手',
      description: '涉猎 4+ 个不同主题',
      icon: Icons.hub_outlined,
      color: Colors.teal,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'main_line_pusher',
      title: '主线推进者',
      description: '单个主题占比达到 45%',
      icon: Icons.route_outlined,
      color: Colors.deepPurple,
      category: 'breadth',
      priority: 2,
    ),

    // === Learning Medals (学习相关) ===
    MedalInfo(
      id: 'knowledge_scout',
      title: '知识侦察兵',
      description: '进行 3+ 次知识检索',
      icon: Icons.travel_explore_rounded,
      color: Colors.teal,
      category: 'breadth',
      priority: 2,
    ),
    MedalInfo(
      id: 'exam_prep_sprinter',
      title: '备考冲刺者',
      description: '3+ 次备考相关活动',
      icon: Icons.school_outlined,
      color: Colors.red,
      category: 'completion',
      priority: 3,
    ),

    // === Course Medals (课程相关) ===
    MedalInfo(
      id: 'course_companion',
      title: '课表同行者',
      description: '记录第一节课',
      icon: Icons.event_note_outlined,
      color: Colors.blueGrey,
      category: 'persistence',
      priority: 2,
    ),
    MedalInfo(
      id: 'full_course_survivor',
      title: '满课生存者',
      description: '单日课程数达到 5 节',
      icon: Icons.view_day_outlined,
      color: Colors.deepOrange,
      category: 'persistence',
      priority: 3,
    ),

    // === Screen Time Medals (屏幕时间相关) ===
    MedalInfo(
      id: 'screen_master',
      title: '屏幕掌控者',
      description: '生产力应用占比达到 50%',
      icon: Icons.desktop_windows_outlined,
      color: Colors.blueGrey,
      category: 'efficiency',
      priority: 2,
    ),
    MedalInfo(
      id: 'low_distraction_mode',
      title: '低分心模式',
      description: '分心应用占比 ≤15%',
      icon: Icons.visibility_off_outlined,
      color: Colors.grey,
      category: 'efficiency',
      priority: 3,
    ),

    // === Expanded Focus Medals ===
    MedalInfo(
      id: 'focus_expert',
      title: '专注专家',
      description: '累计专注时长达到 24 小时',
      icon: Icons.psychology_rounded,
      color: Colors.indigo,
      category: 'focus',
      priority: 4,
    ),
    MedalInfo(
      id: 'focus_legend',
      title: '专注传奇',
      description: '累计专注时长达到 100 小时',
      icon: Icons.auto_awesome_rounded,
      color: Colors.amber,
      category: 'focus',
      priority: 5,
    ),
    MedalInfo(
      id: 'pomo_runner',
      title: '番茄长跑者',
      description: '累计完成 50 个番茄钟',
      icon: Icons.directions_run_rounded,
      color: Colors.orange,
      category: 'focus',
      priority: 3,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'pomo_marathon',
      title: '番茄马拉松',
      description: '累计完成 200 个番茄钟',
      icon: Icons.timer_3_rounded,
      color: Colors.redAccent,
      category: 'focus',
      priority: 4,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'ultra_focus',
      title: '极度专注',
      description: '单次专注时长超过 120 分钟',
      icon: Icons.bolt_rounded,
      color: Colors.yellowAccent,
      category: 'focus',
      priority: 4,
    ),
    MedalInfo(
      id: 'distraction_immune',
      title: '分心免疫',
      description: '连续 5 次专注无任何中断',
      icon: Icons.health_and_safety_rounded,
      color: Colors.tealAccent,
      category: 'focus',
      priority: 3,
    ),

    // === Expanded Completion Medals ===
    MedalInfo(
      id: 'task_millionaire',
      title: '任务百万富翁',
      description: '累计完成 50 个任务',
      icon: Icons.monetization_on_rounded,
      color: Colors.amber,
      category: 'completion',
      priority: 3,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'task_emperor',
      title: '任务大帝',
      description: '累计完成 500 个任务',
      icon: Icons.castle_rounded,
      color: Colors.purpleAccent,
      category: 'completion',
      priority: 5,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'early_bird',
      title: '晨曦之光',
      description: '累计在早晨 8 点前完成 10 次专注',
      icon: Icons.wb_twilight_rounded,
      color: Colors.orangeAccent,
      category: 'persistence',
      priority: 3,
    ),
    MedalInfo(
      id: 'night_owl',
      title: '星光伴读者',
      description: '累计在凌晨后完成 10 次专注',
      icon: Icons.dark_mode_rounded,
      color: Colors.indigoAccent,
      category: 'persistence',
      priority: 3,
    ),
    MedalInfo(
      id: 'weekend_warrior',
      title: '周末战士',
      description: '在周末累计专注超过 5 小时',
      icon: Icons.fort_rounded,
      color: Colors.red,
      category: 'persistence',
      priority: 3,
    ),
    MedalInfo(
      id: 'productivity_spike',
      title: '产出爆发',
      description: '单日完成任务数量超过 10 个',
      icon: Icons.trending_up_rounded,
      color: Colors.lightBlueAccent,
      category: 'completion',
      priority: 4,
    ),

    // === Expanded Persistence Medals ===
    MedalInfo(
      id: 'perfect_week',
      title: '完美周',
      description: '连续 7 天保持活跃',
      icon: Icons.calendar_month_rounded,
      color: Colors.greenAccent,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'persistence_hero',
      title: '毅力英雄',
      description: '连续 30 天保持活跃',
      icon: Icons.shield_rounded,
      color: Colors.blueAccent,
      category: 'persistence',
      priority: 5,
    ),
    MedalInfo(
      id: 'monthly_checkin',
      title: '月度打卡达人',
      description: '一个月内活跃天数达到 20 天',
      icon: Icons.verified_user_rounded,
      color: Colors.cyan,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'steady_pulse',
      title: '稳定脉搏',
      description: '连续 5 天保持相同的专注时长',
      icon: Icons.monitor_heart_rounded,
      color: Colors.pinkAccent,
      category: 'persistence',
      priority: 3,
    ),

    // === Expanded Efficiency & Learning ===
    MedalInfo(
      id: 'efficiency_demon',
      title: '效率狂魔',
      description: '单日生产力比例达到 95%',
      icon: Icons.speed_rounded,
      color: Colors.red,
      category: 'efficiency',
      priority: 4,
    ),
    MedalInfo(
      id: 'screen_time_slayer',
      title: '屏幕时间杀手',
      description: '连续一周分心应用占比低于 10%',
      icon: Icons.cleaning_services_rounded,
      color: Colors.teal,
      category: 'efficiency',
      priority: 4,
    ),
    MedalInfo(
      id: 'knowledge_glutton',
      title: '知识贪食者',
      description: '累计进行 50 次知识检索',
      icon: Icons.menu_book_rounded,
      color: Colors.brown,
      category: 'breadth',
      priority: 3,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'exam_conqueror',
      title: '考试征服者',
      description: '累计完成 20 次备考活动',
      icon: Icons.military_tech_rounded,
      color: Colors.deepOrange,
      category: 'completion',
      priority: 4,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'deep_diver',
      title: '深度潜水员',
      description: '累计完成 10 次深度专注（≥60分钟）',
      icon: Icons.waves_rounded,
      color: Colors.blue,
      category: 'focus',
      priority: 3,
      isRepeatable: true,
    ),

    // === Expanded Course & Social ===
    MedalInfo(
      id: 'course_veteran',
      title: '课堂老兵',
      description: '累计记录 50 节课程',
      icon: Icons.history_edu_rounded,
      color: Colors.blueGrey,
      category: 'persistence',
      priority: 4,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'no_skip_champion',
      title: '全勤奖章',
      description: '一周内没有任何漏掉的计划课程',
      icon: Icons.assignment_turned_in_rounded,
      color: Colors.lightGreen,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'sync_pioneer',
      title: '同步先锋',
      description: '第一次成功进行多端同步',
      icon: Icons.sync_rounded,
      color: Colors.purple,
      category: 'efficiency',
      priority: 2,
    ),
    MedalInfo(
      id: 'island_resident',
      title: '岛屿居民',
      description: '在 Windows 灵动岛模式下累计专注 10 小时',
      icon: Icons.landscape_rounded,
      color: Colors.green,
      category: 'efficiency',
      priority: 3,
    ),

    // === Special Performance Medals ===
    MedalInfo(
      id: 'focus_streak_5',
      title: '五连专注',
      description: '单日内连续完成 5 个番茄钟',
      icon: Icons.repeat_one_on_rounded,
      color: Colors.orange,
      category: 'focus',
      priority: 3,
    ),
    MedalInfo(
      id: 'multi_tasker',
      title: '多面手',
      description: '单日内涉猎 3 个以上不同的任务分类',
      icon: Icons.category_rounded,
      color: Colors.teal,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'early_finisher_50',
      title: '早起早完',
      description: '累计提前完成 50 个任务',
      icon: Icons.done_all_rounded,
      color: Colors.green,
      category: 'completion',
      priority: 4,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'deadline_survivor_20',
      title: 'DDL 幸存者',
      description: '累计在截止日期当天完成 20 个任务',
      icon: Icons.alarm_on_rounded,
      color: Colors.redAccent,
      category: 'completion',
      priority: 4,
      isRepeatable: true,
    ),

    // === Category: Subject Specialists (学科专家 10个) ===
    MedalInfo(
      id: 'subject_mathematician',
      title: '数学建模者',
      description: '在数学/理科类目累计专注 20 小时',
      icon: Icons.functions_rounded,
      color: Colors.blue,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_linguist',
      title: '语言研习员',
      description: '在语言类目累计专注 20 小时',
      icon: Icons.translate_rounded,
      color: Colors.indigo,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_coder',
      title: '代码架构师',
      description: '在编程/计算机类目累计专注 20 小时',
      icon: Icons.code_rounded,
      color: Colors.green,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_artist',
      title: '灵感捕捉者',
      description: '在艺术/设计类目累计专注 20 小时',
      icon: Icons.palette_rounded,
      color: Colors.pink,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_scientist',
      title: '实验室常客',
      description: '在科学/实验类目累计专注 20 小时',
      icon: Icons.science_rounded,
      color: Colors.teal,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_historian',
      title: '时间旅行者',
      description: '在历史/社科类目累计专注 20 小时',
      icon: Icons.history_rounded,
      color: Colors.brown,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_athlete',
      title: '强健体魄',
      description: '在体育/健身类目累计专注 20 小时',
      icon: Icons.fitness_center_rounded,
      color: Colors.orange,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_musician',
      title: '旋律织网者',
      description: '在音乐/艺术类目累计专注 20 小时',
      icon: Icons.music_note_rounded,
      color: Colors.deepPurple,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_bookworm',
      title: '博览群书',
      description: '在阅读/文学类目累计专注 20 小时',
      icon: Icons.auto_stories_rounded,
      color: Colors.blueGrey,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'subject_polyglot',
      title: '通晓百家',
      description: '同时有 5 个以上学科达到 5 小时专注',
      icon: Icons.public_rounded,
      color: Colors.cyan,
      category: 'breadth',
      priority: 4,
    ),

    // === Category: Habit Masters (习惯大师 10个) ===
    MedalInfo(
      id: 'habit_early_riser',
      title: '早起冠军',
      description: '累计 30 天在早上 7 点前开始专注',
      icon: Icons.wb_sunny_rounded,
      color: Colors.orangeAccent,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'habit_night_reader',
      title: '深夜火炬手',
      description: '累计 30 天在晚上 11 点后仍保持专注',
      icon: Icons.fireplace_rounded,
      color: Colors.amberAccent,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'habit_lunch_warrior',
      title: '午间勤奋者',
      description: '累计 20 天在午休时段（12:00-14:00）专注',
      icon: Icons.lunch_dining_rounded,
      color: Colors.redAccent,
      category: 'persistence',
      priority: 3,
    ),
    MedalInfo(
      id: 'habit_streak_100',
      title: '百日伟业',
      description: '连续活跃天数达到 100 天',
      icon: Icons.workspace_premium_rounded,
      color: Colors.amber,
      category: 'persistence',
      priority: 5,
    ),
    MedalInfo(
      id: 'habit_weekly_streak_10',
      title: '十周之约',
      description: '连续 10 周每周至少活跃 5 天',
      icon: Icons.calendar_view_week_rounded,
      color: Colors.blueAccent,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'habit_monthly_champion',
      title: '全勤标兵',
      description: '单月活跃天数达到 28 天以上',
      icon: Icons.verified_rounded,
      color: Colors.greenAccent,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'habit_year_companion',
      title: '岁月见证者',
      description: '使用应用记录时间达到 1 年',
      icon: Icons.hourglass_full_rounded,
      color: Colors.indigoAccent,
      category: 'persistence',
      priority: 5,
    ),
    MedalInfo(
      id: 'habit_streak_resurrection',
      title: '浴火重生',
      description: '断签后重新连续活跃 7 天',
      icon: Icons.egg_rounded,
      color: Colors.orange,
      category: 'persistence',
      priority: 3,
    ),
    MedalInfo(
      id: 'habit_weekend_pro',
      title: '周末执念',
      description: '连续 4 个周末保持高强度专注',
      icon: Icons.weekend_rounded,
      color: Colors.deepOrangeAccent,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'habit_rhythm_master',
      title: '节奏大师',
      description: '连续 7 天在同一时间段开始第一笔专注',
      icon: Icons.piano_rounded,
      color: Colors.purple,
      category: 'persistence',
      priority: 4,
    ),

    // === Category: Productivity Ninja (产出忍者 10个) ===
    MedalInfo(
      id: 'ninja_speed_demon',
      title: '闪电侠',
      description: '任务创建后 15 分钟内即完成',
      icon: Icons.bolt_rounded,
      color: Colors.yellow,
      category: 'efficiency',
      priority: 3,
    ),
    MedalInfo(
      id: 'ninja_bulk_completer',
      title: '批量处理器',
      description: '单小时内完成 5 个以上任务',
      icon: Icons.layers_rounded,
      color: Colors.blue,
      category: 'efficiency',
      priority: 4,
    ),
    MedalInfo(
      id: 'ninja_focus_block_4',
      title: '专注之盾',
      description: '单日专注总时长超过 4 小时',
      icon: Icons.security_rounded,
      color: Colors.teal,
      category: 'focus',
      priority: 3,
    ),
    MedalInfo(
      id: 'ninja_focus_block_8',
      title: '专注之魂',
      description: '单日专注总时长超过 8 小时',
      icon: Icons.auto_awesome_motion_rounded,
      color: Colors.deepPurpleAccent,
      category: 'focus',
      priority: 5,
    ),
    MedalInfo(
      id: 'ninja_deep_diver_3h',
      title: '深海潜水员',
      description: '单次专注时长超过 3 小时',
      icon: Icons.scuba_diving_rounded,
      color: Colors.blueAccent,
      category: 'focus',
      priority: 5,
    ),
    MedalInfo(
      id: 'ninja_zero_distraction',
      title: '真空领域',
      description: '单日分心应用使用时间为 0',
      icon: Icons.do_not_disturb_on_rounded,
      color: Colors.white70,
      category: 'efficiency',
      priority: 4,
    ),
    MedalInfo(
      id: 'ninja_planned_perfection',
      title: '完美闭环',
      description: '当日创建的所有任务全部在当日完成',
      icon: Icons.published_with_changes_rounded,
      color: Colors.green,
      category: 'completion',
      priority: 4,
    ),
    MedalInfo(
      id: 'ninja_inbox_zero',
      title: '收件箱清零',
      description: '睡前没有任何未完成的待办事项',
      icon: Icons.mark_email_read_rounded,
      color: Colors.cyanAccent,
      category: 'completion',
      priority: 3,
    ),
    MedalInfo(
      id: 'ninja_consistency_king',
      title: '稳定如山',
      description: '连续一周专注时长波动小于 10%',
      icon: Icons.balance_rounded,
      color: Colors.grey,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'ninja_efficiency_max',
      title: '效能之巅',
      description: '全天生产力时长占比超过 98%',
      icon: Icons.keyboard_double_arrow_up_rounded,
      color: Colors.red,
      category: 'efficiency',
      priority: 5,
    ),

    // === Category: Academic Excellence (学术卓越 10个) ===
    MedalInfo(
      id: 'academic_course_100',
      title: '学分收割者',
      description: '累计记录 100 节课程',
      icon: Icons.history_edu_rounded,
      color: Colors.blueGrey,
      category: 'persistence',
      priority: 5,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'academic_exam_overlord',
      title: '考神附体',
      description: '累计完成 50 次备考专注',
      icon: Icons.military_tech_rounded,
      color: Colors.red,
      category: 'completion',
      priority: 5,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'academic_search_guru',
      title: '检索大师',
      description: '累计检索次数达到 100 次',
      icon: Icons.manage_search_rounded,
      color: Colors.teal,
      category: 'breadth',
      priority: 4,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'academic_early_finish_diamond',
      title: '效率钻石',
      description: '累计提前完成 100 个任务',
      icon: Icons.diamond_rounded,
      color: Colors.cyan,
      category: 'completion',
      priority: 5,
      isRepeatable: true,
    ),
    MedalInfo(
      id: 'academic_no_skip_month',
      title: '满勤神话',
      description: '连续一个月没有任何漏掉的课程计划',
      icon: Icons.assignment_turned_in_rounded,
      color: Colors.greenAccent,
      category: 'persistence',
      priority: 5,
    ),
    MedalInfo(
      id: 'academic_full_house_7',
      title: '魔鬼课表',
      description: '单日课程数达到 7 节',
      icon: Icons.view_comfortable_rounded,
      color: Colors.deepOrange,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'academic_bridge_builder',
      title: '知识建模者',
      description: '检索后立即开启相关专注（累计 20 次）',
      icon: Icons.architecture_rounded,
      color: Colors.lightBlue,
      category: 'breadth',
      priority: 4,
    ),
    MedalInfo(
      id: 'academic_library_phantom',
      title: '图书馆幽灵',
      description: '在“图书馆”地点累计专注超过 50 小时',
      icon: Icons.local_library_rounded,
      color: Colors.brown,
      category: 'focus',
      priority: 4,
    ),
    MedalInfo(
      id: 'academic_top_of_class',
      title: '榜首常客',
      description: '在某个学科的专注时长超过全站 90% 用户',
      icon: Icons.leaderboard_rounded,
      color: Colors.amber,
      category: 'breadth',
      priority: 5,
    ),
    MedalInfo(
      id: 'academic_deep_thinker',
      title: '深度思考者',
      description: '累计完成 50 次 60 分钟以上的深度专注',
      icon: Icons.psychology_alt_rounded,
      color: Colors.purple,
      category: 'focus',
      priority: 5,
    ),

    // === Category: App Explorer (功能探索 10个) ===
    MedalInfo(
      id: 'explorer_widget_loyalist',
      title: '挂件发烧友',
      description: '累计通过桌面挂件启动专注 50 次',
      icon: Icons.widgets_rounded,
      color: Colors.blue,
      category: 'efficiency',
      priority: 3,
    ),
    MedalInfo(
      id: 'explorer_island_pro_100',
      title: '灵动岛专家',
      description: '在灵动岛模式下累计专注 100 小时',
      icon: Icons.landscape_rounded,
      color: Colors.greenAccent,
      category: 'efficiency',
      priority: 5,
    ),
    MedalInfo(
      id: 'explorer_sync_master',
      title: '多端合一',
      description: '累计多端同步次数达到 100 次',
      icon: Icons.cloud_sync_rounded,
      color: Colors.blueAccent,
      category: 'efficiency',
      priority: 4,
    ),
    MedalInfo(
      id: 'explorer_countdown_master',
      title: '倒数大师',
      description: '累计创建并完成 50 个倒数日事项',
      icon: Icons.event_available_rounded,
      color: Colors.pinkAccent,
      category: 'completion',
      priority: 3,
    ),
    MedalInfo(
      id: 'explorer_reminder_loyalist',
      title: '准时赴约',
      description: '累计响应并完成 100 个日程提醒',
      icon: Icons.notifications_active_rounded,
      color: Colors.orange,
      category: 'persistence',
      priority: 4,
    ),
    MedalInfo(
      id: 'explorer_report_analyzer',
      title: '自我洞察',
      description: '累计查看详细数据报告 30 次',
      icon: Icons.analytics_rounded,
      color: Colors.tealAccent,
      category: 'efficiency',
      priority: 2,
    ),
    MedalInfo(
      id: 'explorer_multi_subject_10',
      title: '博学之士',
      description: '累计创建并记录 10 个以上不同的学科分类',
      icon: Icons.category_outlined,
      color: Colors.indigo,
      category: 'breadth',
      priority: 4,
    ),
    MedalInfo(
      id: 'explorer_pathfinder_10',
      title: '学术开拓者',
      description: '使用搜索功能探索过 10 个不同的知识领域',
      icon: Icons.map_rounded,
      color: Colors.deepOrangeAccent,
      category: 'breadth',
      priority: 3,
    ),
    MedalInfo(
      id: 'explorer_night_watch',
      title: '守夜人',
      description: '在凌晨 2 点到 4 点之间完成过专注',
      icon: Icons.visibility_rounded,
      color: Colors.white,
      category: 'persistence',
      priority: 5,
    ),
    MedalInfo(
      id: 'explorer_app_pioneer',
      title: '先锋体验者',
      description: '尝试使用过应用内所有的主要功能模块',
      icon: Icons.auto_awesome_rounded,
      color: Colors.amberAccent,
      category: 'efficiency',
      priority: 4,
    ),
  ];

  /// 计算单个勋章的进度 (0.0-1.0)
  static MedalProgress calculateMedalProgress(
    MedalInfo medal,
    TimelineSummary summary,
    int totalFocusMinutes,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
    int courseCount,
    int maxDailyCourseCount,
    int screenTimeSeconds,
    int productiveScreenSeconds,
    int distractionScreenSeconds,
  ) {
    double progress = 0.0;
    bool earned = false;
    String nextMilestone = '';
    int stepsRemaining = 0;
    int earnedCount = 0;
    DateTime? firstEarnedAt;
    DateTime? earnedAt;

    switch (medal.id) {
      // === 原有勋章逻辑 ===
      case 'focus_starter':
        earned = summary.pomodoroCount >= 1;
        progress = earned ? 1.0 : (summary.pomodoroCount.clamp(0, 1).toDouble());
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '需要 1 次 Pomodoro';
        if (earned) {
          earnedCount = summary.pomodoroCount;
          firstEarnedAt = summary.actualStartTime;
          earnedAt = summary.actualEndTime;
        }
        break;

      case 'two_hour_guardian':
        progress = (totalFocusMinutes / 120).clamp(0.0, 1.0);
        earned = totalFocusMinutes >= 120;
        stepsRemaining = earned ? 0 : (120 - totalFocusMinutes);
        nextMilestone = earned ? '已获得' : '还需要 ${(120 - totalFocusMinutes)} 分钟';
        break;

      case 'eight_hour_trek':
        progress = (totalFocusMinutes / 480).clamp(0.0, 1.0);
        earned = totalFocusMinutes >= 480;
        stepsRemaining = earned ? 0 : (480 - totalFocusMinutes);
        nextMilestone = earned ? '已获得' : '还需要 ${(480 - totalFocusMinutes)} 分钟';
        break;

      case 'deep_worker':
        earned = summary.longestPomodoroMinutes >= 60;
        progress = (summary.longestPomodoroMinutes / 60).clamp(0.0, 1.0);
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '单次最长已达 ${summary.longestPomodoroMinutes} 分钟';
        break;

      case 'long_focus_specialist':
        earned = summary.longestPomodoroMinutes >= 90;
        progress = (summary.longestPomodoroMinutes / 90).clamp(0.0, 1.0);
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '单次最长已达 ${summary.longestPomodoroMinutes} 分钟';
        break;

      case 'stable_output':
        final lowInterruption = summary.interruptionRate <= 0.1;
        earned = lowInterruption && summary.pomodoroCount >= 3;
        progress = earned ? 1.0 : (summary.pomodoroCount / 3).clamp(0.0, 0.9);
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '中断率 ${(summary.interruptionRate * 100).toStringAsFixed(1)}%，需 ≤10%';
        break;

      case 'task_harvester':
        earned = completedCount >= 1;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '完成第一个任务';
        if (earned) {
          earnedCount = completedCount;
          firstEarnedAt = summary.actualStartTime;
          earnedAt = summary.actualEndTime;
        }
        break;

      case 'plan_fulfiller':
        final rate = totalCount > 0 ? completedCount / totalCount : 0.0;
        progress = (rate / 0.8).clamp(0.0, 1.0);
        earned = rate >= 0.8 && totalCount >= 3;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '当前完成率 ${(rate * 100).toStringAsFixed(0)}%，需达 80%';
        break;

      case 'early_deliverer':
        earned = earlyCompletionCount >= 1;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '还需提前完成 1 个任务';
        break;

      case 'ddl_tamer':
        earned = deadlineSprintCount >= 1;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '在 DDL 前完成 1 个任务';
        break;

      case 'night_efficiency_king':
        final isNightOwl = summary.peakHour >= 20 || summary.peakHour <= 5;
        earned = isNightOwl && totalFocusMinutes > 30;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得 (高峰: ${summary.peakHour}:00)' : '探索你的高效时段';
        break;

      case 'golden_hour':
        earned = summary.peakHour > 0;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得 (高峰: ${summary.peakHour}:00)' : '分析你的专注规律';
        break;

      case 'long_distance_runner':
        progress = (summary.consecutiveActiveDays / 3).clamp(0.0, 1.0);
        earned = summary.consecutiveActiveDays >= 3;
        stepsRemaining = earned ? 0 : (3 - summary.consecutiveActiveDays);
        nextMilestone = earned ? '已获得' : '当前连续活跃 ${summary.consecutiveActiveDays} 天';
        break;

      case 'learning_polymath':
        final subjectCount = summary.subjectDistribution.length;
        progress = (subjectCount / 4).clamp(0.0, 1.0);
        earned = subjectCount >= 4;
        stepsRemaining = earned ? 0 : (4 - subjectCount);
        nextMilestone = earned ? '已获得' : '当前涉及 $subjectCount 个学科，需 4 个';
        break;

      case 'main_line_pusher':
        final ratio = _calculateTopSubjectRatio(summary);
        progress = (ratio / 45).clamp(0.0, 1.0);
        earned = ratio >= 45 && totalFocusMinutes > 60;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '最高主题占比 ${ratio.toStringAsFixed(0)}%，需达 45%';
        break;

      case 'knowledge_scout':
        progress = (summary.searchCount / 3).clamp(0.0, 1.0);
        earned = summary.searchCount >= 3;
        stepsRemaining = earned ? 0 : (3 - summary.searchCount);
        nextMilestone = earned ? '已获得' : '当前检索 ${summary.searchCount} 次，需 3 次';
        break;

      case 'exam_prep_sprinter':
        progress = (summary.examPrepCount / 3).clamp(0.0, 1.0);
        earned = summary.examPrepCount >= 3;
        stepsRemaining = earned ? 0 : (3 - summary.examPrepCount);
        nextMilestone = earned ? '已获得' : '当前备考 ${summary.examPrepCount} 次，需 3 次';
        break;

      case 'course_companion':
        earned = courseCount >= 1;
        progress = earned ? 1.0 : 0.0;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '记录第一节课';
        break;

      case 'full_course_survivor':
        earned = maxDailyCourseCount >= 5;
        progress = (maxDailyCourseCount / 5).clamp(0.0, 1.0);
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得' : '单日最高 $maxDailyCourseCount 节课，需 5 节';
        break;

      case 'screen_master':
        final masterRatio = screenTimeSeconds > 0 ? (productiveScreenSeconds / screenTimeSeconds) * 100 : 0.0;
        progress = (masterRatio / 50).clamp(0.0, 1.0);
        earned = masterRatio >= 50;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得 (生产力 ${masterRatio.toStringAsFixed(0)}%)' : '生产力应用占比 ${masterRatio.toStringAsFixed(0)}%，需达 50%';
        break;

      case 'low_distraction_mode':
        final distractionRatio = screenTimeSeconds > 0 ? (distractionScreenSeconds / screenTimeSeconds) * 100 : 0.0;
        progress = ((100 - distractionRatio) / 85).clamp(0.0, 1.0);
        earned = distractionRatio <= 15;
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned ? '已获得 (分心 ${distractionRatio.toStringAsFixed(0)}%)' : '分心应用占比 ${distractionRatio.toStringAsFixed(0)}%，需 ≤15%';
        break;

      // === 新增扩展勋章逻辑 ===
      case 'focus_expert':
        progress = (totalFocusMinutes / (24 * 60)).clamp(0.0, 1.0);
        earned = totalFocusMinutes >= 24 * 60;
        stepsRemaining = earned ? 0 : (24 * 60 - totalFocusMinutes);
        nextMilestone = earned ? '已获得' : '还需要 ${(24 * 60 - totalFocusMinutes)} 分钟';
        break;

      case 'focus_legend':
        progress = (totalFocusMinutes / (100 * 60)).clamp(0.0, 1.0);
        earned = totalFocusMinutes >= 100 * 60;
        stepsRemaining = earned ? 0 : (100 * 60 - totalFocusMinutes);
        nextMilestone = earned ? '已获得' : '还需要 ${(100 * 60 - totalFocusMinutes)} 分钟';
        break;

      case 'pomo_runner':
        progress = (summary.pomodoroCount / 50).clamp(0.0, 1.0);
        earned = summary.pomodoroCount >= 50;
        stepsRemaining = earned ? 0 : (50 - summary.pomodoroCount);
        nextMilestone = earned ? '已获得' : '还需要 ${(50 - summary.pomodoroCount)} 个';
        if (earned) earnedCount = summary.pomodoroCount ~/ 50;
        break;

      case 'pomo_marathon':
        progress = (summary.pomodoroCount / 200).clamp(0.0, 1.0);
        earned = summary.pomodoroCount >= 200;
        stepsRemaining = earned ? 0 : (200 - summary.pomodoroCount);
        nextMilestone = earned ? '已获得' : '还需要 ${(200 - summary.pomodoroCount)} 个';
        if (earned) earnedCount = summary.pomodoroCount ~/ 200;
        break;

      case 'ultra_focus':
        earned = summary.longestPomodoroMinutes >= 120;
        progress = (summary.longestPomodoroMinutes / 120).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '单次最高 ${summary.longestPomodoroMinutes} 分钟';
        break;

      case 'distraction_immune':
        earned = summary.interruptionRate == 0 && summary.pomodoroCount >= 5;
        progress = (summary.pomodoroCount / 5).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '连续 5 次无中断';
        break;

      case 'task_millionaire':
        progress = (completedCount / 50).clamp(0.0, 1.0);
        earned = completedCount >= 50;
        if (earned) earnedCount = completedCount ~/ 50;
        nextMilestone = earned ? '已获得' : '还需完成 ${(50 - completedCount)} 个';
        break;

      case 'task_emperor':
        progress = (completedCount / 500).clamp(0.0, 1.0);
        earned = completedCount >= 500;
        if (earned) earnedCount = completedCount ~/ 500;
        nextMilestone = earned ? '已获得' : '还需完成 ${(500 - completedCount)} 个';
        break;

      case 'early_bird':
        int earlySessions = summary.hourlyDistribution.sublist(5, 8).fold(0, (a, b) => a + b);
        progress = (earlySessions / 10).clamp(0.0, 1.0);
        earned = earlySessions >= 10;
        nextMilestone = earned ? '已获得' : '还需 ${(10 - earlySessions)} 次早起专注';
        break;

      case 'night_owl':
        int lateSessions = summary.hourlyDistribution.sublist(0, 4).fold(0, (a, b) => a + b);
        progress = (lateSessions / 10).clamp(0.0, 1.0);
        earned = lateSessions >= 10;
        nextMilestone = earned ? '已获得' : '还需 ${(10 - lateSessions)} 次深夜专注';
        break;

      case 'weekend_warrior':
        final wkMins = summary.weekendFocusMinutes;
        earned = wkMins >= 300;
        progress = (wkMins / 300).clamp(0.0, 1.0);
        stepsRemaining = earned ? 0 : (300 - wkMins).clamp(1, 300);
        nextMilestone = earned ? '已获得' : '周末累计专注 $wkMins 分钟，需 300 分钟';
        break;

      case 'productivity_spike':
        final peakDay = summary.mostProductiveDayCompletedCount;
        earned = peakDay >= 10;
        progress = (peakDay / 10).clamp(0.0, 1.0);
        stepsRemaining = earned ? 0 : (10 - peakDay).clamp(1, 10);
        nextMilestone = earned ? '已获得' : '单日最高完成 $peakDay 个，需 10 个';
        break;

      case 'perfect_week':
        progress = (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
        earned = summary.consecutiveActiveDays >= 7;
        nextMilestone = earned ? '已获得' : '当前连续活跃 ${summary.consecutiveActiveDays} 天';
        break;

      case 'persistence_hero':
        progress = (summary.consecutiveActiveDays / 30).clamp(0.0, 1.0);
        earned = summary.consecutiveActiveDays >= 30;
        nextMilestone = earned ? '已获得' : '当前连续活跃 ${summary.consecutiveActiveDays} 天';
        break;

      case 'monthly_checkin':
        earned = summary.consecutiveActiveDays >= 20;
        progress = (summary.consecutiveActiveDays / 20).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '活跃天数还需 ${20 - summary.consecutiveActiveDays} 天';
        break;

      case 'steady_pulse':
        {
          final trend = summary.dailyTrend;
          final streak = summary.consecutiveActiveDays;
          bool stable = false;
          if (trend.length >= 5) {
            final last5 = trend.sublist(trend.length - 5);
            final mean = last5.fold<double>(0, (a, b) => a + b) / 5;
            if (mean > 0) {
              final variance = last5
                  .map((v) => (v - mean) * (v - mean))
                  .fold<double>(0, (a, b) => a + b) / 5;
              final cv = sqrt(variance) / mean;
              stable = cv < 0.2;
            }
          }
          earned = stable && streak >= 5;
          progress = earned
              ? 1.0
              : (streak / 5).clamp(0.0, 0.9) * (stable ? 1.0 : 0.6);
          stepsRemaining = earned ? 0 : 1;
          nextMilestone = earned
              ? '已获得'
              : '每日专注时长波动较大，需连续 5 天保持稳定';
        }
        break;

      case 'efficiency_demon':
        earned = summary.interruptionRate <= 0.05 && totalFocusMinutes > 120;
        progress = earned ? 1.0 : ((summary.interruptionRate <= 0.05 && totalFocusMinutes > 60) ? 0.8 : 0.5);
        nextMilestone = earned ? '已获得' : '中断率 ${(summary.interruptionRate * 100).toStringAsFixed(1)}%，专注需超 120 分钟';
        break;

      case 'screen_time_slayer':
        earned = summary.interruptionRate <= 0.1 &&
            summary.consecutiveActiveDays >= 7;
        progress = earned
            ? 1.0
            : (1.0 - summary.interruptionRate) *
                (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
        stepsRemaining = earned ? 0 : 1;
        nextMilestone = earned
            ? '已获得'
            : '分心 ${(summary.interruptionRate * 100).toStringAsFixed(0)}%，需 ≤10% 且连续活跃 ≥7 天';
        break;

      case 'knowledge_glutton':
        progress = (summary.searchCount / 50).clamp(0.0, 1.0);
        earned = summary.searchCount >= 50;
        if (earned) earnedCount = summary.searchCount ~/ 50;
        nextMilestone = earned ? '已获得' : '还需检索 ${50 - summary.searchCount} 次';
        break;

      case 'exam_conqueror':
        progress = (summary.examPrepCount / 20).clamp(0.0, 1.0);
        earned = summary.examPrepCount >= 20;
        if (earned) earnedCount = summary.examPrepCount ~/ 20;
        nextMilestone = earned ? '已获得' : '还需备考 ${20 - summary.examPrepCount} 次';
        break;

      case 'deep_diver':
        progress = (summary.deepWorkCount / 10).clamp(0.0, 1.0);
        earned = summary.deepWorkCount >= 10;
        if (earned) earnedCount = summary.deepWorkCount ~/ 10;
        nextMilestone = earned ? '已获得' : '还需深度专注 ${10 - summary.deepWorkCount} 次';
        break;

      case 'course_veteran':
        progress = (courseCount / 50).clamp(0.0, 1.0);
        earned = courseCount >= 50;
        if (earned) earnedCount = courseCount ~/ 50;
        nextMilestone = earned ? '已获得' : '还需上课 ${50 - courseCount} 节';
        break;

      case 'no_skip_champion':
        earned = summary.todoCompletionRate >= 0.95 && totalCount > 5;
        progress = earned ? 1.0 : (totalCount > 0 ? (summary.todoCompletionRate * (totalCount / 6).clamp(0.0, 1.0)) : 0.0);
        nextMilestone = earned ? '已获得' : '完成率 ${(summary.todoCompletionRate * 100).toStringAsFixed(0)}%，需达 95% 且任务数 > 5';
        break;

      case 'sync_pioneer':
        earned = true; 
        progress = 1.0;
        nextMilestone = '已开启云端生活';
        break;

      case 'island_resident':
        earned = totalFocusMinutes >= 600;
        progress = (totalFocusMinutes / 600).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '岛屿停留时长还需 ${600 - totalFocusMinutes} 分钟';
        break;

      case 'focus_streak_5':
        {
          final hourly = summary.hourlyDistribution;
          final maxInHour = hourly.isEmpty ? 0 : hourly.reduce(max);
          earned = maxInHour >= 5;
          progress = (maxInHour / 5).clamp(0.0, 1.0);
          stepsRemaining = earned ? 0 : 1;
          nextMilestone = earned
              ? '已获得'
              : '单小时最高 $maxInHour 次，需单日连续 5 个番茄钟';
        }
        break;

      case 'multi_tasker':
        earned = summary.subjectDistribution.length >= 3;
        progress = (summary.subjectDistribution.length / 3).clamp(0.0, 1.0);
        nextMilestone = '全能学习选手';
        break;

      case 'early_finisher_50':
        progress = (earlyCompletionCount / 50).clamp(0.0, 1.0);
        earned = earlyCompletionCount >= 50;
        if (earned) earnedCount = earlyCompletionCount ~/ 50;
        nextMilestone = earned ? '已获得' : '还需提前完成 ${50 - earlyCompletionCount} 个任务';
        break;

      case 'deadline_survivor_20':
        progress = (deadlineSprintCount / 20).clamp(0.0, 1.0);
        earned = deadlineSprintCount >= 20;
        if (earned) earnedCount = deadlineSprintCount ~/ 20;
        nextMilestone = earned ? '已获得' : '还需在 DDL 当天完成 ${20 - deadlineSprintCount} 个任务';
        break;

      // === Category: Subject Specialists (10个) ===
      case 'subject_mathematician':
        final mathMins = (summary.subjectDistribution['数学'] ?? 0) + (summary.subjectDistribution['理科'] ?? 0);
        progress = (mathMins / (20 * 60)).clamp(0.0, 1.0);
        earned = mathMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '数学理科类还需专注 ${(20 * 60 - mathMins).toInt()} 分钟';
        break;
      case 'subject_linguist':
        final langMins = summary.subjectDistribution['语言'] ?? 0;
        progress = (langMins / (20 * 60)).clamp(0.0, 1.0);
        earned = langMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '语言类还需专注 ${(20 * 60 - langMins).toInt()} 分钟';
        break;
      case 'subject_coder':
        final codeMins = (summary.subjectDistribution['编程'] ?? 0) + (summary.subjectDistribution['计算机'] ?? 0);
        progress = (codeMins / (20 * 60)).clamp(0.0, 1.0);
        earned = codeMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '编程类还需专注 ${(20 * 60 - codeMins).toInt()} 分钟';
        break;
      case 'subject_artist':
        final artMins = (summary.subjectDistribution['艺术'] ?? 0) + (summary.subjectDistribution['设计'] ?? 0);
        progress = (artMins / (20 * 60)).clamp(0.0, 1.0);
        earned = artMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '艺术类还需专注 ${(20 * 60 - artMins).toInt()} 分钟';
        break;
      case 'subject_scientist':
        final sciMins = (summary.subjectDistribution['科学'] ?? 0) + (summary.subjectDistribution['实验'] ?? 0);
        progress = (sciMins / (20 * 60)).clamp(0.0, 1.0);
        earned = sciMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '科学类还需专注 ${(20 * 60 - sciMins).toInt()} 分钟';
        break;
      case 'subject_historian':
        final histMins = (summary.subjectDistribution['历史'] ?? 0) + (summary.subjectDistribution['社科'] ?? 0);
        progress = (histMins / (20 * 60)).clamp(0.0, 1.0);
        earned = histMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '历史社科类还需专注 ${(20 * 60 - histMins).toInt()} 分钟';
        break;
      case 'subject_athlete':
        final fitMins = (summary.subjectDistribution['体育'] ?? 0) + (summary.subjectDistribution['健身'] ?? 0);
        progress = (fitMins / (20 * 60)).clamp(0.0, 1.0);
        earned = fitMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '体育健身类还需专注 ${(20 * 60 - fitMins).toInt()} 分钟';
        break;
      case 'subject_musician':
        final musicMins = summary.subjectDistribution['音乐'] ?? 0;
        progress = (musicMins / (20 * 60)).clamp(0.0, 1.0);
        earned = musicMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '音乐类还需专注 ${(20 * 60 - musicMins).toInt()} 分钟';
        break;
      case 'subject_bookworm':
        final readMins = (summary.subjectDistribution['阅读'] ?? 0) + (summary.subjectDistribution['文学'] ?? 0);
        progress = (readMins / (20 * 60)).clamp(0.0, 1.0);
        earned = readMins >= 20 * 60;
        nextMilestone = earned ? '已获得' : '文学类还需专注 ${(20 * 60 - readMins).toInt()} 分钟';
        break;
      case 'subject_polyglot':
        final deepSubjects = summary.subjectDistribution.values.where((v) => v >= 5 * 60).length;
        progress = (deepSubjects / 5).clamp(0.0, 1.0);
        earned = deepSubjects >= 5;
        nextMilestone = earned ? '已获得' : '当前 $deepSubjects 个学科达 5 小时，需 5 个';
        break;

      // === Category: Habit Masters (10个) ===
      case 'habit_early_riser':
        // 假设通过 hourlyDistribution[5-7] 模拟晨间天数统计
        int earlyDays = summary.hourlyDistribution.sublist(5, 8).fold(0, (a, b) => a + b) ~/ 2; // 近似
        progress = (earlyDays / 30).clamp(0.0, 1.0);
        earned = earlyDays >= 30;
        nextMilestone = earned ? '已获得' : '还需早起专注 ${30 - earlyDays} 天';
        break;
      case 'habit_night_reader':
        int nightDays = summary.hourlyDistribution.sublist(23).fold(0, (a, b) => a + (b > 0 ? 1 : 0)) + 
                        summary.hourlyDistribution.sublist(0, 2).fold(0, (a, b) => a + (b > 0 ? 1 : 0));
        progress = (nightDays / 30).clamp(0.0, 1.0);
        earned = nightDays >= 30;
        nextMilestone = earned ? '已获得' : '还需深夜专注 ${30 - nightDays} 天';
        break;
      case 'habit_lunch_warrior':
        int lunchDays = summary.hourlyDistribution.sublist(12, 14).fold(0, (a, b) => a + (b > 0 ? 1 : 0));
        progress = (lunchDays / 20).clamp(0.0, 1.0);
        earned = lunchDays >= 20;
        nextMilestone = earned ? '已获得' : '还需午间专注 ${20 - lunchDays} 天';
        break;
      case 'habit_streak_100':
        progress = (summary.consecutiveActiveDays / 100).clamp(0.0, 1.0);
        earned = summary.consecutiveActiveDays >= 100;
        stepsRemaining = earned ? 0 : (100 - summary.consecutiveActiveDays);
        nextMilestone = earned
            ? '已获得'
            : '当前连续 ${summary.consecutiveActiveDays} 天，需 100 天';
        break;
      case 'habit_weekly_streak_10':
        {
          final streak = summary.consecutiveActiveDays;
          // 连续活跃70天 = 10周每天活跃，必然满足"每周至少活跃5天"
          earned = streak >= 70;
          progress = (streak / 70).clamp(0.0, 1.0);
          stepsRemaining = earned ? 0 : (70 - streak).clamp(1, 70);
          nextMilestone = earned
              ? '已获得'
              : '连续活跃 $streak 天，需 70 天（10 周 × 每天）';
        }
        break;
      case 'habit_monthly_champion':
        final monthDays = summary.monthlyActiveDays;
        earned = monthDays >= 28;
        progress = (monthDays / 28).clamp(0.0, 1.0);
        stepsRemaining = earned ? 0 : (28 - monthDays);
        nextMilestone = earned ? '已获得' : '本月活跃 $monthDays 天，需达 28 天';
        break;
      case 'habit_year_companion':
        {
          final spanDays = summary.actualStartTime != null &&
                  summary.actualEndTime != null
              ? summary.actualEndTime!
                  .difference(summary.actualStartTime!)
                  .inDays
              : 0;
          progress = (spanDays / 365).clamp(0.0, 1.0);
          earned = spanDays >= 365;
          stepsRemaining = earned ? 0 : (365 - spanDays).clamp(1, 365);
          nextMilestone = earned
              ? '已获得'
              : '已使用 $spanDays 天，需满 365 天';
        }
        break;
      case 'habit_streak_resurrection':
        earned = summary.consecutiveActiveDays >= 7;
        progress = (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
        nextMilestone = '断签后的强势回归';
        break;
      case 'habit_weekend_pro':
        {
          final wkMins = summary.weekendFocusMinutes;
          final streak = summary.consecutiveActiveDays;
          // 连续活跃28天=覆盖4个连续周末; 4个周末各~4h高强度≈960分钟
          final targetMins = 960;
          earned = streak >= 28 && wkMins >= targetMins;
          progress = ((streak / 28) * (wkMins / targetMins)).clamp(0.0, 1.0);
          stepsRemaining = earned ? 0 : 1;
          nextMilestone = earned
              ? '已获得'
              : '连续活跃 $streak 天，周末专注累计 $wkMins 分钟，需 4 周 × 4h';
        }
        break;
      case 'habit_rhythm_master':
        earned = summary.consecutiveActiveDays >= 7;
        progress = (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '当前连续 ${summary.consecutiveActiveDays} 天，需 7 天';
        break;

      // === Category: Productivity Ninja (10个) ===
      case 'ninja_speed_demon':
        earned = earlyCompletionCount > 5;
        progress = (earlyCompletionCount / 5).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '还需提前完成 ${5 - earlyCompletionCount} 个任务';
        break;
      case 'ninja_bulk_completer':
        earned = completedCount >= 5;
        progress = (completedCount / 5).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '还需完成 ${5 - completedCount} 个任务';
        break;
      case 'ninja_focus_block_4':
        earned = totalFocusMinutes >= 4 * 60;
        progress = (totalFocusMinutes / 240).clamp(0.0, 1.0);
        break;
      case 'ninja_focus_block_8':
        earned = totalFocusMinutes >= 8 * 60;
        progress = (totalFocusMinutes / 480).clamp(0.0, 1.0);
        break;
      case 'ninja_deep_diver_3h':
        earned = summary.longestPomodoroMinutes >= 180;
        progress = (summary.longestPomodoroMinutes / 180).clamp(0.0, 1.0);
        break;
      case 'ninja_zero_distraction':
        earned = distractionScreenSeconds == 0 && totalFocusMinutes > 60;
        progress = earned ? 1.0 : 0.0;
        break;
      case 'ninja_planned_perfection':
        earned = totalCount > 0 && completedCount == totalCount;
        progress = earned ? 1.0 : 0.0;
        break;
      case 'ninja_inbox_zero':
        earned = totalCount > 0 && completedCount == totalCount;
        progress = totalCount > 0 ? (completedCount / totalCount).clamp(0.0, 1.0) : 0.0;
        nextMilestone = earned ? '已获得' : '还有 ${totalCount - completedCount} 个未完成';
        break;
      case 'ninja_consistency_king':
        earned = summary.consecutiveActiveDays >= 7;
        progress = (summary.consecutiveActiveDays / 7).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '当前连续 ${summary.consecutiveActiveDays} 天，需 7 天';
        break;
      case 'ninja_efficiency_max':
        final effRatio = screenTimeSeconds > 0 ? (productiveScreenSeconds / screenTimeSeconds) : 0.0;
        earned = effRatio >= 0.98;
        progress = effRatio;
        break;

      // === Category: Academic Excellence (10个) ===
      case 'academic_course_100':
        progress = (courseCount / 100).clamp(0.0, 1.0);
        earned = courseCount >= 100;
        break;
      case 'academic_exam_overlord':
        progress = (summary.examPrepCount / 50).clamp(0.0, 1.0);
        earned = summary.examPrepCount >= 50;
        break;
      case 'academic_search_guru':
        progress = (summary.searchCount / 100).clamp(0.0, 1.0);
        earned = summary.searchCount >= 100;
        break;
      case 'academic_early_finish_diamond':
        progress = (earlyCompletionCount / 100).clamp(0.0, 1.0);
        earned = earlyCompletionCount >= 100;
        break;
      case 'academic_no_skip_month':
        earned = summary.consecutiveActiveDays >= 30;
        progress = (summary.consecutiveActiveDays / 30).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '当前连续 ${summary.consecutiveActiveDays} 天，需 30 天';
        break;
      case 'academic_full_house_7':
        earned = maxDailyCourseCount >= 7;
        progress = (maxDailyCourseCount / 7).clamp(0.0, 1.0);
        break;
      case 'academic_bridge_builder':
        earned = summary.searchCount >= 20 && summary.pomodoroCount >= 20;
        progress = ((summary.searchCount / 20 + summary.pomodoroCount / 20) / 2).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '检索 ${summary.searchCount}/20，专注 ${summary.pomodoroCount}/20';
        break;
      case 'academic_library_phantom':
        final libMins = summary.subjectDistribution['图书馆'] ?? 0;
        progress = (libMins / (50 * 60)).clamp(0.0, 1.0);
        earned = libMins >= 50 * 60;
        break;
      case 'academic_top_of_class':
        earned = totalFocusMinutes > 5000;
        progress = (totalFocusMinutes / 5000).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '还需专注 ${5000 - totalFocusMinutes} 分钟';
        break;
      case 'academic_deep_thinker':
        progress = (summary.deepWorkCount / 50).clamp(0.0, 1.0);
        earned = summary.deepWorkCount >= 50;
        break;

      // === Category: App Explorer (10个) ===
      case 'explorer_widget_loyalist':
        earned = true; // 无法直接检测，暂定已体验
        progress = 1.0;
        break;
      case 'explorer_island_pro_100':
        progress = (totalFocusMinutes / 6000).clamp(0.0, 1.0);
        earned = totalFocusMinutes >= 6000;
        break;
      case 'explorer_sync_master':
        earned = true;
        progress = 1.0;
        break;
      case 'explorer_countdown_master':
        earned = true;
        progress = 1.0;
        break;
      case 'explorer_reminder_loyalist':
        earned = true;
        progress = 1.0;
        break;
      case 'explorer_report_analyzer':
        earned = true;
        progress = 1.0;
        break;
      case 'explorer_multi_subject_10':
        earned = summary.subjectDistribution.length >= 10;
        progress = (summary.subjectDistribution.length / 10).clamp(0.0, 1.0);
        break;
      case 'explorer_pathfinder_10':
        earned = summary.searchCount >= 10;
        progress = (summary.searchCount / 10).clamp(0.0, 1.0);
        nextMilestone = earned ? '已获得' : '还需探索 ${10 - summary.searchCount} 个领域';
        break;
      case 'explorer_night_watch':
        int lateSessions = summary.hourlyDistribution.sublist(2, 5).fold(0, (a, b) => a + b);
        earned = lateSessions > 0;
        progress = earned ? 1.0 : 0.0;
        break;
      case 'explorer_app_pioneer':
        earned = true;
        progress = 1.0;
        break;

      default:
        progress = 0.0;
        stepsRemaining = 1;
        nextMilestone = '待实现';
        break;
    }

    return MedalProgress(
      medal: medal,
      progress: progress,
      earned: earned,
      nextMilestone: nextMilestone,
      stepsRemaining: stepsRemaining,
      earnedCount: earnedCount,
      firstEarnedAt: firstEarnedAt,
      earnedAt: earnedAt,
    );
  }

  /// 计算顶部主题的占比
  static double _calculateTopSubjectRatio(TimelineSummary summary) {
    if (summary.subjectDistribution.isEmpty) return 0.0;
    final total = summary.subjectDistribution.values.fold<double>(0.0, (sum, val) => sum + val);
    if (total == 0) return 0.0;
    final topValue = summary.subjectDistribution.values.fold<double>(0.0, (max, val) => val > max ? val : max);
    return (topValue / total) * 100;
  }

  /// 生成推荐（获取未获得的勋章，按步数排序）
  static List<MedalProgress> recommendNext(List<MedalProgress> allProgresses) {
    final unearned = allProgresses.where((p) => !p.earned && p.progress < 1.0).toList();
    unearned.sort((a, b) => a.stepsRemaining.compareTo(b.stepsRemaining));
    return unearned.take(6).toList();
  }

  /// 完整推荐流程
  static MedalRecommendation getRecommendations(
    TimelineSummary summary,
    int totalFocusMinutes,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
    int courseCount,
    int maxDailyCourseCount,
    int screenTimeSeconds,
    int productiveScreenSeconds,
    int distractionScreenSeconds,
  ) {
    final allProgresses = allMedals.map((medal) {
      return calculateMedalProgress(
        medal,
        summary,
        totalFocusMinutes,
        completedCount,
        totalCount,
        earlyCompletionCount,
        deadlineSprintCount,
        courseCount,
        maxDailyCourseCount,
        screenTimeSeconds,
        productiveScreenSeconds,
        distractionScreenSeconds,
      );
    }).toList();

    final earned = allProgresses.where((p) => p.earned).toList();
    final recommendations = recommendNext(allProgresses);

    return MedalRecommendation(
      topRecommendations: recommendations,
      allMedals: allProgresses,
      earnedMedals: earned,
    );
  }

  /// ML-enhanced recommendation: feature scoring + Thompson Sampling bandit
  /// Returns a full [MedalRecommendation] with isML=true and per-medal reasons.
  static Future<MedalRecommendation> recommendNextML(
    List<MedalProgress> allProgresses,
    TimelineSummary summary,
    int totalFocusMinutes,
    int completedCount,
    int totalCount,
    int earlyCompletionCount,
    int deadlineSprintCount,
    int screenTimeSeconds,
    int productiveScreenSeconds,
    int distractionScreenSeconds,
  ) async {
    try {
      final earned = allProgresses.where((p) => p.earned).toList();
      // Exclude anomalies: progress >= 1.0 but not marked earned
      final unearned = allProgresses.where((p) => !p.earned && p.progress < 1.0).toList();
      if (unearned.isEmpty) {
        return MedalRecommendation(
          topRecommendations: [],
          allMedals: allProgresses,
          earnedMedals: earned,
          isML: true,
        );
      }

      // 1. Extract user features
      final features = MedalFeatureExtractor.extractFeatures(
        summary,
        totalFocusMinutes,
        completedCount,
        totalCount,
        earlyCompletionCount,
        deadlineSprintCount,
        screenTimeSeconds,
        productiveScreenSeconds,
        distractionScreenSeconds,
      );

      // 2. Compute earned medals per category for diversity bonus
      final earnedPerCategory = <String, int>{};
      for (final p in earned) {
        earnedPerCategory[p.medal.category] = (earnedPerCategory[p.medal.category] ?? 0) + 1;
      }

      // 3. Get bandit samples
      final banditService = MedalBanditService.instance;
      final banditSamples = await banditService.sampleAll(
        unearned.map((p) => p.medal.id).toList(),
      );

      // 4. Update outcomes from previous recommendations
      await banditService.updateOutcomes(allProgresses);

      // 5. Score each medal and generate reasons
      final scored = <_ScoredEntry>[];
      for (final progress in unearned) {
        final breakdown = MedalFeatureExtractor.scoreMedalWithBreakdown(
          progress, features, earnedPerCategory,
        );
        final banditSample = banditSamples[progress.medal.id] ?? 0.5;
        final totalObs = await banditService.getObservationCount(progress.medal.id);
        final combined = _combinedScore(breakdown.total, banditSample, totalObs);
        final reason = _generateReason(breakdown, progress, banditSample, totalObs);
        scored.add(_ScoredEntry(progress: progress, score: combined, reason: reason));
      }

      // 6. Sort by combined score descending, take top 6
      scored.sort((a, b) => b.score.compareTo(a.score));
      final top6 = scored.take(6).toList();

      // 7. Record impressions for bandit learning
      await banditService.recordImpressions(top6.map((s) => s.progress.medal.id).toList());

      // 8. Build reasons map
      final reasons = <String, String>{};
      for (final entry in top6) {
        reasons[entry.progress.medal.id] = entry.reason;
      }

      return MedalRecommendation(
        topRecommendations: top6.map((s) => s.progress).toList(),
        allMedals: allProgresses,
        earnedMedals: earned,
        isML: true,
        recommendReasons: reasons,
      );
    } catch (e) {
      debugPrint('ML recommendation failed, falling back: $e');
      final fallback = recommendNext(allProgresses);
      return MedalRecommendation(
        topRecommendations: fallback,
        allMedals: allProgresses,
        earnedMedals: allProgresses.where((p) => p.earned).toList(),
        isML: false,
      );
    }
  }

  static String _generateReason(
    ScoreBreakdown breakdown,
    MedalProgress progress,
    double banditSample,
    int totalObs,
  ) {
    final parts = <String>[];

    // Proximity: strongest signal
    if (breakdown.proximity > 0.7) {
      parts.add('已完成 ${(progress.progress * 100).toInt()}%，距离解锁很近');
    } else if (breakdown.proximity > 0.4) {
      parts.add('进度 ${(progress.progress * 100).toInt()}%，稳步推进中');
    }

    // Category affinity
    if (breakdown.affinity > 0.6) {
      final catLabel = _categoryLabel(progress.medal.category);
      parts.add('匹配你擅长的$catLabel领域');
    }

    // Velocity: recent activity
    if (breakdown.velocity > 0.6) {
      parts.add('你最近在这个领域很活跃');
    }

    // Diversity: under-explored category
    if (breakdown.diversity > 0.6) {
      parts.add('拓展新的成就领域');
    }

    // Challenge preference
    if (breakdown.challenge > 0.7 && progress.medal.priority >= 4) {
      parts.add('适合你挑战高难度的习惯');
    } else if (breakdown.challenge > 0.7 && progress.medal.priority <= 2) {
      parts.add('轻松入门，建立信心');
    }

    // Bandit learning signal
    if (totalObs >= 10 && banditSample > 0.65) {
      parts.add('历史数据表明你倾向完成此类勋章');
    }

    if (parts.isEmpty) {
      parts.add('综合评估推荐');
    }

    return parts.join('；');
  }

  static String _categoryLabel(String category) {
    switch (category) {
      case 'focus': return '专注';
      case 'completion': return '完成';
      case 'persistence': return '坚持';
      case 'efficiency': return '效率';
      case 'breadth': return '广度';
      default: return category;
    }
  }

  /// Blend feature score with bandit sample.
  /// Cold start: 100% feature. After 50+ observations: 60% feature / 40% bandit.
  static double _combinedScore(double featureScore, double banditSample, int totalObservations) {
    final banditConfidence = (totalObservations / 50.0).clamp(0.0, 1.0);
    final banditWeight = 0.4 * banditConfidence;
    final featureWeight = 1.0 - banditWeight;
    return featureWeight * featureScore + banditWeight * banditSample;
  }
}

class _ScoredEntry {
  final MedalProgress progress;
  final double score;
  final String reason;
  const _ScoredEntry({required this.progress, required this.score, required this.reason});
}
