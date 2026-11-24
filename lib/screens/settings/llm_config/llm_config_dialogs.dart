part of '../llm_config_page.dart';

extension _LLMConfigDialogs on _LLMConfigPageState {
  Future<void> _showAddCustomTextModelDialog({
    CustomTextModel? existing,
  }) async {
    if (!await _ensureLlmConfigurationAllowed() || !mounted) return;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final modelIdCtrl = TextEditingController(text: existing?.modelId ?? '');
    final apiUrlCtrl = TextEditingController(text: existing?.apiUrl ?? '');
    final apiKeyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final formKey = GlobalKey<FormState>();

    await showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '添加自定义文本模型' : '编辑自定义文本模型'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '模型名称',
                    hintText: '如: 我的GPT模型',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入模型名称' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: modelIdCtrl,
                  decoration: const InputDecoration(
                    labelText: '模型ID',
                    hintText: '如: gpt-4o',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入模型ID' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: apiUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API 地址',
                    hintText: 'https://api.openai.com/v1/chat/completions',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入API地址' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: apiKeyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: '输入您的 API Key',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入API Key' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final model = CustomTextModel(
                  id: existing?.id ?? _uuid.v4(),
                  name: nameCtrl.text.trim(),
                  modelId: modelIdCtrl.text.trim(),
                  apiUrl: apiUrlCtrl.text.trim(),
                  apiKey: apiKeyCtrl.text.trim(),
                );
                await LLMService.saveCustomTextModel(model);
                if (!mounted || !ctx.mounted) return;
                _mutateState(() {
                  if (existing != null) {
                    final idx = _customTextModels.indexWhere(
                      (m) => m.id == existing.id,
                    );
                    if (idx >= 0) _customTextModels[idx] = model;
                  } else {
                    _customTextModels.add(model);
                  }
                  _updateApiKeyDisplay();
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCustomTextModelDialog(CustomTextModel model) async {
    await _showAddCustomTextModelDialog(existing: model);
  }

  Future<void> _deleteCustomTextModel(CustomTextModel model) async {
    if (!await _ensureLlmConfigurationAllowed() || !mounted) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除自定义文本模型 "${model.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LLMService.deleteCustomTextModel(model.id);
      _mutateState(() {
        _customTextModels.removeWhere((m) => m.id == model.id);
        if (_selectedTextModel == model.id) {
          _selectedTextModel = null;
        }
        _updateApiKeyDisplay();
      });
    }
  }

  Future<void> _showAddCustomVisionModelDialog({
    CustomVisionModel? existing,
  }) async {
    if (!await _ensureLlmConfigurationAllowed() || !mounted) return;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final modelIdCtrl = TextEditingController(text: existing?.modelId ?? '');
    final apiUrlCtrl = TextEditingController(text: existing?.apiUrl ?? '');
    final apiKeyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final formKey = GlobalKey<FormState>();
    final selectedModalities = <String>{'image', ...?existing?.modalities};

    await showAppDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '添加自定义多模态模型' : '编辑自定义多模态模型'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      hintText: '如: 我的多模态模型',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入模型名称' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: modelIdCtrl,
                    decoration: const InputDecoration(
                      labelText: '模型ID',
                      hintText: '如: gpt-4o',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入模型ID' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: apiUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API 地址',
                      hintText: 'https://api.openai.com/v1/chat/completions',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入API地址' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: apiKeyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: '输入您的 API Key',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入API Key' : null,
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '模型支持的输入',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children:
                        const {
                          'image': '图片',
                          'audio': '音频',
                          'video': '视频',
                          'file': 'PDF/文件',
                        }.entries.map((entry) {
                          return FilterChip(
                            label: Text(entry.value),
                            selected: selectedModalities.contains(entry.key),
                            onSelected: entry.key == 'image'
                                ? null
                                : (selected) {
                                    setDialogState(() {
                                      if (selected) {
                                        selectedModalities.add(entry.key);
                                      } else {
                                        selectedModalities.remove(entry.key);
                                      }
                                    });
                                  },
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '图片默认开启；其他类型必须与服务商的 Chat Completions 协议一致。',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final model = CustomVisionModel(
                    id: existing?.id ?? _uuid.v4(),
                    name: nameCtrl.text.trim(),
                    modelId: modelIdCtrl.text.trim(),
                    apiUrl: apiUrlCtrl.text.trim(),
                    apiKey: apiKeyCtrl.text.trim(),
                    modalities: selectedModalities,
                  );
                  await LLMService.saveCustomVisionModel(model);
                  if (!mounted || !ctx.mounted) return;
                  _mutateState(() {
                    if (existing != null) {
                      final idx = _customVisionModels.indexWhere(
                        (m) => m.id == existing.id,
                      );
                      if (idx >= 0) _customVisionModels[idx] = model;
                    } else {
                      _customVisionModels.add(model);
                    }
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditCustomVisionModelDialog(CustomVisionModel model) async {
    await _showAddCustomVisionModelDialog(existing: model);
  }

  Future<void> _deleteCustomVisionModel(CustomVisionModel model) async {
    if (!await _ensureLlmConfigurationAllowed() || !mounted) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除自定义多模态模型 "${model.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LLMService.deleteCustomVisionModel(model.id);
      _mutateState(() {
        _customVisionModels.removeWhere((m) => m.id == model.id);
        if (_selectedVisionModel == model.id) {
          _selectedVisionModel = null;
        }
      });
    }
  }
}
