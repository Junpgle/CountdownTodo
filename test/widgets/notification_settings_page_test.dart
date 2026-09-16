import 'package:countdown_todo/screens/settings/notification_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('窄屏通知设置不为总开关和子卡片制造大面积留白', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: NotificationSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('通知与提醒设置')).style?.color,
      theme.colorScheme.onSurface,
    );

    final masterCard = find.ancestor(
      of: find.text('实时活动通知'),
      matching: find.byType(AnimatedContainer),
    );
    expect(masterCard, findsOneWidget);
    expect(tester.getSize(masterCard).width, greaterThan(320));

    final childCard = find.ancestor(
      of: find.text('课程实时通知'),
      matching: find.byType(AnimatedContainer),
    );
    expect(childCard, findsOneWidget);
    expect(tester.getSize(childCard).height, lessThan(150));
    expect(tester.takeException(), isNull);
  });
}
