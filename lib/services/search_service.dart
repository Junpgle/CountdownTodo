import 'package:flutter/material.dart';

import '../models.dart';
import '../models/todo_create_save_result.dart';
import '../models/search_scope.dart';
import '../screens/about_screen.dart';
import '../screens/team_management_screen.dart';
import '../screens/team_announcement_screen.dart';
import '../screens/team_message_center_screen.dart';
import '../storage_service.dart';
import 'todo_editor_save_service.dart';
import 'database_helper.dart';
import 'api_service.dart';
import 'pomodoro_service.dart';

import 'package:intl/intl.dart';

import '../screens/home_settings_screen.dart';
import '../utils/page_transitions.dart';
import '../widgets/todo_section_widget.dart';

import '../screens/pomodoro_screen.dart';
import '../screens/time_log_screen.dart';
import 'course_service.dart';
import 'global_search_extra_service.dart';
import '../screens/screen_time_detail_screen.dart';
import '../screens/course_screens.dart';
import '../screens/login_screen.dart';
import '../screens/search_record_detail_screen.dart';
import '../screens/add_todo_screen.dart';
import '../screens/fixed_schedule_editor_screen.dart';
import '../screens/folder_manage_screen.dart';
import '../screens/todo_plan_screen.dart';
import '../screens/help/feature_explorer_screen.dart';
import '../screens/historical_todos_screen.dart';
import '../screens/ai_assistant_tutorial_screen.dart';
import '../screens/conflict_inbox_screen.dart';
import '../screens/math_menu_screen.dart';
import '../utils/calendar_date_math.dart';
import '../features/finance/models/finance_models.dart';
import '../features/finance/screens/finance_transaction_detail_screen.dart';
import '../features/finance/screens/finance_loan_screen.dart';
import '../features/finance/screens/finance_budget_entry_screen.dart';
import '../features/finance/screens/finance_home_screen.dart';
import '../features/journal/models/journal_entry.dart';
import '../features/journal/screens/journal_detail_screen.dart';
import '../features/journal/screens/journal_home_screen.dart';
import '../screens/personal_timeline_screen.dart';
import '../features/habits/models/habit_goal.dart';
import '../features/habits/repositories/habit_repository.dart';
import '../features/habits/screens/habit_detail_screen.dart';
import '../features/habits/screens/habit_center_screen.dart';
import '../features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import '../features/thirty_day_challenge/screens/challenge_center_screen.dart';
import 'app_settings_catalog.dart';
import '../utils/ai_settings_navigation.dart';
import '../utils/app_dialogs.dart';

part 'search_service_database.dart';
part 'search_service_navigation.dart';

final RegExp _searchTermSeparatorPattern = RegExp(r'[\s,，;；]+');
final RegExp _fullSearchDatePattern = RegExp(
  r'^(\d{4})[./\-/年](\d{1,2})[./\-/月](\d{1,2})[日号]?$',
);
final RegExp _shortSearchDatePattern = RegExp(
  r'^(\d{1,2})[./\-/月](\d{1,2})[日号]?$',
);
final Map<(String?, String), DateFormat> _searchDateFormats = {};

DateFormat _searchDateFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _searchDateFormats.putIfAbsent((
    locale,
    pattern,
  ), () => DateFormat(pattern, locale));
}

class SearchResultWithScore {
  final SearchResult result;
  final int score;
  SearchResultWithScore(this.result, this.score);
}

class _IndexedStaticSearchResult {
  _IndexedStaticSearchResult(this.result)
    : title = result.title.toLowerCase(),
      subtitle = result.subtitle?.toLowerCase(),
      breadcrumb = result.breadcrumb?.toLowerCase();

  final SearchResult result;
  final String title;
  final String? subtitle;
  final String? breadcrumb;
}

class SearchService {
  static final SearchService instance = SearchService._();
  SearchService._();

  static List<TodoItem> _filterOverdueTodos({
    required List<TodoItem> todos,
    required Set<String> excludedRecurrenceSeriesIds,
    required DateTime before,
  }) {
    return todos
        .where(
          (item) =>
              !item.isDeleted &&
              !item.isDone &&
              !item.isSkipped &&
              item.isOverdueAt(before) &&
              !excludedRecurrenceSeriesIds.contains(item.recurrenceSeriesId),
        )
        .toList();
  }

  Future<void>? _warmupFuture;
  String? _preparedTimeLogsUsername;
  Future<void>? _timeLogsReadyFuture;

  Future<void> warmup() {
    return _warmupFuture ??= _runWarmup();
  }

  Future<void> _runWarmup() async {
    try {
      await Future.wait<void>([
        DatabaseHelper.instance.warmSearchIndex(),
        _prepareTimeLogs(),
      ]);
    } catch (error) {
      _warmupFuture = null;
      debugPrint('Search warmup failed: $error');
    }
  }

  Future<void> _prepareTimeLogs() async {
    final username = await StorageService.getLoginSession() ?? 'default';
    if (_preparedTimeLogsUsername == username && _timeLogsReadyFuture != null) {
      return _timeLogsReadyFuture!;
    }
    _preparedTimeLogsUsername = username;
    return _timeLogsReadyFuture = StorageService.getTimeLogs(
      username,
      limit: 1,
    ).then<void>((_) {});
  }

  // The platform-specific settings directory and feature entries are stable
  // for the lifetime of the app, so build their search results once.
  static final List<_IndexedStaticSearchResult> _staticSettings = [
    for (final item in AppSettingsCatalog.available)
      _IndexedStaticSearchResult(
        SearchResult(
          id: 'setting_${item.id}',
          title: item.title,
          subtitle: item.description,
          icon: Icons.settings_outlined,
          type: SearchResultType.setting,
          breadcrumb: item.path,
          extraData: {'route': '/settings', 'target': item.id},
        ),
      ),
    ..._staticEntries.map(_IndexedStaticSearchResult.new),
  ];

  static final List<SearchResult> _staticEntries = [
    SearchResult(
      id: 'setting_login',
      title: '账户登录 / 注册',
      subtitle: '管理 Uni-Sync 云同步账号',
      icon: Icons.account_circle,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 账号',
      extraData: {'route': '/login'},
    ),
    SearchResult(
      id: 'setting_team_management',
      title: '团队协作 / 创建团队 / 加入团队',
      subtitle: '管理您的所有协作团队',
      icon: Icons.groups,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 团队',
      extraData: {'route': '/teams'},
    ),
    SearchResult(
      id: 'setting_team_announcement',
      title: '团队公告 / 公告列表',
      subtitle: '查看您所在团队发布的最新消息',
      icon: Icons.campaign,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 团队',
      extraData: {'route': '/teams', 'target': 'announcements'},
    ),
    SearchResult(
      id: 'setting_team_messages',
      title: '团队消息中心 / 消息通知',
      subtitle: '管理入队申请与系统通知',
      icon: Icons.message,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 团队',
      extraData: {'route': '/teams', 'target': 'messages'},
    ),
    SearchResult(
      id: 'setting_team_members',
      title: '团队成员 / 成员管理 / 踢人 / 权限',
      subtitle: '查看或管理团队内的合作伙伴',
      icon: Icons.manage_accounts,
      type: SearchResultType.setting,
      breadcrumb: '设置 > 团队',
      extraData: {'route': '/teams', 'target': 'members'},
    ),
    // 业务入口：即使用户还没有创建具体数据，也可以通过搜索打开模块。
    SearchResult(
      id: 'feature_habit_center',
      title: '习惯中心 / 习惯追踪 / 习惯打卡',
      subtitle: '记录习惯、查看连续记录和完成趋势',
      icon: Icons.track_changes_rounded,
      type: SearchResultType.habit,
      extraData: {'route': '/habits'},
    ),
    SearchResult(
      id: 'feature_challenge_center',
      title: '挑战中心 / 自定义挑战 / 30天找到全新自我',
      subtitle: '探索、创建、记录和分享自己的挑战',
      icon: Icons.auto_awesome_rounded,
      type: SearchResultType.challenge,
      extraData: {'route': '/challenge'},
    ),
    SearchResult(
      id: 'feature_finance',
      title: '个人记账 / 账单 / 预算',
      subtitle: '查看账单、分类、预算与借款',
      icon: Icons.receipt_long_rounded,
      type: SearchResultType.finance,
      extraData: {'route': '/finance'},
    ),
    SearchResult(
      id: 'feature_journal',
      title: '私密日记 / 日记本',
      subtitle: '查看本机保存的日记',
      icon: Icons.auto_stories_outlined,
      type: SearchResultType.journal,
      extraData: {'route': '/journal'},
    ),
    SearchResult(
      id: 'feature_fixed_schedule',
      title: '固定日程 / 日程安排',
      subtitle: '查看课程与固定日程',
      icon: Icons.event_available_outlined,
      type: SearchResultType.fixedSchedule,
      extraData: {'route': '/course/weekly'},
    ),
    SearchResult(
      id: 'feature_plan_blocks',
      title: '待办规划块 / 今日计划',
      subtitle: '查看已安排的执行时段',
      icon: Icons.view_timeline_outlined,
      type: SearchResultType.planBlock,
      extraData: {'route': '/plan'},
    ),
    // 🚀 业务模块直达
    SearchResult(
      id: 'feature_pomodoro_stats',
      title: '番茄钟统计 / 专注统计 / 效率分析',
      subtitle: '查看每日、每周的专注时长分布',
      icon: Icons.bar_chart,
      type: SearchResultType.log,
      extraData: {'route': '/pomodoro/stats'},
    ),
    SearchResult(
      id: 'feature_time_log_manual',
      title: '时间日志补录 / 手动补录时间',
      subtitle: '手动补录错过的专注或学习时段',
      icon: Icons.more_time,
      type: SearchResultType.log,
      extraData: {'route': '/time_log/manual'},
    ),
    SearchResult(
      id: 'feature_explorer_hub',
      title: '功能探索百宝箱 / 功能大全 / 隐藏技巧 / 新手教程',
      subtitle: '一图总览所有功能位置、30秒快速上手与版本更新亮点',
      icon: Icons.explore_rounded,
      type: SearchResultType.action,
      extraData: {'route': '/feature_explorer'},
    ),
    SearchResult(
      id: 'feature_historical_todos',
      title: '历史待办 / 回收站 / 误删恢复 / 已完成归档',
      subtitle: '查看已完成的待办或从回收站批量恢复误删任务',
      icon: Icons.restore_from_trash_rounded,
      type: SearchResultType.todo,
      extraData: {'route': '/historical_todos'},
    ),
    SearchResult(
      id: 'feature_ai_tutorial',
      title: 'AI 助手教程 / 语音速记 / 截图识图 / 取件码识别',
      subtitle: '了解如何按住 + 号说话速记、从相册分享截图识别待办与账单',
      icon: Icons.smart_toy_outlined,
      type: SearchResultType.chat,
      extraData: {'route': '/ai_tutorial'},
    ),
    SearchResult(
      id: 'feature_conflict_inbox',
      title: '冲突收件箱 / 同步冲突处理 / 时间重叠检测',
      subtitle: '查看并解决多设备同步冲突或日程时间重叠',
      icon: Icons.sync_problem_rounded,
      type: SearchResultType.action,
      extraData: {'route': '/conflicts'},
    ),
    SearchResult(
      id: 'feature_math_quiz',
      title: '数学测验 / 心算口算 / 专注唤醒',
      subtitle: '开始专注前用快速四则运算激活大脑状态',
      icon: Icons.functions_rounded,
      type: SearchResultType.action,
      extraData: {'route': '/math_quiz'},
    ),
  ];

  /// Searches the same indexed setting entries used by global search without
  /// querying user data or recording a search-history item.
  List<SearchResult> searchSettings(String query) {
    final searchTerms = _extractSearchTerms(query.trim().toLowerCase());
    if (searchTerms.isEmpty) return const <SearchResult>[];

    final matches =
        _searchIndexedStaticResults(searchTerms, SearchScope.settings)
            .where((match) => match.result.type == SearchResultType.setting)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return matches.map((match) => match.result).toList(growable: false);
  }

  List<SearchResultWithScore> _searchIndexedStaticResults(
    List<String> searchTerms,
    SearchScope scope,
  ) {
    final matches = <SearchResultWithScore>[];
    for (final indexed in _staticSettings) {
      final result = indexed.result;
      if (!scope.includes(result.type)) continue;

      final score = _calculateScore(
        indexed.title,
        indexed.subtitle,
        indexed.breadcrumb,
        searchTerms,
      );
      if (score > 0) {
        matches.add(SearchResultWithScore(result, score));
      }
    }
    return matches;
  }

  Future<List<SearchResult>> search(
    String query, {
    SearchScope scope = SearchScope.all,
    bool recordHistory = true,
    SearchSourceObserver? onSourceQueried,
    bool Function()? shouldContinue,
  }) async {
    if (shouldContinue?.call() == false) return const <SearchResult>[];
    if (query.trim().isEmpty) {
      return scope == SearchScope.all
          ? await guessSearch(shouldContinue: shouldContinue)
          : [];
    }
    final q = query.toLowerCase().trim();
    final searchNow = DateTime.now();
    final targetDate = _parseDateQuery(q, now: searchNow);

    // 🚀 异步记录搜索历史
    if (recordHistory) {
      DatabaseHelper.instance
          .insertSearchHistory(q)
          .catchError((e) => debugPrint("Record search history error: $e"));
    }

    final searchTerms = _extractSearchTerms(q);
    final usernameFuture = StorageService.getLoginSession();
    final scoredResults = <SearchResultWithScore>[];
    final featureSearch =
        scope.includesAny(const [
          SearchResultType.habit,
          SearchResultType.challenge,
        ])
        ? _searchHabitsAndChallenges(
            searchTerms,
            scope,
            onSourceQueried,
            shouldContinue: shouldContinue,
          ).catchError((_) => <SearchResult>[])
        : Future.value(<SearchResult>[]);
    final databaseSearch =
        scope.includesAny(const [
          SearchResultType.todo,
          SearchResultType.todoGroup,
          SearchResultType.course,
          SearchResultType.countdown,
          SearchResultType.log,
          SearchResultType.tag,
          SearchResultType.app,
        ])
        ? _searchDatabase(
            q,
            searchTerms,
            scope,
            onSourceQueried,
            usernameFuture: usernameFuture,
            targetDate: targetDate,
            now: searchNow,
            shouldContinue: shouldContinue,
          ).catchError((_) => <SearchResult>[])
        : Future.value(<SearchResult>[]);
    final Future<List<SearchResult>> extraSearch = usernameFuture
        .then<List<SearchResult>>((username) {
          if (shouldContinue?.call() == false) return <SearchResult>[];
          return GlobalSearchExtraService.search(
            username ?? 'default',
            searchTerms,
            targetDate: targetDate,
            scope: scope,
            onSourceQueried: onSourceQueried,
            shouldContinue: shouldContinue,
          ).catchError((_) => <SearchResult>[]);
        });

    // 1. 静态索引扫描，共享设置页的目录搜索和相关度评分。
    scoredResults.addAll(_searchIndexedStaticResults(searchTerms, scope));

    // 2. 习惯、挑战与数据库查询互不依赖，并行执行以缩短输入后的等待。
    final searchResults = await Future.wait<List<SearchResult>>([
      featureSearch,
      databaseSearch,
      extraSearch,
    ]);
    if (shouldContinue?.call() == false) return const <SearchResult>[];

    for (final item in searchResults[0]) {
      final score = _calculateScore(
        item.title.toLowerCase(),
        item.subtitle?.toLowerCase(),
        null,
        searchTerms,
      );
      if (score > 0) {
        scoredResults.add(SearchResultWithScore(item, score + 8));
      }
    }

    // 3. 数据库扫描
    // 🚀 修复：DB 查询结果已经由 SQL LIKE/FTS 确认与 query 相关，
    // 不能再用 _calculateScore 二次过滤（否则备注匹配但不在 subtitle 里的条目会被丢弃）。
    // 用 score+10 保证 DB 结果优先展示，同时仍按标题相关度排序。
    for (final item in searchResults[1]) {
      final score = _calculateScore(
        item.title.toLowerCase(),
        item.subtitle?.toLowerCase(),
        null,
        searchTerms,
      );
      // DB 已过滤，保底给 score=1，避免备注命中却被丢弃
      scoredResults.add(
        SearchResultWithScore(item, (score > 0 ? score : 1) + 10),
      );
    }

    for (final item in searchResults[2]) {
      final score = _calculateScore(
        item.title.toLowerCase(),
        item.subtitle?.toLowerCase(),
        null,
        searchTerms,
      );
      scoredResults.add(
        SearchResultWithScore(item, (score > 0 ? score : 1) + 10),
      );
    }

    scoredResults.sort((a, b) => b.score.compareTo(a.score));

    // 5. 强制去重：根据 ID 过滤重复项（防止数据库中存在冗余数据导致展示混乱）
    final seenIds = <String>{};
    final finalResults = <SearchResult>[];
    for (final sr in scoredResults) {
      if (seenIds.add(sr.result.id)) finalResults.add(sr.result);
    }

    // 6. 动态动作注入
    if (scope.includes(SearchResultType.action) &&
        (q.contains('新') || q.contains('加'))) {
      finalResults.insert(
        0,
        SearchResult(
          id: 'action_new_todo',
          title: '快速新建待办',
          subtitle: '点击立即创建新任务',
          icon: Icons.add_task,
          type: SearchResultType.action,
          extraData: {'action': 'new_todo'},
        ),
      );
    }

    return finalResults;
  }

  List<String> _extractSearchTerms(String query) {
    return query
        .split(_searchTermSeparatorPattern)
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool _matchesAllTerms(String text, List<String> terms) {
    final lower = text.toLowerCase();
    for (final term in terms) {
      if (!lower.contains(term)) return false;
    }
    return true;
  }

  DateTime? _parseDateQuery(String query, {DateTime? now}) {
    final current = now ?? DateTime.now();
    switch (query) {
      case '今天':
      case '今日':
      case '今':
      case 'today':
        return current;
      case '昨天':
      case '昨日':
      case 'yesterday':
        return AppTimeFormats.localDayStartOffset(current, -1);
      case '前天':
        return AppTimeFormats.localDayStartOffset(current, -2);
      case '大前天':
        return AppTimeFormats.localDayStartOffset(current, -3);
      case '明天':
      case '明日':
      case 'tomorrow':
        return AppTimeFormats.localDayStartOffset(current, 1);
      case '后天':
        return AppTimeFormats.localDayStartOffset(current, 2);
      case '大后天':
        return AppTimeFormats.localDayStartOffset(current, 3);
    }
    final full = _fullSearchDatePattern.firstMatch(query);
    final short = _shortSearchDatePattern.firstMatch(query);
    final year = full == null
        ? current.year
        : int.tryParse(full.group(1)!) ?? 0;
    final month =
        int.tryParse((full ?? short)?.group(full == null ? 1 : 2) ?? '') ?? 0;
    final day =
        int.tryParse((full ?? short)?.group(full == null ? 2 : 3) ?? '') ?? 0;
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day
        ? parsed
        : null;
  }

  @visibleForTesting
  DateTime? parseDateQueryForTest(String query, {required DateTime now}) =>
      _parseDateQuery(query, now: now);

  @visibleForTesting
  static ({DateTime start, DateTime end}) dateRangeForSearch(DateTime date) {
    final start = AppTimeFormats.dayStart(date);
    return (start: start, end: AppTimeFormats.localDayStartOffset(start, 1));
  }

  int _calculateScore(
    String title,
    String? subtitle,
    String? breadcrumb,
    List<String> terms,
  ) {
    if (terms.isEmpty) return 0;
    if (terms.length == 1) {
      final term = terms.first;
      if (title == term) return 100;
      if (title.startsWith(term)) return 80;
      if (title.contains(term)) return 50;
      if (subtitle?.contains(term) ?? false) return 20;
      if (breadcrumb?.contains(term) ?? false) return 10;
      return 0;
    }

    var score = 0;
    for (final term in terms) {
      final matchesTitle = title.contains(term);
      final matchesSubtitle = subtitle?.contains(term) ?? false;
      final matchesBreadcrumb = breadcrumb?.contains(term) ?? false;
      if (!matchesTitle && !matchesSubtitle && !matchesBreadcrumb) return 0;

      if (title == term) {
        score += 100;
      } else if (title.startsWith(term)) {
        score += 80;
      } else if (title.contains(term)) {
        score += 50;
      } else if (subtitle?.contains(term) ?? false) {
        score += 20;
      } else if (breadcrumb?.contains(term) ?? false) {
        score += 10;
      } else {
        score += 5;
      }
    }
    return score + terms.length * 10;
  }
}
