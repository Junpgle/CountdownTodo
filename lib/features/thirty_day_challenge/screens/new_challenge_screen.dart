import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cloud_challenge.dart';
import '../models/thirty_day_challenge.dart';
import '../services/challenge_share_codec.dart';
import '../services/clipboard_share_detector.dart';
import '../services/challenge_text_parser.dart';
import 'cloud_challenge_picker_screen.dart';

class NewChallengeScreen extends StatefulWidget {
  final ChallengeDraft? initialDraft;

  const NewChallengeScreen({super.key, this.initialDraft});

  @override
  State<NewChallengeScreen> createState() => _NewChallengeScreenState();
}

class _NewChallengeScreenState extends State<NewChallengeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _tasksController = TextEditingController();
  bool _isImporting = false;

  List<String> get _taskTitles =>
      ChallengeTextParser.parseTaskTitles(_tasksController.text);

  @override
  void initState() {
    super.initState();
    final initialDraft = widget.initialDraft;
    if (initialDraft != null) {
      _titleController.text = initialDraft.title;
      _tasksController.text = initialDraft.taskTitles.join('\n');
    }
    _tasksController.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tasksController
      ..removeListener(_refreshPreview)
      ..dispose();
    super.dispose();
  }

  void _refreshPreview() => setState(() {});

  void _applyDraft(ChallengeDraft draft) {
    _titleController.text = draft.title;
    _tasksController.text = draft.taskTitles.join('\n');
    _tasksController.selection = TextSelection.collapsed(
      offset: _tasksController.text.length,
    );
  }

  Future<void> _shareChallenge() async {
    final title = _titleController.text.trim();
    final tasks = _taskTitles;
    if (title.isEmpty || tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写挑战名称和至少一项任务，再分享挑战')),
      );
      return;
    }

    try {
      final sharedText = ChallengeShareCodec.encode(
        ChallengeDraft(title: title, taskTitles: tasks),
      );
      await Clipboard.setData(
        ClipboardData(text: sharedText),
      );
      await ClipboardSharePayload.markLocallyGenerated(sharedText);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制分享内容，朋友可在新建挑战页点击“识别剪贴板”导入'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享内容复制失败，请稍后再试')),
      );
    }
  }

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;

    final sharedDraft = ChallengeShareCodec.tryDecode(text);
    if (sharedDraft != null) {
      _applyDraft(sharedDraft);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已识别并导入挑战「${sharedDraft.title}」')),
      );
      return;
    }

    _tasksController.text = text;
    _tasksController.selection = TextSelection.collapsed(
      offset: _tasksController.text.length,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已从剪贴板粘贴任务清单')),
    );
  }

  Future<void> _importTextFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'csv', 'json'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;

      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('文件内容为空或当前平台无法读取文件');
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final sharedDraft = ChallengeShareCodec.tryDecode(text);
      if (sharedDraft != null) {
        _applyDraft(sharedDraft);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入挑战「${sharedDraft.title}」')),
        );
      } else {
        _tasksController.text = text;
        _tasksController.selection = TextSelection.collapsed(
          offset: _tasksController.text.length,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${_taskTitles.length} 项任务')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文本导入失败，请选择 UTF-8 编码的文本文件')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _openCloudChallenges() async {
    final result = await Navigator.of(context).push<CloudChallengePickerResult>(
      MaterialPageRoute(builder: (_) => const CloudChallengePickerScreen()),
    );
    final selected = result?.challenge;
    if (selected == null || !mounted) return;

    _applyDraft(selected.toDraft());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已填入云端挑战「${selected.title}」')),
    );
  }

  void _createChallenge() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final titles = _taskTitles;
    if (titles.isEmpty) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(
      ChallengeDraft(
        title: _titleController.text.trim(),
        taskTitles: titles,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final taskTitles = _taskTitles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新建打卡挑战'),
        actions: [
          IconButton(
            tooltip: '分享挑战',
            onPressed: _isImporting ? null : _shareChallenge,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          TextButton(
            onPressed: _isImporting ? null : _createChallenge,
            child: const Text('开始挑战'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                '把任何想完成的事情做成一场自己的挑战',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '输入或导入任务清单，每一行就是一项任务。任务数量和内容都不受 30 项限制。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _isImporting ? null : _openCloudChallenges,
                icon: const Icon(Icons.cloud_download_rounded),
                label: const Text('从 GitHub 获取云端挑战'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '挑战名称',
                  hintText: '例如：我的阅读挑战',
                  prefixIcon: Icon(Icons.title_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.trim().isEmpty == true ? '请给这场挑战起个名字' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tasksController,
                minLines: 10,
                maxLines: 18,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: '任务清单（每行一项）',
                  hintText: '读完一本书\n跑步 3 公里\n给朋友写一封信',
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 150),
                    child: Icon(Icons.format_list_bulleted_rounded),
                  ),
                  suffixIcon: IconButton(
                    tooltip: '清空',
                    onPressed: _tasksController.text.isEmpty
                        ? null
                        : _tasksController.clear,
                    icon: const Icon(Icons.clear_rounded),
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (_) => taskTitles.isEmpty ? '至少输入一行任务' : null,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _pasteText,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('识别剪贴板'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _importTextFile,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_rounded),
                    label: Text(_isImporting ? '导入中…' : '导入挑战文件'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _shareChallenge,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('分享挑战'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '分享内容会自动识别标题和任务；普通文本仍会按行导入。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: scheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.preview_rounded, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '任务预览 · ${taskTitles.length} 项',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      if (taskTitles.isEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          '还没有任务，输入内容后会在这里预览。',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        ...taskTitles.take(6).toList().asMap().entries.map(
                              (entry) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${entry.key + 1}.',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(entry.value)),
                                  ],
                                ),
                              ),
                            ),
                        if (taskTitles.length > 6)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '还有 ${taskTitles.length - 6} 项任务…',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isImporting ? null : _createChallenge,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('创建并开始'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
