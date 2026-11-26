import 'package:countdown_todo/services/power_save_mode_service.dart';
import 'package:countdown_todo/widgets/app_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
