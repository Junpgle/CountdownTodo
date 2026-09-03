import 'package:countdown_todo/screens/settings/llm_config_page.dart';
import 'package:countdown_todo/services/llm_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('model config keeps text and multimodal selections independent',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final secureValues = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, (call) async {
      final arguments = call.arguments is Map
          ? Map<Object?, Object?>.from(call.arguments as Map)
          : <Object?, Object?>{};
      final key = arguments['key']?.toString();
      switch (call.method) {
        case 'read':
          return secureValues[key];
        case 'write':
          secureValues[key!] = arguments['value']?.toString() ?? '';
          return null;
        case 'delete':
          secureValues.remove(key);
          return null;
        case 'deleteAll':
          secureValues.clear();
          return null;
        case 'containsKey':
          return secureValues.containsKey(key);
        case 'readAll':
          return secureValues;
        case 'isProtectedDataAvailable':
          return true;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(secureStorageChannel, null),
    );

    await LLMService.saveConfig(
      LLMConfig(
        apiKey: 'test-key',
        model: 'glm-4.7-flash',
        visionModel: 'glm-4.6v-flash',
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: LLMConfigPage(isEmbedded: true)),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(DropdownButton<String>).evaluate().length == 2) break;
    }

    final modelDropdowns = find.byType(DropdownButton<String>);
    expect(modelDropdowns, findsNWidgets(2));
    expect(find.text('多模态模型'), findsOneWidget);
    expect(find.text('GLM-4.7-Flash'), findsOneWidget);

    await tester.ensureVisible(modelDropdowns.at(1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(modelDropdowns.at(1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('GLM-4.1V-Thinking-Flash').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('GLM-4.7-Flash'), findsOneWidget);
    expect(find.text('GLM-4.1V-Thinking-Flash'), findsOneWidget);
  });
}
