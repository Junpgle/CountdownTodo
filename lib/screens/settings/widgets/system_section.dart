import 'dart:io';
import 'package:flutter/material.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_state_views.dart';

class SystemSection extends StatelessWidget {
  final String? highlightTarget;
  final Map<String, GlobalKey>? itemKeys; // 🚀 新增
  final VoidCallback? onOpenCalendarSync;
  final VoidCallback onOpenFeatureGuide;
  final String cacheSizeStr;
  final VoidCallback onClearCache;
  final VoidCallback onShowStorageAnalysis;
  final bool isCheckingUpdate;
  final VoidCallback onCheckUpdates;

  const SystemSection({
    super.key,
    this.highlightTarget,
    this.itemKeys,
    this.onOpenCalendarSync,
    required this.onOpenFeatureGuide,
    required this.cacheSizeStr,
    required this.onClearCache,
    required this.onShowStorageAnalysis,
    required this.isCheckingUpdate,
    required this.onCheckUpdates,
  });

  Widget _buildTile({
    required BuildContext context,
    required String targetId,
    required Widget child,
  }) {
    return AppSettingsHighlightedTile(
      targetId: targetId,
      highlightTarget: highlightTarget,
      itemKeys: itemKeys,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: '系统与关于',
      children: [
        _buildTile(
          context: context,
          targetId: 'feature_guide',
          child: ListTile(
            leading: Icon(Icons.school_rounded, color: colorScheme.primary),
            title: const Text('重新查看新版教程与权限设置'),
            subtitle: const Text('可再次查看功能介绍与重新配置各项权限'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenFeatureGuide,
          ),
        ),
        if (onOpenCalendarSync != null) ...[
          const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'calendar_sync',
            child: ListTile(
              leading: Icon(Icons.event_available_outlined,
                  color: colorScheme.secondary),
              title: const Text('写入手机系统日历'),
              subtitle: const Text('选择待办、课程、倒数日写入或清除'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenCalendarSync,
            ),
          ),
        ],
        if (!Platform.isWindows) ...[
          const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'cache',
            child: ListTile(
              leading: Icon(Icons.cleaning_services,
                  color: Theme.of(context).colorScheme.secondary),
              title: const Text('深度清理缓存与冗余'),
              subtitle: const Text('包含更新残留包与深度图片缓存'),
              trailing: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  cacheSizeStr,
                  key: ValueKey(cacheSizeStr),
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold),
                ),
              ),
              onTap: onClearCache,
            ),
          ),
          const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'storage',
            child: ListTile(
              leading: Icon(Icons.data_usage, color: colorScheme.cdtWarning),
              title: const Text('存储空间深度分析'),
              subtitle: const Text('找出占用数百MB的隐藏文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onShowStorageAnalysis,
            ),
          ),
        ],
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'about',
          child: ListTile(
            leading: Icon(Icons.system_update, color: colorScheme.cdtSuccess),
            title: const Text('检查新版本'),
            trailing: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: isCheckingUpdate
                  ? const AppLoadingIndicator(
                      key: ValueKey('checking'),
                    )
                  : const Icon(
                      Icons.chevron_right,
                      key: ValueKey('ready'),
                    ),
            ),
            onTap: isCheckingUpdate ? null : onCheckUpdates,
          ),
        ),
      ],
    );
  }
}
