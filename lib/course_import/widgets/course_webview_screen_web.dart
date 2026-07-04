import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CourseWebViewScreen extends StatelessWidget {
  final String initialUrl;

  const CourseWebViewScreen({
    super.key,
    this.initialUrl = 'https://www.bing.com',
  });

  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.tryParse(initialUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('网页导入')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.public_rounded,
                  size: 48,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Flutter Web 无法嵌入原生 WebView',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '请在浏览器打开教务页面，导出 HTML/MHTML/JSON/ICS 后回到课表导入选择文件。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _openInBrowser(context),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('在浏览器打开'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
