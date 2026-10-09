import 'dart:convert';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/search_scope.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/search_scope_fixture.dart';

const expectedSources = <SearchScope, Set<String>>{
  SearchScope.todos: {'todos', 'todoGroups'},
  SearchScope.schedule: {'courses', 'fixedSchedules', 'planBlocks'},
  SearchScope.finance: {'finance'},
  SearchScope.focus: {'timeLogs', 'tags', 'pomodoro'},
  SearchScope.countdowns: {'countdowns'},
  SearchScope.habits: {'habits', 'habitCheckIns'},
  SearchScope.challenges: {'challenges', 'challengeTasks'},
  SearchScope.screenTime: {'screenTime'},
  SearchScope.teams: {'teams'},
  SearchScope.journal: {'journal'},
  SearchScope.chat: {'chat'},
  SearchScope.settings: {},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('每个业务结果类型仅属于一个专属范围，历史和建议仅属于全部', () {
    for (final type in SearchResultType.values) {
      expect(SearchScope.all.includes(type), isTrue);
      final domains = SearchScope.values.where(
        (scope) => scope != SearchScope.all && scope.includes(type),
      );
      expect(
        domains,
        hasLength(
          {SearchResultType.history, SearchResultType.recommend}.contains(type)
              ? 0
              : 1,
        ),
        reason: type.name,
      );
    }
    expect(SearchScope.schedule.types, {
      SearchResultType.course,
      SearchResultType.fixedSchedule,
      SearchResultType.planBlock,
    });
    expect(SearchScope.challenges.types, {
      SearchResultType.challenge,
      SearchResultType.challengeTask,
      SearchResultType.challengeTemplate,
    });
  });

  group('真实查询适配器', () {
    late SearchScopeFixture fixture;
    setUp(() async {
      fixture = SearchScopeFixture();
      await fixture.initialize();
    });
    tearDown(() => fixture.dispose());

    for (final entry in expectedSources.entries) {
      test('${entry.key.label}仅调用对应来源并保持命中类型', () async {
        final sources = <String>[];
        final results = await SearchService.instance.search(
          '午餐',
          scope: entry.key,
          recordHistory: false,
          onSourceQueried: sources.add,
        );
        expect(sources.toSet(), entry.value);
        expect(sources, hasLength(entry.value.length));
        expect(results.every((item) => entry.key.includes(item.type)), isTrue);
        if ({
          SearchScope.todos,
          SearchScope.schedule,
          SearchScope.finance,
          SearchScope.focus,
          SearchScope.countdowns,
          SearchScope.habits,
          SearchScope.challenges,
          SearchScope.journal,
          SearchScope.chat,
        }.contains(entry.key)) {
          expect(results, isNotEmpty);
        }
        if (entry.key == SearchScope.schedule) {
          expect(
            results.map((item) => item.type).toSet(),
            SearchScope.schedule.types,
          );
        }
        if (entry.key == SearchScope.habits) {
          expect(
            results.map((item) => item.type).toSet(),
            SearchScope.habits.types,
          );
        }
        if (entry.key == SearchScope.challenges) {
          expect(
            results.map((item) => item.type),
            containsAll([
              SearchResultType.challenge,
              SearchResultType.challengeTask,
            ]),
          );
        }
      });
    }

    test('全部保留所有本地来源和多个业务模块', () async {
      final sources = <String>[];
      final results = await SearchService.instance.search(
        '午餐',
        recordHistory: false,
        onSourceQueried: sources.add,
      );
      expect(
        sources.toSet(),
        expectedSources.values.expand((items) => items).toSet(),
      );
      expect(sources, hasLength(18));
      expect(
        results.map((item) => item.type),
        containsAll([
          SearchResultType.todo,
          SearchResultType.finance,
          SearchResultType.journal,
          SearchResultType.course,
          SearchResultType.fixedSchedule,
          SearchResultType.planBlock,
          SearchResultType.chat,
        ]),
      );
      expect(results.map((item) => item.id).toSet(), hasLength(results.length));
    });

    test('中文多词与备注命中不被标题相关度过滤丢弃', () async {
      final results = await SearchService.instance.search(
        '午餐 报销',
        scope: SearchScope.todos,
        recordHistory: false,
      );
      expect(results.single.id, 'db_todo_todo_0');
      expect(results.single.title, '取回餐具 0');
    });

    test('日程日期查询包含课程、固定日程和规划块', () async {
      final results = await SearchService.instance.search(
        '2026-10-07',
        scope: SearchScope.schedule,
        recordHistory: false,
      );
      expect(
        results.map((item) => item.type).toSet(),
        SearchScope.schedule.types,
      );
      final none = await SearchService.instance.search(
        '2026-10-08',
        scope: SearchScope.schedule,
        recordHistory: false,
      );
      expect(none, isEmpty);
    });

    test('专属范围空输入不读取任何来源或写入历史', () async {
      final sources = <String>[];
      final results = await SearchService.instance.search(
        '  ',
        scope: SearchScope.finance,
        onSourceQueried: sources.add,
      );
      expect(results, isEmpty);
      expect(sources, isEmpty);
      expect(await fixture.db.query('search_history'), isEmpty);
    });

    test('记账范围包含贷款、分期和分类等子类型', () async {
      await FinanceStorage.saveCategory(
        FinanceCategory(
          uuid: 'category',
          name: '午餐分类',
          type: FinanceCategoryType.expense,
        ),
      );
      await FinanceStorage.saveLoan(
        FinanceLoan(
          uuid: 'loan',
          name: '午餐借款',
          principalMinor: 30000,
          termMonths: 3,
          startDate: '2026-10-07',
          repaymentDay: 7,
        ),
      );
      final results = await SearchService.instance.search(
        '午餐',
        scope: SearchScope.finance,
        recordHistory: false,
      );
      expect(
        results.map((item) => item.id),
        containsAll([
          'finance_transaction_finance_0',
          'finance_category_category',
          'finance_loan_loan',
        ]),
      );
      expect(
        results.any((item) => item.id.startsWith('finance_installment_')),
        isTrue,
      );
    });

    test('刷新与范围切换可关闭历史写入，业务结果保持正常', () async {
      await SearchService.instance.search('午餐', scope: SearchScope.finance);
      await SearchService.instance.search(
        '午餐',
        scope: SearchScope.todos,
        recordHistory: false,
      );
      final history = await DatabaseHelper.instance.getRecentSearches();
      expect(history.single['query'], '午餐');
      expect(history.single['frequency'], 1);
    });

    test('设置范围保留平台过滤和动态快捷操作', () async {
      final results = await SearchService.instance.search(
        '新',
        scope: SearchScope.settings,
        recordHistory: false,
      );
      expect(results.map((item) => item.id), contains('action_new_todo'));
      final finance = await SearchService.instance.search(
        '新',
        scope: SearchScope.finance,
        recordHistory: false,
      );
      expect(
        finance.any((item) => item.type == SearchResultType.action),
        isFalse,
      );
    });
  });

  test('合成跨模块数据测量来源调用与查询耗时', () async {
    final fixture = SearchScopeFixture();
    await fixture.initialize(rows: 200);
    addTearDown(fixture.dispose);
    final times = <String, List<int>>{'all': [], 'finance': []};
    final counts = <String, int>{};
    for (var i = 0; i < 7; i++) {
      for (final scope in [SearchScope.all, SearchScope.finance]) {
        final sources = <String>[];
        final watch = Stopwatch()..start();
        final results = await SearchService.instance.search(
          '午餐',
          scope: scope,
          recordHistory: false,
          onSourceQueried: sources.add,
        );
        watch.stop();
        expect(results, isNotEmpty);
        counts[scope.name] = sources.length;
        if (i > 0) times[scope.name]!.add(watch.elapsedMicroseconds);
      }
    }
    expect(counts, {'all': 18, 'finance': 1});
    final median = <String, double>{};
    for (final entry in times.entries) {
      entry.value.sort();
      median[entry.key] = ((entry.value[2] + entry.value[3]) / 2) / 1000;
    }
    // Measured observations only; timing is deliberately not a pass/fail claim.
    // ignore: avoid_print
    print(
      'SEARCH_SCOPE_BENCHMARK ${jsonEncode({'rowsPerMainDomain': 200, 'logicalSourceCalls': counts, 'medianMilliseconds': median, 'measuredRunsPerScope': 6})}',
    );
  });
}
