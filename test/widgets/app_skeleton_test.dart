import 'package:countdown_todo/services/animation_config_service.dart';
import 'package:countdown_todo/services/power_save_mode_service.dart';
import 'package:countdown_todo/widgets/app_skeleton.dart';
import 'package:countdown_todo/widgets/app_state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSkeletonScope & primitives', () {
    testWidgets('renders in light and dark Material 3 themes', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: brightness,
              ),
              useMaterial3: true,
            ),
            home: const Scaffold(
              body: AppSkeletonScope(
                child: Column(
                  children: [
                    AppSkeletonLine(width: 120, height: 14),
                    SizedBox(height: 8),
                    AppSkeletonCircle(size: 36),
                    SizedBox(height: 8),
                    AppSkeletonCard(child: AppSkeletonBox(height: 40)),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(AppSkeletonScope), findsOneWidget);
        expect(find.byType(AppSkeletonBox), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'degrades shimmer to static tonal blocks when disableAnimations is true',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: AppSkeletonScope(
                  child: Column(
                    children: [
                      AppSkeletonLine(width: 140, height: 14),
                      SizedBox(height: 8),
                      AppSkeletonCircle(size: 36),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        expect(SchedulerBinding.instance.transientCallbackCount, 0);
        await tester.pumpAndSettle();
        expect(find.byType(AppSkeletonBox), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'stops ticker cleanly when PowerSaveModeService is active or animate=false',
      (tester) async {
        expect(PowerSaveModeService.isEnabled, isFalse);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AppSkeletonScope(
                animate: false,
                child: AppSkeletonBox(width: 100, height: 24),
              ),
            ),
          ),
        );

        expect(SchedulerBinding.instance.transientCallbackCount, 0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('AppSkeleton presets responsive & shrinkWrap checks', () {
    final presets = <String, Widget Function({required bool shrinkWrap})>{
      'AppSkeletonListPage': ({required shrinkWrap}) => AppSkeletonListPage(
        shrinkWrap: shrinkWrap,
        showHeroCard: true,
        showSearchBar: true,
        showFilterChips: true,
        useTwoColumnsOnWide: true,
      ),
      'AppSkeletonDashboardPage': ({required shrinkWrap}) =>
          AppSkeletonDashboardPage(
            shrinkWrap: shrinkWrap,
            showPeriodHeader: true,
            showFilterChips: true,
            showMetricGrid: true,
            showChart: true,
          ),
      'AppSkeletonCalendarPage': ({required shrinkWrap}) =>
          AppSkeletonCalendarPage(shrinkWrap: shrinkWrap),
      'AppSkeletonFormPage': ({required shrinkWrap}) =>
          AppSkeletonFormPage(shrinkWrap: shrinkWrap, showAmountHeader: true),
      'AppSkeletonSettingsPage': ({required shrinkWrap}) =>
          AppSkeletonSettingsPage(
            shrinkWrap: shrinkWrap,
            twoColumnOnWide: true,
          ),
      'AppSkeletonSettingsSection': ({required shrinkWrap}) =>
          const AppSkeletonSettingsSection(),
      'AppSkeletonSheetList': ({required shrinkWrap}) =>
          AppSkeletonSheetList(shrinkWrap: shrinkWrap),
      'AppSkeletonDocument': ({required shrinkWrap}) =>
          AppSkeletonDocument(shrinkWrap: shrinkWrap),
    };

    for (final entry in presets.entries) {
      for (final viewport in [const Size(360, 640), const Size(1280, 800)]) {
        for (final shrinkWrap in [false, true]) {
          testWidgets(
            '${entry.key} renders without overflow at ${viewport.width.toInt()}x${viewport.height.toInt()} (shrinkWrap=$shrinkWrap)',
            (tester) async {
              tester.view.physicalSize = viewport;
              tester.view.devicePixelRatio = 1.0;
              addTearDown(() {
                tester.view.resetPhysicalSize();
                tester.view.resetDevicePixelRatio();
              });

              final widget = entry.value(shrinkWrap: shrinkWrap);
              await tester.pumpWidget(
                MaterialApp(
                  home: MediaQuery(
                    data: const MediaQueryData(disableAnimations: true),
                    child: Scaffold(
                      body: shrinkWrap
                          ? SingleChildScrollView(child: widget)
                          : widget,
                    ),
                  ),
                ),
              );
              await tester.pump();

              expect(find.byType(AppSkeletonScope), findsOneWidget);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('Tablet & wide viewport skeleton differentiation', () {
    Future<void> pumpViewport(
      WidgetTester tester,
      Size size,
      Widget child, {
      double? maxConstraintWidth,
      bool wrapInScrollView = false,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Widget content = child;
      if (maxConstraintWidth != null) {
        content = Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: maxConstraintWidth, child: content),
        );
      }
      if (wrapInScrollView) {
        content = SingleChildScrollView(child: content);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(body: content),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'AppSkeletonListPage adapts columns by available width (including narrow pane inside tablet)',
      (tester) async {
        const photoWallSkeleton = AppSkeletonListPage(
          useTwoColumnsOnWide: true,
          wideBreakpoint: 900,
          narrowColumns: 2,
          wideColumns: 4,
          itemCount: 8,
        );

        await pumpViewport(tester, const Size(360, 640), photoWallSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-list-grid-2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-list-grid-4')),
          findsNothing,
        );

        await pumpViewport(tester, const Size(1280, 800), photoWallSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-list-grid-4')),
          findsOneWidget,
        );

        // Constrained embedded pane (360px wide inside a 1280px tablet screen)
        // must follow LayoutBuilder constraints, not full window width.
        await pumpViewport(
          tester,
          const Size(1280, 800),
          const AppSkeletonListPage(
            useTwoColumnsOnWide: true,
            wideBreakpoint: 640,
            itemCount: 4,
          ),
          maxConstraintWidth: 360,
        );
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-list-grid-2')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AppSkeletonDashboardPage renders splitColumns and metricsAndGrid on tablet',
      (tester) async {
        const splitSkeleton = AppSkeletonDashboardPage(
          wideLayout: AppSkeletonDashboardWideLayout.splitColumns,
          wideBreakpoint: 900,
          showTopHeaderSpan: true,
          wideListColumns: 3,
          listCount: 6,
        );

        await pumpViewport(tester, const Size(360, 640), splitSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-dashboard-split')),
          findsNothing,
        );

        await pumpViewport(tester, const Size(1280, 800), splitSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-dashboard-split')),
          findsOneWidget,
        );

        const gridSkeleton = AppSkeletonDashboardPage(
          wideLayout: AppSkeletonDashboardWideLayout.metricsAndGrid,
          wideBreakpoint: 640,
          wideListColumns: 2,
          listCount: 4,
        );

        await pumpViewport(tester, const Size(360, 640), gridSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-dashboard-grid')),
          findsNothing,
        );

        await pumpViewport(tester, const Size(1280, 800), gridSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-dashboard-grid')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AppSkeletonCalendarPage splits calendar and day detail on tablet',
      (tester) async {
        const calendarSkeleton = AppSkeletonCalendarPage(
          splitOnWide: true,
          wideBreakpoint: 600,
        );

        await pumpViewport(tester, const Size(360, 640), calendarSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-calendar-split')),
          findsNothing,
        );

        await pumpViewport(tester, const Size(1280, 800), calendarSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-calendar-split')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AppSkeletonFormPage switches to wide header and 2-column fields on tablet',
      (tester) async {
        const formSkeleton = AppSkeletonFormPage(
          maxWidth: 1180,
          twoColumnOnWide: true,
          showPreviewHeaderOnWide: true,
          showStepperHeaderOnWide: true,
          wideBreakpoint: 760,
          fieldCount: 4,
        );

        await pumpViewport(tester, const Size(360, 640), formSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-form-wide')),
          findsNothing,
        );

        await pumpViewport(tester, const Size(1280, 800), formSkeleton);
        expect(
          find.byKey(const ValueKey<String>('app-skeleton-form-wide')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AppSkeletonSettingsPage renders master-detail split on tablet',
      (tester) async {
        for (final shrinkWrap in [false, true]) {
          final settingsSkeleton = AppSkeletonSettingsPage(
            masterDetailOnWide: true,
            masterDetailBreakpoint: 800,
            shrinkWrap: shrinkWrap,
          );

          await pumpViewport(
            tester,
            const Size(360, 640),
            settingsSkeleton,
            wrapInScrollView: shrinkWrap,
          );
          expect(
            find.byKey(
              const ValueKey<String>('app-skeleton-settings-master-detail'),
            ),
            findsNothing,
          );

          await pumpViewport(
            tester,
            const Size(1280, 800),
            settingsSkeleton,
            wrapInScrollView: shrinkWrap,
          );
          expect(
            find.byKey(
              const ValueKey<String>('app-skeleton-settings-master-detail'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'AppSkeletonScope switches to AppLoadingView when skeleton setting is disabled',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await AnimationConfigService.setSkeletonScreenEnabled(true);
        addTearDown(() async {
          await AnimationConfigService.setSkeletonScreenEnabled(true);
        });

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AppSkeletonListPage())),
        );
        await tester.pump();

        expect(find.byType(AppSkeletonCard), findsWidgets);
        expect(find.byType(AppLoadingView), findsNothing);

        await AnimationConfigService.setSkeletonScreenEnabled(false);
        await tester.pump();

        expect(find.byType(AppLoadingView), findsOneWidget);
        expect(find.byType(AppSkeletonCard), findsNothing);

        await AnimationConfigService.setSkeletonScreenEnabled(true);
        await tester.pump();

        expect(find.byType(AppSkeletonCard), findsWidgets);
        expect(find.byType(AppLoadingView), findsNothing);
      },
    );
  });
}
