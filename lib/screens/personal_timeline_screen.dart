import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:io';
import '../models.dart';
import '../services/timeline_service.dart';
import '../services/pomodoro_service.dart';
import '../storage_service.dart';
import '../services/course_service.dart';

enum TimelineDimension { daily, weekly, monthly, yearly }

class PersonalTimelineScreen extends StatefulWidget {
  final String username;
  const PersonalTimelineScreen({super.key, required this.username});

  @override
  State<PersonalTimelineScreen> createState() => _PersonalTimelineScreenState();
}

class _PersonalTimelineScreenState extends State<PersonalTimelineScreen>
    with SingleTickerProviderStateMixin {
  TimelineDimension _dimension = TimelineDimension.daily;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isExportingPoster = false;
  late AnimationController _animationController;

  // Data points
  List<TimelineEvent> _events = [];
  TimelineSummary? _summary;
  int _totalFocusMinutes = 0;
  String? _topAppCategory;
  int _completedCount = 0;
  int _totalCount = 0;
  int _screenTimeSeconds = 0;
  int _productiveScreenSeconds = 0;
  int _distractionScreenSeconds = 0;
  int _deadlineSprintCount = 0;
  int _earlyCompletionCount = 0;
  int _courseCount = 0;
  int _maxDailyCourseCount = 0;
  List<MapEntry<String, int>> _topScreenApps = [];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    DateTime start;
    DateTime end;

    final day =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

    switch (_dimension) {
      case TimelineDimension.daily:
        start = day;
        end = day.add(const Duration(days: 1));
        break;
      case TimelineDimension.weekly:
        start = day.subtract(Duration(days: day.weekday - 1));
        end = start.add(const Duration(days: 7));
        break;
      case TimelineDimension.monthly:
        start = DateTime(day.year, day.month, 1);
        end = DateTime(day.year, day.month + 1, 1);
        break;
      case TimelineDimension.yearly:
        start = DateTime(day.year, 1, 1);
        end = DateTime(day.year + 1, 1, 1);
        break;
    }

    try {
      // 1. Get Timeline Summary for Range
      final summary = await TimelineService.instance
          .getSummaryForRange(widget.username, start, end);

      // 2. Get detailed events for Daily only (too many for others)
      if (_dimension == TimelineDimension.daily) {
        _events = await TimelineService.instance
            .getEventsForDay(widget.username, day);
      } else {
        _events = []; // Or maybe fetch "Major" events
      }

      // 3. Get Focus Time
      final records = await PomodoroService.getRecordsInRange(start, end);
      int totalSecs = records.fold(0, (sum, r) => sum + r.effectiveDuration);

      // 4. Get Top Category (Simplified)
      final screenStats = await StorageService.getScreenTimeHistory();
      final appMappings = await StorageService.getAppMappings();
      Map<String, int> catUsage = {};
      Map<String, int> appUsage = {};
      int screenTotal = 0;
      int productiveScreen = 0;
      int distractionScreen = 0;

      // Iterate through days in range
      DateTime cursor = start;
      while (cursor.isBefore(end)) {
        final dateStr = DateFormat('yyyy-MM-dd').format(cursor);
        final stats = screenStats[dateStr] ?? [];
        for (var item in stats) {
          final appName = item['app_name']?.toString() ??
              item['package_name']?.toString() ??
              '未知应用';
          final packageName = item['package_name']?.toString() ?? '';
          final duration = (item['duration'] as num?)?.toInt() ?? 0;
          final cat = _getScreenCategoryForApp(
            appName: appName,
            packageName: packageName,
            backendCategory: item['category']?.toString(),
            mappings: appMappings,
          );
          catUsage[cat] = (catUsage[cat] ?? 0) + duration;
          appUsage[appName] = (appUsage[appName] ?? 0) + duration;
          screenTotal += duration;
          if (_isProductiveScreenCategory(cat)) productiveScreen += duration;
          if (_isDistractionScreenCategory(cat)) distractionScreen += duration;
        }
        cursor = cursor.add(const Duration(days: 1));
      }

      final todos = await StorageService.getTodos(widget.username);
      final completedTodos = todos.where((todo) {
        return !todo.isDeleted &&
            todo.isDone &&
            todo.updatedAt >= start.millisecondsSinceEpoch &&
            todo.updatedAt < end.millisecondsSinceEpoch;
      }).toList();
      final plannedTodos = todos.where((todo) {
        if (todo.isDeleted) return false;
        final createdInRange = todo.createdAt >= start.millisecondsSinceEpoch &&
            todo.createdAt < end.millisecondsSinceEpoch;
        final dueEnd = _effectiveTodoDueEnd(todo);
        final dueInRange = todo.dueDate != null &&
            dueEnd != null &&
            !dueEnd.isBefore(start) &&
            dueEnd.isBefore(end);
        final completedInRange = todo.isDone &&
            todo.updatedAt >= start.millisecondsSinceEpoch &&
            todo.updatedAt < end.millisecondsSinceEpoch;
        return createdInRange || dueInRange || completedInRange;
      }).toList();
      final sprintCount = completedTodos.where((todo) {
        final due = _effectiveTodoDueEnd(todo);
        if (due == null) return false;
        final doneAt = DateTime.fromMillisecondsSinceEpoch(todo.updatedAt);
        final diff = due.difference(doneAt);
        return !diff.isNegative && diff.inHours <= 24;
      }).length;
      final earlyCount = completedTodos.where((todo) {
        final due = _effectiveTodoDueEnd(todo);
        if (due == null) return false;
        final doneAt = DateTime.fromMillisecondsSinceEpoch(todo.updatedAt);
        return due.difference(doneAt).inHours >= 24;
      }).length;

      final courses = await CourseService.getAllCourses(widget.username);
      final Map<String, int> coursesByDay = {};
      for (final course in courses) {
        DateTime? courseDay;
        try {
          courseDay = DateFormat('yyyy-MM-dd').parseStrict(course.date);
        } catch (_) {
          courseDay = null;
        }
        if (courseDay == null ||
            courseDay.isBefore(start) ||
            !courseDay.isBefore(end)) {
          continue;
        }
        coursesByDay[course.date] = (coursesByDay[course.date] ?? 0) + 1;
      }

      String? topCat;
      if (catUsage.isNotEmpty) {
        topCat =
            catUsage.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      }

      if (mounted) {
        setState(() {
          _summary = summary;
          _totalFocusMinutes = totalSecs ~/ 60;

          // Smart Top Category: Prioritize task-based subject if app category is generic
          String? displayCat = topCat;
          if (displayCat == null || displayCat == '其他') {
            if (summary.subjectDistribution.entries.isNotEmpty) {
              final topSub = summary.subjectDistribution.entries
                  .reduce((a, b) => a.value > b.value ? a : b)
                  .key;
              if (topSub != '其他') {
                displayCat = topSub;
              }
            }
          }
          _topAppCategory = displayCat ?? '学习';
          _completedCount = completedTodos.length;
          _totalCount = plannedTodos.isEmpty
              ? completedTodos.length
              : plannedTodos.length;
          _screenTimeSeconds = screenTotal;
          _productiveScreenSeconds = productiveScreen;
          _distractionScreenSeconds = distractionScreen;
          _deadlineSprintCount = sprintCount;
          _earlyCompletionCount = earlyCount;
          _courseCount = coursesByDay.values.fold(0, (sum, v) => sum + v);
          _maxDailyCourseCount = coursesByDay.values.isEmpty
              ? 0
              : coursesByDay.values.reduce(math.max);
          _topScreenApps = appUsage.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          _topScreenApps = _topScreenApps.take(5).toList();
          _isLoading = false;
        });
        _animationController.forward(from: 0.0);
      }
    } catch (e) {
      debugPrint('Error loading insight data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getScreenCategoryForApp({
    required String appName,
    required String packageName,
    required String? backendCategory,
    required Map<String, String> mappings,
  }) {
    final mappedByName = mappings[appName];
    if (mappedByName != null && mappedByName != '未分类') {
      return mappedByName;
    }

    final mappedByPackage = mappings[packageName];
    if (mappedByPackage != null && mappedByPackage != '未分类') {
      return mappedByPackage;
    }

    if (backendCategory != null &&
        backendCategory.isNotEmpty &&
        backendCategory != '未分类') {
      return backendCategory;
    }

    return _guessScreenCategory(appName);
  }

  String _guessScreenCategory(String appName) {
    final l = appName.toLowerCase();
    if (l.contains('微信') ||
        l.contains('qq') ||
        l.contains('小红书') ||
        l.contains('微博')) {
      return '社交通讯';
    }
    if (l.contains('抖音') ||
        l.contains('哔哩') ||
        l.contains('bilibili') ||
        l.contains('音乐') ||
        l.contains('视频') ||
        l.contains('直播') ||
        l.contains('游戏')) {
      return '影音娱乐';
    }
    if (l.contains('studio') ||
        l.contains('code') ||
        l.contains('visual studio') ||
        l.contains('vscode') ||
        l.contains('vs code') ||
        l.contains('intellij') ||
        l.contains('idea') ||
        l.contains('pycharm') ||
        l.contains('webstorm') ||
        l.contains('clion') ||
        l.contains('cursor') ||
        l.contains('trae') ||
        l.contains('sublime') ||
        l.contains('notepad++') ||
        l.contains('terminal') ||
        l.contains('powershell') ||
        l.contains('cmd') ||
        l.contains('git') ||
        l.contains('github') ||
        l.contains('docker') ||
        l.contains('postman') ||
        l.contains('dev') ||
        l.contains('flutter') ||
        l.contains('dart') ||
        l.contains('python') ||
        l.contains('java') ||
        l.contains('node') ||
        l.contains('npm') ||
        l.contains('编程') ||
        l.contains('代码') ||
        l.contains('开发') ||
        l.contains('调试') ||
        l.contains('word') ||
        l.contains('excel') ||
        l.contains('笔记') ||
        l.contains('论文') ||
        l.contains('学习')) {
      return '学习办公';
    }
    if (l.contains('edge') ||
        l.contains('chrome') ||
        l.contains('浏览') ||
        l.contains('计算器') ||
        l.contains('设置')) {
      return '实用工具';
    }
    return '其他';
  }

  bool _isProductiveScreenCategory(String category) {
    return category == '学习办公' || category == '实用工具';
  }

  bool _isDistractionScreenCategory(String category) {
    return category == '社交通讯' || category == '影音娱乐' || category == '游戏与辅助';
  }

  DateTime? _effectiveTodoDueEnd(TodoItem todo) {
    final due = todo.dueDate;
    if (due == null) return null;

    final localDue = due.toLocal();
    final looksDateOnly = localDue.hour == 0 &&
        localDue.minute == 0 &&
        localDue.second == 0 &&
        localDue.millisecond == 0;
    if (!todo.isAllDayTask && !looksDateOnly) return localDue;

    return DateTime(
      localDue.year,
      localDue.month,
      localDue.day,
      23,
      59,
      59,
      999,
    );
  }

  Future<void> _chooseAndSaveTimelinePoster() async {
    if (_summary == null || _isExportingPoster) return;

    final includeMedals = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '保存分享长图',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: const Text('带上勋章墙'),
                  subtitle: const Text('适合展示完整阶段成果'),
                  onTap: () => Navigator.pop(context, true),
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('不带勋章墙'),
                  subtitle: const Text('长图更短，适合快速分享'),
                  onTap: () => Navigator.pop(context, false),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (includeMedals == null) return;
    await _saveTimelinePoster(includeMedals: includeMedals);
  }

  Future<void> _saveTimelinePoster({required bool includeMedals}) async {
    if (_summary == null || _isExportingPoster) return;

    setState(() => _isExportingPoster = true);
    final posterKey = GlobalKey();
    OverlayEntry? entry;

    try {
      final overlay = Overlay.of(context);
      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      entry = OverlayEntry(
        builder: (_) => Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.01,
              child: Material(
                color: Colors.transparent,
                child: RepaintBoundary(
                  key: posterKey,
                  child: Theme(
                    data: theme,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        size: Size(1080, 1920),
                        devicePixelRatio: 1,
                        textScaler: TextScaler.noScaling,
                      ),
                      child: _buildSharePoster(
                        cs,
                        includeMedals: includeMedals,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      overlay.insert(entry);
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final boundary = posterKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('分享长图渲染失败');
      }

      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('PNG 编码失败');
      }

      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final safePeriod = _getPeriodName();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}${Platform.pathSeparator}'
          'CountDownTodo_${safePeriod}_timeline_$timestamp.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('长图已保存：${file.path}'),
          action: SnackBarAction(
            label: '打开',
            onPressed: () => OpenFile.open(file.path),
          ),
        ),
      );
    } catch (e) {
      debugPrint('保存时间线长图失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存长图失败：$e')),
        );
      }
    } finally {
      entry?.remove();
      if (mounted) setState(() => _isExportingPoster = false);
    }
  }

  Widget _buildSharePoster(ColorScheme cs, {required bool includeMedals}) {
    return Container(
      width: 1080,
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(56, 56, 56, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CountDownTodo ${_getPeriodName()}总结',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getDateRangeString(),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                DateFormat('yyyy.MM.dd HH:mm').format(DateTime.now()),
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _buildStatsOverview(cs, true),
          const SizedBox(height: 36),
          _buildSectionTitle('概览回顾', Icons.insights_rounded, cs),
          const SizedBox(height: 16),
          _buildRangeSummary(cs, true),
          _buildOverviewInsightPanels(cs, true),
          if (includeMedals) _buildMedalWall(cs, true),
          const SizedBox(height: 36),
          _buildSectionTitle('数据深度洞察', Icons.analytics_outlined, cs),
          const SizedBox(height: 16),
          _buildSubjectDonutChart(cs),
          const SizedBox(height: 36),
          _buildReflection(cs),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '由 CountDownTodo 生成',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildWebsiteQr(cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebsiteQr(ColorScheme cs) {
    const siteUrl = 'https://countdowntodo.junpgle.me/';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '扫码访问',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                siteUrl,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          QrImageView(
            data: siteUrl,
            version: QrVersions.auto,
            size: 96,
            gapless: false,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(colorScheme),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildAppBar(context, colorScheme),
              SliverToBoxAdapter(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),

                        // Animated Content Area
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600),
                          switchInCurve: Curves.easeOutQuart,
                          switchOutCurve: Curves.easeInQuart,
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.02),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _isLoading
                              ? _buildSkeleton(colorScheme)
                              : Column(
                                  key: ValueKey(
                                      'content_${_dimension}_${_selectedDate.millisecondsSinceEpoch}'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildStatsOverview(colorScheme, isWide),
                                    const SizedBox(height: 40),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Left Side: Main Content
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _buildSectionTitle(
                                                    '概览回顾',
                                                    Icons.insights_rounded,
                                                    colorScheme),
                                                const SizedBox(height: 16),
                                                _buildRangeSummary(
                                                    colorScheme, isWide),
                                                _buildOverviewInsightPanels(
                                                    colorScheme, isWide),
                                                _buildMedalWall(
                                                    colorScheme, isWide),
                                                if (_dimension ==
                                                    TimelineDimension
                                                        .daily) ...[
                                                  const SizedBox(height: 40),
                                                  _buildSectionTitle(
                                                      '时光足迹',
                                                      Icons
                                                          .auto_stories_outlined,
                                                      colorScheme),
                                                  const SizedBox(height: 16),
                                                  _buildTimelineFlow(
                                                      colorScheme),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 48),
                                          // Right Side: Sidebar
                                          SizedBox(
                                            width: 320,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _buildSectionTitle(
                                                    '数据深度洞察',
                                                    Icons.analytics_outlined,
                                                    colorScheme),
                                                const SizedBox(height: 20),
                                                _buildSideHighlights(
                                                    colorScheme),
                                                const SizedBox(height: 40),
                                                _buildSectionTitle(
                                                    '感悟与思考',
                                                    Icons.edit_note_rounded,
                                                    colorScheme),
                                                const SizedBox(height: 16),
                                                _buildReflection(colorScheme),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      // Mobile Layout (Existing)
                                      _buildSectionTitle(
                                          _dimension == TimelineDimension.daily
                                              ? '概览回顾'
                                              : '阶段回顾',
                                          Icons.insights_rounded,
                                          colorScheme),
                                      const SizedBox(height: 16),
                                      _buildRangeSummary(colorScheme, isWide),
                                      _buildOverviewInsightPanels(
                                          colorScheme, isWide),
                                      _buildMedalWall(colorScheme, isWide),
                                      if (_dimension ==
                                          TimelineDimension.daily) ...[
                                        const SizedBox(height: 40),
                                        _buildSectionTitle(
                                            '时光足迹',
                                            Icons.auto_stories_outlined,
                                            colorScheme),
                                        const SizedBox(height: 16),
                                        _buildTimelineFlow(colorScheme),
                                      ],
                                      const SizedBox(height: 40),
                                      _buildSectionTitle(
                                          '数据深度洞察',
                                          Icons.analytics_outlined,
                                          colorScheme),
                                      const SizedBox(height: 16),
                                      _buildSideHighlights(colorScheme),
                                      const SizedBox(height: 40),
                                      _buildSectionTitle('感悟与思考',
                                          Icons.edit_note_rounded, colorScheme),
                                      const SizedBox(height: 16),
                                      _buildReflection(colorScheme),
                                    ],
                                    const SizedBox(height: 60),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton(ColorScheme cs) {
    return Column(
      key: const ValueKey('skeleton'),
      children: [
        Container(
          height: 110,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(32),
          ),
        ),
        const SizedBox(height: 40),
        ...List.generate(
            3,
            (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    height: 90,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                )),
      ],
    );
  }

  Widget _buildBackground(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surface,
            cs.primaryContainer.withValues(alpha: 0.08),
            cs.secondaryContainer.withValues(alpha: 0.04),
            cs.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
              bottom: 100,
              left: -100,
              child: _buildBlob(cs.secondary.withValues(alpha: 0.03), 400)),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent)),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme cs) {
    return SliverAppBar(
      expandedHeight: 280,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          tooltip: '保存分享长图',
          icon: _isExportingPoster
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.ios_share_rounded),
          onPressed:
              _isLoading || _isExportingPoster
                  ? null
                  : _chooseAndSaveTimelinePoster,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            // Subtle Pattern or Illustration (Fixed)
            Positioned(
              right: -60,
              top: -40,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.12),
                      cs.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            _buildGreeting(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildGreeting(ColorScheme cs) {
    String label;
    String sub;
    switch (_dimension) {
      case TimelineDimension.daily:
        label = DateFormat('yyyy年MM月dd日').format(_selectedDate);
        sub = DateFormat('EEEE', 'zh_CN').format(_selectedDate);
        break;
      case TimelineDimension.weekly:
        final start =
            _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        final end = start.add(const Duration(days: 6));
        label =
            '${DateFormat('MM/dd').format(start)} - ${DateFormat('MM/dd').format(end)}';
        sub = '本周回顾';
        break;
      case TimelineDimension.monthly:
        label = DateFormat('yyyy年MM月').format(_selectedDate);
        sub = '月度总结';
        break;
      case TimelineDimension.yearly:
        label = '${_selectedDate.year}年';
        sub = '年度回顾';
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sub,
                    style: TextStyle(
                        fontSize: 14,
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(label,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Serif')),
                if (_dimension != TimelineDimension.daily) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _getDateRangeString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _buildDimensionToggle(cs),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(
                    _getMotivationText(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildNavButton(Icons.chevron_left_rounded, () => _navigate(-1)),
              const SizedBox(width: 8),
              _buildNavButton(Icons.chevron_right_rounded, () => _navigate(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      ),
    );
  }

  void _navigate(int direction) {
    setState(() {
      switch (_dimension) {
        case TimelineDimension.daily:
          _selectedDate = _selectedDate.add(Duration(days: direction));
          break;
        case TimelineDimension.weekly:
          _selectedDate = _selectedDate.add(Duration(days: direction * 7));
          break;
        case TimelineDimension.monthly:
          _selectedDate =
              DateTime(_selectedDate.year, _selectedDate.month + direction, 1);
          break;
        case TimelineDimension.yearly:
          _selectedDate = DateTime(_selectedDate.year + direction, 1, 1);
          break;
      }
    });
    _loadData();
  }

  Widget _buildDimensionToggle(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: TimelineDimension.values.map((d) {
          final isSelected = _dimension == d;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _dimension = d);
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? cs.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    _getDimensionName(d),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getDimensionName(TimelineDimension d) {
    switch (d) {
      case TimelineDimension.daily:
        return '日';
      case TimelineDimension.weekly:
        return '周';
      case TimelineDimension.monthly:
        return '月';
      case TimelineDimension.yearly:
        return '年';
    }
  }

  String _getDateRangeString() {
    if (_summary != null &&
        _summary!.actualStartTime != null &&
        _summary!.actualEndTime != null) {
      return '${DateFormat('yyyy.MM.dd').format(_summary!.actualStartTime!)} - ${DateFormat('yyyy.MM.dd').format(_summary!.actualEndTime!)}';
    }

    DateTime start;
    DateTime end;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

    switch (_dimension) {
      case TimelineDimension.daily:
        return DateFormat('yyyy.MM.dd').format(day);
      case TimelineDimension.weekly:
        start = day.subtract(Duration(days: day.weekday - 1));
        end = start.add(const Duration(days: 6));
        final displayEnd = end.isAfter(today) ? today : end;
        return '${DateFormat('yyyy.MM.dd').format(start)} - ${DateFormat('yyyy.MM.dd').format(displayEnd)}';
      case TimelineDimension.monthly:
        start = DateTime(day.year, day.month, 1);
        end = DateTime(day.year, day.month + 1, 0);
        final displayEnd = end.isAfter(today) ? today : end;
        return '${DateFormat('yyyy.MM.dd').format(start)} - ${DateFormat('yyyy.MM.dd').format(displayEnd)}';
      case TimelineDimension.yearly:
        start = DateTime(day.year, 1, 1);
        end = DateTime(day.year, 12, 31);
        final displayEnd = end.isAfter(today) ? today : end;
        return '${DateFormat('yyyy.MM.dd').format(start)} - ${DateFormat('yyyy.MM.dd').format(displayEnd)}';
    }
  }

  Widget _buildStatsOverview(ColorScheme cs, bool isWide) {
    final summary = _summary;
    if (summary == null) return const SizedBox();

    final focusTimeStr = _formatMinutes(_totalFocusMinutes);
    final completionRate =
        _totalCount > 0 ? _completedCount / _totalCount : 0.0;
    final screenConversion = _screenTimeSeconds > 0
        ? (_totalFocusMinutes * 60) / _screenTimeSeconds
        : 0.0;
    final topSub = summary.topSubject;
    final subRatio = _subjectRatio(summary, topSub);
    final subjectName = topSub != '全能型' ? topSub : '多主题任务';
    final keywordText = _buildKeywordText(summary);
    final qualityLine = summary.pomodoroCount > 0
        ? '平均每次 ${summary.avgPomodoroMinutes.toStringAsFixed(0)} 分钟，深度专注占 ${_formatPercent(summary.deepWorkCount / summary.pomodoroCount)}。'
        : '暂时没有可统计的专注质量数据。';

    final hero = Container(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 28 : 22),
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: cs.brightness == Brightness.dark ? 0.18 : 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_getPeriodName()}你累计专注 $focusTimeStr，完成 $_completedCount 个任务。',
            style: TextStyle(
              fontSize: isWide ? 24 : 20,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${summary.peakHour}:00 是你的黄金产出时段，$subjectName 占据了你 ${subRatio > 0 ? subRatio : (summary.homeworkRatio * 100).toInt()}% 的精力。$qualityLine',
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildInsightPill('完成率 ${_formatPercent(completionRate)}',
                  Icons.check_circle_outline_rounded, cs.primary, cs),
              _buildInsightPill('连续活跃 ${summary.consecutiveActiveDays} 天',
                  Icons.local_fire_department_outlined, Colors.deepOrange, cs),
              _buildInsightPill('转化率 ${_formatPercent(screenConversion)}',
                  Icons.desktop_windows_outlined, Colors.teal, cs),
              _buildInsightPill('屏幕偏好 ${_topAppCategory ?? '学习办公'}',
                  Icons.category_outlined, Colors.orange, cs),
              _buildInsightPill(
                  '关键词 $keywordText', Icons.sell_outlined, Colors.indigo, cs),
            ],
          ),
        ],
      ),
    );

    Widget statsGrid;
    if (isWide) {
      statsGrid = Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
                '总专注', focusTimeStr, '', Icons.spa_outlined, cs.primary, cs),
            _buildStatItem('任务完成', '$_completedCount/$_totalCount', '',
                Icons.task_alt_rounded, cs.secondary, cs),
            _buildStatItem('完成率', _formatPercent(completionRate), '',
                Icons.pie_chart_outline_rounded, Colors.green, cs),
            _buildStatItem(
                '平均专注',
                summary.avgPomodoroMinutes.toStringAsFixed(0),
                'min',
                Icons.psychology_outlined,
                Colors.purple,
                cs),
            _buildStatItem('DDL冲刺', '$_deadlineSprintCount', '次',
                Icons.auto_graph_rounded, Colors.redAccent, cs),
            _buildStatItem('最强主题', subjectName, '', Icons.category_outlined,
                Colors.orange, cs),
          ],
        ),
      );
    } else {
      statsGrid = Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('总专注', focusTimeStr, '', Icons.spa_outlined,
                    cs.primary, cs),
                _buildStatItem('任务完成', '$_completedCount/$_totalCount', '',
                    Icons.task_alt_rounded, cs.secondary, cs),
                _buildStatItem('完成率', _formatPercent(completionRate), '',
                    Icons.pie_chart_outline_rounded, Colors.green, cs),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                    '平均专注',
                    summary.avgPomodoroMinutes.toStringAsFixed(0),
                    'min',
                    Icons.psychology_outlined,
                    Colors.purple,
                    cs),
                _buildStatItem('DDL冲刺', '$_deadlineSprintCount', '次',
                    Icons.auto_graph_rounded, Colors.redAccent, cs),
                _buildStatItem('最强主题', subjectName, '', Icons.category_outlined,
                    Colors.orange, cs),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hero,
        const SizedBox(height: 14),
        statsGrid,
        const SizedBox(height: 10),
        _buildAchievementStrip(cs),
      ],
    );
  }

  Widget _buildInsightPill(
      String text, IconData icon, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _buildAchievementStrip(ColorScheme cs) {
    final badges = _earnedMedals();
    if (badges.isEmpty) return const SizedBox();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: badges.take(4).map((badge) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badge.icon, color: badge.color, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(badge.title,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  Text(badge.desc,
                      style:
                          TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<
      ({
        String title,
        String desc,
        DateTime? earnedAt,
        IconData icon,
        Color color
      })> _earnedMedals() {
    final summary = _summary;
    if (summary == null) return const [];
    final earnedAt = summary.actualEndTime ??
        summary.latestTodoCompletionTime ??
        summary.longestPomodoroDate ??
        _selectedDate;
    final badges = <({
      String title,
      String desc,
      DateTime? earnedAt,
      IconData icon,
      Color color
    })>[];
    if (summary.pomodoroCount >= 1) {
      badges.add((
        title: '专注启动者',
        desc: '记录 ${summary.pomodoroCount} 次专注',
        earnedAt: earnedAt,
        icon: Icons.play_circle_outline_rounded,
        color: Colors.green
      ));
    }
    if (_totalFocusMinutes >= 120) {
      badges.add((
        title: '两小时守门员',
        desc: '累计专注 ${_formatMinutes(_totalFocusMinutes)}',
        earnedAt: earnedAt,
        icon: Icons.hourglass_bottom_rounded,
        color: Colors.blue
      ));
    }
    if (_totalFocusMinutes >= 480) {
      badges.add((
        title: '八小时长征',
        desc: '累计专注 ${_formatMinutes(_totalFocusMinutes)}',
        earnedAt: earnedAt,
        icon: Icons.terrain_rounded,
        color: Colors.brown
      ));
    }
    if (summary.deepWorkCount > 0) {
      badges.add((
        title: '深度工作者',
        desc: '${summary.deepWorkCount} 次深度专注',
        earnedAt: summary.longestPomodoroDate ?? earnedAt,
        icon: Icons.diamond_outlined,
        color: Colors.purple
      ));
    }
    if (summary.longestPomodoroMinutes >= 90) {
      badges.add((
        title: '长专注选手',
        desc: '单次专注 ${summary.longestPomodoroMinutes} 分钟',
        earnedAt: summary.longestPomodoroDate ?? earnedAt,
        icon: Icons.workspace_premium_rounded,
        color: Colors.amber
      ));
    }
    if (summary.interruptionRate <= 0.1 && summary.pomodoroCount >= 3) {
      badges.add((
        title: '稳定输出',
        desc: '中断率 ${_formatPercent(summary.interruptionRate)}',
        earnedAt: earnedAt,
        icon: Icons.shield_moon_rounded,
        color: Colors.indigoAccent
      ));
    }
    if (_completedCount >= 1) {
      badges.add((
        title: '任务收割者',
        desc: '完成 $_completedCount 个任务',
        earnedAt: summary.latestTodoCompletionTime ?? earnedAt,
        icon: Icons.task_alt_rounded,
        color: Colors.green
      ));
    }
    if (_totalCount > 0 && _completedCount / _totalCount >= 0.8) {
      badges.add((
        title: '计划兑现者',
        desc: '完成率 ${_formatPercent(_completedCount / _totalCount)}',
        earnedAt: summary.latestTodoCompletionTime ?? earnedAt,
        icon: Icons.fact_check_outlined,
        color: Colors.lightGreen
      ));
    }
    if (_earlyCompletionCount > 0) {
      badges.add((
        title: '提前交付者',
        desc: '提前完成 $_earlyCompletionCount 项',
        earnedAt: summary.latestTodoCompletionTime ?? earnedAt,
        icon: Icons.rocket_launch_outlined,
        color: Colors.cyan
      ));
    }
    if (_deadlineSprintCount > 0) {
      badges.add((
        title: 'DDL驯服者',
        desc: '截止前完成 $_deadlineSprintCount 项',
        earnedAt: summary.latestTodoCompletionTime ?? earnedAt,
        icon: Icons.flag_outlined,
        color: Colors.redAccent
      ));
    }
    final hasRhythm = summary.hourlyDistribution.any((v) => v > 0);
    if (hasRhythm && (summary.peakHour >= 20 || summary.peakHour <= 5)) {
      badges.add((
        title: '深夜效率王',
        desc: '${summary.peakHour}:00 产出最高',
        earnedAt: earnedAt,
        icon: Icons.nightlight_round,
        color: Colors.indigo
      ));
    } else if (hasRhythm) {
      badges.add((
        title: '黄金${summary.peakHour}点',
        desc: '你的高效窗口',
        earnedAt: earnedAt,
        icon: Icons.wb_sunny_outlined,
        color: Colors.orange
      ));
    }
    if (summary.subjectDistribution.length >= 4) {
      badges.add((
        title: '学习多面手',
        desc: '覆盖 ${summary.subjectDistribution.length} 个主题',
        earnedAt: earnedAt,
        icon: Icons.hub_outlined,
        color: Colors.teal
      ));
    }
    final topSubject = summary.topSubject;
    final topSubjectRatio = _subjectRatio(summary, topSubject);
    if (topSubject != '全能型' && topSubjectRatio >= 45) {
      badges.add((
        title: '主线推进者',
        desc: '$topSubject 占 $topSubjectRatio%',
        earnedAt: earnedAt,
        icon: Icons.route_outlined,
        color: Colors.deepPurple
      ));
    }
    if (summary.searchCount >= 3) {
      badges.add((
        title: '知识侦察兵',
        desc: '${summary.searchCount} 次知识检索',
        earnedAt: summary.lastSearchTime ?? earnedAt,
        icon: Icons.travel_explore_rounded,
        color: Colors.teal
      ));
    }
    if (summary.examPrepCount >= 3) {
      badges.add((
        title: '备考冲刺者',
        desc: '${summary.examPrepCount} 次备考信号',
        earnedAt: earnedAt,
        icon: Icons.school_outlined,
        color: Colors.red
      ));
    }
    if (summary.consecutiveActiveDays >= 3) {
      badges.add((
        title: '长跑型选手',
        desc: '连续活跃 ${summary.consecutiveActiveDays} 天',
        earnedAt: earnedAt,
        icon: Icons.local_fire_department_outlined,
        color: Colors.deepOrange
      ));
    }
    if (_courseCount >= 1) {
      badges.add((
        title: '课表同行者',
        desc: '记录 $_courseCount 节课',
        earnedAt: earnedAt,
        icon: Icons.event_note_outlined,
        color: Colors.blueGrey
      ));
    }
    if (_maxDailyCourseCount >= 5) {
      badges.add((
        title: '满课生存者',
        desc: '最满一天 $_maxDailyCourseCount 节课',
        earnedAt: earnedAt,
        icon: Icons.view_day_outlined,
        color: Colors.deepOrange
      ));
    }
    if (_screenTimeSeconds > 0 &&
        _productiveScreenSeconds / _screenTimeSeconds >= 0.5) {
      badges.add((
        title: '屏幕掌控者',
        desc:
            '生产力应用 ${_formatPercent(_productiveScreenSeconds / _screenTimeSeconds)}',
        earnedAt: earnedAt,
        icon: Icons.desktop_windows_outlined,
        color: Colors.blueGrey
      ));
    }
    if (_screenTimeSeconds > 0 &&
        _distractionScreenSeconds / _screenTimeSeconds <= 0.15) {
      badges.add((
        title: '低分心模式',
        desc:
            '分心应用 ${_formatPercent(_distractionScreenSeconds / _screenTimeSeconds)}',
        earnedAt: earnedAt,
        icon: Icons.visibility_off_outlined,
        color: Colors.grey
      ));
    }

    return badges;
  }

  Widget _buildMedalWall(ColorScheme cs, bool isWide) {
    final medals = _earnedMedals();
    if (medals.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('勋章墙', Icons.emoji_events_outlined, cs),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: medals.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 3 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 104,
            ),
            itemBuilder: (context, index) {
              final medal = medals[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: medal.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(medal.icon, color: medal.color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            medal.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            medal.desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '获得于 ${_formatMedalTime(medal.earnedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.64),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatMedalTime(DateTime? time) {
    if (time == null) return _getDateRangeString();
    switch (_dimension) {
      case TimelineDimension.daily:
        return DateFormat('HH:mm').format(time);
      case TimelineDimension.weekly:
      case TimelineDimension.monthly:
        return DateFormat('MM/dd HH:mm').format(time);
      case TimelineDimension.yearly:
        return DateFormat('yyyy/MM/dd').format(time);
    }
  }

  Widget _buildStatItem(String label, String value, String unit, IconData icon,
      Color color, ColorScheme cs) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
                if (unit.isNotEmpty)
                  Text(' $unit',
                      style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
              ],
            ),
          ),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) return '$hours 小时 $mins 分钟';
    if (hours > 0) return '$hours 小时';
    return '$mins 分钟';
  }

  String _formatSecondsCompact(int seconds) {
    if (seconds <= 0) return '0分';
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    if (hours > 0 && mins > 0) return '$hours时$mins分';
    if (hours > 0) return '$hours时';
    if (mins > 0) return '$mins分';
    return '$seconds秒';
  }

  String _formatPercent(double value) {
    if (value.isNaN || value.isInfinite) return '0%';
    return '${(value.clamp(0.0, 1.0) * 100).round()}%';
  }

  int _subjectRatio(TimelineSummary summary, String subject) {
    if (!summary.subjectDistribution.containsKey(subject)) return 0;
    final total = summary.subjectDistribution.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return 0;
    return ((summary.subjectDistribution[subject]! / total) * 100).round();
  }

  String _buildKeywordText(TimelineSummary summary) {
    final words = <String>[
      ...summary.subjectDistribution.entries
          .where((e) => e.key != '其他')
          .map((e) => e.key),
      if (summary.examPrepCount > 0) '备考',
      if (summary.deepWorkCount > 0) '深度专注',
      if (_deadlineSprintCount > 0) 'DDL',
    ];
    if (words.isEmpty) return '专注、计划';
    return words.take(4).join('、');
  }

  String _getTaskCompositionReason() {
    final homework = (_summary?.homeworkRatio ?? 0) * 100;
    final exam = (_summary?.examRatio ?? 0) * 100;
    if (homework > 40) return '作业类占比 ${homework.round()}%，高于 40%';
    if (exam > 20) return '备考类占比 ${exam.round()}%，高于 20%';
    return '作业和备考都未单独占主导';
  }

  Widget _buildSectionTitle(String title, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineFlow(ColorScheme cs) {
    if (_events.isEmpty) return _buildEmptyState(cs);
    return Column(
        children: _events.map((e) => _buildJournalEntry(e, cs)).toList());
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          '这段时间静悄悄的，\n休息也是为了更好地出发。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildJournalEntry(TimelineEvent event, ColorScheme cs) {
    final timeStr = DateFormat('HH:mm').format(event.timestamp);
    final isImportant = event.type == TimelineEventType.pomodoroEnd ||
        event.type == TimelineEventType.todoCompleted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timeStr,
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatEventTitle(event),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isImportant ? FontWeight.w600 : FontWeight.normal,
                        color: cs.onSurface)),
                if (event.subtitle != null)
                  Text(event.subtitle!,
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSummary(ColorScheme cs, bool isWide) {
    if (_summary == null) return _buildEmptyState(cs);

    final List<Widget> cards = [
      _buildTrendCard(
        '专注产出',
        '${(_summary!.pomodoroCount)} 次专注',
        '平均每轮 ${_summary!.avgPomodoroMinutes.toStringAsFixed(0)} 分钟',
        Icons.timer_rounded,
        cs.primary,
        cs,
        trend: _summary!.dailyTrend,
        extraItems: _summary!.topFocusSessions.length > 1
            ? _summary!.topFocusSessions
                .skip(1)
                .take(4)
                .toList()
                .asMap()
                .entries
                .map((e) {
                final session = e.value;
                final dur = session['actual_duration'] as int;
                return _buildRankItem(
                    e.key + 2,
                    session['todo_title'] as String? ?? '无题',
                    '${dur ~/ 60}m',
                    cs);
              }).toList()
            : null,
      ),
      _buildStatCard(
        '最长单次专注',
        '${_summary!.longestPomodoroMinutes} 分钟',
        _summary!.longestPomodoroTitle != null
            ? '专注「${_summary!.longestPomodoroTitle}」'
            : '挑战自我极限',
        Icons.workspace_premium_rounded,
        Colors.amber,
        cs,
        extraItems: _summary!.topFocusSessions.length > 1
            ? _summary!.topFocusSessions
                .skip(1)
                .take(4)
                .toList()
                .asMap()
                .entries
                .map((e) {
                final session = e.value;
                final dur = session['actual_duration'] as int;
                return _buildRankItem(
                    e.key + 2,
                    session['todo_title'] as String? ?? '无题',
                    '${dur ~/ 60}m',
                    cs);
              }).toList()
            : null,
      ),
      _buildStatCard(
        '专注质量',
        '中断率 ${(_summary!.interruptionRate * 100).toStringAsFixed(1)}%',
        '${_summary!.interruptionCount} 次被打断或放弃',
        Icons.shield_moon_rounded,
        Colors.indigo,
        cs,
        extraItems: [
          const SizedBox(height: 8),
          _buildRankItem(0, '深度心流', '${_summary!.deepWorkCount}次', cs),
          _buildRankItem(0, '平均时长',
              '${_summary!.avgPomodoroMinutes.toStringAsFixed(0)}m', cs),
        ],
      ),
      _buildStatCard(
        '任务执行力',
        '完成率 ${_formatPercent(_totalCount > 0 ? _completedCount / _totalCount : 0)}',
        '计划 $_totalCount 项，完成 $_completedCount 项',
        Icons.done_all_rounded,
        Colors.green,
        cs,
        extraItems: [
          const SizedBox(height: 8),
          _buildRankItem(0, '提前完成', '$_earlyCompletionCount项', cs),
          _buildRankItem(0, '截止前24小时完成', '$_deadlineSprintCount项', cs),
        ],
      ),
      _buildStatCard(
        '屏幕时间转化',
        _formatPercent(_screenTimeSeconds > 0
            ? (_totalFocusMinutes * 60) / _screenTimeSeconds
            : 0),
        '屏幕使用 ${_formatSecondsCompact(_screenTimeSeconds)}，专注 ${_formatMinutes(_totalFocusMinutes)}',
        Icons.monitor_heart_outlined,
        Colors.teal,
        cs,
        extraItems: [
          const SizedBox(height: 8),
          _buildRankItem(
              0,
              '生产力应用',
              _formatPercent(_screenTimeSeconds > 0
                  ? _productiveScreenSeconds / _screenTimeSeconds
                  : 0),
              cs),
          _buildRankItem(
              0, '分心应用', _formatSecondsCompact(_distractionScreenSeconds), cs),
          ..._topScreenApps.take(3).toList().asMap().entries.map((e) {
            final app = e.value;
            return _buildRankItem(
                e.key + 1, app.key, _formatSecondsCompact(app.value), cs);
          }),
        ],
      ),
      _buildTrendCard(
        '深度工作',
        '${_summary!.deepWorkCount} 次',
        '单次专注达到 60 分钟',
        Icons.bolt_rounded,
        Colors.amber,
        cs,
        extraItems: [
          const SizedBox(height: 8),
          _buildMiniBarChart(
              _summary!.hourlyDistribution.map((v) => v.toDouble()).toList(),
              cs.primary,
              cs),
        ],
      ),
      if (_courseCount > 0)
        _buildStatCard(
          '课程节律',
          '$_courseCount 节课',
          _maxDailyCourseCount > 0 ? '最满一天 $_maxDailyCourseCount 节课' : '课表联动统计',
          Icons.school_outlined,
          Colors.deepPurple,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            _buildRankItem(0, '课后任务完成', '${_summary!.todoCompletedCount}项', cs),
            _buildRankItem(0, '备考任务信号', '${_summary!.examPrepCount}次', cs),
          ],
        ),
      if (_summary!.examPrepCount > 0)
        _buildStatCard(
          '备考冲刺波',
          '${_summary!.examPrepCount} 次备考',
          '检测到高强度考试准备',
          Icons.auto_graph_rounded,
          Colors.redAccent,
          cs,
          extraItems: [
            const SizedBox(height: 8),
            ..._summary!.examSubjectDist.entries.take(5).map((e) {
              final maxVal = _summary!.examSubjectDist.values.isNotEmpty
                  ? _summary!.examSubjectDist.values.reduce(math.max).toDouble()
                  : 1.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key,
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                        Text('${e.value}次',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: maxVal > 0 ? e.value / maxVal : 0,
                        backgroundColor:
                            Colors.redAccent.withValues(alpha: 0.1),
                        color: Colors.redAccent,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      _buildStatCard(
        '知识探索',
        '${_summary!.searchCount} 次检索',
        _summary!.topSearchQuery != null
            ? '最常搜索: ${_summary!.topSearchQuery}'
            : '探索未知的边界',
        Icons.travel_explore_rounded,
        Colors.teal,
        cs,
        extraItems: _summary!.topSearchQueries
            .take(5)
            .toList()
            .asMap()
            .entries
            .map((e) {
          final q = e.value;
          return _buildRankItem(
              e.key + 1, q['query'] as String? ?? '', '${q['freq']}x', cs);
        }).toList(),
      ),
      _buildStatCard(
        '任务构成',
        _summary!.homeworkRatio > 0.4
            ? '作业攻坚型'
            : (_summary!.examRatio > 0.2 ? '备考冲刺型' : '全面均衡型'),
        _getTaskCompositionReason(),
        Icons.donut_large_rounded,
        Colors.blueGrey,
        cs,
        extraItems: [
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                height: 48,
                width: 48,
                child: CustomPaint(
                  painter: _DonutPainter([
                    MapEntry('HW', _summary!.homeworkRatio),
                    MapEntry('EX', _summary!.examRatio),
                    MapEntry(
                        'OT',
                        (1.0 - _summary!.homeworkRatio - _summary!.examRatio)
                            .clamp(0.0, 1.0)),
                  ], [
                    cs.primary,
                    cs.secondary,
                    cs.outlineVariant
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _buildRankItem(
                        0, '作业类', _formatPercent(_summary!.homeworkRatio), cs),
                    _buildRankItem(
                        0, '备考类', _formatPercent(_summary!.examRatio), cs),
                    _buildRankItem(
                        0,
                        '其他主题',
                        _formatPercent((1.0 -
                                _summary!.homeworkRatio -
                                _summary!.examRatio)
                            .clamp(0.0, 1.0)),
                        cs),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ];

    final int colCount =
        isWide ? (MediaQuery.of(context).size.width > 1200 ? 4 : 3) : 2;

    return _buildBalancedCardRows(cards, colCount);
  }

  Widget _buildBalancedCardRows(List<Widget> cards, int maxColumns) {
    if (cards.isEmpty) return const SizedBox();

    final columns = math.min(maxColumns, cards.length);
    final rowCount = (cards.length / columns).ceil();
    final baseSize = cards.length ~/ rowCount;
    final remainder = cards.length % rowCount;

    int cursor = 0;
    final rows = <List<Widget>>[];
    for (int row = 0; row < rowCount; row++) {
      final rowSize = baseSize + (row < remainder ? 1 : 0);
      rows.add(cards.sublist(cursor, cursor + rowSize));
      cursor += rowSize;
    }

    return Column(
      children: [
        for (int rowIndex = 0; rowIndex < rows.length; rowIndex++)
          Padding(
            padding:
                EdgeInsets.only(bottom: rowIndex == rows.length - 1 ? 0 : 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int colIndex = 0;
                      colIndex < rows[rowIndex].length;
                      colIndex++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: colIndex == 0 ? 0 : 6,
                          right: colIndex == rows[rowIndex].length - 1 ? 0 : 6,
                        ),
                        child: rows[rowIndex][colIndex],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMiniBarChart(List<double> data, Color color, ColorScheme cs) {
    if (data.isEmpty) return const SizedBox();
    final max = data.reduce((a, b) => a > b ? a : b);
    if (max == 0) return const SizedBox();

    return SizedBox(
        height: 38,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data
              .map((v) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: Container(
                        height: math.max(3, (v / max) * 38),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ));
  }

  Widget _buildTrendCard(String title, String content, String subtitle,
      IconData icon, Color color, ColorScheme cs,
      {List<double>? trend, List<Widget>? extraItems}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 12),
          if (trend != null && trend.length >= 2) ...[
            SizedBox(
              height: 44,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(trend, color.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(content,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (extraItems != null && extraItems.isNotEmpty) ...[
            const Divider(height: 16, thickness: 0.5),
            ...extraItems,
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String content, String subtitle,
      IconData icon, Color color, ColorScheme cs,
      {List<Widget>? extraItems}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 12),
          Text(content,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (extraItems != null && extraItems.isNotEmpty) ...[
            const Divider(height: 16, thickness: 0.5),
            ...extraItems,
          ],
        ],
      ),
    );
  }

  Widget _buildRankItem(int rank, String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (rank > 0) ...[
            Container(
              width: 12,
              height: 12,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('$rank',
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _buildOverviewInsightPanels(ColorScheme cs, bool isWide) {
    final panels = [
      _buildMasonryInsightPanel(
        '质量雷达',
        Icons.shield_outlined,
        cs,
        _buildQualitySnapshot(cs, fillHeight: isWide),
        fillHeight: isWide,
      ),
      _buildMasonryInsightPanel(
        '屏幕投入',
        Icons.devices_other_rounded,
        cs,
        _buildScreenSnapshot(cs, fillHeight: isWide),
        fillHeight: isWide,
      ),
      _buildMasonryInsightPanel(
        '产出节拍',
        Icons.query_stats_rounded,
        cs,
        _buildHourlyRhythm(cs),
        fillHeight: isWide,
      ),
    ];

    if (!isWide) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Column(
          children: [
            for (int i = 0; i < panels.length; i++)
              Padding(
                padding:
                    EdgeInsets.only(bottom: i == panels.length - 1 ? 0 : 16),
                child: panels[i],
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: SizedBox(
        height: 286,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < panels.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 6,
                    right: i == panels.length - 1 ? 0 : 6,
                  ),
                  child: panels[i],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasonryInsightPanel(
    String title,
    IconData icon,
    ColorScheme cs,
    Widget child, {
    bool fillHeight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title, icon, cs),
        const SizedBox(height: 12),
        if (fillHeight) Expanded(child: child) else child,
      ],
    );
  }

  Widget _buildSideHighlights(ColorScheme cs) {
    if (_summary == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('学习图谱', Icons.auto_awesome_mosaic_rounded, cs),
        const SizedBox(height: 20),
        _buildSubjectDonutChart(cs),
      ],
    );
  }

  Widget _buildQualitySnapshot(ColorScheme cs, {bool fillHeight = false}) {
    final summary = _summary!;
    final deepRatio = summary.pomodoroCount > 0
        ? summary.deepWorkCount / summary.pomodoroCount
        : 0.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: fillHeight
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRankItem(0, '平均专注时长',
              '${summary.avgPomodoroMinutes.toStringAsFixed(0)}分钟', cs),
          _buildRankItem(0, '深度专注占比', _formatPercent(deepRatio), cs),
          _buildRankItem(
              0, '中断率', _formatPercent(summary.interruptionRate), cs),
          _buildRankItem(
              0, '最长连续专注链', '${summary.longestPomodoroMinutes}分钟', cs),
          const SizedBox(height: 10),
          Text(
            summary.interruptionRate <= 0.15
                ? '你不是在频繁切换，而是真的沉下来了。'
                : '本阶段中断偏多，适合把高难任务放进黄金时段。',
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenSnapshot(ColorScheme cs, {bool fillHeight = false}) {
    if (_screenTimeSeconds <= 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Text('暂无屏幕使用数据',
            style:
                TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: fillHeight
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRankItem(
              0, '屏幕总时长', _formatSecondsCompact(_screenTimeSeconds), cs),
          _buildRankItem(
              0,
              '专注转化率',
              _formatPercent((_totalFocusMinutes * 60) / _screenTimeSeconds),
              cs),
          _buildRankItem(
              0,
              '生产力应用占比',
              _formatPercent(_productiveScreenSeconds / _screenTimeSeconds),
              cs),
          _buildRankItem(0, '分心应用时长',
              _formatSecondsCompact(_distractionScreenSeconds), cs),
          if (_topScreenApps.isNotEmpty) ...[
            const Divider(height: 18, thickness: 0.5),
            ..._topScreenApps.take(3).toList().asMap().entries.map((e) {
              final app = e.value;
              return _buildRankItem(
                  e.key + 1, app.key, _formatSecondsCompact(app.value), cs);
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSubjectDonutChart(ColorScheme cs) {
    final dist = _summary!.subjectDistribution;
    if (dist.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        child: Text('暂无分类数据',
            style:
                TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
      );
    }

    final sorted = dist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final List<Color> palette = [
      cs.primary,
      cs.secondary,
      cs.tertiary,
      cs.errorContainer,
      Colors.orangeAccent,
      Colors.tealAccent,
      Colors.indigoAccent,
      cs.outline,
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 140,
            child: Stack(
              children: [
                Center(
                  child: CustomPaint(
                    size: const Size(120, 120),
                    painter: _DonutPainter(sorted, palette),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(_summary!.pomodoroCount)}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -1),
                      ),
                      Text(
                        '总项',
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(sorted.length, (i) {
              final e = sorted[i];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette[i % palette.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${e.key} ${(e.value * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyRhythm(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.1),
            cs.secondary.withValues(alpha: 0.1)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartHeight = constraints.hasBoundedHeight
              ? (constraints.maxHeight - 96).clamp(52.0, 76.0)
              : 70.0;
          final chart = _buildHourlyChart(
            _summary!.hourlyDistribution,
            _summary!.peakHour,
            cs,
            height: chartHeight,
          );

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 24),
              const SizedBox(height: 8),
              Text('${_getPeriodName()}黄金活跃期',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              chart,
              const SizedBox(height: 10),
              Text('${_summary!.peakHour}:00 为巅峰时刻',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: cs.primary)),
              const SizedBox(height: 6),
              Text('该时段活动最密集，适合安排高难任务',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      height: 1.4)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHourlyChart(List<int> distribution, int peakHour, ColorScheme cs,
      {double height = 82}) {
    if (distribution.isEmpty) return SizedBox(height: height);

    final int maxVal = distribution.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (i) {
                final h = distribution[i];
                final bool isPeak = i == peakHour;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FractionallySizedBox(
                      heightFactor: h == 0 ? 0.06 : (h / maxVal),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isPeak
                              ? cs.primary
                              : cs.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(24, (i) {
              final show = i == 0 || i == 6 || i == 12 || i == 18 || i == 23;
              return Expanded(
                child: Text(
                  show ? i.toString().padLeft(2, '0') : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 9,
                    color: i == peakHour
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.48),
                    fontWeight:
                        i == peakHour ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ],
    );
  }

  String _getPeriodName() {
    switch (_dimension) {
      case TimelineDimension.daily:
        return '今日';
      case TimelineDimension.weekly:
        return '本周';
      case TimelineDimension.monthly:
        return '本月';
      case TimelineDimension.yearly:
        return '今年';
    }
  }

  Widget _buildReflection(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(Icons.format_quote_rounded,
              color: cs.primary.withValues(alpha: 0.3), size: 40),
          const SizedBox(height: 16),
          Text(
            _getReflectionText(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.8,
              fontFamily: 'Serif',
              color: cs.onSurface.withValues(alpha: 0.8),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          Text('— 时光记录员',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.primary.withValues(alpha: 0.5),
                  letterSpacing: 2)),
        ],
      ),
    );
  }

  String _formatEventTitle(TimelineEvent event) {
    final int seed = event.id.hashCode;
    final String sub = (event.subtitle ?? '').toLowerCase();

    String pick(List<String> options) => options[seed % options.length];

    // Keyword detection
    final bool isHomework =
        sub.contains('作业') || sub.contains('练习') || sub.contains('刷题');
    final bool isExam = sub.contains('考试') ||
        sub.contains('测验') ||
        sub.contains('考证') ||
        sub.contains('竞赛');
    final bool isReview = sub.contains('复习') ||
        sub.contains('总结') ||
        sub.contains('整理') ||
        sub.contains('笔记');
    final bool isReading = sub.contains('阅读') ||
        sub.contains('看书') ||
        sub.contains('读书') ||
        sub.contains('文献');

    switch (event.type) {
      case TimelineEventType.pomodoroStart:
        if (isHomework) {
          return pick(
              ['开启作业攻坚模式', '开始在题海中远航', '正在消灭今日作业', '笔尖下的专注力', '让作业也变成享受']);
        }
        if (isExam) {
          return pick(
              ['进入考前冲刺状态', '模拟实战，严阵以待', '为了那个目标，出发', '正在构建知识盔甲', '考场如战场，此刻亮剑']);
        }
        if (isReview) {
          return pick(['温故而知新', '梳理凌乱的思想', '搭建知识的脚手架', '让记忆变得更深邃', '正在进行深度总结']);
        }
        if (isReading) {
          return pick(
              ['潜入书香的世界', '跨越时空的对话', '在文字间寻找答案', '静心享受阅读时光', '开启心灵的洗礼']);
        }
        return pick([
          '开启了专注之旅',
          '让世界安静下来',
          '潜入思考的深处',
          '专注于当下的美好',
          '启动高效引擎',
          '此刻，唯有专注',
          '与目标同行',
          '听，是专注的声音',
          '开始雕琢时光',
          '进入心流频道'
        ]);

      case TimelineEventType.pomodoroEnd:
        if (isHomework) {
          return pick([
            '搞定了！离完成又近一步',
            '笔耕不辍，收获满满',
            '又攻克了一道难题',
            '让作业见证你的成长',
            '今日份作业能量注入完毕'
          ]);
        }
        if (isExam) {
          return pick([
            '离梦想的终点更近了',
            '多一分专注，多一分底气',
            '胜算在一点点积攒',
            '你的努力，必有回响',
            '为了那张完美的答卷'
          ]);
        }
        if (isReview) {
          return pick([
            '知识点已经刻入脑海',
            '思想变得更加清晰',
            '又完成了一次查漏补缺',
            '梳理，是为了更好的出发',
            '收获了成长的复利'
          ]);
        }
        if (isReading) {
          return pick(
              ['收获了文字的芬芳', '拓宽了生命的维度', '与作者共鸣的瞬间', '知识的种子正在发芽', '精神世界又丰盈了一些']);
        }
        return pick([
          '收获了专注的果实',
          '完成了一次深呼吸',
          '时光不负苦心人',
          '专注画上圆满句号',
          '又一次战胜了分心',
          '内心的充盈感',
          '让努力被看见',
          '合上专注的篇章',
          '达成一次深度连接',
          '汗水凝结成光'
        ]);

      case TimelineEventType.todoCreated:
        return pick([
          '播种了一个新希望',
          '建立了奋斗的目标',
          '写下未来的约定',
          '开启新任务的挑战',
          '清单上的新成员',
          '勾勒成长的蓝图',
          '给未来一个交代',
          '新的旅程由此开始',
          '记录下这一刻的灵感',
          '待办项+1'
        ]);

      case TimelineEventType.todoCompleted:
        if (isHomework) {
          return pick([
            '彻底消灭了这项作业',
            '作业清单-1，快乐值+1',
            '笔尖圆满收官',
            '让成就感在纸面跳跃',
            '搞定，今晚可以睡个好觉'
          ]);
        }
        if (isExam) {
          return pick(
              ['这是一次漂亮的突围', '又翻过了一座大山', '离证书/高分又近了', '为这场博弈画上句号', '你是自己的冠军']);
        }
        return pick([
          '达成了一个小目标',
          '划掉了一个烦恼',
          '离梦想又近了一步',
          '又一个目标被征服',
          '完美的句点',
          '成就感满满',
          '坚持终有回响',
          '实力证明了自己',
          '完成，是最好的奖励',
          '给努力一个回馈'
        ]);

      case TimelineEventType.courseStart:
        return pick([
          '步入知识的殿堂',
          '与智慧有个约会',
          '课堂，是成长的阶梯',
          '吸收新知识的养分',
          '聆听思想的碰撞',
          '在学海中起航',
          '开启学术模式',
          '知识点正在加载',
          '拓宽认知的边界',
          '在课堂遇见更好的自己'
        ]);
      case TimelineEventType.searchQuery:
        return '探索：${event.subtitle}';
      default:
        return event.title;
    }
  }

  String _getReflectionText() {
    final int seed = _selectedDate.day +
        _selectedDate.month +
        _selectedDate.year +
        _dimension.index;
    String pick(List<String> options) => options[seed % options.length];

    if (_totalFocusMinutes == 0) {
      return pick([
        "有时候，静谧的休息也是一种力量。\n在无声的岁月里，\n愿你正温柔地积蓄着光芒。",
        "暂时的停歇，是为了跳得更高。\n给自己一点温柔，\n明天又是全新的开始。",
        "今天的留白，是为了画出更美的未来。\n好好休息，也是一种自律。",
        "允许自己偶尔的‘无所事事’，\n在忙碌的世界里，\n找回那份宁静的初衷。",
        "晚风微凉，生活很长。\n愿你今晚有个好梦，\n积攒满格的勇气。",
        "不去追赶时间，让时间来拥抱你。\n今天的寂静，是成长的呼吸。",
        "慢下来，听听内心的声音。\n不焦虑，不盲从，\n在节奏中寻找平衡。",
        "生活不只有冲刺，还有漫步。\n愿你在休息中，\n发现平凡日子里的光。",
        "累了就停下，这并不代表放弃。\n在独处的时光里，\n你是自由且完整的。",
        "收起行囊，在港湾里泊靠。\n愿明日的阳光，\n能照进你充满力量的梦。"
      ]);
    }

    if (_dimension == TimelineDimension.daily) {
      return pick([
        "专注的灵魂最动人，\n你与目标同行的身影，\n是今日最美的风景。",
        "哪怕只是微小的进步，\n也值得被温柔以待。\n每一分钟的努力，\n都在折射未来的光。",
        "今日的汗水，\n会化作明日的星辰。\n感谢你如此坚定地走在路上。",
        "世界喧嚣，你自清欢。\n在这一份专注里，\n你找到了自己的宇宙。",
        "每一个番茄钟的滴答声，\n都是梦想在敲门。\n你离未来，又近了一些。",
        "你是时间的雕刻师，\n用专注打磨着平凡的日常。\n今日的收获，沉甸甸且珍贵。",
        "不积跬步，无以至千里。\n你走的每一步，\n都有其不可替代的意义。",
        "愿这一份充实，\n能化作今晚香甜的睡眠。\n你值得所有的赞美。",
        "在这段旅程中，\n你既是行者，也是光。\n照亮了属于自己的坚持。",
        "完成比完美更重要，\n而你今天做得如此出色。\n请继续保持这份热爱。"
      ]);
    }

    return pick([
      "这一阶段的奔波与坚持，\n终将汇成成长的河流。\n感谢那个从不轻言放弃的自己。",
      "月盈月亏，岁月流转，\n你的足迹清晰而坚定。\n愿接下来的日子，能遇见更好的风景。",
      "年岁序展，光阴如梭，\n这一段的努力，\n已写就最动人的篇章。",
      "回头望去，那是你亲手耕耘出的绿洲。\n在这段时间里，\n你证明了自己的韧性。",
      "每一次攀登都值得铭记，\n每一个高度都是新的起点。\n愿你心怀热望，步履不停。",
      "时光不会遗忘每一滴汗水，\n空间会记住每一次专注。\n这一份总结，是你最好的勋章。",
      "在变幻的世界里，\n守住了一份不变的坚持。\n你比想象中更加强大。",
      "愿这段时间的沉淀，\n能化作你厚积薄发的底气。\n未来已来，不惧挑战。",
      "每一次总结，都是为了更好的出发。\n整理好心情，\n去迎接下一场山海。",
      "你的努力，藏在每一个被勾掉的待办里。\n它们聚沙成塔，\n终将铸就你的不凡。"
    ]);
  }

  String _getMotivationText() {
    final int seed =
        _selectedDate.day + _selectedDate.month + _selectedDate.year;
    String pick(List<String> options) => options[seed % options.length];

    return pick([
      "专注当下，便是对未来最好的期许。",
      "点滴积累，终将汇成璀璨星河。",
      "坚持的每一天，都在定义全新的你。",
      "岁月的厚重，藏在每一个奋斗的瞬间。",
      "不焦虑未来，不沉溺过去，只深耕现在。",
      "每一个伟大的成就，都源于一次小小的专注。",
      "向着光生长，哪怕缓慢，也要坚定。",
      "愿你心如明镜，在专注中见众生，见自己。",
      "时间对每个人都是公平的，专注让它更有价值。",
      "既然选择了远方，便只顾风雨兼程。",
      "在这一秒，做最好的自己。",
      "平凡的日常里，也藏着不凡的英雄梦想。"
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, double>> data;
  final List<Color> palette;

  _DonutPainter(this.data, this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = radius * 0.35;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double startAngle = -3.14159 / 2;
    for (int i = 0; i < data.length; i++) {
      final sweepAngle = data[i].value * 2 * 3.14159;
      paint.color = palette[i % palette.length];

      // Draw arc with slight gap
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle + 0.05,
        sweepAngle - 0.1,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final double maxVal = data.reduce((a, b) => a > b ? a : b);
    final double minVal = data.reduce((a, b) => a < b ? a : b);
    final double range = (maxVal - minVal).clamp(1.0, double.infinity);

    final double stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - ((data[i] - minVal) / range * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
