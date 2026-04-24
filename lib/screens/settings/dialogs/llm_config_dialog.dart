import 'package:flutter/material.dart';
import '../../../services/llm_service.dart';

class LLMConfigDialog extends StatefulWidget {
  const LLMConfigDialog({super.key});

  @override
  State<LLMConfigDialog> createState() => _LLMConfigDialogState();
}

class _LLMConfigDialogState extends State<LLMConfigDialog> {
  final _apiUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _visionModelCtrl = TextEditingController();
  final _textPromptCtrl = TextEditingController();
  final _visionPromptCtrl = TextEditingController();
  bool _obscureApiKey = true;
  bool _isLoading = true;
  bool _isTesting = false;
  final bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await LLMService.getConfig();
    if (config != null) {
      _apiUrlCtrl.text = config.apiUrl;
      _apiKeyCtrl.text = config.apiKey;
      _modelCtrl.text = config.model;
      _visionModelCtrl.text = config.visionModel;
      _textPromptCtrl.text = config.textPrompt;
      _visionPromptCtrl.text = config.visionPrompt;
    } else {
      _apiUrlCtrl.text =
          'https://open.bigmodel.cn/api/paas/v4/chat/completions';
      _modelCtrl.text = 'glm-4.7-flash';
      _visionModelCtrl.text = 'glm-4.6v-flash';
      _textPromptCtrl.text = LLMConfig.defaultTextPrompt;
      _visionPromptCtrl.text = LLMConfig.defaultVisionPrompt;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      // 先保存当前配置
      final config = LLMConfig(
        apiKey: _apiKeyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        visionModel: _visionModelCtrl.text.trim(),
        apiUrl: _apiUrlCtrl.text.trim(),
        textPrompt: _textPromptCtrl.text,
        visionPrompt: _visionPromptCtrl.text,
      );
      await LLMService.saveConfig(config);

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
    _apiUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _visionModelCtrl.dispose();
    _textPromptCtrl.dispose();
    _visionPromptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('大模型API配置'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '支持智谱AI等兼容OpenAI格式的API',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiUrlCtrl,
                    decoration: InputDecoration(
                      labelText: 'API地址',
                      hintText:
                          'https://open.bigmodel.cn/api/paas/v4/chat/completions',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: '输入您的API Key',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureApiKey
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () {
                          setState(() => _obscureApiKey = !_obscureApiKey);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelCtrl,
                    decoration: InputDecoration(
                      labelText: '文本模型',
                      hintText: 'glm-4.7-flash',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.text_fields),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _visionModelCtrl,
                    decoration: InputDecoration(
                      labelText: '视觉模型 (图片识别)',
                      hintText: 'glm-4.6v-flash',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.image),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('高级设置 (自定义Prompt)',
                        style: TextStyle(fontSize: 14)),
                    children: [
                      const SizedBox(height: 8),
                      const Text('文本识别Prompt:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      const Text('可用变量: {now} 当前时间, {input} 输入文本',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _textPromptCtrl,
                        maxLines: 8,
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('图片识别Prompt:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      const Text('可用变量: {now} 当前时间',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _visionPromptCtrl,
                        maxLines: 8,
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace'),
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
                                _textPromptCtrl.text =
                                    LLMConfig.defaultTextPrompt;
                                _visionPromptCtrl.text =
                                    LLMConfig.defaultVisionPrompt;
                              });
                            },
                            icon: const Icon(Icons.restore, size: 16),
                            label: const Text('恢复默认'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
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
        TextButton(
          onPressed: () async {
            await LLMService.clearConfig();
            if (context.mounted) {
              Navigator.pop(context, true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清除大模型配置')),
              );
            }
          },
          child: const Text('清除'),
        ),
        FilledButton(
          onPressed: () async {
            if (_apiKeyCtrl.text.trim().isEmpty ||
                _modelCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请填写API Key和模型名称')),
              );
              return;
            }
            final config = LLMConfig(
              apiKey: _apiKeyCtrl.text.trim(),
              model: _modelCtrl.text.trim(),
              visionModel: _visionModelCtrl.text.trim().isEmpty
                  ? null
                  : _visionModelCtrl.text.trim(),
              apiUrl: _apiUrlCtrl.text.trim().isEmpty
                  ? null
                  : _apiUrlCtrl.text.trim(),
              textPrompt:
                  _textPromptCtrl.text.isEmpty ? null : _textPromptCtrl.text,
              visionPrompt: _visionPromptCtrl.text.isEmpty
                  ? null
                  : _visionPromptCtrl.text,
            );
            await LLMService.saveConfig(config);
            if (context.mounted) {
              Navigator.pop(context, true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('大模型配置已保存')),
              );
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
