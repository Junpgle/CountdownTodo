import 'package:flutter/material.dart';
import '../../storage_service.dart';
import '../login_screen.dart';
import '../../utils/page_transitions.dart';

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
  static final DateTime _cloudflareDisableDate = DateTime(2026, 6, 1);
  static const String _cloudflareDisabledMessage =
      '该服务器将于2026/06/01禁用，请及时迁移到阿里云服务器';

  bool get _isCloudflareDisabled =>
      !DateTime.now().isBefore(_cloudflareDisableDate);

  @override
  void initState() {
    super.initState();
    _selectedServer = widget.initialServerChoice;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(
        title: const Text('云端数据接口线路'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_queue,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '选择服务器',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '切换服务器后需要重新登录，且不同服务器的登录状态不互通',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildServerOption(
                    value: 'cloudflare',
                    title: 'Cloudflare（即将禁用）',
                    subtitle: _isCloudflareDisabled
                        ? '已禁用，请使用阿里云ECS'
                        : '2026/06/01 前仍可登录使用',
                    icon: Icons.shield_outlined,
                  ),
                  const SizedBox(height: 10),
                  _buildCloudflareWarning(),
                  const SizedBox(height: 8),
                  _buildServerOption(
                    value: 'aliyun',
                    title: '阿里云ECS',
                    subtitle: '更快',
                    icon: Icons.speed_outlined,
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
              onPressed: () => _handleServerChange(),
              icon: const Icon(Icons.save),
              label: const Text('保存设置'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudflareWarning() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.red.shade700, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cloudflare 服务器将于 2026/06/01 禁用',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '由于开发精力有限，后续将不再同时维护 Cloudflare 与阿里云两套 API 服务。当前及未来的新功能都会优先基于阿里云服务器开发与适配，因此 Cloudflare 线路可能出现不稳定、功能缺失或无法正常使用的情况。',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.78),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '为保证应用体验和代码维护质量，后续版本将逐步移除 App 中与 Cloudflare 服务器相关的旧逻辑。建议尽快迁移并使用阿里云服务器。',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedServer == value;
    final isCloudflare = value == 'cloudflare';
    final isDisabled = isCloudflare && _isCloudflareDisabled;
    final baseColor = isDisabled ? Colors.grey[400] : Colors.grey[600];
    return InkWell(
      onTap: () {
        if (isCloudflare) {
          _showCloudflareNotice();
          if (isDisabled) return;
        }
        setState(() => _selectedServer = value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : baseColor,
            ),
            const SizedBox(width: 12),
            Icon(icon,
                size: 24,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : baseColor),
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
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : (isCloudflare ? Colors.grey[600] : Colors.black87),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isCloudflare ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _handleServerChange() async {
    if (_selectedServer == 'cloudflare') {
      _showCloudflareNotice();
      if (_isCloudflareDisabled) return;
    }

    if (_selectedServer == widget.initialServerChoice) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换服务器'),
        content: const Text('不同服务器的登录凭证不互通，切换后需要重新登录。\n\n确定要切换吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('切换并重新登录')),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await StorageService.saveServerChoice(_selectedServer);
      await StorageService.clearLoginSession();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          PageTransitions.fadeThrough(const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  void _showCloudflareNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(_cloudflareDisabledMessage)),
    );
  }
}
