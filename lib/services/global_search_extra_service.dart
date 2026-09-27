import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../features/finance/models/finance_models.dart';
import '../features/finance/services/finance_repository.dart';
import '../features/habits/repositories/habit_repository.dart';
import '../features/journal/services/journal_storage.dart';
import '../features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import '../features/thirty_day_challenge/services/cloud_challenge_service.dart';
import '../models.dart';
import '../storage_service.dart';
import 'api_service.dart';
import 'chat_storage_service.dart';
import 'database_helper.dart';

/// Search adapters for user records maintained outside the original search
/// tables. Every result has a stable id and enough data to open a detail page.
abstract final class GlobalSearchExtraService {
  static String? _remoteUsername;
  static DateTime? _remoteLoadedAt;
  static Future<void>? _remoteLoading;
  static List<SearchResult> _remoteRecords = const [];

  static String _money(int minor, String currency) =>
      '$currency ${(minor / 100).toStringAsFixed(2)}';

  static String _day(int millis) => DateFormat('yyyy-MM-dd HH:mm')
      .format(DateTime.fromMillisecondsSinceEpoch(millis));

  static bool _matches(
    List<String> terms,
    Iterable<Object?> values, {
    DateTime? targetDate,
    DateTime? recordDate,
  }) {
    if (targetDate != null) {
      return recordDate != null &&
          targetDate.year == recordDate.year &&
          targetDate.month == recordDate.month &&
          targetDate.day == recordDate.day;
    }
    final text = values.where((value) => value != null).join(' ').toLowerCase();
    return terms.every((term) => text.contains(term));
  }

  static SearchResult _result({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required SearchResultType type,
    required String label,
    required Map<String, String> fields,
    Object? record,
    Map<String, dynamic> data = const {},
  }) =>
      SearchResult(
        id: id,
        title: title,
        subtitle: subtitle,
        icon: icon,
        type: type,
        extraData: {
          'detail_label': label,
          'fields': fields,
          if (record != null) 'record': record,
          ...data,
        },
      );

  static Future<List<T>> _safeList<T>(
      Future<List<T>> source, String sourceName) async {
    try {
      return await source;
    } catch (error) {
      debugPrint('$sourceName global search failed: $error');
      return <T>[];
    }
  }

  static Future<List<SearchResult>> search(
    String username,
    List<String> terms, {
    DateTime? targetDate,
  }) async {
    final sources = await Future.wait<List<SearchResult>>([
      searchFinance(terms, targetDate),
      _journal(username, terms, targetDate),
      _schedule(username, terms, targetDate),
      _habitCheckIns(terms, targetDate),
      _challengeTasks(terms, targetDate),
      _chat(terms, targetDate),
      _localTeams(username, terms, targetDate),
    ]);
    final records = sources.expand((source) => source).toList();
    if (_remoteUsername == username) {
      records.addAll(_remoteRecords.where((record) {
        final data = record.extraData ?? const {};
        final fields = data['fields'] as Map? ?? const {};
        final timestamp = data['search_timestamp'] as int?;
        return _matches(
          terms,
          [record.title, record.subtitle, ...fields.values],
          targetDate: targetDate,
          recordDate: timestamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(timestamp),
        );
      }));
    }
    return records;
  }

  static Future<List<SearchResult>> searchFinance(
      List<String> terms, DateTime? date) async {
    final results = <SearchResult>[];
    try {
      final values = await Future.wait<dynamic>([
        _safeList(FinanceRepository.getCategories(includeArchived: true),
            'Finance categories'),
        _safeList(FinanceRepository.getPaymentMethods(includeArchived: true),
            'Finance payment methods'),
        _safeList(FinanceRepository.getTransactions(), 'Finance transactions'),
        _safeList(FinanceRepository.getBudgets(), 'Finance budgets'),
        _safeList(FinanceRepository.getRecurringRules(), 'Finance rules'),
        _safeList(FinanceRepository.getTemplates(), 'Finance templates'),
        _safeList(FinanceRepository.getLoans(), 'Finance loans'),
      ]);
      final categories = values[0] as List<FinanceCategory>;
      final payments = values[1] as List<FinancePaymentMethod>;
      final categoryById = {for (final item in categories) item.uuid: item};
      final paymentById = {for (final item in payments) item.uuid: item};

      for (final item in values[2] as List<FinanceTransaction>) {
        final category = categoryById[item.categoryUuid];
        final payment = paymentById[item.paymentMethodUuid];
        final title = item.merchant?.trim().isNotEmpty == true
            ? item.merchant!.trim()
            : category?.name ?? item.type.label;
        final amount = _money(item.amountMinor, item.currencyCode);
        if (!_matches(
            terms,
            [
              title,
              item.note,
              category?.name,
              payment?.name,
              item.transactionDate,
              amount,
              item.type.label
            ],
            targetDate: date,
            recordDate: DateTime.tryParse(item.transactionDate))) {
          continue;
        }
        results.add(_result(
          id: 'finance_transaction_${item.uuid}',
          title: title,
          subtitle: '${item.type.label} · $amount · ${item.transactionDate}',
          icon: Icons.receipt_long_rounded,
          type: SearchResultType.finance,
          label: '账单详情',
          record: item,
          data: {'finance_category': category, 'finance_payment': payment},
          fields: {
            '金额': amount,
            '日期': item.transactionDate,
            '分类': category?.name ?? '未分类',
            '付款方式': payment?.name ?? '未指定',
            '备注': item.note ?? '',
          },
        ));
      }

      for (final item in categories) {
        if (!_matches(terms, [item.name, item.type.label, '记账分类', '分类'],
            targetDate: date)) {
          continue;
        }
        results.add(_result(
          id: 'finance_category_${item.uuid}',
          title: item.name,
          subtitle:
              '记账分类 · ${item.type.label}${item.isArchived ? ' · 已归档' : ''}',
          icon: Icons.category_outlined,
          type: SearchResultType.finance,
          label: '记账分类',
          fields: {
            '名称': item.name,
            '类型': item.type.label,
            '状态': item.isArchived ? '已归档' : '使用中'
          },
        ));
      }
      for (final item in payments) {
        if (!_matches(terms, [item.name, '付款方式'], targetDate: date)) {
          continue;
        }
        results.add(_result(
          id: 'finance_payment_${item.uuid}',
          title: item.name,
          subtitle: '付款方式${item.isArchived ? ' · 已归档' : ''}',
          icon: Icons.account_balance_wallet_outlined,
          type: SearchResultType.finance,
          label: '付款方式',
          fields: {'名称': item.name, '状态': item.isArchived ? '已归档' : '使用中'},
        ));
      }
      for (final item in values[3] as List<FinanceBudget>) {
        final scope = categoryById[item.categoryUuid]?.name ??
            paymentById[item.paymentMethodUuid]?.name ??
            '总预算';
        final amount = _money(item.amountMinor, item.currencyCode);
        final matchesMonth =
            date != null && item.monthKey == DateFormat('yyyy-MM').format(date);
        if (date != null
            ? !matchesMonth
            : !_matches(
                terms, [scope, item.note, item.monthKey, amount, '预算'])) {
          continue;
        }
        results.add(_result(
          id: 'finance_budget_${item.uuid}',
          title: '$scope预算',
          subtitle: '${item.monthKey} · $amount',
          icon: Icons.savings_outlined,
          type: SearchResultType.finance,
          label: '预算',
          record: item,
          fields: {
            '月份': item.monthKey,
            '范围': scope,
            '金额': amount,
            '备注': item.note ?? ''
          },
        ));
      }
      for (final item in values[4] as List<FinanceRecurringRule>) {
        final amount = _money(item.amountMinor, item.currencyCode);
        if (!_matches(
            terms,
            [
              item.name,
              item.merchant,
              item.note,
              categoryById[item.categoryUuid]?.name,
              amount,
              '周期账单',
              '自动记账'
            ],
            targetDate: date,
            recordDate: DateTime.tryParse(item.startDate))) {
          continue;
        }
        results.add(_result(
          id: 'finance_rule_${item.uuid}',
          title: item.name,
          subtitle: '周期账单 · $amount',
          icon: Icons.event_repeat_rounded,
          type: SearchResultType.finance,
          label: '周期账单',
          fields: {
            '金额': amount,
            '开始日期': item.startDate,
            '结束日期': item.endDate ?? '',
            '商家': item.merchant ?? '',
            '备注': item.note ?? '',
            '状态': item.isEnabled ? '启用' : '停用'
          },
        ));
      }
      for (final item in values[5] as List<FinanceEntryTemplate>) {
        final amount = _money(item.amountMinor, item.currencyCode);
        if (!_matches(
            terms,
            [
              item.name,
              item.merchant,
              item.note,
              categoryById[item.categoryUuid]?.name,
              amount,
              '记账模板'
            ],
            targetDate: date)) {
          continue;
        }
        results.add(_result(
          id: 'finance_template_${item.uuid}',
          title: item.name,
          subtitle: '记账模板 · $amount',
          icon: Icons.bookmark_outline,
          type: SearchResultType.finance,
          label: '记账模板',
          fields: {
            '金额': amount,
            '商家': item.merchant ?? '',
            '备注': item.note ?? '',
            '使用次数': '${item.useCount}'
          },
        ));
      }
      for (final loan in values[6] as List<FinanceLoan>) {
        final amount = _money(loan.principalMinor, loan.currencyCode);
        if (_matches(terms, [loan.name, loan.lender, loan.note, amount, '借款'],
            targetDate: date, recordDate: DateTime.tryParse(loan.startDate))) {
          results.add(_result(
            id: 'finance_loan_${loan.uuid}',
            title: loan.name,
            subtitle: '借款 · $amount',
            icon: Icons.account_balance_outlined,
            type: SearchResultType.finance,
            label: '借款',
            record: loan,
            fields: {
              '本金': amount,
              '借款方': loan.lender ?? '',
              '开始日期': loan.startDate,
              '备注': loan.note ?? ''
            },
          ));
        }
        for (final installment in await _safeList(
            FinanceRepository.getLoanInstallments(loan.uuid),
            'Finance loan installments')) {
          if (!_matches(
              terms,
              [
                loan.name,
                loan.lender,
                installment.dueDate,
                '还款',
                '${installment.installmentIndex}'
              ],
              targetDate: date,
              recordDate: DateTime.tryParse(installment.dueDate))) {
            continue;
          }
          results.add(_result(
            id: 'finance_installment_${installment.uuid}',
            title: '${loan.name} · 第${installment.installmentIndex}期',
            subtitle: '还款 · ${installment.dueDate}',
            icon: Icons.payments_outlined,
            type: SearchResultType.finance,
            label: '还款计划',
            fields: {
              '到期日': installment.dueDate,
              '应还': _money(installment.paymentMinor, loan.currencyCode),
              '状态': installment.isPaid ? '已还' : '未还'
            },
          ));
        }
      }
    } catch (error) {
      debugPrint('Finance global search failed: $error');
    }
    return results;
  }

  static Future<List<SearchResult>> _journal(
      String username, List<String> terms, DateTime? date) async {
    final results = <SearchResult>[];
    try {
      const pageSize = 40;
      final contentTerm =
          terms.where((term) => term != '日记' && term != '私密日记').firstOrNull;
      var offset = 0;
      while (true) {
        final page = await JournalStorage.instance.loadEntries(
          accountId: username,
          limit: pageSize,
          offset: offset,
          searchQuery: date == null ? contentTerm : null,
        );
        for (final item in page) {
          if (!_matches(terms, [item.title, item.content, '日记 私密日记'],
              targetDate: date, recordDate: item.occurredAt)) {
            continue;
          }
          results.add(_result(
            id: 'journal_${item.id}',
            title:
                item.title?.trim().isNotEmpty == true ? item.title! : '未命名日记',
            subtitle: DateFormat('yyyy-MM-dd').format(item.occurredAt),
            icon: Icons.auto_stories_outlined,
            type: SearchResultType.journal,
            label: '私密日记',
            record: item,
            fields: {
              '日期': DateFormat('yyyy-MM-dd').format(item.occurredAt),
              '正文': item.content
            },
          ));
        }
        if (page.length < pageSize) break;
        offset += pageSize;
      }
    } catch (error) {
      debugPrint('Journal global search failed: $error');
    }
    return results;
  }

  static Future<List<SearchResult>> _schedule(
      String username, List<String> terms, DateTime? date) async {
    final results = <SearchResult>[];
    try {
      final schedules = await StorageService.getFixedSchedules(username);
      for (final item in schedules) {
        if (item.isDeleted ||
            !_matches(
                terms, [item.title, item.location, item.remark, item.date],
                targetDate: date, recordDate: DateTime.tryParse(item.date))) {
          continue;
        }
        results.add(_result(
          id: 'fixed_schedule_${item.id}',
          title: item.title,
          subtitle:
              '固定日程 · ${item.date}${item.location == null ? '' : ' · ${item.location}'}',
          icon: Icons.event_available_outlined,
          type: SearchResultType.fixedSchedule,
          label: '固定日程',
          record: item,
          fields: {
            '日期': item.date,
            '地点': item.location ?? '',
            '备注': item.remark ?? ''
          },
        ));
      }
      final blocks = await StorageService.getPlanBlocks(username);
      for (final item in blocks) {
        if (item.isDeleted) continue;
        final start = DateTime.fromMillisecondsSinceEpoch(item.startTime);
        final title = item.titleSnapshot?.trim().isNotEmpty == true
            ? item.titleSnapshot!
            : '待办规划块';
        if (!_matches(terms, [title, item.remark, _day(item.startTime)],
            targetDate: date, recordDate: start)) {
          continue;
        }
        results.add(_result(
          id: 'plan_block_${item.id}',
          title: title,
          subtitle: '规划块 · ${_day(item.startTime)}',
          icon: Icons.view_timeline_outlined,
          type: SearchResultType.planBlock,
          label: '待办规划块',
          record: item,
          fields: {
            '开始': _day(item.startTime),
            '结束': _day(item.endTime),
            '计划时长': '${item.plannedMinutes} 分钟',
            '备注': item.remark ?? ''
          },
        ));
      }
    } catch (error) {
      debugPrint('Schedule global search failed: $error');
    }
    return results;
  }

  static Future<List<SearchResult>> _habitCheckIns(
      List<String> terms, DateTime? date) async {
    final results = <SearchResult>[];
    try {
      final goals = await HabitRepository.getGoals();
      final names = {for (final goal in goals) goal.uuid: goal.name};
      final checkIns = await HabitRepository.getCheckIns();
      for (final item in checkIns) {
        if (item.isDeleted) continue;
        final name = names[item.habitUuid] ?? '习惯';
        if (!_matches(
            terms, [name, item.note, item.logicalDate, '${item.value}'],
            targetDate: date,
            recordDate: DateTime.tryParse(item.logicalDate))) {
          continue;
        }
        results.add(_result(
          id: 'habit_checkin_${item.uuid}',
          title: '$name · 打卡',
          subtitle: '${item.logicalDate} · ${item.value}',
          icon: Icons.task_alt_rounded,
          type: SearchResultType.habitCheckIn,
          label: '习惯打卡',
          fields: {
            '习惯': name,
            '日期': item.logicalDate,
            '数值': '${item.value}',
            '备注': item.note ?? ''
          },
          data: {'habit_uuid': item.habitUuid},
        ));
      }
    } catch (error) {
      debugPrint('Habit check-in global search failed: $error');
    }
    return results;
  }

  static Future<List<SearchResult>> _challengeTasks(
      List<String> terms, DateTime? date) async {
    final results = <SearchResult>[];
    try {
      if (!await ThirtyDayChallengeRepository.hasStarted()) return results;
      final state = await ThirtyDayChallengeRepository.load();
      for (final task in state.tasks) {
        if (!_matches(terms, [state.challengeTitle, task.title, task.feeling],
            targetDate: date, recordDate: task.completedAt)) {
          continue;
        }
        results.add(_result(
          id: 'challenge_task_${task.id}',
          title: task.title,
          subtitle:
              '${state.challengeTitle} · ${task.isCompleted ? '已完成' : '未完成'}',
          icon: Icons.auto_awesome_outlined,
          type: SearchResultType.challengeTask,
          label: '挑战任务',
          fields: {
            '挑战': state.challengeTitle,
            '状态': task.isCompleted ? '已完成' : '未完成',
            '完成时间': task.completedAt == null
                ? ''
                : DateFormat('yyyy-MM-dd HH:mm').format(task.completedAt!),
            '感受记录': task.feeling
          },
        ));
      }
    } catch (error) {
      debugPrint('Challenge task global search failed: $error');
    }
    return results;
  }

  static Future<List<SearchResult>> _chat(
      List<String> terms, DateTime? date) async {
    final results = <SearchResult>[];
    try {
      final sessions = await ChatStorageService.loadSessions();
      for (final session in sessions) {
        final history = await _safeList(
            ChatStorageService.loadHistory(session.id), 'AI chat history');
        if (_matches(terms, [session.title, 'AI 对话'],
            targetDate: date, recordDate: session.updatedAt)) {
          results.add(_result(
            id: 'chat_session_${session.id}',
            title: session.title,
            subtitle:
                'AI 历史对话 · ${DateFormat('yyyy-MM-dd').format(session.updatedAt)}',
            icon: Icons.chat_bubble_outline_rounded,
            type: SearchResultType.chat,
            label: 'AI 历史对话',
            fields: {
              '会话标题': session.title,
              '更新时间': DateFormat('yyyy-MM-dd HH:mm').format(session.updatedAt),
              '对话内容': history
                  .map((message) => '${message.role.name}: ${message.content}')
                  .join('\n\n'),
            },
            data: {'chat_session_id': session.id},
          ));
        }
        for (final message in history) {
          if (!_matches(terms, [session.title, message.content],
              targetDate: date, recordDate: message.timestamp)) {
            continue;
          }
          final preview = message.content.replaceAll(RegExp(r'\s+'), ' ');
          results.add(_result(
            id: 'chat_message_${session.id}_${message.id}',
            title: session.title,
            subtitle:
                preview.length > 90 ? '${preview.substring(0, 90)}…' : preview,
            icon: Icons.forum_outlined,
            type: SearchResultType.chat,
            label: 'AI 对话消息',
            fields: {
              '会话': session.title,
              '时间': DateFormat('yyyy-MM-dd HH:mm').format(message.timestamp),
              '内容': message.content
            },
            data: {'chat_session_id': session.id},
          ));
        }
      }
    } catch (error) {
      debugPrint('Chat global search failed: $error');
    }
    return results;
  }

  static Future<List<SearchResult>> _localTeams(
      String username, List<String> terms, DateTime? date) async {
    final results = <SearchResult>[];
    try {
      final db = await DatabaseHelper.instance.databaseForUser(username);
      final rows = await db.query('teams');
      for (final row in rows) {
        final team = Team.fromJson(row);
        if (!_matches(terms, [team.name],
            targetDate: date,
            recordDate: DateTime.fromMillisecondsSinceEpoch(team.createdAt))) {
          continue;
        }
        results.add(_result(
          id: 'team_${team.uuid}',
          title: team.name,
          subtitle: '团队 · ${team.memberCount} 位成员',
          icon: Icons.groups_rounded,
          type: SearchResultType.team,
          label: '团队',
          fields: {'团队名称': team.name, '成员数': '${team.memberCount}'},
          data: {'team_uuid': team.uuid},
        ));
      }
    } catch (error) {
      debugPrint('Local team global search failed: $error');
    }
    return results;
  }

  /// Remote catalogs are loaded once per search opening. Local records remain
  /// searchable immediately; the overlay refreshes when this future finishes.
  static Future<void> warmupRemote(String username) {
    final fresh = _remoteUsername == username &&
        _remoteLoadedAt != null &&
        DateTime.now().difference(_remoteLoadedAt!) <
            const Duration(minutes: 5);
    if (fresh) return Future.value();
    if (_remoteUsername != username) {
      _remoteUsername = username;
      _remoteRecords = const [];
      _remoteLoading = null;
    }
    if (_remoteLoading != null) return _remoteLoading!;
    late Future<void> pending;
    pending = _loadRemote(username).whenComplete(() {
      if (identical(_remoteLoading, pending)) _remoteLoading = null;
    });
    _remoteLoading = pending;
    return pending;
  }

  static Future<void> _loadRemote(String username) async {
    final records = <SearchResult>[];
    final teamsFuture = ApiService.fetchTeams()
        .timeout(const Duration(seconds: 4))
        .catchError((Object error) {
      debugPrint('Team global search warmup failed: $error');
      return <dynamic>[];
    });
    final cloud = CloudChallengeService();
    try {
      final cached = await cloud.readCachedCatalog();
      final catalog = cached?.catalog ??
          await cloud.fetchCatalog().timeout(const Duration(seconds: 4));
      for (final template in catalog.challenges) {
        records.add(_result(
          id: 'challenge_template_${template.id}',
          title: template.title,
          subtitle: '云端挑战模板 · ${template.description}',
          icon: Icons.auto_awesome_motion_rounded,
          type: SearchResultType.challengeTemplate,
          label: '挑战模板',
          fields: {
            '简介': template.description,
            '标签': template.tags.join('、'),
            '任务': template.tasks.join('\n')
          },
        ));
      }
    } catch (error) {
      debugPrint('Challenge catalog search warmup failed: $error');
    } finally {
      cloud.dispose();
    }

    try {
      final rawTeams = await teamsFuture;
      final teams = rawTeams
          .whereType<Map>()
          .map((raw) => Team.fromJson(Map<String, dynamic>.from(raw)))
          .toList();
      for (final team in teams) {
        records.add(_result(
          id: 'team_${team.uuid}',
          title: team.name,
          subtitle: '团队 · ${team.memberCount} 位成员',
          icon: Icons.groups_rounded,
          type: SearchResultType.team,
          label: '团队',
          fields: {'团队名称': team.name, '成员数': '${team.memberCount}'},
          data: {'team_uuid': team.uuid},
        ));
      }
      final grouped = await Future.wait(teams.map((team) async {
        final values = await Future.wait<dynamic>([
          ApiService.fetchTeamAnnouncements(team.uuid)
              .timeout(const Duration(seconds: 4), onTimeout: () => []),
          _fetchAllTeamSystemMessages(team.uuid),
        ]);
        final entries = <SearchResult>[];
        for (final raw in values[0] as List<dynamic>) {
          if (raw is! Map) continue;
          final item =
              TeamAnnouncement.fromJson(Map<String, dynamic>.from(raw));
          entries.add(_result(
            id: 'team_announcement_${item.uuid}',
            title: item.title,
            subtitle: '${team.name} · 团队公告',
            icon: Icons.campaign_outlined,
            type: SearchResultType.team,
            label: '团队公告',
            fields: {
              '团队': team.name,
              '内容': item.content,
              '发布者': item.creatorName ?? ''
            },
            data: {'team_uuid': team.uuid, 'search_timestamp': item.createdAt},
          ));
        }
        final messages = values[1] as List<dynamic>;
        if (messages.isNotEmpty) {
          for (final raw in messages) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final title =
                map['title']?.toString() ?? map['type']?.toString() ?? '团队消息';
            final content =
                map['content']?.toString() ?? map['message']?.toString() ?? '';
            final identity =
                map['uuid'] ?? map['id'] ?? map['timestamp'] ?? entries.length;
            entries.add(_result(
              id: 'team_message_${team.uuid}_$identity',
              title: title,
              subtitle: '${team.name} · $content',
              icon: Icons.mark_chat_unread_outlined,
              type: SearchResultType.team,
              label: '团队消息',
              fields: {
                '团队': team.name,
                '内容': content,
                '类型': map['type']?.toString() ?? ''
              },
              data: {
                'team_uuid': team.uuid,
                'search_timestamp':
                    int.tryParse(map['timestamp']?.toString() ?? '')
              },
            ));
          }
        }
        return entries;
      }));
      records.addAll(grouped.expand((group) => group));
    } catch (error) {
      debugPrint('Team global search warmup failed: $error');
    }
    if (_remoteUsername == username) {
      _remoteRecords = records;
      _remoteLoadedAt = DateTime.now();
    }
  }

  static Future<List<dynamic>> _fetchAllTeamSystemMessages(
      String teamUuid) async {
    const pageSize = 100;
    final messages = <dynamic>[];
    final seenIds = <String>{};
    var offset = 0;
    while (true) {
      Map<String, dynamic> response;
      try {
        response = await ApiService.fetchTeamSystemMessages(
          teamUuid,
          limit: pageSize,
          offset: offset,
        ).timeout(const Duration(seconds: 4));
      } catch (error) {
        debugPrint('Team messages search failed: $error');
        break;
      }
      final page = response['messages'];
      if (page is! List || page.isEmpty) break;
      var added = 0;
      for (final raw in page) {
        if (raw is! Map) continue;
        final id = raw['id']?.toString() ?? raw['uuid']?.toString();
        if (id == null || seenIds.add(id)) {
          messages.add(raw);
          added++;
        }
      }
      // Older servers ignore paging and return their original 50 records.
      if (page.length < pageSize || added == 0) break;
      offset += page.length;
    }
    return messages;
  }
}
