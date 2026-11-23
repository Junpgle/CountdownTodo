import 'package:countdown_todo/screens/settings/widgets/sync_settings_section.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettingsStorage.setOfflineModeEnabled(false);
  });

  testWidgets('SyncSettingsSection shows confirmation dialog when enabling offline mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SyncSettingsSection(username: 'tester'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('同步与数据策略'), findsOneWidget);
    expect(find.text('离线模式（不走服务器同步）'), findsOneWidget);

    final offlineTile = find.text('离线模式（不走服务器同步）');
    await tester.ensureVisible(offlineTile);
    await tester.tap(offlineTile);
    await tester.pumpAndSettle();

    expect(find.text('确认开启离线模式？'), findsOneWidget);
    expect(find.textContaining('主动断开 WebSocket 实时同步通道'), findsOneWidget);
    expect(find.textContaining('以下功能将无法使用'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(AppSettingsStorage.offlineModeNotifier.value, isFalse);

    await tester.tap(offlineTile);
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认开启'));
    await tester.pumpAndSettle();
    expect(AppSettingsStorage.offlineModeNotifier.value, isTrue);
  });
}
