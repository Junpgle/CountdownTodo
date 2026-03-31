import 'package:flutter/material.dart';
import '../../storage_service.dart';
import '../login_screen.dart';

class ServerChoicePage extends StatefulWidget {
  final String initialServerChoice;

  const ServerChoicePage({
    super.key,
    required this.initialServerChoice,
  });

  @override
  State<ServerChoicePage> createState() => _ServerChoicePageState();
}

class _ServerChoicePageState extends State<ServerChoicePage> {
  late String _selectedServer;

  @override
  void initState() {
    super.initState();
    _selectedServer = widget.initialServerChoice;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
                    title: 'Cloudflare',
                    subtitle: '更安全',
                    icon: Icons.shield_outlined,
                  ),
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

  Widget _buildServerOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedServer == value;
    return InkWell(
      onTap: () {
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
            Radio<String>(
              value: value,
              groupValue: _selectedServer,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedServer = val);
                }
              },
            ),
            Icon(icon,
                size: 24,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[600]),
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
                          : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
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
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
