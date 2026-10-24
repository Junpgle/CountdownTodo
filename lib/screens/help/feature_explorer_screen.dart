import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/finance/screens/finance_home_screen.dart';
import '../../features/habits/screens/habit_center_screen.dart';
import '../../features/journal/screens/journal_home_screen.dart';
import '../../features/thirty_day_challenge/screens/challenge_center_screen.dart';
import '../../models/todo_create_save_result.dart';
import '../../services/feature_tip_service.dart';
import '../../services/onboarding_checklist_service.dart';
import '../../storage_service.dart';
import '../../utils/app_dialogs.dart';
import '../../utils/app_platform.dart';
import '../../utils/page_transitions.dart';
import '../../utils/countdown_todo_tutorial_links.dart';
import '../../widgets/floating_glass_control.dart';
import '../../widgets/global_search_overlay.dart';
import '../../widgets/optional_liquid_glass_surface.dart';
import '../add_todo_screen.dart';
import '../ai_assistant_tutorial_screen.dart';
import '../animation_settings_page.dart';
import '../band_sync_screen.dart';
import '../conflict_inbox_screen.dart';
import '../course_calendar_adjustment_screen.dart';
import '../course_screens.dart';
import '../feature_guide_screen.dart';
import '../fixed_schedule_editor_screen.dart';
import '../historical_todos_screen.dart';
import '../home_settings_screen.dart';
import '../math_menu_screen.dart';
import '../personal_timeline_screen.dart';
import '../pomodoro_screen.dart';
import '../settings/device_calendar_read_page.dart';
import '../settings/lan_sync_screen.dart';
import '../settings/pages/platform_specific_settings_page.dart';
import '../settings/pages/preference_settings_page.dart';
import '../team_management_screen.dart';
import '../time_log_screen.dart';
import '../todo_plan_screen.dart';

enum FeatureExplorerCategory {
  all('全部', Icons.apps_rounded),
  recent('近期新增', Icons.new_releases_rounded),
  schedule('时间与日程', Icons.calendar_month_rounded),
  focus('专注与复盘', Icons.timer_rounded),
  growth('成长与生活', Icons.self_improvement_rounded),
  aiAndSync('AI 与多端', Icons.auto_awesome_rounded),
  hiddenTips('隐藏神技', Icons.lightbulb_rounded);

  final String label;
  final IconData icon;
  const FeatureExplorerCategory(this.label, this.icon);
}

class FeatureExplorerItem {
  final String id;
  final String title;
  final String subtitle;
  final String locationPath;
  final FeatureExplorerCategory category;
  final IconData icon;
  final String? badgeText;
  final bool isNew;
  final List<String> keywords;
  final List<String> steps;
  final String actionLabel;
  final String? tutorialLabel;
  final Uri? tutorialUri;
  final Widget Function(BuildContext context, String username)? pageBuilder;
  final Future<void> Function(BuildContext context, String username)?
  customAction;

  const FeatureExplorerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.locationPath,
    required this.category,
    required this.icon,
    this.badgeText,
    this.isNew = false,
    this.keywords = const [],
    required this.steps,
    required this.actionLabel,
    this.tutorialLabel,
    this.tutorialUri,
    this.pageBuilder,
    this.customAction,
  });
}

class FeatureExplorerScreen extends StatefulWidget {
  final String? username;
  final bool isEmbedded;
  final FeatureExplorerCategory initialCategory;

  const FeatureExplorerScreen({
    super.key,
    this.username,
    this.isEmbedded = false,
    this.initialCategory = FeatureExplorerCategory.all,
  });

  @override
  State<FeatureExplorerScreen> createState() => _FeatureExplorerScreenState();
}

class _FeatureExplorerScreenState extends State<FeatureExplorerScreen> {
  final TextEditingController _searchController = TextEditingController();
  late FeatureExplorerCategory _selectedCategory = widget.initialCategory;
  String _searchQuery = '';
  Set<String> _seenBadges = const {};

  @override
  void initState() {
    super.initState();
    _loadSeenBadges();
    FeatureTipService.revision.addListener(_loadSeenBadges);
    OnboardingChecklistService.markTaskCompleted(
      OnboardingChecklistService.taskExploreFeatureHub,
    );
  }

  @override
  void dispose() {
    FeatureTipService.revision.removeListener(_loadSeenBadges);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeenBadges() async {
    final seen = await FeatureTipService.getSeenFeatureBadges();
    if (!mounted) return;
    setState(() {
      _seenBadges = seen;
    });
  }

  Future<String> _resolveUsername() async {
    final provided = widget.username?.trim();
    if (provided != null && provided.isNotEmpty) return provided;
    return await StorageService.getLoginSession() ?? 'default';
  }

  List<FeatureExplorerItem> _buildCatalog() {
    return [
      // ── 时间与日程 ──────────────────────────────────────────
      FeatureExplorerItem(
        id: 'fixed_schedule_related_todo',
        title: '固定日程与关联待办',
        subtitle: '管理每周例会、自习或班次，可直接关联待办并在改期时自动复核截止时间',
        locationPath: '底部导航「周视图」> 右上角「+」> 固定日程',
        category: FeatureExplorerCategory.schedule,
        icon: Icons.event_repeat_rounded,
        badgeText: 'v7.1 新增',
        isNew: true,
        keywords: const ['固定日程', '例会', '关联待办', '改期', '复核', '周视图', '重复日程'],
        steps: const [
          '从底部导航进入「周视图」，点击右上角「+」或在网格空白处拖拽创建固定日程。',
          '在固定日程详情或编辑页中，点击「关联待办」可绑定现有待办或直接新建关联待办。',
          '当固定日程调整时间或改期时，系统会自动提示复核关联待办的截止期限，防止遗漏。',
          '支持单次修改、此后修改或整个重复系列修改。',
        ],
        actionLabel: '新建固定日程',
        pageBuilder: (_, username) =>
            FixedScheduleEditorScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'todo_plan_center',
        title: '规划中心与时间块排期',
        subtitle: '把待办任务拖拽安排到今日/本周时间轴，将“要做什么”变成“几点到几点做”',
        locationPath: '首页「今日日程与规划」卡片 / 侧边栏「规划中心」',
        category: FeatureExplorerCategory.schedule,
        icon: Icons.edit_calendar_rounded,
        badgeText: 'v6.7 升级',
        isNew: true,
        keywords: const [
          '规划中心',
          '规划块',
          '时间块',
          '排期',
          '拆分',
          '待办池',
          '智能规划',
          'v4.6',
          'v6.7',
        ],
        steps: const [
          '从首页点击「今日日程与规划」卡片或从侧边栏进入「规划中心」。',
          '从待安排池中选择待办，分配到今天或未来几天的具体空闲时段。',
          '遇到耗时长的大任务，可使用「拆分」功能切成多个可执行时间块。',
          '配置「每周可安排时间」后，系统能自动识别你的空闲预算。',
        ],
        actionLabel: '打开规划中心',
        pageBuilder: (_, username) => TodoPlanScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'todos_and_countdowns',
        title: '待办事项与重要倒数日',
        subtitle: '支持按天/周/月/自定义周期循环、文件夹归类、快递/取件码识别上岛与历史归档',
        locationPath: '首页底部「+」按钮 / 首页待办与倒计时卡片',
        category: FeatureExplorerCategory.schedule,
        icon: Icons.task_alt_rounded,
        badgeText: 'v1.0 经典',
        keywords: const [
          '待办',
          '倒数日',
          '倒计时',
          '循环',
          '重复',
          '文件夹',
          '考试',
          '纪念日',
          'v1.0',
        ],
        steps: const [
          '点击首页底部中央「+」按钮，可快速选择创建「待办」或「倒计时」。',
          '待办支持设置截止时间、开始时段、全天事项、提前提醒以及循环规则（每日/每周/每月/自定义天数）。',
          '包含“取件码/取餐码/快递”字样的今日待办会自动高亮并推送到灵动岛/通知栏。',
          '点击待办卡片右上角的文件夹图标可管理分类，点击历史图标可恢复误删或查看已完成记录。',
        ],
        actionLabel: '去新建待办',
        customAction: (context, username) async {
          final groups = await StorageService.getTodoGroups(username);
          if (!context.mounted) return;
          await Navigator.of(context, rootNavigator: true).push(
            PageTransitions.slideHorizontal(
              AddTodoScreen(
                todoGroups: groups,
                onTodoAdded: (todo) async {
                  final todos = await StorageService.getTodos(username);
                  final idx = todos.indexWhere((item) => item.id == todo.id);
                  if (idx < 0) {
                    todos.add(todo);
                  } else {
                    todos[idx] = todo;
                  }
                  await StorageService.saveTodos(username, todos);
                },
                onManualTodoSaved: (todo) async {
                  final todos = await StorageService.getTodos(username);
                  final idx = todos.indexWhere((item) => item.id == todo.id);
                  if (idx < 0) {
                    todos.add(todo);
                  } else {
                    todos[idx] = todo;
                  }
                  await StorageService.saveTodos(username, todos);
                  return const TodoCreateSaveResult();
                },
              ),
            ),
          );
        },
      ),
      FeatureExplorerItem(
        id: 'todo_folders_and_groups',
        title: '待办文件夹与精细分组',
        subtitle: '按工作、生活、学习分门别类归纳待办，支持首页快速切换、文件夹折叠与批量归类',
        locationPath: '首页「待办事项」卡片右上角「文件夹」图标',
        category: FeatureExplorerCategory.schedule,
        icon: Icons.folder_special_rounded,
        badgeText: 'v4.6 新增',
        keywords: const [
          '文件夹',
          '分组',
          '归类',
          '标签',
          '分类',
          '待办管理',
          'v4.6',
        ],
        steps: const [
          '在首页「待办事项」卡片右上角点击文件夹图标进入分类管理。',
          '可自定义创建不同主题与颜色的文件夹（例如“考研备考”、“日常琐事”、“工作项目”）。',
          '首页待办卡片支持一键过滤切换指定文件夹，让当下的焦点任务一目了然。',
          '新建或编辑待办时可选择归属文件夹，也支持长按待办批量移动分组。',
        ],
        actionLabel: '管理待办分组',
        customAction: (context, username) async {
          final groups = await StorageService.getTodoGroups(username);
          if (!context.mounted) return;
          await Navigator.of(context, rootNavigator: true).push(
            PageTransitions.slideHorizontal(
              AddTodoScreen(
                todoGroups: groups,
                onTodoAdded: (todo) async {
                  final todos = await StorageService.getTodos(username);
                  final idx = todos.indexWhere((item) => item.id == todo.id);
                  if (idx < 0) {
                    todos.add(todo);
                  } else {
                    todos[idx] = todo;
                  }
                  await StorageService.saveTodos(username, todos);
                },
                onManualTodoSaved: (todo) async {
                  final todos = await StorageService.getTodos(username);
                  final idx = todos.indexWhere((item) => item.id == todo.id);
                  if (idx < 0) {
                    todos.add(todo);
                  } else {
                    todos[idx] = todo;
                  }
                  await StorageService.saveTodos(username, todos);
                  return const TodoCreateSaveResult();
                },
              ),
            ),
          );
        },
      ),
      FeatureExplorerItem(
        id: 'course_schedule_and_import',
        title: '课程表与教务一键导入',
        subtitle: '支持主流高校教务系统导入、周视图/月视图切换、午休折叠与学期进度条',
        locationPath: '底部导航「周视图」/ 设置 > 课表与学期',
        category: FeatureExplorerCategory.schedule,
        icon: Icons.school_rounded,
        badgeText: 'v1.0 经典',
        keywords: const [
          '课程表',
          '课表',
          '教务导入',
          '开学',
          '学期',
          '周视图',
          '月视图',
          'v1.0',
        ],
        steps: const [
          '前往「设置 > 课表与学期」开启学期设置，可从教务系统网页或课表文件一键导入课程。',
          '在首页底部点击「周视图」可查看整周课程、固定日程与规划块，并支持切换到半月/月视图。',
          '周视图支持折叠空置的午休时段，让课表紧凑清晰。',
          '开启学期起止日期后，首页顶部会自动显示当前教学周与学期进度条。',
        ],
        actionLabel: '打开周视图',
        pageBuilder: (_, username) => WeeklyCourseScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'course_holiday_adjustment',
        title: '法定节假日放假与调休',
        subtitle: '遇到国庆、五一等法定节假日调休补课，一键将某天的课表平移到补课日',
        locationPath: '设置 > 课表与学期 > 放假与调休安排',
        category: FeatureExplorerCategory.schedule,
        icon: Icons.rule_folder_rounded,
        badgeText: 'v4.13 新增',
        keywords: const [
          '调休',
          '放假',
          '节假日',
          '补课',
          '换课',
          '课表调整',
          'v4.13',
        ],
        steps: const [
          '进入「设置 > 课表与学期 > 放假与调休安排」。',
          '内置官方节假日调休预设提醒，也可手动添加放假日期（当天课程自动停课）。',
          '添加「调休补课」映射（例如把周三的课调到周六上），周视图和首页提醒会自动按调休后课表运行。',
        ],
        actionLabel: '配置放假与调休',
        pageBuilder: (_, _) => const CourseCalendarAdjustmentScreen(),
      ),
      if (DeviceCalendarReadServicePlaceholder.isSupportedPlatform)
        FeatureExplorerItem(
          id: 'device_calendar_read',
          title: '手机系统日历只读融合',
          subtitle: '将系统日历日程只读显示在首页与周视图中，零上传、零修改系统日历',
          locationPath: '设置 > 数据与互联 > 读取手机日历',
          category: FeatureExplorerCategory.schedule,
          icon: Icons.perm_contact_calendar_rounded,
          badgeText: 'v6.2 新增',
          isNew: true,
          keywords: const [
            '手机日历',
            '系统日历',
            '苹果日历',
            '只读',
            '日程同步',
            'v6.2',
          ],
          steps: const [
            '前往「设置 > 数据与互联 > 读取手机日历」。',
            '授权日历读取权限并勾选需要展示的系统日历账本。',
            '系统日程会直接融合显示在首页今日日程与周视图中，且绝不会上传云端或改动系统日历。',
          ],
          actionLabel: '配置手机日历',
          pageBuilder: (_, _) => const DeviceCalendarReadPage(),
        ),

      // ── 专注与复盘 ──────────────────────────────────────────
      FeatureExplorerItem(
        id: 'pomodoro_focus',
        title: '番茄钟与跨端实时专注',
        subtitle: '支持倒计时/正计时、绑定待办与标签、多设备实时同步专注状态与灵动岛展示',
        locationPath: '底部导航「番茄钟」/ 首页专注Tab',
        category: FeatureExplorerCategory.focus,
        icon: Icons.timer_rounded,
        badgeText: 'v3.0 升级',
        keywords: const [
          '番茄钟',
          '专注',
          '正计时',
          '倒计时',
          '标签',
          '跨端同步',
          'v1.0',
          'v3.0',
        ],
        steps: const [
          '点击底部导航栏的「番茄钟」图标进入专注工作台。',
          '可选择倒计时或正计时模式，绑定当前正在攻克的待办事项与专注标签。',
          '登录同一账号后，手机开启专注，电脑端/平板端与桌面悬浮窗会通过 WebSocket 实时同步显示专注进度。',
        ],
        actionLabel: '开启专注',
        pageBuilder: (_, username) => PomodoroScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'time_log_and_backfill',
        title: '时间日志与拖拽补录',
        subtitle: '忘记开番茄钟？可在时间轴网格上直接拖拽补录过去的时间开销',
        locationPath: '侧边栏「时间日志」/ 专注页统计',
        category: FeatureExplorerCategory.focus,
        icon: Icons.history_edu_rounded,
        badgeText: 'v3.0 升级',
        keywords: const [
          '时间日志',
          '补录',
          '时间记录',
          '拖拽创建',
          '复盘',
          'v2.8',
          'v3.0',
        ],
        steps: const [
          '从侧边栏打开「时间日志」页面。',
          '点击右上角「补录」按钮，或直接在日历网格空白处上下拖拽，即可快速框选时间段创建记录。',
          '支持关联专注标签与分类统计，让每一天的真实时间去向清晰可查。',
        ],
        actionLabel: '打开时间日志',
        pageBuilder: (_, username) => TimeLogScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'pomodoro_habit_link',
        title: '专注时长自动联动习惯打卡',
        subtitle: '设置时长型习惯并绑定标签，番茄钟专注完成后自动累计打卡进度，告别手动记录',
        locationPath: '侧边栏「习惯中心」/ 底部导航「番茄钟」',
        category: FeatureExplorerCategory.focus,
        icon: Icons.auto_mode_rounded,
        badgeText: 'v6.0 新增',
        keywords: const [
          '习惯联动',
          '时长型习惯',
          '自动打卡',
          '专注标签',
          '番茄钟',
          '习惯中心',
          'v6.0',
        ],
        steps: const [
          '前往「侧边栏 > 习惯中心」，新建或编辑习惯时将类型设为「专注时长型」。',
          '为习惯绑定对应的专注标签（例如“背单词”、“深度阅读”）。',
          '在番茄钟专注工作台选择该标签并完成专注，系统会自动累计当日习惯时长，无需重复打卡。',
        ],
        actionLabel: '前往习惯中心',
        pageBuilder: (_, username) => HabitCenterScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'personal_timeline_report',
        title: '个人时间轴与全维报告',
        subtitle: '按日/周/月/年汇总你的专注、待办完成率、习惯打卡与屏幕使用分布',
        locationPath: '侧边栏「个人报告」/ 首页「专注」Tab',
        category: FeatureExplorerCategory.focus,
        icon: Icons.timeline_rounded,
        badgeText: 'v4.16 新增',
        keywords: const [
          '个人报告',
          '时间轴',
          '周报',
          '月报',
          '年报',
          '统计',
          '效率分析',
          'v4.16',
        ],
        steps: const [
          '从侧边栏点击「个人报告」，或切换到首页右下角「专注」Tab 点击个人时间轴卡片。',
          '支持按日、周、月、年四个维度查看效率趋势、时间分布饼图与里程碑回顾。',
          '在报告页还可进入「勋章墙」，查看已解锁的专注与坚持成就。',
        ],
        actionLabel: '查看个人报告',
        pageBuilder: (_, username) =>
            PersonalTimelineScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'private_journal',
        title: '私密日记本',
        subtitle: '记录每日心情、复盘与随想，支持图文排版与关键词检索',
        locationPath: '侧边栏「日记」/ 全局搜索「日记」',
        category: FeatureExplorerCategory.focus,
        icon: Icons.auto_stories_rounded,
        badgeText: 'v5.7 新增',
        keywords: const [
          '日记',
          '私密日记',
          '随笔',
          '心情',
          '复盘笔记',
          'v5.7',
        ],
        steps: const [
          '打开首页左上角侧边栏，点击「日记」即可进入私密日记本。',
          '支持记录每日思考、插入图片与心情标签，并通过全局搜索快速检索往期日记。',
        ],
        actionLabel: '打开日记本',
        pageBuilder: (_, username) => JournalHomeScreen(username: username),
      ),

      // ── 成长与生活 ──────────────────────────────────────────
      FeatureExplorerItem(
        id: 'finance_and_ai_bill',
        title: '个人记账与 AI 账单识别',
        subtitle: '支持月度累计结余趋势、多维分类筛选、预算管理，以及一句话/付款截图自动生成账单草案',
        locationPath: '侧边栏「记账」/ 首页底部「+」> 记账',
        category: FeatureExplorerCategory.growth,
        icon: Icons.account_balance_wallet_outlined,
        badgeText: 'v7.1 升级',
        isNew: true,
        keywords: const [
          '记账',
          '账单',
          '预算',
          '结余趋势',
          '花销',
          '收入',
          '支出',
          '借款',
          '截图记账',
          'v5.8',
          'v7.1',
        ],
        steps: const [
          '点击底部「+ > 记账」或从侧边栏进入「记账」首页，查看本月收支概览与新增的「月度累计结余趋势图」。',
          '点击结余趋势节点或使用账单列表的日期/分类筛选，可一键汇总多笔账单合计。',
          '支持自然语言输入（如“午饭 28.5 元微信支付”）或从系统相册把付款截图分享给 App，自动生成可编辑草案。',
          '所有 AI 识别结果都会先进入草案供你核对，绝不未经确认直接写入账本。',
        ],
        actionLabel: '打开记账中心',
        tutorialLabel: 'AI 高阶教程',
        tutorialUri: CountdownTodoTutorialLinks.aiAssistantAdvanced,
        pageBuilder: (_, username) => FinanceHomeScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'habit_center',
        title: '习惯中心与防误触盖章',
        subtitle: '支持完成型、专注时长型、数量型、时间点型四种习惯，带热力图与连续打卡统计',
        locationPath: '侧边栏「习惯中心」/ 首页「专注」Tab 今日习惯卡片',
        category: FeatureExplorerCategory.growth,
        icon: Icons.track_changes_rounded,
        badgeText: 'v7.1 优化',
        isNew: true,
        keywords: const [
          '习惯',
          '打卡',
          '早起',
          '背单词',
          '喝水',
          '运动',
          '热力图',
          '盖章',
          'v6.0',
          'v7.1',
        ],
        steps: const [
          '从侧边栏或首页「专注」Tab 进入「习惯中心」，点击新建习惯。',
          '可选择普通打卡、按数量打卡（如喝 8 杯水）、按时间点打卡（如 23:00 前早睡）或绑定番茄钟标签自动累计时长。',
          '支持防误触延迟盖章动效、日历视图回溯补卡与趋势分析。',
        ],
        actionLabel: '打开习惯中心',
        pageBuilder: (_, username) => HabitCenterScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'thirty_day_challenge',
        title: '挑战中心（30天找到全新自我）',
        subtitle: '自由导入或从云端题库挑选挑战清单，支持随机抽卡、图文打卡与生成长图报告分享',
        locationPath: '侧边栏「挑战中心」/ 设置 > 帮助与反馈 > 挑战中心',
        category: FeatureExplorerCategory.growth,
        icon: Icons.auto_awesome_rounded,
        badgeText: 'v6.2 新增',
        keywords: const [
          '挑战',
          '30天挑战',
          '抽卡',
          '生活记录',
          '挑战报告',
          '分享挑战',
          'v6.2',
        ],
        steps: const [
          '进入「挑战中心」，可从公共挑战库挑选，或按行粘贴/导入 `.txt/.md` 创建你自己的挑战清单。',
          '不知道今天做什么时，点「随机抽卡」从未完成任务中抽取一项去体验。',
          '完成后可写下当下感受并配图，挑战结束后一键导出精美图文报告分享给好友。',
        ],
        actionLabel: '探索挑战中心',
        pageBuilder: (_, _) => const ChallengeCenterScreen(),
      ),
      FeatureExplorerItem(
        id: 'medal_wall_achievements',
        title: '勋章墙与成长成就体系',
        subtitle: '累计专注时长、连续待办打卡、习惯沉淀，解锁数十枚精美成就勋章与高光时刻',
        locationPath: '侧边栏「个人报告」> 勋章墙 / 首页专注Tab',
        category: FeatureExplorerCategory.growth,
        icon: Icons.military_tech_rounded,
        badgeText: 'v5.5 新增',
        keywords: const [
          '勋章',
          '成就',
          '里程碑',
          '专注打卡',
          '奖励',
          '荣誉',
          '坚持',
          'v5.5',
        ],
        steps: const [
          '从侧边栏点击「个人报告」，在报告页面点击右上角「勋章墙」。',
          '涵盖专注大师、自律达人、早起打卡、多端极客等数十枚动态成就勋章。',
          '达成里程碑时会弹出动态祝贺卡片，记录你的每一次自我超越。',
        ],
        actionLabel: '查看个人报告与勋章',
        pageBuilder: (_, username) =>
            PersonalTimelineScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'math_wake_up_quiz',
        title: '数学心算测验',
        subtitle: '用几道快速四则运算激活大脑专注状态，支持难度调节与答题统计',
        locationPath: '首页「数学测验」卡片 / 全局搜索「数学测验」',
        category: FeatureExplorerCategory.growth,
        icon: Icons.functions_rounded,
        badgeText: 'v3.0 升级',
        keywords: const [
          '数学',
          '测验',
          '心算',
          '口算',
          '提神',
          'v1.0',
          'v3.0',
        ],
        steps: const [
          '在首页找到「数学测验」卡片（若隐藏可在 设置 > 偏好设置 > 首页布局 中开启），或直接点击下方按钮进入。',
          '开始专注前做一轮快速心算，帮助大脑快速进入状态。',
        ],
        actionLabel: '开始数学测验',
        pageBuilder: (_, username) => MathMenuScreen(username: username),
      ),

      // ── AI 与多端黑科技 ──────────────────────────────────────────
      FeatureExplorerItem(
        id: 'ai_assistant_and_tutorial',
        title: 'AI 智能助手与图文识别',
        subtitle: '一句话增删改查待办、查询课表空档、录入账单草案、识别截图中的通知与取件码',
        locationPath: '首页右上角「AI 机器人」图标 / 长按底部「+」按钮',
        category: FeatureExplorerCategory.aiAndSync,
        icon: Icons.smart_toy_outlined,
        badgeText: 'v7.1 升级',
        isNew: true,
        keywords: const [
          'AI',
          '助手',
          '大模型',
          '语音',
          '识图',
          '截图',
          '取件码',
          '自然语言',
          'v3.0',
          'v7.1',
        ],
        steps: const [
          '点击首页右上角 AI 图标进入对话，可直接说：“帮我把明天下午3点的开会加到待办”或“统计这周餐饮花了多少钱”。',
          '把微信群通知截图、课程表截图或支付账单截图从系统相册「分享」给 CountDownTodo，AI 会自动提取待办、取餐码和账单草案。',
          '在「设置 > 模型与 API 配置」中填写 API Key 即可开启；即使不配 Key，也支持一键复制提示词配合外部 AI 粘贴识别。',
        ],
        actionLabel: '查看 AI 完整教程',
        tutorialLabel: 'AI 高阶教程',
        tutorialUri: CountdownTodoTutorialLinks.aiAssistantAdvanced,
        pageBuilder: (_, _) => const AiAssistantTutorialScreen(),
      ),
      FeatureExplorerItem(
        id: 'global_search_command_palette',
        title: '全局搜索与快捷命令面板',
        subtitle: '一键搜索待办、课程、账单、日记、时间日志，还能直接搜设置项与功能入口',
        locationPath: '首页右上角「放大镜」图标',
        category: FeatureExplorerCategory.aiAndSync,
        icon: Icons.search_rounded,
        badgeText: 'v4.2 新增',
        keywords: const [
          '搜索',
          '全局搜索',
          '查找',
          '命令面板',
          '设置搜索',
          '日期搜索',
          'v4.2',
        ],
        steps: const [
          '点击首页右上角放大镜打开全局搜索。',
          '支持直接输入日期（如“明天”、“10月24日”）查看当天的所有待办、课程与记录。',
          '找不到某个功能或设置时，直接搜口语词（如“调休”、“手环”、“液态玻璃”、“备份”），点击结果即可直达对应页面。',
        ],
        actionLabel: '打开全局搜索',
        pageBuilder: (_, _) => const GlobalSearchOverlay(),
      ),
      FeatureExplorerItem(
        id: 'team_collaboration',
        title: '群组团队协作与共享待办',
        subtitle: '创建或加入小组，发布置顶公告，分配“共同完成”或“各自打卡”的团队任务',
        locationPath: '首页右上角「团队」图标 / 侧边栏「群组团队」',
        category: FeatureExplorerCategory.aiAndSync,
        icon: Icons.groups_rounded,
        badgeText: 'v3.7 新增',
        keywords: const [
          '团队',
          '群组',
          '协作',
          '共享待办',
          '公告',
          '小组作业',
          'v3.7',
        ],
        steps: const [
          '从侧边栏或首页右上角进入「群组团队」，可创建新团队或通过邀请码加入团队。',
          '创建待办时选择关联团队，支持“共同协作（一人勾选全员完成）”和“独立打卡（每人各自完成）”两种模式。',
          '团队管理员可发布团队置顶公告，成员在首页顶部即可收到提醒。',
        ],
        actionLabel: '打开群组团队',
        pageBuilder: (_, username) => TeamManagementScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'cloud_sync_and_conflict_inbox',
        title: '多端云同步与冲突收件箱',
        subtitle: '手机、平板、Windows、macOS 与 Web 实时同步，遇到多端修改冲突提供可视化比对合并',
        locationPath: '首页右上角「同步」图标 / 设置 > 账户与同步',
        category: FeatureExplorerCategory.aiAndSync,
        icon: Icons.sync_rounded,
        badgeText: 'v7.1 增强',
        keywords: const [
          '同步',
          '云同步',
          '冲突',
          '冲突收件箱',
          '多端',
          '备份',
          'v4.2',
          'v7.1',
        ],
        steps: const [
          '在多台设备登录同一账号即可自动同步待办、课程、规划块、记账、习惯与专注状态。',
          '点击首页顶栏的「同步」图标可查看同步总览、手动触发同步或进入「冲突收件箱」解决多端同时编辑产生的冲突。',
        ],
        actionLabel: '打开冲突收件箱',
        pageBuilder: (_, username) => ConflictInboxScreen(username: username),
      ),
      if (!kIsWeb)
        FeatureExplorerItem(
          id: 'lan_direct_sync',
          title: '局域网面对面互传同步',
          subtitle: '无需经过云端服务器，在同一 Wi-Fi / 热点下手机与电脑点对点极速同步数据',
          locationPath: '设置 > 数据与互联 > 局域网同步',
          category: FeatureExplorerCategory.aiAndSync,
          icon: Icons.wifi_tethering_rounded,
          badgeText: 'v4.2 新增',
          keywords: const [
            '局域网',
            '互传',
            '离线同步',
            '内网',
            '点对点',
            'v4.2',
          ],
          steps: const [
            '将手机和电脑连接到同一个 Wi-Fi 或手机热点。',
            '在两端同时进入「设置 > 数据与互联 > 局域网同步」，即可自动发现设备并点对点同步。',
          ],
          actionLabel: '打开局域网同步',
          pageBuilder: (_, _) => const LanSyncScreen(),
        ),
      if (!kIsWeb && AppPlatform.isAndroid)
        FeatureExplorerItem(
          id: 'xiaomi_band_sync',
          title: '小米手环快应用同步',
          subtitle: '将今日待办、课程表与倒计时同步到小米手环腕上随时查看',
          locationPath: '设置 > 平台专属设置 / 数据与互联 > 手环同步',
          category: FeatureExplorerCategory.aiAndSync,
          icon: Icons.watch_rounded,
          badgeText: 'v6.1 升级',
          keywords: const [
            '手环',
            '小米手环',
            '穿戴',
            '手表',
            '腕上待办',
            'v3.0',
            'v6.1',
          ],
          steps: const [
            '在小米手环上安装 CountDownTodo 伴侣快应用。',
            '在手机端打开「手环同步」页面，一键推送今日待办、近期课程与倒计时到手环。',
          ],
          actionLabel: '打开手环同步',
          pageBuilder: (_, _) => const BandSyncScreen(),
        ),
      FeatureExplorerItem(
        id: 'animation_liquid_glass',
        title: 'Liquid Glass 液态玻璃与动效预设',
        subtitle: '独创的液态玻璃流光高光质感与边缘折射，可自由微调动画缩放与阻尼感',
        locationPath: '设置 > 偏好设置 > 动画设置',
        category: FeatureExplorerCategory.aiAndSync,
        icon: Icons.blur_on_rounded,
        badgeText: 'v6.5 升级',
        keywords: const [
          '液态玻璃',
          '动效',
          '动画',
          'Liquid Glass',
          '流光',
          '高斯模糊',
          '省电模式',
          '视觉',
          'v5.8',
          'v6.5',
        ],
        steps: const [
          '前往「设置 > 偏好设置 > 动画设置」。',
          '开启「液态玻璃效果」，界面将呈现独特的玻璃拟态流光与边缘折射。',
          '可针对设备性能选择流畅模式或性能优先模式，系统低电量或省电模式下会自动优雅降级保护电池。',
        ],
        actionLabel: '打开动画设置',
        pageBuilder: (_, _) => const AnimationSettingsPage(),
      ),
      FeatureExplorerItem(
        id: 'data_backup_and_restore',
        title: '全量数据备份与离线 JSON 导出',
        subtitle: '随时将本地所有待办、课表、账单、习惯与日记导出为标准 JSON 文件，安全防丢',
        locationPath: '设置 > 数据与互联 > 数据备份与恢复',
        category: FeatureExplorerCategory.aiAndSync,
        icon: Icons.cloud_download_rounded,
        badgeText: 'v5.0 升级',
        keywords: const [
          '备份',
          '导出',
          '导入',
          '恢复',
          'JSON',
          '数据安全',
          '离线数据',
          '迁移',
          'v5.0',
        ],
        steps: const [
          '前往「设置 > 数据与互联 > 数据备份与恢复」。',
          '点击「立即备份」可生成包含全量待办、课表、账单、日记的离线 JSON 文件。',
          '换机或重新安装应用时，只需点击「恢复数据」选择文件即可秒级恢复全部内容。',
        ],
        actionLabel: '前往数据设置',
        pageBuilder: (_, _) => const SettingsPage(initialTarget: 'sync'),
      ),
      FeatureExplorerItem(
        id: 'platform_island_and_widgets',
        title: '灵动岛、悬浮窗与桌面小组件',
        subtitle: '支持 Android 桌面小组件、Windows 灵动岛悬浮窗、macOS 菜单栏实时专注与小组件',
        locationPath: '设置 > 平台专属设置 / 动画设置',
        category: FeatureExplorerCategory.aiAndSync,
        icon: Icons.widgets_rounded,
        badgeText: 'v5.4 扩展',
        keywords: const [
          '小组件',
          '小部件',
          '灵动岛',
          '悬浮窗',
          '菜单栏',
          '状态栏',
          '液态玻璃',
          'v4.13',
          'v5.4',
        ],
        steps: const [
          'Android：长按手机桌面空白处添加 CountDownTodo 小部件，主屏直接查看待办、课表与专注进度。',
          'Windows：支持最小化到系统托盘、开启桌面灵动岛悬浮窗展示倒计时与专注状态，并支持读取 Tai 屏幕使用时间。',
          'macOS：专注期间右上角菜单栏实时显示剩余时间，并支持 macOS 桌面小组件。',
          '全平台：在「设置 > 动画设置」中可开启 Liquid Glass 液态玻璃质感与调整动画速度。',
        ],
        actionLabel: kIsWeb ? '打开动画与视觉设置' : '打开平台专属设置',
        tutorialLabel: '小部件教程',
        tutorialUri: CountdownTodoTutorialLinks.widgetFeatures,
        pageBuilder: (_, _) => kIsWeb
            ? const AnimationSettingsPage()
            : const PlatformSpecificSettingsPage(),
      ),
      if (kIsWeb)
        FeatureExplorerItem(
          id: 'web_pwa_app',
          title: 'PWA 网页应用免安装',
          subtitle: '在 Chrome/Edge/Safari 浏览器中一键添加到桌面或主屏幕，无缝独立运行',
          locationPath: '浏览器地址栏「安装应用」图标 / 手机浏览器「添加到主屏幕」',
          category: FeatureExplorerCategory.aiAndSync,
          icon: Icons.install_desktop_rounded,
          badgeText: 'v5.0 新增',
          keywords: const ['PWA', '网页版', '安装', '桌面版', '渐进式网页应用', 'v5.0'],
          steps: const [
            '电脑端：使用 Chrome 或 Edge 打开网页版，点击地址栏右侧的「安装应用」图标。',
            '手机端：使用 Safari 或 Chrome 打开，点击分享菜单并选择「添加到主屏幕」。',
            '安装后拥有独立窗口与专属图标，秒速启动且支持离线缓存。',
          ],
          actionLabel: '查看 Web 特性说明',
          pageBuilder: (_, _) =>
              const FeatureGuideScreen(mode: FeatureGuideMode.guide),
        ),

      // ── 隐藏神技 (Tips & Tricks) ─────────────────────────────────
      FeatureExplorerItem(
        id: 'tip_long_press_voice',
        title: '神技 1：按住底部「+」直接说话速记',
        subtitle: '不用打字！按住首页底部中央的「+」按钮不放即可直接语音说出待办或账单',
        locationPath: '首页底部导航栏中央「+」按钮（长按）',
        category: FeatureExplorerCategory.hiddenTips,
        icon: Icons.mic_rounded,
        badgeText: 'v7.1 新增',
        isNew: true,
        keywords: const [
          '长按',
          '语音',
          '速记',
          '按住说话',
          '加号',
          '手势',
          'v7.1',
        ],
        steps: const [
          '在首页底部导航栏找到中央带流光边框的「+」按钮。',
          '长按按住不放即可直接录音说话，松手后自动转文字并交给 AI 助手生成待办或账单，上滑还可切换发送方式。',
        ],
        actionLabel: '了解 AI 与语音配置',
        tutorialLabel: 'AI 高阶教程',
        tutorialUri: CountdownTodoTutorialLinks.aiAssistantAdvanced,
        pageBuilder: (_, _) => const AiAssistantTutorialScreen(),
      ),
      FeatureExplorerItem(
        id: 'tip_recycle_bin_multi_restore',
        title: '神技 2：历史待办与跨系列批量恢复',
        subtitle: '误删了重要待办或循环任务？进入历史待办回收站支持跨系列多选一键恢复',
        locationPath: '首页「待办事项」卡片右上角「历史/时钟」图标',
        category: FeatureExplorerCategory.hiddenTips,
        icon: Icons.restore_from_trash_rounded,
        badgeText: 'v7.1 升级',
        isNew: true,
        keywords: const [
          '回收站',
          '恢复',
          '误删',
          '历史待办',
          '批量恢复',
          'v7.1',
        ],
        steps: const [
          '在首页「待办事项」区域右上角点击历史记录图标。',
          '可查看已完成归档的待办，或切换到回收站批量勾选多条误删待办（包含重复待办系列）一键恢复。',
        ],
        actionLabel: '打开历史待办与回收站',
        pageBuilder: (_, username) => HistoricalTodosScreen(username: username),
      ),
      FeatureExplorerItem(
        id: 'tip_system_share_image',
        title: '神技 3：系统相册分享图片一键识待办+账单+取餐码',
        subtitle: '看到付款截图、取餐码截图或群通知图片，直接从系统分享菜单发给 CountDownTodo',
        locationPath: '手机相册/微信图片 > 系统分享 > CountDownTodo',
        category: FeatureExplorerCategory.hiddenTips,
        icon: Icons.burst_mode_rounded,
        badgeText: 'v7.1 升级',
        keywords: const [
          '系统分享',
          '截图识别',
          '取餐码',
          '取件码',
          '账单识别',
          '照片识别',
          'v5.8',
          'v7.1',
        ],
        steps: const [
          '在任意应用（如微信、支付宝、相册）查看图片时，点击「分享给其他应用」并选择 CountDownTodo。',
          '应用会自动在后台分析图片：如果同一张图既有付款金额又有取餐码，会同时提取待办提醒与记账草案，不会把取餐码误当成金额！',
        ],
        actionLabel: '查看识图教程',
        tutorialLabel: 'AI 高阶教程',
        tutorialUri: CountdownTodoTutorialLinks.aiAssistantAdvanced,
        pageBuilder: (_, _) => const AiAssistantTutorialScreen(),
      ),
      FeatureExplorerItem(
        id: 'tip_customize_home_and_drawer',
        title: '神技 4：自由定制首页模块顺序与侧边栏',
        subtitle: '首页卡片太多？可以自由隐藏不用的模块、调整上下顺序，打造最顺手的专属工作台',
        locationPath: '设置 > 偏好设置 > 首页布局 / 侧边栏菜单',
        category: FeatureExplorerCategory.hiddenTips,
        icon: Icons.dashboard_customize_rounded,
        badgeText: 'v5.6 增强',
        keywords: const [
          '首页布局',
          '定制',
          '隐藏卡片',
          '排序',
          '侧边栏设置',
          'v4.16',
          'v5.6',
        ],
        steps: const [
          '前往「设置 > 偏好设置」，点击「首页布局」或「侧边栏菜单」。',
          '可以拖拽调整每个功能卡片在首页或专注页的显示顺序，或关闭暂时不需要的模块。',
        ],
        actionLabel: '前往设置中心',
        pageBuilder: (_, _) => const SettingsPage(initialTarget: 'preference'),
      ),
      FeatureExplorerItem(
        id: 'tip_global_theme_color',
        title: '神技 5：全局动态主题色彩与外观',
        subtitle: '支持跟随壁纸动态取色、莫兰迪色系切换与纯黑 OLED 极暗省电模式',
        locationPath: '设置 > 偏好设置 > 主题色彩',
        category: FeatureExplorerCategory.hiddenTips,
        icon: Icons.format_paint_rounded,
        badgeText: 'v4.16 新增',
        keywords: const [
          '主题色彩',
          '莫兰迪',
          '动态取色',
          '壁纸取色',
          '深色模式',
          '极暗模式',
          '外观',
          'v4.16',
        ],
        steps: const [
          '前往「设置 > 偏好设置」，点击「主题色彩」。',
          '支持从当前壁纸或相册图片智能提取主色调，生成和谐的 Material 3 动态色盘。',
          '支持浅色、深色以及针对 OLED 屏幕优化的纯黑极暗模式，夜间使用更护眼省电。',
        ],
        actionLabel: '配置主题色彩',
        pageBuilder: (_, _) =>
            const PreferenceSettingsPage(initialTarget: 'theme_color'),
      ),
      FeatureExplorerItem(
        id: 'tip_batch_todo_operations',
        title: '神技 6：待办长按多选与批量批处理',
        subtitle: '任务积压太多？长按待办开启多选模式，一键批量完成、批量延期或移入回收站',
        locationPath: '首页待办列表卡片（长按待办条目）',
        category: FeatureExplorerCategory.hiddenTips,
        icon: Icons.checklist_rounded,
        badgeText: 'v5.6 引入',
        keywords: const [
          '批量',
          '多选',
          '批量完成',
          '批量删除',
          '长按',
          '批处理',
          '效率',
          'v5.6',
        ],
        steps: const [
          '在首页待办列表中长按任意一条待办事项，即可激活「多选批处理模式」。',
          '勾选多条待办后，底部操作栏支持一键批量标记完成、批量修改截止日期或批量移入回收站。',
          '点击全选按钮更可对当前文件夹下的所有待办进行快速整理。',
        ],
        actionLabel: '去管理待办',
        customAction: (context, username) async {
          final groups = await StorageService.getTodoGroups(username);
          if (!context.mounted) return;
          await Navigator.of(context, rootNavigator: true).push(
            PageTransitions.slideHorizontal(
              AddTodoScreen(
                todoGroups: groups,
                onTodoAdded: (todo) async {
                  final todos = await StorageService.getTodos(username);
                  final idx = todos.indexWhere((item) => item.id == todo.id);
                  if (idx < 0) {
                    todos.add(todo);
                  } else {
                    todos[idx] = todo;
                  }
                  await StorageService.saveTodos(username, todos);
                },
                onManualTodoSaved: (todo) async {
                  final todos = await StorageService.getTodos(username);
                  final idx = todos.indexWhere((item) => item.id == todo.id);
                  if (idx < 0) {
                    todos.add(todo);
                  } else {
                    todos[idx] = todo;
                  }
                  await StorageService.saveTodos(username, todos);
                  return const TodoCreateSaveResult();
                },
              ),
            ),
          );
        },
      ),
    ];
  }

  int _itemPriority(FeatureExplorerItem item) {
    if (item.isNew && !_seenBadges.contains(item.id)) {
      return 0; // 近期新增且用户未读：最高优先级置顶
    }
    if (item.isNew) {
      return 1; // 近期新增（已读）：次优先级
    }
    return 2; // 其他常驻核心功能与技巧
  }

  List<FeatureExplorerItem> _filteredItems(List<FeatureExplorerItem> catalog) {
    final query = _searchQuery.trim().toLowerCase();
    final indexed = <({int index, FeatureExplorerItem item})>[];
    for (var i = 0; i < catalog.length; i++) {
      final item = catalog[i];
      final bool matches;
      if (query.isEmpty) {
        if (_selectedCategory == FeatureExplorerCategory.all) {
          matches = true;
        } else if (_selectedCategory == FeatureExplorerCategory.recent) {
          matches = item.isNew;
        } else {
          matches = item.category == _selectedCategory;
        }
      } else {
        final haystack = [
          item.title,
          item.subtitle,
          item.locationPath,
          item.badgeText ?? '',
          ...item.keywords,
          ...item.steps,
        ].join(' ').toLowerCase();
        matches = query
            .split(RegExp(r'\s+'))
            .every((term) => term.isEmpty || haystack.contains(term));
      }
      if (matches) {
        indexed.add((index: i, item: item));
      }
    }

    indexed.sort((a, b) {
      final priorityCompare = _itemPriority(a.item)
          .compareTo(_itemPriority(b.item));
      if (priorityCompare != 0) return priorityCompare;
      return a.index.compareTo(b.index);
    });

    return indexed.map((entry) => entry.item).toList();
  }

  Future<void> _launchFeature(FeatureExplorerItem item) async {
    await FeatureTipService.markFeatureBadgeSeen(item.id);
    // Also mark corresponding onboarding task if applicable
    switch (item.id) {
      case 'todos_and_countdowns':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskCreateTodoOrCountdown,
        );
      case 'fixed_schedule_related_todo':
      case 'course_schedule_and_import':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskCourseOrSchedule,
        );
      case 'todo_plan_center':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskPlanBlock,
        );
      case 'pomodoro_focus':
      case 'time_log_and_backfill':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskPomodoroFocus,
        );
      case 'ai_assistant_and_tutorial':
      case 'tip_long_press_voice':
        await OnboardingChecklistService.markTaskCompleted(
          OnboardingChecklistService.taskAiOrQuickVoice,
        );
    }

    final username = await _resolveUsername();
    if (!mounted) return;
    if (item.customAction != null) {
      await item.customAction!(context, username);
      return;
    }
    if (item.pageBuilder != null) {
      final page = item.pageBuilder!(context, username);
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(PageTransitions.slideHorizontal(page));
    }
  }

  Future<void> _launchTutorial(FeatureExplorerItem item) async {
    final tutorialUri = item.tutorialUri;
    if (tutorialUri == null) return;

    try {
      final launched = await launchUrl(
        tutorialUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开教程链接，请稍后重试。')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('打开教程失败，请检查网络后重试。')));
    }
  }

  Future<void> _showItemDetailSheet(FeatureExplorerItem item) async {
    await FeatureTipService.markFeatureBadgeSeen(item.id);
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    await showAppModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.icon,
                      color: scheme.onPrimaryContainer,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.title,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (item.badgeText != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  item.badgeText!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_rounded,
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '入口位置：${item.locationPath}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '如何操作',
                style: Theme.of(sheetContext).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < item.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.steps[i],
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: scheme.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _launchFeature(item);
                  },
                  icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: Text(item.actionLabel),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (item.tutorialUri != null) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _launchTutorial(item);
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(item.tutorialLabel ?? '查看高阶教程'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catalog = _buildCatalog();
    final filtered = _filteredItems(catalog);
    final unreadNewCount = catalog
        .where((item) => item.isNew && !_seenBadges.contains(item.id))
        .length;

    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('功能探索百宝箱'),
              actions: [
                if (unreadNewCount > 0)
                  TextButton.icon(
                    onPressed: () async {
                      for (final item in catalog.where((e) => e.isNew)) {
                        await FeatureTipService.markFeatureBadgeSeen(item.id);
                      }
                    },
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('全部标为已读'),
                  ),
              ],
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.isEmbedded
                ? 16
                : floatingGlassSettingsContentTopInset(context, extra: 16),
            16,
            32,
          ),
          children: [
            _buildHeroBanner(scheme, catalog.length, unreadNewCount),
            const SizedBox(height: 14),
            _buildSearchField(scheme),
            const SizedBox(height: 12),
            _buildCategoryBar(scheme, unreadNewCount),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              _buildEmptyState(scheme)
            else
              ..._buildFeatureListWidgets(filtered, scheme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFeatureListWidgets(
    List<FeatureExplorerItem> items,
    ColorScheme scheme,
  ) {
    final showGroupHeaders =
        _selectedCategory == FeatureExplorerCategory.all &&
        _searchQuery.trim().isEmpty;
    if (!showGroupHeaders) {
      return items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildFeatureCard(item, scheme),
            ),
          )
          .toList();
    }

    final unreadNew = <FeatureExplorerItem>[];
    final readNew = <FeatureExplorerItem>[];
    final regular = <FeatureExplorerItem>[];

    for (final item in items) {
      final priority = _itemPriority(item);
      if (priority == 0) {
        unreadNew.add(item);
      } else if (priority == 1) {
        readNew.add(item);
      } else {
        regular.add(item);
      }
    }

    final widgets = <Widget>[];

    if (unreadNew.isNotEmpty) {
      widgets.add(
        _buildSectionGroupHeader(
          scheme: scheme,
          icon: Icons.fiber_new_rounded,
          title: '近期新增 · 未读',
          count: unreadNew.length,
          highlight: true,
        ),
      );
      for (final item in unreadNew) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildFeatureCard(item, scheme),
          ),
        );
      }
    }

    if (readNew.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 6));
      }
      widgets.add(
        _buildSectionGroupHeader(
          scheme: scheme,
          icon: Icons.new_releases_outlined,
          title: '近期新增 · 已读',
          count: readNew.length,
        ),
      );
      for (final item in readNew) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildFeatureCard(item, scheme),
          ),
        );
      }
    }

    if (regular.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 6));
      }
      widgets.add(
        _buildSectionGroupHeader(
          scheme: scheme,
          icon: Icons.apps_rounded,
          title: '常驻核心功能与技巧',
          count: regular.length,
        ),
      );
      for (final item in regular) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildFeatureCard(item, scheme),
          ),
        );
      }
    }

    return widgets;
  }

  Widget _buildSectionGroupHeader({
    required ColorScheme scheme,
    required IconData icon,
    required String title,
    required int count,
    bool highlight = false,
  }) {
    final accent = highlight ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: highlight ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
            decoration: BoxDecoration(
              color: highlight
                  ? scheme.primary.withValues(alpha: 0.14)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(
    ColorScheme scheme,
    int totalCount,
    int unreadNewCount,
  ) {
    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      highContrast: true,
      tint: scheme.primary.withValues(alpha: 0.14),
      fallbackDecoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.65),
            scheme.tertiaryContainer.withValues(alpha: 0.45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.explore_rounded,
                  color: scheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '全景功能地图 · 共 $totalCount 项能力与技巧',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      unreadNewCount > 0
                          ? '有 $unreadNewCount 项新版本升级亮点等你体验，点击卡片看教程，点「去试试」一键直达！'
                          : '不知道某个功能在哪里？点击任意卡片查看入口路径与 30 秒上手指南，或一键直达。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: Icon(
                  Icons.system_update_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                label: const Text('查看版本更新日志'),
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).push(
                    PageTransitions.slideHorizontal(
                      FeatureGuideScreen(
                        mode: FeatureGuideMode.changelog,
                        loggedInUser: widget.username,
                      ),
                    ),
                  );
                },
              ),
              ActionChip(
                avatar: Icon(
                  Icons.checklist_rounded,
                  size: 16,
                  color: scheme.tertiary,
                ),
                label: const Text('重新显示首页探索清单'),
                onPressed: () async {
                  await OnboardingChecklistService.setDismissed(false);
                  await OnboardingChecklistService.setExpanded(true);
                  if (!mounted) return;
                  AppSnackBars.showSnackBar(
                    context,
                    const SnackBar(content: Text('已在首页恢复显示「新手探索任务清单」')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ColorScheme scheme) {
    return TextField(
      key: const ValueKey<String>('feature-explorer-search-field'),
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        hintText: '搜索功能、场景或技巧（如：调休、补录、记账、语音、手环）',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildCategoryBar(ColorScheme scheme, int unreadNewCount) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: FeatureExplorerCategory.values.map((category) {
          final selected = _selectedCategory == category;
          final showDot =
              category == FeatureExplorerCategory.recent && unreadNewCount > 0;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              showCheckmark: false,
              avatar: Icon(
                category.icon,
                size: 16,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(category.label),
                  if (showDot) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$unreadNewCount',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheme.onError,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onSelected: (_) {
                setState(() => _selectedCategory = category);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFeatureCard(FeatureExplorerItem item, ColorScheme scheme) {
    final isUnreadNew = item.isNew && !_seenBadges.contains(item.id);
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey<String>('feature-explorer-card-${item.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showItemDetailSheet(item),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnreadNew
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: scheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            if (item.badgeText != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: item.isNew
                                      ? scheme.primary.withValues(alpha: 0.14)
                                      : scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  item.badgeText!,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: item.isNew
                                        ? scheme.primary
                                        : scheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                            if (isUnreadNew) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: scheme.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.place_outlined, size: 15, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.locationPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      key: ValueKey<String>('feature-explorer-try-${item.id}'),
                      onPressed: () => _launchFeature(item),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                      label: const Text(
                        '去试试',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

  Widget _buildEmptyState(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 44,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '没有找到匹配「$_searchQuery」的功能',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _selectedCategory = FeatureExplorerCategory.all;
              });
            },
            child: const Text('重置筛选条件'),
          ),
        ],
      ),
    );
  }
}

abstract final class DeviceCalendarReadServicePlaceholder {
  static bool get isSupportedPlatform =>
      !kIsWeb && (AppPlatform.isAndroid || AppPlatform.isIOS);
}
