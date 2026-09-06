import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/chat_storage_service.dart';
import '../../../services/llm_service.dart';
import '../../../utils/page_transitions.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/floating_glass_control.dart';
import '../llm_config_page.dart';

/// Settings that control how the in-app AI assistant builds and presents a
/// request. Model credentials and model selection remain in [LLMConfigPage].
class AiAssistantSettingsPage extends StatefulWidget {
  final bool isEmbedded;

  const AiAssistantSettingsPage({super.key, this.isEmbedded = false});

  @override
  State<AiAssistantSettingsPage> createState() =>
      _AiAssistantSettingsPageState();
}

class _AiAssistantSettingsPageState extends State<AiAssistantSettingsPage> {
  final TextEditingController _promptController = TextEditingController();

  bool _isLoading = true;
  bool _isSavingPrompt = false;
  bool _smartContext = true;
  bool _showContextPreview = false;
  bool _injectMoreContext = false;
  bool _deepThinking = false;
  bool _promptEnabled = true;
  bool _promptDirty = false;
  late Future<LLMConfig?> _llmConfigFuture;

  @override
  void initState() {
    super.initState();
    _llmConfigFuture = LLMService.getConfig();
    _loadSettings();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final values = await Future.wait<dynamic>([
      ChatStorageService.getCustomPrompt(),
      ChatStorageService.isPromptEnabled(),
      ChatStorageService.isSmartContextEnabled(),
      ChatStorageService.shouldShowContextPreview(),
      ChatStorageService.shouldInjectMoreContext(),
      ChatStorageService.isDeepThinkingEnabled(),
    ]);
    if (!mounted) return;
    _promptController.text = values[0] as String;
    setState(() {
      _promptEnabled = values[1] as bool;
      _smartContext = values[2] as bool;
      _showContextPreview = values[3] as bool;
      _injectMoreContext = values[4] as bool;
      _deepThinking = values[5] as bool;
      _isLoading = false;
    });
  }

  Future<void> _setSetting({
    required bool value,
    required void Function(bool value) update,
    required Future<void> Function(bool value) persist,
  }) async {
    setState(() => update(value));
    try {
      await persist(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => update(!value));
      _showSnackBar('保存 AI 助手设置失败：$error');
    }
  }

  Future<void> _savePrompt() async {
    if (!mounted || _isSavingPrompt || !_promptDirty) return;
    setState(() => _isSavingPrompt = true);
    try {
      await ChatStorageService.saveCustomPrompt(_promptController.text);
      if (!mounted) return;
      setState(() => _promptDirty = false);
      _showSnackBar('助手提示词已保存');
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('保存助手提示词失败：$error');
    } finally {
      if (mounted) setState(() => _isSavingPrompt = false);
    }
  }

  Future<void> _resetPrompt() async {
    await ChatStorageService.resetPrompt();
    if (!mounted) return;
    setState(() {
      _promptController.text = ChatStorageService.defaultPrompt;
      _promptDirty = false;
      _promptEnabled = true;
    });
    await ChatStorageService.setPromptEnabled(true);
    if (!mounted) return;
    _showSnackBar('已恢复默认助手提示词');
  }

  Future<void> _openModelConfig() async {
    await _savePrompt();
    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      PageTransitions.slideHorizontal(const LLMConfigPage()),
    );
    if (!mounted) return;
    setState(() => _llmConfigFuture = LLMService.getConfig());
  }

  void _showPromptPreview() {
    final prompt = _promptController.text.trim();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('提示词预览'),
        content: SizedBox(
          width: MediaQuery.sizeOf(dialogContext).width * 0.85,
          child: SingleChildScrollView(
            child: SelectableText(
              prompt.isEmpty ? ChatStorageService.defaultPrompt : prompt,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return LiquidGlassSwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: enabled ? onChanged : null,
      semanticLabel: title,
    );
  }

  Widget _buildPromptSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: '助手提示词',
      children: [
        _buildSwitch(
          title: '启用自定义提示词',
          subtitle: '关闭后使用应用内置的默认提示词',
          value: _promptEnabled,
          onChanged: (value) => _setSetting(
            value: value,
            update: (next) => _promptEnabled = next,
            persist: ChatStorageService.setPromptEnabled,
          ),
        ),
        const AppSettingsDivider(indent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _promptController,
            enabled: _promptEnabled,
            minLines: 8,
            maxLines: 18,
            onChanged: (_) {
              if (!_promptDirty) setState(() => _promptDirty = true);
            },
            decoration: InputDecoration(
              labelText: '自定义提示词',
              hintText: '可使用 {now}、{todos} 等变量；待办、日程、账单等上下文会按当前问题注入。',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.25,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: _resetPrompt,
                icon: const Icon(Icons.restore),
                label: const Text('恢复默认'),
              ),
              TextButton.icon(
                onPressed: _showPromptPreview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('预览'),
              ),
              FilledButton.icon(
                onPressed:
                    _promptDirty && !_isSavingPrompt ? _savePrompt : null,
                icon: _isSavingPrompt
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('保存提示词'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: '模型与 API',
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(Icons.hub_outlined, color: colorScheme.primary),
          title: const Text('模型与 API 配置'),
          subtitle: FutureBuilder<LLMConfig?>(
            future: _llmConfigFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text('加载中...', style: TextStyle(fontSize: 12));
              }
              final config = snapshot.data;
              if (config == null || !config.isConfigured) {
                return Text(
                  '未配置；对话和识图功能暂不可用',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.error,
                  ),
                );
              }
              final vision = config.visionModel.trim();
              return Text(
                vision.isEmpty
                    ? '文本模型：${config.model}'
                    : '文本：${config.model} · 多模态：$vision',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                ),
              );
            },
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openModelConfig,
        ),
        const AppSettingsDivider(indent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            '服务商、API Key、文本模型和多模态模型在这里独立管理；本页只控制助手行为和上下文策略。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        widget.isEmbedded
            ? 16
            : floatingGlassSettingsContentTopInset(context, extra: 16),
        16,
        32,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              children: [
                Text(
                  '在这里调整 AI 助手如何理解问题、注入数据和组织回答。所有开关会同步到对话页顶部的快捷设置。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                AppSettingsSection(
                  title: '智能上下文',
                  children: [
                    _buildSwitch(
                      title: '启用智能上下文',
                      subtitle: '按当前问题注入待办、日程、规划、账单等只读数据',
                      value: _smartContext,
                      onChanged: (value) => _setSetting(
                        value: value,
                        update: (next) => _smartContext = next,
                        persist: ChatStorageService.setSmartContextEnabled,
                      ),
                    ),
                    const AppSettingsDivider(indent: 16),
                    _buildSwitch(
                      title: '在输入区显示注入预览',
                      subtitle: '关闭只隐藏 UI 详情，不会停止上下文注入',
                      value: _showContextPreview,
                      enabled: _smartContext,
                      onChanged: (value) => _setSetting(
                        value: value,
                        update: (next) => _showContextPreview = next,
                        persist: ChatStorageService.setShowContextPreview,
                      ),
                    ),
                    const AppSettingsDivider(indent: 16),
                    _buildSwitch(
                      title: '默认扩展上下文范围',
                      subtitle: '相关日期问题默认查看未来 30 天',
                      value: _injectMoreContext,
                      enabled: _smartContext,
                      onChanged: (value) => _setSetting(
                        value: value,
                        update: (next) => _injectMoreContext = next,
                        persist: ChatStorageService.setInjectMoreContext,
                      ),
                    ),
                    const AppSettingsDivider(indent: 16),
                    _buildSwitch(
                      title: '默认开启深度思考',
                      subtitle: '模型支持时附带 thinking 参数，可能增加响应时间和费用',
                      value: _deepThinking,
                      onChanged: (value) => _setSetting(
                        value: value,
                        update: (next) => _deepThinking = next,
                        persist: ChatStorageService.setDeepThinkingEnabled,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildPromptSection(context),
                const SizedBox(height: 8),
                _buildModelSection(context),
                const SizedBox(height: 8),
                AppSettingsSection(
                  title: '协议说明',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'CDT Actions v2 · Smart Context v2\n'
                          '新回复使用带版本的动作信封；历史聊天仍兼容旧版 ACTION 数组。\n'
                          '关闭智能上下文后，助手不会自动读取上述业务数据。',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final standalone = !widget.isEmbedded;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_savePrompt());
      },
      child: Scaffold(
        extendBodyBehindAppBar: standalone,
        appBar: widget.isEmbedded
            ? null
            : FloatingGlassAppBar(
                flexibleSpace: const FloatingGlassTopBarBackground(),
                title: const Text('AI 助手设置'),
              ),
        body: floatingGlassSettingsBody(
          context,
          standalone: standalone,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(context),
        ),
      ),
    );
  }
}
