import 'dart:convert';

import 'package:countdown_todo/screens/help/help_center_screen.dart';
import 'package:countdown_todo/screens/home_settings_screen.dart';
import 'package:countdown_todo/screens/settings/pages/preference_settings_page.dart';
import 'package:countdown_todo/screens/settings/pages/interconnect_settings_page.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

Finder _navigationSource(String id) => find.byWidgetPredicate(
  (widget) =>
      widget.key is GlobalKey &&
      widget.key.toString().contains('settings-$id]'),
);

Future<void> _finishSettingsLoad(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  // Package/cache sections probe the filesystem outside the fake test clock.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pumpAndSettle();
}

Future<ContainerTransformRoute<dynamic>> _openFromSource(
  WidgetTester tester,
  Finder source,
  _RouteObserver observer,
) async {
  await Scrollable.ensureVisible(tester.element(source), alignment: 0.35);
  await tester.pumpAndSettle();
  final sourceRect = tester.getRect(source);
  final routeCount = observer.routes.length;
  await tester.tap(source);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  expect(observer.routes, hasLength(routeCount + 1));
  final route = observer.routes.last;
  expect(route, isA<ContainerTransformRoute<dynamic>>());
  final transform = route as ContainerTransformRoute<dynamic>;
  expect(transform.sourceRect, sourceRect);
  return transform;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'enable_animations': true,
      'enable_lazy_load': true,
      'update_manifest_cache_time': DateTime.now().millisecondsSinceEpoch,
      'update_manifest_cache_json': jsonEncode({
        'version_name': '6.4.35',
        'version_code': 1,
        'update_info': {'title': '测试更新', 'description': '测试更新'},
      }),
    });
    PackageInfo.setMockInitialValues(
      appName: 'CountdownTodo',
      packageName: 'test.settings',
      version: '6.4.35',
      buildNumber: '1',
      buildSignature: '',
    );
    PageTransitions.setPowerSaveMode(false);
    await PageTransitions.init();
  });

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('portrait settings categories expand from each tapped row', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const SettingsPage(),
      ),
    );
    await _finishSettingsLoad(tester);
    for (final id in [
      'minor_mode',
      'preference',
      'animation',
      'course',
      'interconnect',
      'llm_config',
      'ai_assistant',
      'platform',
      'notifications',
      'permissions',
      'help',
      'about',
    ]) {
      final source = _navigationSource(id);
      expect(source, findsOneWidget, reason: id);
      final route = await _openFromSource(tester, source, observer);
      // Return before constructing unrelated destination services.
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(route.sourceRect, tester.getRect(source));
    }
    final serverSource = find
        .ancestor(
          of: find.text('云端数据接口线路'),
          matching: find.byType(KeyedSubtree),
        )
        .first;
    final serverRoute = await _openFromSource(tester, serverSource, observer);
    expect(serverRoute.settings.name, '云端数据接口线路');
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('landscape settings keep pane selection and nested breadcrumbs', (
    tester,
  ) async {
    await setSize(tester, const Size(1280, 800));
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const SettingsPage(),
      ),
    );
    await _finishSettingsLoad(tester);
    final rootRouteCount = observer.routes.length;
    await tester.tap(find.text('数据与互联'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MCP 接入'));
    await tester.pumpAndSettle();
    expect(observer.routes, hasLength(rootRouteCount));
    expect(find.text('MCP 接入说明'), findsOneWidget);
    expect(find.text('MCP（模型上下文协议）'), findsOneWidget);
    await tester.tap(find.text('设置 > 数据与互联'));
    await tester.pumpAndSettle();
    expect(find.text('MCP 接入说明'), findsNothing);
    expect(find.text('MCP 接入'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'preference advanced buttons and previews keep separate sources',
    (tester) async {
      await setSize(tester, const Size(390, 844));
      final navigatorKey = GlobalKey<NavigatorState>();
      final observer = _RouteObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [observer],
          home: const PreferenceSettingsPage(),
        ),
      );
      await _finishSettingsLoad(tester);
      for (final entry in {
        'wallpaper_advanced': '首页壁纸设置',
        'home_text_advanced': '首页文字自定义',
        'home_text_preview': '首页文字自定义',
        'home_layout_advanced': '首页布局',
        'home_layout_preview': '首页布局',
        'sidebar_menu_advanced': '侧边栏菜单',
        'sidebar_menu_preview': '侧边栏菜单',
      }.entries) {
        final source = _navigationSource(entry.key);
        final route = await _openFromSource(tester, source, observer);
        expect(route.settings.name, entry.value);
        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(source, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('portrait data tools expand from their own cards', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const InterconnectSettingsPage(username: 'tester'),
      ),
    );
    await tester.pumpAndSettle();
    for (final entry in {
      'MCP 接入': 'MCP 接入说明',
      '局域网同步': '局域网互传与同步',
      '写入手机系统日历': '日历同步向导',
      '批量标签': '批量添加标签',
      '重复待办合并': '合并重复待办',
      '数据导出': '数据导出',
      '数据导入': '数据导入',
    }.entries) {
      final source = find
          .ancestor(
            of: find.text(entry.key),
            matching: find.byWidgetPredicate(
              (widget) => widget is Container && widget.key is GlobalKey,
            ),
          )
          .first;
      final route = await _openFromSource(tester, source, observer);
      expect(route.settings.name, entry.value);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('help articles expand from the corresponding settings entry', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const HelpCenterScreen(),
      ),
    );
    for (final title in ['习惯中心', '小组件与桌面功能']) {
      final source = find.ancestor(
        of: find.text(title),
        matching: find.byType(ListTile),
      );
      await _openFromSource(tester, source, observer);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
