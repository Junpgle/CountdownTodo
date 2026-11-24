part of '../llm_config_page.dart';

extension _LLMConfigLogic on _LLMConfigPageState {
  Future<void> _authorizeAndLoadConfig() async {
    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.llmConfiguration,
    );
    if (!authorized) {
      if (mounted) {
        _mutateState(() {
          _accessDenied = true;
          _isLoading = false;
        });
      }
      return;
    }
    await _loadConfig();
    if (!{
      'llm_custom_text',
      'llm_custom_vision',
    }.contains(widget.initialTarget)) {
      return;
    }
    for (var frame = 0; frame < 90 && mounted; frame++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null ||
          (route.isCurrent &&
              !route.offstage &&
              (route.animation == null ||
                  route.animation!.status == AnimationStatus.completed))) {
        if (widget.initialTarget == 'llm_custom_text') {
          _showAddCustomTextModelDialog();
        } else {
          _showAddCustomVisionModelDialog();
        }
        return;
      }
    }
  }

  Future<void> _loadConfig() async {
    final config = await LLMService.getConfig();
    _customTextModels = await LLMService.getCustomTextModels();
    _customVisionModels = await LLMService.getCustomVisionModels();
    _zhipuApiKey = await LLMService.getProviderApiKey('zhipu');
    _mimoApiKey = await LLMService.getProviderApiKey('mimo');
    _mimoTokenPlanApiKey = await LLMService.getProviderApiKey(
      AiChatService.mimoTokenPlanProvider,
    );
    _deepseekApiKey = await LLMService.getProviderApiKey('deepseek');
    _nvidiaNimApiKey = await LLMService.getProviderApiKey('nvidia_nim');
    for (final provider in _llmProviders.keys) {
      _setFetchedProviderModels(
        provider,
        await LLMService.getProviderModels(provider),
      );
    }

    final configProvider = config?.provider ?? '';
    final providerFromConfigUrl = config == null
        ? ''
        : AiChatService.inferProviderFromApiUrl(config.apiUrl);
    // Older configs did not always persist the provider. If the endpoint
    // identifies a provider, use it for backward-compatible migration.
    final savedTextProvider =
        configProvider == 'zhipu' && providerFromConfigUrl.isNotEmpty
        ? providerFromConfigUrl
        : configProvider;
    final savedVisionProvider = config?.visionProvider ?? '';

    if (config != null) {
      if (savedTextProvider == 'mimo' && _mimoApiKey.isEmpty) {
        _mimoApiKey = config.apiKey;
      } else if (savedTextProvider == AiChatService.mimoTokenPlanProvider &&
          _mimoTokenPlanApiKey.isEmpty) {
        _mimoTokenPlanApiKey = config.apiKey;
      }
      _presetApiKeyCtrl.text = config.apiKey;
      _textPromptCtrl.text = config.textPrompt;
      _visionPromptCtrl.text = config.visionPrompt;

      // 如果存储的智谱 API Key 为空且当前是预设模型，则初始化它
      if (_zhipuApiKey.isEmpty) {
        final textModelExists = _llmTextModels.any((m) => m.id == config.model);
        if (textModelExists) {
          _zhipuApiKey = config.apiKey;
        }
      }

      final textModelId = config.model;
      final visionModelId = config.visionModel;

      final textModelExists = _llmTextModels.any((m) => m.id == textModelId);
      final customTextMatch = _customTextModels
          .where((m) => m.modelId == textModelId)
          .firstOrNull;

      final visionModelExists = _llmVisionModels.any(
        (m) => m.id == visionModelId,
      );
      final customVisionMatch = _customVisionModels
          .where((m) => m.modelId == visionModelId)
          .firstOrNull;

      if (textModelExists) {
        _selectedTextModel = textModelId;
      } else if (customTextMatch != null) {
        _selectedTextModel = customTextMatch.id;
      } else if (textModelId.isNotEmpty) {
        _selectedTextModel = textModelId;
      } else {
        _selectedTextModel = null;
      }

      if (visionModelExists) {
        _selectedVisionModel = visionModelId;
      } else if (customVisionMatch != null) {
        _selectedVisionModel = customVisionMatch.id;
      } else if (visionModelId.isNotEmpty) {
        _selectedVisionModel = visionModelId;
      } else {
        _selectedVisionModel = null;
      }
    } else {
      _selectedTextModel = 'glm-4.7-flash';
      _selectedVisionModel = 'glm-4.6v-flash';
      _textPromptCtrl.text = LLMConfig.defaultTextPrompt;
      _visionPromptCtrl.text = LLMConfig.defaultVisionPrompt;
    }

    final hasAnyApiKey = [
      _zhipuApiKey,
      _mimoApiKey,
      _mimoTokenPlanApiKey,
      _deepseekApiKey,
      _nvidiaNimApiKey,
      config?.apiKey ?? '',
    ].any((key) => key.trim().isNotEmpty);
    _currentStep = widget.initialStep?.clamp(0, 2) ?? (hasAnyApiKey ? 2 : 0);

    // 根据已选模型确定各自的服务商。优先使用已保存的服务商，避免
    // Token Plan 与普通 MiMo 的同名模型被前缀匹配到错误端点。
    if (_customTextModels.any((m) => m.id == _selectedTextModel)) {
      _selectedTextModelProvider = 'custom';
    } else if (_llmProviders.containsKey(savedTextProvider)) {
      _selectedTextModelProvider = savedTextProvider;
    } else {
      _selectedTextModelProvider = _getModelProvider(
        _selectedTextModel,
        preferredProvider: _selectedTextModelProvider,
      );
    }
    if (_customVisionModels.any((m) => m.id == _selectedVisionModel)) {
      _selectedVisionModelProvider = 'custom';
    } else if (_llmProviders.containsKey(savedVisionProvider)) {
      _selectedVisionModelProvider = savedVisionProvider;
    } else {
      _selectedVisionModelProvider = _getModelProvider(
        _selectedVisionModel,
        preferredProvider: _selectedVisionModelProvider,
      );
    }

    _updateApiKeyDisplay();
    if (mounted) _mutateState(() => _isLoading = false);
  }

  String _getModelProvider(String? modelId, {String? preferredProvider}) {
    if (modelId == null) return preferredProvider ?? 'zhipu';
    if (_customTextModels.any((m) => m.id == modelId) ||
        _customVisionModels.any((m) => m.id == modelId)) {
      return 'custom';
    }

    if (preferredProvider != null &&
        preferredProvider != 'custom' &&
        _llmProviders.containsKey(preferredProvider)) {
      final hasTextModel = _getTextModelsForProvider(preferredProvider)
          .any((m) => m.id == modelId);
      final hasVisionModel = _getVisionModelsForProvider(preferredProvider)
          .any((m) => m.id == modelId);
      if (hasTextModel || hasVisionModel) return preferredProvider;
    }

    final preset = _llmTextModels.where((m) => m.id == modelId).firstOrNull;
    if (preset != null) return preset.provider;
    final fetchedTextModel = _fetchedTextModelsByProvider.values
        .expand((models) => models)
        .where((m) => m.id == modelId)
        .firstOrNull;
    if (fetchedTextModel != null) return fetchedTextModel.provider;
    final visionPreset = _llmVisionModels
        .where((m) => m.id == modelId)
        .firstOrNull;
    if (visionPreset != null) return visionPreset.provider;
    final fetchedVisionModel = _fetchedVisionModelsByProvider.values
        .expand((models) => models)
        .where((m) => m.id == modelId)
        .firstOrNull;
    if (fetchedVisionModel != null) {
      return fetchedVisionModel.provider;
    }
    return preferredProvider ?? 'zhipu';
  }

  List<TextModelInfo> _getTextModelsForProvider(String provider) {
    final presetModels = _llmTextModels.where((m) => m.provider == provider);
    final byId = <String, TextModelInfo>{
      for (final model in presetModels) model.id: model,
      for (final model in _fetchedTextModelsByProvider[provider] ?? [])
        model.id: model,
    };
    return byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<VisionModelInfo> _getVisionModelsForProvider(String provider) {
    final presetModels = _llmVisionModels.where((m) => m.provider == provider);
    final byId = <String, VisionModelInfo>{
      for (final model in presetModels) model.id: model,
      for (final model in _fetchedVisionModelsByProvider[provider] ?? [])
        model.id: model,
    };
    return byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _setFetchedProviderModels(String provider, List<String> modelIds) {
    final normalized =
        modelIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    _fetchedTextModelsByProvider[provider] = normalized
        .map(
          (id) => TextModelInfo(
            id: id,
            name: id,
            description:
                '${_llmProviders[provider]?['name'] ?? provider} 拉取的可用模型',
            context: '-',
            maxOutput: '-',
            isPaid: true,
            provider: provider,
          ),
        )
        .toList();
    _fetchedVisionModelsByProvider[provider] = normalized
        .map(
          (id) => VisionModelInfo(
            id: id,
            name: id,
            description:
                '${_llmProviders[provider]?['name'] ?? provider} 拉取的可用模型',
            context: '-',
            maxOutput: '-',
            isPaid: true,
            provider: provider,
          ),
        )
        .toList();
  }

  void _updateApiKeyDisplay() {
    final customText = _customTextModels
        .where((m) => m.id == _selectedTextModel)
        .firstOrNull;
    if (customText != null) {
      _presetApiKeyCtrl.text = customText.apiKey;
    } else {
      final provider = _selectedTextModelProvider == 'custom'
          ? _getModelProvider(
              _selectedTextModel,
              preferredProvider: _selectedTextModelProvider,
            )
          : _selectedTextModelProvider;
      _presetApiKeyCtrl.text = switch (provider) {
        'mimo' => _mimoApiKey,
        AiChatService.mimoTokenPlanProvider => _mimoTokenPlanApiKey,
        'deepseek' => _deepseekApiKey,
        'nvidia_nim' => _nvidiaNimApiKey,
        _ => _zhipuApiKey,
      };
    }
  }

  String _getEffectiveApiKey() {
    final customText = _customTextModels
        .where((m) => m.id == _selectedTextModel)
        .firstOrNull;
    return customText?.apiKey ?? _presetApiKeyCtrl.text.trim();
  }

  String _getEffectiveApiUrl() {
    final customText = _customTextModels
        .where((m) => m.id == _selectedTextModel)
        .firstOrNull;
    if (customText != null) return customText.apiUrl;
    final provider = _selectedTextModelProvider == 'custom'
        ? _getModelProvider(
            _selectedTextModel,
            preferredProvider: _selectedTextModelProvider,
          )
        : _selectedTextModelProvider;
    if (provider == 'nvidia_nim') {
      return 'https://integrate.api.nvidia.com/v1';
    }
    return _llmProviders[provider]?['apiUrl'] ??
        _llmProviders['zhipu']!['apiUrl']!;
  }

  String _getEffectiveModelId() {
    final customText = _customTextModels
        .where((m) => m.id == _selectedTextModel)
        .firstOrNull;
    return customText?.modelId ?? (_selectedTextModel ?? '');
  }

  String? _getEffectiveVisionModelId() {
    final customVision = _customVisionModels
        .where((m) => m.id == _selectedVisionModel)
        .firstOrNull;
    return customVision?.modelId ?? _selectedVisionModel;
  }

  Future<void> _testConnection() async {
    if (!await _ensureLlmConfigurationAllowed()) return;
    _mutateState(() => _isTesting = true);
    try {
      final textModel = _selectedTextModel ?? '';

      if (textModel.isEmpty) {
        throw Exception('请选择文本模型');
      }

      final testConfig = LLMConfig(
        provider: _selectedTextModelProvider,
        visionProvider: _selectedVisionModelProvider,
        apiKey: _getEffectiveApiKey(),
        model: _getEffectiveModelId(),
        visionModel: _getEffectiveVisionModelId(),
        apiUrl: _getEffectiveApiUrl(),
        textPrompt: _textPromptCtrl.text,
        visionPrompt: _visionPromptCtrl.text,
      );
      await LLMService.saveConfig(testConfig);

      final result = await LLMService.testConnection();
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(
            content: Text(
              '连接成功！响应: ${result.substring(0, result.length > 50 ? 50 : result.length)}...',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('连接失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _mutateState(() => _isTesting = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!await _ensureLlmConfigurationAllowed()) return;
    final textModel = _selectedTextModel ?? '';
    if (textModel.isEmpty) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          const SnackBar(content: Text('请选择文本模型')),
        );
      }
      return;
    }

    final provider = _selectedTextModelProvider == 'custom'
        ? _getModelProvider(
            _selectedTextModel,
            preferredProvider: _selectedTextModelProvider,
          )
        : _selectedTextModelProvider;
    final config = LLMConfig(
      provider: provider,
      visionProvider: _selectedVisionModelProvider,
      apiKey: _getEffectiveApiKey(),
      model: _getEffectiveModelId(),
      visionModel: _getEffectiveVisionModelId(),
      apiUrl: _getEffectiveApiUrl(),
      textPrompt: _textPromptCtrl.text.isEmpty ? null : _textPromptCtrl.text,
      visionPrompt: _visionPromptCtrl.text.isEmpty
          ? null
          : _visionPromptCtrl.text,
    );

    // 保存所有已填写的 provider API keys
    if (_zhipuApiKey.isNotEmpty) {
      await LLMService.saveProviderApiKey('zhipu', _zhipuApiKey);
    }
    if (_mimoApiKey.isNotEmpty) {
      await LLMService.saveProviderApiKey('mimo', _mimoApiKey);
    }
    if (_mimoTokenPlanApiKey.isNotEmpty) {
      await LLMService.saveProviderApiKey(
        AiChatService.mimoTokenPlanProvider,
        _mimoTokenPlanApiKey,
      );
    }
    if (_deepseekApiKey.isNotEmpty) {
      await LLMService.saveProviderApiKey('deepseek', _deepseekApiKey);
    }
    if (_nvidiaNimApiKey.isNotEmpty) {
      await LLMService.saveProviderApiKey('nvidia_nim', _nvidiaNimApiKey);
    }

    await LLMService.saveConfig(config);
    if (mounted) {
      Navigator.pop(context, true);
      AppSnackBars.showSnackBar(
        context,
        const SnackBar(content: Text('大模型配置已保存')),
      );
    }
  }

  bool _useWideLayout(double width) => width >= 820;

  Future<bool> _ensureLlmConfigurationAllowed() async {
    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.llmConfiguration,
    );
    if (!authorized && mounted) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(
          content: Text(
            MinorModeService.instance.authorizationFailureMessage(
              MinorModeAction.llmConfiguration,
            ),
          ),
        ),
      );
    }
    return authorized;
  }

  Future<void> _fetchProviderModels(
    String provider, {
    required _ModelSelectionTarget target,
  }) async {
    if (!await _ensureLlmConfigurationAllowed()) return;
    final apiKey = switch (provider) {
      'mimo' => _mimoApiKey,
      AiChatService.mimoTokenPlanProvider => _mimoTokenPlanApiKey,
      'deepseek' => _deepseekApiKey,
      'nvidia_nim' => _nvidiaNimApiKey,
      _ => _zhipuApiKey,
    };
    final providerName = _llmProviders[provider]?['name'] ?? provider;

    if (apiKey.isEmpty) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('请先在上一步填写 $providerName API Key')),
        );
      }
      return;
    }
    if (mounted) {
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('正在拉取 $providerName 模型列表...')),
      );
    }
    try {
      final models = await AiChatService.fetchProviderModels(
        provider: provider,
        apiKey: apiKey,
      );
      if (!mounted) return;
      final existingIds = _llmTextModels
          .where((m) => m.provider == provider)
          .map((m) => m.id)
          .toSet();
      final newModels = models
          .where((id) => !existingIds.contains(id))
          .toList();
      _setFetchedProviderModels(provider, models);
      await LLMService.saveProviderModels(provider, models);
      if (!mounted) return;

      _mutateState(() {
        final fetchedTextModels = _fetchedTextModelsByProvider[provider] ?? [];
        final fetchedVisionModels =
            _fetchedVisionModelsByProvider[provider] ?? [];
        if (target == _ModelSelectionTarget.text) {
          _selectedTextModelProvider = provider;
          if (_selectedTextModel == null && fetchedTextModels.isNotEmpty) {
            _selectedTextModel = fetchedTextModels.first.id;
          }
        } else {
          _selectedVisionModelProvider = provider;
          if (_selectedVisionModel == null && fetchedVisionModels.isNotEmpty) {
            _selectedVisionModel = fetchedVisionModels.first.id;
          }
        }
      });

      if (newModels.isEmpty) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('$providerName 模型列表已是最新')),
        );
        return;
      }
      final count = newModels.length;
      AppSnackBars.showSnackBar(
        context,
        SnackBar(content: Text('已拉取 $count 个 $providerName 模型')),
      );
      for (final id in newModels) {
        debugPrint('[$providerName] 可用模型: $id');
      }
      showAppDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('可用 $providerName 模型'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView(
              children: models
                  .map(
                    (id) => ListTile(
                      dense: true,
                      title: Text(id, style: const TextStyle(fontSize: 13)),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _mutateState(() {
                            if (target == _ModelSelectionTarget.text) {
                              _selectedTextModel = id;
                              _selectedTextModelProvider = provider;
                            } else {
                              _selectedVisionModel = id;
                              _selectedVisionModelProvider = provider;
                            }
                          });
                        },
                        child: const Text('选用'),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        AppSnackBars.showSnackBar(
          context,
          SnackBar(content: Text('$providerName 模型列表拉取失败: $e')),
        );
      }
    }
  }
}
