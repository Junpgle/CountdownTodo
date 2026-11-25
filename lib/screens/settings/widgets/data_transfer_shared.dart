import 'package:flutter/material.dart';

import '../../../services/minor_mode_policy.dart';
import '../../../services/minor_mode_service.dart';
import '../../../utils/app_dialogs.dart';
import '../../../widgets/floating_glass_control.dart';

/// 校验未成年人模式下的导入/导出操作权限，被拒绝时弹出统一提示。
Future<bool> authorizeMinorModeDataTransfer(
  BuildContext context,
  MinorModeAction action,
) async {
  final authorized = await MinorModeService.instance.authorizeAction(action);
  if (!authorized && context.mounted) {
    AppSnackBars.showSnackBar(
      context,
      SnackBar(
        content: Text(
          MinorModeService.instance.authorizationFailureMessage(action),
        ),
      ),
    );
  }
  return authorized;
}

/// 数据导入/导出页面共用的宽窄屏响应式页面骨架。
class DataTransferScaffold extends StatelessWidget {
  final String title;
  final bool isEmbedded;
  final bool isLoading;
  final List<Widget> primaryChildren;
  final List<Widget> secondaryChildren;
  final List<Widget> narrowChildren;

  const DataTransferScaffold({
    super.key,
    required this.title,
    required this.isEmbedded,
    this.isLoading = false,
    required this.primaryChildren,
    required this.secondaryChildren,
    required this.narrowChildren,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final isWideScreen = screenWidth > 600;
    final standalone = !isEmbedded && !isWideScreen;
    final useWideLayout = isLandscape || isWideScreen;

    return Scaffold(
      extendBodyBehindAppBar: standalone,
      appBar: isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: Text(title),
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: standalone,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : useWideLayout
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: primaryChildren,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: secondaryChildren,
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  standalone
                      ? floatingGlassSettingsContentTopInset(context)
                      : 16,
                  16,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: narrowChildren,
                ),
              ),
      ),
    );
  }
}

/// 数据传输页统一区块卡片，支持可选图标标题与内容列。
class DataTransferSectionCard extends StatelessWidget {
  final IconData? icon;
  final String? title;
  final double titleFontSize;
  final double headerSpacing;
  final List<Widget> children;

  const DataTransferSectionCard({
    super.key,
    this.icon,
    this.title,
    this.titleFontSize = 15,
    this.headerSpacing = 12,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleTextStyle = TextStyle(
      fontSize: titleFontSize,
      fontWeight: FontWeight.bold,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              if (icon != null)
                Row(
                  children: [
                    Icon(icon, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(title!, style: titleTextStyle),
                  ],
                )
              else
                Text(title!, style: titleTextStyle),
              SizedBox(height: headerSpacing),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 数据传输页全宽主操作按钮（导出/导入），使用 Material 3 `onPrimary` 指示器颜色。
class DataTransferPrimaryActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isBusy;
  final IconData icon;
  final String label;
  final String busyLabel;

  const DataTransferPrimaryActionButton({
    super.key,
    required this.onPressed,
    required this.isBusy,
    required this.icon,
    required this.label,
    required this.busyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: isBusy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              )
            : Icon(icon),
        label: Text(isBusy ? busyLabel : label),
      ),
    );
  }
}
