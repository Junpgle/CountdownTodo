import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_device_context_service.dart';
import 'package:countdown_todo/services/ai_query_tool_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildDefinitions 包含 query_device_context 且可执行查询', () async {
    final definitions = AiQueryToolService.buildDefinitions();
    final deviceTool = definitions.firstWhere(
      (tool) => (tool['function'] as Map)['name'] == 'query_device_context',
    );
    final fn = deviceTool['function'] as Map<String, dynamic>;
    final params = fn['parameters'] as Map<String, dynamic>;
    expect(params['required'], isEmpty);
    expect(
      (params['properties'] as Map<String, dynamic>).containsKey(
        'include_location',
      ),
      isTrue,
    );

    bool? capturedIncludeLocation;
    final service = AiQueryToolService(
      loadAppData: (_) async => const [],
      loadHabitData: (_, _, _) async => const [],
      loadDeviceContext: ({required includeLocation}) async {
        capturedIncludeLocation = includeLocation;
        return {
          'ok': true,
          'local_time': '2026-11-15 20:15:00',
          'timezone_name': 'CST',
          'timezone_offset': '+08:00',
          'location': {
            'supported': true,
            'authorized': true,
            'city': '合肥市',
          },
        };
      },
    );

    final defaultResult = await service.execute(
      const AiChatFunctionCall(
        id: 'call_1',
        name: 'query_device_context',
        arguments: '',
      ),
    );
    expect(capturedIncludeLocation, isTrue);
    expect(defaultResult['ok'], isTrue);
    expect(defaultResult['timezone_name'], 'CST');
    expect((defaultResult['location'] as Map)['city'], '合肥市');

    final noLocationResult = await service.execute(
      const AiChatFunctionCall(
        id: 'call_2',
        name: 'query_device_context',
        arguments: '{"include_location": false}',
      ),
    );
    expect(capturedIncludeLocation, isFalse);
    expect(noLocationResult['ok'], isTrue);
  });

  test('readDeviceContext 返回本地时间与时区并在未授权时安全降级', () async {
    final fixedNow = DateTime(2026, 11, 15, 20, 15, 30);
    final withoutLocation = await AiDeviceContextService.readDeviceContext(
      includeLocation: false,
      nowOverride: fixedNow,
    );
    expect(withoutLocation['ok'], isTrue);
    expect(withoutLocation['local_time'], '2026-11-15 20:15:30');
    expect(withoutLocation['weekday'], '周日');
    expect(withoutLocation['timezone_name'], isNotEmpty);
    expect(withoutLocation['timezone_offset'], isNotEmpty);
    expect(withoutLocation.containsKey('location'), isFalse);

    final deniedLocation = await AiDeviceContextService.readDeviceContext(
      includeLocation: true,
      nowOverride: fixedNow,
      requestPermission: () async => PermissionStatus.denied,
    );
    expect(deniedLocation['ok'], isTrue);
    final location = deniedLocation['location'] as Map<String, dynamic>;
    expect(location['authorized'], isFalse);
    expect(location['message'], isNotEmpty);
  });
}
