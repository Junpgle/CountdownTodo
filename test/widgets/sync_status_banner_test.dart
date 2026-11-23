import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:countdown_todo/widgets/sync_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettingsStorage.setOfflineModeEnabled(false);
  });

  tearDown(() async {
    await AppSettingsStorage.setOfflineModeEnabled(false);
  });

  testWidgets('hides disconnect banner when offline mode is enabled', (
    tester,
  ) async {
    await AppSettingsStorage.setOfflineModeEnabled(true);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(children: [SyncStatusBanner()]),
        ),
      ),
    );

    // Wait past the 5-second disconnect banner delay.
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('实时通道已断开，正在重连...'), findsNothing);
    expect(find.text('实时同步通道连接失败'), findsNothing);
  });
}
