import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_state_views.dart';

class PermissionSection extends StatelessWidget {
  final List<Map<String, dynamic>> permissionDefs;
  final Map<String, PermissionStatus?> permissionStatuses;
  final bool isCheckingPermissions;
  final VoidCallback onCheckAllPermissions;
  final Function(String) onRequestOrOpenPermission;

  const PermissionSection({
    super.key,
    required this.permissionDefs,
    required this.permissionStatuses,
    required this.isCheckingPermissions,
    required this.onCheckAllPermissions,
    required this.onRequestOrOpenPermission,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!AppPlatform.isAndroid && !AppPlatform.isIOS) {
      return const AppEmptyState(
        icon: Icons.shield_outlined,
        title: '桌面端无需管理权限',
        message: '当前平台 (macOS / Windows / Linux) 的系统权限由底层自动分配和托管，您无需在此手动授权。',
      );
    }

    final allGranted = permissionDefs.every((def) {
      final status = permissionStatuses[def['key'] as String];
      return status == PermissionStatus.granted ||
          status == PermissionStatus.limited;
    });
    final undoneCount = permissionDefs.where((d) {
      final s = permissionStatuses[d['key'] as String];
      return s != null &&
          s != PermissionStatus.granted &&
          s != PermissionStatus.limited;
    }).length;

    final statusColor =
        allGranted ? colorScheme.cdtSuccess : colorScheme.cdtWarning;

    return AppSettingsSection(
      title: '权限管理',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (permissionStatuses.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                allGranted ? '全部已授权' : '$undoneCount 项未授权',
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: isCheckingPermissions ? null : onCheckAllPermissions,
            visualDensity: VisualDensity.compact,
            icon: isCheckingPermissions
                ? const AppLoadingIndicator(size: 16)
                : Icon(Icons.refresh,
                    size: 18, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      children: [
        for (int i = 0; i < permissionDefs.length; i++) ...[
          if (i > 0) const AppSettingsDivider(),
          _buildPermissionTile(context, permissionDefs[i]),
        ],
      ],
    );
  }

  Widget _buildPermissionTile(BuildContext context, Map<String, dynamic> def) {
    final String key = def['key'] as String;
    final String label = def['label'] as String;
    final String desc = def['desc'] as String;
    final IconData icon = def['icon'] as IconData;
    final bool critical = def['critical'] as bool;
    final colorScheme = Theme.of(context).colorScheme;
    final Color color = _permissionColor(colorScheme, key, critical);

    final PermissionStatus? status = permissionStatuses[key];
    final bool granted = status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
    final bool denied = status != null && !granted;

    Widget statusIcon;
    if (isCheckingPermissions && status == null) {
      statusIcon = const SizedBox(
          key: ValueKey('checking'), child: AppLoadingIndicator(size: 18));
    } else if (status == null) {
      statusIcon = Icon(
        Icons.help_outline,
        key: const ValueKey('unknown'),
        size: 20,
        color: colorScheme.onSurfaceVariant,
      );
    } else if (granted) {
      statusIcon = Icon(
        Icons.check_circle,
        key: const ValueKey('granted'),
        size: 20,
        color: colorScheme.cdtSuccess,
      );
    } else {
      statusIcon = Icon(
        critical ? Icons.error : Icons.warning_amber_rounded,
        key: ValueKey('denied_${critical ? 'critical' : 'warning'}'),
        size: 20,
        color: critical ? colorScheme.error : colorScheme.cdtWarning,
      );
    }

    statusIcon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: statusIcon,
    );

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: denied && critical ? colorScheme.error : null)),
          if (critical) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('必要',
                  style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
      subtitle: Text(desc,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusIcon,
          if (denied) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => onRequestOrOpenPermission(key),
              style: FilledButton.styleFrom(
                minimumSize: const Size(60, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('去开启', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Color _permissionColor(ColorScheme colorScheme, String key, bool isCritical) {
    if (isCritical) return colorScheme.error;
    return switch (key) {
      'storage' => colorScheme.secondary,
      'usage_stats' => colorScheme.tertiary,
      'request_install' => colorScheme.cdtInfo,
      _ => colorScheme.primary,
    };
  }
}
