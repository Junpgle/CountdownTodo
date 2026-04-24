import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

class PrivacyPolicyDialog extends StatefulWidget {
  final bool isUpdate;
  final VoidCallback onAgree;
  final VoidCallback onDisagree;
  final String? content;

  const PrivacyPolicyDialog({
    super.key,
    this.isUpdate = false,
    required this.onAgree,
    required this.onDisagree,
    this.content,
  });

  @override
  State<PrivacyPolicyDialog> createState() => _PrivacyPolicyDialogState();
}

class _PrivacyPolicyDialogState extends State<PrivacyPolicyDialog> {
  String? _content;
  bool _isLoading = true;

  static const String PRIVACY_RAW_URL =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';

  @override
  void initState() {
    super.initState();
    if (widget.content != null) {
      _content = widget.content;
      _isLoading = false;
    } else {
      _fetchContent();
    }
  }

  Future<void> _fetchContent() async {
    try {
      final response = await http.get(Uri.parse(PRIVACY_RAW_URL));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _content = response.body;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('获取隐私政策失败: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDisagree(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认不同意'),
        content: const Text(
          '不同意隐私政策将导致以下后果：\n\n'
          '• 退出当前账号\n'
          '• 清除本地所有数据（包括待办、倒计时、番茄钟记录等）\n'
          '• 无法使用数据同步等云端功能\n\n'
          '已收集的个人信息将在合理期限内删除或匿名化处理。\n\n'
          '是否确认？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      widget.onDisagree();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isUpdate ? '隐私政策已更新' : '隐私政策与用户协议'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isUpdate) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '我们更新了隐私政策，请仔细阅读后继续同意。',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _content == null
                      ? const Center(child: Text('加载失败，请检查网络连接'))
                      : Markdown(
                          data: _content!,
                          padding: EdgeInsets.zero,
                          styleSheet: MarkdownStyleSheet(
                            h1: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                            h2: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                            h3: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                            p: const TextStyle(fontSize: 13, height: 1.5),
                            listBullet: const TextStyle(fontSize: 13),
                            blockquote: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                            code: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace'),
                            codeblockDecoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            tableHead: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                            tableBody: const TextStyle(fontSize: 13),
                          ),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _handleDisagree(context),
          child: const Text('不同意'),
        ),
        FilledButton(
          onPressed: widget.onAgree,
          child: Text(widget.isUpdate ? '我已阅读并同意' : '同意并继续'),
        ),
      ],
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
