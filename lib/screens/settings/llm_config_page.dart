import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../services/llm_service.dart';

class TextModelInfo {
  final String id;
  final String name;
  final String description;
  final String context;
  final String maxOutput;
  final bool isPaid;

  const TextModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.context,
    required this.maxOutput,
    this.isPaid = false,
  });
}

class VisionModelInfo {
  final String id;
  final String name;
  final String description;
  final String? context;
  final String? maxOutput;
  final bool isPaid;

  const VisionModelInfo({
    required this.id,
    required this.name,
    required this.description,
    this.context,
    this.maxOutput,
    this.isPaid = false,
  });
}

class LLMConfigPage extends StatefulWidget {
  const LLMConfigPage({super.key});

  @override
  State<LLMConfigPage> createState() => _LLMConfigPageState();
}

class _LLMConfigPageState extends State<LLMConfigPage> {
  final _presetApiKeyCtrl = TextEditingController();
  final _textPromptCtrl = TextEditingController();
  final _visionPromptCtrl = TextEditingController();
  bool _obscureApiKey = true;
  bool _isLoading = true;
  bool _isTesting = false;
  bool _showAdvanced = false;
  String? _selectedTextModel;
  String? _selectedVisionModel;
  bool _showAllTextModels = false;
  bool _showAllVisionModels = false;
  List<CustomTextModel> _customTextModels = [];
  List<CustomVisionModel> _customVisionModels = [];
  final _uuid = const Uuid();

  static const List<TextModelInfo> textModels = [
    TextModelInfo(
      id: 'glm-4.7-flash',
      name: 'GLM-4.7-Flash',
      description: '免费模型，最新基座模型的普惠版本',
      context: '200K',
      maxOutput: '128K',
      isPaid: false,
    ),
    TextModelInfo(
      id: 'glm-4-flash-250414',
      name: 'GLM-4-Flash-250414',
      description: '免费模型，超长上下文处理能力，多语言支持',
      context: '128K',
      maxOutput: '16K',
      isPaid: false,
    ),
    TextModelInfo(
      id: 'glm-4.5-flash',
      name: 'GLM-4.5-Flash（即将下线）',
      description: '免费模型，支持深度思考模式',
      context: '128K',
      maxOutput: '96K',
      isPaid: false,
    ),
    TextModelInfo(
      id: 'glm-5',
      name: 'GLM-5',
      description: '最新旗舰基座，编程能力对齐Claude Opus 4.5',
      context: '200K',
      maxOutput: '128K',
      isPaid: true,
    ),
    TextModelInfo(
      id: 'glm-5-turbo',
      name: 'GLM-5-Turbo',
      description: '龙虾增强基座，复杂长任务执行连续性好',
      context: '200K',
      maxOutput: '128K',
      isPaid: true,
    ),
    TextModelInfo(
      id: 'glm-4.7',
      name: 'GLM-4.7',
      description: '高智能模型，编程更强更稳、审美更好',
      context: '200K',
      maxOutput: '128K',
      isPaid: true,
    ),
    TextModelInfo(
      id: 'glm-4.7-flashx',
      name: 'GLM-4.7-FlashX',
      description: '轻量高速，适用于中文写作、翻译等通用场景',
      context: '200K',
      maxOutput: '128K',
      isPaid: true,
    ),
    TextModelInfo(
      id: 'glm-4.6',
      name: 'GLM-4.6',
      description: '超强性能，高级编码能力、强大推理及工具调用',
      context: '200K',
      maxOutput: '128K',
      isPaid: true,
    ),
    TextModelInfo(
      id: 'glm-4.5-air',
      name: 'GLM-4.5-Air',
      description: '高性价比，在推理、编码和智能体任务上表现强劲',
      context: '128K',
      maxOutput: '96K',
      isPaid: true,
    ),
    TextModelInfo(
      id: 'glm-4.5-airx',
      name: 'GLM-4.5-AirX',
      description: '高性价比极速版，推理速度快',
      context: '128K',
      maxOutput: '96K',
      isPaid: true,
    ),
    TextModelInfo(
      id: 'glm-4-long',
      name: 'GLM-4-Long',
      description: '超长输入，支持高达1M上下文',
      context: '1M',
      maxOutput: '4K',
      isPaid: true,
    ),
    TextModelInfo(
      id: 'glm-4-flashx-250414',
      name: 'GLM-4-FlashX-250414',
      description: '高速低价，超快推理速度，更高并发保障',
      context: '128K',
      maxOutput: '16K',
      isPaid: true,
    ),
  ];

  static const List<VisionModelInfo> visionModels = [
    VisionModelInfo(
      id: 'glm-4.6v-flash',
      name: 'GLM-4.6V-Flash',
      description: '免费模型，视觉推理能力，支持工具调用',
      context: '128K',
      maxOutput: '32K',
      isPaid: false,
    ),
    VisionModelInfo(
      id: 'glm-4.1v-thinking-flash',
      name: 'GLM-4.1V-Thinking-Flash',
      description: '免费模型，视觉推理，复杂场景理解',
      context: '64K',
      maxOutput: '16K',
      isPaid: false,
    ),
    VisionModelInfo(
      id: 'glm-4v-flash',
      name: 'GLM-4V-Flash',
      description: '免费模型，图像理解，多语言支持',
      context: '16K',
      maxOutput: '1K',
      isPaid: false,
    ),
    VisionModelInfo(
      id: 'glm-4.6v',
      name: 'GLM-4.6V',
      description: '旗舰视觉推理，SOTA性能，原生支持工具调用',
      context: '128K',
      maxOutput: '32K',
      isPaid: true,
    ),
    VisionModelInfo(
      id: 'glm-ocr',
      name: 'GLM-OCR',
      description: '轻量图文解析，高精度高效率，支持复杂文档',
      context: '单图≤10MB',
      maxOutput: null,
      isPaid: true,
    ),
    VisionModelInfo(
      id: 'autoglm-phone',
      name: 'AutoGLM-Phone',
      description: '手机智能助理框架，自动完成App操作',
      context: '20K',
      maxOutput: '2048',
      isPaid: true,
    ),
    VisionModelInfo(
      id: 'glm-4.1v-thinking-flashx',
      name: 'GLM-4.1V-Thinking-FlashX',
      description: '轻量视觉推理，复杂场景理解，高并发',
      context: '64K',
      maxOutput: '16K',
      isPaid: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await LLMService.getConfig();
    _customTextModels = await LLMService.getCustomTextModels();
    _customVisionModels = await LLMService.getCustomVisionModels();

    if (config != null) {
      _presetApiKeyCtrl.text = config.apiKey;
      _textPromptCtrl.text = config.textPrompt;
      _visionPromptCtrl.text = config.visionPrompt;

      final textModelId = config.model;
      final visionModelId = config.visionModel;

      final textModelExists = textModels.any((m) => m.id == textModelId);
      final customTextMatch =
          _customTextModels.where((m) => m.modelId == textModelId).firstOrNull;

      final visionModelExists = visionModels.any((m) => m.id == visionModelId);
      final customVisionMatch = _customVisionModels
          .where((m) => m.modelId == visionModelId)
          .firstOrNull;

      if (textModelExists) {
        _selectedTextModel = textModelId;
      } else if (customTextMatch != null) {
        _selectedTextModel = customTextMatch.id;
      } else {
        _selectedTextModel = null;
      }

      if (visionModelExists) {
        _selectedVisionModel = visionModelId;
      } else if (customVisionMatch != null) {
        _selectedVisionModel = customVisionMatch.id;
      } else {
        _selectedVisionModel = null;
      }
    } else {
      _selectedTextModel = 'glm-4.7-flash';
      _selectedVisionModel = 'glm-4.6v-flash';
      _textPromptCtrl.text = LLMConfig.defaultTextPrompt;
      _visionPromptCtrl.text = LLMConfig.defaultVisionPrompt;
    }
    _updateApiKeyDisplay();
    if (mounted) setState(() => _isLoading = false);
  }

  void _updateApiKeyDisplay() {
    final customText =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    if (customText != null) {
      _presetApiKeyCtrl.text = customText.apiKey;
    }
  }

  String _getEffectiveApiKey() {
    final customText =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    return customText?.apiKey ?? _presetApiKeyCtrl.text.trim();
  }

  String? _getEffectiveApiUrl() {
    final customText =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    return customText?.apiUrl;
  }

  String _getEffectiveModelId() {
    final customText =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    return customText?.modelId ?? (_selectedTextModel ?? '');
  }

  String? _getEffectiveVisionModelId() {
    final customVision = _customVisionModels
        .where((m) => m.id == _selectedVisionModel)
        .firstOrNull;
    return customVision?.modelId ?? _selectedVisionModel;
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      final textModel = _selectedTextModel ?? '';
      final visionModel = _selectedVisionModel ?? '';

      if (textModel.isEmpty) {
        throw Exception('请选择文本模型');
      }

      final customText =
          _customTextModels.where((m) => m.id == textModel).firstOrNull;
      final customVision =
          _customVisionModels.where((m) => m.id == visionModel).firstOrNull;

      final testConfig = LLMConfig(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '连接成功！响应: ${result.substring(0, result.length > 50 ? 50 : result.length)}...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  void dispose() {
    _presetApiKeyCtrl.dispose();
    _textPromptCtrl.dispose();
    _visionPromptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('大模型API配置'),
        actions: [
          TextButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering, size: 18),
            label: Text(_isTesting ? '测试中...' : '测试连接'),
          ),
          IconButton(
            onPressed: () async {
              await LLMService.clearConfig();
              if (context.mounted) {
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清除大模型配置')),
                );
              }
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: '清除配置',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildIntroSection(),
                const SizedBox(height: 16),
                _buildApiConfigSection(),
                const SizedBox(height: 16),
                _buildTextModelSection(),
                const SizedBox(height: 16),
                _buildVisionModelSection(),
                const SizedBox(height: 16),
                _buildAdvancedSection(),
                const SizedBox(height: 24),
                _buildSaveButton(),
              ],
            ),
    );
  }

  Widget _buildIntroSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'AI 功能介绍',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '本应用基于 OpenAI API 兼容接口开发，并对智谱 API 进行了深度适配。您可以在下方自定义 OpenAI API 兼容的 Base URL 与模型，也可以直接使用应用内预设的免费智谱大模型。',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 6),
                      Text(
                        '如何获取 API Key',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在下方链接申请专属 API Key 后，即可在本应用中调用智谱免费大模型进行 AI 分析。请注意，免费模型服务可能存在不稳定情况，如需获得更佳体验，建议使用付费服务。',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[700], height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final url = Uri.parse(
                          'https://www.bigmodel.cn/invite?icode=VCykXNmHhts4csYPy2wX3LC%2Fk7jQAKmT1mpEiZXXnFw%3D');
                      try {
                        await launchUrl(url, mode: LaunchMode.platformDefault);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('无法打开链接: $e')),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new,
                              size: 16, color: Colors.blue[700]),
                          const SizedBox(width: 6),
                          Text(
                            '智谱AI开放平台 - API Key 申请',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: Text(
                'API Key 申请步骤',
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                _buildStep('1', '点击添加新的 API Key',
                    '进入上述申请地址后，在页面中找到「添加新的 API Key」按钮并点击。'),
                _buildStep('2', '新建 API Key',
                    '点击按钮后弹出新建窗口，填写 API Key 名称（仅用于区分不同密钥），填写后点击「确定」完成创建。'),
                _buildStep('3', '配置至应用',
                    '创建成功后，复制生成的完整 API Key，粘贴至下方配置位置，即可启用 AI 分析功能。'),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '安全提示：页面列表会展示账户下所有 API Key，请妥善保管，勿与他人共享、勿暴露于客户端代码中。',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange[800], height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600], height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiConfigSection() {
    final selectedTextCustom =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    final isUsingCustomText = selectedTextCustom != null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'API Key',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isUsingCustomText
                  ? '当前使用自定义模型 "${selectedTextCustom.name}" 的 API Key'
                  : '用于智谱预设模型的 API Key',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _presetApiKeyCtrl,
              obscureText: _obscureApiKey,
              enabled: !isUsingCustomText,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: '输入您的 API Key',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.key),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureApiKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() => _obscureApiKey = !_obscureApiKey);
                  },
                ),
              ),
            ),
            if (isUsingCustomText) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.green[700]),
                        const SizedBox(width: 6),
                        Text(
                          '使用自定义模型的 API 配置',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'API 地址: ${selectedTextCustom.apiUrl}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'API Key: ${selectedTextCustom.apiKey.substring(0, selectedTextCustom.apiKey.length > 8 ? 8 : selectedTextCustom.apiKey.length)}****',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextModelSection() {
    final allModels = <Map<String, dynamic>>[];
    for (final m in _customTextModels) {
      allModels.add({'type': 'custom', 'model': m});
    }
    for (final m in textModels) {
      allModels.add({'type': 'preset', 'model': m});
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.text_fields,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '文本模型',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showAddCustomTextModelDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加自定义'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '专注于处理和生成自然语言，涵盖语言理解与推理能力',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            if (_selectedTextModel != null) _buildSelectedTextModelTile(),
            if (!_showAllTextModels)
              TextButton.icon(
                onPressed: () => setState(() => _showAllTextModels = true),
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('展开更多模型'),
              )
            else ...[
              ...allModels
                  .where((item) =>
                      (item['type'] == 'preset'
                          ? (item['model'] as TextModelInfo).id
                          : (item['model'] as CustomTextModel).id) !=
                      _selectedTextModel)
                  .map((item) => item['type'] == 'preset'
                      ? _buildTextModelTile(item['model'] as TextModelInfo)
                      : _buildCustomTextModelTile(
                          item['model'] as CustomTextModel)),
              TextButton.icon(
                onPressed: () => setState(() => _showAllTextModels = false),
                icon: const Icon(Icons.expand_less, size: 18),
                label: const Text('收起'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTextModelTile() {
    final preset =
        textModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    final custom =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;

    if (preset != null) return _buildTextModelTile(preset);
    if (custom != null) return _buildCustomTextModelTile(custom);
    return const SizedBox.shrink();
  }

  Widget _buildTextModelTile(TextModelInfo model) {
    final isSelected = _selectedTextModel == model.id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTextModel = model.id;
          _showAllTextModels = false;
          _updateApiKeyDisplay();
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<String>(
                  value: model.id,
                  groupValue: _selectedTextModel,
                  onChanged: (val) {
                    setState(() {
                      _selectedTextModel = val;
                      _showAllTextModels = false;
                      _updateApiKeyDisplay();
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Expanded(
                  child: Text(
                    model.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (model.isPaid)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '付费',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange[800],
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildChip('上下文: ${model.context}'),
                      const SizedBox(width: 8),
                      _buildChip('输出: ${model.maxOutput}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomTextModelTile(CustomTextModel model) {
    final isSelected = _selectedTextModel == model.id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTextModel = model.id;
          _showAllTextModels = false;
        });
      },
      onLongPress: () => _showEditCustomTextModelDialog(model),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.purple : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Colors.purple.withValues(alpha: 0.1) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<String>(
                  value: model.id,
                  groupValue: _selectedTextModel,
                  onChanged: (val) {
                    setState(() {
                      _selectedTextModel = val;
                      _showAllTextModels = false;
                      _updateApiKeyDisplay();
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        model.modelId,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '自定义',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.purple[800],
                        fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _deleteCustomTextModel(model),
                  tooltip: '删除',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _showEditCustomTextModelDialog(model),
                  tooltip: '编辑',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API: ${model.apiUrl}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisionModelSection() {
    final allModels = <Map<String, dynamic>>[];
    for (final m in _customVisionModels) {
      allModels.add({'type': 'custom', 'model': m});
    }
    for (final m in visionModels) {
      allModels.add({'type': 'preset', 'model': m});
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.image,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '视觉模型',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showAddCustomVisionModelDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加自定义'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '用于图片识别和视觉理解',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            if (_selectedVisionModel != null) _buildSelectedVisionModelTile(),
            if (!_showAllVisionModels)
              TextButton.icon(
                onPressed: () => setState(() => _showAllVisionModels = true),
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('展开更多模型'),
              )
            else ...[
              ...allModels
                  .where((item) =>
                      (item['type'] == 'preset'
                          ? (item['model'] as VisionModelInfo).id
                          : (item['model'] as CustomVisionModel).id) !=
                      _selectedVisionModel)
                  .map((item) => item['type'] == 'preset'
                      ? _buildVisionModelTile(item['model'] as VisionModelInfo)
                      : _buildCustomVisionModelTile(
                          item['model'] as CustomVisionModel)),
              TextButton.icon(
                onPressed: () => setState(() => _showAllVisionModels = false),
                icon: const Icon(Icons.expand_less, size: 18),
                label: const Text('收起'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedVisionModelTile() {
    final preset =
        visionModels.where((m) => m.id == _selectedVisionModel).firstOrNull;
    final custom = _customVisionModels
        .where((m) => m.id == _selectedVisionModel)
        .firstOrNull;

    if (preset != null) return _buildVisionModelTile(preset);
    if (custom != null) return _buildCustomVisionModelTile(custom);
    return const SizedBox.shrink();
  }

  Widget _buildVisionModelTile(VisionModelInfo model) {
    final isSelected = _selectedVisionModel == model.id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedVisionModel = model.id;
          _showAllVisionModels = false;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<String>(
                  value: model.id,
                  groupValue: _selectedVisionModel,
                  onChanged: (val) {
                    setState(() {
                      _selectedVisionModel = val;
                      _showAllVisionModels = false;
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Expanded(
                  child: Text(
                    model.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (model.isPaid)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '付费',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange[800],
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (model.context != null)
                        _buildChip('上下文: ${model.context}'),
                      if (model.maxOutput != null)
                        _buildChip('输出: ${model.maxOutput}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomVisionModelTile(CustomVisionModel model) {
    final isSelected = _selectedVisionModel == model.id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedVisionModel = model.id;
          _showAllVisionModels = false;
        });
      },
      onLongPress: () => _showEditCustomVisionModelDialog(model),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.purple : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Colors.purple.withValues(alpha: 0.1) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<String>(
                  value: model.id,
                  groupValue: _selectedVisionModel,
                  onChanged: (val) {
                    setState(() {
                      _selectedVisionModel = val;
                      _showAllVisionModels = false;
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        model.modelId,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '自定义',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.purple[800],
                        fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _deleteCustomVisionModel(model),
                  tooltip: '删除',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _showEditCustomVisionModelDialog(model),
                  tooltip: '编辑',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'API: ${model.apiUrl}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildAdvancedSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading:
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
            title:
                const Text('高级设置 (自定义Prompt)', style: TextStyle(fontSize: 14)),
            trailing:
                Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
            onTap: () {
              setState(() => _showAdvanced = !_showAdvanced);
            },
          ),
          if (_showAdvanced) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('文本识别Prompt:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('可用变量: {now} 当前时间, {input} 输入文本',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _textPromptCtrl,
                    maxLines: 8,
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('图片识别Prompt:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('可用变量: {now} 当前时间',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _visionPromptCtrl,
                    maxLines: 8,
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _textPromptCtrl.text = LLMConfig.defaultTextPrompt;
                            _visionPromptCtrl.text =
                                LLMConfig.defaultVisionPrompt;
                          });
                        },
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('恢复默认'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: () async {
          final textModel = _selectedTextModel ?? '';
          final visionModel = _selectedVisionModel ?? '';

          if (textModel.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请选择文本模型')),
            );
            return;
          }

          final customText =
              _customTextModels.where((m) => m.id == textModel).firstOrNull;

          final config = LLMConfig(
            apiKey: _getEffectiveApiKey(),
            model: _getEffectiveModelId(),
            visionModel: _getEffectiveVisionModelId(),
            apiUrl: _getEffectiveApiUrl(),
            textPrompt:
                _textPromptCtrl.text.isEmpty ? null : _textPromptCtrl.text,
            visionPrompt:
                _visionPromptCtrl.text.isEmpty ? null : _visionPromptCtrl.text,
          );
          await LLMService.saveConfig(config);
          if (context.mounted) {
            Navigator.pop(context, true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('大模型配置已保存')),
            );
          }
        },
        icon: const Icon(Icons.save),
        label: const Text('保存配置'),
      ),
    );
  }

  Future<void> _showAddCustomTextModelDialog(
      {CustomTextModel? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final modelIdCtrl = TextEditingController(text: existing?.modelId ?? '');
    final apiUrlCtrl = TextEditingController(text: existing?.apiUrl ?? '');
    final apiKeyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
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
                setState(() {
                  if (existing != null) {
                    final idx = _customTextModels
                        .indexWhere((m) => m.id == existing.id);
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
    final confirmed = await showDialog<bool>(
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
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LLMService.deleteCustomTextModel(model.id);
      setState(() {
        _customTextModels.removeWhere((m) => m.id == model.id);
        if (_selectedTextModel == model.id) {
          _selectedTextModel = null;
        }
        _updateApiKeyDisplay();
      });
    }
  }

  Future<void> _showAddCustomVisionModelDialog(
      {CustomVisionModel? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final modelIdCtrl = TextEditingController(text: existing?.modelId ?? '');
    final apiUrlCtrl = TextEditingController(text: existing?.apiUrl ?? '');
    final apiKeyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '添加自定义视觉模型' : '编辑自定义视觉模型'),
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
                    hintText: '如: 我的视觉模型',
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
                final model = CustomVisionModel(
                  id: existing?.id ?? _uuid.v4(),
                  name: nameCtrl.text.trim(),
                  modelId: modelIdCtrl.text.trim(),
                  apiUrl: apiUrlCtrl.text.trim(),
                  apiKey: apiKeyCtrl.text.trim(),
                );
                await LLMService.saveCustomVisionModel(model);
                setState(() {
                  if (existing != null) {
                    final idx = _customVisionModels
                        .indexWhere((m) => m.id == existing.id);
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
    );
  }

  Future<void> _showEditCustomVisionModelDialog(CustomVisionModel model) async {
    await _showAddCustomVisionModelDialog(existing: model);
  }

  Future<void> _deleteCustomVisionModel(CustomVisionModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除自定义视觉模型 "${model.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await LLMService.deleteCustomVisionModel(model.id);
      setState(() {
        _customVisionModels.removeWhere((m) => m.id == model.id);
        if (_selectedVisionModel == model.id) {
          _selectedVisionModel = null;
        }
      });
    }
  }
}
