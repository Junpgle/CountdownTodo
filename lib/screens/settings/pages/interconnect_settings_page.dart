import 'package:flutter/material.dart';

import '../../../utils/app_platform.dart';
import '../../../utils/page_transitions.dart';
import '../../band_sync_screen.dart';
import '../lan_sync_screen.dart';
import '../calendar_sync_page.dart';
import '../batch_tag_page.dart';
import 'data_export_page.dart';
import 'data_import_page.dart';

class InterconnectSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  final String username;
  const InterconnectSettingsPage(
      {super.key,
      this.initialTarget,
      this.isEmbedded = false,
      required this.username});

  @override
  State<InterconnectSettingsPage> createState() =>
      _InterconnectSettingsPageState();
}

class _InterconnectSettingsPageState extends State<InterconnectSettingsPage> {
  final Map<String, GlobalKey> _itemKeys = {
    'lan_sync': GlobalKey(),
    'band_sync': GlobalKey(),
    'calendar_sync': GlobalKey(),
    'batch_tag': GlobalKey(),
    'data_export': GlobalKey(),
    'data_import': GlobalKey(),
  };

  String? _highlightTarget;

  @override
  void initState() {
    super.initState();
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget(widget.initialTarget!);
      });
    }
  }

  void _scrollToTarget(String target) {
    final key = _itemKeys[target];
    if (key?.currentContext != null) {
      setState(() => _highlightTarget = target);
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) setState(() => _highlightTarget = null);
      });
    }
  }

  Widget _buildTile({required String targetId, required Widget child}) {
    final bool isHighlighted = _highlightTarget == targetId;
    return Container(
      key: _itemKeys[targetId],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }

  Widget _buildFeatureCard({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildTile(
      targetId: id,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(icon, color: colorScheme.onPrimaryContainer, size: 28),
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = AppPlatform.isWeb;
    final featureCards = <Widget>[
      if (!isWeb) ...[
        _buildFeatureCard(
          id: 'lan_sync',
          icon: Icons.wifi_tethering,
          title: '局域网同步',
          subtitle: '同账号设备间无缝互传数据',
          onTap: () {
            Navigator.push(
              context,
              PageTransitions.slideHorizontal(
                LanSyncScreen(isEmbedded: widget.isEmbedded),
                settings: const RouteSettings(name: '局域网互传与同步'),
              ),
            );
          },
        ),
        _buildFeatureCard(
          id: 'band_sync',
          icon: Icons.watch_outlined,
          title: '小米手环',
          subtitle: '借助快应用将待办同步至手环',
          onTap: () {
            Navigator.push(
              context,
              PageTransitions.slideHorizontal(
                BandSyncScreen(isEmbedded: widget.isEmbedded),
                settings: const RouteSettings(name: '智能手环同步'),
              ),
            );
          },
        ),
        _buildFeatureCard(
          id: 'calendar_sync',
          icon: Icons.calendar_month,
          title: '系统日历',
          subtitle: '将软件内课表双向同步至系统',
          onTap: () {
            Navigator.push(
              context,
              PageTransitions.slideHorizontal(
                CalendarSyncPage(isEmbedded: widget.isEmbedded),
                settings: const RouteSettings(name: '日历同步向导'),
              ),
            );
          },
        ),
      ],
      if (isWeb)
        _buildFeatureCard(
          id: 'calendar_sync',
          icon: Icons.calendar_month,
          title: '日历 ICS',
          subtitle: '导出课程、待办、倒数日和规划',
          onTap: () {
            Navigator.push(
              context,
              PageTransitions.slideHorizontal(
                CalendarSyncPage(isEmbedded: widget.isEmbedded),
                settings: const RouteSettings(name: '导出日历文件'),
              ),
            );
          },
        ),
      _buildFeatureCard(
        id: 'batch_tag',
        icon: Icons.label_outlined,
        title: '批量标签',
        subtitle: '为番茄钟和时间日志批量添加标签',
        onTap: () {
          Navigator.push(
            context,
            PageTransitions.slideHorizontal(
              BatchTagPage(
                username: widget.username,
                isEmbedded: widget.isEmbedded,
              ),
              settings: const RouteSettings(name: '批量添加标签'),
            ),
          );
        },
      ),
      _buildFeatureCard(
        id: 'data_export',
        icon: Icons.upload_file,
        title: '数据导出',
        subtitle: isWeb ? '下载为浏览器文件' : '将待办、课程、倒计时等数据导出为文件',
        onTap: () {
          Navigator.push(
            context,
            PageTransitions.slideHorizontal(
              DataExportPage(isEmbedded: widget.isEmbedded),
              settings: const RouteSettings(name: '数据导出'),
            ),
          );
        },
      ),
      _buildFeatureCard(
        id: 'data_import',
        icon: Icons.download,
        title: '数据导入',
        subtitle: isWeb ? '从浏览器选择备份文件' : '从备份文件恢复或合并数据',
        onTap: () {
          Navigator.push(
            context,
            PageTransitions.slideHorizontal(
              DataImportPage(isEmbedded: widget.isEmbedded),
              settings: const RouteSettings(name: '数据导入'),
            ),
          );
        },
      ),
    ];

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('数据与互联'),
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0, left: 4.0),
              child: Text(isWeb ? '浏览器数据工具' : '设备互联向导',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            if (isWeb) ...[
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 16),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded,
                      color:
                          Theme.of(context).colorScheme.onSecondaryContainer),
                  title: const Text('浏览器沙盒限制'),
                  subtitle: const Text(
                    '局域网直连、系统日历写入和手环快应用同步需要原生系统权限；网页版可通过导出 ICS 文件导入系统日历。',
                  ),
                ),
              ),
            ],
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.95,
              children: featureCards,
            ),
          ],
        ),
      ),
    );
  }
}
