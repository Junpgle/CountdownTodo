import 'package:countdown_todo/screens/settings/pages/account_devices_page.dart';
import 'package:countdown_todo/screens/settings/widgets/account_section.dart';
import 'package:countdown_todo/utils/ai_settings_navigation.dart';
import 'package:countdown_todo/widgets/settings_focus_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AccountSection renders 登录设备管理 and invokes callback', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountSection(
              username: 'alice',
              userId: 1,
              userTier: 'pro',
              syncProgress: 0.2,
              isLoadingStatus: false,
              onRefreshStatus: () {},
              onForceFullSync: () {},
              onLogout: () {},
              onChangePassword: () {},
              onManageDevices: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('登录设备管理'), findsOneWidget);
    await tester.tap(find.text('登录设备管理'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  test('AiSettingsNavigation resolves account_devices destination', () {
    final page = AiSettingsNavigation.pageFor(
      'account_devices',
      username: 'alice',
    );
    expect(page, isA<SettingsFocusPage>());
    expect((page! as SettingsFocusPage).child, isA<AccountDevicesPage>());
  });

  testWidgets('AccountDevicesPage lists devices and kicks via email code', (
    tester,
  ) async {
    var devices = <Map<String, dynamic>>[
      {
        'device_id': 'dev-1',
        'device_name': 'MacBook Pro (PC)',
        'platform': 'macos',
        'app_version': '7.22.6',
        'ip_address': '127.0.0.1',
        'last_seen_at': DateTime.now().millisecondsSinceEpoch,
        'is_current': true,
        'is_online': true,
      },
      {
        'device_id': 'dev-2',
        'device_name': 'Pixel 9 (Phone)',
        'platform': 'android',
        'app_version': '7.22.5',
        'ip_address': '10.0.0.2',
        'last_seen_at': DateTime.now().millisecondsSinceEpoch - 300000,
        'is_current': false,
        'is_online': false,
      },
    ];

    String? sentCodeForDevice;
    String? kickedDevice;
    String? kickedCode;

    await tester.pumpWidget(
      MaterialApp(
        home: AccountDevicesPage(
          syncCurrentDevice: () async {},
          fetchDevices: () async => {
            'success': true,
            'masked_email': 'al***@example.com',
            'devices': devices,
          },
          sendKickCode: (deviceId) async {
            sentCodeForDevice = deviceId;
            return {
              'success': true,
              'message': '验证码已发送',
              'masked_email': 'al***@example.com',
            };
          },
          kickDevice: (deviceId, code) async {
            kickedDevice = deviceId;
            kickedCode = code;
            devices = devices.where((d) => d['device_id'] != deviceId).toList();
            return {'success': true, 'message': '已将该设备踢下线'};
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('MacBook Pro (PC)'), findsOneWidget);
    expect(find.text('Pixel 9 (Phone)'), findsOneWidget);
    expect(find.text('当前设备'), findsOneWidget);
    expect(find.text('踢出'), findsOneWidget);

    await tester.tap(find.text('踢出'));
    await tester.pumpAndSettle();

    expect(find.text('验证邮箱并踢出设备'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);

    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    expect(sentCodeForDevice, 'dev-2');
    expect(find.text('验证码已发送至 al***@example.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('确认踢出'));
    await tester.pumpAndSettle();

    expect(kickedDevice, 'dev-2');
    expect(kickedCode, '123456');
    expect(find.text('Pixel 9 (Phone)'), findsNothing);
    expect(find.text('MacBook Pro (PC)'), findsOneWidget);
  });
}
