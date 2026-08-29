import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/floating_glass_control.dart';
import '../models/finance_models.dart';
import '../services/finance_text_parser.dart';
import 'finance_entry_screen.dart';

/// Clipboard/text import for bills. It produces drafts and always hands them
/// to the regular editor instead of writing directly to the database.
class FinanceTextRecognitionScreen extends StatefulWidget {
  const FinanceTextRecognitionScreen({super.key});

  @override
  State<FinanceTextRecognitionScreen> createState() =>
      _FinanceTextRecognitionScreenState();
}

class _FinanceTextRecognitionScreenState
    extends State<FinanceTextRecognitionScreen> {
  final _controller = TextEditingController();
  bool _isRecognizing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    setState(() => _controller.text = text);
  }

  void _useExample() {
    setState(() {
      _controller.text = '''#记账
类型: 支出
金额: 28.50
分类: 餐饮
商家: 午餐
日期: ${dateKey(DateTime.now())}
付款方式: 微信
备注: 工作日午餐''';
    });
  }

  Future<void> _recognize() async {
    if (_isRecognizing) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showMessage('请先输入或粘贴账单文本');
      return;
    }
    final drafts = FinanceTextParser.parse(
      text,
      source: FinanceEntrySource.import,
    );
    if (drafts.isEmpty) {
      _showMessage('没有识别到完整账单，请检查金额和类型');
      return;
    }

    setState(() => _isRecognizing = true);
    var savedCount = 0;
    for (final draft in drafts) {
      if (!mounted) return;
      final result = await Navigator.of(context).push<FinanceTransaction>(
        MaterialPageRoute(
          builder: (_) => FinanceEntryScreen(initialDraft: draft),
        ),
      );
      if (result != null) savedCount++;
    }
    if (!mounted) return;
    setState(() => _isRecognizing = false);
    if (savedCount > 0) {
      _showMessage('已保存 $savedCount 笔账单');
      Navigator.of(context).pop();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: FloatingGlassAppBar(
        flexibleSpace: const FloatingGlassTopBarBackground(),
        title: const Text('文本识别记账'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          color: colorScheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '粘贴账单，识别后逐笔编辑',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: _useExample,
                        child: const Text('填入示例'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    FinanceTextParser.formatHelp,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            minLines: 10,
            maxLines: 18,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: '#记账\n类型: 支出\n金额: 12.50\n分类: 餐饮',
              alignLabelWithHint: true,
              labelText: '账单文本',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '从剪贴板粘贴',
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isRecognizing ? null : _recognize,
            icon: _isRecognizing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_isRecognizing ? '正在打开编辑器...' : '识别并编辑'),
          ),
        ],
      ),
    );
  }
}
