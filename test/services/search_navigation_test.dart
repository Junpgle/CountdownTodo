import 'dart:async';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/search_record_detail_screen.dart';
import 'package:countdown_todo/screens/animation_settings_page.dart';
import 'package:countdown_todo/services/search_service.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RouteObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;
  Route<dynamic>? lastPopped;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPopped = route;
  }
}

void main() {
  testWidgets('倒计时结果从卡片展开并沿同一路由收回', (tester) async {
    SharedPreferences.setMockInitialValues({
      'enable_animations': true,
      'enable_lazy_load': false,
      'animation_duration': 300,
    });
    await PageTransitions.init();

    final sourceKey = GlobalKey();
    final observer = _RouteObserver();
    final result = SearchResult(
      id: 'db_countdown_test',
      title: '毕业倒计时',
      subtitle: '还有 30 天',
      icon: Icons.timer_outlined,
      type: SearchResultType.countdown,
      extraData: {
        'fields': {'目标日期': '2026-10-25'},
        'detail_label': '倒计时',
      },
    );

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Scaffold(
        body: Builder(builder: (context) {
          return Center(
            child: FilledButton(
              key: sourceKey,
              onPressed: () => unawaited(SearchNavigationHandler.handle(
                context,
                result,
                sourceKey: sourceKey,
              )),
              child: const Text('打开搜索结果'),
            ),
          );
        }),
      ),
    ));

    await tester.tap(find.text('打开搜索结果'));
    await tester.pumpAndSettle();

    final detailRoute = observer.lastPushed;
    expect(detailRoute, isA<ContainerTransformRoute>());
    expect(find.byType(SearchRecordDetailScreen), findsOneWidget);
    expect(find.text('2026-10-25'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(observer.lastPopped, same(detailRoute));
    expect(find.text('打开搜索结果'), findsOneWidget);
  });

  testWidgets('设置搜索结果直接展开目标设置页，返回时收回到结果卡片', (tester) async {
    SharedPreferences.setMockInitialValues({
      'enable_animations': true,
      'enable_lazy_load': false,
      'animation_duration': 300,
    });
    await PageTransitions.init();

    final sourceKey = GlobalKey();
    final observer = _RouteObserver();
    final result = SearchResult(
      id: 'setting_animation',
      title: '动画效果',
      icon: Icons.animation,
      type: SearchResultType.setting,
      extraData: {'route': '/settings', 'target': 'animation'},
    );

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Scaffold(
        body: Builder(
            builder: (context) => Center(
                  child: FilledButton(
                    key: sourceKey,
                    onPressed: () => unawaited(SearchNavigationHandler.handle(
                      context,
                      result,
                      sourceKey: sourceKey,
                    )),
                    child: const Text('打开动画设置'),
                  ),
                )),
      ),
    ));

    await tester.tap(find.text('打开动画设置'));
    await tester.pumpAndSettle();
    final detailRoute = observer.lastPushed;
    expect(detailRoute, isA<ContainerTransformRoute>());
    expect(find.byType(AnimationSettingsPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(observer.lastPopped, same(detailRoute));
    expect(find.text('打开动画设置'), findsOneWidget);
  });
}
