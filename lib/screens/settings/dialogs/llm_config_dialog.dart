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
  bool _obscureApiKey = true;
  bool _isLoading = true;

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
    } else {
      _apiUrlCtrl.text =
          'https://open.bigmodel.cn/api/paas/v4/chat/completions';
      _modelCtrl.text = 'glm-4-flash';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
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
                      labelText: '模型名称',
                      hintText: 'glm-4-flash',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.psychology),
                    ),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
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
          child: const Text('清除配置'),
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
              apiUrl: _apiUrlCtrl.text.trim().isEmpty
                  ? null
                  : _apiUrlCtrl.text.trim(),
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
