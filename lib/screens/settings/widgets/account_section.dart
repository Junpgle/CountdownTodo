import 'package:flutter/material.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_state_views.dart';

class AccountSection extends StatelessWidget {
  final String username;
  final int? userId;
  final String userTier;
  final double syncProgress;
  final bool isLoadingStatus;
  final VoidCallback onRefreshStatus;
  final VoidCallback onForceFullSync;
  final VoidCallback onLogout;
  final VoidCallback onChangePassword;

  const AccountSection({
    super.key,
    required this.username,
    required this.userId,
    required this.userTier,
    required this.syncProgress,
    required this.isLoadingStatus,
    required this.onRefreshStatus,
    required this.onForceFullSync,
    required this.onLogout,
    required this.onChangePassword,
  });

  Color getTierColor(String tier, ColorScheme colorScheme) {
    switch (tier.toLowerCase()) {
      case 'admin':
        return colorScheme.error;
      case 'promax':
        return colorScheme.primary;
      case 'pro':
        return colorScheme.cdtWarning;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: '账户管理',
      children: [
        InkWell(
          onTap: onChangePassword,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.person)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(userId != null ? "UID: $userId" : "离线模式",
                          style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.edit_square,
                    size: 20, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const AppSettingsDivider(),
        Padding(
          padding:
              const EdgeInsets.only(left: 56, right: 16, top: 12, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("账户等级", style: TextStyle(fontSize: 14)),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: isLoadingStatus
                        ? const AppLoadingIndicator(
                            key: ValueKey('loading'),
                            size: 14,
                          )
                        : Text(
                            userTier.toUpperCase(),
                            key: ValueKey(userTier),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: getTierColor(userTier, colorScheme),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text("今日同步额度",
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: syncProgress,
                  minHeight: 6,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(syncProgress > 0.9
                      ? colorScheme.error
                      : Theme.of(context).colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
        const AppSettingsDivider(),
        ListTile(
          leading: Icon(Icons.cloud_sync, color: colorScheme.primary),
          title: const Text('强制全量同步'),
          subtitle: const Text('重置同步水位，从云端拉取所有最新数据'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onForceFullSync,
        ),
        const AppSettingsDivider(),
        ListTile(
          leading: Icon(Icons.logout, color: colorScheme.error),
          title: Text('退出当前账号',
              style: TextStyle(
                  color: colorScheme.error, fontWeight: FontWeight.w600)),
          onTap: onLogout,
        ),
      ],
    );
  }
}
