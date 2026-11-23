import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/screens/feature_guide_screen.dart';
import 'package:countdown_todo/widgets/changelog_bullet_item.dart';

void main() {
  group('ChangelogBulletItem', () {
    test(
      'resolves distinct bright colors for 新增, 优化, 修复 in light and dark',
      () {
        for (final brightness in Brightness.values) {
          final addStyle = resolveChangelogTagStyle('【新增】功能 A', brightness)!;
          final optStyle = resolveChangelogTagStyle('【优化】性能 B', brightness)!;
          final fixStyle = resolveChangelogTagStyle('【修复】问题 C', brightness)!;

          expect(addStyle.label, '新增');
          expect(optStyle.label, '优化');
          expect(fixStyle.label, '修复');
          expect({addStyle.color, optStyle.color, fixStyle.color}.length, 3);
        }
      },
    );

    testWidgets('renders tag pill and body text cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ChangelogBulletItem(item: '【新增】支持沉浸式底部'),
                ChangelogBulletItem(item: '【优化】列表滚动性能'),
                ChangelogBulletItem(item: '【修复】底部空白问题'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('新增'), findsOneWidget);
      expect(find.text('优化'), findsOneWidget);
      expect(find.text('修复'), findsOneWidget);
      expect(find.textContaining('支持沉浸式底部'), findsOneWidget);
      expect(find.textContaining('列表滚动性能'), findsOneWidget);
      expect(find.textContaining('底部空白问题'), findsOneWidget);
    });
  });

  group('FeatureGuideScreen changelog bottom immersion', () {
    testWidgets(
      'scroll view is not clipped by bottom SafeArea and includes bottom inset padding',
      (tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: const MaterialApp(
              home: FeatureGuideScreen(mode: FeatureGuideMode.changelog),
            ),
          ),
        );
        await tester.pump();

        final safeArea = tester.widget<SafeArea>(
          find
              .descendant(
                of: find.byType(PageView),
                matching: find.byType(SafeArea),
              )
              .first,
        );
        expect(safeArea.bottom, isFalse);

        final scrollView = tester.widget<SingleChildScrollView>(
          find
              .descendant(
                of: find.byType(PageView),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );
        final resolvedPadding = scrollView.padding as EdgeInsets;
        expect(resolvedPadding.bottom, greaterThan(24));
      },
    );
  });
}
