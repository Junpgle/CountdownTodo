import 'dart:convert';

import 'package:countdown_todo/screens/home_settings_screen.dart';
import 'package:countdown_todo/services/sidebar_menu_service.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:countdown_todo/widgets/home_drawer_menu.dart';
import 'package:countdown_todo/widgets/home_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DrawerRouteObserver extends NavigatorObserver {
  final List<ContainerTransformRoute<void>> transforms = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ContainerTransformRoute<void>) transforms.add(route);
  }
}

HomeDrawerMenu _drawerMenu({
  required GlobalKey key,
  required Future<void> Function(String id, GlobalKey sourceKey) onNavigate,
}) => HomeDrawerMenu(
  key: key,
  username: 'drawer-user',
  timeSalutation: '晚上好',
  onSettings: (key) => onNavigate('settings', key),
  onOpenUpdateSettings: (key) => onNavigate('updateSettings', key),
  onAiAssistant: (key) => onNavigate('aiAssistant', key),
  onTeams: (key) => onNavigate('teams', key),
  onFinance: (key) => onNavigate('finance', key),
  onChangelog: (key) => onNavigate('changelog', key),
  onChallengeCenter: (key) => onNavigate('challengeCenter', key),
  onUpdate: (key) => onNavigate('update', key),
  onTimeline: (key) => onNavigate('timeline', key),
  onJournal: (key) => onNavigate('journal', key),
  onScreenTime: (key) => onNavigate('screenTime', key),
  onPlanCenter: (key) => onNavigate('planCenter', key),
  onHabits: (key) => onNavigate('habits', key),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'current_username': 'drawer-user',
      'enable_animations': true,
      'update_manifest_cache_time': DateTime.now().millisecondsSinceEpoch,
      'update_manifest_cache_json': jsonEncode({
        'version_name': '9.0.0',
        'version_code': 900,
        'update_info': {'title': '测试更新', 'description': '测试更新'},
      }),
    });
    PackageInfo.setMockInitialValues(
      appName: 'CountdownTodo',
      packageName: 'test.drawer',
      version: '6.4.35',
      buildNumber: '1',
      buildSignature: '',
    );
    PageTransitions.setPowerSaveMode(false);
    await PageTransitions.init();
  });

  for (final configuration in ['phone', 'wide-dark', 'regrouped']) {
    testWidgets(
      '$configuration drawer entries expand and return to their row',
      (tester) async {
        final isWide = configuration == 'wide-dark';
        tester.view.physicalSize = isWide
            ? const Size(1440, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (configuration == 'regrouped') {
          await SidebarMenuService.savePair(
            features: ['update', 'journal'],
            utilities: SidebarMenuService.allKeys().reversed.where(
              (key) => key != 'update' && key != 'journal',
            ),
          );
          await SidebarMenuService.saveVisibility({'finance': false});
        }

        final navigatorKey = GlobalKey<NavigatorState>();
        final drawerKey = GlobalKey();
        final drawerController = ZoomDrawerController();
        final observer = _DrawerRouteObserver();
        final sourceKeys = <String, GlobalKey>{};
        final calls = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [observer],
            theme: ThemeData(
              brightness: isWide ? Brightness.dark : Brightness.light,
              pageTransitionsTheme: PageTransitions.theme,
            ),
            home: ZoomDrawer(
              controller: drawerController,
              slideWidth: homeDrawerSlideWidthFor(
                screenWidth: isWide ? 1440 : 390,
                isWide: isWide,
              ),
              menuScreenWidth: isWide ? 360 : null,
              angle: 0,
              menuScreen: _drawerMenu(
                key: drawerKey,
                onNavigate: (id, sourceKey) async {
                  calls.add(id);
                  sourceKeys[id] = sourceKey;
                  await PageTransitions.pushFromRect<void>(
                    context: drawerKey.currentContext!,
                    sourceKey: sourceKey,
                    page: Scaffold(
                      body: Center(child: Text('destination-$id')),
                    ),
                  );
                },
              ),
              mainScreen: const Scaffold(body: Text('home')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        drawerController.open!();
        await tester.pumpAndSettle();

        final entries = {
          for (final definition in SidebarMenuService.definitions.values)
            if (configuration != 'regrouped' || definition.key != 'finance')
              definition.key: definition.title,
          'settings': '设置中心',
          'updateSettings': '发现新版本！',
        };
        if (configuration == 'regrouped') {
          expect(find.text('记账'), findsNothing);
        }
        for (final entry in entries.entries) {
          final titleFinder = find.text(entry.value);
          await tester.ensureVisible(titleFinder);
          await tester.pumpAndSettle();
          final sourceFinder = find
              .ancestor(
                of: titleFinder,
                matching: find.byType(
                  entry.key == 'updateSettings' ? InkWell : Material,
                ),
              )
              .first;
          final sourceRect = tester.getRect(sourceFinder);
          final previousCount = observer.transforms.length;
          await tester.tap(titleFinder);
          // Two taps before the async route push must still open only one page.
          await tester.tap(titleFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 20));
          await tester.pump();

          expect(observer.transforms, hasLength(previousCount + 1));
          expect(calls.where((id) => id == entry.key), hasLength(1));
          final route = observer.transforms.last;
          expect(route.sourceRect, sourceRect);
          final sourceKey = sourceKeys[entry.key]!;
          expect(sourceKey.currentContext, isNotNull);
          expect(drawerController.isOpen!(), isTrue);
          await tester.pumpAndSettle();
          expect(find.text('destination-${entry.key}'), findsOneWidget);

          navigatorKey.currentState!.pop();
          await tester.pump();
          expect(route.animation!.status, AnimationStatus.reverse);
          await tester.pump(
            route.reverseTransitionDuration - const Duration(milliseconds: 1),
          );
          final container = tester.widget<Positioned>(
            find
                .byWidgetPredicate(
                  (widget) => widget is Positioned && widget.child is ClipRRect,
                )
                .last,
          );
          expect(container.left, closeTo(sourceRect.left, 1));
          expect(container.top, closeTo(sourceRect.top, 1));
          expect(container.width, closeTo(sourceRect.width, 1));
          expect(container.height, closeTo(sourceRect.height, 1));
          await tester.pumpAndSettle();
          expect(find.text('destination-${entry.key}'), findsNothing);
          expect(drawerController.isOpen!(), isTrue);
          expect(tester.getRect(find.byKey(sourceKey)), sourceRect);
        }
        expect(sourceKeys.values.toSet(), hasLength(entries.length));
      },
    );
  }

  for (final returnEarly in [false, true]) {
    testWidgets(
      returnEarly
          ? 'returning during update entrance cancels the manual check'
          : 'manual update check waits for the container entrance',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('enable_lazy_load', false);
        await prefs.setString(
          'update_manifest_cache_json',
          jsonEncode({'version_name': '6.4.35', 'version_code': 6435}),
        );
        await PageTransitions.init();
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            theme: ThemeData(pageTransitionsTheme: PageTransitions.theme),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    ContainerTransformRoute<void>(
                      page: const SettingsPage(
                        initialTarget: 'update',
                        checkUpdatesOnOpen: true,
                      ),
                      sourceRect: const Rect.fromLTWH(28, 240, 220, 52),
                      sourceColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  child: const Text('检查更新'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('检查更新'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(find.text('检查完成'), findsNothing);

        if (returnEarly) navigatorKey.currentState!.pop();
        await tester.pump(const Duration(milliseconds: 500));
        // Settings also probes downloaded packages using filesystem I/O.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('检查完成'), returnEarly ? findsNothing : findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  test('keeps phone drawer proportional and caps wide drawer width', () {
    expect(
      homeDrawerSlideWidthFor(screenWidth: 390, isWide: false),
      closeTo(280.8, 0.001),
    );
    expect(
      homeDrawerSlideWidthFor(screenWidth: 768, isWide: true),
      closeTo(307.2, 0.001),
    );
    expect(
      homeDrawerSlideWidthFor(screenWidth: 1440, isWide: true),
      closeTo(360, 0.001),
    );
  });

  testWidgets('wide home app bars can expose the drawer button', (
    tester,
  ) async {
    final menuKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: HomeAppBar(
            username: 'Test user',
            timeSalutation: '晚上好',
            currentGreeting: '祝你今天一切顺利！',
            isLight: false,
            isSyncing: false,
            onSync: () {},
            onSettings: () {},
            menuKey: menuKey,
            showMenuButton: true,
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    expect(find.byKey(menuKey), findsOneWidget);
  });
}
