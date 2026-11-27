import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/ai_device_context_service.dart';
import '../../../services/ai_memory_service.dart';
import '../../../services/permission_request_coordinator.dart';
import '../../../services/chat_storage_service.dart';
import '../../../services/daily_ai_suggestion_service.dart';
import '../../../services/storage/user_session_storage.dart';
import '../../../models/ai_context_mode.dart';
import '../../../models/ai_tool_budget.dart';
import '../../../widgets/ai_context_mode_selector.dart';
import '../../../widgets/ai_tool_budget_dialog.dart';
import '../../../services/llm_service.dart';
import '../../../utils/settings_navigation.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_skeleton.dart';
import '../../../widgets/floating_glass_control.dart';
import '../llm_config_page.dart';
import '../../../utils/app_dialogs.dart';

/// Settings that control how the in-app AI assistant builds and presents a
/// request. Model credentials and model selection remain in [LLMConfigPage].
class AiAssistantSettingsPage extends StatefulWidget {
  static const String dailyAiSuggestionTarget = 'daily_ai_suggestion';

  final bool isEmbedded;
  final String? initialTarget;

  const AiAssistantSettingsPage({
    super.key,
    this.isEmbedded = false,
    this.initialTarget,
  });

  @override
  State<AiAssistantSettingsPage> createState() =>
      _AiAssistantSettingsPageState();
}

class _AiAssistantSettingsPageState extends State<AiAssistantSettingsPage>
    with SettingsTargetHighlightMixin<AiAssistantSettingsPage> {
  final GlobalKey _modelConfigKey = GlobalKey();
  final GlobalKey _dailyAiSuggestionKey = GlobalKey();
  final TextEditingController _promptController = TextEditingController();

  @override
  GlobalKey? resolveSettingsTargetKey(String target) => switch (target) {
    AiAssistantSettingsPage.dailyAiSuggestionTarget => _dailyAiSuggestionKey,
    _ => null,
  };

  bool _isLoading = true;
  bool _isSavingPrompt = false;
  bool _smartContext = true;
  AiContextMode _contextMode = AiContextMode.functionCalling;
  AiToolBudget _toolBudget = AiToolBudget.standard;
  bool _showContextPreview = false;
  bool _injectMoreContext = false;
  bool _deepThinking = true;
  bool _promptEnabled = true;
  bool _promptDirty = false;
  bool _dailyAiSuggestionEnabled = false;
  bool _dailyAiManualSectionKept = false;
  DailyAiSuggestionContextConfig _dailyAiContextConfig =
      const DailyAiSuggestionContextConfig();
  bool _aiMemoryEnabled = true;
  PermissionStatus _locationPermissionStatus = PermissionStatus.denied;
  List<AiMemoryItem> _aiMemories = const [];
  String? _currentUsername;
  late Future<LLMConfig?> _llmConfigFuture;

  @override
  void initState() {
    super.initState();
    _llmConfigFuture = LLMService.getConfig();
    AiMemoryService.revision.addListener(_onMemoryRevisionChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    AiMemoryService.revision.removeListener(_onMemoryRevisionChanged);
    _promptController.dispose();
    super.dispose();
  }

  void _onMemoryRevisionChanged() {
    if (!mounted || _isLoading) return;
    unawaited(_reloadMemories());
  }

  Future<void> _reloadMemories() async {
    final enabled = await AiMemoryService.isEnabled(_currentUsername);
    final memories = await AiMemoryService.loadMemories(_currentUsername);
    if (!mounted) return;
    setState(() {
      _aiMemoryEnabled = enabled;
      _aiMemories = memories;
    });
  }

  Future<void> _loadSettings() async {
    final username = await UserSessionStorage.getCurrentUsername();
    final values = await Future.wait<dynamic>([
      ChatStorageService.getCustomPrompt(),
      ChatStorageService.isPromptEnabled(),
      ChatStorageService.isSmartContextEnabled(),
      ChatStorageService.shouldShowContextPreview(),
      ChatStorageService.shouldInjectMoreContext(),
      ChatStorageService.isDeepThinkingEnabled(),
      ChatStorageService.getContextMode(),
      ChatStorageService.getToolBudget(),
      DailyAiSuggestionService.isEnabled(username),
      DailyAiSuggestionService.isManualSectionKept(username),
      DailyAiSuggestionService.loadContextConfig(username),
      AiMemoryService.isEnabled(username),
      AiMemoryService.loadMemories(username),
      AiDeviceContextService.getLocationPermissionStatus(),
    ]);
    if (!mounted) return;
    _promptController.text = values[0] as String;
    setState(() {
      _currentUsername = username;
      _promptEnabled = values[1] as bool;
      _smartContext = values[2] as bool;
      _showContextPreview = values[3] as bool;
      _injectMoreContext = values[4] as bool;
      _deepThinking = values[5] as bool;
      _contextMode = values[6] as AiContextMode;
      _toolBudget = values[7] as AiToolBudget;
      _dailyAiSuggestionEnabled = values[8] as bool;
      _dailyAiManualSectionKept = values[9] as bool;
      _dailyAiContextConfig = values[10] as DailyAiSuggestionContextConfig;
      _aiMemoryEnabled = values[11] as bool;
      _aiMemories = values[12] as List<AiMemoryItem>;
      _locationPermissionStatus = values[13] as PermissionStatus;
      _isLoading = false;
    });
    scheduleInitialSettingsTarget(widget.initialTarget);
  }

  Future<void> _requestLocationPermission() async {
    final result = await PermissionRequestCoordinator(context: context)
        .request(AppPermissionKind.location, fallbackToSettingsOnDenied: true);
    if (!mounted) return;
    setState(() {
      _locationPermissionStatus = result.status;
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

  Future<void> _setContextMode(AiContextMode mode) async {
    final previous = _contextMode;
    setState(() => _contextMode = mode);
    try {
      await ChatStorageService.setContextMode(mode);
    } catch (error) {
      if (!mounted) return;
      setState(() => _contextMode = previous);
      _showSnackBar('保存上下文模式失败：$error');
    }
  }

  Future<void> _editToolBudget() async {
    final next = await showAiToolBudgetDialog(
      context,
      initialBudget: _toolBudget,
    );
    if (next == null || next == _toolBudget) return;
    final previous = _toolBudget;
    setState(() => _toolBudget = next);
    try {
      await ChatStorageService.setToolBudget(next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _toolBudget = previous);
      _showSnackBar('保存工具调用预算失败：$error');
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
    await SettingsNavigation.push<bool>(
      context: context,
      page: LLMConfigPage(isEmbedded: widget.isEmbedded),
      sourceKey: _modelConfigKey,
      isEmbedded: widget.isEmbedded,
      settings: const RouteSettings(name: '模型与 API 配置'),
    );
    if (!mounted) return;
    final llmConfigFuture = LLMService.getConfig();
    setState(() {
      _llmConfigFuture = llmConfigFuture;
    });
  }

  void _showPromptPreview() {
    final prompt = _promptController.text.trim();
    showAppDialog<void>(
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
    AppSnackBars.showSnackBar(context, SnackBar(content: Text(message)));
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
              hintText: '可使用 {now}、{todos} 等变量；业务数据按所选模式查询或注入。',
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
                onPressed: _promptDirty && !_isSavingPrompt
                    ? _savePrompt
                    : null,
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

  Future<void> _showMemoryEditorDialog({AiMemoryItem? existing}) async {
    final controller = TextEditingController(text: existing?.content ?? '');
    final result = await showAppDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? '添加 AI 记忆' : '编辑 AI 记忆'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: AiMemoryService.maxItemLength,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '例如：晚上 22:00 后不安排高强度学习 / 回复尽量简短直接',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty) {
      _showSnackBar('记忆内容不能为空');
      return;
    }
    if (existing == null) {
      await AiMemoryService.addMemory(
        _currentUsername,
        trimmed,
        source: 'manual',
      );
    } else {
      await AiMemoryService.updateMemory(
        _currentUsername,
        existing.id,
        trimmed,
      );
    }
    await _reloadMemories();
  }

  Future<void> _confirmClearMemories() async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: '清空 AI 记忆',
      message: '确定清空已保存的所有个人偏好记忆吗？清空后无法恢复。',
      confirmLabel: '清空',
    );
    if (!confirmed) return;
    await AiMemoryService.clearMemories(_currentUsername);
    await _reloadMemories();
    if (mounted) _showSnackBar('已清空 AI 记忆');
  }

  Widget _buildMemorySection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: 'AI 记忆（个人偏好）',
      children: [
        _buildSwitch(
          title: '启用 AI 记忆',
          subtitle:
              '记住你的作息、偏好和回复风格，同时用于 AI 对话与今日 AI 建议（最多 ${AiMemoryService.maxItems} 条）',
          value: _aiMemoryEnabled,
          onChanged: (value) => _setSetting(
            value: value,
            update: (next) => _aiMemoryEnabled = next,
            persist: (next) =>
                AiMemoryService.setEnabled(_currentUsername, next),
          ),
        ),
        const AppSettingsDivider(indent: 16),
        if (_aiMemories.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '暂无记忆。可在下方手动添加，或在对话中说“记住我…”让 AI 自动保存。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < _aiMemories.length; i++) ...[
            if (i > 0) const AppSettingsDivider(indent: 16),
            ListTile(
              enabled: _aiMemoryEnabled,
              contentPadding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
              title: Text(
                _aiMemories[i].content,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                _aiMemories[i].source == 'ai' ? '对话中记住' : '手动添加',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: _aiMemoryEnabled
                  ? () => _showMemoryEditorDialog(existing: _aiMemories[i])
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                tooltip: '删除记忆',
                onPressed: () async {
                  await AiMemoryService.deleteMemory(
                    _currentUsername,
                    _aiMemories[i].id,
                  );
                  await _reloadMemories();
                },
              ),
            ),
          ],
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _aiMemoryEnabled
                    ? () => _showMemoryEditorDialog()
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加偏好记忆'),
              ),
              const Spacer(),
              if (_aiMemories.isNotEmpty)
                TextButton.icon(
                  onPressed: _confirmClearMemories,
                  icon: Icon(
                    Icons.delete_sweep_outlined,
                    size: 18,
                    color: colorScheme.error,
                  ),
                  label: Text('清空', style: TextStyle(color: colorScheme.error)),
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
          key: _modelConfigKey,
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
                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                );
              }
              final vision = config.visionModel.trim();
              return Text(
                vision.isEmpty
                    ? '文本模型：${config.model}'
                    : '文本：${config.model} · 多模态：$vision',
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
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
        widget.isEmbedded ? 16 : floatingGlassSettingsContentTopInset(context),
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
                      subtitle: '允许助手通过所选模式读取待办、日程、账单等业务数据',
                      value: _smartContext,
                      onChanged: (value) => _setSetting(
                        value: value,
                        update: (next) => _smartContext = next,
                        persist: ChatStorageService.setSmartContextEnabled,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AiContextModeSelector(
                          value: _contextMode,
                          onChanged: _setContextMode,
                        ),
                      ),
                    ),
                    const AppSettingsDivider(indent: 16),
                    ListTile(
                      enabled:
                          _smartContext &&
                          _contextMode == AiContextMode.functionCalling,
                      title: const Text('单轮工具调用预算'),
                      subtitle: Text(_toolBudget.summaryLabel),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap:
                          _smartContext &&
                              _contextMode == AiContextMode.functionCalling
                          ? _editToolBudget
                          : null,
                    ),
                    const AppSettingsDivider(indent: 16),
                    _buildSwitch(
                      title: '在输入区显示注入预览',
                      subtitle: '关闭只隐藏 UI 详情，不会停止上下文注入',
                      value: _showContextPreview,
                      enabled:
                          _smartContext &&
                          _contextMode == AiContextMode.smartContextInjection,
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
                      enabled:
                          _smartContext &&
                          _contextMode == AiContextMode.smartContextInjection,
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
                    if (AiDeviceContextService.supportsNativeLocation) ...[
                      const AppSettingsDivider(indent: 16),
                      ListTile(
                        title: const Text('位置权限（函数调用基础信息）'),
                        subtitle: Text(
                          _locationPermissionStatus.isGranted ||
                                  _locationPermissionStatus.isLimited
                              ? '已提前授权，AI 助手可按需查询当前城市、位置与时区'
                              : _locationPermissionStatus.isPermanentlyDenied
                              ? '已被拒绝，点击前往系统设置开启位置权限'
                              : '未授权；可提前授权供函数调用读取所在位置与时区',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: _requestLocationPermission,
                          child: Text(
                            _locationPermissionStatus.isGranted ||
                                    _locationPermissionStatus.isLimited
                                ? '已授权'
                                : _locationPermissionStatus.isPermanentlyDenied
                                ? '去设置'
                                : '提前授权',
                          ),
                        ),
                        onTap: _requestLocationPermission,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  key: _dailyAiSuggestionKey,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color:
                        highlightTarget ==
                            AiAssistantSettingsPage.dailyAiSuggestionTarget
                        ? colorScheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: AppSettingsSection(
                    title: '每日 AI 建议',
                    children: [
                      _buildSwitch(
                        title: '每天首次打开生成今日建议',
                        subtitle: '每天首次打开 App 时自动调用 AI 结合待办与日程生成建议，置顶展示在首页第一页',
                        value: _dailyAiSuggestionEnabled,
                        onChanged: (value) => _setSetting(
                          value: value,
                          update: (next) => _dailyAiSuggestionEnabled = next,
                          persist: (next) =>
                              DailyAiSuggestionService.setEnabled(
                                _currentUsername,
                                next,
                              ),
                        ),
                      ),
                      const AppSettingsDivider(indent: 16),
                      _buildSwitch(
                        title: '在首页保留板块（手动生成）',
                        subtitle: '关闭自动生成时，仍在首页保留「今日 AI 建议」板块，仅在手动点击时调用 AI',
                        value: _dailyAiManualSectionKept,
                        enabled: !_dailyAiSuggestionEnabled,
                        onChanged: (value) => _setSetting(
                          value: value,
                          update: (next) => _dailyAiManualSectionKept = next,
                          persist: (next) =>
                              DailyAiSuggestionService.setManualSectionKept(
                                _currentUsername,
                                next,
                              ),
                        ),
                      ),
                      const AppSettingsDivider(indent: 16),
                      ListTile(
                        enabled:
                            _dailyAiSuggestionEnabled ||
                            _dailyAiManualSectionKept,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        leading: Icon(
                          Icons.refresh_rounded,
                          color:
                              (_dailyAiSuggestionEnabled ||
                                  _dailyAiManualSectionKept)
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: const Text('立即重新生成今日建议'),
                        subtitle: const Text(
                          '清除今日缓存并重新调用 AI 生成，若今天曾关闭卡片也会重新展示',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap:
                            (_dailyAiSuggestionEnabled ||
                                _dailyAiManualSectionKept)
                            ? () async {
                                await DailyAiSuggestionService.requestRegenerate(
                                  _currentUsername,
                                );
                                if (!mounted) return;
                                _showSnackBar('已触发重新生成，返回首页即可查看最新今日建议');
                              }
                            : null,
                      ),
                      const AppSettingsDivider(indent: 16),
                      ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        leading: Icon(
                          Icons.tune_rounded,
                          color: colorScheme.primary,
                        ),
                        title: const Text('纳入建议的上下文'),
                        subtitle: Text(
                          '默认全部开启（已启用 ${_dailyAiContextConfig.enabledCount}/${DailyAiContextOption.values.length} 项），可按需关闭',
                        ),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        children: [
                          for (final option in DailyAiContextOption.values) ...[
                            const AppSettingsDivider(indent: 16),
                            _buildSwitch(
                              title: option.title,
                              subtitle: option.subtitle,
                              value: _dailyAiContextConfig.isEnabled(option),
                              onChanged: (value) => _setSetting(
                                value: value,
                                update: (next) {
                                  _dailyAiContextConfig = _dailyAiContextConfig
                                      .copyWithOption(option, next);
                                },
                                persist: (next) =>
                                    DailyAiSuggestionService.setContextOption(
                                      _currentUsername,
                                      option,
                                      next,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildMemorySection(context),
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
                          '默认使用工具查询：模型选择查询条件，App 回传只读结果后继续回答。\n'
                          '工具查询需要支持原生 Function Calling 的模型；不支持时可切换智能注入。\n'
                          '关闭智能上下文后，两种模式都不会读取新的业务数据。',
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
              ? AppSkeletonSettingsPage(
                  topPadding: standalone
                      ? floatingGlassSettingsContentTopInset(context)
                      : 16,
                  sectionCount: 3,
                  rowsPerSection: 3,
                )
              : _buildContent(context),
        ),
      ),
    );
  }
}
