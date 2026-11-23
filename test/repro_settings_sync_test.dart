import 'package:countdown_todo/screens/home_settings_screen.dart';
import 'package:countdown_todo/screens/settings/widgets/sync_settings_section.dart';
import 'package:countdown_todo/screens/settings/widgets/update_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
    PackageInfo.setMockInitialValues(
      appName: 'CountdownTodo',
      packageName: 'com.example.countdowntodo',
      version: '7.25.0',
      buildNumber: '7.25.0',
      buildSignature: '',
    );
  });

  testWidgets('Wide settings account pane keeps sync section after switching', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'current_user': 'Junpgle'});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }

    expect(find.byType(UpdateSettingsSection), findsOneWidget);
    expect(find.byType(SyncSettingsSection), findsOneWidget);
    expect(find.text('同步与数据策略', skipOffstage: false), findsOneWidget);

    // Switch to another pane and immediately back to account (within 200ms transition)
    await tester.tap(find.text('未成年人模式'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.textContaining('你好，'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(UpdateSettingsSection), findsOneWidget);
    expect(find.byType(SyncSettingsSection), findsOneWidget);
    expect(find.text('同步与数据策略', skipOffstage: false), findsOneWidget);
  });
}
