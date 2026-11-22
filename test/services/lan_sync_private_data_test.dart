import 'package:countdown_todo/services/lan_sync_private_data.dart';
import 'package:countdown_todo/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('mergePortableSettings only syncs whitelisted unset settings', () async {
    SharedPreferences.setMockInitialValues({
      'notify_course_enabled': false,
      'course_reminder_minutes': 20,
      'todo_folder_display_mode': 'grid',
      'app_offline_mode_enabled': true,
      'app_wallpaper_custom_path': '/Users/alice/secret.png',
    });

    final exported = await LanSyncPrivateData.gatherPortableSettings();
    expect(exported['notify_course_enabled'], isFalse);
    expect(exported['course_reminder_minutes'], 20);
    expect(exported['todo_folder_display_mode'], 'grid');
    expect(exported.containsKey('app_offline_mode_enabled'), isFalse);
    expect(exported.containsKey('app_wallpaper_custom_path'), isFalse);

    // Target device has an explicit local override for course_reminder_minutes.
    SharedPreferences.setMockInitialValues({'course_reminder_minutes': 10});
    final merged = await LanSyncPrivateData.mergePortableSettings(exported);
    expect(merged, 2);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notify_course_enabled'), isFalse);
    expect(prefs.getString('todo_folder_display_mode'), 'grid');
    // Existing local override is preserved.
    expect(prefs.getInt('course_reminder_minutes'), 10);
    expect(prefs.containsKey('app_offline_mode_enabled'), isFalse);
  });

  test('mergeSecrets fills missing provider models and custom models', () async {
    await LLMService.saveProviderModels('nvidia_nim', ['meta/llama-3.1-70b']);

    final merged = await LanSyncPrivateData.mergeSecrets({
      'providerModels': {
        'nvidia_nim': ['meta/llama-3.1-70b', 'qwen/qwen2.5-72b'],
      },
    });
    expect(merged, 1);

    final models = await LLMService.getProviderModels('nvidia_nim');
    expect(models, ['meta/llama-3.1-70b', 'qwen/qwen2.5-72b']);
  });
}
