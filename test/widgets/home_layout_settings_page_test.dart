import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/screens/settings/pages/home_layout_settings_page.dart';

void main() {
  testWidgets('wide settings only show wide layout groups', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(1000, 800)),
        child: MaterialApp(home: HomeLayoutSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('左栏'), findsOneWidget);
    expect(find.text('右栏'), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(find.text('专注'), findsNothing);
    expect(find.textContaining('仅显示宽屏布局'), findsOneWidget);
  });

  testWidgets('mobile settings only show mobile layout groups', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(home: HomeLayoutSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('仅显示手机布局'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('专注'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('专注'), findsOneWidget);
    expect(find.text('左栏'), findsNothing);
    expect(find.text('右栏'), findsNothing);
  });

  testWidgets('moving a component between groups keeps the list tree stable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(home: HomeLayoutSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    final moveToFocus = find.byIcon(Icons.arrow_forward_rounded).first;

    await tester.scrollUntilVisible(
      moveToFocus,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(moveToFocus);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('顶部横幅'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('顶部横幅'), findsOneWidget);
  });

  testWidgets('a component can be hidden without leaving the settings list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(home: HomeLayoutSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byTooltip('隐藏组件').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('隐藏组件').first);
    await tester.pumpAndSettle();

    expect(find.text('已隐藏 · 第 1 位'), findsOneWidget);
    expect(find.byTooltip('显示组件'), findsOneWidget);
  });
}
