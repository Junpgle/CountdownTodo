import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_service.dart';
import '../../services/background_notification_service.dart';
import '../../services/minor_mode_policy.dart';
import '../../services/minor_mode_service.dart';
import '../../services/pomodoro_sync_service.dart';
import '../../storage_service.dart';
import '../../widgets/floating_glass_control.dart';

class ServerChoicePage extends StatefulWidget {
  final String initialServerChoice;
  final bool isEmbedded;

  const ServerChoicePage({
    super.key,
    required this.initialServerChoice,
    this.isEmbedded = false,
  });

  @override
  State<ServerChoicePage> createState() => _ServerChoicePageState();
}

class _ServerChoicePageState extends State<ServerChoicePage> {
  late String _selectedServer;

  @override
  void initState() {
    super.initState();
    _selectedServer = ApiService.normalizeServerChoice(
      widget.initialServerChoice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('云端数据接口线路'),
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            floatingGlassSettingsContentTopInset(context),
            16,
            16,
          ),
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_queue,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '选择接口线路',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRouteNotice(),
                    const SizedBox(height: 16),
                    _buildServerOption(
                      value: ApiService.serverChoiceAliyunDirect,
                      title: '阿里云直连（HTTP）',
                      description: '优点：链路更短，通常延迟更低；不依赖 Cloudflare 中转。\n'
                          '注意：客户端到服务器之间不是加密连接，不建议在公共 Wi-Fi 等不可信网络下使用。',
                      icon: Icons.speed_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildServerOption(
                      value: ApiService.serverChoiceCloudflare,
                      title: 'Cloudflare 中转（HTTPS）',
                      description: '优点：客户端到中转入口使用 HTTPS，兼容性和公共网络安全性更好。\n'
                          '不足：多经过一层中转，可能增加少量延迟，并依赖 Cloudflare 线路与代理配置。',
                      icon: Icons.shield_outlined,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _handleServerChange,
                icon: const Icon(Icons.save),
                label: const Text('保存设置'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteNotice() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '两条线路指向同一套阿里云生产数据。切换不会迁移或删除数据，当前登录状态保持不变；实时同步通道会在保存后自动重连。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerOption({
    required String value,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedServer == value;
    final titleColor = isSelected ? colorScheme.primary : colorScheme.onSurface;
    final iconColor =
        isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () => setState(() => _selectedServer = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color:
                isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, color: colorScheme.primary),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleServerChange() async {
    final currentChoice = ApiService.normalizeServerChoice(
      widget.initialServerChoice,
    );
    if (_selectedServer == currentChoice) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换接口线路'),
        content: const Text(
          '两条线路使用同一套阿里云账户和数据。确定切换吗？保存后当前请求会使用新线路，实时同步会自动重连。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('切换线路'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.sensitive,
    );
    if (!authorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              MinorModeService.instance.authorizationFailureMessage(
                MinorModeAction.sensitive,
              ),
            ),
          ),
        );
      }
      return;
    }

    await StorageService.saveServerChoice(_selectedServer);
    unawaited(PomodoroSyncService.instance.manualReconnect());
    unawaited(_refreshBackgroundNotificationPoll());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到 $_selectedRouteTitle')),
      );
      Navigator.pop(context);
    }
  }

  String get _selectedRouteTitle =>
      _selectedServer == ApiService.serverChoiceCloudflare
          ? 'Cloudflare HTTPS 中转'
          : '阿里云 HTTP 直连';

  Future<void> _refreshBackgroundNotificationPoll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('current_user_id');
      var token = ApiService.getToken();
      if (token == null || token.isEmpty) {
        token = await StorageService.getAuthToken();
      }
      if (userId == null || userId <= 0 || token == null || token.isEmpty) {
        return;
      }
      await BackgroundNotificationService.configureNotificationPoll(
        userId: userId,
        token: token,
        apiBaseUrl: ApiService.effectiveBaseUrl,
      );
    } catch (_) {
      // The in-app route is already updated; retry background setup later on
      // the next login/dashboard lifecycle if the native channel is unavailable.
    }
  }
}
