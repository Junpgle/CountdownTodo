import 'package:countdown_todo/widgets/home_drawer_menu.dart';
import 'package:countdown_todo/widgets/home_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

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

  testWidgets('wide home app bars can expose the drawer button',
      (tester) async {
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
