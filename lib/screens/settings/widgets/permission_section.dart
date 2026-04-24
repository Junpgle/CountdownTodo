import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

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
    if (!Platform.isAndroid && !Platform.isIOS) return const SizedBox.shrink();

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Row(
            children: [
              const Text('权限管理',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(width: 8),
              if (permissionStatuses.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: allGranted
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    allGranted ? '全部已授权' : '$undoneCount 项未授权',
                    style: TextStyle(
                        fontSize: 11,
                        color: allGranted ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: isCheckingPermissions ? null : onCheckAllPermissions,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: isCheckingPermissions
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 18, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              for (int i = 0; i < permissionDefs.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                _buildPermissionTile(context, permissionDefs[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionTile(BuildContext context, Map<String, dynamic> def) {
    final String key = def['key'] as String;
    final String label = def['label'] as String;
    final String desc = def['desc'] as String;
    final IconData icon = def['icon'] as IconData;
    final Color color = def['color'] as Color;
    final bool critical = def['critical'] as bool;

    final PermissionStatus? status = permissionStatuses[key];
    final bool granted = status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
    final bool denied = status != null && !granted;

    Widget statusIcon;
    if (isCheckingPermissions && status == null) {
      statusIcon = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (status == null) {
      statusIcon = const Icon(Icons.help_outline, size: 20, color: Colors.grey);
    } else if (granted) {
      statusIcon =
          const Icon(Icons.check_circle, size: 20, color: Colors.green);
    } else {
      statusIcon = Icon(
        critical ? Icons.error : Icons.warning_amber_rounded,
        size: 20,
        color: critical ? Colors.redAccent : Colors.orange,
      );
    }

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
                  color: denied && critical ? Colors.redAccent : null)),
          if (critical) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('必要',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
      subtitle: Text(desc,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
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
}
