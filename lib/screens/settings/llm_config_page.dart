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
  final String provider;

  const TextModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.context,
    required this.maxOutput,
    this.isPaid = false,
    this.provider = 'zhipu',
  });
}

class VisionModelInfo {
  final String id;
  final String name;
  final String description;
  final String? context;
  final String? maxOutput;
  final bool isPaid;
  final String provider;

  const VisionModelInfo({
    required this.id,
    required this.name,
    required this.description,
    this.context,
    this.maxOutput,
    this.isPaid = false,
    this.provider = 'zhipu',
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
  bool _isLoading = true;
  bool _isTesting = false;
  String? _selectedTextModel;
  String? _selectedVisionModel;
  List<CustomTextModel> _customTextModels = [];
  List<CustomVisionModel> _customVisionModels = [];
  String _zhipuApiKey = '';
  String _mimoApiKey = '';
  String _deepseekApiKey = '';
  String _selectedTextModelProvider = 'zhipu';
  String _selectedVisionModelProvider = 'zhipu';
  int _currentStep = 0;
  final _uuid = const Uuid();

  static const Map<String, Map<String, String>> providers = {
    'zhipu': {
      'name': '智谱AI',
      'apiUrl': 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    },
    'mimo': {
      'name': '小米MiMo',
      'apiUrl': 'https://api.xiaomimimo.com/v1/chat/completions',
    },
    'deepseek': {
      'name': 'DeepSeek',
      'apiUrl': 'https://api.deepseek.com/chat/completions',
    },
  };

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
    // === 小米 MiMo 模型 ===
    TextModelInfo(
      id: 'mimo-v2.5-pro',
      name: 'MiMo-V2.5-Pro',
      description: '万亿参数旗舰，42B激活，Agent性能媲美Claude Opus 4.6',
      context: '1M',
      maxOutput: '128K',
      isPaid: true,
      provider: 'mimo',
    ),
    TextModelInfo(
      id: 'mimo-v2.5',
      name: 'MiMo-V2.5',
      description: '原生全模态感知，支持图像/视频/音频/文本，1M上下文',
      context: '1M',
      maxOutput: '32K',
      isPaid: true,
      provider: 'mimo',
    ),
    TextModelInfo(
      id: 'mimo-v2-flash',
      name: 'MiMo-V2-Flash',
      description: '极速推理模型，响应速度快，适合轻量任务',
      context: '128K',
      maxOutput: '64K',
      isPaid: true,
      provider: 'mimo',
    ),
    // === DeepSeek 模型 ===
    TextModelInfo(
      id: 'deepseek-v4-flash',
      name: 'DeepSeek-V4-Flash',
      description: '高性能推理模型，支持思维链，1M超长上下文',
      context: '1M',
      maxOutput: '384K',
      isPaid: true,
      provider: 'deepseek',
    ),
    TextModelInfo(
      id: 'deepseek-v4-pro',
      name: 'DeepSeek-V4-Pro',
      description: '旗舰推理模型，更强推理能力，支持深度思考',
      context: '1M',
      maxOutput: '384K',
      isPaid: true,
      provider: 'deepseek',
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
    // === 小米 MiMo 视觉模型 ===
    VisionModelInfo(
      id: 'mimo-v2.5',
      name: 'MiMo-V2.5',
      description: '原生全模态感知，支持图像/视频/音频理解，1M上下文',
      context: '1M',
      maxOutput: '32K',
      isPaid: true,
      provider: 'mimo',
    ),
    VisionModelInfo(
      id: 'mimo-v2-omni',
      name: 'MiMo-V2-Omni',
      description: '多模态理解与推理，支持图像分析和视觉问答',
      context: '128K',
      maxOutput: '32K',
      isPaid: false,
      provider: 'mimo',
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
    _zhipuApiKey = await LLMService.getProviderApiKey('zhipu');
    _mimoApiKey = await LLMService.getProviderApiKey('mimo');
    _deepseekApiKey = await LLMService.getProviderApiKey('deepseek');

    if (config != null) {
      _presetApiKeyCtrl.text = config.apiKey;
      _textPromptCtrl.text = config.textPrompt;
      _visionPromptCtrl.text = config.visionPrompt;

      // 如果存储的智谱 API Key 为空且当前是预设模型，则初始化它
      if (_zhipuApiKey.isEmpty) {
        final textModelExists = textModels.any((m) => m.id == config.model);
        if (textModelExists) {
          _zhipuApiKey = config.apiKey;
        }
      }

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

    // 根据已选模型确定各自的服务商
    if (_customTextModels.any((m) => m.id == _selectedTextModel)) {
      _selectedTextModelProvider = 'custom';
    } else {
      _selectedTextModelProvider = _getModelProvider(_selectedTextModel);
    }
    if (_customVisionModels.any((m) => m.id == _selectedVisionModel)) {
      _selectedVisionModelProvider = 'custom';
    } else {
      _selectedVisionModelProvider = _getModelProvider(_selectedVisionModel);
    }

    _updateApiKeyDisplay();
    if (mounted) setState(() => _isLoading = false);
  }

  String _getModelProvider(String? modelId) {
    if (modelId == null) return 'zhipu';
    final preset = textModels.where((m) => m.id == modelId).firstOrNull;
    if (preset != null) return preset.provider;
    final visionPreset = visionModels.where((m) => m.id == modelId).firstOrNull;
    if (visionPreset != null) return visionPreset.provider;
    return 'zhipu';
  }

  void _updateApiKeyDisplay() {
    final customText =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    if (customText != null) {
      _presetApiKeyCtrl.text = customText.apiKey;
    } else {
      final provider = _getModelProvider(_selectedTextModel);
      _presetApiKeyCtrl.text = switch (provider) {
        'mimo' => _mimoApiKey,
        'deepseek' => _deepseekApiKey,
        _ => _zhipuApiKey,
      };
    }
  }

  String _getEffectiveApiKey() {
    final customText =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    return customText?.apiKey ?? _presetApiKeyCtrl.text.trim();
  }

  String _getEffectiveApiUrl() {
    final customText =
        _customTextModels.where((m) => m.id == _selectedTextModel).firstOrNull;
    if (customText != null) return customText.apiUrl;
    final provider = _getModelProvider(_selectedTextModel);
    return providers[provider]?['apiUrl'] ?? providers['zhipu']!['apiUrl']!;
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

      if (textModel.isEmpty) {
        throw Exception('请选择文本模型');
      }

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

  Future<void> _saveConfig() async {
    final textModel = _selectedTextModel ?? '';
    if (textModel.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择文本模型')),
        );
      }
      return;
    }

    final config = LLMConfig(
      apiKey: _getEffectiveApiKey(),
      model: _getEffectiveModelId(),
      visionModel: _getEffectiveVisionModelId(),
      apiUrl: _getEffectiveApiUrl(),
      textPrompt: _textPromptCtrl.text.isEmpty ? null : _textPromptCtrl.text,
      visionPrompt:
          _visionPromptCtrl.text.isEmpty ? null : _visionPromptCtrl.text,
    );

    // 保存所有已填写的 provider API keys
    if (_zhipuApiKey.isNotEmpty) {
      await LLMService.saveProviderApiKey('zhipu', _zhipuApiKey);
    }
    if (_mimoApiKey.isNotEmpty) {
      await LLMService.saveProviderApiKey('mimo', _mimoApiKey);
    }
    if (_deepseekApiKey.isNotEmpty) {
      await LLMService.saveProviderApiKey('deepseek', _deepseekApiKey);
    }

    await LLMService.saveConfig(config);
    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('大模型配置已保存')),
      );
    }
  }

  // ==================== Step 1: 选择服务商 ====================

  Widget _buildStep1Provider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '本应用基于 OpenAI API 兼容接口开发，已深度适配以下大模型平台。文本模型和视觉模型可以来自不同服务商，自由混搭。',
          style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
        ),
        const SizedBox(height: 12),
        // 快速跳转链接
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickLink(
              label: '智谱AI开放平台',
              icon: Icons.open_in_new,
              color: Colors.orange,
              url:
                  'https://www.bigmodel.cn/invite?icode=VCykXNmHhts4csYPy2wX3LC%2Fk7jQAKmT1mpEiZXXnFw%3D',
            ),
            _buildQuickLink(
              label: '小米MiMo开放平台',
              icon: Icons.open_in_new,
              color: Colors.blue,
              url: 'https://platform.xiaomimimo.com',
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
          '支持的服务商',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 12),
        _buildProviderInfoCard(
          name: '智谱AI',
          description: '国内领先AI平台，提供多种免费模型',
          features: ['免费模型可用', '中文能力出色', '200K上下文'],
          color: Colors.orange,
          icon: Icons.auto_awesome,
        ),
        const SizedBox(height: 10),
        _buildProviderInfoCard(
          name: '小米MiMo',
          description: '万亿参数全模态模型，Agent能力媲美Claude Opus',
          features: ['1M超长上下文', '全模态感知', '深度推理'],
          color: Colors.blue,
          icon: Icons.smart_toy,
        ),
        const SizedBox(height: 10),
        _buildProviderInfoCard(
          name: 'DeepSeek',
          description: '高性能推理模型，支持思维链和超长输出',
          features: ['1M上下文', '384K输出', '深度思考'],
          color: Colors.green,
          icon: Icons.psychology,
        ),
        const SizedBox(height: 10),
        _buildProviderInfoCard(
          name: '自定义 OpenAI 兼容',
          description: '接入任意 OpenAI API 兼容的服务',
          features: ['自由配置', '支持第三方平台'],
          color: Colors.grey,
          icon: Icons.settings,
        ),
      ],
    );
  }

  Widget _buildProviderInfoCard({
    required String name,
    required String description,
    required List<String> features,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
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
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: features
                      .map((f) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(f,
                                style: TextStyle(
                                    fontSize: 11, color: color)),
                          ))
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
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('无法打开链接: $e')),
            );
          }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '配置您需要使用的 API Key。文本模型和视觉模型可以来自不同服务商，请按需填写。',
          style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
        ),
        const SizedBox(height: 16),
        _buildProviderKeyField(
          provider: 'zhipu',
          name: '智谱AI',
          color: Colors.orange,
          apiKey: _zhipuApiKey,
          onChanged: (val) => _zhipuApiKey = val,
          url:
              'https://www.bigmodel.cn/invite?icode=VCykXNmHhts4csYPy2wX3LC%2Fk7jQAKmT1mpEiZXXnFw%3D',
          linkLabel: '→ 前往智谱AI开放平台申请',
        ),
        const SizedBox(height: 12),
        _buildProviderKeyField(
          provider: 'mimo',
          name: '小米MiMo',
          color: Colors.blue,
          apiKey: _mimoApiKey,
          onChanged: (val) => _mimoApiKey = val,
          url: 'https://platform.xiaomimimo.com',
          linkLabel: '→ 前往小米MiMo开放平台申请',
        ),
        const SizedBox(height: 12),
        _buildProviderKeyField(
          provider: 'deepseek',
          name: 'DeepSeek',
          color: Colors.green,
          apiKey: _deepseekApiKey,
          onChanged: (val) => _deepseekApiKey = val,
          url: 'https://platform.deepseek.com',
          linkLabel: '→ 前往DeepSeek开放平台申请',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
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
      ],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
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
              Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: color)),
              const Spacer(),
              InkWell(
                onTap: () async {
                  try {
                    await launchUrl(Uri.parse(url),
                        mode: LaunchMode.platformDefault);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('无法打开链接: $e')),
                      );
                    }
                  }
                },
                child: Text(
                  linkLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: TextEditingController(text: apiKey)
              ..selection =
                  TextSelection.collapsed(offset: apiKey.length),
            obscureText: true,
            decoration: InputDecoration(
              hintText: '输入 $name API Key（留空则跳过）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              prefixIcon: const Icon(Icons.key, size: 18),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ==================== Step 3: 选择模型 ====================

  Widget _buildStep3Models() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '分别选择文本模型和视觉模型的服务商及模型，支持混搭。',
          style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
        ),

        const SizedBox(height: 20),

        // 文本模型选择
        _buildModelSection(
          title: '文本模型',
          selectedProvider: _selectedTextModelProvider,
          onProviderChanged: (provider) {
            setState(() {
              _selectedTextModelProvider = provider;
              // 清空不属于新服务商的模型
              if (provider != 'custom') {
                final ok = textModels.any((m) => m.id == _selectedTextModel && m.provider == provider);
                if (!ok) _selectedTextModel = null;
              }
              _updateApiKeyDisplay();
            });
          },
          models: textModels.where((m) => m.provider == _selectedTextModelProvider).toList(),
          selectedModelId: _selectedTextModel,
          onModelChanged: (val) {
            setState(() {
              _selectedTextModel = val;
              _updateApiKeyDisplay();
            });
          },
          customModels: _customTextModels,
          selectedIsCustom: _customTextModels.any((m) => m.id == _selectedTextModel),
          onCustomTap: (m) => setState(() => _selectedTextModel = m.id),
          onCustomEdit: _showEditCustomTextModelDialog,
          onCustomDelete: _deleteCustomTextModel,
          onAddCustom: _showAddCustomTextModelDialog,
          customLabel: '自定义文本模型',
        ),

        const SizedBox(height: 24),

        // 视觉模型选择
        _buildModelSection(
          title: '视觉模型',
          selectedProvider: _selectedVisionModelProvider,
          onProviderChanged: (provider) {
            setState(() {
              _selectedVisionModelProvider = provider;
              if (provider != 'custom') {
                final ok = visionModels.any((m) => m.id == _selectedVisionModel && m.provider == provider);
                if (!ok) _selectedVisionModel = null;
              }
            });
          },
          models: visionModels.where((m) => m.provider == _selectedVisionModelProvider).toList(),
          selectedModelId: _selectedVisionModel,
          onModelChanged: (val) {
            setState(() => _selectedVisionModel = val);
          },
          customModels: _customVisionModels,
          selectedIsCustom: _customVisionModels.any((m) => m.id == _selectedVisionModel),
          onCustomTap: (m) => setState(() => _selectedVisionModel = m.id),
          onCustomEdit: _showEditCustomVisionModelDialog,
          onCustomDelete: _deleteCustomVisionModel,
          onAddCustom: _showAddCustomVisionModelDialog,
          customLabel: '自定义视觉模型',
        ),

        const SizedBox(height: 16),

        // 高级设置
        ExpansionTile(
          title: Text('高级设置 (自定义Prompt)',
              style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            Text('文本识别 Prompt（可用变量: {now} {input}）',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 6),
            TextField(
              controller: _textPromptCtrl,
              maxLines: 6,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 12),
            Text('图片识别 Prompt（可用变量: {now}）',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 6),
            TextField(
              controller: _visionPromptCtrl,
              maxLines: 6,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _textPromptCtrl.text = LLMConfig.defaultTextPrompt;
                    _visionPromptCtrl.text = LLMConfig.defaultVisionPrompt;
                  });
                },
                icon: const Icon(Icons.restore, size: 14),
                label: const Text('恢复默认', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModelSection({
    required String title,
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
      {'key': 'zhipu', 'name': '智谱AI', 'color': Colors.orange, 'icon': Icons.auto_awesome},
      {'key': 'mimo', 'name': '小米MiMo', 'color': Colors.blue, 'icon': Icons.smart_toy},
      {'key': 'deepseek', 'name': 'DeepSeek', 'color': Colors.green, 'icon': Icons.psychology},
      {'key': 'custom', 'name': '自定义', 'color': Colors.grey, 'icon': Icons.settings},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.grey[800])),
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
                    Icon(icon, color: isSelected ? color : Colors.grey[500], size: 28),
                    const SizedBox(height: 6),
                    Text(name,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? color : Colors.grey[700])),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 14),

        // 自定义模型 or 预设模型下拉
        if (selectedProvider == 'custom') ...[
          if (customModels.isNotEmpty)
            ...(customModels.map((m) => _buildCustomModelChip(
                  name: m.name,
                  modelId: m.modelId,
                  isSelected: selectedModelId == m.id,
                  onTap: () => onCustomTap(m),
                  onEdit: () => onCustomEdit(m),
                  onDelete: () => onCustomDelete(m),
                ))),
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
                  .map((m) => DropdownMenuItem<String>(
                        value: m.id,
                        child: Row(
                          children: [
                            Text(m.name, style: const TextStyle(fontSize: 13)),
                            if (m.isPaid) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text('付费',
                                    style: TextStyle(
                                        fontSize: 9, color: Colors.orange[800])),
                              ),
                            ],
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: onModelChanged,
            ),
          ),
          if (models.any((m) => m.id == selectedModelId)) ...[
            const SizedBox(height: 6),
            () {
              final selected = models.firstWhere((m) => m.id == selectedModelId);
              return _buildModelInfo(
                  selected.description,
                  selected.context ?? selected.context,
                  selected.maxOutput ?? selected.maxOutput);
            }(),
          ],
        ] else ...[
          Text('该服务商暂无$title',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ],
      ],
    );
  }

  Widget _buildModelInfo(
      String description, String context, String maxOutput) {
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
          Text(description,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
              value: name,
              groupValue: isSelected ? name : null,
              onChanged: (_) => onTap(),
              activeColor: Colors.purple,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(modelId,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontFamily: 'monospace')),
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
              icon: Icon(Icons.delete_outline, size: 16, color: Colors.red[400]),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
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
          IconButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清除配置'),
                  content: const Text('确定要清除所有大模型配置吗？'),
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
                      child: const Text('清除'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await LLMService.clearConfig();
                if (context.mounted) {
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清除大模型配置')),
                  );
                }
              }
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: '清除配置',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stepper(
              currentStep: _currentStep,
              onStepContinue: () {
                if (_currentStep < 2) {
                  setState(() => _currentStep++);
                } else {
                  _saveConfig();
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() => _currentStep--);
                }
              },
              onStepTapped: (step) {
                // 只允许点击已完成的步骤或当前步骤
                if (step <= _currentStep) {
                  setState(() => _currentStep = step);
                }
              },
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Row(
                    children: [
                      if (_currentStep < 2)
                        FilledButton.icon(
                          onPressed: details.onStepContinue,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('下一步'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _isTesting ? null : details.onStepContinue,
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text('保存配置'),
                        ),
                      if (_currentStep > 0) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: details.onStepCancel,
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('上一步'),
                        ),
                      ],
                    ],
                  ),
                );
              },
              steps: [
                Step(
                  title: const Text('选择服务商'),
                  content: _buildStep1Provider(),
                  isActive: _currentStep >= 0,
                  state: _currentStep > 0
                      ? StepState.complete
                      : StepState.indexed,
                ),
                Step(
                  title: const Text('配置 API Key'),
                  content: _buildStep2ApiKey(),
                  isActive: _currentStep >= 1,
                  state: _currentStep > 1
                      ? StepState.complete
                      : _currentStep == 1
                          ? StepState.indexed
                          : StepState.disabled,
                ),
                Step(
                  title: const Text('选择模型'),
                  content: _buildStep3Models(),
                  isActive: _currentStep >= 2,
                  state: _currentStep == 2
                      ? StepState.indexed
                      : StepState.disabled,
                ),
              ],
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
