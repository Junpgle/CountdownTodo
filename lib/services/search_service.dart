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
  ];

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

    // 1. 静态索引扫描
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
        scoredResults.add(SearchResultWithScore(result, score));
      }
    }

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

  Future<List<SearchResult>> _searchHabitsAndChallenges(
    List<String> searchTerms,
    SearchScope scope,
    SearchSourceObserver? onSourceQueried, {
    bool Function()? shouldContinue,
  }) async {
    final results = <SearchResult>[];

    if (scope.includes(SearchResultType.habit)) {
      if (shouldContinue?.call() == false) return results;
      onSourceQueried?.call('habits');
      try {
        final goals = await HabitRepository.getGoals();
        if (shouldContinue?.call() == false) return results;
        for (final goal in goals) {
          if (goal.isDeleted) continue;
          final sourceLabel = switch (goal.sourceType) {
            HabitSourceType.recurringTodo => '完成型',
            HabitSourceType.pomodoroTag => '专注时长型',
            HabitSourceType.quantityCheckIn => '数量型',
            HabitSourceType.timeCheckIn => '时间点型',
            HabitSourceType.durationCheckIn => '独立时长型',
          };
          final searchable =
              '${goal.name} 习惯 $sourceLabel'
              '${goal.isArchived ? ' 已归档 归档习惯' : ''}';
          if (!_matchesAllTerms(searchable, searchTerms)) continue;

          results.add(
            SearchResult(
              id: 'db_habit_${goal.uuid}',
              title: goal.name.isEmpty ? '未命名习惯' : goal.name,
              subtitle: '习惯 · $sourceLabel${goal.isArchived ? ' · 已归档' : ''}',
              icon: Icons.track_changes_rounded,
              type: SearchResultType.habit,
              extraData: {'route': '/habits', 'habit_uuid': goal.uuid},
            ),
          );
        }
      } catch (_) {}
    }

    if (scope.includes(SearchResultType.challenge)) {
      if (shouldContinue?.call() == false) return results;
      onSourceQueried?.call('challenges');
      try {
        // 未开始挑战时，静态“挑战中心”入口已经足够；避免每次输入关键词
        // 都为用户创建一份默认挑战状态。
        if (!await ThirtyDayChallengeRepository.hasStarted()) return results;
        if (shouldContinue?.call() == false) return results;
        final state = await ThirtyDayChallengeRepository.load();
        if (shouldContinue?.call() == false) return results;
        final taskTitles = state.tasks.map((task) => task.title).toList();
        final searchable = [
          state.challengeTitle,
          '挑战',
          '挑战中心',
          '30天',
          ...taskTitles,
        ].join(' ');

        if (_matchesAllTerms(searchable, searchTerms)) {
          final matchedTasks = state.tasks
              .where((task) {
                final title = task.title.toLowerCase();
                return searchTerms.any((term) => title.contains(term));
              })
              .take(2)
              .map((task) => task.title)
              .join('、');
          final progress = '${state.completedCount}/${state.tasks.length} 项已完成';
          results.add(
            SearchResult(
              id: 'db_challenge_current',
              title: state.challengeTitle,
              subtitle: matchedTasks.isEmpty
                  ? '挑战 · $progress'
                  : '挑战 · $progress · 相关任务：$matchedTasks',
              icon: Icons.auto_awesome_rounded,
              type: SearchResultType.challenge,
              extraData: {'route': '/challenge'},
            ),
          );
        }
      } catch (_) {}
    }

    return results;
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

  Future<List<SearchResult>> _searchDatabase(
    String query,
    List<String> searchTerms,
    SearchScope scope,
    SearchSourceObserver? onSourceQueried, {
    required Future<String?> usernameFuture,
    required DateTime? targetDate,
    required DateTime now,
    bool Function()? shouldContinue,
  }) async {
    final dbItems = <SearchResult>[];
    if (shouldContinue?.call() == false) return dbItems;
    final db = DatabaseHelper.instance;
    final username = await usernameFuture ?? 'default';
    if (shouldContinue?.call() == false) return dbItems;
    final q = query.toLowerCase().trim();

    final isDateQuery = targetDate != null;
    final dateRange = targetDate == null
        ? null
        : dateRangeForSearch(targetDate);
    final startOfDay = dateRange?.start;
    final endOfDay = dateRange?.end;
    final targetDateValue = targetDate;
    final isTodayQuery =
        isDateQuery &&
        targetDateValue != null &&
        targetDateValue.year == now.year &&
        targetDateValue.month == now.month &&
        targetDateValue.day == now.day;
    final dateQueryHint = isDateQuery && startOfDay != null
        ? '搜索到${_searchDateFormat('yyyy年M月d日').format(startOfDay)}的结果'
        : null;

    if (scope.includes(SearchResultType.todo)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('todos');
      // ── 待办事项 ──────────────────────────────────────────────────────────
      List<Map<String, dynamic>> todos = [];
      try {
        if (isDateQuery) {
          // Keep recurrence behavior on a cold cache, then use indexed date
          // columns once recurrence instances have already been materialized.
          final matchedTodos = await StorageService.getTodosForSearchDateRange(
            username,
            from: startOfDay!,
            to: endOfDay!,
          );
          if (shouldContinue?.call() == false) return dbItems;
          todos = matchedTodos
              .map(
                (t) => {
                  'uuid': t.id,
                  'content': t.title,
                  'is_completed': t.isDone ? 1 : 0,
                  'is_skipped': t.isSkipped ? 1 : 0,
                  'is_deleted': 0,
                  'due_date': t.dueDate?.millisecondsSinceEpoch,
                  'created_date': t.createdDate,
                  'team_name': t.teamName,
                  'remark': t.remark,
                },
              )
              .toList();
        } else {
          final candidates = await db.searchTodosByTerms(searchTerms);
          if (shouldContinue?.call() == false) return dbItems;
          todos = candidates.where((t) {
            final content = t['content']?.toString() ?? '';
            final remark = t['remark']?.toString() ?? '';
            final teamName = t['team_name']?.toString() ?? '';
            final haystack = '$content $remark $teamName';
            return _matchesAllTerms(haystack, searchTerms);
          }).toList();
        }
      } catch (e) {
        // debugPrint('Todo search error: $e');
      }

      final todoDateFormat = _searchDateFormat('MM/dd');
      for (var t in todos) {
        // 构建副标题：备注（优先）+ 截止时间 + 归属团队
        // 🚀 修复：备注始终显示在副标题第一行，而非仅作兜底
        final metaParts = <String>[];
        final dueDateMs = t['due_date'];
        if (dueDateMs != null && dueDateMs != 0) {
          final dueDate = DateTime.fromMillisecondsSinceEpoch(
            dueDateMs is int
                ? dueDateMs
                : int.tryParse(dueDateMs.toString()) ?? 0,
          );
          metaParts.add('截止 ${todoDateFormat.format(dueDate)}');
        }
        final createdDateMs = t['created_date'];
        if (createdDateMs != null && createdDateMs != 0) {
          final createdDate = DateTime.fromMillisecondsSinceEpoch(
            createdDateMs is int
                ? createdDateMs
                : int.tryParse(createdDateMs.toString()) ?? 0,
          );
          metaParts.add('开始 ${todoDateFormat.format(createdDate)}');
        }
        if (t['team_name'] != null && (t['team_name'] as String).isNotEmpty) {
          metaParts.add('团队: ${t['team_name']}');
        }
        final remarkStr = t['remark']?.toString().trim();
        // subtitle = 备注（若有）＋元信息（若有）
        final subtitle = [
          if (remarkStr != null && remarkStr.isNotEmpty) remarkStr,
          if (metaParts.isNotEmpty) metaParts.join(' · '),
        ].join('  |  ');
        final displaySubtitle = subtitle.isNotEmpty ? subtitle : '个人待办';
        final isSkipped = t['is_skipped'] == 1 || t['is_skipped'] == true;
        dbItems.add(
          SearchResult(
            id: 'db_todo_${t['uuid']}',
            title: t['content'] ?? '未命名任务',
            subtitle: displaySubtitle,
            icon: isSkipped
                ? Icons.skip_next_rounded
                : t['is_completed'] == 1
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            type: SearchResultType.todo,
            extraData: {
              'uuid': t['uuid'],
              'table': 'todos',
              'is_completed': t['is_completed'],
              'is_skipped': isSkipped ? 1 : 0,
              'due_date': dueDateMs,
              'team_name': t['team_name'],
              'remark': remarkStr,
              'date_query_hint': ?dateQueryHint,
            },
          ),
        );
      }
    }

    if (scope.includes(SearchResultType.course)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('courses');
      // ── 课程 ─────────────────────────────────────────────────────────────
      try {
        final courseMap = <String, Map<String, dynamic>>{};
        if (isDateQuery) {
          final dateCourses = await CourseService.getCoursesForDateRange(
            username,
            from: startOfDay!,
            to: endOfDay!,
          );
          if (shouldContinue?.call() == false) return dbItems;
          for (final course in dateCourses) {
            courseMap[course.uuid] = {
              'uuid': course.uuid,
              'course_name': course.courseName,
              'teacher_name': course.teacherName,
              'room_name': course.roomName,
              'week_index': course.weekIndex,
              'weekday': course.weekday,
              'start_time': course.startTime,
              'end_time': course.endTime,
              'course_record': course,
            };
          }
        } else {
          final rows = await db.searchCoursesByTerms(searchTerms);
          if (shouldContinue?.call() == false) return dbItems;
          for (final row in rows) {
            courseMap[row['uuid'].toString()] = row;
          }
        }
        final courses = courseMap.values.where((c) {
          if (isDateQuery) return true;
          final courseName = c['course_name']?.toString() ?? '';
          final teacherName = c['teacher_name']?.toString() ?? '';
          final roomName = c['room_name']?.toString() ?? '';
          final haystack = '$courseName $teacherName $roomName';
          return _matchesAllTerms(haystack, searchTerms);
        }).toList();
        for (var c in courses) {
          // 构建时间描述：第几周 + 星期几 + 第几节
          final weekIdx = c['week_index'];
          final weekday = c['weekday'];
          const weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
          final weekdayStr = (weekday != null && weekday >= 1 && weekday <= 7)
              ? weekdayNames[weekday]
              : '';
          final startSlot = c['start_time'];
          final endSlot = c['end_time'];
          final timePart = (startSlot != null && endSlot != null)
              ? '第 $startSlot-$endSlot 节'
              : '';
          final weekPart = weekIdx != null ? '第 $weekIdx 周' : '';
          final subtitle = [
            weekPart,
            weekdayStr,
            timePart,
            c['room_name'] ?? '',
          ].where((s) => s.isNotEmpty).join(' · ');

          dbItems.add(
            SearchResult(
              id: 'db_course_${c['uuid']}',
              title: c['course_name'] ?? '未知课程',
              subtitle: subtitle.isNotEmpty
                  ? subtitle
                  : (c['teacher_name'] ?? '未知教师'),
              icon: Icons.school,
              type: SearchResultType.course,
              extraData: {
                'uuid': c['uuid'],
                'table': 'courses',
                'teacher_name': c['teacher_name'],
                'room_name': c['room_name'],
                'week_index': weekIdx,
                'weekday': weekday,
                if (c['course_record'] != null)
                  'course_record': c['course_record'],
                'date_query_hint': ?dateQueryHint,
              },
            ),
          );
        }
      } catch (e) {
        // debugPrint('Course search error: $e');
      }
    }

    if (scope.includes(SearchResultType.countdown)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('countdowns');
      // ── 倒计时 ────────────────────────────────────────────────────────────
      try {
        final countdownMap = <String, Map<String, dynamic>>{};
        if (isDateQuery) {
          final items = await StorageService.getCountdowns(
            username,
            from: startOfDay!,
            to: endOfDay!,
          );
          if (shouldContinue?.call() == false) return dbItems;
          for (final item in items) {
            if (item.isDeleted) continue;
            countdownMap[item.id] = item.toJson();
          }
        } else {
          final rows = await db.searchCountdownsByTerms(searchTerms);
          if (shouldContinue?.call() == false) return dbItems;
          for (final row in rows) {
            countdownMap[row['uuid'].toString()] = row;
          }
        }
        final countdowns = countdownMap.values.where((cd) {
          if (isDateQuery) return true;
          final title = cd['title']?.toString() ?? '';
          final teamName = cd['team_name']?.toString() ?? '';
          final haystack = '$title $teamName';
          return _matchesAllTerms(haystack, searchTerms);
        }).toList();
        for (var cd in countdowns) {
          String subtitle = '未设置日期';
          final targetMs = cd['target_time'];
          if (targetMs != null) {
            final target = DateTime.fromMillisecondsSinceEpoch(
              targetMs is int
                  ? targetMs
                  : int.tryParse(targetMs.toString()) ?? 0,
            );
            final diff = CalendarDateMath.daysBetween(now, target);
            final dateStr = _searchDateFormat('yyyy/MM/dd').format(target);
            subtitle = diff >= 0
                ? '还有 $diff 天 · $dateStr'
                : '已过 ${-diff} 天 · $dateStr';
          }
          dbItems.add(
            SearchResult(
              id: 'db_countdown_${cd['uuid']}',
              title: cd['title'] ?? '未命名倒计时',
              subtitle: subtitle,
              icon: Icons.timer_outlined,
              type: SearchResultType.countdown,
              extraData: {
                'uuid': cd['uuid'],
                'table': 'countdowns',
                'fields': {
                  '目标日期': targetMs == null ? '' : subtitle,
                  '所属团队': cd['team_name']?.toString() ?? '',
                },
                'detail_label': '倒计时',
                'date_query_hint': ?dateQueryHint,
              },
            ),
          );
        }
      } catch (e) {
        // debugPrint('Countdown search error: $e');
      }
    }

    if (scope.includes(SearchResultType.log)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('timeLogs');
      // ── 时间日志 ──────────────────────────────────────────────────────────
      try {
        // Keep the legacy SharedPreferences-to-SQL migration guarantee while
        // all actual search filtering stays inside SQLite.
        await _prepareTimeLogs();
        if (shouldContinue?.call() == false) return dbItems;
        List<Map<String, dynamic>> matchedLogs;
        if (isDateQuery) {
          matchedLogs = await db.searchTimeLogsByDate(
            startOfDay!.millisecondsSinceEpoch,
            endOfDay!.millisecondsSinceEpoch,
          );
          if (shouldContinue?.call() == false) return dbItems;
        } else {
          final logMap = <String, Map<String, dynamic>>{};
          final rows = await db.searchTimeLogsByTerms(searchTerms);
          if (shouldContinue?.call() == false) return dbItems;
          for (final row in rows) {
            logMap[row['uuid'].toString()] = row;
          }
          matchedLogs = logMap.values.where((log) {
            final rawTitle = log['title'];
            final rawRemark = log['remark'];
            final title = rawTitle is String ? rawTitle : '';
            final remark = rawRemark is String ? rawRemark : '';
            final haystack = '$title $remark';
            return _matchesAllTerms(haystack, searchTerms);
          }).toList();
        }

        final logDateFormat = _searchDateFormat('MM/dd HH:mm');
        for (final log in matchedLogs) {
          final startMs = (log['start_time'] as num?)?.toInt() ?? 0;
          final endMs = (log['end_time'] as num?)?.toInt() ?? startMs;
          final start = DateTime.fromMillisecondsSinceEpoch(startMs);
          final end = DateTime.fromMillisecondsSinceEpoch(endMs);
          final mins = end.difference(start).inMinutes;
          final title = log['title']?.toString() ?? '';
          final remark = log['remark']?.toString();
          dbItems.add(
            SearchResult(
              id: 'db_log_${log['uuid']}',
              title: title.isNotEmpty ? title : '未命名专注',
              subtitle:
                  '$mins 分钟 · ${logDateFormat.format(start)}'
                  '${remark?.isNotEmpty == true ? ' · $remark' : ''}',
              icon: Icons.history_edu_rounded,
              type: SearchResultType.log,
              extraData: {
                'uuid': log['uuid'],
                'table': 'time_logs',
                'date_query_hint': ?dateQueryHint,
              },
            ),
          );
        }
      } catch (e) {
        // debugPrint('Time log search error: $e');
      }
    }

    if (scope.includes(SearchResultType.tag)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('tags');
      // ── 时间日志标签 ─────────────────────────────────────────────────────
      // 搜索标签名，点击可跳转到该标签的折线图统计界面
      try {
        final allTags = await PomodoroService.getTags();
        if (shouldContinue?.call() == false) return dbItems;
        final matchedTags = allTags.where(
          (t) => _matchesAllTerms(t.name, searchTerms),
        );
        for (var tag in matchedTags) {
          dbItems.add(
            SearchResult(
              id: 'db_tag_${tag.uuid}',
              title: tag.name,
              subtitle: '专注标签 · 点击查看折线图统计',
              icon: Icons.label_rounded,
              type: SearchResultType.tag,
              extraData: {
                'tag_uuid': tag.uuid,
                'tag_name': tag.name,
                'tag_color': tag.color,
                'route': '/time_log/tag',
              },
            ),
          );
        }
      } catch (e) {
        // debugPrint('Tag search error: $e');
      }
    }

    if (scope.includes(SearchResultType.app)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('screenTime');
      // ── 屏幕使用时间 (App 搜索) ─────────────────────────────────────────
      // 日期查询时：直接展示目标日期的聚合屏幕时间；普通关键词查询时：按应用名匹配历史缓存。
      if (isDateQuery) {
        try {
          final seenApps = <String>{};

          void addScreenTimeApps(
            List<dynamic> stats, {
            required bool includeAll,
          }) {
            for (var item in stats) {
              if (item is! Map) continue;
              final appName = item['app_name']?.toString().trim() ?? '';
              if (appName.isEmpty) continue;

              final normalized = appName.toLowerCase();
              if (seenApps.contains(normalized)) continue;

              final matchesQuery =
                  includeAll || _matchesAllTerms(appName, searchTerms);
              if (!matchesQuery) continue;

              seenApps.add(normalized);
              final subtitle = '屏幕使用时间 · 点击查看应用详情';

              dbItems.add(
                SearchResult(
                  id: 'db_app_$normalized',
                  title: appName,
                  subtitle: subtitle,
                  icon: Icons.smartphone_rounded,
                  type: SearchResultType.app,
                  extraData: {
                    'app_name': appName,
                    'route': '/screen_time/app',
                    'search_date_ms': startOfDay!.millisecondsSinceEpoch,
                    'date_query_hint': ?dateQueryHint,
                  },
                ),
              );
            }
          }

          final history = await StorageService.getScreenTimeHistory();
          if (shouldContinue?.call() == false) return dbItems;
          final targetDateKey = _searchDateFormat('yyyy-MM-dd')
              .format(startOfDay!);
          final targetDayStats = history[targetDateKey];

          if (targetDayStats != null && targetDayStats.isNotEmpty) {
            addScreenTimeApps(targetDayStats, includeAll: true);
          } else if (isTodayQuery) {
            final screenTimeCache = await StorageService.getScreenTimeCache();
            if (shouldContinue?.call() == false) return dbItems;
            if (screenTimeCache.isNotEmpty) {
              addScreenTimeApps(screenTimeCache, includeAll: true);
            }
          }
        } catch (e) {
          // debugPrint('Screen time search error: $e');
        }
      } else {
        try {
          final seenApps = <String>{};

          void addScreenTimeApps(List<dynamic> stats) {
            for (var item in stats) {
              if (item is! Map) continue;
              final appName = item['app_name']?.toString().trim() ?? '';
              if (appName.isEmpty) continue;

              final normalized = appName.toLowerCase();
              if (seenApps.contains(normalized)) continue;
              if (!normalized.contains(q)) continue;

              seenApps.add(normalized);
              dbItems.add(
                SearchResult(
                  id: 'db_app_$normalized',
                  title: appName,
                  subtitle: '屏幕使用时间 · 点击查看应用详情',
                  icon: Icons.smartphone_rounded,
                  type: SearchResultType.app,
                  extraData: {'app_name': appName, 'route': '/screen_time/app'},
                ),
              );
            }
          }

          final screenTimeCache = await StorageService.getScreenTimeCache();
          if (shouldContinue?.call() == false) return dbItems;
          if (screenTimeCache.isNotEmpty) {
            addScreenTimeApps(screenTimeCache);
          }

          final history = await StorageService.getScreenTimeHistory();
          if (shouldContinue?.call() == false) return dbItems;
          for (final dayEntry in history.entries) {
            final dayStats = dayEntry.value;
            if (dayStats.isEmpty) continue;
            addScreenTimeApps(dayStats);
          }
        } catch (e) {
          // debugPrint('Screen time search error: $e');
        }
      }
    }

    if (scope.includes(SearchResultType.log)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('pomodoro');
      // ── 番茄钟 ──────────────────────────────────────────────────────────
      {
        try {
          final matchingRange = isDateQuery
              ? await PomodoroService.getRecordsInRange(startOfDay!, endOfDay!)
              : await PomodoroService.getRecords();
          if (shouldContinue?.call() == false) return dbItems;
          final tagNames = isDateQuery
              ? const <String, String>{}
              : {
                  for (final tag in await PomodoroService.getTags())
                    tag.uuid: tag.name,
                };
          if (shouldContinue?.call() == false) return dbItems;
          final matchedPoms = isDateQuery
              ? matchingRange
              : matchingRange.where((p) {
                  final searchable = StringBuffer()
                    ..write(p.todoTitle ?? '')
                    ..write(' ')
                    ..write(p.note ?? '');
                  for (final tagUuid in p.tagUuids) {
                    final tagName = tagNames[tagUuid];
                    if (tagName == null) continue;
                    searchable
                      ..write(' ')
                      ..write(tagName);
                  }
                  return _matchesAllTerms(searchable.toString(), searchTerms);
                }).toList();
          final pomodoroTimeFormat = _searchDateFormat('HH:mm');
          for (var p in matchedPoms) {
            final start = DateTime.fromMillisecondsSinceEpoch(p.startTime);
            final end = p.endTime != null
                ? DateTime.fromMillisecondsSinceEpoch(p.endTime!)
                : start.add(Duration(minutes: p.effectiveDuration ~/ 60));
            final mins = p.effectiveDuration ~/ 60;
            dbItems.add(
              SearchResult(
                id: 'db_pom_${p.uuid}',
                title: p.todoTitle?.isNotEmpty == true ? p.todoTitle! : '专注记录',
                subtitle:
                    '$mins 分钟 · ${pomodoroTimeFormat.format(start)}'
                    ' - ${pomodoroTimeFormat.format(end)} · ${p.isCompleted ? "完成" : "中断"}',
                icon: Icons.timer_outlined,
                type: SearchResultType.log, // 与时间日志归在一组
                extraData: {
                  'uuid': p.uuid,
                  'table': 'pomodoro_records',
                  'date_query_hint': ?dateQueryHint,
                },
              ),
            );
          }
        } catch (e) {
          // debugPrint('Pomodoro search error: $e');
        }
      }
    }

    if (scope.includes(SearchResultType.todoGroup)) {
      if (shouldContinue?.call() == false) return dbItems;
      onSourceQueried?.call('todoGroups');
      // ── 待办文件夹 ────────────────────────────────────────────────────────
      try {
        final groupMap = <String, Map<String, dynamic>>{};
        final rows = await db.searchTodoGroupsByTerms(searchTerms);
        if (shouldContinue?.call() == false) return dbItems;
        for (final row in rows) {
          groupMap[row['uuid'].toString()] = row;
        }
        final groups = groupMap.values.where((g) {
          final name = g['name']?.toString() ?? '';
          final teamName = g['team_name']?.toString() ?? '';
          final haystack = '$name $teamName';
          return _matchesAllTerms(haystack, searchTerms);
        }).toList();
        for (var g in groups) {
          dbItems.add(
            SearchResult(
              id: 'db_group_${g['uuid']}',
              title: g['name'] ?? '未命名文件夹',
              subtitle: g['team_name'] != null
                  ? '团队文件夹 · ${g['team_name']}'
                  : '个人文件夹',
              icon: Icons.folder_rounded,
              type: SearchResultType.todoGroup,
              extraData: {'uuid': g['uuid'], 'table': 'todo_groups'},
            ),
          );
        }
      } catch (e) {
        // debugPrint('Todo group search error: $e');
      }
    }

    return dbItems;
  }

  /// 🚀 猜你想搜：非常轻量的启发式“小模型”
  /// 基于时间、任务紧急度、搜索历史、近期活动进行智能推荐
  Future<List<SearchResult>> guessSearch({
    bool Function()? shouldContinue,
  }) async {
    final suggestions = <SearchResult>[];
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final username = await StorageService.getLoginSession() ?? 'default';
    if (shouldContinue?.call() == false) return suggestions;
    // Start independent recommendation inputs together. Processing remains
    // ordered so the visible ranking is stable.
    final coursesFuture = CourseService.getAllCourses(username)
        .catchError((_) => <CourseItem>[]);
    // Keep the recommendation count aligned with the todo list and filter
    // used by the result detail and the home screen.
    final overdueTodosFuture =
        Future.wait<dynamic>([
              StorageService.getTodos(username),
              HabitRepository.getHabitOnlyRecurringTodoSeriesIds(),
            ])
            .then(
              (results) => shouldContinue?.call() == false
                  ? <TodoItem>[]
                  : _filterOverdueTodos(
                      todos: results[0] as List<TodoItem>,
                      excludedRecurrenceSeriesIds: results[1] as Set<String>,
                      before: now,
                    ),
            )
            .catchError((_) => <TodoItem>[]);
    final overdueCountFuture = overdueTodosFuture.then(
      (overdueTodos) => overdueTodos.length,
    );
    final topHistoryFuture = db
        .getRecentSearches(limit: 1)
        .catchError((_) => <Map<String, dynamic>>[]);
    final recentHistoryFuture = db
        .getRecentSearches(limit: 5, currentHour: now.hour)
        .catchError((_) => <Map<String, dynamic>>[]);
    final pomodoroFuture = PomodoroService.getLatestRecord().catchError(
      (_) => null,
    );

    // 1. 时间维度：根据时刻推荐
    final hour = now.hour;

    // 🚀 新增：基于“最近”课程的推荐 (全量时间轴最近)
    try {
      final allCourses = await coursesFuture;
      if (shouldContinue?.call() == false) return suggestions;
      if (allCourses.isNotEmpty) {
        CourseItem? nearestCourse;
        int minDiffSeconds = 0x7FFFFFFF; // 很大一个数
        String reason = "";

        for (var c in allCourses) {
          try {
            final dateParts = c.date.split('-');
            if (dateParts.length != 3) continue;

            final startDt = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              c.startTime ~/ 100,
              c.startTime % 100,
            );
            final endDt = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              c.endTime ~/ 100,
              c.endTime % 100,
            );

            // 1. 如果正在进行，优先级最高
            if (now.isAfter(startDt) && now.isBefore(endDt)) {
              nearestCourse = c;
              minDiffSeconds = 0;
              reason = "正在进行的课程";
              break;
            }

            // 2. 计算绝对距离
            final diffToStart = now.difference(startDt).inSeconds.abs();
            final diffToEnd = now.difference(endDt).inSeconds.abs();
            final localMin = diffToStart < diffToEnd ? diffToStart : diffToEnd;

            if (localMin < minDiffSeconds) {
              minDiffSeconds = localMin;
              nearestCourse = c;
              reason = now.isBefore(startDt) ? "即将开始的课程" : "最近结束的课程";
            }
          } catch (_) {}
        }

        if (nearestCourse != null) {
          suggestions.add(
            SearchResult(
              id: 'guess_recent_course',
              title: nearestCourse.courseName,
              subtitle: '🎓 $reason · ${nearestCourse.roomName}',
              icon: Icons.school_rounded,
              type: SearchResultType.recommend,
              extraData: {
                'action': 'apply_query',
                'query': nearestCourse.courseName,
              },
            ),
          );
        }
      }
    } catch (_) {}

    if (hour >= 6 && hour <= 10) {
      suggestions.add(
        SearchResult(
          id: 'guess_today_plan',
          title: '查看今日课表与待办',
          subtitle: '✨ 早安！开启高效的一天',
          icon: Icons.wb_sunny_outlined,
          type: SearchResultType.recommend,
          extraData: {'action': 'navigate', 'route': '/course/weekly'},
        ),
      );
    } else if (hour >= 21 || hour <= 2) {
      suggestions.add(
        SearchResult(
          id: 'guess_today_stats',
          title: '查看今日完成情况',
          subtitle: '🌙 晚安！回顾今日成就，展望下周规划',
          icon: Icons.insert_chart_outlined,
          type: SearchResultType.recommend,
          extraData: {
            'action': 'navigate',
            'route': '/personal_timeline',
            'initialDimension': 0, // 🚀 1 代表周视图
          },
        ),
      );
    }

    // 2. 紧急维度：逾期任务探测 (权重最高)
    try {
      final overdueCount = await overdueCountFuture;
      if (shouldContinue?.call() == false) return suggestions;
      if (overdueCount > 0) {
        suggestions.add(
          SearchResult(
            id: 'guess_overdue',
            title: '处理逾期任务 ($overdueCount)',
            subtitle: '⚠️ 发现已截止但未完成的任务，建议优先处理',
            icon: Icons.priority_high_rounded,
            type: SearchResultType.recommend,
            extraData: {'action': 'filter_overdue'},
          ),
        );
      }
    } catch (_) {}

    // 3. 历史频率维度：最常搜索 (Top 1)
    try {
      final topHistory = await topHistoryFuture; // 不按时段，按绝对频率
      if (shouldContinue?.call() == false) return suggestions;
      if (topHistory.isNotEmpty) {
        final h = topHistory.first;
        suggestions.add(
          SearchResult(
            id: 'guess_most_frequent',
            title: h['query'],
            subtitle: '💡 您最常搜索的内容',
            icon: Icons.lightbulb_outline_rounded,
            type: SearchResultType.recommend,
            extraData: {'action': 'apply_query', 'query': h['query']},
          ),
        );
      }
    } catch (_) {}

    // 4. 历史时间维度：最近搜索 (时段敏感型，展示前 5 条)
    try {
      final history = await recentHistoryFuture;
      if (shouldContinue?.call() == false) return suggestions;
      for (var h in history) {
        // 如果已经作为“最常搜索”推荐过了，就不再在历史里重复显示（可选）
        suggestions.add(
          SearchResult(
            id: 'history_${h['query']}',
            title: h['query'],
            subtitle: '最近搜过',
            icon: Icons.history_rounded,
            type: SearchResultType.history,
            extraData: {'action': 'apply_query', 'query': h['query']},
          ),
        );
      }
    } catch (_) {}

    // 4. 活动维度：近期专注活动
    try {
      final lastPom = await pomodoroFuture;
      if (shouldContinue?.call() == false) return suggestions;
      if (lastPom != null) {
        if (lastPom.todoTitle != null && lastPom.todoTitle!.isNotEmpty) {
          suggestions.add(
            SearchResult(
              id: 'guess_recent_focus',
              title: '继续搜索: ${lastPom.todoTitle}',
              subtitle: '🔥 您最近正在专注这项任务',
              icon: Icons.local_fire_department_rounded,
              type: SearchResultType.recommend,
              extraData: {'action': 'ai_query', 'query': lastPom.todoTitle},
            ),
          );
        }
      }
    } catch (_) {}

    // 5. 统计维度：今日屏幕时间
    suggestions.add(
      SearchResult(
        id: 'guess_screen_time',
        title: '今日屏幕使用时长',
        subtitle: '📊 看看今天在手机上花了多少时间',
        icon: Icons.pie_chart_rounded,
        type: SearchResultType.recommend,
        extraData: {'action': 'navigate', 'route': '/screen_time'},
      ),
    );

    return suggestions;
  }
}

class SearchNavigationHandler {
  static Future<void> handle(
    BuildContext context,
    SearchResult result, {
    required GlobalKey sourceKey,
  }) async {
    final data = result.extraData;
    if (data == null) return;

    final route = data['route'] as String?;
    final action = data['action'] as String?;
    final query = data['query'] as String?;

    if (action != null) {
      if ((action == 'ai_query' || action == 'apply_query') && query != null) {
        // 交给 UI 层处理：重新设置 Search Bar 的文本并触发搜索
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text("正在搜索: $query"),
            duration: const Duration(seconds: 1),
          ),
        );
      } else if (action == 'new_todo') {
        await _executeAction(context, action, sourceKey);
      } else if (action == 'navigate') {
        await _navigateByRoute(context, route ?? '', data, sourceKey);
      } else if (action == 'filter_overdue') {
        final username = await StorageService.getLoginSession() ?? 'default';
        final results = await Future.wait<dynamic>([
          StorageService.getTodos(username),
          HabitRepository.getHabitOnlyRecurringTodoSeriesIds(),
        ]);
        final overdue = SearchService._filterOverdueTodos(
          todos: results[0] as List<TodoItem>,
          excludedRecurrenceSeriesIds: results[1] as Set<String>,
          before: DateTime.now(),
        );
        if (!context.mounted) return;
        await _push(
          context,
          sourceKey,
          SearchRecordDetailScreen(
            result: SearchResult(
              id: result.id,
              title: result.title,
              subtitle: '${overdue.length} 项待办逾期',
              icon: result.icon,
              type: result.type,
              extraData: {
                'detail_label': '逾期待办',
                'fields': {'待办': overdue.map((item) => item.title).join('\n')},
              },
            ),
          ),
        );
      }
      return;
    }

    if (route != null) {
      await _navigateByRoute(context, route, data, sourceKey);
    } else if (result.type == SearchResultType.todo) {
      await _handleTodoEdit(context, result, sourceKey);
    } else if (result.type == SearchResultType.course ||
        data['type'] == 'course_detail') {
      await _handleCourseNavigation(context, result, sourceKey);
    } else if (result.type == SearchResultType.log) {
      final uuid = data['uuid']?.toString();
      final table = data['table']?.toString();
      if (uuid == null) {
        _showMissingRecord(context);
        return;
      }
      final tags = await PomodoroService.getTags();
      if (table == 'pomodoro_records') {
        final records = await PomodoroService.getRecords();
        if (!context.mounted) return;
        for (final record in records) {
          if (record.uuid == uuid) {
            await _push(
              context,
              sourceKey,
              PomodoroDetailScreen(record: record, tags: tags),
            );
            return;
          }
        }
      } else {
        final username = await StorageService.getLoginSession() ?? 'default';
        final logs = await StorageService.getTimeLogs(username);
        if (!context.mounted) return;
        for (final log in logs) {
          if (log.id == uuid) {
            await _push(
              context,
              sourceKey,
              TimeLogDetailScreen(log: log, tags: tags),
            );
            return;
          }
        }
      }
      _showMissingRecord(context);
    } else if (result.type == SearchResultType.journal &&
        data['record'] is JournalEntry) {
      final username = await StorageService.getLoginSession() ?? 'default';
      if (!context.mounted) return;
      await _push(
        context,
        sourceKey,
        JournalDetailScreen(
          accountId: username,
          entry: data['record'] as JournalEntry,
        ),
      );
    } else if (result.type == SearchResultType.fixedSchedule &&
        data['record'] is FixedScheduleItem) {
      final username = await StorageService.getLoginSession() ?? 'default';
      if (!context.mounted) return;
      await _push(
        context,
        sourceKey,
        FixedScheduleEditorScreen(
          username: username,
          item: data['record'] as FixedScheduleItem,
          onSave: (item) => StorageService.saveFixedSchedules(username, [item]),
        ),
      );
    } else if (result.type == SearchResultType.finance &&
        data['record'] is FinanceTransaction) {
      await _push(
        context,
        sourceKey,
        FinanceTransactionDetailScreen(
          transaction: data['record'] as FinanceTransaction,
          category: data['finance_category'] as FinanceCategory?,
          paymentMethod: data['finance_payment'] as FinancePaymentMethod?,
        ),
      );
    } else if (result.type == SearchResultType.finance &&
        data['record'] is FinanceLoan) {
      await _push(
        context,
        sourceKey,
        FinanceLoanDetailScreen(loan: data['record'] as FinanceLoan),
      );
    } else if (result.type == SearchResultType.finance &&
        data['record'] is FinanceBudget) {
      final budget = data['record'] as FinanceBudget;
      final month = DateTime.tryParse('${budget.monthKey}-01');
      if (month != null) {
        await _push(
          context,
          sourceKey,
          FinanceBudgetEntryScreen(month: month, budget: budget),
        );
      }
    } else if (result.type == SearchResultType.todoGroup) {
      final username = await StorageService.getLoginSession() ?? 'default';
      final todos = await StorageService.getTodos(username);
      final groups = await StorageService.getTodoGroups(username);
      final groupId = data['uuid']?.toString();
      if (!context.mounted) return;
      await _push(
        context,
        sourceKey,
        FolderManageScreen(
          username: username,
          todoGroups: groups,
          allTodos: todos,
          initialGroupId: groupId,
          onGroupsChanged: (items) async =>
              StorageService.saveTodoGroups(username, items),
          onTodosChanged: (items) async =>
              StorageService.saveTodos(username, items),
          onManualTodoSaved: (todo) async {
            final allTodos = await StorageService.getTodos(username);
            final existingIndex = allTodos.indexWhere(
              (item) => item.id == todo.id,
            );
            if (existingIndex < 0) {
              allTodos.add(todo);
            } else {
              allTodos[existingIndex] = todo;
            }
            await StorageService.saveTodos(username, allTodos);
            return const TodoCreateSaveResult();
          },
        ),
      );
    } else {
      await _push(context, sourceKey, SearchRecordDetailScreen(result: result));
    }
  }

  static Future<void> _push(
    BuildContext context,
    GlobalKey sourceKey,
    Widget page, {
    RouteSettings? settings,
  }) async {
    if (!context.mounted) return;
    await PageTransitions.pushFromRect(
      context: context,
      page: page,
      sourceKey: sourceKey,
      settings: settings,
    );
  }

  static void _showMissingRecord(BuildContext context) {
    if (!context.mounted) return;
    AppSnackBars.showSnackBar(
      context,
      const SnackBar(content: Text('这条记录已不存在，请重新搜索')),
    );
  }

  static Future<void> _handleTodoEdit(
    BuildContext context,
    SearchResult result,
    GlobalKey sourceKey,
  ) async {
    try {
      final uuid = result.extraData?['uuid'];
      if (uuid == null) {
        _showMissingRecord(context);
        return;
      }

      final db = DatabaseHelper.instance;
      final todoMap = await db.getTodoByUuid(uuid);
      if (todoMap == null) {
        if (!context.mounted) return;
        _showMissingRecord(context);
        return;
      }

      final username = await StorageService.getLoginSession();
      if (username == null) {
        if (!context.mounted) return;
        _showMissingRecord(context);
        return;
      }

      // 🚀 核心修复：due_date 在 DB 中是 TEXT (jsonType)，需要安全转 int
      int? toInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v == 0 ? null : v;
        final parsed = int.tryParse(v.toString());
        return (parsed == null || parsed == 0) ? null : parsed;
      }

      final todo = TodoItem(
        id: todoMap['uuid']?.toString(),
        title: todoMap['content']?.toString() ?? '',
        isDone: todoMap['is_completed'] == 1,
        isDeleted: todoMap['is_deleted'] == 1,
        version: (todoMap['version'] is int)
            ? todoMap['version']
            : int.tryParse(todoMap['version'].toString()) ?? 1,
        updatedAt: (todoMap['updated_at'] is int)
            ? todoMap['updated_at']
            : int.tryParse(todoMap['updated_at'].toString()),
        createdAt: (todoMap['created_at'] is int)
            ? todoMap['created_at']
            : int.tryParse(todoMap['created_at'].toString()),
        createdDate: toInt(todoMap['created_date']),
        dueDate: toInt(todoMap['due_date']) != null
            ? DateTime.fromMillisecondsSinceEpoch(toInt(todoMap['due_date'])!)
            : null,
        remark: todoMap['remark']?.toString(),
        groupId: todoMap['group_id']?.toString(),
        teamUuid: todoMap['team_uuid']?.toString(),
        teamName: todoMap['team_name']?.toString(),
        collabType: (todoMap['collab_type'] is int)
            ? todoMap['collab_type']
            : int.tryParse(todoMap['collab_type'].toString()) ?? 0,
        reminderMinutes: toInt(todoMap['reminder_minutes']),
      );

      final allTodos = await StorageService.getTodos(username);
      final allGroups = await StorageService.getTodoGroups(username);
      final canonicalTodo =
          allTodos.cast<TodoItem?>().firstWhere(
            (candidate) => candidate?.id == todo.id,
            orElse: () => null,
          ) ??
          todo;

      if (context.mounted) {
        await _push(
          context,
          sourceKey,
          TodoEditScreen(
            // 使用完整存储模型，保留循环规则和 recurrenceSeriesId，
            // 这样从全局搜索进入编辑页也能访问同系列的其他期次。
            todo: canonicalTodo,
            todos: allTodos,
            onTodosChanged: (newList) async {
              await StorageService.saveTodos(username, newList);
              if (context.mounted) {
                AppSnackBars.showSnackBar(
                  context,
                  const SnackBar(
                    content: Text("待办已更新"),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            onEditorSave: (changedTodos, baselines) async {
              final result = await TodoEditorSaveService.save(
                username: username,
                changedTodos: changedTodos,
                baselines: baselines,
              );
              if (context.mounted && result.warnings.isEmpty) {
                AppSnackBars.showSnackBar(
                  context,
                  const SnackBar(
                    content: Text('待办已更新'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              return result;
            },
            onEditorGroupsSave: (changedGroups, baselines) =>
                TodoEditorSaveService.saveGroups(
                  username: username,
                  changedGroups: changedGroups,
                  baselines: baselines,
                ),
            todoGroups: allGroups,
            onGroupsChanged: (newGroups) async {
              await StorageService.saveTodoGroups(username, newGroups);
            },
            username: username,
          ),
        );
      }
    } catch (e) {
      debugPrint('Open searched todo failed: $e');
      if (!context.mounted) return;
      _showMissingRecord(context);
    }
  }

  static Future<void> _handleCourseNavigation(
    BuildContext context,
    SearchResult result,
    GlobalKey sourceKey,
  ) async {
    try {
      final username = await StorageService.getLoginSession() ?? 'default';
      final adjusted = result.extraData?['course_record'];
      if (adjusted is CourseItem) {
        if (!context.mounted) return;
        await _push(
          context,
          sourceKey,
          CourseDetailScreen(course: adjusted, username: username),
        );
        return;
      }
      final uuid = result.extraData?['uuid'];
      if (uuid == null) {
        if (!context.mounted) return;
        _showMissingRecord(context);
        return;
      }

      final courses = await CourseService.getAllCourses(username);
      if (!context.mounted) return;
      for (final course in courses) {
        if (course.uuid == uuid.toString()) {
          await _push(
            context,
            sourceKey,
            CourseDetailScreen(course: course, username: username),
          );
          return;
        }
      }
      _showMissingRecord(context);
    } catch (e) {
      debugPrint('Open searched course failed: $e');
      _showMissingRecord(context);
    }
  }

  static Future<void> _navigateByRoute(
    BuildContext context,
    String route,
    Map<String, dynamic> data,
    GlobalKey sourceKey,
  ) async {
    final target = data['target'] as String?;
    Widget? page;
    final username = await StorageService.getLoginSession() ?? 'default';
    if (!context.mounted) return;

    if (route == '/time_log/tag') {
      final tagUuid = data['tag_uuid'];
      if (tagUuid != null) {
        await _push(
          context,
          sourceKey,
          TimeLogScreen(username: username, initialTagUuid: tagUuid),
        );
      }
      return;
    }

    if (route == '/screen_time/app') {
      final appName = data['app_name'];
      if (appName != null) {
        final history = await StorageService.getScreenTimeHistory();
        final todayKey = _searchDateFormat('yyyy-MM-dd').format(DateTime.now());
        if (history[todayKey] == null || history[todayKey]!.isEmpty) {
          final cachedToday = await StorageService.getScreenTimeCache();
          if (cachedToday.isNotEmpty) {
            history[todayKey] = cachedToday;
          }
        }
        if (!context.mounted) return;
        final searchDateMs = data['search_date_ms'] as int?;
        await _push(
          context,
          sourceKey,
          AppDetailScreen(
            appName: appName,
            historyStats: history,
            filter: DeviceFilter.all,
            range: ScreenTimeRange.day,
            anchorDate: searchDateMs == null
                ? DateTime.now()
                : DateTime.fromMillisecondsSinceEpoch(searchDateMs),
          ),
        );
      }
      return;
    }

    switch (route) {
      case '/pomodoro/stats':
        final dim = data['initialDimension'] as int? ?? 0;
        page = PomodoroScreen(
          username: username,
          initialTab: 1,
          initialDimension: dim,
        );
        break;
      case '/personal_timeline':
        final dimIndex = data['initialDimension'] as int? ?? 0;
        final dim = dimIndex >= 0 && dimIndex < TimelineDimension.values.length
            ? TimelineDimension.values[dimIndex]
            : TimelineDimension.daily;
        page = PersonalTimelineScreen(
          username: username,
          initialDimension: dim,
        );
        break;
      case '/time_log/manual':
        page = TimeLogScreen(username: username);
        break;
      case '/settings':
        if (target == null) {
          page = const SettingsPage();
          break;
        }
        final settingsPage = AiSettingsNavigation.pageFor(
          target,
          username: username,
        );
        if (settingsPage == null) {
          AppSnackBars.showSnackBar(
            context,
            const SnackBar(content: Text('这项设置当前不可用，请重新搜索')),
          );
          return;
        }
        final destination = AppSettingsCatalog.available.firstWhere(
          (item) => item.id == target,
        );
        await _push(
          context,
          sourceKey,
          settingsPage,
          settings: RouteSettings(name: destination.path),
        );
        return;
      case '/about':
        page = const AboutScreen();
        break;
      case '/login':
        page = const LoginScreen();
        break;
      case '/teams':
        if (target == 'messages' ||
            target == 'announcements' ||
            target == 'members') {
          final rawTeams = await ApiService.fetchTeams();
          final teams = rawTeams
              .whereType<Map>()
              .map((raw) => Team.fromJson(Map<String, dynamic>.from(raw)))
              .toList();
          if (target == 'messages') {
            page = TeamMessageCenterScreen(
              managedTeams: teams
                  .where((team) => team.userRole == TeamRole.admin)
                  .toList(),
            );
          } else if (teams.isNotEmpty) {
            page = target == 'announcements'
                ? TeamAnnouncementScreen(team: teams.first)
                : TeamMembersSearchScreen(team: teams.first);
          }
        }
        page ??= TeamManagementScreen(username: username);
        break;
      case '/today':
        page = WeeklyCourseScreen(username: username);
        break;
      case '/course/weekly':
        page = WeeklyCourseScreen(username: username);
        break;
      case '/plan':
        page = TodoPlanScreen(username: username);
        break;
      case '/finance':
        page = FinanceHomeScreen(username: username);
        break;
      case '/journal':
        page = JournalHomeScreen(username: username);
        break;
      case '/tomorrow':
        page = WeeklyCourseScreen(username: username);
        break;
      case '/screen_time':
        final cache = await StorageService.getScreenTimeCache();
        page = ScreenTimeDetailScreen(todayStats: cache);
        break;
      case '/habits':
        final habitUuid = data['habit_uuid']?.toString();
        if (habitUuid != null && habitUuid.isNotEmpty) {
          final goals = await HabitRepository.getGoals();
          HabitGoal? goal;
          for (final candidate in goals) {
            if (candidate.uuid == habitUuid) {
              goal = candidate;
              break;
            }
          }
          page = goal == null
              ? HabitCenterScreen(username: username)
              : HabitDetailScreen(goal: goal, username: username);
        } else {
          page = HabitCenterScreen(username: username);
        }
        break;
      case '/challenge':
        page = const ChallengeCenterScreen();
        break;
    }

    if (page != null && context.mounted) {
      await _push(context, sourceKey, page);
    }
  }

  static Future<void> _executeAction(
    BuildContext context,
    String action,
    GlobalKey sourceKey,
  ) async {
    if (action == 'new_todo') {
      final username = await StorageService.getLoginSession() ?? 'default';
      final groups = await StorageService.getTodoGroups(username);
      if (!context.mounted) return;
      await _push(
        context,
        sourceKey,
        AddTodoScreen(
          todoGroups: groups,
          onTodoAdded: (todo) async {
            final todos = await StorageService.getTodos(username);
            final existingIndex = todos.indexWhere(
              (item) => item.id == todo.id,
            );
            if (existingIndex < 0) {
              todos.add(todo);
            } else {
              todos[existingIndex] = todo;
            }
            await StorageService.saveTodos(username, todos);
          },
          onManualTodoSaved: (todo) async {
            final todos = await StorageService.getTodos(username);
            final existingIndex = todos.indexWhere(
              (item) => item.id == todo.id,
            );
            if (existingIndex < 0) {
              todos.add(todo);
            } else {
              todos[existingIndex] = todo;
            }
            await StorageService.saveTodos(username, todos);
            return const TodoCreateSaveResult();
          },
          onTodosBatchAdded: (added) async {
            final todos = await StorageService.getTodos(username);
            final indexById = <String, int>{};
            for (var index = 0; index < todos.length; index++) {
              indexById.putIfAbsent(todos[index].id, () => index);
            }
            for (final todo in added) {
              final index = indexById[todo.id];
              if (index == null) {
                indexById[todo.id] = todos.length;
                todos.add(todo);
              } else {
                todos[index] = todo;
              }
            }
            await StorageService.saveTodos(username, todos);
          },
          onFixedScheduleAdded: (item) =>
              StorageService.saveFixedSchedules(username, [item]),
        ),
      );
    }
  }
}
