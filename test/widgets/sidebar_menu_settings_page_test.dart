import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/screens/settings/pages/sidebar_menu_settings_page.dart';

void main() {
  testWidgets('an entry can be hidden and restored in sidebar settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(home: SidebarMenuSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('隐藏入口').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('已隐藏'), findsOneWidget);
    expect(find.byTooltip('显示入口'), findsOneWidget);

    await tester.tap(find.byTooltip('显示入口').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('隐藏入口'), findsWidgets);
  });
}
