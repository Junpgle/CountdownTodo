import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/search_scope.dart';
import 'package:countdown_todo/screens/search_record_detail_screen.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:countdown_todo/widgets/global_search_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SearchResult result(String title, SearchResultType type) => SearchResult(
  id: title,
  title: title,
  subtitle: '合成验收记录',
  icon: Icons.receipt_long_outlined,
  type: type,
  extraData: {
    'fields': {'备注': '验收用合成数据'},
    'detail_label': '验收记录',
  },
);

class SearchCall {
  SearchCall(this.query, this.scope, this.recordHistory);
  final String query;
  final SearchScope scope;
  final bool recordHistory;
}

Future<void> pumpSearch(
  WidgetTester tester, {
  required GlobalSearchCallback search,
  Size size = const Size(1200, 900),
  double textScale = 1,
  double keyboard = 0,
  Brightness brightness = Brightness.light,
  Future<void> Function()? warmup,
  NavigatorObserver? observer,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      ),
      navigatorObservers: [?observer],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: GlobalSearchOverlay(
        search: search,
        warmupRemote: warmup ?? () async {},
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, SearchScope scope) async {
  final target = find.byKey(ValueKey('search_scope_${scope.name}'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> input(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 350));
}

class Routes extends NavigatorObserver {
  Route<dynamic>? lastPushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'enable_animations': true,
      'enable_lazy_load': false,
      'animation_duration': 300,
    });
    await PageTransitions.init();
  });

  testWidgets('范围切换保留关键词且防御过滤无关结果', (tester) async {
    final calls = <SearchCall>[];
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) async {
        calls.add(SearchCall(query, scope, recordHistory));
        return query.isEmpty
            ? []
            : [
                result('午餐账单', SearchResultType.finance),
                result('午餐日记', SearchResultType.journal),
              ];
      },
    );
    await input(tester, '午餐');
    await tester.pumpAndSettle();
    await choose(tester, SearchScope.finance);
    await tester.pumpAndSettle();
    expect(find.text('午餐账单', findRichText: true), findsOneWidget);
    expect(find.text('午餐日记', findRichText: true), findsNothing);
    expect(find.text('搜索范围：记账'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '午餐',
    );
    expect(calls.where((call) => call.recordHistory), hasLength(1));
    await choose(tester, SearchScope.all);
    await tester.pumpAndSettle();
    expect(find.text('午餐日记', findRichText: true), findsOneWidget);
  });

  testWidgets('空输入提示和搜索全部按钮准确，清空保留范围', (tester) async {
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) async => [],
    );
    await choose(tester, SearchScope.finance);
    await tester.pumpAndSettle();
    expect(find.text('输入关键词，在记账中搜索'), findsOneWidget);
    await input(tester, '没有这笔账');
    await tester.pumpAndSettle();
    expect(find.text('在记账中未找到“没有这笔账”'), findsOneWidget);
    await tester.tap(find.text('搜索全部'));
    await tester.pumpAndSettle();
    expect(find.text('搜索范围：全部'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '没有这笔账',
    );
    await choose(tester, SearchScope.finance);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('输入关键词，在记账中搜索'), findsOneWidget);
  });

  testWidgets('更多范围可选择，关闭重开恢复全部', (tester) async {
    Future<List<SearchResult>> search(
      String query, {
      required SearchScope scope,
      required bool recordHistory,
    }) async => <SearchResult>[];
    await pumpSearch(tester, search: search);
    await tester.tap(find.byKey(const ValueKey('search_scope_more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<SearchScope>, 'AI 对话'),
    );
    await tester.pumpAndSettle();
    expect(find.text('搜索范围：AI 对话'), findsOneWidget);
    expect(find.text('输入关键词，在AI 对话中搜索'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpSearch(tester, search: search);
    expect(find.text('搜索范围：全部'), findsOneWidget);
  });

  testWidgets('范围A到B到A，旧请求不能覆盖结果或结束最新加载', (tester) async {
    final pending = <Completer<List<SearchResult>>>[];
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) {
        if (query.isEmpty) return Future.value([]);
        final completer = Completer<List<SearchResult>>();
        pending.add(completer);
        return completer.future;
      },
    );
    await input(tester, '午餐');
    await choose(tester, SearchScope.finance);
    await choose(tester, SearchScope.all);
    expect(pending, hasLength(3));
    pending[0].complete([result('旧全部', SearchResultType.finance)]);
    pending[1].complete([result('旧记账', SearchResultType.finance)]);
    await tester.pump();
    expect(find.text('旧全部', findRichText: true), findsNothing);
    expect(find.text('旧记账', findRichText: true), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending[2].complete([result('新全部', SearchResultType.finance)]);
    await tester.pumpAndSettle();
    expect(find.text('新全部', findRichText: true), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('关键词变化的防抖窗口内旧结果无效，清空也失效', (tester) async {
    final pending = <Completer<List<SearchResult>>>[];
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) {
        if (query.isEmpty) return Future.value([]);
        final completer = Completer<List<SearchResult>>();
        pending.add(completer);
        return completer.future;
      },
    );
    await input(tester, '午餐');
    await tester.enterText(find.byType(TextField), '晚餐');
    pending[0].complete([result('午餐旧结果', SearchResultType.finance)]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('午餐旧结果', findRichText: true), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), '');
    pending[1].complete([result('晚餐旧结果', SearchResultType.finance)]);
    await tester.pumpAndSettle();
    expect(find.text('晚餐旧结果', findRichText: true), findsNothing);
  });

  testWidgets('查询进行中可一键清空且旧结果失效', (tester) async {
    final pending = Completer<List<SearchResult>>();
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) {
        return query.isEmpty ? Future.value([]) : pending.future;
      },
    );
    await choose(tester, SearchScope.finance);
    await input(tester, '午餐');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('清空搜索'));
    pending.complete([result('旧账单', SearchResultType.finance)]);
    await tester.pumpAndSettle();
    expect(find.text('输入关键词，在记账中搜索'), findsOneWidget);
    expect(find.text('旧账单', findRichText: true), findsNothing);
  });

  testWidgets('范围内初始三条和展开全部保持正常', (tester) async {
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) async {
        return query.isEmpty
            ? []
            : [
                for (var i = 0; i < 5; i++)
                  result('午餐账单$i', SearchResultType.finance),
              ];
      },
    );
    await choose(tester, SearchScope.finance);
    await input(tester, '午餐');
    await tester.pumpAndSettle();
    expect(find.text('午餐账单2', findRichText: true), findsOneWidget);
    expect(find.text('午餐账单3', findRichText: true), findsNothing);
    await tester.tap(find.text('查看全部 5 项'));
    await tester.pumpAndSettle();
    expect(find.text('午餐账单4', findRichText: true), findsOneWidget);
  });

  testWidgets('在输入防抖结束前选范围也记录一次搜索历史', (tester) async {
    final calls = <SearchCall>[];
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) async {
        calls.add(SearchCall(query, scope, recordHistory));
        return [];
      },
    );
    await tester.enterText(find.byType(TextField), '午餐');
    await choose(tester, SearchScope.finance);
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.query == '午餐'), hasLength(1));
    expect(calls.last.recordHistory, isTrue);
  });

  testWidgets('远端缓存预热刷新不重复记录历史', (tester) async {
    final remote = Completer<void>();
    final calls = <SearchCall>[];
    await pumpSearch(
      tester,
      warmup: () => remote.future,
      search: (query, {required scope, required recordHistory}) async {
        calls.add(SearchCall(query, scope, recordHistory));
        return [];
      },
    );
    await input(tester, '午餐');
    await tester.pumpAndSettle();
    remote.complete();
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.query == '午餐'), hasLength(2));
    expect(calls.where((call) => call.recordHistory), hasLength(1));
  });

  testWidgets('查询异常可重试且不重复记录历史', (tester) async {
    var attempts = 0;
    final calls = <SearchCall>[];
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) async {
        calls.add(SearchCall(query, scope, recordHistory));
        if (query.isNotEmpty && attempts++ == 0) {
          throw StateError('fixture failure');
        }
        return [];
      },
    );
    await input(tester, '午餐');
    await tester.pumpAndSettle();
    expect(find.text('搜索暂时不可用'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('搜索暂时不可用'), findsNothing);
    expect(calls.last.recordHistory, isFalse);
  });

  testWidgets('详情容器动画和返回保留范围关键词，刷新不记录历史', (tester) async {
    final observer = Routes();
    final calls = <SearchCall>[];
    await pumpSearch(
      tester,
      observer: observer,
      search: (query, {required scope, required recordHistory}) async {
        calls.add(SearchCall(query, scope, recordHistory));
        return query.isEmpty ? [] : [result('午餐账单', SearchResultType.finance)];
      },
    );
    await choose(tester, SearchScope.finance);
    await input(tester, '午餐');
    await tester.pumpAndSettle();
    await tester.tap(find.text('午餐账单', findRichText: true));
    await tester.pumpAndSettle();
    expect(observer.lastPushed, isA<ContainerTransformRoute>());
    expect(find.byType(SearchRecordDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('搜索范围：记账'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '午餐',
    );
    expect(calls.last.scope, SearchScope.finance);
    expect(calls.last.recordHistory, isFalse);
  });

  testWidgets('默认懒加载下详情返回按钮可点击', (tester) async {
    SharedPreferences.setMockInitialValues({
      'enable_animations': true,
      'enable_lazy_load': true,
      'container_content_start': 28,
      'animation_duration': 300,
    });
    await PageTransitions.init();
    await pumpSearch(
      tester,
      search: (query, {required scope, required recordHistory}) async {
        return query.isEmpty ? [] : [result('午餐账单', SearchResultType.finance)];
      },
    );
    await choose(tester, SearchScope.finance);
    await input(tester, '午餐');
    await tester.pumpAndSettle();
    await tester.tap(find.text('午餐账单', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.byType(SearchRecordDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('搜索范围：记账'), findsOneWidget);
    expect(find.byType(SearchRecordDetailScreen), findsNothing);
  });

  for (final config in [
    (size: const Size(320, 640), scale: 1.6, keyboard: 260.0, dark: false),
    (size: const Size(720, 360), scale: 1.4, keyboard: 130.0, dark: true),
    (size: const Size(1280, 900), scale: 2.0, keyboard: 0.0, dark: true),
  ]) {
    testWidgets('界面适配 ${config.size} 字体${config.scale} 键盘${config.keyboard}', (
      tester,
    ) async {
      await pumpSearch(
        tester,
        size: config.size,
        textScale: config.scale,
        keyboard: config.keyboard,
        brightness: config.dark ? Brightness.dark : Brightness.light,
        search: (query, {required scope, required recordHistory}) async =>
            query.isEmpty
            ? []
            : [
                for (var i = 0; i < 5; i++)
                  result('午餐账单$i 内容较长的合成验收记录', SearchResultType.finance),
              ],
      );
      await choose(tester, SearchScope.finance);
      await tester.pumpAndSettle();
      await input(tester, '午餐');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
