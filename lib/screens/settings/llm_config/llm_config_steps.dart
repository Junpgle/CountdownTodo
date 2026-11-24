part of '../llm_config_page.dart';

extension _LLMConfigSteps on _LLMConfigPageState {
  Widget _buildAccessDeniedBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 52,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                '大模型功能已受未成年人模式保护',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                MinorModeService.instance.authorizationFailureMessage(
                  MinorModeAction.llmConfiguration,
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _responsiveItemWidth(
    double maxWidth, {
    required int itemCount,
    double minWidth = 280,
    double spacing = 12,
    int maxColumns = 2,
  }) {
    if (maxWidth.isInfinite) return minWidth;
    final columns = (maxWidth / (minWidth + spacing)).floor().clamp(
      1,
      itemCount.clamp(1, maxColumns),
    );
    return (maxWidth - spacing * (columns - 1)) / columns;
  }

  // ==================== Step 1: 了解服务商 ====================

  Widget _buildStep1Provider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final providerCards = [
          _buildProviderInfoCard(
            name: '智谱AI',
            description: '国内领先AI平台，提供多种免费模型',
            features: ['免费模型可用', '中文能力出色', '200K上下文'],
            color: Colors.orange,
            icon: Icons.auto_awesome,
          ),
          _buildProviderInfoCard(
            name: '小米MiMo',
            description: '万亿参数全模态模型，Agent能力媲美Claude Opus',
            features: ['1M超长上下文', '全模态感知', '深度推理'],
            color: Colors.blue,
            icon: Icons.smart_toy,
          ),
          _buildProviderInfoCard(
            name: 'MiMo Token Plan',
            description: '小米 MiMo 的 Token Plan 专属 API 入口',
            features: ['独立配额', 'OpenAI兼容', '支持模型列表'],
            color: Colors.indigo,
            icon: Icons.token_outlined,
          ),
          _buildProviderInfoCard(
            name: 'DeepSeek',
            description: '高性能推理模型，支持思维链和超长输出',
            features: ['1M上下文', '384K输出', '深度思考'],
            color: Colors.green,
            icon: Icons.psychology,
          ),
          _buildProviderInfoCard(
            name: '自定义 OpenAI 兼容',
            description: '接入任意 OpenAI API 兼容的服务',
            features: ['自由配置', '支持第三方平台'],
            color: Colors.grey,
            icon: Icons.settings,
          ),
        ];
        final cardWidth = _responsiveItemWidth(
          constraints.maxWidth,
          itemCount: providerCards.length,
          minWidth: 260,
          maxColumns: constraints.maxWidth >= 1080 ? 4 : 2,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdvancedAiTutorialCard(),
            Text(
              '这里只管理服务商、API Key 和模型连接。助手行为、智能上下文和对话提示词请在“AI 助手设置”中调整。',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickLink(
                  label: '智谱AI开放平台',
                  icon: Icons.open_in_new,
                  color: Colors.orange,
                  url: 'https://www.bigmodel.cn/invite?icode=VCykXNmHhts4csYPy2wX3LC%2Fk7jQAKmT1mpEiZXXnFw%3D',
                ),
                _buildQuickLink(
                  label: '小米MiMo开放平台',
                  icon: Icons.open_in_new,
                  color: Colors.blue,
                  url: 'https://platform.xiaomimimo.com',
                ),
                _buildQuickLink(
                  label: 'MiMo Token Plan 文档',
                  icon: Icons.open_in_new,
                  color: Colors.indigo,
                  url: 'https://mimo.mi.com/docs/welcome',
                ),
                _buildQuickLink(
                  label: 'DeepSeek开放平台',
                  icon: Icons.open_in_new,
                  color: Colors.green,
                  url: 'https://platform.deepseek.com',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '支持的服务商（模型将在下一步选择）',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: providerCards
                  .map((card) => SizedBox(width: cardWidth, child: card))
                  .toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProviderInfoCard({
    required String name,
    required String description,
    required List<String> features,
    required Color color,
    required IconData icon,
  }) {
    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 12,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: features
                      .map(
                        (f) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(fontSize: 11, color: color),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLink({
    required String label,
    required IconData icon,
    required Color color,
    required String url,
  }) {
    return InkWell(
      onTap: () async {
        try {
          await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
        } catch (e) {
          if (!mounted) return;
          AppSnackBars.showSnackBar(
            context,
            SnackBar(content: Text('无法打开链接: $e')),
          );
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Step 2: 配置 API Key ====================

  Widget _buildStep2ApiKey() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyFields = [
          _buildProviderKeyField(
            provider: 'zhipu',
            name: '智谱AI',
            color: Colors.orange,
            apiKey: _zhipuApiKey,
            onChanged: (val) => _zhipuApiKey = val,
            url: 'https://www.bigmodel.cn/invite?icode=VCykXNmHhts4csYPy2wX3LC%2Fk7jQAKmT1mpEiZXXnFw%3D',
            linkLabel: '→ 前往智谱AI开放平台申请',
          ),
          _buildProviderKeyField(
            provider: 'mimo',
            name: '小米MiMo',
            color: Colors.blue,
            apiKey: _mimoApiKey,
            onChanged: (val) => _mimoApiKey = val,
            url: 'https://platform.xiaomimimo.com',
            linkLabel: '→ 前往小米MiMo开放平台申请',
          ),
          _buildProviderKeyField(
            provider: AiChatService.mimoTokenPlanProvider,
            name: 'MiMo Token Plan',
            color: Colors.indigo,
            apiKey: _mimoTokenPlanApiKey,
            onChanged: (val) => _mimoTokenPlanApiKey = val,
            url: 'https://mimo.mi.com/docs/welcome',
            linkLabel: '→ 查看 MiMo Token Plan 文档',
          ),
          _buildProviderKeyField(
            provider: 'deepseek',
            name: 'DeepSeek',
            color: Colors.green,
            apiKey: _deepseekApiKey,
            onChanged: (val) => _deepseekApiKey = val,
            url: 'https://platform.deepseek.com',
            linkLabel: '→ 前往DeepSeek开放平台申请',
          ),
          _buildNvidiaNimKeyField(),
        ];
        final fieldWidth = _responsiveItemWidth(
          constraints.maxWidth,
          itemCount: keyFields.length,
          minWidth: 320,
          maxColumns: 2,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '配置您需要使用的 API Key。文本模型和多模态模型可以来自不同服务商，请按需填写；填写后点击“下一步”选择模型。',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: keyFields
                  .map((field) => SizedBox(width: fieldWidth, child: field))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(
              '模型选择和连接测试位于下一步，测试时会使用你刚刚选中的文本模型。',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProviderKeyField({
    required String provider,
    required String name,
    required Color color,
    required String apiKey,
    required ValueChanged<String> onChanged,
    required String url,
    required String linkLabel,
  }) {
    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: apiKey.isNotEmpty ? Colors.green : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: color,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () async {
                      try {
                        await launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.platformDefault,
                        );
                      } catch (e) {
                        if (!mounted) return;
                        AppSnackBars.showSnackBar(
                          context,
                          SnackBar(content: Text('无法打开链接: $e')),
                        );
                      }
                    },
                    child: Text(
                      linkLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: TextEditingController(text: apiKey)
              ..selection = TextSelection.collapsed(offset: apiKey.length),
            obscureText: true,
            decoration: InputDecoration(
              hintText: '输入 $name API Key（留空则跳过）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
              prefixIcon: const Icon(Icons.key, size: 18),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildNvidiaNimKeyField() {
    final color = Colors.cyan;
    return OptionalLiquidGlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      highContrast: true,
      fallbackDecoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _nvidiaNimApiKey.isNotEmpty
                      ? Colors.green
                      : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'NVIDIA NIM',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: color,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () async {
                      try {
                        await launchUrl(
                          Uri.parse('https://build.nvidia.com'),
                          mode: LaunchMode.platformDefault,
                        );
                      } catch (e) {
                        if (!mounted) return;
                        AppSnackBars.showSnackBar(
                          context,
                          SnackBar(content: Text('无法打开链接: $e')),
                        );
                      }
                    },
                    child: Text(
                      '→ 前往 NVIDIA Build 申请',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: TextEditingController(text: _nvidiaNimApiKey)
              ..selection = TextSelection.collapsed(
                offset: _nvidiaNimApiKey.length,
              ),
            obscureText: true,
            decoration: InputDecoration(
              hintText: '输入 NVIDIA NIM API Key（nvapi-...）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
              prefixIcon: const Icon(Icons.key, size: 18),
            ),
            onChanged: (val) => _nvidiaNimApiKey = val,
          ),
        ],
      ),
    );
  }

  // ==================== Step 3: 选择模型 ====================

  Widget _buildStep3Models() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = _useWideLayout(constraints.maxWidth);
        final textModelSection = _buildModelSection(
          title: '文本模型',
          selectionTarget: _ModelSelectionTarget.text,
          selectedProvider: _selectedTextModelProvider,
          onProviderChanged: (provider) {
            _mutateState(() {
              _selectedTextModelProvider = provider;
              if (provider != 'custom') {
                final ok = _getTextModelsForProvider(provider)
                    .any((m) => m.id == _selectedTextModel);
                if (!ok) _selectedTextModel = null;
              }
              _updateApiKeyDisplay();
            });
          },
          models: _getTextModelsForProvider(_selectedTextModelProvider),
          selectedModelId: _selectedTextModel,
          onModelChanged: (val) {
            _mutateState(() {
              _selectedTextModel = val;
              _updateApiKeyDisplay();
            });
          },
          customModels: _customTextModels,
          selectedIsCustom: _customTextModels.any(
            (m) => m.id == _selectedTextModel,
          ),
          onCustomTap: (m) => _mutateState(() => _selectedTextModel = m.id),
          onCustomEdit: _showEditCustomTextModelDialog,
          onCustomDelete: _deleteCustomTextModel,
          onAddCustom: _showAddCustomTextModelDialog,
          customLabel: '自定义文本模型',
        );
        final visionModelSection = _buildModelSection(
          title: '多模态模型',
          selectionTarget: _ModelSelectionTarget.vision,
          selectedProvider: _selectedVisionModelProvider,
          onProviderChanged: (provider) {
            _mutateState(() {
              _selectedVisionModelProvider = provider;
              if (provider != 'custom') {
                final ok = _getVisionModelsForProvider(provider)
                    .any((m) => m.id == _selectedVisionModel);
                if (!ok) _selectedVisionModel = null;
              }
            });
          },
          models: _getVisionModelsForProvider(_selectedVisionModelProvider),
          selectedModelId: _selectedVisionModel,
          onModelChanged: (val) {
            _mutateState(() => _selectedVisionModel = val);
          },
          customModels: _customVisionModels,
          selectedIsCustom: _customVisionModels.any(
            (m) => m.id == _selectedVisionModel,
          ),
          onCustomTap: (m) => _mutateState(() => _selectedVisionModel = m.id),
          onCustomEdit: _showEditCustomVisionModelDialog,
          onCustomDelete: _deleteCustomVisionModel,
          onAddCustom: _showAddCustomVisionModelDialog,
          customLabel: '自定义多模态模型',
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分别选择对话文本模型和图片/音频/视频输入使用的多模态模型，支持混搭。',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: textModelSection),
                  const SizedBox(width: 20),
                  Expanded(child: visionModelSection),
                ],
              )
            else ...[
              textModelSection,
              const SizedBox(height: 24),
              visionModelSection,
            ],
            const SizedBox(height: 16),
            _buildPromptSettings(wide: wide),
            _buildTestConnectionButton(wide: wide),
          ],
        );
      },
    );
  }

  Widget _buildTestConnectionButton({required bool wide}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Align(
        alignment: wide ? Alignment.centerRight : Alignment.centerLeft,
        child: SizedBox(
          width: wide ? 320 : double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering, size: 18),
            label: Text(_isTesting ? '测试连接' : '测试当前选中模型的连接'),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptSettings({required bool wide}) {
    final textPrompt = _buildPromptField(
      label: '文本识别 Prompt（可用变量: {now} {input}）',
      controller: _textPromptCtrl,
    );
    final visionPrompt = _buildPromptField(
      label: '图片识别 Prompt（可用变量: {now}）',
      controller: _visionPromptCtrl,
    );

    return ExpansionTile(
      initiallyExpanded: {
        'llm_recognition',
        'llm_text_prompt',
        'llm_vision_prompt',
        'llm_prompt_reset',
      }.contains(widget.initialTarget),
      title: Text(
        '识别服务高级配置（不影响对话助手）',
        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: textPrompt),
              const SizedBox(width: 16),
              Expanded(child: visionPrompt),
            ],
          )
        else ...[
          textPrompt,
          const SizedBox(height: 12),
          visionPrompt,
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              _mutateState(() {
                _textPromptCtrl.text = LLMConfig.defaultTextPrompt;
                _visionPromptCtrl.text = LLMConfig.defaultVisionPrompt;
              });
            },
            icon: const Icon(Icons.restore, size: 14),
            label: const Text('恢复默认', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildPromptField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: 6,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(10),
          ),
        ),
      ],
    );
  }

  Widget _buildModelSection({
    required String title,
    required _ModelSelectionTarget selectionTarget,
    required String selectedProvider,
    required ValueChanged<String> onProviderChanged,
    required List models,
    required String? selectedModelId,
    required ValueChanged<String?> onModelChanged,
    required List customModels,
    required bool selectedIsCustom,
    required Function onCustomTap,
    required Function onCustomEdit,
    required Function onCustomDelete,
    required VoidCallback onAddCustom,
    required String customLabel,
  }) {
    final providerOptions = [
      {
        'key': 'zhipu',
        'name': '智谱AI',
        'color': Colors.orange,
        'icon': Icons.auto_awesome,
      },
      {
        'key': 'mimo',
        'name': '小米MiMo',
        'color': Colors.blue,
        'icon': Icons.smart_toy,
      },
      {
        'key': AiChatService.mimoTokenPlanProvider,
        'name': 'MiMo Token Plan',
        'color': Colors.indigo,
        'icon': Icons.token_outlined,
      },
      {
        'key': 'deepseek',
        'name': 'DeepSeek',
        'color': Colors.green,
        'icon': Icons.psychology,
      },
      {
        'key': 'nvidia_nim',
        'name': 'NVIDIA NIM',
        'color': Colors.cyan,
        'icon': Icons.workspace_premium,
      },
      {
        'key': 'custom',
        'name': '自定义',
        'color': Colors.grey,
        'icon': Icons.settings,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 10),

        // 服务商选择
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: providerOptions.map((opt) {
            final key = opt['key'] as String;
            final name = opt['name'] as String;
            final color = opt['color'] as Color;
            final icon = opt['icon'] as IconData;
            final isSelected = selectedProvider == key;

            return InkWell(
              onTap: () => onProviderChanged(key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 100,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? color : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: isSelected ? color.withValues(alpha: 0.08) : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      icon,
                      color: isSelected ? color : Colors.grey[500],
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? color : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 14),

        if (selectedProvider != 'custom') ...[
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _fetchProviderModels(
                selectedProvider,
                target: selectionTarget,
              ),
              icon: const Icon(Icons.cloud_download_outlined, size: 16),
              label: Text(
                '拉取${_llmProviders[selectedProvider]?['name'] ?? selectedProvider}模型列表',
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // 自定义模型 or 预设模型下拉
        if (selectedProvider == 'custom') ...[
          if (customModels.isNotEmpty)
            RadioGroup<String>(
              groupValue: selectedModelId,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                final selected = customModels.firstWhere(
                  (model) => model.id == value,
                );
                onCustomTap(selected);
              },
              child: Column(
                children: customModels
                    .map<Widget>(
                      (m) => _buildCustomModelChip(
                        value: m.id,
                        name: m.name,
                        modelId: m.modelId,
                        isSelected: selectedModelId == m.id,
                        onTap: () => onCustomTap(m),
                        onEdit: () => onCustomEdit(m),
                        onDelete: () => onCustomDelete(m),
                      ),
                    )
                    .toList(),
              ),
            ),
          TextButton.icon(
            onPressed: onAddCustom,
            icon: const Icon(Icons.add, size: 16),
            label: Text('添加$customLabel'),
          ),
        ] else if (models.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              value: models.any((m) => m.id == selectedModelId)
                  ? selectedModelId
                  : null,
              isExpanded: true,
              underline: const SizedBox(),
              hint: Text('选择$title', style: const TextStyle(fontSize: 13)),
              items: models
                  .map(
                    (m) => DropdownMenuItem<String>(
                      value: m.id,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          if (m.isPaid) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '付费',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.orange[800],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onModelChanged,
            ),
          ),
          if (models.any((m) => m.id == selectedModelId)) ...[
            const SizedBox(height: 6),
            () {
              final selected = models.firstWhere(
                (m) => m.id == selectedModelId,
              );
              return _buildModelInfo(
                selected.description,
                selected.context ?? selected.context,
                selected.maxOutput ?? selected.maxOutput,
              );
            }(),
          ],
        ] else ...[
          Text(
            '该服务商暂无$title',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  Widget _buildModelInfo(String description, String context, String maxOutput) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              _buildChip('上下文: $context'),
              _buildChip('输出: $maxOutput'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomModelChip({
    required String value,
    required String name,
    required String modelId,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.purple : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Colors.purple.withValues(alpha: 0.05) : null,
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              activeColor: Colors.purple,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    modelId,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.red[400],
              ),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
