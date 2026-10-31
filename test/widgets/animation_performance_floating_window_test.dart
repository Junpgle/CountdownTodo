import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/screens/animation_settings_page.dart';
import 'package:countdown_todo/services/animation_performance_monitor_service.dart';
import 'package:countdown_todo/utils/navigator_utils.dart';
import 'package:countdown_todo/widgets/animation_performance_floating_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AnimationPerformanceMonitorService.resetForTesting();
    AnimationPerformanceMonitorService.testRefreshRate = 60.0;
    addTearDown(AnimationPerformanceMonitorService.resetForTesting);
  });

  group('AnimationPerformanceMonitorService Unit Tests', () {
    test('show, hide, and toggle floating window state', () {
      expect(AnimationPerformanceMonitorService.isFloatingActive, isFalse);
      expect(AnimationPerformanceMonitorService.isExpanded, isFalse);

      AnimationPerformanceMonitorService.showFloating();
      expect(AnimationPerformanceMonitorService.isFloatingActive, isTrue);
      expect(AnimationPerformanceMonitorService.isExpanded, isFalse);

      AnimationPerformanceMonitorService.setExpanded(true);
      expect(AnimationPerformanceMonitorService.isExpanded, isTrue);

      AnimationPerformanceMonitorService.toggleExpanded();
      expect(AnimationPerformanceMonitorService.isExpanded, isFalse);

      AnimationPerformanceMonitorService.hideFloating();
      expect(AnimationPerformanceMonitorService.isFloatingActive, isFalse);

      AnimationPerformanceMonitorService.toggleFloating();
      expect(AnimationPerformanceMonitorService.isFloatingActive, isTrue);
    });

    test('recordTimingsForTesting updates metrics snapshot', () {
      final timingGood = FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 2000,
        rasterStart: 2100,
        rasterFinish: 5100,
        rasterFinishWallTime: 5100,
      );
      final timingBad = FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 16000,
        rasterStart: 16100,
        rasterFinish: 28100,
        rasterFinishWallTime: 28100,
      );

      AnimationPerformanceMonitorService.recordTimingsForTesting([
        timingGood,
        timingBad,
      ]);

      final snapshot = AnimationPerformanceMonitorService.currentSnapshot;
      expect(snapshot.targetRefreshRate, 60.0);
      expect(snapshot.smoothnessPercent, 50.0);
      expect(snapshot.jankCount, 1);
      expect(snapshot.currentFps, closeTo(30.0, 0.1));
    });
  });

  group('AnimationPerformanceFloatingWindow Widget Tests', () {
    testWidgets(
      'hidden when inactive and renders compact capsule when active',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Center(child: Text('Underlying Screen Content')),
                  Positioned.fill(child: AnimationPerformanceFloatingWindow()),
                ],
              ),
            ),
          ),
        );

        // 默认未开启时无内容
        expect(
          find.byKey(const ValueKey('animation-performance-floating-capsule')),
          findsNothing,
        );
        expect(find.text('Underlying Screen Content'), findsOneWidget);

        // 开启悬浮窗
        AnimationPerformanceMonitorService.showFloating();
        await tester.pumpAndSettle();

        // 呈现紧凑胶囊
        expect(
          find.byKey(const ValueKey('animation-performance-floating-capsule')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('animation-performance-floating-fps-capsule'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('expand to full card and collapse back to capsule', (
      tester,
    ) async {
      AnimationPerformanceMonitorService.showFloating();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: AnimationPerformanceFloatingWindow()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击胶囊展开按钮
      final expandBtn = find.byKey(
        const ValueKey('animation-performance-floating-expand-btn'),
      );
      expect(expandBtn, findsOneWidget);
      await tester.tap(expandBtn);
      await tester.pumpAndSettle();

      // 验证已展开为详情面板
      expect(
        find.byKey(
          const ValueKey('animation-performance-floating-expanded-card'),
        ),
        findsOneWidget,
      );
      expect(find.text('实时性能监控'), findsOneWidget);
      expect(find.text('实时帧率'), findsOneWidget);
      expect(find.text('渲染耗时'), findsOneWidget);
      expect(find.text('综合负载压力'), findsOneWidget);
      expect(find.textContaining('开启较多特效可能会导致卡顿'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('animation-performance-floating-go-settings-btn'),
        ),
        findsOneWidget,
      );

      // 点击收起图标
      final collapseBtn = find.byIcon(Icons.close_fullscreen_rounded);
      expect(collapseBtn, findsOneWidget);
      await tester.tap(collapseBtn);
      await tester.pumpAndSettle();

      // 验证回到紧凑胶囊
      expect(
        find.byKey(const ValueKey('animation-performance-floating-capsule')),
        findsOneWidget,
      );
    });

    testWidgets('close button hides floating window', (tester) async {
      AnimationPerformanceMonitorService.showFloating();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: AnimationPerformanceFloatingWindow()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final closeBtn = find.byKey(
        const ValueKey('animation-performance-floating-close-btn'),
      );
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(AnimationPerformanceMonitorService.isFloatingActive, isFalse);
      expect(
        find.byKey(const ValueKey('animation-performance-floating-capsule')),
        findsNothing,
      );
    });

    testWidgets('dragging floating window updates its position', (
      tester,
    ) async {
      AnimationPerformanceMonitorService.showFloating();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: AnimationPerformanceFloatingWindow()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final capsuleFinder = find.byKey(
        const ValueKey('animation-performance-floating-capsule'),
      );
      final initialOffset = tester.getTopLeft(capsuleFinder);

      // 拖拽悬浮窗
      await tester.drag(capsuleFinder, const Offset(-40, 50));
      await tester.pumpAndSettle();

      final movedOffset = tester.getTopLeft(capsuleFinder);
      expect(movedOffset.dx, lessThan(initialOffset.dx));
      expect(movedOffset.dy, greaterThan(initialOffset.dy));
    });

    testWidgets(
      'tapping underlying screen outside floating window still responds',
      (tester) async {
        int underlyingTapCount = 0;
        AnimationPerformanceMonitorService.showFloating();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Center(
                    child: ElevatedButton(
                      onPressed: () => underlyingTapCount++,
                      child: const Text('Underlying Button'),
                    ),
                  ),
                  const Positioned.fill(
                    child: AnimationPerformanceFloatingWindow(),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 点击底层的按钮
        await tester.tap(find.text('Underlying Button'));
        await tester.pumpAndSettle();

        // 验证底层按钮成功响应点击
        expect(underlyingTapCount, 1);
      },
    );
  });

  group('AnimationPerformanceMetricCard Floating Controls Integration', () {
    testWidgets(
      'toggle chip and navigate button in settings card trigger floating',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: appNavigatorKey,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AnimationSettingsPage(),
                          ),
                        );
                      },
                      child: const Text('Open Settings'),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // 打开动画设置页
        await tester.tap(find.text('Open Settings'));
        await tester.pumpAndSettle();

        // 默认处于收起状态，点击展开负载压力卡片展示操作与数值
        final expandBtn = find.byKey(
          const ValueKey('animation-performance-expand-btn'),
        );
        expect(expandBtn, findsOneWidget);
        await tester.tap(expandBtn);
        await tester.pumpAndSettle();

        // 验证展开后悬浮控制按钮存在
        final toggleChip = find.byKey(
          const ValueKey('animation-performance-float-toggle-chip'),
        );
        final navigateBtn = find.byKey(
          const ValueKey('animation-performance-float-navigate-btn'),
        );
        expect(toggleChip, findsOneWidget);
        expect(navigateBtn, findsOneWidget);

        // 点击开启悬浮窗
        await tester.tap(toggleChip);
        await tester.pumpAndSettle();
        expect(AnimationPerformanceMonitorService.isFloatingActive, isTrue);

        // 点击带到其他页面测试：激活并返回上一页
        await tester.tap(navigateBtn);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        expect(AnimationPerformanceMonitorService.isFloatingActive, isTrue);
        // 返回了上一页
        expect(find.text('Open Settings'), findsOneWidget);
      },
    );
  });
}
