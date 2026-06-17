import 'package:flutter/material.dart';

import '../../../utils/page_transitions.dart';
import '../../band_sync_screen.dart';
import '../lan_sync_screen.dart';

class InterconnectSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const InterconnectSettingsPage({super.key, this.initialTarget, this.isEmbedded = false});

  @override
  State<InterconnectSettingsPage> createState() => _InterconnectSettingsPageState();
}

class _InterconnectSettingsPageState extends State<InterconnectSettingsPage> {
  final Map<String, GlobalKey> _itemKeys = {
    'lan_sync': GlobalKey(),
    'band_sync': GlobalKey(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(
        title: const Text('设备互联'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          _buildTile(
            targetId: 'lan_sync',
            child: ListTile(
              leading: const Icon(Icons.wifi_tethering, color: Colors.blue),
              title: const Text('局域网同步'),
              subtitle: const Text('同账号设备间局域网同步数据'),
              trailing: const Icon(Icons.chevron_right),
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
          ),
          const Divider(height: 1, indent: 56),
          _buildTile(
            targetId: 'band_sync',
            child: ListTile(
              leading: const Icon(Icons.watch_outlined, color: Colors.orange),
              title: const Text('小米手环互联'),
              subtitle: const Text('使用快应用将待办同步至小米手环'),
              trailing: const Icon(Icons.chevron_right),
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
          ),
        ],
      ),
    );
  }
}
