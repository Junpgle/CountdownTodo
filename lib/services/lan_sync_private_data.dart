import 'package:shared_preferences/shared_preferences.dart';

import 'chat_storage_service.dart';
import 'llm_service.dart';

/// Gathers and merges sensitive credentials (API keys, LLM configs) and
/// portable app settings exclusively over the v2 ECDH + AES-256-GCM LAN channel.
class LanSyncPrivateData {
  LanSyncPrivateData._();

  static const List<String> _providerIds = <String>[
    'zhipu',
    'mimo',
    'mimo_token_plan',
    'deepseek',
    'nvidia_nim',
  ];

  static const List<String> _providerModelListIds = <String>[
    'nvidia_nim',
    'deepseek',
    'zhipu',
  ];

  static const List<String> _portableBoolKeys = <String>[
    'notify_live_activity_enabled',
    'notify_normal_enabled',
    'notify_course_enabled',
    'notify_quiz_enabled',
    'notify_todo_summary_enabled',
    'notify_special_todo_enabled',
    'notify_pomodoro_enabled',
    'notify_todo_recognize_enabled',
    'notify_pomodoro_end_enabled',
    'notify_todo_live_enabled',
    'notify_countdown_enabled',
    'notify_reminder_enabled',
    'notify_finance_budget_enabled',
    'notify_finance_recurring_enabled',
    'todo_folders_inline',
    'finance_category_tap_opens_ledger',
    'band_service_enabled',
  ];

  static const List<String> _portableIntKeys = <String>[
    'course_reminder_minutes',
    'category_reminder_minutes',
    'app_wallpaper_index',
  ];

  static const List<String> _portableStringKeys = <String>[
    'todo_folder_display_mode',
    'app_wallpaper_provider',
    'app_wallpaper_image_format',
    'app_wallpaper_mkt',
    'app_wallpaper_resolution',
  ];

  static Future<Map<String, dynamic>> gatherSecrets() async {
    final llmConfig = await LLMService.getConfig();
    final providerApiKeys = <String, String>{};
    for (final provider in _providerIds) {
      final key = (await LLMService.getProviderApiKey(provider)).trim();
      if (key.isNotEmpty) {
        providerApiKeys[provider] = key;
      }
    }

    final providerModels = <String, List<String>>{};
    for (final provider in _providerModelListIds) {
      final models = await LLMService.getProviderModels(provider);
      if (models.isNotEmpty) {
        providerModels[provider] = models;
      }
    }

    final customTextModels = await LLMService.getCustomTextModels();
    final customVisionModels = await LLMService.getCustomVisionModels();
    final chatConfig = await ChatStorageService.getChatConfig();

    return <String, dynamic>{
      if (llmConfig != null && llmConfig.isConfigured)
        'llmConfig': llmConfig.toJson(),
      if (providerApiKeys.isNotEmpty) 'providerApiKeys': providerApiKeys,
      if (providerModels.isNotEmpty) 'providerModels': providerModels,
      if (customTextModels.isNotEmpty)
        'customTextModels': customTextModels.map((m) => m.toJson()).toList(),
      if (customVisionModels.isNotEmpty)
        'customVisionModels': customVisionModels
            .map((m) => m.toJson())
            .toList(),
      if (chatConfig != null &&
          (chatConfig['apiKey']?.trim().isNotEmpty ?? false))
        'chatConfig': chatConfig,
    };
  }

  static Future<int> mergeSecrets(Map<String, dynamic>? remote) async {
    if (remote == null || remote.isEmpty) return 0;
    int mergedCount = 0;

    final rawProviderKeys = remote['providerApiKeys'];
    if (rawProviderKeys is Map) {
      for (final entry in rawProviderKeys.entries) {
        final provider = entry.key.toString().trim();
        final remoteKey = entry.value?.toString().trim() ?? '';
        if (provider.isEmpty || remoteKey.isEmpty) continue;
        final localKey = (await LLMService.getProviderApiKey(provider)).trim();
        if (localKey.isEmpty) {
          await LLMService.saveProviderApiKey(provider, remoteKey);
          mergedCount++;
        }
      }
    }

    final rawProviderModels = remote['providerModels'];
    if (rawProviderModels is Map) {
      for (final entry in rawProviderModels.entries) {
        final provider = entry.key.toString().trim();
        if (provider.isEmpty || entry.value is! List) continue;
        final remoteModels = (entry.value as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (remoteModels.isEmpty) continue;
        final localModels = await LLMService.getProviderModels(provider);
        final combined = <String>[...localModels];
        bool changed = false;
        for (final model in remoteModels) {
          if (!combined.contains(model)) {
            combined.add(model);
            changed = true;
          }
        }
        if (changed) {
          await LLMService.saveProviderModels(provider, combined);
          mergedCount++;
        }
      }
    }

    final rawCustomText = remote['customTextModels'];
    if (rawCustomText is List) {
      final localModels = await LLMService.getCustomTextModels();
      final existingIds = localModels.map((m) => m.id).toSet();
      for (final item in rawCustomText) {
        if (item is! Map) continue;
        final model = CustomTextModel.fromJson(Map<String, dynamic>.from(item));
        if (model.id.isNotEmpty &&
            model.apiKey.isNotEmpty &&
            !existingIds.contains(model.id)) {
          await LLMService.saveCustomTextModel(model);
          existingIds.add(model.id);
          mergedCount++;
        }
      }
    }

    final rawCustomVision = remote['customVisionModels'];
    if (rawCustomVision is List) {
      final localModels = await LLMService.getCustomVisionModels();
      final existingIds = localModels.map((m) => m.id).toSet();
      for (final item in rawCustomVision) {
        if (item is! Map) continue;
        final model = CustomVisionModel.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (model.id.isNotEmpty &&
            model.apiKey.isNotEmpty &&
            !existingIds.contains(model.id)) {
          await LLMService.saveCustomVisionModel(model);
          existingIds.add(model.id);
          mergedCount++;
        }
      }
    }

    final rawLlmConfig = remote['llmConfig'];
    if (rawLlmConfig is Map) {
      final remoteConfig = LLMConfig.fromJson(
        Map<String, dynamic>.from(rawLlmConfig),
      );
      if (remoteConfig.isConfigured) {
        final localConfig = await LLMService.getConfig();
        if (localConfig == null || !localConfig.isConfigured) {
          await LLMService.saveConfig(remoteConfig);
          mergedCount++;
        }
      }
    }

    final rawChatConfig = remote['chatConfig'];
    if (rawChatConfig is Map) {
      final model = rawChatConfig['model']?.toString().trim() ?? '';
      final apiKey = rawChatConfig['apiKey']?.toString().trim() ?? '';
      final apiUrl = rawChatConfig['apiUrl']?.toString().trim();
      final provider = rawChatConfig['provider']?.toString().trim();
      if (model.isNotEmpty && apiKey.isNotEmpty) {
        final localChat = await ChatStorageService.getChatConfig();
        final localKey = localChat?['apiKey']?.trim() ?? '';
        if (localChat == null || localKey.isEmpty) {
          await ChatStorageService.saveChatConfig(
            model: model,
            apiKey: apiKey,
            apiUrl: apiUrl,
            provider: provider,
          );
          mergedCount++;
        }
      }
    }

    return mergedCount;
  }

  static Future<Map<String, dynamic>> gatherPortableSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, dynamic>{};

    for (final key in _portableBoolKeys) {
      if (prefs.containsKey(key)) {
        final val = prefs.getBool(key);
        if (val != null) result[key] = val;
      }
    }
    for (final key in _portableIntKeys) {
      if (prefs.containsKey(key)) {
        final val = prefs.getInt(key);
        if (val != null) result[key] = val;
      }
    }
    for (final key in _portableStringKeys) {
      if (prefs.containsKey(key)) {
        final val = prefs.getString(key);
        if (val != null) result[key] = val;
      }
    }

    return result;
  }

  static Future<int> mergePortableSettings(Map<String, dynamic>? remote) async {
    if (remote == null || remote.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    int mergedCount = 0;

    for (final key in _portableBoolKeys) {
      final val = remote[key];
      if (val is bool && !prefs.containsKey(key)) {
        await prefs.setBool(key, val);
        mergedCount++;
      }
    }
    for (final key in _portableIntKeys) {
      final val = remote[key];
      if (val is int && !prefs.containsKey(key)) {
        await prefs.setInt(key, val);
        mergedCount++;
      }
    }
    for (final key in _portableStringKeys) {
      final val = remote[key];
      if (val is String && !prefs.containsKey(key)) {
        await prefs.setString(key, val);
        mergedCount++;
      }
    }

    return mergedCount;
  }
}
