import 'package:flutter/material.dart';

import '../../../utils/page_transitions.dart';
import '../../band_sync_screen.dart';
import '../lan_sync_screen.dart';
import '../calendar_sync_page.dart';
import '../batch_tag_page.dart';

class InterconnectSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  final String username;
  const InterconnectSettingsPage({super.key, this.initialTarget, this.isEmbedded = false, required this.username});

  @override
  State<InterconnectSettingsPage> createState() => _InterconnectSettingsPageState();
}

class _InterconnectSettingsPageState extends State<InterconnectSettingsPage> {
  final Map<String, GlobalKey> _itemKeys = {
    'lan_sync': GlobalKey(),
    'band_sync': GlobalKey(),
    'calendar_sync': GlobalKey(),
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
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return _buildTile(
      targetId: id,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.05),
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
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(
        title: const Text('数据与互联'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16.0, left: 4.0),
              child: Text('设备互联向导', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.95,
              children: [
                _buildFeatureCard(
                  id: 'lan_sync',
                  icon: Icons.wifi_tethering,
                  title: '局域网同步',
                  subtitle: '同账号设备间无缝互传数据',
                  color: Colors.blue,
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
                  color: Colors.orange,
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
                  color: Colors.redAccent,
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
                _buildFeatureCard(
                  id: 'batch_tag',
                  icon: Icons.label_outlined,
                  title: '批量标签',
                  subtitle: '为番茄钟和时间日志批量添加标签',
                  color: Colors.teal,
                  onTap: () {
                    Navigator.push(
                      context,
                      PageTransitions.slideHorizontal(
                        BatchTagPage(username: widget.username),
                        settings: const RouteSettings(name: '批量添加标签'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
