part of 'course_screens.dart';
// ignore_for_file: unused_element, unused_element_parameter, annotate_overrides

abstract class _WeeklyCourseScreenStateBase extends State<WeeklyCourseScreen>
    with TickerProviderStateMixin {
  int _currentWeek = 1;
  List<int> _availableWeeks = [];
  List<CourseItem> _weekCourses = [];

  List<TodoItem> _allTodos = [];

  // 拆分：全天/跨天待办 和 日内局部待办
  Map<int, List<TodoItem>> _allDayTodosPerDay = {};
  Map<int, List<TodoItem>> _intraDayTodosPerDay = {};
  List<DeviceCalendarEvent> _deviceCalendarEvents = [];
  Map<int, List<DeviceCalendarEvent>> _allDayDeviceCalendarEventsPerDay = {};
  Map<int, List<DeviceCalendarEvent>> _timedDeviceCalendarEventsPerDay = {};

  bool _isLoading = true;
  DateTime? _semesterMonday;

  // 多学期支持
  List<SemesterInfo> _semesters = [];

  List<TimeLogItem> _allTimeLogs = [];
  List<PomodoroRecord> _allPomodoroRecords = [];
  List<PomodoroTag> _pomodoroTags = [];
  List<TodoPlanBlock> _allPlanBlocks = [];
  Map<int, List<TimeLogItem>> _timeLogsPerDay = {};
  Map<int, List<PomodoroRecord>> _pomodorosPerDay = {};
  Map<int, List<TodoPlanBlock>> _planBlocksPerDay = {};
  final Set<String> _activeDataViews = {
    'courses',
    'todos',
    'plans',
    'timeLogs',
    'pomodoros',
    'deviceCalendar',
  };
  bool _collapseFreeTime = true;

  // --- 🚀 视图模式分级 (1周, 2周, 1个月) ---
  int _viewMode = 0; // 0: 1周, 1: 2周, 2: 1个月
  DateTime _selectedMonth = DateTime.now();
  List<CourseItem> _allCourses = [];
  bool _isNextSlide = true;
  double _dragOffset = 0.0; // 实时跟踪滑动位移
  DateTime? _selectedMonthDay; // 平板模式下月视图选中的日期

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _courseExpandCtrl;
  late Animation<double> _courseExpandAnim;

  late PageController _pageController;
  final Map<String, GlobalKey> _courseCardKeys = {};
  final Map<String, GlobalKey> _todoCardKeys = {};
  final Map<String, GlobalKey> _timeLogCardKeys = {};
  final Map<String, GlobalKey> _pomodoroCardKeys = {};

  final GlobalKey _filterKey = GlobalKey();
  final GlobalKey _viewModeKey = GlobalKey();
  final GlobalKey _timeLogKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();
  final GlobalKey _allDayKey = GlobalKey();
  final GlobalKey _dayHeaderKey = GlobalKey();

  bool _showCoachMarks = false;

  GlobalKey _getCourseCardKey(String courseName, int weekday, int startTime) {
    // Include current week to avoid key collisions while AnimatedSwitcher keeps
    // both previous and next week grids in the tree during transition.
    final keyStr = 'w${_currentWeek}_${courseName}_${weekday}_$startTime';
    return _courseCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  GlobalKey _getTodoCardKey(String id, {int? weekday}) {
    final keyStr = weekday != null
        ? 'w${_currentWeek}_${id}_d$weekday'
        : 'w${_currentWeek}_$id';
    return _todoCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  GlobalKey _getTimeLogCardKey(String id) {
    final keyStr = 'w${_currentWeek}_$id';
    return _timeLogCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  GlobalKey _getPomodoroCardKey(String id) {
    final keyStr = 'w${_currentWeek}_$id';
    return _pomodoroCardKeys.putIfAbsent(keyStr, () => GlobalKey());
  }

  // 时间轴参数配置
  final double timeColumnWidth = 45.0;
  final int startHour = 6;
  final int endHour = 24;

  // 自适应空闲时间压缩：统一记录所有被扣除的绝对时间区间。
  List<_HiddenTimeRange> _hiddenTimeRanges = const [];
  double? _lunchCardStartMinute;
  double _lunchCardDuration = 0.0;
  String _lunchCollapseText = '';

  DateTime? _lastModeSwitch;

  // --- 🚀 性能优化: 预先按日期分组数据 (避免在动画期间重复计算) ---
  Map<String, List<CourseItem>> _monthCourseMap = {};
  Map<String, List<TodoItem>> _monthTodoMap = {};
  Map<String, List<TodoItem>> _monthCrossDayTodoMap = {};
  Map<String, List<TimeLogItem>> _monthLogMap = {};
  Map<String, List<PomodoroRecord>> _monthPomMap = {};
  Map<String, List<TodoPlanBlock>> _monthPlanMap = {};
  bool _monthDataPrepared = false;
  final int _maxExpandedSpanDays = 366;
  void initState();
  void dispose();
  Future<void> _loadData();
  Future<void> _loadDeviceCalendarEventsForCurrentWeek();
  void _updateWeekCourses();
  void _checkCoachMarks();
  void _groupDataForMonthView();
  void _forEachExpandedDay({
    required DateTime start,
    required DateTime end,
    required String debugLabel,
    required void Function(DateTime day) onDay,
  });
  TodoItem _createRecurringOccurrence(TodoItem todo, DateTime targetDay);
  List<TodoItem> _expandRecurringTodo(TodoItem todo, DateTime weekStart);
  void _updateWeekTodos();
  void _updateWeekDeviceCalendarEvents();
  void _updateWeekTimeLogsPomodorosAndPlans();
  void _changeWeek(int delta);
  void _jumpToWeek(int newWeek);
  void _toggleViewMode(int mode);
  void _changeMonth(int delta);
  String _getWeekLabel();
  String _getBiWeekLabel();
  void _showWeekJumpDialog();
  void _jumpToCurrentWeek();
  Widget _buildMonthDaySidebar(DateTime day);
  Widget _buildDetailSidebarItem(BuildContext context, dynamic item);
  void _handleFilterSelection(String value);
  double _filterMenuWidth(BuildContext context);
  int get _selectedFilterCount;
  Widget _buildFilterMenuHeader();
  Widget _buildFilterMenuDivider();
  Widget _buildFilterSectionLabel(String label);
  Widget _buildCheckableMenuItem(String key, String label);
  Widget _buildFilterActionItem(
      String value, String label, IconData icon, Color color);
  DateTime? _getMondayOfCurrentWeek();
  void _checkCollapsedSlots();
  double get _totalHiddenMinutes;
  double _mapTimeToVirtualMinutes(int hour, int minute);
  double _timeToY(int hour, int minute, double minuteHeight);
  Color _getCourseColor(String courseName);
  void _showAllDayTodos(
      BuildContext context, List<TodoItem> todos, String dateStr);
  Widget _buildAllDayHeaderRow(DateTime? monday);
  bool _timeRangesOverlap(
      int startA, int endAExclusive, int startB, int endBExclusive);
  bool _isRecordAssociatedWithPlan(PomodoroRecord record, TodoPlanBlock plan);
  Map<String, dynamic> _calculatePlanPomodoroProgress(TodoPlanBlock plan);
  bool _isPomodoroAssociatedWithPlan(PomodoroRecord record);
  Widget _buildHeader(DateTime? monday);
  bool _isHourCollapsed(int hour);
  String _formatMinute(double minute);
  String _buildLunchCollapseText(
      double rangeStart, double rangeEnd, double pre, double post);
  Widget _buildGrid(double cellWidth, double minuteHeight);
  Widget _buildTodaySidebar();
  Widget build(BuildContext context);
  Widget _buildSkeleton();
  Widget _buildSkeletonBox(
      double cellWidth, double top, double height, int dayIndex, Color color);
  void _showDayDetailSheet(DateTime day);
}
